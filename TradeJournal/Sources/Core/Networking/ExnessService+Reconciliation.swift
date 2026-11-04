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
            DispatchQueue.main.async {
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


        func parseId(_ val: Any?) -> String? {
            if let s = val as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty {
                return s.trimmingCharacters(in: .whitespaces)
            }
            if let i = val as? Int { return String(i) }
            if let i64 = val as? Int64 { return String(i64) }
            if let num = val as? NSNumber { return num.stringValue }
            return nil
        }

        func parseInt(_ val: Any?) -> Int? {
            if let i = val as? Int { return i }
            if let i64 = val as? Int64 { return Int(i64) }
            if let num = val as? NSNumber { return num.intValue }
            if let s = val as? String, let i = Int(s) { return i }
            return nil
        }

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

        // 3. Query Deals and Orders History in safe 14-day chunks (Exness limit: max 30 days per request)
        // Backfill up to 84 days back (6 chunks of 14 days)
        let nowServer = Date().addingTimeInterval(Double(serverTimeOffsetMs) / 1000.0)
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

            // A. Fetch Deals with cursor pagination (Exness returns max 100 items per page sorted ascending by event_time)
            var dealCursorDate = w.from
            for _ in 0..<15 {
                let fromStr = isoFormatter.string(from: dealCursorDate)
                let encodedFrom = fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr
                let dealsPath = "/v1/history/accounts/\(cleanId)/deals?from=\(encodedFrom)&to=\(encodedTo)"
                let dRes = await fetchEndpointData(path: dealsPath, host: clusterHost)
                guard let dJson = dRes.json,
                      let items = (dJson["deals"] as? [[String: Any]]) ?? (dJson["items"] as? [[String: Any]]),
                      !items.isEmpty else {
                    break
                }

                var addedNewDeals = 0
                for it in items {
                    let deal = (it["deal"] as? [String: Any]) ?? it
                    if let dId = parseId(deal["deal_id"]) ?? parseId(deal["id"]),
                       !seenDealIds.contains(dId) {
                        seenDealIds.insert(dId)
                        allDeals.append(deal)
                        addedNewDeals += 1
                    }
                }

                if items.count < 100 || addedNewDeals == 0 {
                    break
                }
                if let lastItem = items.last {
                    let lastDeal = (lastItem["deal"] as? [String: Any]) ?? lastItem
                    if let lastDate = parseDate(lastItem["event_time"]) ?? parseDate(lastDeal["create_time"]),
                       lastDate > dealCursorDate {
                        dealCursorDate = lastDate
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            // B. Fetch Orders with cursor pagination (Exness returns max 100 items per page sorted ascending by event_time)
            var orderCursorDate = w.from
            for _ in 0..<15 {
                let fromStr = isoFormatter.string(from: orderCursorDate)
                let encodedFrom = fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr
                let ordersPath = "/v1/history/accounts/\(cleanId)/orders?from=\(encodedFrom)&to=\(encodedTo)"
                let oRes = await fetchEndpointData(path: ordersPath, host: clusterHost)
                guard let oJson = oRes.json,
                      let items = (oJson["orders"] as? [[String: Any]]) ?? (oJson["items"] as? [[String: Any]]),
                      !items.isEmpty else {
                    break
                }

                var addedNewOrders = 0
                for it in items {
                    let order = (it["order"] as? [String: Any]) ?? it
                    if let oId = parseId(order["order_id"]) ?? parseId(order["id"]),
                       !seenOrderIds.contains(oId) {
                        seenOrderIds.insert(oId)
                        allOrders.append(order)
                        addedNewOrders += 1
                    }
                }

                if items.count < 100 || addedNewOrders == 0 {
                    break
                }
                if let lastItem = items.last {
                    let lastOrder = (lastItem["order"] as? [String: Any]) ?? lastItem
                    if let lastDate = parseDate(lastItem["event_time"]) ?? parseDate(lastOrder["update_time"]) ?? parseDate(lastOrder["create_time"]),
                       lastDate > orderCursorDate {
                        orderCursorDate = lastDate
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
        }


        // 4. Map Orders and Positions to SL / TP by position_id and order_id
        func extractSltp(from dict: [String: Any]) -> (sl: Decimal?, tp: Decimal?) {
            let sl = parseDecimal(dict["stop_loss_price"]) ??
                     parseDecimal(dict["stop_loss"]) ??
                     parseDecimal(dict["sl"]) ??
                     parseDecimal(dict["sl_price"])
            let tp = parseDecimal(dict["take_profit_price"]) ??
                     parseDecimal(dict["take_profit"]) ??
                     parseDecimal(dict["tp"]) ??
                     parseDecimal(dict["tp_price"])
            let validSl = (sl != nil && (sl ?? 0) > 0) ? sl : nil
            let validTp = (tp != nil && (tp ?? 0) > 0) ? tp : nil
            return (validSl, validTp)
        }

        var positionSltpMap: [String: (sl: Decimal?, tp: Decimal?)] = [:]

        // 4.1 Harvest from all Orders (historical + active snapshot)
        for o in allOrders {
            let (sl, tp) = extractSltp(from: o)
            guard sl != nil || tp != nil else { continue }
            if let posId = parseId(o["position_id"]) ?? parseId(o["positionId"]) {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
            if let ordId = parseId(o["order_id"]) ?? parseId(o["orderId"]) {
                let existing = positionSltpMap[ordId] ?? (nil, nil)
                positionSltpMap[ordId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
        }

        // 4.2 Harvest from Snapshot Positions
        for p in snapshotPositions {
            let (sl, tp) = extractSltp(from: p)
            guard sl != nil || tp != nil else { continue }
            if let posId = parseId(p["position_id"]) ?? parseId(p["positionId"]) {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
        }

        // 4.3 Harvest from Deal close reasons or comments (e.g. "[sl]", "[tp 2715.00]", "stop_loss")
        for d in allDeals {
            guard let posId = parseId(d["position_id"]) ?? parseId(d["positionId"]) else { continue }
            let comment = (d["comment"] as? String ?? "").lowercased()
            let reason = (d["reason"] as? String ?? d["close_reason"] as? String ?? "").lowercased()
            let p = parseDecimal(d["price"])

            let isSl = comment.contains("[sl") || comment.contains("sl]") || reason.contains("stop_loss") || reason == "sl"
            let isTp = comment.contains("[tp") || comment.contains("tp]") || reason.contains("take_profit") || reason == "tp"

            if (isSl || isTp), let price = p, price > 0 {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (
                    isSl ? (existing.sl ?? price) : existing.sl,
                    isTp ? (existing.tp ?? price) : existing.tp
                )
            }
        }

        // 5. Group deals by position_id
        struct DealGroup {
            let positionId: String
            var symbol: String
            var openDeals: [[String: Any]]
            var closeDeals: [[String: Any]]
        }

        var groups: [String: DealGroup] = [:]
        for d in allDeals {
            let type = (d["type"] as? String ?? "").lowercased()
            if type == "balance" || type.contains("deposit") || type.contains("withdraw") || type == "null_compensation" || type == "credit" || type == "bonus" {
                // Deposit, withdrawal, or negative-balance compensation transaction
                continue
            }
            guard let posId = parseId(d["position_id"]) ?? parseId(d["positionId"]), !posId.isEmpty else { continue }
            let sym = (d["instrument"] as? String) ?? (d["symbol"] as? String) ?? "UNKNOWN"

            if groups[posId] == nil {
                groups[posId] = DealGroup(positionId: posId, symbol: sym, openDeals: [], closeDeals: [])
            }

            // Robust classification of open (IN) vs close (OUT) deal
            let entryTypeStr = (d["entry_type"] as? String ?? d["entry"] as? String ?? "").lowercased()
            let entryInt = parseInt(d["entry"]) ?? parseInt(d["entry_type"])
            let typeStr = (d["type"] as? String ?? d["action"] as? String ?? "").lowercased()
            let reasonStr = (d["reason"] as? String ?? d["close_reason"] as? String ?? d["comment"] as? String ?? "").lowercased()
            let hasCloseReason = reasonStr.contains("sl") || reasonStr.contains("tp") || reasonStr.contains("close") || reasonStr.contains("stop_out") || reasonStr.contains("so")
            let hasProfit = (parseDecimal(d["profit"]) ?? 0) != 0 || (d["profit"] as? [String: Any]) != nil
            let hasCloseTime = d["close_time"] != nil || d["closed_at"] != nil

            let isClose: Bool = {
                if entryInt == 1 || entryInt == 2 || entryInt == 3 { return true }
                if entryInt == 0 { return false }
                if entryTypeStr.contains("out") || entryTypeStr.contains("exit") || entryTypeStr.contains("close") { return true }
                if entryTypeStr.contains("in") || entryTypeStr.contains("entry") || entryTypeStr.contains("open") { return false }
                if typeStr.contains("close") || typeStr.contains("out") || typeStr.contains("exit") { return true }
                if typeStr.contains("open") || typeStr.contains("in") || typeStr.contains("entry") { return false }
                if hasCloseTime || hasCloseReason || hasProfit { return true }
                return false
            }()

            if isClose {
                groups[posId]?.closeDeals.append(d)
            } else {
                groups[posId]?.openDeals.append(d)
            }
        }

        // 6. Build atomic Executions and authoritative Trades (with multi-deal and partial close support)
        var directTrades: [Trade] = []
        var newExecutions: [Execution] = []
        let defaultPlaybookId = await MainActor.run { TradeDataStore.shared.defaultPlaybook?.id }

        for (posId, g) in groups {
            let sym = g.symbol
            let assetClass = assetClassForSymbol(sym)
            let sltp = positionSltpMap[posId]
            var execIds: [String] = []

            // A. Open Deals & Entry (Support multiple open fills/scale-in)
            var totalOpenVolume: Decimal = 0
            var openWeightedSum: Decimal = 0
            var earliestOpenDate: Date = Date()
            var tradeDir: TradeDirection = .long

            for (idx, od) in g.openDeals.enumerated() {
                let v = parseDecimal(od["volume"]) ?? 0
                let p = parseDecimal(od["price"]) ?? 0
                let d = parseDate(od["create_time"]) ?? Date()
                let dirStr = (od["direction"] as? String ?? "buy").lowercased()
                let currentDir: TradeDirection = (dirStr == "sell") ? .short : .long

                if idx == 0 {
                    tradeDir = currentDir
                    earliestOpenDate = d
                } else if d < earliestOpenDate {
                    earliestOpenDate = d
                }

                totalOpenVolume += v
                openWeightedSum += (p * v)

                if let dId = parseId(od["deal_id"]) ?? parseId(od["id"]) {
                    let execId = "exness_deal_\(dId)"
                    execIds.append(execId)
                    let fillHash = "\(journalAccId)|\(sym)|\(dirStr)|\(v)|\(p)|\(Int64(d.timeIntervalSince1970 * 1000))"
                    let openFill = Execution(
                        id: execId,
                        accountId: journalAccId,
                        symbol: sym,
                        side: currentDir == .short ? .sell : .buy,
                        quantity: v,
                        price: p,
                        fee: 0,
                        swap: nil,
                        executedAt: d,
                        assetClass: assetClass,
                        source: "exness",
                        contentHash: fillHash
                    )
                    newExecutions.append(openFill)
                }
            }

            let entryPrice = totalOpenVolume > 0 ? (openWeightedSum / totalOpenVolume) : (parseDecimal(g.openDeals.first?["price"]) ?? 0)
            let volume = totalOpenVolume > 0 ? totalOpenVolume : (parseDecimal(g.openDeals.first?["volume"]) ?? 0.01)

            // B. Close Deals & Exits (Support Partial Closes)
            var totalClosedVolume: Decimal = 0
            var closeWeightedSum: Decimal = 0
            var totalRealizedPnl: Decimal = 0
            var latestCloseDate: Date = earliestOpenDate
            var exits: [ExitAttribution] = []

            for cd in g.closeDeals {
                let v = parseDecimal(cd["volume"]) ?? 0
                let p = parseDecimal(cd["price"]) ?? entryPrice
                let d = parseDate(cd["create_time"]) ?? parseDate(cd["time"]) ?? earliestOpenDate
                let exitDir = (cd["direction"] as? String ?? "sell").lowercased()

                var dealPnl: Decimal = 0
                if let pObj = cd["profit"] as? [String: Any] {
                    dealPnl = parseDecimal(pObj["amount"]) ?? parseDecimal(pObj["value"]) ?? 0
                } else if let directP = parseDecimal(cd["profit"]) {
                    dealPnl = directP
                } else if let pVal = parseDecimal(cd["realized_pnl"]) ?? parseDecimal(cd["net_profit"]) ?? parseDecimal(cd["pnl"]) {
                    dealPnl = pVal
                }

                totalClosedVolume += v
                closeWeightedSum += (p * v)
                totalRealizedPnl += dealPnl
                if d > latestCloseDate {
                    latestCloseDate = d
                }

                if let cdId = parseId(cd["deal_id"]) ?? parseId(cd["id"]) {
                    let exitExecId = "exness_deal_\(cdId)"
                    execIds.append(exitExecId)
                    let exitHash = "\(journalAccId)|\(sym)|\(exitDir)|\(v)|\(p)|\(Int64(d.timeIntervalSince1970 * 1000))"
                    let exitFill = Execution(
                        id: exitExecId,
                        accountId: journalAccId,
                        symbol: sym,
                        side: tradeDir == .short ? .buy : .sell,
                        quantity: v,
                        price: p,
                        fee: 0,
                        swap: nil,
                        executedAt: d,
                        assetClass: assetClass,
                        source: "exness",
                        contentHash: exitHash
                    )
                    newExecutions.append(exitFill)

                    exits.append(ExitAttribution(
                        executionId: exitExecId,
                        grossPnl: dealPnl,
                        quantity: v
                    ))
                }
            }

            let remainingOpenVolume = max(Decimal(0), volume - totalClosedVolume)
            let isFullyClosed = remainingOpenVolume <= Decimal(0.000001) && totalClosedVolume > 0
            let avgExit = totalClosedVolume > 0 ? (closeWeightedSum / totalClosedVolume) : nil

            // Authoritative contract P&L fallback: if broker reported deal profit 0 but price moved, calculate gross P&L
            if totalRealizedPnl == 0, let exitP = avgExit, exitP > 0, entryPrice > 0 {
                let calcPnl = AssetContractEngine.calculateGrossPnl(
                    symbol: sym,
                    direction: tradeDir,
                    quantity: totalClosedVolume,
                    entryPrice: entryPrice,
                    exitPrice: exitP
                )
                if calcPnl != 0 {
                    totalRealizedPnl = calcPnl
                }
            }

            let status: TradeStatus = isFullyClosed
                ? (totalRealizedPnl > 0 ? .win : (totalRealizedPnl < 0 ? .loss : .breakeven))
                : .open
            let durMs = isFullyClosed ? Int64(max(0, latestCloseDate.timeIntervalSince(earliestOpenDate) * 1000)) : nil
            let finalClosedAt = isFullyClosed ? latestCloseDate : nil

            let trade = Trade(
                key: "exness_\(posId)",
                accountId: journalAccId,
                symbol: sym,
                assetClass: assetClass,
                direction: tradeDir,
                status: status,
                openedAt: earliestOpenDate,
                closedAt: finalClosedAt,
                quantity: volume,
                openQuantity: isFullyClosed ? 0 : remainingOpenVolume,
                avgEntry: entryPrice,
                avgExit: avgExit,
                grossPnl: totalRealizedPnl,
                fees: 0,
                swap: nil,
                netPnl: totalRealizedPnl,
                executionCount: execIds.count,
                executionIds: execIds,
                exits: exits,
                durationMs: durMs,
                playbookId: defaultPlaybookId,
                stopLoss: sltp?.sl,
                profitTarget: sltp?.tp
            )
            directTrades.append(trade)
        }

        // 7. Parse active Snapshot positions (if not already covered in deals)
        for p in snapshotPositions {
            guard let posId = parseId(p["position_id"]) ?? parseId(p["id"]), !posId.isEmpty else { continue }
            let (slFromPos, tpFromPos) = extractSltp(from: p)
            let sltp = positionSltpMap[posId]
            let resolvedSl = slFromPos ?? sltp?.sl
            let resolvedTp = tpFromPos ?? sltp?.tp

            let stateStr = (p["state"] as? String ?? "").lowercased()
            let isClosedState = stateStr == "closed" || stateStr == "close" || p["close_time"] != nil || p["closed_at"] != nil

            if let existingIdx = directTrades.firstIndex(where: { $0.key == "exness_\(posId)" }) {
                // If already marked as closed by deals in Step 6, NEVER resurrect back to open!
                if directTrades[existingIdx].status.isClosed {
                    if let sl = resolvedSl, directTrades[existingIdx].stopLoss == nil {
                        directTrades[existingIdx].stopLoss = sl
                    }
                    if let tp = resolvedTp, directTrades[existingIdx].profitTarget == nil {
                        directTrades[existingIdx].profitTarget = tp
                    }
                    continue
                }

                // If snapshot explicitly reports position closed, complete it
                if isClosedState {
                    directTrades[existingIdx].status = directTrades[existingIdx].netPnl > 0 ? .win : (directTrades[existingIdx].netPnl < 0 ? .loss : .breakeven)
                    directTrades[existingIdx].openQuantity = 0
                    directTrades[existingIdx].closedAt = parseDate(p["close_time"]) ?? parseDate(p["closed_at"]) ?? Date()
                    continue
                }

                if let liveVol = parseDecimal(p["volume"]), liveVol > Decimal(0.000001) {
                    directTrades[existingIdx].openQuantity = min(liveVol, directTrades[existingIdx].quantity)
                    directTrades[existingIdx].status = .open
                    directTrades[existingIdx].closedAt = nil
                } else {
                    directTrades[existingIdx].status = directTrades[existingIdx].netPnl > 0 ? .win : (directTrades[existingIdx].netPnl < 0 ? .loss : .breakeven)
                    directTrades[existingIdx].openQuantity = 0
                    directTrades[existingIdx].closedAt = parseDate(p["close_time"]) ?? parseDate(p["closed_at"]) ?? Date()
                }
                if let sl = resolvedSl, directTrades[existingIdx].stopLoss == nil {
                    directTrades[existingIdx].stopLoss = sl
                }
                if let tp = resolvedTp, directTrades[existingIdx].profitTarget == nil {
                    directTrades[existingIdx].profitTarget = tp
                }
                continue
            }

            // If position is closed and wasn't in deals, skip creating an open trade
            if isClosedState {
                continue
            }

            let sym = (p["instrument"] as? String) ?? "UNKNOWN"
            let assetClass = assetClassForSymbol(sym)
            let dirStr = (p["direction"] as? String ?? "buy").lowercased()
            let tradeDir: TradeDirection = (dirStr == "sell") ? .short : .long
            let price = parseDecimal(p["open_price"]) ?? 0
            let volume = parseDecimal(p["volume"]) ?? 0.01
            let openDate = parseDate(p["create_time"]) ?? Date()

            let execId = "exness_pos_\(posId)"
            let fillHash = "\(journalAccId)|\(sym)|\(dirStr)|\(volume)|\(price)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let fill = Execution(
                id: execId,
                accountId: journalAccId,
                symbol: sym,
                side: tradeDir == .short ? .sell : .buy,
                quantity: volume,
                price: price,
                fee: 0,
                swap: nil,
                executedAt: openDate,
                assetClass: assetClass,
                source: "exness",
                contentHash: fillHash
            )
            newExecutions.append(fill)

            let openTrade = Trade(
                key: "exness_\(posId)",
                accountId: journalAccId,
                symbol: sym,
                assetClass: assetClass,
                direction: tradeDir,
                status: .open,
                openedAt: openDate,
                closedAt: nil,
                quantity: volume,
                openQuantity: volume,
                avgEntry: price,
                avgExit: nil,
                grossPnl: 0,
                fees: 0,
                swap: nil,
                netPnl: 0,
                executionCount: 1,
                executionIds: [execId],
                exits: [],
                durationMs: nil,
                playbookId: defaultPlaybookId,
                stopLoss: resolvedSl,
                profitTarget: resolvedTp
            )
            directTrades.append(openTrade)
        }

        // 8. Ingest into TradeDataStore
        var mergedAccountTradesForUpload: [Trade] = []
        await MainActor.run {
            let dataStore = TradeDataStore.shared

            var currentTrades = dataStore.trades
            var tradesMutated = false

            // Check for any previously open Exness positions that are NO LONGER in active broker snapshot
            if snapshotResult.statusCode == 200 {
                let activePositionIds = Set(snapshotPositions.compactMap { parseId($0["position_id"]) ?? parseId($0["id"]) })
                for idx in 0..<currentTrades.count {
                    if currentTrades[idx].accountId == journalAccId &&
                       currentTrades[idx].key.hasPrefix("exness_") &&
                       currentTrades[idx].status == .open {
                        let posId = String(currentTrades[idx].key.dropFirst("exness_".count))
                        if !activePositionIds.contains(posId) && !directTrades.contains(where: { $0.key == currentTrades[idx].key }) {
                            // Only finalize from snapshot disappearance if we actually have an exit price or non-zero P&L
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

            // A. Merge direct trades with broker-reported P&L
            if !directTrades.isEmpty {
                let defaultPbId = dataStore.defaultPlaybook?.id
                for t in directTrades {
                    var tradeToMerge = t
                    if let idx = currentTrades.firstIndex(where: { $0.key == tradeToMerge.key || $0.id == tradeToMerge.id }) {
                        let existing = currentTrades[idx]

                        // Safeguard: If existing trade in journal was genuinely closed (with valid exit or non-zero P&L),
                        // and incoming tradeToMerge is reported as .open (e.g. stale snapshot or delayed sync),
                        // PRESERVE the closed state! Never regress a closed trade back to open!
                        if existing.status.isClosed && (existing.avgExit != nil || existing.netPnl != 0) && tradeToMerge.status == .open {
                            tradeToMerge.status = existing.status
                            tradeToMerge.closedAt = existing.closedAt ?? Date()
                            tradeToMerge.openQuantity = 0
                            tradeToMerge.avgExit = tradeToMerge.avgExit ?? existing.avgExit
                            if existing.netPnl != 0 {
                                tradeToMerge.netPnl = existing.netPnl
                                tradeToMerge.grossPnl = existing.grossPnl
                            }
                        }

                        // 1. Playbook
                        if let existingPbId = existing.playbookId, !existingPbId.isEmpty {
                            tradeToMerge.playbookId = existingPbId
                        } else if tradeToMerge.playbookId == nil {
                            tradeToMerge.playbookId = defaultPbId
                        }

                        // 2. User Annotations (Notes, Tags, Mistakes, Rating, ReviewedAt)
                        if let existingNotes = existing.notes, !existingNotes.isEmpty {
                            tradeToMerge.notes = existingNotes
                        }
                        if !existing.tags.isEmpty {
                            tradeToMerge.tags = Array(Set(existing.tags + tradeToMerge.tags))
                        }
                        if !existing.mistakes.isEmpty {
                            tradeToMerge.mistakes = existing.mistakes
                        }
                        if let r = existing.rating {
                            tradeToMerge.rating = r
                        }
                        if let rev = existing.reviewedAt {
                            tradeToMerge.reviewedAt = rev
                        }

                        // 3. SL / TP Priority:
                        // Priority 1: Broker-reported SL/TP (tradeToMerge.stopLoss / profitTarget from Exness)
                        // Priority 2: User manually entered SL/TP (existing.stopLoss / existing.profitTarget)
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
            }
            if !directTrades.isEmpty || tradesMutated {
                dataStore.trades = currentTrades
                dataStore.deduplicateTrades()
            }
            mergedAccountTradesForUpload = dataStore.trades.filter { $0.accountId == journalAccId }

            // B. Import execution fills
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
            }

            // C. Invalidate performance caches and persist
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
        }

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
}
