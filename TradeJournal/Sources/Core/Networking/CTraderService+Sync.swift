import Foundation

// MARK: - cTrader Auto-Registration & Synchronization with TradeDataStore
extension CTraderService {
    
    /// Registers discovered cTrader accounts directly into TradeDataStore so they immediately appear
    /// in the ShellHeaderView account dropdown, AccountsManagerView, and all journal filtering views.
    @discardableResult
    public func registerDiscoveredAccounts(into dataStore: TradeDataStore) -> [Account] {
        guard !discoveredAccounts.isEmpty else { return [] }
        
        var registered: [Account] = []
        var hasChanges = false
        
        for account in discoveredAccounts {
            let journalAccId = "ctrader_\(account.ctidTraderAccountId)"
            let brokerName = account.brokerTitleShort.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeBroker = brokerName.isEmpty ? "cTrader" : brokerName
            let envLabel = account.isLive ? "Live" : "Demo"
            let accountName = "\(safeBroker) #\(account.traderLogin) (\(envLabel))"
            
            if let existingIdx = dataStore.accounts.firstIndex(where: {
                $0.id == journalAccId ||
                $0.id.isEquivalentAccountId(to: journalAccId) ||
                $0.id.cleanAccountId == String(account.ctidTraderAccountId) ||
                $0.id.cleanAccountId == String(account.traderLogin) ||
                $0.name.contains("\(account.traderLogin)")
            }) {
                var acc = dataStore.accounts[existingIdx]
                acc.name = accountName
                acc.broker = safeBroker
                if acc.currency.uppercased() == "USD" && (account.currency == "SEK" || account.currency == "SGD") {
                    // Retain user's configured USD currency
                } else if !account.currency.isEmpty {
                    acc.currency = account.currency
                }
                acc.kind = .sync
                acc.autoSync = true
                if acc.initialBalance == 0 && account.balance > 0 {
                    acc.initialBalance = account.balance
                }
                dataStore.accounts[existingIdx] = acc
                registered.append(acc)
                hasChanges = true
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: accountName,
                    broker: safeBroker,
                    kind: .sync,
                    currency: account.currency,
                    initialBalance: account.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true,
                    visibleInJournal: true
                )
                dataStore.accounts.append(newAcc)
                registered.append(newAcc)
                hasChanges = true
            }
        }
        
        // Remove default placeholder account if real accounts are registered
        if dataStore.accounts.contains(where: { $0.id.hasPrefix("ctrader_") || $0.id.hasPrefix("the5ers_") }) {
            if dataStore.accounts.count > 1 {
                dataStore.accounts.removeAll(where: { $0.id == "default-acc" })
            }
        }
        
        // Auto-select this cTrader account if current selection is default-acc
        if dataStore.selectedAccountId == "default-acc", let firstRegistered = registered.first {
            dataStore.selectedAccountId = firstRegistered.id
        }
        
        if hasChanges {
            dataStore.deduplicateAndCleanAccounts()
            dataStore.saveToDisk(immediate: true)
            dataStore.objectWillChange.send()
        }
        
