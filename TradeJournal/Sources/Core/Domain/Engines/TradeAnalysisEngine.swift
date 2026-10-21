import Foundation

public typealias AnalysisFilters = [String: String]

public enum Dimension: String, CaseIterable, Equatable {
    case symbol = "symbol"
    case playbook = "playbook"
    case tag = "tag"
    case mistake = "mistake"
    case direction = "direction"
    case assetClass = "assetClass"
    case weekday = "weekday"
    case month = "month"
    case entryHour = "entryHour"
    case exitHour = "exitHour"
    case entry15 = "entry15"
    case exit15 = "exit15"
    case duration = "duration"
    case quantity = "quantity"
    case entryPrice = "entryPrice"
    case exitPrice = "exitPrice"
    case realizedR = "realizedR"
    case plannedR = "plannedR"
    case outcome = "outcome"
    
    public var label: String {
        switch self {
        case .symbol: return "Symbol"
        case .playbook: return "Strategy"
        case .tag: return "Tag"
        case .mistake: return "Mistake"
        case .direction: return "Direction"
        case .assetClass: return "Asset class"
        case .weekday: return "Weekday"
        case .month: return "Month"
        case .entryHour: return "Entry hour"
        case .exitHour: return "Exit hour"
        case .entry15: return "Entry · 15 minutes"
        case .exit15: return "Exit · 15 minutes"
        case .duration: return "Holding time"
        case .quantity: return "Position size"
        case .entryPrice: return "Entry price"
        case .exitPrice: return "Exit price"
        case .realizedR: return "Realized R"
        case .plannedR: return "Planned R"
        case .outcome: return "Outcome"
        }
    }
}

public struct GroupSummary: Equatable, Sendable {
    public let trades: Int
    public let netPnl: Decimal
    public let winRate: Double?
    public let avgRealizedR: Double?
    public let avgPlannedR: Double?
    public let avgDurationMs: Double?
    public let volume: Decimal
    public let profitFactor: Double?
    public let noLosses: Bool
}

public struct GroupAnalysisResult: Equatable, Sendable {
    public let row: String
    public let column: String
    public let summary: GroupSummary
}

/// Ported 1:1 from `packages/core/src/analysis.ts`.
public enum TradeAnalysisEngine {
    
    public static func tradeRisk(trade: Trade) -> Decimal? {
        guard let stop = trade.stopLoss else { return nil }
        
        let multiplier: Decimal
        if let explicitMultiplier = trade.contractMultiplier {
            multiplier = explicitMultiplier
        } else {
            let derivatives: Set<String> = ["futures", "option", "cfd", "forex"]
            let spec = AssetContractEngine.spec(for: trade.symbol)
            if spec.contractSize == 1, let asset = trade.assetClass, derivatives.contains(asset) {
                // Derivative without a known contract size: risk cannot be expressed in money.
                return nil
            }
            multiplier = spec.contractSize
        }
        
        guard multiplier > 0 && trade.quantity > 0 else { return nil }
        
        let distance: Decimal = (trade.avgEntry - stop) * (trade.direction == .long ? 1 : -1)
        return distance > 0 ? (distance * trade.quantity * multiplier) : nil
    }
    
    public static func tradeR(trade: Trade) -> Double? {
        guard let risk = tradeRisk(trade: trade), risk > 0, trade.status != .open else { return nil }
        return NSDecimalNumber(decimal: trade.netPnl).doubleValue / NSDecimalNumber(decimal: risk).doubleValue
    }
    
    public static func plannedR(trade: Trade) -> Double? {
        guard let stop = trade.stopLoss, let target = trade.profitTarget else { return nil }
        
        let sign: Decimal = trade.direction == .long ? 1 : -1
        let risk = (trade.avgEntry - stop) * sign
        let reward = (target - trade.avgEntry) * sign
        
        guard risk > 0 && reward >= 0 else { return nil }
        return NSDecimalNumber(decimal: reward).doubleValue / NSDecimalNumber(decimal: risk).doubleValue
    }
    
