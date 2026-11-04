import Foundation
import Combine

extension ExnessService {
    // MARK: - Exness Data Ingestion & Parser

    internal func fetchEndpointData(path: String, host: String) async -> (json: [String: Any]?, statusCode: Int) {
        let cleanHost = host.hasSuffix("/") ? String(host.dropLast()) : host
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "\(cleanHost)\(cleanPath)") else { return (nil, 0) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        guard let headers = try? signRequest(method: "GET", path: cleanPath, bodyData: nil) else { return (nil, 0) }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let start = Date()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, 0) }

        recordServerTime(from: http, roundTripStart: start)

        if http.statusCode == 200 {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json, 200)
        } else {
            AppLogger.debug("Exness: Endpoint \(cleanHost)\(cleanPath) -> HTTP \(http.statusCode)")
            return (nil, http.statusCode)
        }
    }

    internal func assetClassForSymbol(_ symbol: String) -> AssetClass {
        let symUpper = symbol.uppercased()
        if symUpper.hasPrefix("XAU") || symUpper.hasPrefix("XAG") || symUpper.contains("GOLD") || symUpper.contains("SILVER") {
            return "commodity"
        }
        if symUpper.hasPrefix("BTC") || symUpper.hasPrefix("ETH") || symUpper.hasPrefix("SOL") || symUpper.hasPrefix("XRP") {
            return "crypto"
        }
        if symUpper.hasPrefix("US30") || symUpper.hasPrefix("USTEC") || symUpper.hasPrefix("NAS") || symUpper.hasPrefix("SPX") || symUpper.hasPrefix("GER") || symUpper.hasPrefix("UK100") || symUpper.hasPrefix("WS30") {
            return "indices"
        }
        return "forex"
    }

    /// Synchronizes trades, orders, positions, and history from Exness REST API
    public func syncTrades() async throws -> Int {
        let cleanId = accountId.cleanAccountId
        guard !cleanId.isEmpty else {
            throw NSError(domain: "ExnessService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please configure Exness Account ID."])
        }

        await MainActor.run {
            self.isSyncing = true
        }
        defer {
            Task { @MainActor in
                self.isSyncing = false
            }
        }

        // 1. Fetch live balance, equity, and normalized currency
        _ = try? await testConnection()

        let accessPointHost = await resolveAccessPoint()
        let clusterHost = accessPointHost.contains("ap-") ? accessPointHost : "https://api.exness-api.com"
        let journalAccId = "exness_\(cleanId)"

        await MainActor.run {
            self.syncAccountWithDataStore()
        }

        // 2. Fetch live snapshot positions and orders
        let snapshotResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/snapshot", host: clusterHost)
        var snapshotPositions: [[String: Any]] = []
        var allOrders: [[String: Any]] = []
        var seenOrderIds = Set<String>()




        if let sJson = snapshotResult.json {
            if let posArr = sJson["positions"] as? [[String: Any]] {
                snapshotPositions = posArr
            }
            if let ordArr = (sJson["orders"] as? [[String: Any]]) ?? (sJson["items"] as? [[String: Any]]) {
                for it in ordArr {
                    let order = (it["order"] as? [String: Any]) ?? it
                    if let oId = parseId(order["order_id"]) ?? parseId(order["id"]), !seenOrderIds.contains(oId) {
                        seenOrderIds.insert(oId)
                        allOrders.append(order)
                    }
                }
            }
        }

        // Fallback: dedicated active positions endpoint if snapshot returned empty positions
        if snapshotPositions.isEmpty {
            let posResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/positions", host: clusterHost)
            if let pJson = posResult.json, let posArr = (pJson["positions"] as? [[String: Any]]) ?? (pJson["items"] as? [[String: Any]]) {
                snapshotPositions = posArr
            }
        }

        // Also query active trading orders endpoint (contains active SL/TP orders on open positions)
        let activeOrdersResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/orders", host: clusterHost)
        if let aoJson = activeOrdersResult.json, let ordArr = (aoJson["orders"] as? [[String: Any]]) ?? (aoJson["items"] as? [[String: Any]]) {
            for it in ordArr {
                let order = (it["order"] as? [String: Any]) ?? it
                if let oId = parseId(order["order_id"]) ?? parseId(order["id"]), !seenOrderIds.contains(oId) {
                    seenOrderIds.insert(oId)
                    allOrders.append(order)
                }
            }
        }

        // 3. Query Deals and Orders History in safe 14-day chunks
        let allDeals = await fetchHistoryDealsAndOrders(
            cleanId: cleanId,
            clusterHost: clusterHost,
            nowServer: nowServer,
            allOrders: &allOrders,
            seenOrderIds: &seenOrderIds
        )

        // 4. Map Orders and Positions to SL / TP by position_id and order_id
        let positionSltpMap = buildPositionSltpMap(
            allOrders: allOrders,
            snapshotPositions: snapshotPositions,
            allDeals: allDeals
        )

        // 5. Group deals by position_id
        let groups = groupDealsByPosition(allDeals)

        // 6. Build atomic Executions and authoritative Trades (with multi-deal and partial close support)
        var directTrades: [Trade] = []
        var newExecutions: [Execution] = []
        let defaultPlaybookId = await MainActor.run { TradeDataStore.shared.defaultPlaybook?.id }

        for (posId, g) in groups {
            let sltp = positionSltpMap[posId]
            let trade = buildReconciledTrade(
                posId: posId,
                g: g,
                journalAccId: journalAccId,
                defaultPlaybookId: defaultPlaybookId,
                sltp: sltp,
                newExecutions: &newExecutions
            )
            directTrades.append(trade)
        }

        // 7. Parse active Snapshot positions (if not already covered in deals)
        reconcileSnapshotPositions(
            snapshotPositions: snapshotPositions,
            directTrades: &directTrades,
            positionSltpMap: positionSltpMap,
            journalAccId: journalAccId,
            defaultPlaybookId: defaultPlaybookId,
            newExecutions: &newExecutions
        )

        // 8. Ingest into TradeDataStore
        let mergedAccountTradesForUpload = await ingestReconciledExnessTrades(
            journalAccId: journalAccId,
            cleanId: cleanId,
            directTrades: directTrades,
            newExecutions: newExecutions,
            snapshotStatusCode: snapshotResult.statusCode,
            snapshotPositions: snapshotPositions
        )

        let now = Date()
        UserDefaults.standard.set(now, forKey: kExnessLastSync)
        await MainActor.run {
            self.lastSyncDate = now
            self.isConnected = true
        }

        // Asynchronously backup to Supabase Cloud in the background without blocking UI
        let tradesToBackup = mergedAccountTradesForUpload
        if SupabaseService.shared.isConfigured {
            Task.detached(priority: .background) {
                if !tradesToBackup.isEmpty {
                    _ = try? await SupabaseService.shared.upsertTrades(tradesToBackup)
                }
                if !newExecutions.isEmpty {
                    _ = try? await SupabaseService.shared.upsertExecutions(newExecutions)
                }
            }
        }

        return self.syncedTradesCount
    }

    private func fetchHistoryDealsAndOrders(
        cleanId: String,
        clusterHost: String,
        nowServer: Date,
        allOrders: inout [[String: Any]],
        seenOrderIds: inout Set<String>
    ) async -> [[String: Any]] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        var chunkWindows: [(from: Date, to: Date)] = []
        for i in 0..<6 {
            let chunkEnd = nowServer.addingTimeInterval(-Double(i * 14 * 24 * 3600))
            let chunkStart = nowServer.addingTimeInterval(-Double((i + 1) * 14 * 24 * 3600))
            chunkWindows.append((from: chunkStart, to: chunkEnd))
        }

        var allDeals: [[String: Any]] = []
        var seenDealIds = Set<String>()

        for w in chunkWindows {
            let toStr = isoFormatter.string(from: w.to)
            let encodedTo = toStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? toStr

            var dealCursorDate = w.from
            for _ in 0..<15 {
                let fromStr = isoFormatter.string(from: dealCursorDate)
                let encodedFrom = fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr
                let dealsPath = "/v1/history/accounts/\(cleanId)/deals?from=\(encodedFrom)&to=\(encodedTo)"
                let dRes = await fetchEndpointData(path: dealsPath, host: clusterHost)
                guard let dJson = dRes.json,
                      let items = (dJson["deals"] as? [[String: Any]]) ?? (dJson["items"] as? [[String: Any]]),
                      !items.isEmpty else { break }

                var addedNewDeals = 0
                for it in items {
                    let deal = (it["deal"] as? [String: Any]) ?? it
                    if let dId = parseId(deal["deal_id"]) ?? parseId(deal["id"]), !seenDealIds.contains(dId) {
                        seenDealIds.insert(dId)
                        allDeals.append(deal)
                        addedNewDeals += 1
                    }
                }
                if items.count < 100 || addedNewDeals == 0 { break }
                if let lastItem = items.last {
                    let lastDeal = (lastItem["deal"] as? [String: Any]) ?? lastItem
                    if let lastDate = parseDate(lastItem["event_time"]) ?? parseDate(lastDeal["create_time"]),
                       lastDate > dealCursorDate {
                        dealCursorDate = lastDate
                    } else { break }
                } else { break }
            }

            var orderCursorDate = w.from
            for _ in 0..<15 {
                let fromStr = isoFormatter.string(from: orderCursorDate)
                let encodedFrom = fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr
                let ordersPath = "/v1/history/accounts/\(cleanId)/orders?from=\(encodedFrom)&to=\(encodedTo)"
                let oRes = await fetchEndpointData(path: ordersPath, host: clusterHost)
                guard let oJson = oRes.json,
                      let items = (oJson["orders"] as? [[String: Any]]) ?? (oJson["items"] as? [[String: Any]]),
                      !items.isEmpty else { break }

                var addedNewOrders = 0
                for it in items {
                    let order = (it["order"] as? [String: Any]) ?? it
                    if let oId = parseId(order["order_id"]) ?? parseId(order["id"]), !seenOrderIds.contains(oId) {
                        seenOrderIds.insert(oId)
                        allOrders.append(order)
                        addedNewOrders += 1
                    }
                }
                if items.count < 100 || addedNewOrders == 0 { break }
                if let lastItem = items.last {
                    let lastOrder = (lastItem["order"] as? [String: Any]) ?? lastItem
                    if let lastDate = parseDate(lastItem["event_time"]) ?? parseDate(lastOrder["update_time"]) ?? parseDate(lastOrder["create_time"]),
                       lastDate > orderCursorDate {
                        orderCursorDate = lastDate
                    } else { break }
                } else { break }
            }
        }
        return allDeals
    }

    private func ingestReconciledExnessTrades(
        journalAccId: String,
        cleanId: String,
        directTrades: [Trade],
        newExecutions: [Execution],
        snapshotStatusCode: Int,
        snapshotPositions: [[String: Any]]
    ) async -> [Trade] {
        await MainActor.run {
            let dataStore = TradeDataStore.shared
            var currentTrades = dataStore.trades
            var tradesMutated = false

            if snapshotStatusCode == 200 {
                let activePositionIds = Set(snapshotPositions.compactMap { parseId($0["position_id"]) ?? parseId($0["id"]) })
                for idx in 0..<currentTrades.count {
                    if currentTrades[idx].accountId == journalAccId &&
                       currentTrades[idx].key.hasPrefix("exness_") &&
                       currentTrades[idx].status == .open {
                        let posId = String(currentTrades[idx].key.dropFirst("exness_".count))
                        if !activePositionIds.contains(posId) && !directTrades.contains(where: { $0.key == currentTrades[idx].key }) {
                            var pnl = currentTrades[idx].netPnl
                            if pnl == 0, let exitP = currentTrades[idx].avgExit, exitP > 0, currentTrades[idx].avgEntry > 0 {
                                pnl = AssetContractEngine.calculateGrossPnl(
                                    symbol: currentTrades[idx].symbol,
                                    direction: currentTrades[idx].direction,
                                    quantity: currentTrades[idx].quantity,
                                    entryPrice: currentTrades[idx].avgEntry,
                                    exitPrice: exitP
                                )
                                currentTrades[idx].grossPnl = pnl
                                currentTrades[idx].netPnl = pnl
                            }
                            if pnl != 0 || currentTrades[idx].avgExit != nil {
                                currentTrades[idx].status = pnl > 0 ? .win : (pnl < 0 ? .loss : .breakeven)
                                currentTrades[idx].openQuantity = Decimal.zero
                                if currentTrades[idx].closedAt == nil {
                                    currentTrades[idx].closedAt = Date()
                                }
                                tradesMutated = true
                            }
                        }
                    }
                }
            }

            let defaultPbId = dataStore.defaultPlaybook?.id
            for t in directTrades {
                var tradeToMerge = t
                if let idx = currentTrades.firstIndex(where: { $0.key == tradeToMerge.key }) {
                    let existing = currentTrades[idx]
                    if tradeToMerge.notes == nil || (tradeToMerge.notes?.isEmpty ?? true) {
                        tradeToMerge.notes = existing.notes
                    }
                    if tradeToMerge.tags.isEmpty { tradeToMerge.tags = existing.tags }
                    if tradeToMerge.mistakes.isEmpty { tradeToMerge.mistakes = existing.mistakes }
                    if tradeToMerge.rating == nil { tradeToMerge.rating = existing.rating }
                    if tradeToMerge.playbookId == nil { tradeToMerge.playbookId = existing.playbookId ?? defaultPbId }
                    if tradeToMerge.reviewedAt == nil { tradeToMerge.reviewedAt = existing.reviewedAt }

                    if tradeToMerge.stopLoss == nil || (tradeToMerge.stopLoss ?? 0) <= 0 {
                        tradeToMerge.stopLoss = existing.stopLoss
                    }
                    if tradeToMerge.profitTarget == nil || (tradeToMerge.profitTarget ?? 0) <= 0 {
                        tradeToMerge.profitTarget = existing.profitTarget
                    }
                    currentTrades[idx] = tradeToMerge
                } else {
                    if tradeToMerge.playbookId == nil {
                        tradeToMerge.playbookId = defaultPbId
                    }
                    currentTrades.append(tradeToMerge)
                }
            }
            if !directTrades.isEmpty || tradesMutated {
                dataStore.trades = currentTrades
                dataStore.deduplicateTrades()
            }
            let merged = dataStore.trades.filter { $0.accountId == journalAccId }

            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
            }

            if !directTrades.isEmpty || !newExecutions.isEmpty || tradesMutated {
                if dataStore.selectedAccountId.isEmpty || dataStore.selectedAccountId == "default-acc" {
                    dataStore.selectedAccountId = journalAccId
                }
                dataStore.invalidatePerformanceCaches()
                dataStore.performSaveToDiskAsync()
                dataStore.objectWillChange.send()
            }

            let total = directTrades.count
            self.syncedTradesCount = total

            let formattedBal = Formatters.formatCurrency(self.balance, currency: self.currency)
            let accLabel = self.accountName.isEmpty ? cleanId : "'\(self.accountName)'"

            if total > 0 {
                self.lastSyncSummary = "Connected • Balance: \(formattedBal) • \(total) trades synced"
            } else {
                self.lastSyncSummary = "Connected • Balance: \(formattedBal) • Account \(accLabel) synced (no recent deals in 28-day window)"
            }
            return merged
        }
    }
}
