import Foundation
import SwiftUI

// MARK: - Trades, Executions & Reconstruction Extension
extension TradeDataStore {
    
    public var filteredTrades: [Trade] {
        let effectiveAccountId: String = {
            if selectedAccountId == "all" || selectedAccountId == "default-acc" || selectedAccountId.isEmpty {
                return selectedAccount?.id ?? selectedAccountId
            }
            return selectedAccountId
        }()
        if let cached = _cachedFilteredTrades,
           _cachedFilteredTradesAccountId == effectiveAccountId {
            return cached
        }
        let result: [Trade]
        if effectiveAccountId.isEmpty || effectiveAccountId == "all" {
            let visibleIds = visibleAccountIds
            result = trades.filter { trade in
                if trade.symbol == "ACCOUNT" { return false }
                if visibleIds.contains(trade.accountId) { return true }
                let clean = trade.accountId.cleanAccountId
                if visibleIds.contains(clean) || visibleIds.contains(trade.accountId.the5ersCanonicalId) {
                    return true
                }
                return false
            }
        } else {
            let selId = effectiveAccountId
            result = trades.filter { trade in
                guard trade.symbol != "ACCOUNT" else { return false }
                return trade.accountId == selId || TradeDataStore.isSameAccountId(trade.accountId, selId)
            }
        }
        _cachedFilteredTrades = result
        _cachedFilteredTradesAccountId = effectiveAccountId
        return result
    }
    
    public var existingHashesForSelectedAccount: Set<String> {
        Set(executions.filter { $0.accountId == selectedAccountId }.map { $0.contentHash })
    }
    
    /// Currency of every known account, keyed by account id.
    /// Used to convert balances into the reporting currency when accounts are aggregated.
    public var accountCurrencyMap: [String: String] {
        var map: [String: String] = [:]
        for account in accounts {
            map[account.id] = account.currency.uppercased()
            map[account.id.cleanAccountId] = account.currency.uppercased()
        }
        return map
    }
    
    /// Applies new conversion settings and rebuilds the round trips so that the trade P&L,
    /// balances and reports all use the same currency.
    public func applyCurrencyConversion(_ conversion: CurrencyConversion) {
        guard conversion != currencyConversion else { return }
        currencyConversion = conversion
        rebuildAllAccounts(forceRebuildTrades: true)
        saveToDisk(immediate: true)
    }
    
    /// Currency the given account reports commissions and swap in.
    public func accountCurrency(for accountId: String) -> String {
        if let account = accounts.first(where: { $0.id == accountId }) {
            return account.currency.uppercased()
        }
        if let account = accounts.first(where: { $0.id.cleanAccountId == accountId.cleanAccountId }) {
            return account.currency.uppercased()
        }
        return currencyConversion.reportingCurrency
    }
    
    /// Imports new fills for an account and triggers reconstruction
    public func importExecutions(accountId: String, newExecutions: [Execution]) {
        let existingIds = Set(executions.map { $0.id })
        let existingHashes = executionHashes.union(executions.map { $0.contentHash })
        
        let uniqueNew = newExecutions.filter { fill in
            if existingIds.contains(fill.id) || existingHashes.contains(fill.contentHash) {
                return false
            }
            // Check semantic duplicate in existing executions
            let semantic = TradeDeduplicator.executionSemanticKey(for: fill)
            let isDuplicate = executions.contains { existing in
                TradeDeduplicator.executionSemanticKey(for: existing) == semantic
            }
            return !isDuplicate
        }
        
        guard !uniqueNew.isEmpty else {
            AppLogger.info("No new unique executions to import.")
            if trades.filter({ $0.accountId == accountId }).isEmpty && !executions.filter({ $0.accountId == accountId }).isEmpty {
                rebuildAccount(accountId: accountId)
                deduplicateTrades()
                invalidatePerformanceCaches()
                saveToDisk(immediate: true)
                objectWillChange.send()
            }
            return
        }
        
        for fill in uniqueNew {
            executionHashes.insert(fill.contentHash)
            executions.append(fill)
        }
        
        deduplicateExecutions()
        rebuildAccount(accountId: accountId)
        deduplicateTrades()
        saveToDisk(immediate: true)
        AppLogger.info("Imported \(uniqueNew.count) executions for account \(accountId). Rebuilt \(trades.count) trades.")
    }
    
    /// Deduplicates executions by ID, contentHash, and semantic execution attributes
    public func deduplicateExecutions() {
        let cleaned = TradeDeduplicator.deduplicate(executions)
        if cleaned.count != executions.count {
            AppLogger.info("Deduplicated executions from \(executions.count) down to \(cleaned.count)")
            self.executions = cleaned
            self.executionHashes = Set(cleaned.map { $0.contentHash })
        }
    }
    