    public static func clockTime(iso: String, timeZone: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0) ?? .current
        return formatter.string(from: date)
    }
    
    private static func list(_ value: String?) -> [String] {
        guard let val = value, !val.isEmpty else { return [] }
        return val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    private static func within(_ value: Double?, min: String?, max: String?) -> Bool {
        if min == nil && max == nil { return true }
        guard let val = value, val.isFinite else { return false }
        if let minStr = min, let minVal = Double(minStr), val < minVal { return false }
        if let maxStr = max, let maxVal = Double(maxStr), val > maxVal { return false }
        return true
    }
    
    private static func withinDecimal(_ value: Decimal?, min: String?, max: String?) -> Bool {
        guard let val = value else { return min == nil && max == nil ? true : false }
        let d = NSDecimalNumber(decimal: val).doubleValue
        return within(d, min: min, max: max)
    }
    
    private static func inTime(iso: String?, after: String?, before: String?, tz: String) -> Bool {
        if after == nil && before == nil { return true }
        guard let isoStr = iso else { return false }
        let t = clockTime(iso: isoStr, timeZone: tz)
        if let a = after, let b = before, a > b {
            return t >= a || t <= b
        }
        if let a = after, t < a { return false }
        if let b = before, t > b { return false }
        return true
    }
    
    public static func matchesFilters(trade: Trade, filters: AnalysisFilters, timeZone: String = "UTC") -> Bool {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let openedIso = isoFormatter.string(from: trade.openedAt)
        let closedIso = trade.closedAt.map(isoFormatter.string)
        
        if let accounts = filters["accounts"], !accounts.isEmpty {
            if !list(accounts).contains(trade.accountId) { return false }
        }
        
        let from = filters["from"]
        let to = filters["to"]
        if from != nil || to != nil {
            let dayDate = trade.closedAt ?? trade.openedAt
            let day = AggregateEngine.dayKeyOf(date: dayDate, timeZone: timeZone)
            if let f = from, day < f { return false }
            if let t = to, day > t { return false }
        }
        
        if let sym = filters["symbol"], !sym.isEmpty {
            let allowed = list(sym.uppercased())
            if !allowed.contains(trade.symbol.uppercased()) { return false }
        }
        
        if let exSym = filters["excludeSymbol"], !exSym.isEmpty {
            let excluded = list(exSym.uppercased())
            if excluded.contains(trade.symbol.uppercased()) { return false }
        }
        
        if let tag = filters["tag"], !tag.isEmpty {
            let requiredTags = list(tag)
            for req in requiredTags {
                if !trade.tags.contains(req) { return false }
            }
        }
        
        if let mistake = filters["mistake"], !mistake.isEmpty {
            let requiredMistakes = list(mistake)
            for req in requiredMistakes {
                if !trade.mistakes.contains(req) { return false }
            }
        }
        
        if let playbookId = filters["playbookId"], !playbookId.isEmpty {
            if trade.playbookId != playbookId { return false }
        }
        
        if let dirStr = filters["direction"], !dirStr.isEmpty {
            if trade.direction.rawValue != dirStr { return false }
        }
        
        if let statusStr = filters["status"], !statusStr.isEmpty {
            if statusStr == "closed" {
                if trade.status == .open { return false }
            } else if trade.status.rawValue != statusStr {
                return false
            }
        }
        
        if let asset = filters["assetClass"], !asset.isEmpty {
            if trade.assetClass != asset { return false }
        }
        
        if let reviewed = filters["reviewed"], !reviewed.isEmpty {
            let isReviewed = trade.reviewedAt != nil
            if (reviewed == "yes") != isReviewed { return false }
        }
        
        let ratingDouble = trade.rating.map(Double.init)
        if !within(ratingDouble, min: filters["ratingMin"], max: filters["ratingMax"]) { return false }
        if !withinDecimal(trade.quantity, min: filters["quantityMin"], max: filters["quantityMax"]) { return false }
        if !withinDecimal(trade.avgEntry, min: filters["entryMin"], max: filters["entryMax"]) { return false }
        if !withinDecimal(trade.avgExit, min: filters["exitMin"], max: filters["exitMax"]) { return false }
        
        let durationMinutes = trade.durationMs.map { Double($0) / 60000.0 }
        if !within(durationMinutes, min: filters["durationMin"], max: filters["durationMax"]) { return false }
        
        if filters["rMin"] != nil || filters["rMax"] != nil {
            if !within(tradeR(trade: trade), min: filters["rMin"], max: filters["rMax"]) { return false }
        }
        if filters["plannedRMin"] != nil || filters["plannedRMax"] != nil {
            if !within(plannedR(trade: trade), min: filters["plannedRMin"], max: filters["plannedRMax"]) { return false }
        }
        
        if !withinDecimal(trade.netPnl, min: filters["pnlMin"], max: filters["pnlMax"]) { return false }
        
        if let weekdays = filters["weekdays"], !weekdays.isEmpty {
            let openDay = AggregateEngine.dayKeyOf(date: trade.openedAt, timeZone: timeZone)
            let weekdayIndex = CalendarInsightsEngine.closingWeekday(openDay)
            if !list(weekdays).contains(String(weekdayIndex)) { return false }
        }
        
        if !inTime(iso: openedIso, after: filters["entryAfter"], before: filters["entryBefore"], tz: timeZone) { return false }
        if !inTime(iso: closedIso, after: filters["exitAfter"], before: filters["exitBefore"], tz: timeZone) { return false }
        
        return true
    }
    
    private static func bands(_ n: Double?, bounds: [Double], labels: [String]) -> String {
        guard let val = n, val.isFinite else { return "Unspecified" }
        for (i, b) in bounds.enumerated() {
            if val < b { return labels[i] }
        }
        return labels.last ?? "Unspecified"
    }
    
    public static func dimensionKeys(trade: Trade, dimension: Dimension, timeZone: String) -> [String] {
        let bucketTime = { (date: Date?, step: Int) -> String in
            guard let d = date else { return "Open" }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let time = clockTime(iso: f.string(from: d), timeZone: timeZone)
            let prefix = time.prefix(3)
            let minute = Int(time.suffix(2)) ?? 0
            let bucket = (minute / step) * step
            return "\(prefix)\(String(format: "%02d", bucket))"
        }
        
        switch dimension {
        case .tag:
            return trade.tags.isEmpty ? ["Untagged"] : trade.tags
        case .mistake:
            return trade.mistakes.isEmpty ? ["None"] : trade.mistakes
        case .playbook:
            return [trade.playbookId ?? "Unassigned"]
        case .symbol:
            return [trade.symbol]
        case .direction:
            return [trade.direction.rawValue]
        case .outcome:
            return [trade.status.rawValue]
        case .assetClass:
            return [trade.assetClass ?? "Unspecified"]
        case .month:
            let refDate = trade.closedAt ?? trade.openedAt
            let dayKey = AggregateEngine.dayKeyOf(date: refDate, timeZone: timeZone)
            return [String(dayKey.prefix(7))]
        case .weekday:
            let dayKey = AggregateEngine.dayKeyOf(date: trade.openedAt, timeZone: timeZone)
            let weekdayIndex = CalendarInsightsEngine.closingWeekday(dayKey)
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return [names[weekdayIndex]]
        case .entryHour:
            return [bucketTime(trade.openedAt, 60)]
        case .exitHour:
            return [bucketTime(trade.closedAt, 60)]
        case .entry15:
            return [bucketTime(trade.openedAt, 15)]
        case .exit15:
            return [bucketTime(trade.closedAt, 15)]
        case .duration:
            let minutes = trade.durationMs.map { Double($0) / 60000.0 }
            return [bands(minutes, bounds: [1, 5, 15, 60, 240, 1440], labels: ["<1m", "1–5m", "5–15m", "15–60m", "1–4h", "4–24h", "1d+"])]
        case .quantity:
            let q = NSDecimalNumber(decimal: trade.quantity).doubleValue
            return [bands(q, bounds: [1, 10, 100, 1000], labels: ["<1", "1–10", "10–100", "100–1,000", "1,000+"])]
        case .entryPrice:
            let p = NSDecimalNumber(decimal: trade.avgEntry).doubleValue
            return [bands(p, bounds: [1, 10, 50, 100, 500], labels: ["<1", "1–10", "10–50", "50–100", "100–500", "500+"])]
        case .exitPrice:
            let p = trade.avgExit.map { NSDecimalNumber(decimal: $0).doubleValue }
            return [bands(p, bounds: [1, 10, 50, 100, 500], labels: ["<1", "1–10", "10–50", "50–100", "100–500", "500+"])]
        case .realizedR:
            return [bands(tradeR(trade: trade), bounds: [-2, -1, 0, 1, 2, 3], labels: ["<-2R", "-2 to -1R", "-1 to 0R", "0–1R", "1–2R", "2–3R", "3R+"])]
        case .plannedR:
            return [bands(plannedR(trade: trade), bounds: [-2, -1, 0, 1, 2, 3], labels: ["<-2R", "-2 to -1R", "-1 to 0R", "0–1R", "1–2R", "2–3R", "3R+"])]
        }
    }
    
    public static func summarizeGroup(all: [Trade]) -> GroupSummary {
        let ts = all.filter { $0.status != .open }
        let mean = { (ns: [Double?]) -> Double? in
            let valid = ns.compactMap { $0 }.filter { $0.isFinite }
            return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        }
        let profit = ts.reduce(Decimal(0)) { $0 + max(0, $1.netPnl) }
        let loss = ts.reduce(Decimal(0)) { $0 - min(0, $1.netPnl) }
        let net = ts.reduce(Decimal(0)) { $0 + $1.netPnl }
        let winRate = !ts.isEmpty ? Double(ts.filter { $0.status == .win }.count) / Double(ts.count) : nil
        let profitFactor = loss > 0 ? (NSDecimalNumber(decimal: profit).doubleValue / NSDecimalNumber(decimal: loss).doubleValue) : nil
        let noLosses = profit > 0 && loss == 0
        let avgDuration = mean(ts.map { $0.durationMs.map(Double.init) })
        let avgR = mean(ts.map { tradeR(trade: $0) })
        let avgPlanR = mean(ts.map { plannedR(trade: $0) })
        let volume = ts.reduce(Decimal(0)) { $0 + $1.quantity }
        
        return GroupSummary(
            trades: ts.count,
            netPnl: net,
            winRate: winRate,
            avgRealizedR: avgR,
            avgPlannedR: avgPlanR,
            avgDurationMs: avgDuration,
            volume: volume,
            profitFactor: profitFactor,
            noLosses: noLosses
        )
    }
    
    public static func analyzeGroups(
        trades: [Trade],
        primary: Dimension,
        secondary: Dimension? = nil,
        timeZone: String = "UTC"
    ) -> [GroupAnalysisResult] {
        var groups: [String: (row: String, column: String, trades: [Trade])] = [:]
        for t in trades where t.status != .open {
            let rowKeys = Set(dimensionKeys(trade: t, dimension: primary, timeZone: timeZone))
            let colKeys: Set<String> = secondary.map { Set(dimensionKeys(trade: t, dimension: $0, timeZone: timeZone)) } ?? [""]
            for r in rowKeys {
                for c in colKeys {
                    let key = "\(r)\u{0}\(c)"
                    if var existing = groups[key] {
                        existing.trades.append(t)
                        groups[key] = existing
                    } else {
                        groups[key] = (row: r, column: c, trades: [t])
                    }
                }
            }
        }
        return groups.values.map { g in
            GroupAnalysisResult(row: g.row, column: g.column, summary: summarizeGroup(all: g.trades))
        }.sorted {
            if $0.summary.netPnl != $1.summary.netPnl {
                return $0.summary.netPnl > $1.summary.netPnl
            }
            return $0.row < $1.row
        }
    }
}
