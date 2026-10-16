import Foundation

public enum FinancialInvariants {
    /// Ngưỡng số học để xác định một vị thế đã phẳng hoàn toàn (tránh sai số số thập phân nhỏ)
    public static let flatEpsilon: Decimal = Decimal(string: "0.000000001")!
    public static let epsilon: Decimal = Decimal(string: "0.000001")!
    
    /// Bất biến kiểm tra trạng thái hòa vốn
    public static func isBreakeven(netPnl: Decimal, tolerance: Decimal = flatEpsilon) -> Bool {
        return abs(netPnl) <= tolerance
    }
}
