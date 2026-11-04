import Foundation
import Combine

/// Dedicated domain store managing prop firm accounts, evaluations, funded accounts, receipts, and ledger items.
/// Part of Item 1: TradeDataStore God Object decomposition into domain stores.
@MainActor
public final class PropFirmDomainStore: ObservableObject {
    @Published public var propAccounts: [PropAccountItem] = []
    @Published public var propEntries: [PropEntryItem] = []
    @Published public var propReceipts: [PropReceiptItem] = []
    @Published public var propAudits: [PropAuditItem] = []

    public init(
        propAccounts: [PropAccountItem] = [],
        propEntries: [PropEntryItem] = [],
        propReceipts: [PropReceiptItem] = [],
        propAudits: [PropAuditItem] = []
    ) {
        self.propAccounts = propAccounts
        self.propEntries = propEntries
        self.propReceipts = propReceipts
        self.propAudits = propAudits
    }

    public var activePropAccounts: [PropAccountItem] {
        propAccounts.filter { $0.status == .active || $0.status == .passed }
    }

    public func findPropAccount(byId id: String) -> PropAccountItem? {
        propAccounts.first { $0.id == id || TradeDataStore.isSameAccountId($0.id, id) }
    }
}