    /// Deduplicates trades by key, and by semantic signature (account, symbol, direction, open time, quantity)
    public func deduplicateTrades() {
        let cleaned = TradeDeduplicator.deduplicate(trades)
        if cleaned.count != trades.count {
            AppLogger.info("Deduplicated trades from \(trades.count) down to \(cleaned.count)")
            self.trades = cleaned
            invalidatePerformanceCaches()
        }
    }
    
    /// Reconstructs round trips from raw executions using account profit calculation method
    public func rebuildAccount(accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        
        let accountFills = executions.filter { $0.accountId == accountId }
        
        // Native The5ers MCP accounts store reported positions directly as round trips and do not use atomic execution reconstruction.
        // Accounts with atomic executions (such as cTrader accounts even under The5ers broker) MUST rebuild round trips!
        if accountId.hasPrefix("the5ers_") && !accountId.hasPrefix("ctrader_") && accountFills.isEmpty {
            return
        }
        
        let reconstructed = TradeReconstructionEngine.buildRoundTrips(
            executions: accountFills,
            options: .init(
                method: account.profitCalcMethod,
                multipliers: multipliers,
                context: currencyConversion.context,
                accountCurrency: account.currency.uppercased(),
                defaults: defaults
            )
        )
        
        // Preserve existing user annotations (notes, tags, mistakes, ratings, risk levels) across rebuilds
        var existingAnnotations: [String: (notes: String?, tags: [String], mistakes: [String], rating: Int?, stopLoss: Decimal?, profitTarget: Decimal?, reviewedAt: Date?, playbookId: String?)] = [:]
        for t in trades where t.accountId == accountId {
            existingAnnotations[t.key] = (t.notes, t.tags, t.mistakes, t.rating, t.stopLoss, t.profitTarget, t.reviewedAt, t.playbookId)
        }
        
        let mergedTrades = reconstructed.map { trade -> Trade in
            var t = trade
            if let ann = existingAnnotations[t.key] {
                t.notes = ann.notes
                t.tags = ann.tags
                t.mistakes = ann.mistakes
                t.rating = ann.rating
                t.stopLoss = ann.stopLoss
                t.profitTarget = ann.profitTarget
                t.reviewedAt = ann.reviewedAt
                t.playbookId = ann.playbookId
            } else {
                let defaultRisk = JournalDefaultsEngine.defaultRisk(
                    entry: t.avgEntry,
                    direction: t.direction,
                    accountId: accountId,
                    symbol: t.symbol,
                    defaults: defaults
                )
                if t.stopLoss == nil { t.stopLoss = defaultRisk.stopLoss }
                if t.profitTarget == nil { t.profitTarget = defaultRisk.profitTarget }
            }
            return t
        }
        
        let otherTrades = trades.filter { $0.accountId != accountId }
        trades = otherTrades + mergedTrades
        invalidatePerformanceCaches()
    }
    
    public func rebuildAllAccounts(forceRebuildTrades: Bool = false) {
        deduplicateAndCleanAccounts()
        deduplicateExecutions()
        deduplicateTrades()
        reconcileReceiptsToEntries()
        deduplicatePropEntries()
        deduplicatePropReceipts()
        var localAccounts = accounts
        var accountsModified = false
        for i in 0..<localAccounts.count {
            let cleaned = Formatters.cleanAccountName(localAccounts[i].name, balance: localAccounts[i].initialBalance)
            if localAccounts[i].name != cleaned {
                localAccounts[i].name = cleaned
                accountsModified = true
            }
        }
        if accountsModified {
            accounts = localAccounts
        }
        var localPropAccounts = propAccounts
        var propAccountsModified = false
        for i in 0..<localPropAccounts.count {
            let sizeBal = localPropAccounts[i].sizeMinor.map { Decimal($0) / 100 }
            let cleaned = Formatters.cleanAccountName(localPropAccounts[i].name, balance: sizeBal)
            if localPropAccounts[i].name != cleaned {
                localPropAccounts[i].name = cleaned
                propAccountsModified = true
            }
        }
        if propAccountsModified {
            propAccounts = localPropAccounts
        }
        let needsTradeRebuild = forceRebuildTrades || (trades.isEmpty && !executions.isEmpty) || accounts.contains(where: { acc in
            trades.filter({ $0.accountId == acc.id }).isEmpty && !executions.filter({ $0.accountId == acc.id }).isEmpty
        })
        if needsTradeRebuild {
            for acc in accounts {
                rebuildAccount(accountId: acc.id)
            }
        }
        deduplicateTrades()
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
    }
    
