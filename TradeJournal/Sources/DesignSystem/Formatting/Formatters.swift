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
}
