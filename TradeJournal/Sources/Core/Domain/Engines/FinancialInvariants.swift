import Foundation

public enum FinancialInvariants {
    /// Zero tolerance threshold for breakeven detection (1e-9)
    public static let flatEpsilon: Decimal = Decimal(sign: .plus, exponent: -9, significand: 1)
    /// Standard calculation epsilon (1e-6)
    public static let epsilon: Decimal = Decimal(sign: .plus, exponent: -6, significand: 1)
    
    /// Tests whether net P&L falls within breakeven tolerance
    public static func isBreakeven(netPnl: Decimal, tolerance: Decimal = flatEpsilon) -> Bool {
        return abs(netPnl) <= tolerance
    }
}
