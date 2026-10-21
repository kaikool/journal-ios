import Foundation
import SwiftUI

// MARK: - Accounts & Multi-Account Management Extension
extension TradeDataStore {
    
    public var availableCurrencies: [String] {
        let list = (visibleAccounts.isEmpty ? accounts : visibleAccounts).map { $0.currency.uppercased() }
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
        var ids = Set<String>()
        for acc in visibleAccounts {
            ids.insert(acc.id)
            let clean = acc.id.cleanAccountId
            ids.insert(clean)
            ids.insert(acc.id.the5ersCanonicalId)
            ids.insert(acc.id.ctraderCanonicalId)
        }
        for prop in propAccounts {
            if isPropAccountVisible(prop) {
                ids.insert(prop.id)
                let clean = prop.id.cleanAccountId
                ids.insert(clean)
                ids.insert(prop.id.the5ersCanonicalId)
                ids.insert(prop.id.ctraderCanonicalId)
                if let jId = prop.journalAccountId, !jId.isEmpty {
                    ids.insert(jId)
                    let cleanJ = jId.cleanAccountId
                    ids.insert(cleanJ)
                    ids.insert(jId.the5ersCanonicalId)
                    ids.insert(jId.ctraderCanonicalId)
                }
            }
        }
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
        return accounts.first(where: { $0.id == selId || $0.id == cleanSel || $0.id == altId }) ?? mostRecentActiveAccount ?? accounts.first
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
    
    public func addAccount(name: String, broker: String = "", currency: String = "USD", initialBalance: Decimal = 0, profitCalcMethod: ProfitCalcMethod = .fifo) {
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
    
    public func deduplicateAndCleanAccounts() {
        refreshActiveAccountCache()
        
        var canonicalMap: [String: String] = [:]
        for acc in accounts where !acc.name.hasPrefix("Account ") {
            let clean = acc.id.cleanAccountId
            canonicalMap[clean] = acc.id
            canonicalMap["the5ers_\(clean)"] = acc.id
            canonicalMap["ctrader_\(clean)"] = acc.id
            canonicalMap[acc.id] = acc.id
        }
        for i in 0..<trades.count {
            if let canonical = canonicalMap[trades[i].accountId] {
                trades[i].accountId = canonical
            } else {
                let clean = trades[i].accountId.cleanAccountId
                if let canonical = canonicalMap[clean] {
                    trades[i].accountId = canonical
                }
            }
        }
        
        if accounts.contains(where: { !$0.name.hasPrefix("Account ") }) {
            accounts.removeAll(where: { $0.name.hasPrefix("Account ") })
        }

        var seenCleanAccIds = Set<String>()
        var cleanedAccounts: [Account] = []
        for acc in accounts {
            let clean = acc.id.cleanAccountId
            if seenCleanAccIds.contains(clean) {
                if (acc.id.hasPrefix("the5ers_") || acc.id.hasPrefix("ctrader_")), let idx = cleanedAccounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: acc.id) }) {
                    cleanedAccounts[idx] = acc
                }
                continue
            }
            seenCleanAccIds.insert(clean)
            cleanedAccounts.append(acc)
        }
        if cleanedAccounts.count != accounts.count {
            AppLogger.info("Deduplicated accounts: \(accounts.count) -> \(cleanedAccounts.count)")
            self.accounts = cleanedAccounts
        }

