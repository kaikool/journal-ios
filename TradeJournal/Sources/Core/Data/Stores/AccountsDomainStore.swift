import Foundation
import Combine

/// Dedicated domain store managing trading accounts, active account selection, and account caching.
/// Part of Item 1: TradeDataStore God Object decomposition into domain stores.
@MainActor
public final class AccountsDomainStore: ObservableObject {
    @Published public var accounts: [Account] = []
    @Published public var selectedAccountId: String = "default-acc"
    @Published public var selectedTimeRange: JournalTimeRange = .all

    public init(
        accounts: [Account] = [],
        selectedAccountId: String = "default-acc",
        selectedTimeRange: JournalTimeRange = .all
    ) {
        self.accounts = accounts
        self.selectedAccountId = selectedAccountId
        self.selectedTimeRange = selectedTimeRange
    }

    public var visibleAccounts: [Account] {
        accounts.filter { !$0.isHidden }
    }

    public var visibleAccountIds: Set<String> {
        Set(visibleAccounts.map { $0.id })
    }

    public var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived && !$0.isHidden }
    }

    public func findAccount(byId id: String) -> Account? {
        accounts.first { $0.id == id || TradeDataStore.isSameAccountId($0.id, id) }
    }
}
