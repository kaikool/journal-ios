import Foundation

public enum FinancialInvariants {
    /// Internal domain documentation
    public static let flatEpsilon: Decimal = Decimal(string: "0.000000001")!
    public static let epsilon: Decimal = Decimal(string: "0.000001")!
    
    /// Internal domain documentation
    public static func isBreakeven(netPnl: Decimal, tolerance: Decimal = flatEpsilon) -> Bool {
        return abs(netPnl) <= tolerance
    }
}
