import Foundation
import Combine

// MARK: - Remote Account Merge
extension TradeDataStore {
    /// Merges accounts fetched from Supabase into the local store, preserving local visibility flags,
    /// linking prop-firm journal accounts, deduplicating, and repairing the active account selection.
    func mergeRemoteAccounts(_ remoteAccounts: [Account]) {
        var localAccounts = self.accounts
        if !remoteAccounts.isEmpty {
            for rAcc in remoteAccounts {
                if let idx = localAccounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: rAcc.id) }) {
                    var updated = rAcc
                    if let localVisible = localAccounts[idx].visibleInJournal {
                        updated.visibleInJournal = localVisible
                    }
                    localAccounts[idx] = updated
                } else {
                    localAccounts.append(rAcc)
                }
            }
            if localAccounts.count > 1 {
                localAccounts.removeAll(where: { $0.id == "default-acc" })
            }
        }
        
        var mergedAccountList = localAccounts.filter { !$0.name.hasPrefix("Account ") }
        let existingAccIds = Set(mergedAccountList.map { $0.id })
        
        for p in propAccounts {
            if let jId = p.journalAccountId, !jId.isEmpty && !existingAccIds.contains(jId) {
                if !mergedAccountList.contains(where: { $0.id.isEquivalentAccountId(to: jId) }) {
                    mergedAccountList.append(Account(id: jId, name: p.name, broker: p.firm, kind: .sync, currency: p.currency))
                }
            }
        }
        if self.accounts != mergedAccountList {
            self.accounts = mergedAccountList
            deduplicateAndCleanAccounts()
        }
        if selectedAccountId == "default-acc" || selectedAccountId == "all" || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
            selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
        }
    }
}
