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

    private static let dynamicPriceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.usesGroupingSeparator = true
        return f
    }()

    /// Formats execution price (2 to 5+ decimal places dynamically based on symbol or price magnitude)
    public static func price(_ value: Decimal, symbol: String? = nil) -> String {
        let decimals = decimalPlaces(for: symbol, price: value)
        let f = dynamicPriceFormatter
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
    
    /// Formats excursion / delta in pips (e.g. "+15.2 pips", "8 pips")
    public static func pips(_ value: Double, signed: Bool = false) -> String {
        let prefix = (signed && value > 0) ? "+" : ""
        return "\(prefix)\(points(value)) pips"
    }

    public static func pips(_ value: Decimal, signed: Bool = false) -> String {
        let num = (value as NSDecimalNumber).doubleValue
        return pips(num, signed: signed)
    }

    /// Formats an R-Multiple value (e.g. "1.50 R", "-0.80 R")
    public static func formatRMultiple(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.2f R", v)
    }

    public static func formatRMultiple(_ value: Decimal?) -> String {
        guard let v = value else { return "–" }
        return formatRMultiple((v as NSDecimalNumber).doubleValue)
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

    private static let isoDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let shortMonthDayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM dd, HH:mm"
        return f
    }()

    private static let slashDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoBasicFormatter: ISO8601DateFormatter = {
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

    public static func isoDateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        isoDateTimeFormatter.timeZone = timeZone
        return isoDateTimeFormatter.string(from: date)
    }

    public static func shortMonthDayTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        shortMonthDayTimeFormatter.timeZone = timeZone
        return shortMonthDayTimeFormatter.string(from: date)
    }

    public static func formatIsoTimestamp(_ iso: String, timeZone: TimeZone = .current) -> String {
        if let d = FlexibleDateParser.parse(iso) {
            slashDateTimeFormatter.timeZone = timeZone
            return slashDateTimeFormatter.string(from: d)
        }
        return iso
    }
    
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    public static func formatMonthYear(_ date: Date, timeZone: TimeZone = .current) -> String {
        monthYearFormatter.timeZone = timeZone
        return monthYearFormatter.string(from: date)
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
    
}