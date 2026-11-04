import Foundation
import Combine

// MARK: - Account Deduplication & Data Healing
extension TradeDataStore {
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
        cleanupOpaqueThe5ersRecords()
        cleanupOrphanedThe5ersReceipts()
        normalizePositionQuantitiesAndPnl()
        normalizeThe5ersExpenses()
        reconcileThe5ersPropAccounts()
    }

    private func cleanupOpaqueThe5ersRecords() {
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
    }

    private func cleanupOrphanedThe5ersReceipts() {
        let activeEntryIds = Set(propEntries.map { $0.id })
        if propReceipts.contains(where: { $0.id.hasPrefix("the5ers_") && !activeEntryIds.contains($0.payoutId) }) {
            propReceipts.removeAll(where: { rcpt in
                rcpt.id.hasPrefix("the5ers_") && !activeEntryIds.contains(rcpt.payoutId)
            })
        }
    }

    private func normalizePositionQuantitiesAndPnl() {
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
                if localTrades[i].openQuantity <= 0 && (!localTrades[i].exits.isEmpty || localTrades[i].avgExit != nil) {
                    localTrades[i].status = localTrades[i].netPnl > 0 ? .win : (localTrades[i].netPnl < 0 ? .loss : .breakeven)
                    localTrades[i].openQuantity = Decimal.zero
                    if localTrades[i].closedAt == nil {
                        localTrades[i].closedAt = Date()
                    }
                    modified = true
                } else {
                    if localTrades[i].closedAt != nil {
                        localTrades[i].closedAt = nil
                        modified = true
                    }

                    let isPartial = !localTrades[i].exits.isEmpty || (localTrades[i].openQuantity > 0 && localTrades[i].openQuantity < localTrades[i].quantity)
                    if isPartial {
                        if localTrades[i].openQuantity > localTrades[i].quantity {
                            localTrades[i].openQuantity = localTrades[i].quantity
                            modified = true
                        }
                    } else {
                        if localTrades[i].openQuantity != localTrades[i].quantity {
                            localTrades[i].openQuantity = localTrades[i].quantity
                            modified = true
                        }
                        if localTrades[i].netPnl != 0 || localTrades[i].grossPnl != 0 || localTrades[i].fees != 0 {
                            localTrades[i].netPnl = 0
                            localTrades[i].grossPnl = 0
                            localTrades[i].fees = 0
                            modified = true
                        }
                    }
                }
            } else {
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
    }

    private func normalizeThe5ersExpenses() {
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
    }

    private func reconcileThe5ersPropAccounts() {
        var propsModified = false
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
                if p.currentTradingDays == nil || (p.currentTradingDays == 0 && td > 0) {
                    p.currentTradingDays = td
                    changed = true
                }
                if p.winningDays == nil || (p.winningDays == 0 && wd > 0) {
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
