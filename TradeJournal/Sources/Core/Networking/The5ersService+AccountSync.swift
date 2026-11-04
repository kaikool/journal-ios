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
            
            var rawAccountsList: [[String: Any]] = []
            var seenAccountRefs = Set<String>()
            var successfulArgTemplate: [String: Any]? = nil
            
            for page in 1...20 {
                if Task.isCancelled || isCancelledByUser { throw CancellationError() }
                lastStatus = "Loading The5ers accounts (Page \(page))..."
                let candidateArgsList: [[String: Any]] = {
                    if let template = successfulArgTemplate {
                        var pArgs = template
                        pArgs["page"] = page
                        return [pArgs]
                    }
                    return [
                        [
                            "operation": "list",
                            "page": page,
                            "limit": 50,
                            "contract_version": "1.0",
                            "request_context": ["timezone": "UTC", "locale": "en"]
                        ],
                        [
                            "operation": "list",
                            "page": page,
                            "limit": 50
                        ],
                        ["operation": "list"],
                        [:]
                    ]
                }()
                
                var accountResult: [String: Any]? = nil
                var lastErr: String = ""
                
                for candidateArgs in candidateArgsList {
                    if let res = try? await callMcpTool(name: "the5ers_account", arguments: candidateArgs) {
                        let isErr = (res["isError"] as? Bool) ?? false
                        if !isErr {
                            accountResult = res
                            if successfulArgTemplate == nil {
                                successfulArgTemplate = candidateArgs
                            }
                            break
                        } else {
                            lastErr = (res["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ") ?? ""
                        }
                    }
                }
                
                guard let finalAccountResult = accountResult else {
                    if page == 1 {
                        let msg = lastErr.isEmpty ? "The5ers MCP returned an error when fetching accounts" : lastErr
                        throw NSError(domain: "The5ersMCP", code: 500, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                    break
                }
                
                let unwrappedAccounts = unwrapMcpToolResult(finalAccountResult)
                let pageRows = extractMcpCollection(unwrappedAccounts, collectionKey: "accounts")
                if pageRows.isEmpty { break }
                
                var newCount = 0
                for item in pageRows {
                    let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? "")
                    if !ref.isEmpty && !seenAccountRefs.contains(ref) {
                        seenAccountRefs.insert(ref)
                        rawAccountsList.append(item)
                        newCount += 1
                    }
                }
                
                // Break pagination loop if end of stream reached, or candidateArgs didn't include pagination, or no new accounts
                if pageRows.count < 50 || newCount == 0 || (successfulArgTemplate?["page"] == nil && page == 1) {
                    break
                }
            }
            
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
            var allCandidatePayoutAccounts: [The5ersMcpAccount] = []
            for item in rawAccountsList {
                if item["contest_account_ref"] != nil && item["ref"] == nil { continue }
                let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? "")
                guard !ref.isEmpty else { continue }
                let label = String(describing: item["label"] ?? item["name"] ?? "The5ers Account")
                let bal = Decimal(string: String(describing: item["balance"] ?? item["effectiveBalance"] ?? "0")) ?? 0
                let eq = Decimal(string: String(describing: item["equity"] ?? bal)) ?? bal
                let curr = String(describing: item["currency"] ?? "USD")
                let status = String(describing: item["status"] ?? "active")
                let prog = String(describing: item["type"] ?? item["accountType"] ?? item["program"] ?? "")
                let platform = String(describing: item["tradingPlatform"] ?? item["platform"] ?? item["tradingSystem"] ?? "MT5")
                let createdAt = item["createdAt"] as? String ?? item["creationDate"] as? String ?? item["created_at"] as? String
                
                let isFunded = prog.lowercased().contains("fund") ||
                               prog.lowercased().contains("instant") ||
                               prog.lowercased().contains("live") ||
                               label.lowercased().contains("fund") ||
                               label.lowercased().contains("live")
                
                if isFunded {
                    let stamp: String = {
                        if let raw = createdAt, let d = FlexibleDateParser.parse(raw) {
                            let iso = ISO8601DateFormatter()
                            iso.formatOptions = [.withInternetDateTime]
                            return iso.string(from: d)
                        }
                        return createdAt ?? ""
                    }()
                    let stableId = !stamp.isEmpty ? JournalIds.sha256Hex([label, platform, stamp]) : JournalIds.sha256Hex([label, platform])
                    let mcpAcc = The5ersMcpAccount(
                        id: stableId,
                        ref: ref,
                        label: label,
                        platform: platform,
                        balance: bal,
                        equity: eq,
                        currency: curr,
                        status: status,
                        program: prog.isEmpty ? "funded" : prog,
                        startingBalance: bal,
                        createdAt: createdAt,
                        profitAndLoss: nil,
                        dailyProfitAndLoss: nil,
                        unrealized: 0,
                        totalNetProfit: nil,
                        totalFees: nil,
                        totalTrades: nil,
                        winRate: nil,
                        profitFactor: nil,
                        tradingBlocked: status.lowercased() == "disabled" || status.lowercased() == "closed",
                        profitTarget: nil,
                        maxLoss: nil,
                        maxDailyLoss: nil,
                        minTradingDays: nil,
                        currentTradingDays: nil,
                        winningDays: nil,
                        currentStepName: nil
                    )
                    allCandidatePayoutAccounts.append(mcpAcc)
                }
            }
            
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
                
                // Authoritative initial capital detection (docs/the5ers.md:12: Never substitute current balance for starting capital)
                var explicitStartBal: Decimal? = nil
                let startCandidates: [Any?] = [
                    item["startingBalance"],
                    item["initialBalance"],
                    item["initial_balance"],
                    item["starting_balance"],
                    item["accountSize"],
                    item["account_size"],
                    item["nominalBalance"]
                ]
                for cand in startCandidates {
                    if let num = cand as? NSNumber, num.doubleValue > 0 {
                        explicitStartBal = Decimal(string: num.stringValue); break
                    } else if let s = cand as? String, let dec = Decimal(string: s.trimmingCharacters(in: .whitespaces)), dec > 0 {
                        explicitStartBal = dec; break
                    }
                }
                
                // Sequentially query Authoritative Balance, Statistics, Journey, and Health
                var accProfitAndLoss: Decimal? = nil
                var accDailyProfitAndLoss: Decimal? = nil
                var accUnrealized: Decimal? = nil
                var accTradingBlocked: Bool? = nil
                var accTotalTrades: Int? = nil
                var accWinRate: Double? = nil
                var accProfitFactor: Double? = nil
                var accTotalFees: Decimal? = nil
                var authoritativeWinningDays: Int? = nil
                var authoritativeTradingDays: Int? = nil
                var authoritativeProgramName: String? = nil
                var authoritativeStepName: String? = nil
                var authoritativeAccountType: String? = nil
                var authoritativeProfitTarget: Decimal? = nil
                var authoritativeMaxLoss: Decimal? = nil
                var authoritativeMaxDailyLoss: Decimal? = nil
                var authoritativeMinTradingDays: Int? = nil
                
                let balArgs: [String: Any] = [
                    "operation": "balance",
                    "account_ref": ref,
                    "contract_version": "1.0"
                ]
                if let bRes = try? await callMcpTool(name: "the5ers_account", arguments: balArgs),
                   !(bRes["isError"] as? Bool ?? false) {
                    let uBal = unwrapMcpToolResult(bRes)
                    if let bDict = (uBal as? [String: Any])?["data"] as? [String: Any] ?? uBal as? [String: Any] {
                        if let initB = sourceNumber(bDict["initialBalance"] ?? bDict["baseBalance"] ?? bDict["startingBalance"]), initB > 0 {
                            explicitStartBal = initB
                        }
                        if let cb = sourceNumber(bDict["balance"]), cb > 0 {
                            bal = cb
                        }
                        if let ce = sourceNumber(bDict["equity"]), ce > 0 {
                            eq = ce
                        }
                        accProfitAndLoss = sourceNumber(bDict["profitAndLoss"] ?? bDict["profit_and_loss"] ?? bDict["pnl"] ?? bDict["netProfit"])
                        accDailyProfitAndLoss = sourceNumber(bDict["dailyProfitAndLoss"] ?? bDict["daily_profit_and_loss"] ?? bDict["dailyPnl"])
                        accUnrealized = sourceNumber(bDict["unrealized"] ?? bDict["floatingProfit"] ?? bDict["unrealizedPnl"])
                        if let tb = bDict["tradingBlocked"] as? Bool ?? (bDict["trading_blocked"] as? Bool) {
                            accTradingBlocked = tb
                        }
                        if let ml = sourceNumber(bDict["maxLoss"] ?? bDict["max_loss"]), ml != 0 {
                            authoritativeMaxLoss = abs(ml)
                        }
                        if let adl = sourceNumber(bDict["allowedDailyLosses"] ?? bDict["allowed_daily_losses"]), adl != 0 {
                            authoritativeMaxDailyLoss = abs(adl)
                        }
                    }
                }
                
                // Query Authoritative Statistics from official the5ers_account.statistics
                let statsArgs: [String: Any] = [
                    "operation": "statistics",
                    "account_ref": ref,
                    "contract_version": "1.0"
                ]
                if let sRes = try? await callMcpTool(name: "the5ers_account", arguments: statsArgs),
                   !(sRes["isError"] as? Bool ?? false) {
                    let uStats = unwrapMcpToolResult(sRes)
                    if let sRaw = (uStats as? [String: Any])?["data"] as? [String: Any] ?? uStats as? [String: Any] {
                        let sDict = sourceFields(sRaw)
                        if let tt = extractRequirementInt(sDict["totaltrades"] ?? sDict["tradescount"] ?? sDict["closedtrades"]) {
                            accTotalTrades = tt
                        }
                        if let wrDec = sourceNumber(sDict["winrate"] ?? sDict["winningrate"]) {
                            let wr = NSDecimalNumber(decimal: wrDec).doubleValue
                            accWinRate = wr > 1.0 ? wr / 100.0 : wr
                        }
                        if let pfDec = sourceNumber(sDict["profitfactor"]) {
                            accProfitFactor = NSDecimalNumber(decimal: pfDec).doubleValue
                        }
                        if let tf = sourceNumber(sDict["totalfees"] ?? sDict["fees"] ?? sDict["commissions"]) {
                            accTotalFees = abs(tf)
                        }
                        if accProfitAndLoss == nil,
                           let tnp = sourceNumber(sDict["totalnetprofit"] ?? sDict["netprofit"] ?? sDict["profitandloss"] ?? sDict["pnl"]) {
                            accProfitAndLoss = tnp
                        }
                        if let wd = extractRequirementInt(sDict["winningdays"] ?? sDict["profitabledays"]) {
                            authoritativeWinningDays = wd
                        }
                        if let td = extractRequirementInt(sDict["tradingdays"] ?? sDict["activedays"]) {
                            authoritativeTradingDays = td
                        }
                    }
                }
                
                // Resolve standard prop tier from metadata dynamically (e.g. "$100K", "50K", "25,000")
                var resolvedStartBal: Decimal? = {
                    if let ex = explicitStartBal, ex > 0 { return ex }
                    let combined = "\(label) \(prog)"
                    // Pattern 1: $100K, 50k, 25K
                    if let regexK = try? NSRegularExpression(pattern: #"(?i)\$?(\d{1,4})\s*k\b"#),
                       let match = regexK.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
                       let range = Range(match.range(at: 1), in: combined),
                       let val = Decimal(string: String(combined[range])), val > 0 {
                        return val * 1000
                    }
                    // Pattern 2: $100,000, 50,000, 25000
                    if let regexNum = try? NSRegularExpression(pattern: #"\$?(\d{1,3}(?:,\d{3})+|\d{4,7})\b"#),
                       let match = regexNum.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
                       let range = Range(match.range(at: 1), in: combined) {
                        let cleaned = String(combined[range]).replacingOccurrences(of: ",", with: "")
                        if let val = Decimal(string: cleaned), val >= 1000 {
                            return val
                        }
                    }
                    return nil
                }()
                
                // Also extract any embedded rules/limits directly from the account list item
                parseProgramAndHealthPayload(
                    item,
                    startingBalance: &resolvedStartBal,
                    profitTarget: &authoritativeProfitTarget,
                    maxLoss: &authoritativeMaxLoss,
                    maxDailyLoss: &authoritativeMaxDailyLoss,
                    minTradingDays: &authoritativeMinTradingDays,
                    currentTradingDays: &authoritativeTradingDays,
                    winningDays: &authoritativeWinningDays,
                    programName: &authoritativeProgramName,
                    stepName: &authoritativeStepName,
                    accountType: &authoritativeAccountType
                )
                
                // Query official the5ers_program (rules, progression, journey) and the5ers_consistency (list)
                let existingCachedProp = dataStore.propAccounts.first(where: { TradeDataStore.isSameAccountId($0.id, journalAccId) })
                let needsProgramDetails = isRawActive ||
                                          existingCachedProp == nil ||
                                          (existingCachedProp?.name.hasPrefix("The5ers ") ?? true) ||
                                          existingCachedProp?.profitTargetMinor == nil ||
                                          existingCachedProp?.maxDailyLossMinor == nil ||
                                          existingCachedProp?.maxLossMinor == nil
                if needsProgramDetails {
                    let programOps = isRawActive ? ["rules", "progression", "journey"] : ["rules", "journey"]
                    for op in programOps {
                        let pArgs: [String: Any] = [
                            "operation": op,
                            "account_ref": ref,
                            "contract_version": "1.0"
                        ]
                        if let pRes = try? await callMcpTool(name: "the5ers_program", arguments: pArgs),
                           !(pRes["isError"] as? Bool ?? false) {
                            let uProg = unwrapMcpToolResult(pRes)
                            parseProgramAndHealthPayload(
                                uProg,
                                startingBalance: &resolvedStartBal,
                                profitTarget: &authoritativeProfitTarget,
                                maxLoss: &authoritativeMaxLoss,
                                maxDailyLoss: &authoritativeMaxDailyLoss,
                                minTradingDays: &authoritativeMinTradingDays,
                                currentTradingDays: &authoritativeTradingDays,
                                winningDays: &authoritativeWinningDays,
                                programName: &authoritativeProgramName,
                                stepName: &authoritativeStepName,
                                accountType: &authoritativeAccountType
                            )
                        }
                    }
                    
                    if isRawActive {
                        let consArgs: [String: Any] = [
                            "operation": "list",
                            "account_ref": ref,
                            "contract_version": "1.0"
                        ]
                        if let cRes = try? await callMcpTool(name: "the5ers_consistency", arguments: consArgs),
                           !(cRes["isError"] as? Bool ?? false) {
                            let uCons = unwrapMcpToolResult(cRes)
                            parseProgramAndHealthPayload(
                                uCons,
                                startingBalance: &resolvedStartBal,
                                profitTarget: &authoritativeProfitTarget,
                                maxLoss: &authoritativeMaxLoss,
                                maxDailyLoss: &authoritativeMaxDailyLoss,
                                minTradingDays: &authoritativeMinTradingDays,
                                currentTradingDays: &authoritativeTradingDays,
                                winningDays: &authoritativeWinningDays,
                                programName: &authoritativeProgramName,
                                stepName: &authoritativeStepName,
                                accountType: &authoritativeAccountType
                            )
                        }
                    }
                }
                
                // For active accounts, also query the5ers_account.health to get authoritative currency limits and profitable-days consistency
                if isRawActive && accTradingBlocked != true {
                    let healthArgs: [String: Any] = [
                        "operation": "health",
                        "account_ref": ref,
                        "contract_version": "1.0"
                    ]
                    if let hRes = try? await callMcpTool(name: "the5ers_account", arguments: healthArgs),
                       !(hRes["isError"] as? Bool ?? false) {
                        let uHealth = unwrapMcpToolResult(hRes)
                        parseProgramAndHealthPayload(
                            uHealth,
                            startingBalance: &resolvedStartBal,
                            profitTarget: &authoritativeProfitTarget,
                            maxLoss: &authoritativeMaxLoss,
                            maxDailyLoss: &authoritativeMaxDailyLoss,
                            minTradingDays: &authoritativeMinTradingDays,
                            currentTradingDays: &authoritativeTradingDays,
                            winningDays: &authoritativeWinningDays,
                            programName: &authoritativeProgramName,
                            stepName: &authoritativeStepName,
                            accountType: &authoritativeAccountType
                        )
                    }
                }
                
                let defaultName: String = {
                    if !needsProgramDetails,
                       let cachedName = existingCachedProp?.name,
                       cachedName.contains(" · "),
                       !cachedName.contains(" - "),
                       !cachedName.hasPrefix("The5ers ") {
                        return cachedName
                    }
                    return Self.the5ersDefaultName(
                        from: item,
                        fallbackLabel: label,
                        platform: platform,
                        startingBalance: resolvedStartBal,
                        balance: bal,
                        authoritativeProgramName: authoritativeProgramName,
                        authoritativeStepName: authoritativeStepName,
                        authoritativeAccountType: authoritativeAccountType
                    )
                }()
                let cleanLabel = defaultName.isEmpty ? Formatters.cleanAccountName(label, balance: resolvedStartBal) : defaultName
                
                // Fallback to standard The5ers program specifications when MCP omits a specific rule threshold
                if let sb = resolvedStartBal, sb > 0 {
                    let combinedText = "\(cleanLabel) \(authoritativeProgramName ?? "") \(authoritativeStepName ?? "") \(authoritativeAccountType ?? "") \(prog)".lowercased()
                    let isStep2 = combinedText.contains("- 2") || combinedText.contains("step 2") || combinedText.contains("phase 2") || combinedText.contains("verification")
                    let isBootcamp = combinedText.contains("bootcamp")
                    let isHyperOrInstant = combinedText.contains("hyper") || combinedText.contains("instant")
                    if authoritativeProfitTarget == nil {
                        let pct: Decimal = isHyperOrInstant ? 10 : (isBootcamp ? 6 : (isStep2 ? 5 : 8))
                        authoritativeProfitTarget = (sb * pct) / 100
                    }
                    if authoritativeMaxLoss == nil {
                        let pct: Decimal = isHyperOrInstant ? 6 : (isBootcamp ? 5 : 10)
                        authoritativeMaxLoss = (sb * pct) / 100
                    }
                    if authoritativeMaxDailyLoss == nil {
                        let pct: Decimal = isHyperOrInstant ? 3 : (isBootcamp ? 3 : 5)
                        authoritativeMaxDailyLoss = (sb * pct) / 100
                    }
                    if authoritativeMinTradingDays == nil && !isHyperOrInstant && !isBootcamp {
                        authoritativeMinTradingDays = 3
                    }
                    if bal > 0 {
                        let journalIdForPayout = stableId.hasPrefix("the5ers_") ? stableId : "the5ers_\(stableId)"
                        let settledAccountPayouts = dataStore.propEntries
                            .filter { entry in
                                guard entry.firm == "The5ers", entry.kind == "payout", entry.status == .completed, !entry.voided, let accId = entry.accountId else { return false }
                                return accId == journalIdForPayout || TradeDataStore.isSameAccountId(accId, journalIdForPayout)
                            }
                            .reduce(Decimal.zero) { $0 + Decimal($1.amountMinor) / 100 }
                        accProfitAndLoss = (bal - sb) + settledAccountPayouts
                    }
                }
                
                let mcpAcc = The5ersMcpAccount(
                    id: stableId,
                    ref: ref,
                    label: cleanLabel,
                    platform: platform,
                    balance: bal,
                    equity: eq,
                    currency: curr,
                    status: status,
                    program: prog,
                    startingBalance: resolvedStartBal,
                    createdAt: createdAt,
                    profitAndLoss: accProfitAndLoss,
                    dailyProfitAndLoss: accDailyProfitAndLoss,
                    unrealized: accUnrealized,
                    totalNetProfit: accProfitAndLoss,
                    totalFees: accTotalFees,
                    totalTrades: accTotalTrades,
                    winRate: accWinRate,
                    profitFactor: accProfitFactor,
                    tradingBlocked: accTradingBlocked,
                    profitTarget: authoritativeProfitTarget,
                    maxLoss: authoritativeMaxLoss,
                    maxDailyLoss: authoritativeMaxDailyLoss,
                    minTradingDays: authoritativeMinTradingDays,
                    currentTradingDays: authoritativeTradingDays,
                    winningDays: authoritativeWinningDays,
                    currentStepName: authoritativeStepName
                )
                accountsList.append(mcpAcc)
                
                // Immediately register/update this account in dataStore
                upsertAccountIntoStore(mcpAcc, into: dataStore)
                
                // Stream positions immediately for this account (never skip if account has 0 trades locally)
                let existingTradesForAccount = dataStore.trades.filter {
                    $0.accountId == mcpAcc.id ||
                    TradeDataStore.isSameAccountId($0.accountId, mcpAcc.id) ||
                    TradeDataStore.isSameAccountId($0.accountId, "the5ers_\(mcpAcc.id)")
                }
                let shouldFetchPositions = isRawActive ||
                                           existingTradesForAccount.isEmpty ||
                                           (accTotalTrades == nil || (accTotalTrades ?? 0) > 0) ||
                                           abs(accProfitAndLoss ?? 0) > 0.005 ||
                                           (resolvedStartBal.map { abs(bal - $0) > 0.005 } ?? false)
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
    
}
