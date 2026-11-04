import Foundation
import Combine

// MARK: - Accounts & Multi-Account Management Extension
extension TradeDataStore {

    public var availableCurrencies: [String] {
        if selectedAccountId != "all" && !selectedAccountId.isEmpty {
            if let sel = selectedAccount {
                return [sel.currency.uppercased()]
            }
        }

        let activeAccountIdsWithTrades = Set(trades.map(\.accountId))
        let targetAccounts = visibleAccounts.isEmpty ? accounts : visibleAccounts

        // Only include accounts that have actual trades, unless no accounts have trades yet
        let accountsWithTrades = targetAccounts.filter { acc in
            activeAccountIdsWithTrades.contains(acc.id) ||
            activeAccountIdsWithTrades.contains(acc.id.cleanAccountId) ||
            activeAccountIdsWithTrades.contains(acc.id.the5ersCanonicalId) ||
            activeAccountIdsWithTrades.contains(acc.id.ctraderCanonicalId) ||
            activeAccountIdsWithTrades.contains(acc.id.exnessCanonicalId)
        }

        let pool = accountsWithTrades.isEmpty ? targetAccounts : accountsWithTrades
        let list = pool.map { $0.currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let unique = Array(Set(list)).sorted()
        return unique.isEmpty ? ["USD"] : unique
    }

    public func refreshActiveAccountCache() {
        var activeIds = Set<String>()
        var inactiveIds = Set<String>()
        for p in propAccounts {
            let s = p.status.rawValue.lowercased()
            let isActive = (s == "active" || s == "funded" || s == "open")
            let candidates = [
                p.id,
                p.journalAccountId ?? "",
                p.id.hasPrefix("the5ers_") ? String(p.id.dropFirst(8)) : "the5ers_\(p.id)"
            ].filter { !$0.isEmpty }
            for c in candidates {
                if isActive {
                    activeIds.insert(c)
                } else {
                    inactiveIds.insert(c)
                }
            }
        }
        activePropAccountIdsCache = activeIds
        inactivePropAccountIdsCache = inactiveIds
    }

    public func isAccountActive(_ account: Account) -> Bool {
        if account.archivedAt != nil { return false }
        if activePropAccountIdsCache == nil {
            refreshActiveAccountCache()
        }
        let accId = account.id
        if activePropAccountIdsCache?.contains(accId) == true {
            return true
        }
        if inactivePropAccountIdsCache?.contains(accId) == true {
            return false
        }
        let clean = accId.cleanAccountId
        let alt = accId.the5ersCanonicalId
        if activePropAccountIdsCache?.contains(clean) == true || activePropAccountIdsCache?.contains(alt) == true {
            return true
        }
        if inactivePropAccountIdsCache?.contains(clean) == true || inactivePropAccountIdsCache?.contains(alt) == true {
            return false
        }
        return true
    }

    public func propAccount(for account: Account) -> PropAccountItem? {
        let clean = account.id.cleanAccountId
        let canon = account.id.the5ersCanonicalId
        return propAccounts.first { p in
            p.id == account.id ||
            p.id.cleanAccountId == clean ||
            p.id.the5ersCanonicalId == canon ||
            p.journalAccountId == account.id ||
            p.journalAccountId?.cleanAccountId == clean ||
            p.name == account.name
        }
    }

    public func isPropAccount(_ account: Account) -> Bool {
        account.broker.lowercased() == "the5ers" ||
        account.propProgram != nil ||
        account.id.hasPrefix("the5ers_") ||
        propAccount(for: account) != nil
    }

    public func isAccountVisible(_ account: Account) -> Bool {
        if let v = account.visibleInJournal {
            return v
        }
        return account.archivedAt == nil
    }

    public var visibleAccounts: [Account] {
        if let cached = _cachedVisibleAccounts {
            return cached
        }
        let result = accounts.filter { isAccountVisible($0) }
        _cachedVisibleAccounts = result
        return result
    }

    public var visibleAccountIds: Set<String> {
        if let cached = _cachedVisibleAccountIds {
            return cached
        }
        var ids = Set<String>()
        for acc in visibleAccounts {
            ids.insert(acc.id)
            let clean = acc.id.cleanAccountId
            ids.insert(clean)
            ids.insert(acc.id.the5ersCanonicalId)
            ids.insert(acc.id.ctraderCanonicalId)
            ids.insert(acc.id.exnessCanonicalId)
        }
        for prop in propAccounts {
            if isPropAccountVisible(prop) {
                ids.insert(prop.id)
                let clean = prop.id.cleanAccountId
                ids.insert(clean)
                ids.insert(prop.id.the5ersCanonicalId)
                ids.insert(prop.id.ctraderCanonicalId)
                ids.insert(prop.id.exnessCanonicalId)
                if let jId = prop.journalAccountId, !jId.isEmpty {
                    ids.insert(jId)
                    let cleanJ = jId.cleanAccountId
                    ids.insert(cleanJ)
                    ids.insert(jId.the5ersCanonicalId)
                    ids.insert(jId.ctraderCanonicalId)
                    ids.insert(jId.exnessCanonicalId)
                }
            }
        }
        _cachedVisibleAccountIds = ids
        return ids
    }

    public func isPropAccountVisible(_ prop: PropAccountItem) -> Bool {
        return !prop.archived
    }

    public func isPropEntryVisible(_ entry: PropEntryItem) -> Bool {
        return !entry.voided
    }

    public var activeAccounts: [Account] {
        if let cached = _cachedActiveAccounts {
            return cached
        }
        let result = accounts.filter { isAccountActive($0) }
        _cachedActiveAccounts = result
        return result
    }

    public var mostRecentActiveAccount: Account? {
        if _cachedMostRecentActiveAccountValid {
            return _cachedMostRecentActiveAccount
        }

        let active = activeAccounts
        guard !active.isEmpty else {
            _cachedMostRecentActiveAccount = accounts.first
            _cachedMostRecentActiveAccountValid = true
            return accounts.first
        }

        var latestTradeDateByAccountId: [String: Date] = [:]
        for trade in trades {
            let id = trade.accountId
            if let existing = latestTradeDateByAccountId[id] {
                if trade.openedAt > existing {
                    latestTradeDateByAccountId[id] = trade.openedAt
                }
            } else {
                latestTradeDateByAccountId[id] = trade.openedAt
            }
        }

        var bestAccount: Account? = nil
        var bestDate: Date = .distantPast

        for acc in active {
            let candidates = [
                acc.id,
                acc.id.the5ersCanonicalId,
                acc.id.ctraderCanonicalId,
                acc.id.exnessCanonicalId,
                acc.id.cleanAccountId
            ]
            for cand in candidates where !cand.isEmpty {
                if let d = latestTradeDateByAccountId[cand], d > bestDate {
                    bestDate = d
                    bestAccount = acc
                }
            }
        }

        let result = bestAccount ?? active.first ?? accounts.first
        _cachedMostRecentActiveAccount = result
        _cachedMostRecentActiveAccountValid = true
        return result
    }

    public var selectedAccount: Account? {
        if selectedAccountId == "all" {
            return mostRecentActiveAccount ?? visibleAccounts.first ?? accounts.first
        }
        let selId = selectedAccountId
        let cleanSel = selId.cleanAccountId
        let altId = selId.the5ersCanonicalId
        let cId = selId.ctraderCanonicalId
        let eId = selId.exnessCanonicalId
        return accounts.first(where: {
            $0.id == selId ||
            $0.id == cleanSel ||
            $0.id == altId ||
            $0.id == cId ||
            $0.id == eId ||
            $0.id.isEquivalentAccountId(to: selId)
        }) ?? mostRecentActiveAccount ?? accounts.first
    }

    public func selectAccount(id: String) {
        guard selectedAccountId != id else { return }
        selectedAccountId = id
        invalidatePerformanceCaches()
        if trades.filter({ $0.accountId == id }).isEmpty && !executions.filter({ $0.accountId == id }).isEmpty {
            rebuildAccount(accountId: id)
            invalidatePerformanceCaches()
        }
        saveToDisk()
        objectWillChange.send()
    }

    @discardableResult
    public func addAccount(name: String, broker: String = "", currency: String = "USD", initialBalance: Decimal = 0, profitCalcMethod: ProfitCalcMethod = .fifo) -> Account {
        let newAccount = Account(
            name: name,
            broker: broker,
            currency: currency,
            initialBalance: initialBalance,
            profitCalcMethod: profitCalcMethod
        )
        accounts.append(newAccount)
        selectedAccountId = newAccount.id
        saveToDisk(immediate: true)
        AppLogger.info("Added account: \(name) (\(newAccount.id))")
        return newAccount
    }

    public func archiveAccount(id: String, archived: Bool) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].archivedAt = archived ? Date() : nil
            invalidatePerformanceCaches()
            saveToDisk()
            objectWillChange.send()
        }
    }

    public func updateAccount(
        id: String,
        name: String,
        broker: String,
        kind: AccountKind,
        currency: String,
        initialBalance: Decimal
    ) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[idx].broker = broker.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[idx].kind = kind
        accounts[idx].currency = currency
        accounts[idx].initialBalance = initialBalance
        rebuildAccount(accountId: id)
        invalidatePerformanceCaches()
        saveToDisk(immediate: true)
        objectWillChange.send()
        let updatedAcc = accounts[idx]
        Task {
            try? await SupabaseService.shared.upsertAccounts([updatedAcc])
        }
    }

    public func deleteAccount(id: String) {
        accounts.removeAll(where: { $0.id == id })
        trades.removeAll(where: { $0.accountId == id })
        executions.removeAll(where: { $0.accountId == id })
        if selectedAccountId == id {
            selectedAccountId = accounts.first?.id ?? "all"
        }
        invalidatePerformanceCaches()
        saveToDisk(immediate: true)
        objectWillChange.send()
        Task {
            try? await SupabaseService.shared.deleteAccount(id: id)
        }
    }

    public func toggleAccountAutoSync(id: String) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].autoSync.toggle()
            saveToDisk()
        }
    }

    public func toggleAccountVisibility(id: String) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            let current = isAccountVisible(accounts[idx])
            accounts[idx].visibleInJournal = !current
            invalidatePerformanceCaches()
            saveToDisk()
            objectWillChange.send()
        }
    }

    public func setBulkAccountVisibility(action: String) {
        for idx in accounts.indices {
            switch action {
            case "select-all":
                accounts[idx].visibleInJournal = true
            case "select-active":
                accounts[idx].visibleInJournal = (accounts[idx].archivedAt == nil)
            case "deselect-all":
                accounts[idx].visibleInJournal = false
            default:
                break
            }
        }
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
    }
}
