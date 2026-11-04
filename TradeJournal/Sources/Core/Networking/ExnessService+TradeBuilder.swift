import Foundation

// MARK: - Exness Trade Reconstruction & Deal Matching Extension
extension ExnessService {
    
    internal struct DealGroup {
        let positionId: String
        var symbol: String
        var openDeals: [[String: Any]]
        var closeDeals: [[String: Any]]
    }

    internal func parseId(_ val: Any?) -> String? {
        if let s = val as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            return s.trimmingCharacters(in: .whitespaces)
        }
        if let i = val as? Int { return String(i) }
        if let i64 = val as? Int64 { return String(i64) }
        if let num = val as? NSNumber { return num.stringValue }
        return nil
    }

    internal func parseInt(_ val: Any?) -> Int? {
        if let i = val as? Int { return i }
        if let i64 = val as? Int64 { return Int(i64) }
        if let num = val as? NSNumber { return num.intValue }
        if let s = val as? String, let i = Int(s) { return i }
        return nil
    }

    internal func extractSltp(from dict: [String: Any]) -> (sl: Decimal?, tp: Decimal?) {
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

    internal func buildPositionSltpMap(
        allOrders: [[String: Any]],
        snapshotPositions: [[String: Any]],
        allDeals: [[String: Any]]
    ) -> [String: (sl: Decimal?, tp: Decimal?)] {
        var positionSltpMap: [String: (sl: Decimal?, tp: Decimal?)] = [:]

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

        for p in snapshotPositions {
            let (sl, tp) = extractSltp(from: p)
            guard sl != nil || tp != nil else { continue }
            if let posId = parseId(p["position_id"]) ?? parseId(p["positionId"]) {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
        }

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

        return positionSltpMap
    }

    internal func groupDealsByPosition(_ allDeals: [[String: Any]]) -> [String: DealGroup] {
        var groups: [String: DealGroup] = [:]
        for d in allDeals {
            let type = (d["type"] as? String ?? "").lowercased()
            if type == "balance" || type.contains("deposit") || type.contains("withdraw") || type == "null_compensation" || type == "credit" || type == "bonus" {
                continue
            }
            guard let posId = parseId(d["position_id"]) ?? parseId(d["positionId"]), !posId.isEmpty else { continue }
            let sym = (d["instrument"] as? String) ?? (d["symbol"] as? String) ?? "UNKNOWN"

            if groups[posId] == nil {
                groups[posId] = DealGroup(positionId: posId, symbol: sym, openDeals: [], closeDeals: [])
            }

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
        return groups
    }

    internal func buildReconciledTrade(
        posId: String,
        g: DealGroup,
        journalAccId: String,
        defaultPlaybookId: String?,
        sltp: (sl: Decimal?, tp: Decimal?)?,
        newExecutions: inout [Execution]
    ) -> Trade {
        let sym = g.symbol
        let assetClass = assetClassForSymbol(sym)
        var execIds: [String] = []

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

        return Trade(
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
    }

    internal func reconcileSnapshotPositions(
        snapshotPositions: [[String: Any]],
        directTrades: inout [Trade],
        positionSltpMap: [String: (sl: Decimal?, tp: Decimal?)],
        journalAccId: String,
        defaultPlaybookId: String?,
        newExecutions: inout [Execution]
    ) {
        for p in snapshotPositions {
            guard let posId = parseId(p["position_id"]) ?? parseId(p["id"]), !posId.isEmpty else { continue }
            let (slFromPos, tpFromPos) = extractSltp(from: p)
            let sltp = positionSltpMap[posId]
            let resolvedSl = slFromPos ?? sltp?.sl
            let resolvedTp = tpFromPos ?? sltp?.tp

            let stateStr = (p["state"] as? String ?? "").lowercased()
            let isClosedState = stateStr == "closed" || stateStr == "close" || p["close_time"] != nil || p["closed_at"] != nil

            if let existingIdx = directTrades.firstIndex(where: { $0.key == "exness_\(posId)" }) {
                if directTrades[existingIdx].status.isClosed {
                    if let sl = resolvedSl, directTrades[existingIdx].stopLoss == nil {
                        directTrades[existingIdx].stopLoss = sl
                    }
                    if let tp = resolvedTp, directTrades[existingIdx].profitTarget == nil {
                        directTrades[existingIdx].profitTarget = tp
                    }
                    continue
                }

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
    }
}
