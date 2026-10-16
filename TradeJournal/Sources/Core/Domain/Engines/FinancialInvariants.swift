import Foundation

public enum FinancialInvariants {
    public static let epsilon: Decimal = Decimal(string: "0.000001")! // 1e-6 tolerance for breakeven
    
    public static func isBreakeven(netPnl: Decimal, tolerance: Decimal = epsilon) -> Bool {
        netPnl.magnitude <= tolerance
    }
}
