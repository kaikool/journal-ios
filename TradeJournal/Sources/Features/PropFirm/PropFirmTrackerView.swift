import SwiftUI

/// Prop firm tracker coordinating Accounts, Cash Movements, Payouts, and Transactions
/// Ported 1:1 from `source-repo/apps/web/src/components/prop-firm-tracker.tsx`
public struct PropFirmTrackerView: View {
    public init() {}
    
    public var body: some View {
        PropFirmLedgerView()
    }
}
