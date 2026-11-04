import Foundation

// MARK: - The5ers Position Synchronization & Trade Reconciliation
extension The5ersService {
    /// Fetches and merges positions for a single account from `the5ers_positions.list`
    @MainActor
    internal func syncAccountPositions(
        for acc: The5ersMcpAccount,
        embeddedPositions: [[String: Any]],
        into dataStore: TradeDataStore,
        importedPositionsCount: inout Int
    ) async {
        lastStatus = "Syncing trades: \(acc.label)..."
        await Task.yield()
        
        let pageLimit = 100
        let posArgs: [String: Any] = [
            "operation": "list",
            "account_ref": acc.ref,
            "view": "all",
            "page": 1,
            "limit": pageLimit,
            "contract_version": "1.0",
            "request_context": ["timezone": "UTC", "locale": "en"]
        ]
        
        do {
            var activePosArgs = posArgs
            var posResult = try await callMcpTool(name: "the5ers_positions", arguments: posArgs)
            if let isErr = posResult["isError"] as? Bool, isErr {
                let fbArgs: [String: Any] = [
                    "operation": "list",
                    "account_ref": acc.ref,
                    "view": "all",
                    "contract_version": "1.0"
                ]
                if let fbRes = try? await callMcpTool(name: "the5ers_positions", arguments: fbArgs),
                   !(fbRes["isError"] as? Bool ?? false) {
                    posResult = fbRes
                    activePosArgs = fbArgs
                } else {
                    if !embeddedPositions.isEmpty {
                        mergePositions(embeddedPositions, for: acc, into: dataStore, count: &importedPositionsCount, replaceAccountPositions: true)
                    }
                    return
                }
            }
            let unwrappedPos = unwrapMcpToolResult(posResult)
            var allPositions = extractMcpCollection(unwrappedPos, collectionKey: "positions")
            if allPositions.isEmpty && !embeddedPositions.isEmpty {
                allPositions = embeddedPositions
            }
            
            var seenPageFingerprints = Set<String>()
            if !allPositions.isEmpty {
                let firstFp = allPositions.compactMap { row -> String? in
                    let f = sourceFields(row)
                    return "\(f["symbol"] ?? "")|\(f["opendate"] ?? "")|\(f["quantity"] ?? "")|\(f["entry"] ?? "")"
                }.sorted().joined(separator: ";")
                seenPageFingerprints.insert(firstFp)
            }
            
            let topDict = unwrappedPos as? [String: Any]
            let dataDict = topDict?["data"] as? [String: Any]
            let posPagination = (topDict?["pagination"] as? [String: Any]) ?? (dataDict?["pagination"] as? [String: Any])
            let totalReported = (posPagination?["total"] as? Int) ?? (posPagination?["total"] as? NSNumber)?.intValue
            let initialHasMore = (posPagination?["has_more"] as? Bool) ??
                                 (posPagination?["hasMore"] as? Bool) ??
                                 (totalReported.map { allPositions.count < $0 } ?? (allPositions.count >= pageLimit))
            
            if initialHasMore {
                var page = 2
                while page <= 500 {
                    if Task.isCancelled || isCancelledByUser { break }
                    var pArgs = activePosArgs
                    pArgs["page"] = page
                    
                    lastStatus = "Syncing trades: \(acc.label) (page \(page), \(allPositions.count) loaded)..."
                    await Task.yield()
                    
                    var nextRes: [String: Any]? = nil
                    for retry in 1...3 {
                        if let res = try? await callMcpTool(name: "the5ers_positions", arguments: pArgs),
                           !(res["isError"] as? Bool ?? false) {
                            nextRes = res
                            break
                        }
                        if retry < 3 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                    guard let validRes = nextRes else {
                        AppLogger.warning("The5ers positions: failed to fetch page \(page) for \(acc.label) after 3 retries, stopping.")
                        break
                    }
                    
                    let nextUnwrapped = unwrapMcpToolResult(validRes)
                    let nextPositions = extractMcpCollection(nextUnwrapped, collectionKey: "positions")
                    if nextPositions.isEmpty { break }
                    let nextFp = nextPositions.compactMap { row -> String? in
                        let f = sourceFields(row)
                        return "\(f["symbol"] ?? "")|\(f["opendate"] ?? "")|\(f["quantity"] ?? "")|\(f["entry"] ?? "")"
                    }.sorted().joined(separator: ";")
                    if seenPageFingerprints.contains(nextFp) { break }
                    seenPageFingerprints.insert(nextFp)
                    allPositions.append(contentsOf: nextPositions)
                    let nextTop = nextUnwrapped as? [String: Any]
                    let nextData = nextTop?["data"] as? [String: Any]
                    let nextPag = (nextTop?["pagination"] as? [String: Any]) ?? (nextData?["pagination"] as? [String: Any])
                    let nextTotal = (nextPag?["total"] as? Int) ?? (nextPag?["total"] as? NSNumber)?.intValue ?? totalReported
                    let hasMore = (nextPag?["has_more"] as? Bool) ??
                                  (nextPag?["hasMore"] as? Bool) ??
                                  (nextTotal.map { allPositions.count < $0 } ?? (nextPositions.count >= pageLimit))
                    if !hasMore { break }
                    page += 1
                }
            }
            
            let resolvedPositions = await enrichIncompletePositionsIfNeeded(allPositions)
            mergePositions(resolvedPositions, for: acc, into: dataStore, count: &importedPositionsCount, replaceAccountPositions: true)
        } catch {
            if !embeddedPositions.isEmpty {
                let resolvedEmbedded = await enrichIncompletePositionsIfNeeded(embeddedPositions)
                mergePositions(resolvedEmbedded, for: acc, into: dataStore, count: &importedPositionsCount, replaceAccountPositions: false)
            }
            AppLogger.error("Error syncing trades for account \(acc.label) (\(acc.id)): \(error.localizedDescription)")
        }
    }
    
    /// Drills into any incomplete / bridge-stuck position rows using `the5ers_positions.detail` or `the5ers_positions.trades`
    @MainActor
    internal func enrichIncompletePositionsIfNeeded(_ positions: [[String: Any]]) async -> [[String: Any]] {
        var resolved: [[String: Any]] = []
        
        let exitKeys = ["exit", "closeprice", "exitprice", "close_price", "exit_price", "closedprice", "outprice", "out_price"]
        let pnlKeys = ["profitandloss", "profit_and_loss", "netpnl", "net_pnl", "realizedpnl", "realized_pnl", "net", "profit", "pnl"]
        let entryKeys = ["entry", "openprice", "entryprice", "open_price", "entry_price", "priceopen", "price_open", "inprice", "in_price", "price"]
        let closeKeys = ["closedate", "closedat", "closetime", "close_date", "close_time", "closedatetime", "exittime", "exit_time", "exitdate", "timeclose", "time_close", "outtime", "out_time"]
        
        for row in positions {
            if Task.isCancelled || isCancelledByUser {
                resolved.append(row)
                continue
            }
            
            var enriched = row
            guard let posRef = (row["position_ref"] as? String) ?? (row["ref"] as? String), !posRef.isEmpty else {
                resolved.append(row)
                continue
            }
            
            let rawExit = sourceNumber(firstValue(in: row, keys: exitKeys))
            let rawPnl = sourceNumber(firstValue(in: row, keys: pnlKeys))
            let entry = sourceNumber(firstValue(in: row, keys: entryKeys))
            let hasCloseDate = firstValue(in: row, keys: closeKeys) != nil
            let isClosedFlag = sourceBoolean(firstValue(in: row, keys: ["isclosed", "closed", "isclose"]))
            let st = String(describing: row["status"] ?? "").lowercased()
            
            // Active open positions MUST remain open — never attempt to drill into them as incomplete closed trades:
            let isExplicitlyOpen = (isClosedFlag == false) || st.contains("open") || st == "active"
            if isExplicitlyOpen {
                resolved.append(row)
                continue
            }
            
            let isClosed = (isClosedFlag == true) || hasCloseDate || st.contains("close") || st == "filled" || st == "done"
            let isIncomplete = isClosed && ((rawExit == nil || rawExit == entry) || (rawPnl == nil || rawPnl == 0))
            
            guard isIncomplete else {
                resolved.append(row)
                continue
            }
            
            // 1. Drill into position detail: operation 'detail'
            let detailArgs: [String: Any] = [
                "operation": "detail",
                "position_ref": posRef,
                "contract_version": "1.0",
                "request_context": ["timezone": "UTC", "locale": "en"]
            ]
            
            var detailSucceeded = false
            if let detailRes = try? await callMcpTool(name: "the5ers_positions", arguments: detailArgs),
               !(detailRes["isError"] as? Bool ?? false) {
                let unwrapped = unwrapMcpToolResult(detailRes)
                let detailDict: [String: Any]? = {
                    if let top = unwrapped as? [String: Any] {
                        if let d = top["data"] as? [String: Any] { return d }
                        return top
                    }
                    return nil
                }()
                
                if let dict = detailDict {
                    for (k, v) in dict {
                        let lk = k.lowercased()
                        if lk == "exit" || lk == "closeprice" || lk == "profitandloss" || lk == "fee" || lk == "swap" || lk == "closedate" {
                            enriched[k] = v
                        } else if enriched[k] == nil {
                            enriched[k] = v
                        }
                    }
                    let resExit = sourceNumber(firstValue(in: enriched, keys: exitKeys))
                    let resPnl = sourceNumber(firstValue(in: enriched, keys: pnlKeys))
                    if resExit != nil && resExit != entry && resPnl != nil && resPnl != 0 {
                        detailSucceeded = true
                    }
                }
            }
            
            // 2. If detail still lacks exit or PnL, drill into underlying fills: operation 'trades'
            if !detailSucceeded {
                let tradesArgs: [String: Any] = [
                    "operation": "trades",
                    "position_ref": posRef,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                if let tradesRes = try? await callMcpTool(name: "the5ers_positions", arguments: tradesArgs),
                   !(tradesRes["isError"] as? Bool ?? false) {
                    let unwrapped = unwrapMcpToolResult(tradesRes)
                    let fills = extractMcpCollection(unwrapped, collectionKey: "trades")
                    if !fills.isEmpty {
                        var closingDeal = fills.last
                        for fill in fills {
                            if let pnl = sourceNumber(firstValue(in: fill, keys: pnlKeys)), pnl != 0 {
                                closingDeal = fill
                                break
                            }
                        }
                        if let closeFill = closingDeal {
                            if let p = sourceNumber(firstValue(in: closeFill, keys: ["price", "exit", "closeprice"])) {
                                enriched["exit"] = p
                            }
                            if let pnl = sourceNumber(firstValue(in: closeFill, keys: pnlKeys)) {
                                enriched["profitAndLoss"] = pnl
                            }
                            if let d = firstValue(in: closeFill, keys: ["date", "time", "closedate"]) {
                                enriched["closeDate"] = d
                            }
                            let totalFees = fills.compactMap { sourceNumber(firstValue(in: $0, keys: ["fee", "commission"])) }.reduce(0, +)
                            if totalFees > 0 {
                                enriched["fee"] = totalFees
                            }
                        }
                    }
                }
            }
            
            resolved.append(enriched)
        }
        
        return resolved
    }
    
    /// Reconciles account-level statistics (`totalFees`, `tradingDays`, `winningDays`, `totalTrades`) and verifies closed trade P&L against authoritative account balance
    @MainActor
    internal func reconcileAccountTradesWithMcp(for acc: The5ersMcpAccount, into dataStore: TradeDataStore) async {
        let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
        let targetAccId = dataStore.propAccounts.first(where: {
            TradeDataStore.isSameAccountId($0.id, journalAccId) ||
            $0.id == acc.id ||
            $0.name == acc.label
        })?.journalAccountId ?? journalAccId
        
        let accountCurrency = acc.currency.uppercased()
        let reportingCurrency = dataStore.currencyConversion.reportingCurrency.uppercased()
        let toReporting: (Decimal) -> Decimal = { amount in
            if accountCurrency == reportingCurrency { return amount }
            return dataStore.currencyConversion.context.convert(amount, from: accountCurrency, to: reportingCurrency) ?? amount
        }
        
        let authTotalFees: Decimal = toReporting(abs(acc.totalFees ?? 0))
        
        // Remove any legacy synthetic "ACCOUNT" trades for this account
        var localTrades = dataStore.trades
        let beforePurge = localTrades.count
        localTrades.removeAll { t in
            (t.accountId == targetAccId || TradeDataStore.isSameAccountId(t.accountId, targetAccId)) &&
            (t.symbol == "ACCOUNT" || t.key.contains("_midnight_") || t.key.hasSuffix("_summary"))
        }
        var tradesModified = (localTrades.count != beforePurge)
        
        let closedIndices = localTrades.indices.filter { idx in
            let t = localTrades[idx]
            return (t.accountId == targetAccId || TradeDataStore.isSameAccountId(t.accountId, targetAccId)) &&
                   t.status != .open && t.closedAt != nil
        }
        
        // 1. Only if individual positions omitted fee (sum == 0) while `account.statistics.totalFees` reported non-zero fees,
        // distribute authoritative `totalFees` across closed trades by quantity (never modifying `netPnl` per docs/the5ers.md:24).
        if !closedIndices.isEmpty {
            let currentFeeSum = closedIndices.reduce(Decimal.zero) { $0 + localTrades[$1].fees }
            if currentFeeSum == 0 && authTotalFees > 0.01 {
                let totalQty = closedIndices.reduce(Decimal.zero) { $0 + max(localTrades[$1].quantity, 0.01) }
                var allocatedFees = Decimal.zero
                for (pos, idx) in closedIndices.enumerated() {
                    let share: Decimal
                    if pos == closedIndices.count - 1 {
                        share = max(0, authTotalFees - allocatedFees)
                    } else {
                        let weight = max(localTrades[idx].quantity, 0.01) / (totalQty > 0 ? totalQty : Decimal(closedIndices.count))
                        var rawShare = authTotalFees * weight
                        var rounded = Decimal.zero
                        NSDecimalRound(&rounded, &rawShare, 2, .plain)
                        share = rounded
                        allocatedFees += share
                    }
                    localTrades[idx].fees = share
                    localTrades[idx].grossPnl = localTrades[idx].netPnl + share - (localTrades[idx].swap ?? 0)
                }
                tradesModified = true
            }
        }
        
        if tradesModified {
            dataStore.trades = localTrades
        }
        
        // Reconcile tradingDays, winningDays, totalTrades, totalFeesMinor, and netPnlMinor on PropAccountItem from closed trades if missing from MCP
        var dailyNetMap: [String: Decimal] = [:]
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = TimeZone(secondsFromGMT: 0)
        for idx in closedIndices {
            let t = localTrades[idx]
            let dayKey = dayFmt.string(from: t.closedAt ?? t.openedAt)
            dailyNetMap[dayKey, default: .zero] += t.netPnl
        }
        let computedTradingDays = dailyNetMap.count
        let computedWinningDays = dailyNetMap.values.filter { $0 > 0 }.count
        let computedNetPnl = closedIndices.reduce(Decimal.zero) { $0 + localTrades[$1].netPnl }
        let computedFees = closedIndices.reduce(Decimal.zero) { $0 + localTrades[$1].fees }
        
        if let pIdx = dataStore.propAccounts.firstIndex(where: {
            TradeDataStore.isSameAccountId($0.id, journalAccId) || $0.journalAccountId == targetAccId
        }) {
            var p = dataStore.propAccounts[pIdx]
            var pChanged = false
            if p.currentTradingDays == nil || (p.currentTradingDays == 0 && computedTradingDays > 0) {
                p.currentTradingDays = computedTradingDays
                pChanged = true
            }
            if p.winningDays == nil || (p.winningDays == 0 && computedWinningDays > 0) {
                p.winningDays = computedWinningDays
                pChanged = true
            }
            if p.totalTrades == nil && !closedIndices.isEmpty {
                p.totalTrades = closedIndices.count
                pChanged = true
            }
            if p.totalFeesMinor == nil && computedFees > 0 {
                p.totalFeesMinor = NSDecimalNumber(decimal: abs(computedFees) * 100).int64Value
                pChanged = true
            }
            if !closedIndices.isEmpty {
                let computedNetMinor = NSDecimalNumber(decimal: computedNetPnl * 100).int64Value
                if p.netPnlMinor != computedNetMinor {
                    p.netPnlMinor = computedNetMinor
                    pChanged = true
                }
            } else if p.netPnlMinor == nil {
                if let bal = p.balanceMinor, let sz = p.sizeMinor, sz > 0 {
                    p.netPnlMinor = bal - sz
                    pChanged = true
                }
            }
            if pChanged {
                dataStore.propAccounts[pIdx] = p
            }
        }
    }
}
