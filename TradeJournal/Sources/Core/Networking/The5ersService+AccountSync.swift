import Foundation

// MARK: - The5ers Account & Program Health Synchronization
extension The5ersService {
    @MainActor
    public func syncWithTradeStore(dataStore: TradeDataStore) async throws -> Int {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bearer Session Token not configured"])
        }
        
        isCancelledByUser = false
        isSyncing = true
        lastStatus = "Connecting to The5ers MCP Hub (Protocol 2025-03-26)..."
        defer { isSyncing = false }
        
        do {
            // Always start sync with a fresh MCP session handshake so account_ref tokens are newly minted
            self.isSessionInitialized = false
            self.mcpSessionId = nil
            try await ensureInitialized()
            await refreshAvailableTools()
            
            var rawAccountsList = try await fetchAllRawAccounts()
            
            // Sort raw accounts so active accounts are enriched and streamed to UI first
            rawAccountsList.sort { a, b in
                let sa = String(describing: a["status"] ?? "").lowercased()
                let sb = String(describing: b["status"] ?? "").lowercased()
                let aAct = sa == "active" || sa == "trading" || sa == "available" || sa == "open"
                let bAct = sb == "active" || sb == "trading" || sb == "available" || sb == "open"
                return aAct && !bAct
            }
            
            // Immediately ensure default placeholder account is removed
            if !rawAccountsList.isEmpty {
                dataStore.accounts.removeAll(where: { $0.id == "default-acc" })
            }
            
            // Immediately identify all candidate funded / live / instant accounts across the entire raw inventory
            let allCandidatePayoutAccounts = extractCandidatePayoutAccounts(from: rawAccountsList)
            
            let (accountsList, importedPositionsCount) = try await processAccountsInventory(
                rawAccountsList: rawAccountsList,
                allCandidatePayoutAccounts: allCandidatePayoutAccounts,
                dataStore: dataStore
            )
            
            if accountsList.isEmpty {
                lastStatus = "The5ers MCP responded successfully but no trading accounts were found."
                return 0
            }
            
            if Task.isCancelled || isCancelledByUser { throw CancellationError() }
            
            // Sync purchases and payouts across all accounts (ensures attribution includes any newly enriched inactive accounts)
            await syncPurchases(into: dataStore, targetAccounts: accountsList)
            
            if Task.isCancelled || isCancelledByUser { throw CancellationError() }
            
            let finalPayoutTargets = allCandidatePayoutAccounts.isEmpty ? accountsList : allCandidatePayoutAccounts
            await syncPayouts(into: dataStore, targetAccounts: finalPayoutTargets)
            
            lastSyncTime = Date()
            dataStore.rebuildAllAccounts()
            
            if dataStore.selectedAccountId == "default-acc" || dataStore.selectedAccountId == "all" || dataStore.selectedAccountId.isEmpty || !dataStore.accounts.contains(where: { $0.id == dataStore.selectedAccountId || TradeDataStore.isSameAccountId($0.id, dataStore.selectedAccountId) }) {
                if let targetId = dataStore.mostRecentActiveAccount?.id ?? dataStore.visibleAccounts.first?.id ?? dataStore.accounts.first?.id {
                    dataStore.selectAccount(id: targetId)
                }
            }
            
            dataStore.saveToDisk()
            dataStore.objectWillChange.send()
            let activeCount = accountsList.filter {
                let s = $0.status.lowercased()
                return (s == "active" || s == "available" || s == "open" || s == "trading") && $0.tradingBlocked != true
            }.count
            lastStatus = "Successfully synced \(accountsList.count) accounts (\(activeCount) active) and \(importedPositionsCount) positions from The5ers MCP."
            
            // Automatically push newly synchronized The5ers accounts, trades, and prop entries to Supabase cloud
            if SupabaseService.shared.isConfigured {
                Task {
                    await dataStore.syncWithSupabase(isBackground: true)
                }
            }
            
            return accountsList.count
        } catch {
            if isCancelledByUser {
                isCancelledByUser = false
                lastStatus = "Synchronization cancelled by user."
                throw CancellationError()
            }
            lastStatus = "The5ers MCP sync error: \(error.localizedDescription)"
            throw error
        }
    }
    

    @MainActor
    private func processAccountsInventory(
        rawAccountsList: [[String: Any]],
        allCandidatePayoutAccounts: [The5ersMcpAccount],
        dataStore: TradeDataStore
    ) async throws -> (accounts: [The5ersMcpAccount], positionsCount: Int) {
            var accountsList: [The5ersMcpAccount] = []
            var importedPositionsCount = 0
            var didRunInitialPurchasesAndPayouts = false
            
            for (accIdx, item) in rawAccountsList.enumerated() {
                if Task.isCancelled || isCancelledByUser { throw CancellationError() }
                // Ignore contest accounts which belong to a separate space and cannot be read by standard operations
                if item["contest_account_ref"] != nil && item["ref"] == nil {
                    continue
                }
                let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? UUID().uuidString)
                let label = String(describing: item["label"] ?? item["name"] ?? "The5ers Account")
                var bal = Decimal(string: String(describing: item["balance"] ?? item["effectiveBalance"] ?? "0")) ?? 0
                var eq = Decimal(string: String(describing: item["equity"] ?? bal)) ?? bal
                let curr = String(describing: item["currency"] ?? "USD")
                let status = String(describing: item["status"] ?? "active")
                let prog = String(describing: item["type"] ?? item["accountType"] ?? item["program"] ?? "funded")
                let platform = String(describing: item["tradingPlatform"] ?? item["platform"] ?? item["tradingSystem"] ?? "MT5")
                let createdAt = item["createdAt"] as? String ?? item["creationDate"] as? String ?? item["created_at"] as? String
                
                let rawStatusLower = status.trimmingCharacters(in: .whitespaces).lowercased()
                let isRawActive = (rawStatusLower == "active" || rawStatusLower == "open" || rawStatusLower == "available" || rawStatusLower == "trading")
                
                // Before processing the first inactive account, sync purchases & payouts so Active Accounts + Expenses + Payouts are 100% live within seconds!
                if !isRawActive && !didRunInitialPurchasesAndPayouts && !accountsList.isEmpty {
                    didRunInitialPurchasesAndPayouts = true
                    await syncPurchases(into: dataStore, targetAccounts: accountsList)
                    let payoutScanTargets = allCandidatePayoutAccounts.isEmpty ? accountsList : allCandidatePayoutAccounts
                    await syncPayouts(into: dataStore, targetAccounts: payoutScanTargets)
                    dataStore.invalidatePerformanceCaches()
                    dataStore.objectWillChange.send()
                }
                
                // Deterministic persistent account ID (source-repo/apps/web/src/server/the5ers/data.ts:173-175: sha256([label, platform, stamp]))
                // Ephemeral opaque refs expire after 10m and are never used as persistent journal identity (docs/the5ers.md:16)
                let stamp: String = {
                    if let raw = createdAt, let d = FlexibleDateParser.parse(raw) {
                        let iso = ISO8601DateFormatter()
                        iso.formatOptions = [.withInternetDateTime]
                        return iso.string(from: d)
                    }
                    return createdAt ?? ""
                }()
                let stableId: String = {
                    if !stamp.isEmpty {
                        return JournalIds.sha256Hex([label, platform, stamp])
                    } else {
                        return JournalIds.sha256Hex([label, platform])
                    }
                }()
                let journalAccId = stableId.hasPrefix("the5ers_") ? stableId : "the5ers_\(stableId)"
                
                // Check if this is an already-cached, reconciled INACTIVE account so we can skip redundant network RPCs
                if !isRawActive,
                   let cachedProp = dataStore.propAccounts.first(where: { TradeDataStore.isSameAccountId($0.id, journalAccId) }),
                   cachedProp.status != .active,
                   let cachedPnlMinor = cachedProp.netPnlMinor,
                   let cachedSizeMinor = cachedProp.sizeMinor, cachedSizeMinor > 0,
                   !cachedProp.name.hasPrefix("The5ers ") {
                    let targetId = cachedProp.journalAccountId ?? journalAccId
                    let existingClosed = dataStore.trades.filter {
                        ($0.accountId == targetId || TradeDataStore.isSameAccountId($0.accountId, targetId)) && $0.status != .open && $0.closedAt != nil
                    }
                    let expectedTrades = cachedProp.totalTrades ?? 0
                    let cachedPnlDec = Decimal(cachedPnlMinor) / 100
                    let tradesPnlSum = existingClosed.reduce(Decimal.zero) { $0 + $1.netPnl }
                    let isReconciled = !existingClosed.isEmpty &&
                                       (expectedTrades == 0 || abs(existingClosed.count - expectedTrades) == 0) &&
                                       abs(tradesPnlSum - cachedPnlDec) <= 1.0
                    if isReconciled {
                        let cachedAcc = The5ersMcpAccount(
                            id: stableId,
                            ref: ref,
                            label: cachedProp.name,
                            platform: platform,
                            balance: Decimal(cachedProp.balanceMinor ?? 0) / 100,
                            equity: cachedProp.equityMinor.map { Decimal($0) / 100 } ?? (Decimal(cachedProp.balanceMinor ?? 0) / 100),
                            currency: cachedProp.currency,
                            status: status,
                            program: cachedProp.program.rawValue,
                            startingBalance: Decimal(cachedSizeMinor) / 100,
                            createdAt: createdAt,
                            profitAndLoss: cachedPnlDec,
                            dailyProfitAndLoss: nil,
                            unrealized: 0,
                            totalNetProfit: cachedPnlDec,
                            totalFees: cachedProp.totalFeesMinor.map { Decimal($0) / 100 },
                            totalTrades: cachedProp.totalTrades,
                            winRate: cachedProp.winRate,
                            profitFactor: cachedProp.profitFactor,
                            tradingBlocked: cachedProp.status == .closed || cachedProp.status == .breached,
                            profitTarget: cachedProp.profitTargetMinor.map { Decimal($0) / 100 },
                            maxLoss: cachedProp.maxLossMinor.map { Decimal($0) / 100 },
                            maxDailyLoss: cachedProp.maxDailyLossMinor.map { Decimal($0) / 100 },
                            minTradingDays: cachedProp.minTradingDays,
                            currentTradingDays: cachedProp.currentTradingDays,
                            winningDays: cachedProp.winningDays,
                            currentStepName: cachedProp.currentStepName
                        )
                        accountsList.append(cachedAcc)
                        upsertAccountIntoStore(cachedAcc, into: dataStore)
                        continue
                    }
                }
                
                lastStatus = "Loading account (\(accIdx + 1)/\(rawAccountsList.count)): \(label)..."
                
                let (mcpAcc, shouldFetchPositions) = await enrichSingleAccount(
                    item: item,
                    ref: ref,
                    label: label,
                    platform: platform,
                    status: status,
                    prog: prog,
                    createdAt: createdAt,
                    stableId: stableId,
                    journalAccId: journalAccId,
                    isRawActive: isRawActive,
                    initialBal: bal,
                    initialEq: eq,
                    curr: curr,
                    dataStore: dataStore
                )
                
                accountsList.append(mcpAcc)
                
                // Immediately register/update this account in dataStore
                upsertAccountIntoStore(mcpAcc, into: dataStore)
                if shouldFetchPositions {
                    let embeddedPos = extractMcpCollection(item, collectionKey: "positions")
                    await syncAccountPositions(
                        for: mcpAcc,
                        embeddedPositions: embeddedPos,
                        into: dataStore,
                        importedPositionsCount: &importedPositionsCount
                    )
                }
                
                // Cross-module reconciliation: verify trades against authoritative account balance, statistics (fees/trades), and midnight_history
                await reconcileAccountTradesWithMcp(for: mcpAcc, into: dataStore)
                
                // Immediately refresh UI so active accounts, Dashboard, Calendar, Trades, and Journal update in real time
                dataStore.invalidatePerformanceCaches()
                dataStore.objectWillChange.send()
            }
            

        return (accountsList, importedPositionsCount)
    }
}
