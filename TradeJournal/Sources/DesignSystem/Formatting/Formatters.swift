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
    
    /// Formats decimal numbers for display with specified maximum decimal places.
    public static func formatDecimal(_ value: Decimal?, maxDecimals: Int = 2) -> String {
        guard let v = value else { return "0" }
        inputNumberFormatter.maximumFractionDigits = maxDecimals
        return inputNumberFormatter.string(from: v as NSDecimalNumber) ?? "\(v)"
    }
    
    /// Formats currency with optional Privacy Mode masking
    public static func currency(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        let cleanCode = (currencyCode.uppercased() == "USC" || currencyCode.uppercased() == "USCENT" || currencyCode.uppercased() == "CENT") ? "USD" : currencyCode
        currencyFormatter.currencyCode = cleanCode
        currencyFormatter.currencySymbol = currencySymbol(for: cleanCode)
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
        case "USD", "USC", "USCENT", "CENT": return "$"
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
    
    /// Formats compact chart axis values: 4000 -> "$4K", 1500 -> "$1.5K", 1000000 -> "$1M", 0 -> "$0", -2000 -> "-$2K"
    public static func compactAxisValue(_ value: Double, currency: String = "") -> String {
        guard value.isFinite else { return "" }
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""
        let sym = currency.isEmpty ? "" : currencySymbol(for: currency)
        
        if absVal >= 1_000_000 {
            let num = absVal / 1_000_000
            let formatted = num.truncatingRemainder(dividingBy: 1) == 0 ?
                String(format: "%.0fM", num) :
                String(format: "%.1fM", num)
            return "\(sign)\(sym)\(formatted)"
        } else if absVal >= 1_000 {
            let num = absVal / 1_000
            let formatted = num.truncatingRemainder(dividingBy: 1) == 0 ?
                String(format: "%.0fK", num) :
                String(format: "%.1fK", num)
            return "\(sign)\(sym)\(formatted)"
        } else if absVal == 0 {
            return "\(sym)0"
        } else {
            return "\(sign)\(sym)\(Int(round(absVal)))"
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
    
    /// Determines the standard number of decimal places for a given symbol and optional price
    public static func decimalPlaces(for symbol: String?, price: Decimal? = nil) -> Int {
        guard let s = symbol, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            if let p = price {
                return autoDetectDecimals(for: p)
            }
            return 2
        }
        return AssetContractEngine.spec(for: s).defaultDecimals
    }
    
    /// Auto-detects typical decimal places from numeric magnitude for financial instruments
    public static func autoDetectDecimals(for value: Decimal) -> Int {
        let d = (value as NSDecimalNumber).doubleValue
        if d <= 0 { return 2 }
        if d < 10.0 { return 5 }        // Forex Majors & Crosses: EURUSD 1.08542, GBPUSD 1.29845
        if d < 500.0 { return 3 }       // Forex JPY pairs (154.234), Silver (33.840), Oil (71.50)
        return 2                        // Gold (2745.50), BTC (67500.50), Indices (42350.25)
    }

    /// Formats execution price (2 to 5+ decimal places dynamically based on symbol or price magnitude)
    public static func price(_ value: Decimal, symbol: String? = nil) -> String {
        let decimals = decimalPlaces(for: symbol, price: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.usesGroupingSeparator = true
        if decimals >= 4 {
            f.minimumFractionDigits = min(4, decimals)
        } else if decimals == 3 {
            f.minimumFractionDigits = 2
        } else {
            f.minimumFractionDigits = min(2, decimals)
        }
        f.maximumFractionDigits = decimals
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    public static func price(_ value: Decimal?, symbol: String? = nil) -> String {
        guard let v = value else { return "N/A" }
        return price(v, symbol: symbol)
    }
    
    /// Formats price excursion points / pips (e.g. 15.2, 0.5)
    public static func points(_ value: Decimal) -> String {
        let num = (value as NSDecimalNumber).doubleValue
        if abs(num.truncatingRemainder(dividingBy: 1)) < 0.0001 {
            return String(format: "%.0f", num)
        } else {
            return String(format: "%.1f", num)
        }
    }
    
    public static func points(_ value: Decimal?) -> String {
        guard let v = value else { return "N/A" }
        return points(v)
    }

    public static func points(_ value: Double) -> String {
        if abs(value.truncatingRemainder(dividingBy: 1)) < 0.0001 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
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

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasicFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
        weekdayFormatter.locale = locale
        weekdayFormatter.timeZone = timeZone
        return weekdayFormatter.string(from: date)
    }
    
    // MARK: - Account & Reference Clean Formatters
    
    /// Cleans raw broker/prop labels into standardized, professional account titles:
    /// e.g. "HighStakes Phase 1 · $100K · #123456"
    public static func cleanAccountName(_ raw: String, balance: Decimal? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Trading Account" }
        
        // 1. Split existing delimited strings (' - ', ' · ', ' • ', ' | ') and perform smart deduplication
        let normalizedDelimiters: String = {
            var s = trimmed
            s = s.replacingOccurrences(of: " · ", with: " - ")
            s = s.replacingOccurrences(of: " • ", with: " - ")
            s = s.replacingOccurrences(of: " | ", with: " - ")
            // Standardize any dash with or without surrounding spaces e.g. " -$50K", "-50K", " - 1"
            let dashPattern = #"\s*-\s*"#
            if let regex = try? NSRegularExpression(pattern: dashPattern) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " - ")
            }
            return s
        }()
        let rawParts = normalizedDelimiters.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var deduplicatedParts: [String] = []
        for part in rawParts {
            let pLower = part.lowercased()
            // Skip raw platform placeholders if they appear as separate segments
            if (pLower.hasPrefix("meta-trader") || pLower.hasPrefix("c-trader") || pLower.hasPrefix("account the5ers_")) && rawParts.count > 1 {
                continue
            }
            let pNorm = pLower.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: "")
            
            let isDupe = deduplicatedParts.contains { existing in
                let eNorm = existing.lowercased()
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if eNorm == pNorm { return true }
                // If one contains the other (e.g. "highstakes50k" contains "highstakes" or "50k")
                if pNorm.count >= 3 && eNorm.contains(pNorm) { return true }
                if eNorm.count >= 3 && pNorm.contains(eNorm) { return true }
                return false
            }
            
            if !isDupe {
                deduplicatedParts.append(part)
            } else {
                // If the incoming part is more descriptive (e.g. "High Stakes 50K" vs "High Stakes"), upgrade it
                if let idx = deduplicatedParts.firstIndex(where: { existing in
                    let eNorm = existing.lowercased()
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    return pNorm.count > eNorm.count && pNorm.contains(eNorm)
                }) {
                    deduplicatedParts[idx] = part
                }
            }
        }
        
        let candidate = deduplicatedParts.joined(separator: " · ")
        let lower = candidate.lowercased()
        
        // Check if any word of 4+ characters repeats in the candidate (e.g. "highstakes" repeating)
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 }
        let hasRepeatingWord = Set(words).count != words.count
        
        // Only preserve if candidate is strictly in standard " · " format, has no hyphens or duplicate words
        let isAlreadyClean = trimmed.contains(" · ") && !trimmed.contains("-") && !hasRepeatingWord && !lower.contains("meta-trader") && !lower.contains("c-trader") && !lower.hasPrefix("the5ers_")
        if isAlreadyClean && deduplicatedParts.count >= 2 {
            return candidate
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
            return candidate
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
            if lower.contains("high stakes") || lower.contains("highstakes") || lower.contains("high-stakes") || lower.contains("high steaks") || lower.contains("highsteaks") {
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
            if lower.contains("step 2") || lower.contains("step2") || lower.contains("phase 2") || lower.contains("phase2") || lower.contains("verification") ||
               lower.contains("- 2 -") || lower.contains("- 2-") || lower.contains("-2-") || lower.contains(" - 2 ") || lower.hasSuffix("- 2") || lower.hasSuffix("-2") {
                return "Phase 2"
            }
            if lower.contains("step 3") || lower.contains("step3") || lower.contains("phase 3") || lower.contains("phase3") ||
               lower.contains("- 3 -") || lower.contains("- 3-") || lower.contains("-3-") || lower.contains(" - 3 ") || lower.hasSuffix("- 3") || lower.hasSuffix("-3") {
                return "Phase 3"
            }
            if lower.contains("funded") || lower.contains("live") || lower.contains("master") || pkg == "Instant Funding" {
                return "Funded"
            }
            if lower.contains("step 1") || lower.contains("step1") || lower.contains("phase 1") || lower.contains("phase1") || lower.contains("evaluation") ||
               lower.contains("- 1 -") || lower.contains("- 1-") || lower.contains("-1-") || lower.contains(" - 1 ") || lower.hasSuffix("- 1") || lower.hasSuffix("-1") {
                return "Phase 1"
            }
            return ""
        }()
        
        var components: [String] = [pkg]
        if !phase.isEmpty && phase != pkg {
            components.append(phase)
        }
        
        // Extract size from balance or raw string e.g. "50K", "$100k"
        let sizeCandidate: String? = {
            if let b = balance, b > 0 {
                let bInt = NSDecimalNumber(decimal: b).intValue
                if bInt >= 1000 && bInt % 1000 == 0 {
                    return "$\(bInt / 1000)K"
                }
                return "$\(bInt)"
            }
            if let regex = try? NSRegularExpression(pattern: #"(?i)\$?(\d{1,4})\s*k\b"#),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return "$\(trimmed[range].uppercased())K"
            }
            return nil
        }()
        if let sz = sizeCandidate {
            let sizeBare = sz.replacingOccurrences(of: "$", with: "").lowercased()
            let alreadyHasSize = components.contains { c in
                c.replacingOccurrences(of: "$", with: "").lowercased().contains(sizeBare)
            }
            if !alreadyHasSize {
                components.append(sz)
            }
        }
        
        if !suffix.isEmpty {
            let sNorm = suffix.replacingOccurrences(of: "#", with: "")
            if !components.contains(where: { $0.contains(sNorm) }) {
                components.append("#\(sNorm)")
            }
        }
        
        var finalCleaned: [String] = []
        for c in components {
            let cNorm = c.lowercased()
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")
            let exists = finalCleaned.contains { existing in
                let eNorm = existing.lowercased()
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: " ", with: "")
                return eNorm == cNorm || (cNorm.count >= 4 && eNorm.contains(cNorm)) || (eNorm.count >= 4 && cNorm.contains(eNorm))
            }
            if !exists {
                finalCleaned.append(c)
            }
        }
        return finalCleaned.joined(separator: " · ")
    }
    
    /// Produces a concise account label tailored for tight navigation bars (e.g. "HighStakes P1 · $50K" or "cTrader #7657")
    public static func compactAccountName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Account" }
        
        // Handle dash-separated format: [Package, Phase, Size, #Number]
        let sep = trimmed.contains(" - ") ? " - " : (trimmed.contains(" · ") ? " · " : "")
        if !sep.isEmpty {
            let parts = trimmed.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 4, let p0Raw = parts.first {
                let p0 = p0Raw.replacingOccurrences(of: " ", with: "")
                let p1 = parts[1].replacingOccurrences(of: "Phase ", with: "P").replacingOccurrences(of: "Step ", with: "P")
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 3, let p0Raw = parts.first {
                let p0 = p0Raw.replacingOccurrences(of: " ", with: "")
                let p1 = parts[1]
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 2, let p0 = parts.first, let p1 = parts.last {
                return "\(p0) \(p1)"
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
    
    /// Formats raw ISO date strings or day strings into clean human-readable date (e.g. "Oct 1, 2026")
    public static func formatDisplayDate(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Pending settlement"
        }
        if let d = isoFractionalFormatter.date(from: raw) {
            return dateOnly(d)
        }
        if let d = isoBasicFormatter.date(from: raw) {
            return dateOnly(d)
        }
        if let d = date(fromIsoDay: raw) {
            return dateOnly(d)
        }
        return raw
    }
    
    /// Cleans verbose or system-generated notes from prop transactions (e.g. stripping ISO order timestamps)
    public static func cleanTransactionNote(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parenIndex = cleaned.range(of: " (The5ers official order") {
            cleaned = String(cleaned[..<parenIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let parenIndex = cleaned.range(of: " (The5ers") {
            cleaned = String(cleaned[..<parenIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }
}