    public func updateTradeAnnotations(
        key: String,
        notes: String?,
        tags: [String],
        mistakes: [String] = [],
        stopLoss: Decimal?,
        profitTarget: Decimal? = nil,
        rating: Int?,
        playbookId: String? = nil,
        reviewedAt: Date? = nil
    ) {
        guard let index = trades.firstIndex(where: { $0.key == key }) else { return }
        trades[index].notes = notes
        trades[index].tags = tags
        trades[index].mistakes = mistakes
        trades[index].stopLoss = stopLoss
        trades[index].profitTarget = profitTarget
        trades[index].rating = rating
        trades[index].playbookId = playbookId
        trades[index].reviewedAt = reviewedAt
        saveToDisk()
        AppLogger.info("Updated trade annotations for key: \(key)")
    }
    
    public func addManualTrade(
        accountId: String,
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal?,
        openedAt: Date,
        closedAt: Date?,
        fee: Decimal = 0,
        notes: String? = nil,
        tags: [String] = [],
        mistakes: [String] = [],
        rating: Int? = nil,
        stopLoss: Decimal? = nil,
        profitTarget: Decimal? = nil,
        playbookId: String? = nil,
        ruleAssessments: [String: Bool] = [:]
    ) {
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let entrySide: ExecutionSide = (direction == .long) ? .buy : .sell
        let halfFee = (exitPrice != nil) ? (fee / 2) : fee
        
        let entryFill = Execution(
            accountId: accountId,
            symbol: cleanSymbol,
            side: entrySide,
            quantity: quantity,
            price: entryPrice,
            fee: halfFee,
            executedAt: openedAt,
            source: "manual"
        )
        
        var newExecutions = [entryFill]
        
        if let exitP = exitPrice {
            let exitSide: ExecutionSide = (direction == .long) ? .sell : .buy
            let exitTime = closedAt ?? openedAt.addingTimeInterval(3600)
            let exitFill = Execution(
                accountId: accountId,
                symbol: cleanSymbol,
                side: exitSide,
                quantity: quantity,
                price: exitP,
                fee: halfFee,
                executedAt: exitTime,
                source: "manual"
            )
            newExecutions.append(exitFill)
        }
        
        for fill in newExecutions {
            executionHashes.insert(fill.contentHash)
            executions.append(fill)
        }
        
        rebuildAccount(accountId: accountId)
        
        if let idx = trades.firstIndex(where: { t in
            t.accountId == accountId &&
            t.symbol == cleanSymbol &&
            abs(t.openedAt.timeIntervalSince(openedAt)) < 2
        }) {
            trades[idx].notes = notes
            trades[idx].tags = tags
            trades[idx].mistakes = mistakes
            trades[idx].rating = rating
            trades[idx].stopLoss = stopLoss
            trades[idx].profitTarget = profitTarget
            trades[idx].playbookId = playbookId
            
            if let pbId = playbookId, !ruleAssessments.isEmpty {
                let tradeKey = trades[idx].key
                for (rule, followed) in ruleAssessments {
                    let assessment = PlaybookRuleAssessment(
                        tradeKey: tradeKey,
                        playbookId: pbId,
                        rule: rule,
                        followed: followed
                    )
                    if let aIdx = playbookAssessments.firstIndex(where: { $0.id == assessment.id }) {
                        playbookAssessments[aIdx] = assessment
                    } else {
                        playbookAssessments.append(assessment)
                    }
                }
            }
        }
        
        saveToDisk(immediate: true)
        AppLogger.info("Added manual trade for \(cleanSymbol). Total trades now: \(trades.count)")
        SyncManager.shared.scheduleBackgroundCloudBackup(delaySeconds: 5)
    }
    
    public func deleteTrade(key: String) {
        guard let trade = trades.first(where: { $0.key == key }) else { return }
        let idsToDelete = Set(trade.executionIds)
        
        let deletedFills = executions.filter { idsToDelete.contains($0.id) }
        for fill in deletedFills {
            executionHashes.remove(fill.contentHash)
        }
        executions.removeAll { idsToDelete.contains($0.id) }
        
        rebuildAccount(accountId: trade.accountId)
        saveToDisk(immediate: true)
        AppLogger.info("Deleted trade \(key), remaining trades: \(trades.count)")
        Task {
            try? await SupabaseService.shared.deleteTrade(key: key)
        }
    }

