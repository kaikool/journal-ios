import Foundation

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
    
    /// Định dạng số tiền (có hỗ trợ Privacy Mode làm mờ số dư)
    public static func currency(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        currencyFormatter.currencyCode = currencyCode
        return currencyFormatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
    
    /// Định dạng P&L có dấu cộng/trừ rõ ràng
    public static func pnl(_ amount: Decimal, currencyCode: String = "USD", isPrivate: Bool = false) -> String {
        if isPrivate { return "••••••" }
        let sign = amount > 0 ? "+" : ""
        return "\(sign)\(currency(amount, currencyCode: currencyCode, isPrivate: false))"
    }
    
    /// Định dạng tỷ lệ phần trăm (ví dụ: 0.542 -> "54.2%")
    public static func percentage(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "n/a" }
        return percentFormatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }
    
    /// Định dạng giá thực hiện lệnh (linh hoạt từ 2 tới 5 số lẻ cho Forex/Crypto)
    public static func price(_ value: Decimal) -> String {
        return priceFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    /// Định dạng thời gian theo múi giờ chỉ định
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
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
}
