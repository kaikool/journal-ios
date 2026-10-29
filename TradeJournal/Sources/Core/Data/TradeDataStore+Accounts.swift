import Foundation
import SwiftUI

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
            activeAccountIdsWithTrades.contains(acc.id.ctraderCanonicalId)
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
            (p.journalAccountId != nil && p.journalAccountId!.cleanAccountId == clean) ||
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
        var updatedTrades = trades
        var tradesChanged = false
        for i in 0..<updatedTrades.count {
            if let canonical = canonicalMap[updatedTrades[i].accountId] {
                if updatedTrades[i].accountId != canonical {
                    updatedTrades[i].accountId = canonical
                    tradesChanged = true
                }
            } else {
                let clean = updatedTrades[i].accountId.cleanAccountId
                if let canonical = canonicalMap[clean], updatedTrades[i].accountId != canonical {
                    updatedTrades[i].accountId = canonical
                    tradesChanged = true
                }
            }
        }
        if tradesChanged {
            self.trades = updatedTrades
        }
        
        if accounts.contains(where: { !$0.name.hasPrefix("Account ") }) && accounts.contains(where: { $0.name.hasPrefix("Account ") }) {
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

        cleanupLegacyThe5ersCorruptions()
        deduplicateExecutions()
        deduplicateTrades()
        deduplicatePropEntries()
        deduplicatePropReceipts()
        sanitizeAccountCurrencies()
    }
    
    /// Normalizes accounts whose currency was erroneously detected as SEK or SGD (e.g. from cTrader demo asset leaks)
    /// when the user's actual executions and trades are exclusively in standard USD instruments.
    public func sanitizeAccountCurrencies() {
        var didChange = false
        for idx in accounts.indices {
            let curr = accounts[idx].currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if curr == "SEK" || curr == "SGD" {
                let accId = accounts[idx].id
                let accTrades = trades.filter { $0.accountId == accId || TradeDataStore.isSameAccountId($0.accountId, accId) }
                let hasExoticTrades = accTrades.contains { t in
                    let spec = AssetContractEngine.spec(for: t.symbol)
                    return spec.quoteCurrency == curr || spec.baseCurrency == curr
                }
                if !hasExoticTrades {
                    AppLogger.info("Sanitizing spurious currency \(curr) to USD for account \(accId) (\(accounts[idx].name))")
                    accounts[idx].currency = "USD"
                    rebuildAccount(accountId: accId)
                    didChange = true
                }
            }
        }
        if didChange {
            invalidatePerformanceCaches()
            saveToDisk(immediate: true)
            objectWillChange.send()
        }
    }
    
    /// Audits and cleans up legacy corrupted The5ers records:
    /// - Purges test records accidentally created with "opaque" IDs from old builds
    /// - Enforces zero Net P&L on all open / unclosed positions
    /// - Deduplicates and aligns all The5ers trades
    public func cleanupLegacyThe5ersCorruptions() {
        // 1. Remove ONLY invalid test records with "opaque" IDs from old buggy builds
        if propEntries.contains(where: { $0.firm == "The5ers" && ($0.id.contains("opaque") || $0.reference.contains("opaque")) }) {
            propEntries.removeAll(where: { entry in
                entry.firm == "The5ers" && (entry.id.contains("opaque") || entry.reference.contains("opaque"))
            })
        }
        if propReceipts.contains(where: { $0.id.contains("opaque") || $0.payoutId.contains("opaque") || $0.reference.contains("opaque") }) {
            propReceipts.removeAll(where: { rcpt in
                rcpt.id.contains("opaque") || rcpt.payoutId.contains("opaque") || rcpt.reference.contains("opaque")
            })
        }
        
        // 2. Remove orphaned receipts that don't match any active entry
        let activeEntryIds = Set(propEntries.map { $0.id })
        if propReceipts.contains(where: { $0.id.hasPrefix("the5ers_") && !activeEntryIds.contains($0.payoutId) }) {
            propReceipts.removeAll(where: { rcpt in
                rcpt.id.hasPrefix("the5ers_") && !activeEntryIds.contains(rcpt.payoutId)
            })
        }
        
        // 3. Purge legacy synthetic "ACCOUNT" summary/midnight trades and enforce zero Net P&L on open positions
        var localTrades = trades
        var modified = false
        let countBeforePurge = localTrades.count
        localTrades.removeAll { t in
            t.symbol == "ACCOUNT" || t.key.contains("_midnight_") || t.key.hasSuffix("_summary")
        }
        if localTrades.count != countBeforePurge {
            modified = true
        }
        for i in 0..<localTrades.count {
            if localTrades[i].notes?.hasPrefix("Position synced from") == true {
                localTrades[i].notes = nil
                modified = true
            }
            
            if localTrades[i].status == .open {
                // An active open trade MUST stay open: closedAt is nil, openQuantity is quantity, realized PnL is 0
                if localTrades[i].closedAt != nil {
                    localTrades[i].closedAt = nil
                    modified = true
                }
                if localTrades[i].netPnl != 0 || localTrades[i].grossPnl != 0 || localTrades[i].fees != 0 || localTrades[i].openQuantity != localTrades[i].quantity {
                    localTrades[i].netPnl = 0
                    localTrades[i].grossPnl = 0
                    localTrades[i].fees = 0
                    localTrades[i].openQuantity = localTrades[i].quantity
                    modified = true
                }
            } else {
                // A completed closed trade (.win, .loss, .breakeven) must have openQuantity = 0 and closedAt populated
                if localTrades[i].closedAt == nil {
                    localTrades[i].closedAt = localTrades[i].openedAt.addingTimeInterval(120)
                    modified = true
                }
                if localTrades[i].openQuantity != 0 {
                    localTrades[i].openQuantity = Decimal.zero
                    modified = true
                }
            }
        }
        if modified {
            trades = localTrades
        }
        
        // 4. Clean and normalize The5ers purchase expenses
        var entriesModified = false
        var localEntries = propEntries
        for i in 0..<localEntries.count {
            if localEntries[i].firm == "The5ers" && localEntries[i].kind == "expense" {
                if localEntries[i].category == "other" || localEntries[i].category.isEmpty {
                    localEntries[i].category = "evaluation"
                    entriesModified = true
                }
                if localEntries[i].notes.contains("(The5ers official order placed") {
                    if let clean = localEntries[i].notes.components(separatedBy: " (The5ers official order placed").first, !clean.isEmpty {
                        localEntries[i].notes = clean
                        entriesModified = true
                    }
                }
            }
        }
        if entriesModified {
            propEntries = localEntries
        }
        
        // 5. Ensure all The5ers PropAccountItems have complete program rules, realized Net P&L, & reconciled trade stats
        var propsModified = false
        var tradesReconciled = false
        var currentTrades = trades
        var localProps = propAccounts
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = TimeZone(secondsFromGMT: 0)
        for i in 0..<localProps.count {
            guard localProps[i].firm == "The5ers" else { continue }
            var p = localProps[i]
            var changed = false
            let sizeMinor = p.sizeMinor ?? 0
            let settledPayoutsMinor = propEntries
                .filter { $0.firm == "The5ers" && $0.kind == "payout" && $0.status == .completed && !$0.voided && $0.accountId != nil && ($0.accountId == p.id || $0.accountId == p.journalAccountId || TradeDataStore.isSameAccountId($0.accountId!, p.id)) }
                .reduce(Int64(0)) { $0 + $1.amountMinor }
            if sizeMinor > 0 {
                let text = "\(p.name) \(p.currentStepName ?? "") \(p.program.rawValue)".lowercased()
                let isStep2 = p.program == .verification || text.contains("- 2") || text.contains("step 2") || text.contains("phase 2")
                let isBootcamp = text.contains("bootcamp")
                let isHyperOrInstant = text.contains("hyper") || text.contains("instant") || p.program == .instantFunded
                
                if p.profitTargetMinor == nil {
                    let pct: Int64 = isHyperOrInstant ? 10 : (isBootcamp ? 6 : (isStep2 ? 5 : 8))
                    p.profitTargetMinor = (sizeMinor * pct) / 100
                    changed = true
                }
                if p.maxLossMinor == nil {
                    let pct: Int64 = isHyperOrInstant ? 6 : (isBootcamp ? 5 : 10)
                    p.maxLossMinor = (sizeMinor * pct) / 100
                    changed = true
                }
                if p.maxDailyLossMinor == nil {
                    let pct: Int64 = isHyperOrInstant ? 3 : (isBootcamp ? 3 : 5)
                    p.maxDailyLossMinor = (sizeMinor * pct) / 100
                    changed = true
                }
                if p.minTradingDays == nil && !isHyperOrInstant && !isBootcamp {
                    p.minTradingDays = 3
                    changed = true
                }
            }
            let targetId = p.journalAccountId ?? p.id
            let closedIndices = currentTrades.indices.filter { idx in
                let t = currentTrades[idx]
                return t.symbol != "ACCOUNT" && t.status != .open && t.closedAt != nil &&
                       (t.accountId == targetId || TradeDataStore.isSameAccountId(t.accountId, targetId))
            }
            if !closedIndices.isEmpty {
                let tradeNetSum = closedIndices.reduce(Decimal.zero) { $0 + currentTrades[$1].netPnl }
                let expectedTradeNetMinor = NSDecimalNumber(decimal: tradeNetSum * 100).int64Value
                if p.netPnlMinor != expectedTradeNetMinor {
                    p.netPnlMinor = expectedTradeNetMinor
                    changed = true
                }
                
                var dailyMap: [String: Decimal] = [:]
                for idx in closedIndices {
                    let t = currentTrades[idx]
                    let dk = dayFmt.string(from: t.closedAt ?? t.openedAt)
                    dailyMap[dk, default: .zero] += t.netPnl
                }
                let td = dailyMap.count
                let wd = dailyMap.values.filter { $0 > 0 }.count
                if p.currentTradingDays == nil || (p.currentTradingDays == 0 && td > 0) || tradesReconciled {
                    p.currentTradingDays = td
                    changed = true
                }
                if p.winningDays == nil || (p.winningDays == 0 && wd > 0) || tradesReconciled {
                    p.winningDays = wd
                    changed = true
                }
                if p.totalTrades == nil || (p.totalTrades == 0 && !closedIndices.isEmpty) {
                    p.totalTrades = closedIndices.count
                    changed = true
                }
                if p.totalFeesMinor == nil {
                    let feeSum = closedIndices.reduce(Decimal.zero) { $0 + currentTrades[$1].fees }
                    p.totalFeesMinor = NSDecimalNumber(decimal: abs(feeSum) * 100).int64Value
                    changed = true
                }
            } else {
                if p.winningDays == nil {
                    p.winningDays = 0
                    changed = true
                }
                if p.currentTradingDays == nil {
                    p.currentTradingDays = 0
                    changed = true
                }
            }
            if changed {
                localProps[i] = p
                propsModified = true
            }
        }
        if tradesReconciled {
            trades = currentTrades
            invalidatePerformanceCaches()
        }
        if propsModified {
            propAccounts = localProps
        }
    }
    
    /// Deduplicates propEntries by ID and semantic signature (firm, kind, currency, amount, date, account)
    public func deduplicatePropEntries() {
        var seenIds = Set<String>()
        var seenCanonicals = Set<String>()
        var cleaned: [PropEntryItem] = []
        
        // Prioritize deterministic provider IDs ("the5ers_payout_...", "the5ers_purchase_...") over random UUIDs
        let sortedEntries = propEntries.sorted { a, b in
            let aIsDeterministic = a.id.hasPrefix("the5ers_payout_") || a.id.hasPrefix("the5ers_purchase_")
            let bIsDeterministic = b.id.hasPrefix("the5ers_payout_") || b.id.hasPrefix("the5ers_purchase_")
            if aIsDeterministic != bIsDeterministic {
                return aIsDeterministic && !bIsDeterministic
            }
            return a.revision > b.revision
        }
        
        for entry in sortedEntries {
            let canonId = PropFirmEngine.canonicalPayoutId(entry.id)
            
            // 1. Direct duplicate ID check
            if seenIds.contains(entry.id) {
                continue
            }
            
            // 2. Canonical payout ID check
            if !canonId.isEmpty && canonId != entry.id && seenCanonicals.contains(canonId) {
                continue
            }
            
            // 3. Financial Reconciliation Match (firm, kind, currency, amountMinor, date within ±1 day)
            if let existingIdx = cleaned.firstIndex(where: { kept in
                kept.firm.lowercased() == entry.firm.lowercased() &&
                kept.kind == entry.kind &&
                kept.currency.uppercased() == entry.currency.uppercased() &&
                abs(kept.amountMinor - entry.amountMinor) <= 50 &&
                FlexibleDateParser.areDatesClose(kept.occurredOn, entry.occurredOn, maxDays: 1)
            }) {
                // If the discarded entry has user notes and the kept entry has default notes, preserve user notes
                if !entry.notes.isEmpty && (cleaned[existingIdx].notes.isEmpty || cleaned[existingIdx].notes == "The5ers Official Withdrawal" || cleaned[existingIdx].notes == "The5ers Program Evaluation") {
                    cleaned[existingIdx].notes = entry.notes
                }
                continue
            }
            
            seenIds.insert(entry.id)
            if !canonId.isEmpty {
                seenCanonicals.insert(canonId)
            }
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
        var cleaned: [PropReceiptItem] = []
        
        // Prioritize deterministic provider IDs ("the5ers_rcpt_...") over random UUIDs
        let sortedReceipts = propReceipts.sorted { a, b in
            let aIsDeterministic = a.id.hasPrefix("the5ers_rcpt_")
            let bIsDeterministic = b.id.hasPrefix("the5ers_rcpt_")
            if aIsDeterministic != bIsDeterministic {
                return aIsDeterministic && !bIsDeterministic
            }
            return a.id > b.id
        }
        
        for rcpt in sortedReceipts {
            if seenIds.contains(rcpt.id) {
                continue
            }
            let canonPayout = PropFirmEngine.canonicalPayoutId(rcpt.payoutId)
            let canonRcpt = PropFirmEngine.canonicalPayoutId(rcpt.id)
            
            if !canonRcpt.isEmpty && canonRcpt != rcpt.id && seenCanonicals.contains(canonRcpt) {
                continue
            }
            
            // Financial matching against already kept receipts
            if let _ = cleaned.firstIndex(where: { kept in
                abs(kept.amountMinor - rcpt.amountMinor) <= 50 &&
                (kept.payoutId == rcpt.payoutId || 
                 PropFirmEngine.canonicalPayoutId(kept.payoutId) == canonPayout ||
                 FlexibleDateParser.areDatesClose(kept.occurredOn, rcpt.occurredOn, maxDays: 1))
            }) {
                continue
            }
            
            seenIds.insert(rcpt.id)
            if !canonRcpt.isEmpty {
                seenCanonicals.insert(canonRcpt)
            }
            cleaned.append(rcpt)
        }
        
        if cleaned.count != propReceipts.count {
            AppLogger.info("Deduplicated propReceipts: \(propReceipts.count) -> \(cleaned.count)")
            self.propReceipts = cleaned
        }
    }
    
    /// Reconciles orphan prop receipts to ensure a corresponding payout entry exists in propEntries
    public func reconcileReceiptsToEntries() {
        for rcpt in propReceipts where !rcpt.voided {
            let canonPayout = PropFirmEngine.canonicalPayoutId(rcpt.payoutId)
            let hasEntry = propEntries.contains(where: {
                $0.id == rcpt.payoutId ||
                PropFirmEngine.canonicalPayoutId($0.id) == canonPayout ||
                (!canonPayout.isEmpty && $0.id.contains(canonPayout))
            })
            if !hasEntry {
                let payoutEntryId = rcpt.payoutId.isEmpty ? "the5ers_payout_\(rcpt.id)" : rcpt.payoutId
                let grossMinor = Int64(round(Double(rcpt.amountMinor) / 0.8))
                let newEntry = PropEntryItem(
                    id: payoutEntryId,
                    accountId: nil,
                    firm: "The5ers",
                    kind: "payout",
                    category: "payout",
                    currency: "USD",
                    amountMinor: grossMinor,
                    splitBps: 8000,
                    feeMinor: 0,
                    occurredOn: rcpt.occurredOn,
                    status: .completed,
                    reference: rcpt.reference.isEmpty ? "Settlement Receipt" : rcpt.reference,
                    notes: rcpt.notes
                )
                propEntries.append(newEntry)
            }
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
