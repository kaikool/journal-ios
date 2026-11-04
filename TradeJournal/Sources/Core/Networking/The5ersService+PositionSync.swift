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
    
    internal struct SourcePosition {
        var identityDiscriminator: String?
        let providerId: String?
        let symbol: String
        let direction: TradeDirection
        let openedAtIso: String
        let openedAtDate: Date
        let closedAtIso: String?
        let closedAtDate: Date?
        let quantity: Decimal
        let entry: Decimal
        let exit: Decimal?
        let netPnl: Decimal
        let fee: Decimal?
        let swap: Decimal?
        let isValid: Bool?
    }
    
    /// Sanitizes dictionary keys by removing whitespaces, underscores, and hyphens
    internal func sourceFields(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in dict {
            let cleanKey = key.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            result[cleanKey] = val
        }
        return result
    }
    
    internal func sourceNumber(_ val: Any?) -> Decimal? {
        guard let val = val else { return nil }
        if let num = val as? NSNumber {
            return Decimal(string: num.stringValue)
        }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces)
        return Decimal(string: str)
    }
    
    internal func sourceBoolean(_ val: Any?) -> Bool? {
        guard let val = val else { return nil }
        if let b = val as? Bool { return b }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces).lowercased()
        if ["yes", "true", "1"].contains(str) { return true }
        if ["no", "false", "0"].contains(str) { return false }
        return nil
    }
    
    internal func sourceInstant(_ val: Any?) -> (iso: String, date: Date)? {
        guard let val = val else { return nil }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces)
        guard let date = FlexibleDateParser.parse(str) else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (fmt.string(from: date), date)
    }
    
    internal func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
        for k in keys {
            if let val = dict[k] {
                return val
            }
        }
        return nil
    }
    
    /// Normalizes raw position record into SourcePosition model
    internal func normalizePosition(from raw: [String: Any]) -> SourcePosition? {
        let row = sourceFields(raw)
        
        let rawSymbol = row["symbol"]
        let symbol = String(describing: rawSymbol ?? "").trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty && symbol.count <= 100 else { return nil }
        
        let sideVal = row["side"] ?? row["direction"]
        let sideStr = String(describing: sideVal ?? "").lowercased()
        let direction: TradeDirection? = {
            if sideStr.contains("buy") || sideStr == "long" { return .long }
            if sideStr.contains("sell") || sideStr == "short" { return .short }
            return nil
        }()
        guard let dir = direction else { return nil }
        
        let openKeys = ["opendate", "openedat", "opentime", "open_date", "opendatetime", "time", "timestamp", "datetime"]
        let openVal = firstValue(in: row, keys: openKeys)
        guard let (openedAtIso, openedAtDate) = sourceInstant(openVal) else {
            return nil
        }
        
        let qtyKeys = ["quantity", "lots", "volume", "size", "units"]
        let qtyVal = firstValue(in: row, keys: qtyKeys)
        guard let quantity = sourceNumber(qtyVal), quantity > 0 else {
            return nil
        }
        
        let entryKeys = ["entry", "openprice", "entryprice", "open_price", "price"]
        let entryVal = firstValue(in: row, keys: entryKeys)
        guard let entry = sourceNumber(entryVal) else {
            return nil
        }
        
        // Robust closed status: boolean flag, status token, presence of close date, exit price, or realized P&L
        let explicitClosedFlag = sourceBoolean(firstValue(in: row, keys: ["isclosed", "closed", "isclose"]))
        let st = String(describing: row["status"] ?? "").lowercased()
        let closeKeys = [
            "closedate", "closedat", "closetime", "close_date", "close_time",
            "closedatetime", "exittime", "exit_time", "exitdate", "timeclose",
            "time_close", "outtime", "out_time"
        ]
        let closeVal = firstValue(in: row, keys: closeKeys)
        let parsedCloseInstant = sourceInstant(closeVal)
        
        let exitKeys = [
            "exit", "closeprice", "exitprice", "close_price", "exit_price",
            "closedprice", "outprice", "out_price"
        ]
        let rawExitNum = sourceNumber(firstValue(in: row, keys: exitKeys))
        let hasExitPrice = (rawExitNum != nil && rawExitNum != 0)
        
        let pnlKeys = [
            "profitandloss", "profit_and_loss", "netpnl", "net_pnl", "realizedpnl",
            "realized_pnl", "net", "profit", "pnl"
        ]
        let rawPnlNum = sourceNumber(firstValue(in: row, keys: pnlKeys))
        
        // Generic Ghost / Dangling Position Detection:
        // A ghost position is NOT an open position.
        // A live open position has NO close date (parsedCloseInstant == nil).
        // A bridge-stuck ghost position was opened > 24 hours ago AND has a close timestamp recorded (e.g. scalp deal artifact).
        let isGhostDangling: Bool = {
            guard openedAtDate.timeIntervalSinceNow < -86400 else { return false }
            guard let cl = parsedCloseInstant else { return false }
            return abs(openedAtDate.timeIntervalSince(cl.date)) <= 10 || cl.date >= openedAtDate
        }()
        
        let isClosed: Bool = {
            // Rule 1: Explicitly closed flags from broker
            if explicitClosedFlag == true { return true }
            if st.contains("close") || st == "filled" || st == "done" || st.contains("exit") || st.contains("history") { return true }
            
            // Rule 2: Detected ghost position (has close timestamp from past)
            if isGhostDangling { return true }
            
            // Rule 3: If flagged open or status says open/active, it is genuinely an OPEN trade!
            if explicitClosedFlag == false || st.contains("open") || st == "active" {
                return false
            }
            
            // Rule 4: Neutral record fallback requires both a close timestamp and exit price
            if let cl = parsedCloseInstant, cl.date > openedAtDate, hasExitPrice {
                return true
            }
            return false
        }()
        
        let closedAtTuple: (iso: String, date: Date)?
        let exit: Decimal?
        let netPnl: Decimal
        
        if isClosed {
            if let cl = parsedCloseInstant {
                closedAtTuple = cl.date >= openedAtDate ? cl : (openedAtIso, openedAtDate)
            } else {
                closedAtTuple = (openedAtIso, openedAtDate.addingTimeInterval(120))
            }
            exit = rawExitNum ?? entry
            netPnl = rawPnlNum ?? 0
        } else {
            closedAtTuple = nil
            exit = nil
            netPnl = 0
        }
        
        // Never use ephemeral session-scoped 'ref' ('position-1', 'position-2') as providerId;
        // 'ref' rotates every 10 minutes per session and changes order across pages.
        let provKeys = ["positionid", "ticket", "id", "dealid", "orderid", "order_id"]
        let provVal = firstValue(in: row, keys: provKeys)
        let providerId: String? = {
            if let p = provVal {
                let s = String(describing: p).trimmingCharacters(in: .whitespaces)
                let sl = s.lowercased()
                if !s.isEmpty && !sl.contains("opaque") && !sl.hasPrefix("position-") && !sl.hasPrefix("account-") {
                    return s
                }
            }
            if let rawRef = row["ref"] as? String, rawRef.hasPrefix("pos_v1.") {
                let parts = rawRef.components(separatedBy: ".")
                if parts.count >= 2 {
                    var base64 = parts[1]
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    let remainder = base64.count % 4
                    if remainder > 0 {
                        base64.append(String(repeating: "=", count: 4 - remainder))
                    }
                    if let data = Data(base64Encoded: base64),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ticket = json["p"] {
                        let tStr = String(describing: ticket).trimmingCharacters(in: .whitespaces)
                        if !tStr.isEmpty && tStr != "0" {
                            return tStr
                        }
                    }
                }
            }
            return nil
        }()
        
        let feeVal = firstValue(in: row, keys: ["fee", "commission", "fees", "commissions", "totalfees", "brokerfee", "broker_fee", "orderfee", "order_fee", "cost", "costs", "comm"])
        var fee = sourceNumber(feeVal)
        let swapVal = firstValue(in: row, keys: ["swap", "swaps", "totalswap", "total_swap", "rollover", "financing", "interest", "overnight"])
        let swap = sourceNumber(swapVal)
        let isValid = sourceBoolean(row["isvalid"])
        
        return SourcePosition(
            identityDiscriminator: nil,
            providerId: providerId,
            symbol: symbol,
            direction: dir,
            openedAtIso: openedAtIso,
            openedAtDate: openedAtDate,
            closedAtIso: closedAtTuple?.iso,
            closedAtDate: closedAtTuple?.date,
            quantity: quantity,
            entry: entry,
            exit: exit,
            netPnl: netPnl,
            fee: fee,
            swap: swap,
            isValid: isValid
        )
    }
    
    /// Reconciles and merges remote positions from The5ers into local TradeDataStore
    @MainActor
    internal func mergePositions(
        _ rawPositions: [[String: Any]],
        for acc: The5ersMcpAccount,
        into dataStore: TradeDataStore,
        count: inout Int,
        replaceAccountPositions: Bool = false
    ) {
        let parsed = rawPositions.compactMap { normalizePosition(from: $0) }
        guard !parsed.isEmpty else { return }
        
        let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
        let targetAccId = dataStore.propAccounts.first(where: {
            TradeDataStore.isSameAccountId($0.id, journalAccId) ||
            $0.id == acc.id ||
            $0.name == acc.label
        })?.journalAccountId ?? journalAccId
        
        // Group duplicate positions to compute disambiguation discriminators (matching journal.ts:116-135)
        var groups: [String: [SourcePosition]] = [:]
        for p in parsed {
            let baseKey = JournalIds.positionIdentity(symbol: p.symbol, direction: p.direction.rawValue, openedAt: p.openedAtIso, discriminator: nil)
            groups[baseKey, default: []].append(p)
        }
        
        var valid: [SourcePosition] = []
        for (_, group) in groups {
            if group.count == 1, var item = group.first {
                // Keep identityDiscriminator = nil for unique (symbol, direction, openedAt) positions
                // so tradeKey remains 100% deterministic across sync sessions.
                item.identityDiscriminator = nil
                valid.append(item)
                continue
            }
            // Assign deterministic discriminator to distinguish identical concurrent positions
            let sortedGroup = group.sorted { lhs, rhs in
                if lhs.quantity != rhs.quantity { return lhs.quantity < rhs.quantity }
                if lhs.entry != rhs.entry { return lhs.entry < rhs.entry }
                return lhs.netPnl < rhs.netPnl
            }
            for (idxInGroup, p) in sortedGroup.enumerated() {
                var item = p
                let disc: String
                if let pid = p.providerId, !pid.isEmpty {
                    disc = "provider:\(pid)"
                } else {
                    disc = "entry:\(JournalIds.sha256Hex([p.quantity, p.entry, p.exit ?? 0, p.netPnl, idxInGroup]))"
                }
                item.identityDiscriminator = disc
                valid.append(item)
            }
        }
        
        let existingAccountTrades = dataStore.trades.filter {
            $0.accountId == targetAccId || TradeDataStore.isSameAccountId($0.accountId, targetAccId)
        }
        var nonAccountTrades: [Trade] = []
        if replaceAccountPositions {
            nonAccountTrades = dataStore.trades.filter {
                !($0.accountId == targetAccId || TradeDataStore.isSameAccountId($0.accountId, targetAccId))
            }
        }
        
        var syncedAccountTrades: [Trade] = []
        var usedExistingKeys = Set<String>()
        
        for position in valid {
            let posIdentity = JournalIds.positionIdentity(
                symbol: position.symbol,
                direction: position.direction.rawValue,
                openedAt: position.openedAtIso,
                discriminator: position.identityDiscriminator
            )
            let tradeKey = JournalIds.the5ersTradeKey(sourceAccountId: acc.id, positionIdentity: posIdentity)
            let legacyPosIdentity = JournalIds.positionIdentity(
                symbol: position.symbol,
                direction: position.direction.rawValue,
                openedAt: position.openedAtIso,
                discriminator: nil
            )
            let legacyTradeKey = JournalIds.the5ersTradeKey(sourceAccountId: acc.id, positionIdentity: legacyPosIdentity)
            
            let isClosed = position.closedAtDate != nil
            let rawNetProfit = position.netPnl
            let rawFee = abs(position.fee ?? 0)
            let rawSwap = position.swap ?? 0
            
            let accountCurrency = acc.currency.uppercased()
            let reportingCurrency = dataStore.currencyConversion.reportingCurrency.uppercased()
            let toReporting: (Decimal) -> Decimal = { amount in
                if accountCurrency == reportingCurrency { return amount }
                guard let converted = dataStore.currencyConversion.context.convert(
                    amount,
                    from: accountCurrency,
                    to: reportingCurrency
                ) else {
                    AppLogger.warning("No \(accountCurrency)->\(reportingCurrency) rate configured; The5ers amount \(amount) kept in \(accountCurrency).")
                    return amount
                }
                return converted
            }
            let netPnl = isClosed ? toReporting(rawNetProfit) : Decimal.zero
            let fees = isClosed ? toReporting(rawFee) : Decimal.zero
            let swap: Decimal? = position.swap != nil ? toReporting(rawSwap) : nil
            // Authoritative invariant from Execution.swift: netPnl == grossPnl - fees + swapAmount
            // Reverse costs for gross calculation: grossPnl = netPnl + fees - swapAmount
            let grossPnl = netPnl + fees - (swap ?? 0)
            
            let breakevenBand = JournalDefaultsEngine.breakevenThreshold(
                defaults: dataStore.defaults,
                entryPrice: position.entry,
                quantity: position.quantity,
                multiplier: AssetContractEngine.contractMultiplier(
                    for: position.symbol,
                    customMultipliers: dataStore.multipliers
                )
            )
            let status: TradeStatus = {
                if !isClosed { return .open }
                if abs(netPnl) <= max(breakevenBand, TradeReconstructionEngine.flatEpsilon) { return .breakeven }
                return netPnl > 0 ? .win : .loss
            }()
            
            let durationMs: Int64? = {
                guard isClosed, let closedDate = position.closedAtDate else { return nil }
                return Int64(closedDate.timeIntervalSince(position.openedAtDate) * 1000)
            }()
            
            let openSec = Int64(position.openedAtDate.timeIntervalSince1970)
            let existingMatch = existingAccountTrades.first(where: { candidate in
                guard !usedExistingKeys.contains(candidate.key) else { return false }
                if candidate.key == tradeKey || candidate.key == legacyTradeKey { return true }
                return candidate.symbol.uppercased() == position.symbol.uppercased() &&
                       candidate.direction == position.direction &&
                       abs(Int64(candidate.openedAt.timeIntervalSince1970) - openSec) <= 1 &&
                       abs(candidate.quantity - position.quantity) < 0.001 &&
                       abs(candidate.avgEntry - position.entry) < 0.0001
            })
            
            if var existing = existingMatch {
                usedExistingKeys.insert(existing.key)
                existing.key = tradeKey
                existing.accountId = targetAccId
                
                // Protect already-closed trades from regressing to open or wiping out exit & PnL:
                let incomingIsDefective = (position.exit == nil || position.exit == position.entry) && position.netPnl == 0
                let localIsComplete = existing.avgExit != nil && existing.avgExit != existing.avgEntry && existing.netPnl != 0
                let shouldPreserveComplete = localIsComplete && incomingIsDefective
                let shouldPreserveClosed = (existing.status != .open && existing.closedAt != nil) && !isClosed
                if !shouldPreserveClosed && !shouldPreserveComplete {
                    existing.status = status
                    existing.closedAt = position.closedAtDate
                    existing.openQuantity = isClosed ? 0 : position.quantity
                    existing.avgExit = position.exit
                    existing.grossPnl = grossPnl
                    existing.fees = fees
                    existing.swap = swap
                    existing.netPnl = netPnl
                    existing.durationMs = durationMs
                }
                if existing.notes?.hasPrefix("Position synced from The5ers Hub") == true {
                    existing.notes = nil
                }
                if let t = position.providerId, !t.isEmpty, !existing.executionIds.contains(t) {
                    existing.executionIds.append(t)
                    existing.executionCount = existing.executionIds.count
                }
                if existing.playbookId == nil || existing.playbookId?.isEmpty == true {
                    existing.playbookId = dataStore.defaultPlaybook?.id
                }
                syncedAccountTrades.append(existing)
                count += 1
            } else {
                let trade = Trade(
                    key: tradeKey,
                    accountId: targetAccId,
                    symbol: position.symbol,
                    direction: position.direction,
                    status: status,
                    openedAt: position.openedAtDate,
                    closedAt: position.closedAtDate,
                    quantity: position.quantity,
                    openQuantity: isClosed ? 0 : position.quantity,
                    avgEntry: position.entry,
                    avgExit: position.exit,
                    grossPnl: grossPnl,
                    fees: fees,
                    swap: swap,
                    netPnl: netPnl,
                    executionCount: position.providerId != nil ? 1 : 0,
                    executionIds: position.providerId.map { [$0] } ?? [],
                    durationMs: durationMs,
                    notes: nil,
                    tags: ["the5ers", acc.program.lowercased()],
                    playbookId: dataStore.defaultPlaybook?.id
                )
                syncedAccountTrades.append(trade)
                count += 1
            }
        }
        
        if replaceAccountPositions {
            dataStore.trades = nonAccountTrades + syncedAccountTrades
        } else {
            var updatedTrades = dataStore.trades
            for synced in syncedAccountTrades {
                var s = synced
                if s.playbookId == nil || s.playbookId?.isEmpty == true {
                    s.playbookId = dataStore.defaultPlaybook?.id
                }
                if let idx = updatedTrades.firstIndex(where: { $0.key == s.key }) {
                    if (s.playbookId == nil || s.playbookId?.isEmpty == true), let existingPb = updatedTrades[idx].playbookId, !existingPb.isEmpty {
                        s.playbookId = existingPb
                    }
                    updatedTrades[idx] = s
                } else {
                    updatedTrades.append(s)
                }
            }
            dataStore.trades = updatedTrades
        }
    }
}