    public func updateManualTrade(
        key: String,
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal?,
        openedAt: Date,
        closedAt: Date?,
        fee: Decimal = 0,
        notes: String? = nil,
        tags: [String] = [],
        mistakes: [String] = [],
        rating: Int? = nil,
        stopLoss: Decimal? = nil,
        profitTarget: Decimal? = nil,
        playbookId: String? = nil
    ) {
        guard let trade = trades.first(where: { $0.key == key }) else { return }
        let accId = trade.accountId
        
        let oldIds = Set(trade.executionIds)
        let oldFills = executions.filter { oldIds.contains($0.id) }
        for fill in oldFills {
            executionHashes.remove(fill.contentHash)
        }
        executions.removeAll { oldIds.contains($0.id) }
        
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let entrySide: ExecutionSide = (direction == .long) ? .buy : .sell
        let halfFee = (exitPrice != nil) ? (fee / 2) : fee
        
        let entryFill = Execution(
            accountId: accId,
            symbol: cleanSymbol,
            side: entrySide,
            quantity: quantity,
            price: entryPrice,
            fee: halfFee,
            executedAt: openedAt,
            source: "manual"
        )
        var newExecutions = [entryFill]
        
        if let exitP = exitPrice {
            let exitSide: ExecutionSide = (direction == .long) ? .sell : .buy
            let exitTime = closedAt ?? openedAt.addingTimeInterval(3600)
            let exitFill = Execution(
                accountId: accId,
                symbol: cleanSymbol,
                side: exitSide,
                quantity: quantity,
                price: exitP,
                fee: halfFee,
                executedAt: exitTime,
                source: "manual"
            )
            newExecutions.append(exitFill)
        }
        
        for fill in newExecutions {
            executionHashes.insert(fill.contentHash)
            executions.append(fill)
        }
        
        rebuildAccount(accountId: accId)
        
        if let idx = trades.firstIndex(where: { t in
            t.accountId == accId &&
            t.symbol == cleanSymbol &&
            abs(t.openedAt.timeIntervalSince(openedAt)) < 2
        }) {
            trades[idx].notes = notes
            trades[idx].tags = tags
            trades[idx].mistakes = mistakes
            trades[idx].rating = rating
            trades[idx].stopLoss = stopLoss
            trades[idx].profitTarget = profitTarget
            trades[idx].playbookId = playbookId
        }
        
        saveToDisk(immediate: true)
        AppLogger.info("Updated manual trade for \(cleanSymbol). Total trades now: \(trades.count)")
        Task {
            try? await SupabaseService.shared.deleteTrade(key: key)
        }
        SyncManager.shared.scheduleBackgroundCloudBackup(delaySeconds: 5)
    }
    
    public func resetAllData() {
        executions.removeAll()
        executionHashes.removeAll()
        trades.removeAll()
        calendarNotes.removeAll()
        propAccounts.removeAll()
        propEntries.removeAll()
        propReceipts.removeAll()
        propAudits.removeAll()
        attachments.removeAll()
        createInitialDefaultAccount()
        rebuildAllAccounts()
        saveToDisk(immediate: true)
        AppLogger.info("Reset all trading data to 100% clean blank state.")
    }
    