        var seenCleanPropIds = Set<String>()
        var cleanedPropAccounts: [PropAccountItem] = []
        for p in propAccounts {
            let clean = p.id.cleanAccountId
            if seenCleanPropIds.contains(clean) {
                if p.id.hasPrefix("the5ers_"), let idx = cleanedPropAccounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: p.id) }) {
                    cleanedPropAccounts[idx] = p
                }
                continue
            }
            seenCleanPropIds.insert(clean)
            cleanedPropAccounts.append(p)
        }
        if cleanedPropAccounts.count != propAccounts.count {
            AppLogger.info("Deduplicated prop accounts: \(propAccounts.count) -> \(cleanedPropAccounts.count)")
            self.propAccounts = cleanedPropAccounts
        }

        let the5ersAccountIds = Set(accounts.filter { $0.broker.lowercased() == "the5ers" || $0.id.hasPrefix("the5ers_") }.flatMap { [$0.id, $0.id.cleanAccountId, $0.id.the5ersCanonicalId] })
        executions.removeAll(where: { $0.id.hasPrefix("the5ers_exec_") || $0.source == "the5ers" })
        trades.removeAll(where: { trade in
            (the5ersAccountIds.contains(trade.accountId) || trade.accountId.hasPrefix("the5ers_") || trade.tags.contains("the5ers")) && !trade.key.hasPrefix("the5ers_")
        })

        deduplicateExecutions()
        deduplicateTrades()
        deduplicatePropEntries()
        deduplicatePropReceipts()
    }
    
    /// Deduplicates propEntries by ID and semantic signature (firm, kind, currency, amount, date, account)
    public func deduplicatePropEntries() {
        var seenIds = Set<String>()
        var seenCanonicals = Set<String>()
        var seenSemantics = Set<String>()
        var cleaned: [PropEntryItem] = []
        
        for entry in propEntries {
            let cleanAcc = (entry.accountId ?? "").cleanAccountId
            let canonId = PropFirmEngine.canonicalPayoutId(entry.id)
            let semantic = "\(entry.firm)|\(entry.kind)|\(entry.currency.uppercased())|\(entry.amountMinor)|\(entry.occurredOn)|\(cleanAcc)"
            
            if seenIds.contains(entry.id) {
                continue
            }
            if !canonId.isEmpty && canonId != entry.id && seenCanonicals.contains(canonId) {
                continue
            }
            if seenSemantics.contains(semantic) {
                continue
            }
            seenIds.insert(entry.id)
            if !canonId.isEmpty {
                seenCanonicals.insert(canonId)
            }
            seenSemantics.insert(semantic)
            cleaned.append(entry)
        }
        
        if cleaned.count != propEntries.count {
            AppLogger.info("Deduplicated propEntries: \(propEntries.count) -> \(cleaned.count)")
            self.propEntries = cleaned
        }
    }
    
    /// Deduplicates propReceipts by ID and semantic payout reference
    public func deduplicatePropReceipts() {
        var seenIds = Set<String>()
        var seenCanonicals = Set<String>()
        var seenSemantics = Set<String>()
        var cleaned: [PropReceiptItem] = []
        
        for rcpt in propReceipts {
            if seenIds.contains(rcpt.id) {
                continue
            }
            let canonPayout = PropFirmEngine.canonicalPayoutId(rcpt.payoutId)
            let canonRcpt = PropFirmEngine.canonicalPayoutId(rcpt.id)
            let semantic = "\(canonPayout)|\(rcpt.amountMinor)|\(rcpt.occurredOn)"
            
            if !canonRcpt.isEmpty && canonRcpt != rcpt.id && seenCanonicals.contains(canonRcpt) {
                continue
            }
            if seenSemantics.contains(semantic) {
                continue
            }
            seenIds.insert(rcpt.id)
            if !canonRcpt.isEmpty {
                seenCanonicals.insert(canonRcpt)
            }
            seenSemantics.insert(semantic)
            cleaned.append(rcpt)
        }
        
        if cleaned.count != propReceipts.count {
            AppLogger.info("Deduplicated propReceipts: \(propReceipts.count) -> \(cleaned.count)")
            self.propReceipts = cleaned
        }
    }
    
    public func createInitialDefaultAccount() {
        let defaultAcc = Account(
            id: "default-acc",
            name: "Trading Account",
            broker: "",
            currency: "USD",
            initialBalance: 0
        )
        accounts = [defaultAcc]
        selectedAccountId = defaultAcc.id
        saveToDisk(immediate: true)
    }
}
