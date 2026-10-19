import Foundation
import SwiftUI

public enum Formatters {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()
    
    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 5
        f.minimumFractionDigits = 2
        return f
    }()
    
    /// Formats currency with optional Privacy Mode masking
    public static func currency(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        currencyFormatter.currencyCode = currencyCode
        return currencyFormatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
    
    public static func formatCurrency(_ amount: Decimal, currency: String = "USD", isPrivate: Bool = false) -> String {
        Formatters.currency(amount, currencyCode: currency, isPrivate: isPrivate)
    }
    
    public static func formatCurrency(_ amount: Decimal?, currency: String = "USD", isPrivate: Bool = false) -> String {
        guard let a = amount else { return "-" }
        return Formatters.currency(a, currencyCode: currency, isPrivate: isPrivate)
    }
    
    /// Formats P&L with explicit +/- prefix
    public static func pnl(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        let sign = amount > 0 ? "+" : ""
        return "\(sign)\(currency(amount, currencyCode: currencyCode, isPrivate: false))"
    }
    
    public static func formatPnL(_ amount: Decimal, currency: String = "USD", isPrivate: Bool = false) -> String {
        Formatters.pnl(amount, currencyCode: currency, isPrivate: isPrivate)
    }
    
    public static func formatPnL(_ amount: Decimal?, currency: String = "USD", isPrivate: Bool = false) -> String {
        guard let a = amount else { return "-" }
        return Formatters.pnl(a, currencyCode: currency, isPrivate: isPrivate)
    }
    
    /// Formats percentage value (e.g. 0.542 -> "54.2%")
    public static func percentage(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "n/a" }
        return percentFormatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }
    
    public static func formatPercent(_ value: Decimal?) -> String {
        guard let val = value else { return "n/a" }
        return percentage((val as NSDecimalNumber).doubleValue)
    }
    
    public static func formatPercent(_ value: Double?) -> String {
        percentage(value)
    }
    
    public static func percent(_ value: Double?) -> String {
        formatPercent(value)
    }
    
    public static func percent(_ value: Decimal?) -> String {
        formatPercent(value)
    }
    
    public static func pnlColor(_ amount: Decimal) -> Color {
        if amount > 0 {
            return AppColors.profit
        } else if amount < 0 {
            return AppColors.loss
        } else {
            return AppColors.breakeven
        }
    }
    
    public static func statusColor(_ status: TradeStatus) -> Color {
        switch status {
        case .win:
            return AppColors.profit
        case .loss:
            return AppColors.loss
        case .breakeven:
            return AppColors.breakeven
        case .open:
            return AppColors.brand
        }
    }
    
    /// Formats execution price (2 to 5 decimal places for Forex/Crypto)
    public static func price(_ value: Decimal) -> String {
        return priceFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    public static func formatNumber(_ value: Decimal) -> String {
        return priceFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    public static func formatNumber(_ value: Double) -> String {
        return priceFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    public static func formatNumber(_ value: Decimal?) -> String {
        guard let v = value else { return "-" }
        return formatNumber(v)
    }
    
    public static func formatNumber(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return formatNumber(v)
    }
    
    /// Formats holding duration from milliseconds (e.g. 1d 4h, 2h 15m, 45m 10s)
    public static func formatDuration(ms: Int64?) -> String {
        guard let ms = ms, ms > 0 else { return "-" }
        let totalSeconds = ms / 1000
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
    
    public static func formatDuration(ms: Double?) -> String {
        guard let ms = ms, ms > 0 else { return "-" }
        return formatDuration(ms: Int64(ms))
    }
    
    /// Formats date and time according to designated timezone
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.timeZone = timeZone
        return f.string(from: date)
    }
    
    public static func formatDateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateTime(date, timeZone: timeZone)
    }
    
    public static func formatTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.timeZone = timeZone
        return f.string(from: date)
    }
    
    public static func dateOnly(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = timeZone
        return f.string(from: date)
    }
    
    public static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateOnly(date, timeZone: timeZone)
    }
    
    // MARK: - Account & Reference Clean Formatters
    
    /// Cleans raw broker/prop labels (such as "meta-trader-5 · …7657" or "Meta-Trade-5-......7657")
    /// into professional, human-readable account titles.
    public static func cleanAccountName(_ raw: String, balance: Decimal? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Trading Account" }
        
        let lower = trimmed.lowercased()
        
        let isRawIdOrPrefix = lower.hasPrefix("account the5ers_") ||
                              lower.hasPrefix("account ") ||
                              lower.hasPrefix("the5ers_")
        
        let isRawPlatform = lower.contains("meta-trader") ||
                            lower.contains("meta-trade") ||
                            lower.contains("metatrader") ||
                            lower.contains("c-trader") ||
                            lower.contains("ctrader") ||
                            lower.contains("trader-evolution") ||
                            lower.contains("traderevolution") ||
                            isRawIdOrPrefix
        
        guard isRawPlatform else {
            return trimmed
        }
        
        let platformTag: String
        if lower.contains("meta-trader-5") || lower.contains("meta-trade-5") || lower.contains("mt5") {
            platformTag = "MT5"
        } else if lower.contains("meta-trader-4") || lower.contains("meta-trade-4") || lower.contains("mt4") {
            platformTag = "MT4"
        } else if lower.contains("c-trader") || lower.contains("ctrader") {
            platformTag = "cTrader"
        } else if lower.contains("trader-evolution") || lower.contains("traderevolution") {
            platformTag = "TraderEvolution"
        } else {
            platformTag = "MT5"
        }
        
        var suffix = ""
        let pattern = #"(?:…|\.{3}|[-_·\s])?(\d{3,12})\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            suffix = String(trimmed[range])
        }
        
        var prefix = "The5ers \(platformTag)"
        if lower.hasPrefix("ftmo") {
            prefix = "FTMO \(platformTag)"
        }
        
        var sizePart: String? = nil
        if let b = balance, b > 0 {
            let num = b as NSDecimalNumber
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 0
            sizePart = formatter.string(from: num)
        }
        
        var components: [String] = [prefix]
        if let s = sizePart {
            components.append(s)
        }
        if !suffix.isEmpty {
            components.append("#\(suffix)")
        }
        
        return components.joined(separator: " · ")
    }
    
    /// Formats technical UUIDs, SHA256 hashes, or internal database keys into clean references
    public static func formatReference(_ ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        if trimmed.hasPrefix("the5ers_purchase_") {
            let hash = String(trimmed.dropFirst("the5ers_purchase_".count))
            return "Order #\(hash.prefix(8))"
        }
        if trimmed.hasPrefix("the5ers_payout_") {
            let hash = String(trimmed.dropFirst("the5ers_payout_".count))
            return "Payout #\(hash.prefix(8))"
        }
        if trimmed.hasPrefix("the5ers_received_") || trimmed.hasPrefix("the5ers_rcpt_") {
            let rest = trimmed.components(separatedBy: "_").last ?? trimmed
            return "Receipt #\(rest.prefix(8))"
        }
        if trimmed.hasPrefix("THE5ERS-") {
            let rest = String(trimmed.dropFirst("THE5ERS-".count))
            return "THE5ERS #\(rest.prefix(8))"
        }
        if trimmed.count > 24 && !trimmed.contains(" ") {
            return "#\(trimmed.prefix(8))"
        }
        return trimmed
    }
    
    /// Formats entity IDs cleanly
    public static func formatEntityId(_ id: String) -> String {
        if id.hasPrefix("the5ers_") {
            let sub = String(id.dropFirst(8))
            return sub.count > 12 ? "#\(sub.prefix(8))" : sub
        }
        if id.count > 16 {
            return "#\(id.prefix(8))"
        }
        return id
    }
}