        return registered
    }
    
    /// Tests connection and retrieves linked accounts without modifying journal data.
    public func testConnection() async throws -> (success: Bool, message: String, accounts: [CTraderAccount]) {
        self.isSyncing = true
        self.lastError = nil
        defer {
            self.isSyncing = false
            disconnect()
        }
        
        do {
            let accs = try await fetchAccounts()
            _ = registerDiscoveredAccounts(into: TradeDataStore.shared)
            return (true, "cTrader connection verified! \(accs.count) account(s) registered in Journal.", accs)
        } catch {
            self.lastError = error.localizedDescription
            return (false, "Connection error: \(error.localizedDescription)", [])
        }
    }
    
    @MainActor
    public func cancelSync() {
        self.isSyncing = false
        self.lastStatus = "Synchronization cancelled."
        disconnect()
    }
    
    /// Fully synchronizes selected cTrader accounts and their deal histories into TradeDataStore.
    public func syncWithTradeStore(
        dataStore: TradeDataStore,
        fromTimestamp: Int64? = nil,
        toTimestamp: Int64? = nil,
        targetAccountIds: Set<Int64>? = nil
    ) async throws -> CTraderSyncSummary {
        guard isConfigured else {
            throw NSError(domain: "cTrader", code: 401, userInfo: [NSLocalizedDescriptionKey: "cTrader Access Token is not configured."])
        }
        
        self.isSyncing = true
        self.lastStatus = "Connecting to cTrader Open API..."
        self.lastError = nil
        defer {
            self.isSyncing = false
            disconnect()
        }
        
        let allAccounts = try await fetchAccounts()
        let activeAccounts = allAccounts.filter { acc in
            if let targets = targetAccountIds, !targets.isEmpty {
                return targets.contains(acc.ctidTraderAccountId)
            }
            return selectedAccountIds.isEmpty || selectedAccountIds.contains(acc.ctidTraderAccountId)
        }
        
        guard !activeAccounts.isEmpty else {
            let msg = "No cTrader accounts selected for synchronization."
            self.lastStatus = msg
            return CTraderSyncSummary(accountsSynced: 0, dealsImported: 0, tradesRebuilt: 0, message: msg)
        }
        
        var totalDeals = 0
        var totalRebuiltTrades = 0
        let cleanToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        for account in activeAccounts {
            let accId = account.ctidTraderAccountId
            self.lastStatus = "Syncing account \(account.traderLogin) (\(account.brokerTitleShort))..."
            
            // 1. Authorize specific account session
            do {
                _ = try await sendRequest(
                    payloadType: 2102,
                    payload: ["ctidTraderAccountId": accId, "accessToken": cleanToken]
                )
            } catch {
                let msg = error.localizedDescription.lowercased()
                if msg.contains("already_logged_in") || msg.contains("already authorized") || msg.contains("already logged in") {
                    AppLogger.info("cTrader account \(accId) is already authorized on this session.")
                } else {
                    AppLogger.warn("cTrader account authorization notice for \(accId): \(error.localizedDescription)")
                }
            }
            
            // 2. Fetch Symbol Dictionary (including archived symbols to handle closed trades on delisted/renamed symbols)
            var symbolMap: [Int64: String] = [:]
            if let symbolsRes = try? await sendRequest(payloadType: 2114, payload: ["ctidTraderAccountId": accId, "includeArchivedSymbols": true]) {
                let symbolArray = (symbolsRes["symbol"] as? [[String: Any]]) ?? (symbolsRes["symbols"] as? [[String: Any]]) ?? []
                for s in symbolArray {
                    if let sId = safeInt64(s["symbolId"]),
                       let sName = (s["symbolName"] as? String) ?? (s["name"] as? String) {
                        symbolMap[sId] = sName
                    }
                }
                let archivedArray = (symbolsRes["archivedSymbol"] as? [[String: Any]]) ?? (symbolsRes["archivedSymbols"] as? [[String: Any]]) ?? []
                for s in archivedArray {
                    if let sId = safeInt64(s["symbolId"]),
                       let sName = (s["symbolName"] as? String) ?? (s["name"] as? String) {
                        if symbolMap[sId] == nil {
                            symbolMap[sId] = sName
                        }
                    }
                }
            }
            
            // 3. Ensure Journal Account exists
            let journalAccId = "ctrader_\(accId)"
            let brokerName = account.brokerTitleShort.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeBroker = brokerName.isEmpty ? "cTrader" : brokerName
            let envLabel = account.isLive ? "Live" : "Demo"
            let accountName = "\(safeBroker) #\(account.traderLogin) (\(envLabel))"
            
            if let existingIdx = dataStore.accounts.firstIndex(where: {
                $0.id == journalAccId ||
                $0.id.isEquivalentAccountId(to: journalAccId) ||
                $0.id.cleanAccountId == String(account.ctidTraderAccountId) ||
                $0.id.cleanAccountId == String(account.traderLogin) ||
                $0.name.contains("\(account.traderLogin)")
            }) {
                var acc = dataStore.accounts[existingIdx]
                acc.name = accountName
                acc.broker = safeBroker
                if acc.currency.uppercased() == "USD" && (account.currency == "SEK" || account.currency == "SGD") {
                    // Retain user's configured USD currency
                } else if !account.currency.isEmpty {
                    acc.currency = account.currency
                }
                acc.kind = .sync
                acc.autoSync = true
                acc.visibleInJournal = true
                if acc.initialBalance == 0 && account.balance > 0 {
                    acc.initialBalance = account.balance
                }
                dataStore.accounts[existingIdx] = acc
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: accountName,
                    broker: safeBroker,
                    kind: .sync,
                    currency: account.currency,
                    initialBalance: account.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true,
                    visibleInJournal: true
                )
                dataStore.accounts.append(newAcc)
                dataStore.saveToDisk()
            }
            
            // 4. Fetch Historical Deals in 6-day chunks
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let maxChunkMs: Int64 = 6 * 24 * 60 * 60 * 1000
            let dealsTo = toTimestamp ?? nowMs
            
            let defaultLookbackDays: Int64 = 730
            let fallbackStart = max(nowMs - (defaultLookbackDays * 86_400 * 1000), 0)
            
            let existingAccountExecs = dataStore.executions.filter { $0.accountId == journalAccId }
            let dealsFrom: Int64
            if let fromTimestamp = fromTimestamp, fromTimestamp > 0 {
                dealsFrom = fromTimestamp
            } else if let latestDate = existingAccountExecs.map({ $0.executedAt }).max() {
                let latestMs = Int64(latestDate.timeIntervalSince1970 * 1000)
                dealsFrom = max(latestMs - (2 * 86_400 * 1000), 0)
            } else {
                dealsFrom = fallbackStart
            }
            
            var rawDeals: [[String: Any]] = []
            var seenDealIds = Set<Int64>()
            let totalSpanMs = max(dealsTo - dealsFrom, 1)
            let estimatedChunks = max(1, Int((totalSpanMs + maxChunkMs - 1) / maxChunkMs))
            var chunkIndex = 0
            var consecutiveEmptyChunks = 0
            
            var currentChunkEnd = dealsTo
            while currentChunkEnd > dealsFrom {
                chunkIndex += 1
                let currentChunkStart = max(currentChunkEnd - maxChunkMs, dealsFrom)
                guard currentChunkEnd > currentChunkStart else { break }
                
                self.lastStatus = "Fetching cTrader deals (\(chunkIndex)/\(estimatedChunks))..."
                
                var dealsFoundInChunk = 0
                var chunkFrom = currentChunkStart
                while chunkFrom < currentChunkEnd {
                    let payload: [String: Any] = [
                        "ctidTraderAccountId": accId,
                        "fromTimestamp": chunkFrom,
                        "toTimestamp": currentChunkEnd,
                        "maxRows": 1000
                    ]
                    
                    do {
                        let dealsRes = try await sendRequest(payloadType: 2133, payload: payload)
                        let dealsList = (dealsRes["deal"] as? [[String: Any]]) ?? (dealsRes["deals"] as? [[String: Any]]) ?? (dealsRes["items"] as? [[String: Any]]) ?? []
                        var latestDealTs: Int64 = 0
                        for d in dealsList {
                            if let dealId = safeInt64(d["dealId"]) ?? safeInt64(d["id"]) {
                                if seenDealIds.insert(dealId).inserted {
                                    rawDeals.append(d)
                                    dealsFoundInChunk += 1
                                }
                            }
                            if let ts = safeInt64(d["executionTimestamp"]) ?? safeInt64(d["createTimestamp"]) ?? safeInt64(d["timestamp"]) {
                                latestDealTs = max(latestDealTs, ts)
                            }
                        }
                        
                        let hasMore = (dealsRes["hasMore"] as? Bool) ?? false
                        if hasMore && latestDealTs > chunkFrom && latestDealTs < currentChunkEnd {
                            chunkFrom = latestDealTs + 1
                        } else {
                            break
                        }
                    } catch {
                        AppLogger.warn("cTrader deal chunk [\(chunkFrom)-\(currentChunkEnd)] returned error: \(error.localizedDescription)")
                        break
                    }
                }
                
                if dealsFoundInChunk == 0 && !rawDeals.isEmpty {
                    consecutiveEmptyChunks += 1
                    if consecutiveEmptyChunks >= 15 {
                        break
                    }
                } else if dealsFoundInChunk > 0 {
                    consecutiveEmptyChunks = 0
                }
                
                currentChunkEnd = currentChunkStart
                if currentChunkEnd > dealsFrom {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }
            
            // 5. Convert Deals to Atomic Executions
            var newExecutions: [Execution] = []
            for raw in rawDeals {
                guard let dealId = safeInt64(raw["dealId"]) ?? safeInt64(raw["id"]),
                      let symbolId = safeInt64(raw["symbolId"]),
                      let execTimestamp = safeInt64(raw["executionTimestamp"]) ?? safeInt64(raw["createTimestamp"]) ?? safeInt64(raw["timestamp"]) else {
                    continue
                }
                
                if let statusVal = safeInt64(raw["dealStatus"]) {
                    if statusVal >= 3 { continue }
                } else if let statusStr = raw["dealStatus"] as? String {
                    let upper = statusStr.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if upper == "REJECTED" || upper == "INTERNALLY_REJECTED" || upper == "ERROR" || upper == "MISSED" || upper == "CANCELLED" {
                        continue
                    }
                }
                
                let volRaw = safeInt64(raw["filledVolume"]) ?? safeInt64(raw["volume"]) ?? 0
                guard volRaw > 0 else { continue }
                
                let priceRaw = safeDouble(raw["executionPrice"]) ?? safeDouble(raw["rate"]) ?? safeDouble(raw["price"]) ?? safeDouble(raw["closePrice"]) ?? safeDouble(raw["bid"]) ?? safeDouble(raw["ask"]) ?? 0.0
                guard priceRaw > 0 else { continue }
                
                let symbolName = symbolMap[symbolId] ?? (raw["symbolName"] as? String) ?? (raw["symbol"] as? String) ?? "Symbol_\(symbolId)"
                let sideStr = String(describing: raw["tradeSide"] ?? "BUY").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let side: ExecutionSide = (sideStr == "SELL" || sideStr == "2") ? .sell : .buy
                
                let spec = AssetContractEngine.spec(for: symbolName)
                let isMetals = spec.assetCategory == .goldAndMetals
                let isForex = spec.isForex
                let isCrypto = spec.assetCategory == .crypto
                
                let lotDivisor: Decimal
                if isMetals {
                    lotDivisor = 1_000_000
                } else if isForex {
                    lotDivisor = 10_000_000
                } else {
                    lotDivisor = 100
                }
                let quantity = max(Decimal(0.01), Decimal(volRaw) / lotDivisor)
                
                let moneyDigits = safeInt64(raw["moneyDigits"]).map(Int.init) ?? 2
                let moneyDivisor = pow(10.0, Double(moneyDigits))
                let commRaw = safeDouble(raw["commission"]) ?? 0.0
                let fee = Decimal(abs(commRaw) / moneyDivisor)
                
                let closeDetail = raw["closePositionDetail"] as? [String: Any]
                let swapRaw = safeDouble(closeDetail?["swap"]) ?? safeDouble(raw["swap"]) ?? 0.0
                let swap: Decimal? = swapRaw != 0 ? Decimal(swapRaw / moneyDivisor) : nil
                
                let execDate = Date(timeIntervalSince1970: Double(execTimestamp) / 1000.0)
                let fillId = "ctrader_deal_\(dealId)"
                let hash = "\(journalAccId)|\(spec.cleanSymbol)|\(side.rawValue)|\(quantity)|\(priceRaw)|\(execTimestamp)"
                
                let assetClass = isForex ? "forex" : (isMetals ? "commodity" : (isCrypto ? "crypto" : "index"))
                
                let exec = Execution(
                    id: fillId,
                    accountId: journalAccId,
                    symbol: symbolName,
                    side: side,
                    quantity: quantity,
                    price: Decimal(priceRaw),
                    fee: fee,
                    swap: swap,
                    executedAt: execDate,
                    assetClass: assetClass,
                    source: "ctrader",
                    contentHash: hash
                )
                newExecutions.append(exec)
            }
            
            // 6. Ingest executions and rebuild round trips
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
                totalDeals += newExecutions.count
            } else if dataStore.trades.filter({ $0.accountId == journalAccId }).isEmpty && !dataStore.executions.filter({ $0.accountId == journalAccId }).isEmpty {
                dataStore.rebuildAccount(accountId: journalAccId)
            }
            
            // 7. Check for open positions via Reconcile (payloadType 2124)
            if let reconcileRes = try? await sendRequest(payloadType: 2124, payload: ["ctidTraderAccountId": accId]),
               let positions = (reconcileRes["position"] as? [[String: Any]]) ?? (reconcileRes["positions"] as? [[String: Any]]) {
                
                var activePosKeys = Set<String>()
                
                for pos in positions {
                    let tradeData = (pos["tradeData"] as? [String: Any]) ?? pos
                    guard let posId = safeInt64(pos["positionId"]) ?? safeInt64(tradeData["positionId"]),
                          let sId = safeInt64(tradeData["symbolId"]) ?? safeInt64(pos["symbolId"]),
                          let vol = safeInt64(tradeData["volume"]) ?? safeInt64(pos["volume"]),
                          let price = safeDouble(pos["price"]) ?? safeDouble(tradeData["price"]) else {
                        continue
                    }
                    
                    let openTradeKey = "ctrader_open_\(posId)"
                    activePosKeys.insert(openTradeKey)
                    
                    let sName = symbolMap[sId] ?? "Symbol_\(sId)"
                    let sideStr = String(describing: tradeData["tradeSide"] ?? pos["tradeSide"] ?? "BUY").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let dir: TradeDirection = (sideStr == "SELL" || sideStr == "2") ? .short : .long
                    let openTs = safeInt64(tradeData["openTimestamp"]) ?? safeInt64(pos["openTimestamp"]) ?? nowMs
                    let openDate = Date(timeIntervalSince1970: Double(openTs) / 1000.0)
                    
                    let isMetals = sName.contains("XAU") || sName.contains("XAG")
                    let isForex = sName.count == 6 && !sName.contains("BTC") && !sName.contains("ETH")
                    let lotDivisor: Decimal = isMetals ? 1_000_000 : (isForex ? 10_000_000 : 100)
                    let qty = max(Decimal(0.01), Decimal(vol) / lotDivisor)
                    
                    let stopLossVal = safeDouble(pos["stopLoss"]) ?? safeDouble(tradeData["stopLoss"])
                    let takeProfitVal = safeDouble(pos["takeProfit"]) ?? safeDouble(tradeData["takeProfit"])
                    
                    if let existingIdx = dataStore.trades.firstIndex(where: { $0.key == openTradeKey }) {
                        var existing = dataStore.trades[existingIdx]
                        existing.openQuantity = qty
                        existing.quantity = qty
                        existing.avgEntry = Decimal(price)
                        if let sl = stopLossVal { existing.stopLoss = Decimal(sl) }
                        if let tp = takeProfitVal { existing.profitTarget = Decimal(tp) }
                        if existing.playbookId == nil || existing.playbookId?.isEmpty == true {
                            existing.playbookId = dataStore.defaultPlaybook?.id
                        }
                        dataStore.trades[existingIdx] = existing
                    } else {
                        let alreadyHasOpenTrade = dataStore.trades.contains { t in
                            t.accountId == journalAccId &&
                            t.status == .open &&
                            t.symbol == sName &&
                            t.direction == dir &&
                            abs(t.openQuantity - qty) < Decimal(0.01)
                        }
                        
                        if !alreadyHasOpenTrade {
                            let openTrade = Trade(
                                key: openTradeKey,
                                accountId: journalAccId,
                                symbol: sName,
                                assetClass: isForex ? "forex" : (isMetals ? "commodity" : "cfd"),
                                direction: dir,
                                status: .open,
                                openedAt: openDate,
                                closedAt: nil,
                                quantity: qty,
                                openQuantity: qty,
                                avgEntry: Decimal(price),
                                avgExit: nil,
                                grossPnl: 0,
                                fees: 0,
                                netPnl: 0,
                                executionCount: 1,
                                executionIds: [],
                                notes: "Open position synced from cTrader (Position #\(posId))",
                                tags: ["ctrader", "open"],
                                playbookId: dataStore.defaultPlaybook?.id,
                                stopLoss: stopLossVal.map { Decimal($0) },
                                profitTarget: takeProfitVal.map { Decimal($0) }
                            )
                            dataStore.trades.append(openTrade)
                        }
                    }
                }
                
                // Clean up closed positions that were previously tracked under ctrader_open_*
                dataStore.trades.removeAll { trade in
                    trade.accountId == journalAccId &&
                    trade.key.hasPrefix("ctrader_open_") &&
                    !activePosKeys.contains(trade.key)
                }
            }
            
            dataStore.rebuildAccount(accountId: journalAccId)
            totalRebuiltTrades += dataStore.trades.filter { $0.accountId == journalAccId }.count
            
            if dataStore.selectedAccountId == "default-acc" || dataStore.selectedAccountId.isEmpty {
                dataStore.selectedAccountId = journalAccId
            }
        }
        
        dataStore.deduplicateAndCleanAccounts()
        dataStore.rebuildAllAccounts()
        dataStore.saveToDisk(immediate: true)
        dataStore.invalidatePerformanceCaches()
        dataStore.objectWillChange.send()
        
        let now = Date()
        self.lastSyncDate = now
        let summaryMsg = "cTrader synchronized: \(activeAccounts.count) account(s), \(totalDeals) executions imported, \(totalRebuiltTrades) trades updated."
        self.lastStatus = summaryMsg
        
        if SupabaseService.shared.isConfigured {
            Task {
                await dataStore.syncWithSupabase(isBackground: true)
            }
        }
        
        return CTraderSyncSummary(
            accountsSynced: activeAccounts.count,
            dealsImported: totalDeals,
            tradesRebuilt: totalRebuiltTrades,
            message: summaryMsg
        )
    }
}
