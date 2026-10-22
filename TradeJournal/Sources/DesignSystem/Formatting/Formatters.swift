import Foundation
import SwiftUI

public enum Formatters {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.currencySymbol = "$"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private static let inputNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 5
        return f
    }()
    
    /// Formats decimal numbers for text input fields, stripping floating point precision artifacts and trailing zeros.
    public static func formatDecimalInput(_ value: Decimal?, maxDecimals: Int = 5) -> String {
        guard let v = value else { return "" }
        inputNumberFormatter.maximumFractionDigits = maxDecimals
        return inputNumberFormatter.string(from: v as NSDecimalNumber) ?? "\(v)"
    }
    
    /// Formats currency with optional Privacy Mode masking
    public static func currency(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        currencyFormatter.currencyCode = currencyCode
        currencyFormatter.currencySymbol = currencySymbol(for: currencyCode)
        let formatted = currencyFormatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
        return formatted.replacingOccurrences(of: "US$", with: "$")
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
    
    /// Returns symbol for given ISO currency code (e.g. "USD" -> "$", "EUR" -> "€", "GBP" -> "£", "VND" -> "₫")
    public static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "VND": return "₫"
        default:
            let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: code]))
            let sym = locale.currencySymbol ?? "$"
            return sym.replacingOccurrences(of: "US$", with: "$")
        }
    }
    
    /// Formats compact monetary values (e.g. +$1.2k, -€450, +£2.5M)
    public static func compactCurrency(_ value: Decimal, currency: String = "USD") -> String {
        let sym = currencySymbol(for: currency)
        let doubleVal = (value as NSDecimalNumber).doubleValue
        let prefix = value > 0 ? "+" : (value < 0 ? "-" : "")
        let absVal = abs(doubleVal)
        if absVal >= 1_000_000 {
            return String(format: "%@%@%.1fM", prefix, sym, absVal / 1_000_000)
        } else if absVal >= 1_000 {
            return String(format: "%@%@%.1fk", prefix, sym, absVal / 1_000)
        } else {
            return String(format: "%@%@%.0f", prefix, sym, absVal)
        }
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
    
    private static let mediumDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    
    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    /// Formats date and time according to designated timezone using cached formatter
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        mediumDateTimeFormatter.timeZone = timeZone
        return mediumDateTimeFormatter.string(from: date)
    }
    
    public static func formatDateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateTime(date, timeZone: timeZone)
    }
    
    public static func formatTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        shortTimeFormatter.timeZone = timeZone
        return shortTimeFormatter.string(from: date)
    }
    
    public static func dateOnly(_ date: Date, timeZone: TimeZone = .current) -> String {
        mediumDateFormatter.timeZone = timeZone
        return mediumDateFormatter.string(from: date)
    }
    
    public static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateOnly(date, timeZone: timeZone)
    }
    
    /// Formats Date into standard YYYY-MM-DD day key
    public static func isoDayString(from date: Date, timeZone: TimeZone = .current) -> String {
        isoDayFormatter.timeZone = timeZone
        return isoDayFormatter.string(from: date)
    }
    
    /// Parses Date from standard YYYY-MM-DD day key
    public static func date(fromIsoDay string: String, timeZone: TimeZone = .current) -> Date? {
        isoDayFormatter.timeZone = timeZone
        return isoDayFormatter.date(from: string)
    }
    
    /// Returns human-readable weekday name (e.g. "Monday", "Tuesday")
    public static func weekdayName(from date: Date, timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
    
    // MARK: - Account & Reference Clean Formatters
    
    /// Cleans raw broker/prop labels into standardized, professional account titles:
    /// e.g. "HighStakes Phase 1 · $100K · #123456"
    public static func cleanAccountName(_ raw: String, balance: Decimal? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Trading Account" }
        
        let lower = trimmed.lowercased()
        
        // If already well formatted with dots (e.g. "HighStakes Phase 1 · $100K · #123456"), preserve it
        if trimmed.contains(" · ") && !lower.contains("meta-trader") && !lower.contains("c-trader") {
            return trimmed
        }
        
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
        
        guard isRawPlatform || lower.contains("phase") || lower.contains("step") || lower.contains("stakes") || lower.contains("bootcamp") || lower.contains("growth") else {
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
        let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            suffix = String(trimmed[range])
        }
        
        let pkg: String = {
            if lower.contains("high stakes") || lower.contains("highstakes") || lower.contains("high-stakes") {
                return "High Stakes"
            }
            if lower.contains("hyper growth") || lower.contains("hypergrowth") || lower.contains("hyper-growth") {
                return "Hyper Growth"
            }
            if lower.contains("bootcamp") || lower.contains("boot camp") {
                return "Bootcamp"
            }
            if lower.contains("instant") {
                return "Instant Funding"
            }
            if lower.hasPrefix("ftmo") {
                return "FTMO \(platformTag)"
            }
            return "The5ers \(platformTag)"
        }()
        
        let phase: String = {
            if lower.contains("step 1") || lower.contains("step1") || lower.contains("phase 1") || lower.contains("phase1") || lower.contains("evaluation") {
                return "Phase 1"
            }
            if lower.contains("step 2") || lower.contains("step2") || lower.contains("phase 2") || lower.contains("phase2") || lower.contains("verification") {
                return "Phase 2"
            }
            if lower.contains("funded") || lower.contains("live") || lower.contains("master") {
                return "Funded"
            }
            return ""
        }()
        
        var components: [String] = [pkg]
        if !phase.isEmpty {
            components.append(phase)
        }
        
        if let b = balance, b > 0 {
            let bInt = NSDecimalNumber(decimal: b).intValue
            if bInt >= 1000 && bInt % 1000 == 0 {
                components.append("$\(bInt / 1000)K")
            } else {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = "USD"
                formatter.maximumFractionDigits = 0
                if let formatted = formatter.string(from: b as NSDecimalNumber) {
                    components.append(formatted)
                }
            }
        }
        
        if !suffix.isEmpty {
            components.append("#\(suffix)")
        }
        
        return components.joined(separator: " - ")
    }
    
    /// Produces a concise account label tailored for tight navigation bars (e.g. "HighStakes P1 · $50K" or "cTrader #7657")
    public static func compactAccountName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Account" }
        
        // Handle dash-separated format: [Package, Phase, Size, #Number]
        let sep = trimmed.contains(" - ") ? " - " : (trimmed.contains(" · ") ? " · " : "")
        if !sep.isEmpty {
            let parts = trimmed.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 4 {
                let p0 = parts[0].replacingOccurrences(of: " ", with: "")
                let p1 = parts[1].replacingOccurrences(of: "Phase ", with: "P").replacingOccurrences(of: "Step ", with: "P")
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 3 {
                let p0 = parts[0].replacingOccurrences(of: " ", with: "")
                let p1 = parts[1]
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 2 {
                return "\(parts[0]) \(parts[1])"
            }
        }
        
        let cleaned = cleanAccountName(trimmed)
        if cleaned.contains(" - ") {
            return compactAccountName(cleaned)
        }
        return cleaned
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