    public func loadDemoData() {
        if let existing = accounts.first(where: { $0.broker == "demo" }) {
            if existing.archivedAt != nil {
                archiveAccount(id: existing.id, archived: false)
            }
            selectedAccountId = existing.id
            return
        }
        
        let demoAccountId = JournalIds.newId()
        let demoAccount = Account(
            id: demoAccountId,
            name: "Demo data",
            broker: "demo",
            kind: .import,
            currency: "USD",
            initialBalance: 25000,
            profitCalcMethod: .fifo,
            autoSync: false,
            visibleInJournal: true
        )
        accounts.append(demoAccount)
        
        var fills: [Execution] = []
        var s: Double = 42
        let rnd: () -> Double = {
            s = Double((Int64(s * 1103515245) + 12345) % 2147483648)
            return s / 2147483648.0
        }
        
        struct Spec {
            let symbol: String
            let price: Double
            let qtyMin: Double
            let qtyMax: Double
        }
        let symbols: [Spec] = [
            Spec(symbol: "NVDA", price: 128, qtyMin: 50, qtyMax: 150),
            Spec(symbol: "TSLA", price: 242, qtyMin: 30, qtyMax: 100),
            Spec(symbol: "AAPL", price: 226, qtyMin: 50, qtyMax: 200),
            Spec(symbol: "AMD", price: 158, qtyMin: 80, qtyMax: 250),
            Spec(symbol: "META", price: 512, qtyMin: 20, qtyMax: 60),
            Spec(symbol: "SPY", price: 556, qtyMin: 40, qtyMax: 120)
        ]
        
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        
        func atDate(day: Date, minute: Int) -> Date {
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 13
            comps.minute = 30 + minute
            comps.second = Int(rnd() * 60)
            comps.timeZone = TimeZone(secondsFromGMT: 0)
            return cal.date(from: comps) ?? day
        }
        
        for back in stride(from: 90, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let dow = cal.component(.weekday, from: day)
            if dow == 1 || dow == 7 { continue }
            if rnd() < 0.28 { continue }
            
            let tradesToday = 1 + Int(rnd() * 4)
            var minute = 5 + Int(rnd() * 40)
            
            for _ in 0..<tradesToday {
                let spec = symbols[Int(rnd() * Double(symbols.count)) % symbols.count]
                let isLong = rnd() < 0.72
                let quantity = round(spec.qtyMin + rnd() * (spec.qtyMax - spec.qtyMin))
                let entry = spec.price * (0.97 + rnd() * 0.06)
                let isWin = rnd() < 0.56
                let magnitude = isWin ? (0.004 + rnd() * 0.014) : (0.003 + rnd() * 0.008)
                let exit = entry + (isWin ? 1.0 : -1.0) * (isLong ? 1.0 : -1.0) * magnitude * entry
                let hold = 4 + Int(rnd() * 55)
                let entrySide: ExecutionSide = isLong ? .buy : .sell
                let exitSide: ExecutionSide = isLong ? .sell : .buy
                let entryTime = atDate(day: day, minute: minute)
                let exitTime = atDate(day: day, minute: minute + hold)
                
                fills.append(Execution(
                    accountId: demoAccountId,
                    symbol: spec.symbol,
                    side: entrySide,
                    quantity: Decimal(quantity),
                    price: Decimal(string: String(format: "%.2f", entry)) ?? Decimal(entry),
                    fee: 1,
                    executedAt: entryTime,
                    assetClass: "equity",
                    source: "import"
                ))
                
                if rnd() < 0.3 && quantity >= 60 {
                    let half = round(quantity / 2.0)
                    let mid = entry + (exit - entry) * (0.4 + rnd() * 0.3)
                    let midTime = atDate(day: day, minute: minute + hold / 2)
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(half),
                        price: Decimal(string: String(format: "%.2f", mid)) ?? Decimal(mid),
                        fee: 1,
                        executedAt: midTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(quantity - half),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                } else {
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(quantity),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                }
                minute += hold + 10 + Int(rnd() * 50)
                if minute > 340 { break }
            }
        }
        
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now) {
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "NVDA",
                side: .buy,
                quantity: 120,
                price: 131.42,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 44),
                assetClass: "equity",
                source: "import"
            ))
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "SPY",
                side: .sell,
                quantity: 80,
                price: 561.18,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 92),
                assetClass: "equity",
                source: "import"
            ))
        }
        
        importExecutions(accountId: demoAccountId, newExecutions: fills)
        selectedAccountId = demoAccountId
        saveToDisk(immediate: true)
        AppLogger.info("Loaded demo data: \(fills.count) executions for demo account \(demoAccountId)")
    }
    
    // MARK: - CSV Export
    
    /// Exports all trades to standard CSV format
    public func exportTradesCsv() -> String {
        var lines = ["Key,Account,Symbol,Direction,Status,OpenedAt,ClosedAt,Quantity,AvgEntry,AvgExit,GrossPnL,Fees,Swap,NetPnL,Notes,Tags"]
        let f = ISO8601DateFormatter()
        
        let escapeCsv: (String) -> String = { text in
            if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
                let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return text
        }
        
        for t in trades {
            let row = [
                escapeCsv(t.key),
                escapeCsv(t.accountId),
                escapeCsv(t.symbol),
                escapeCsv(t.direction.rawValue),
                escapeCsv(t.status.rawValue),
                escapeCsv(f.string(from: t.openedAt)),
                escapeCsv(t.closedAt.map { f.string(from: $0) } ?? ""),
                "\(t.quantity)",
                "\(t.avgEntry)",
                t.avgExit.map { "\($0)" } ?? "",
                "\(t.grossPnl)",
                "\(t.fees)",
                "\(t.swapAmount)",
                "\(t.netPnl)",
                escapeCsv(t.notes ?? ""),
                escapeCsv(t.tags.joined(separator: ";"))
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
}
