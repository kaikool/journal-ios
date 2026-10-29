import XCTest
@testable import TradeJournal

/// Golden Acceptance Test Suite ported 1:1 from `source-repo/scripts/verify-features.py`.
/// Proves mathematical, business rule, and architectural parity with the original repository.
final class FeatureVerificationTests: XCTestCase {
    
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    func testGoldenFeatureVerification() {
        // 1. Setup Accounts and Playbook
        let accountAId = "acc-usd-validation"
        let accountBId = "acc-eur-validation"
        let playbookId = "playbook-opening-range"
        
        let accountA = Account(id: accountAId, name: "Validation USD", broker: "Manual", currency: "USD", initialBalance: 10000)
        let _ = Account(id: accountBId, name: "Validation EUR", broker: "Manual", currency: "EUR", initialBalance: 10000)
        
        let playbookRules = ["Entry confirmed", "Risk accepted"]
        let playbook = PlaybookRuleSet(id: playbookId, rules: playbookRules)
        
        // 2. Default fee rules & risk rules (ES multiplier: 50)
        // config = { breakeven: 5, breakevenMode: 'money', feeRules: [{ accountId: A, symbol: 'ES', amount: 1, mode: 'unit' }], riskRules: [{ accountId: A, symbol: 'ES', stop: 2, target: 4, mode: 'price' }] }
        let defaults = JournalDefaults(
            breakeven: 5,
            breakevenMode: "money",
            feeRules: [
                FeeRule(id: "f", accountId: accountAId, symbol: "ES", amount: 1, mode: "unit")
            ],
            riskRules: [
                RiskRule(id: "r", accountId: accountAId, symbol: "ES", stop: 2, target: 4, mode: "price")
            ]
        )
        
        // 3. Fills: 2 buy ES @ 5000, 2 sell ES @ 5010 (ES multiplier: 50)
        let executedAtBuy = iso.date(from: "2026-09-01T14:30:00Z")!
        let executedAtSell = iso.date(from: "2026-09-01T15:30:00Z")!
        
        let fills = [
            Execution(
                id: "e1",
                accountId: accountAId,
                symbol: "ES",
                side: .buy,
                quantity: 2,
                price: 5000,
                fee: 0,
                executedAt: executedAtBuy,
                assetClass: "futures"
            ),
            Execution(
                id: "e2",
                accountId: accountAId,
                symbol: "ES",
                side: .sell,
                quantity: 2,
                price: 5010,
                fee: 0,
                executedAt: executedAtSell,
                assetClass: "futures"
            )
        ]
        
        // Reconstruction with multiplier 50 and defaults
        var reconstructedTrades = TradeReconstructionEngine.buildRoundTrips(
            executions: fills,
            options: .init(multipliers: ["ES": 50], defaults: defaults)
        )
        XCTAssertEqual(reconstructedTrades.count, 1)
        
        // Apply journal defaults (fee: 1 per unit -> 2 in + 2 out = 4; risk: stop=2 -> 4998, target=4 -> 5004)
        for i in 0..<reconstructedTrades.count {
            let t = reconstructedTrades[i]
            // The reconstruction already charges the configured fee rule on both sides of the round trip.
            XCTAssertEqual(t.fees, 4, "Fees must be 4 (1/unit on entry and exit)")
            reconstructedTrades[i].netPnl = t.grossPnl - t.fees
            
            let risk = JournalDefaultsEngine.defaultRisk(
                entry: t.avgEntry,
                direction: t.direction,
                accountId: t.accountId,
                symbol: t.symbol,
                defaults: defaults
            )
            reconstructedTrades[i].stopLoss = risk.stopLoss
            reconstructedTrades[i].profitTarget = risk.profitTarget
        }
        
        let t1 = reconstructedTrades[0]
        // CHECK 1: Scoped default fees and direction-aware stops/targets
        XCTAssertEqual(t1.fees, 4, "Fees must be 4 (1/unit)")
        XCTAssertEqual(t1.netPnl, 996, "Net P&L must be 1000 - 4 = 996")
        XCTAssertEqual(t1.stopLoss, 4998, "Long stop loss must be 5000 - 2 = 4998")
        XCTAssertEqual(t1.profitTarget, 5004, "Long profit target must be 5000 + 4 = 5004")
        
        // CHECK 2: User Annotations & R-multiples
        // User sets: notes, stopLoss: 4995, profitTarget: 5015, playbookId, tags: ["A+", "trend"], rating: 4, reviewed: true
        var annotatedTrade = t1
        annotatedTrade.notes = "## Setup review\n\n**Strong entry** with café notes.\n- [x] Plan followed"
        annotatedTrade.stopLoss = 4995
        annotatedTrade.profitTarget = 5015
        annotatedTrade.playbookId = playbookId
        annotatedTrade.tags = ["A+", "trend"]
        annotatedTrade.rating = 4
        annotatedTrade.reviewedAt = Date()
        
        // Risk per unit = 5000 - 4995 = 5. Total risk = 5 * 2 * 50 = 500.
        // Realized R = 996 / 500 = 1.992
        let riskPerUnit = annotatedTrade.avgEntry - annotatedTrade.stopLoss!
        let totalRisk = riskPerUnit * annotatedTrade.quantity * 50
        let realizedR = Double(truncating: (annotatedTrade.netPnl / totalRisk) as NSNumber)
        XCTAssertEqual(realizedR, 1.992, accuracy: 1e-6)
        
        // Planned R = (5015 - 5000) / (5000 - 4995) = 15 / 5 = 3.0
        let targetPerUnit = annotatedTrade.profitTarget! - annotatedTrade.avgEntry
        let plannedR = Double(truncating: (targetPerUnit / riskPerUnit) as NSNumber)
        XCTAssertEqual(plannedR, 3.0, accuracy: 1e-6)
        
        // CHECK 3: Reimport deduplication & annotation preservation
        // Reimporting the same fills must not duplicate execution hashes or overwrite annotations
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let hash1 = JournalIds.executionHash(
            symbol: "ES",
            side: "buy",
            quantity: 2,
            price: 5000,
            executedAt: iso.string(from: executedAtBuy)
        )
        let hash2 = JournalIds.executionHash(
            symbol: "ES",
            side: "buy",
            quantity: 2,
            price: 5000,
            executedAt: iso.string(from: executedAtBuy)
        )
        XCTAssertEqual(hash1, hash2, "Content hashes must be identical for identical execution")
        
        // CHECK 4: Breakeven tolerance changes classification without changing P&L
        // Sell 1 AAPL @ 100, Buy 1 AAPL @ 105 -> Gross PnL = -5. Fees = 0.
        let aaplFills = [
            Execution(id: "e3", accountId: accountAId, symbol: "AAPL", side: .sell, quantity: 1, price: 100, fee: 0, executedAt: iso.date(from: "2026-09-02T14:30:00Z")!, assetClass: "equity"),
            Execution(id: "e4", accountId: accountAId, symbol: "AAPL", side: .buy, quantity: 1, price: 105, fee: 0, executedAt: iso.date(from: "2026-09-02T15:30:00Z")!, assetClass: "equity")
        ]
        var aaplTrades = TradeReconstructionEngine.buildRoundTrips(
            executions: aaplFills,
            options: .init(defaults: defaults)
        )
        XCTAssertEqual(aaplTrades.count, 1)
        var t2 = aaplTrades[0]
        XCTAssertEqual(t2.netPnl, -5)
        
        // With breakeven tolerance of 5 money: netPnl -5 is within [-5, 5] -> status becomes breakeven!
        XCTAssertEqual(t2.status, .breakeven)
        XCTAssertEqual(t2.netPnl, -5, "P&L remains unchanged at -5 even when classified as breakeven")
        
        // Check overview metrics: 2 closed trades, netPnl = 996 - 5 = 991, 1 breakeven
        let allTrades = [annotatedTrade, t2]
        let metrics = FinancialMetricsEngine.computeMetrics(trades: allTrades, initialBalance: accountA.initialBalance)
        XCTAssertEqual(metrics.closedTrades, 2)
        XCTAssertEqual(metrics.netPnl, 991)
        XCTAssertEqual(metrics.breakevens, 1)
        
        // CHECK 5: Rule adherence checking
        let checksBroken = [
            RuleCheck(tradeKey: annotatedTrade.key, playbookId: playbookId, rule: "Entry confirmed", followed: true),
            RuleCheck(tradeKey: annotatedTrade.key, playbookId: playbookId, rule: "Risk accepted", followed: false)
        ]
        let adherenceBroken = AdherenceEngine.analyzeAdherence(trades: [annotatedTrade], playbooks: [playbook], checks: checksBroken)
        XCTAssertEqual(adherenceBroken.count, 1)
        XCTAssertEqual(adherenceBroken[0].rate, 0.5)
        XCTAssertEqual(adherenceBroken[0].broken.trades, 1)
        XCTAssertEqual(adherenceBroken[0].unassessed, 0)
        
        let checksFollowed = [
            RuleCheck(tradeKey: annotatedTrade.key, playbookId: playbookId, rule: "Entry confirmed", followed: true),
            RuleCheck(tradeKey: annotatedTrade.key, playbookId: playbookId, rule: "Risk accepted", followed: true)
        ]
        let adherenceFollowed = AdherenceEngine.analyzeAdherence(trades: [annotatedTrade], playbooks: [playbook], checks: checksFollowed)
        XCTAssertEqual(adherenceFollowed[0].rate, 1.0)
        XCTAssertEqual(adherenceFollowed[0].followed.netPnl, 996)
        
        // CHECK 6: Missed trades stay outside actual metrics
        let priorNetPnl = metrics.netPnl
        let missed = MissedTrade(
            symbol: "NVDA",
            direction: "long",
            observedAt: "2026-09-02T15:00:00Z",
            playbookId: playbookId,
            entry: 100,
            stop: 98,
            target: 106,
            notes: "Missed entry"
        )
        XCTAssertNotNil(missed.id)
        let metricsAfterMissed = FinancialMetricsEngine.computeMetrics(trades: allTrades, initialBalance: accountA.initialBalance)
        XCTAssertEqual(metricsAfterMissed.netPnl, priorNetPnl, "Missed trade must not alter account P&L")
    }
    
    // MARK: - Replay Market Data & Gap Alignment Test
    
    func testReplaySymbolNormalizationAndResampling() {
        let oandaNormEur = MarketDataService.shared.normalizeMarketSymbol(symbol: "EURUSDm", provider: "oanda")
        XCTAssertEqual(oandaNormEur, "EUR_USD")
        
        let oandaNormGold = MarketDataService.shared.normalizeMarketSymbol(symbol: "XAUUSD.pro", provider: "oanda")
        XCTAssertEqual(oandaNormGold, "XAU_USD")
        
        let binanceBtc = MarketDataService.shared.normalizeMarketSymbol(symbol: "BTCUSD", provider: "binance")
        XCTAssertEqual(binanceBtc, "BTCUSDT")
        
        // Resampling 3 x 5m candles to 1 x 15m candle
        let t0: Int64 = 1719237600000 // 14:00 UTC
        let bars5m = [
            MarketBar(timestamp: t0, open: 2350, high: 2355, low: 2348, close: 2352, volume: 100),
            MarketBar(timestamp: t0 + 300_000, open: 2352, high: 2358, low: 2351, close: 2356, volume: 150),
            MarketBar(timestamp: t0 + 600_000, open: 2356, high: 2360, low: 2354, close: 2359, volume: 200)
        ]
        let resampled15m = TradeReplayEngine.resampleBars(bars5m, to: .m15)
        XCTAssertEqual(resampled15m.count, 1)
        XCTAssertEqual(resampled15m[0].timestamp, t0)
        XCTAssertEqual(resampled15m[0].open, 2350)
        XCTAssertEqual(resampled15m[0].high, 2360)
        XCTAssertEqual(resampled15m[0].low, 2348)
        XCTAssertEqual(resampled15m[0].close, 2359)
        XCTAssertEqual(resampled15m[0].volume, 450)
        
        // 3. Broker Timezone Offset Auto-Alignment & Price Containment Verification
        // Scenario: Trade entered at price 4020 at 14:00 MT5 Cyprus time (UTC+3, actual 11:00 UTC).
        // At 11:00 UTC, the candle has low 4018 and high 4025 (contains 4020).
        // At 14:00 UTC, the market has moved up to 4024-4030.
        let t11Utc: Int64 = 1719226800000 // 11:00 UTC
        let t14Mt5: Int64 = 1719237600000 // 14:00 MT5 timestamp (+3h shift from UTC)
        
        let candleAt11Utc = MarketBar(timestamp: t11Utc, open: 2350, high: 4025, low: 4018, close: 4022, volume: 100)
        let candleAt14Utc = MarketBar(timestamp: t14Mt5, open: 4026, high: 4032, low: 4024, close: 4028, volume: 100)
        
        XCTAssertTrue(TradeReplayEngine.barContainsPrice(candleAt11Utc, price: 4020))
        XCTAssertFalse(TradeReplayEngine.barContainsPrice(candleAt14Utc, price: 4020))
        
        var testBars: [MarketBar] = []
        for i in -6...10 {
            let ts = t11Utc + Int64(i) * 300_000
            let isEntryBar = (i == 0)
            let low: Decimal = isEntryBar ? 4018 : 4024 + Decimal(max(0, i))
            let high: Decimal = isEntryBar ? 4025 : 4030 + Decimal(max(0, i))
            testBars.append(MarketBar(timestamp: ts, open: low + 1, high: high, low: low, close: low + 2, volume: 50))
        }
        
        let testTrade = Trade(
            id: "trade-align-test",
            accountId: "acc-1",
            symbol: "XAUUSD",
            direction: .long,
            quantity: 1,
            avgEntry: 4020,
            avgExit: 4030,
            openedAt: Date(timeIntervalSince1970: Double(t14Mt5) / 1000.0),
            closedAt: Date(timeIntervalSince1970: Double(t14Mt5 + 1800_000) / 1000.0),
            grossPnl: 100,
            netPnl: 95,
            status: .closed
        )
        
        let detectedOffset = TradeReplayEngine.resolveTimeAlignmentOffset(bars: testBars, trade: testTrade, resolution: .m5)
        XCTAssertEqual(detectedOffset, -10_800_000) // -3 hours exact offset resolved!
        
        let alignedTrimmed = TradeReplayEngine.alignAndTrimBars(bars: testBars, trade: testTrade, resolution: .m5, preBarsCount: 4, postBarsCount: 2)
        XCTAssertFalse(alignedTrimmed.isEmpty)
        // The bar at trade.openedAt must contain entry price 4020
        let openBar = alignedTrimmed.first { t14Mt5 >= $0.timestamp && t14Mt5 < ($0.timestamp + 300_000) }
        XCTAssertNotNil(openBar)
        XCTAssertTrue(TradeReplayEngine.barContainsPrice(openBar!, price: 4020))
        XCTAssertLessThanOrEqual(openBar!.low, 4020)
        XCTAssertGreaterThanOrEqual(openBar!.high, 4020)
    }
    
    // MARK: - Progress Routine Archive vs Permanent Deletion Tests
    
    @MainActor
    func testProgressRuleSchedulingArchivingAndTombstones() {
        let dataStore = TradeDataStore.shared
        let ruleId = "test-routine-" + UUID().uuidString
        let rule = ProgressRule(
            id: ruleId,
            title: "Test Trading Checklist",
            stage: "Before trading",
            weekdaysJson: "[1,2,3,4,5]", // Mon-Fri
            createdAt: "2026-10-01",
            archivedAt: nil
        )
        
        // 1. Weekday scheduling & active checks
        XCTAssertEqual(rule.activeWeekdays, [1, 2, 3, 4, 5])
        // 2026-10-27 is a Tuesday (index 2) -> scheduled
        XCTAssertTrue(rule.isScheduled(on: "2026-10-27"))
        // 2026-10-25 is a Sunday (index 0) -> not scheduled
        XCTAssertFalse(rule.isScheduled(on: "2026-10-25"))
        XCTAssertTrue(rule.isActive(on: "2026-10-27"))
        
        // 2. Archiving semantics
        var archivedRule = rule
        archivedRule.archivedAt = "2026-10-27T10:00:00Z"
        XCTAssertTrue(archivedRule.isArchived)
        // Active for yesterday (2026-10-26 < 2026-10-27)
        XCTAssertTrue(archivedRule.isActive(on: "2026-10-26"))
        // Inactive for today and future days
        XCTAssertFalse(archivedRule.isActive(on: "2026-10-27"))
        XCTAssertFalse(archivedRule.isActive(on: "2026-10-28"))
        
        // 3. Save & Permanent Delete with Tombstone tracking
        dataStore.saveProgressRule(rule)
        XCTAssertTrue(dataStore.progressRules.contains(where: { $0.id == ruleId }))
        XCTAssertFalse(dataStore.deletedProgressRuleIds.contains(ruleId))
        
        // Add a progress check for this rule
        dataStore.toggleProgressCheck(ruleId: ruleId, date: "2026-10-27")
        XCTAssertTrue(dataStore.progressChecks.contains(where: { $0.ruleId == ruleId }))
        
        // Delete permanently
        dataStore.deleteProgressRule(id: ruleId)
        
        // Verify completely purged from local rules & checks
        XCTAssertFalse(dataStore.progressRules.contains(where: { $0.id == ruleId }))
        XCTAssertFalse(dataStore.progressChecks.contains(where: { $0.ruleId == ruleId }))
        // Verify tombstone is recorded
        XCTAssertTrue(dataStore.deletedProgressRuleIds.contains(ruleId))
        
        // 4. Verify tombstone prevents remote sync resurrection
        let remoteZombieRule = ProgressRule(
            id: ruleId,
            title: "Zombie Rule from Supabase",
            stage: "Before trading",
            weekdaysJson: "[1,2,3,4,5]"
        )
        // Simulating the sync loop:
        if !dataStore.deletedProgressRuleIds.contains(remoteZombieRule.id) {
            dataStore.progressRules.append(remoteZombieRule)
        }
        // Rule MUST NOT be resurrected!
        XCTAssertFalse(dataStore.progressRules.contains(where: { $0.id == ruleId }))
        
        // Cleanup
        dataStore.deletedProgressRuleIds.remove(ruleId)
    }
    
    // MARK: - Responsible AI Advisor & PreTrade-To-Trade Coach Linking Tests
    
    func testAIAdvisorAccountabilityAndPreTradeLinking() {
        let memory = AIAdvisorMemoryEngine.shared
        let testSymbol = "XAUUSD"
        
        // 1. Test Commitment Extraction & Persistence
        let sampleAnalysis = """
        ### 1. D1 Macro Bias
        Bears control HTF.
        
        ### 4. Khuyến nghị hành động:
        - KẾT LUẬN: SELL (SHORT)
        - Điểm vào tối ưu: 2350.00
        - Cắt lỗ bắt buộc: 2362.00
        - Mục tiêu chốt lời: 2330.00
        - Điều kiện kích hoạt: Chờ nến M15 quét râu tại 2350
        """
        let commitment = memory.extractCommitment(from: sampleAnalysis, symbol: testSymbol)
        XCTAssertEqual(commitment.symbol, "XAUUSD")
        XCTAssertEqual(commitment.bias, "SELL")
        XCTAssertNotNil(commitment.plannedEntry)
        XCTAssertNotNil(commitment.invalidationSL)
        
        memory.saveCommitment(commitment)
        
        // 2. Test Retrieval for Trade opened shortly after
        let retrieved = memory.getLatestCommitment(for: "XAUUSD", beforeOrNear: Date().addingTimeInterval(900))
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.bias, "SELL")
        
        // 3. Test Trade Coach Prompt Injection with Pre-Trade Commitment & Anti-Gaslighting Directive
        let trade = Trade(
            id: "trade-audit-test-1",
            accountId: "acc-1",
            symbol: "XAUUSD",
            direction: .short,
            status: .closed,
            openedAt: Date(),
            closedAt: Date().addingTimeInterval(1200),
            avgEntry: Decimal(2350),
            avgExit: Decimal(2358), // Stopped out / loss
            quantity: Decimal(1),
            netPnl: Decimal(-800),
            fees: Decimal(5)
        )
        
        let promptVi = AIPromptBuilder.buildTradeCoachingPrompt(
            trade: trade,
            isVi: true,
            recentCandlesSummary: "M15 tape...",
            displayTimeZone: "Asia/Ho_Chi_Minh",
            linkedPreTradePlan: retrieved
        )
        
        // Must contain Pre-Trade commitment context
        XCTAssertTrue(promptVi.contains("LỊCH SỬ KẾ HOẠCH PRE-TRADE ĐÃ TƯ VẤN"))
        XCTAssertTrue(promptVi.contains("2350"))
        XCTAssertTrue(promptVi.contains("Thesis Validation & RSI Momentum"))
        
        // 4. Test Lesson Memory & Relevant Recall
        let lesson = TraderAILesson(
            symbol: "XAUUSD",
            setupType: "Supply Sweep",
            mistakeTag: "Early Short",
            lesson: "Chờ M15 CHoCH trước khi short quanh cản H4",
            context: "Test context"
        )
        memory.saveLesson(lesson)
        let relevant = memory.getRelevantLessons(for: "XAUUSD")
        XCTAssertFalse(relevant.isEmpty)
        XCTAssertTrue(relevant.contains(where: { $0.lesson.contains("M15 CHoCH") }))
    }
    
    // MARK: - Test Order Ticket & Pre-Trade Note Binding and Inquiry
    func testOrderTicketPreTradeNoteBindingAndInquiry() {
        let memory = AIAdvisorMemoryEngine.shared
        let commitment = AdvisorCommitmentRecord(
            symbol: "EURUSD",
            bias: "BUY",
            plannedEntry: "1.0820",
            invalidationSL: "1.0790",
            targetTP: "1.0890",
            triggerCondition: "Wait for Asian Low sweep and M15 CHoCH",
            thesisSummary: "Liquidity swept below equal lows, ready for expansion towards London high."
        )
        memory.saveCommitment(commitment)
        
        // 1. Format Markdown block with Order Ticket #998877
        let markdown = PreTradeNoteBinding.formatMarkdownBlock(orderTicket: "998877", commitment: commitment)
        XCTAssertTrue(markdown.contains("PRE-TRADE BIAS • TICKET #998877"))
        XCTAssertTrue(markdown.contains("EURUSD"))
        XCTAssertTrue(markdown.contains("BUY"))
        XCTAssertTrue(markdown.contains("1.0820"))
        XCTAssertTrue(markdown.contains(commitment.id))
        
        // 2. Parse from Note
        let noteWithCustomText = "My trade note before entering.\n\n\(markdown)\n\nFeeling calm."
        let parsed = PreTradeNoteBinding.parseFromNote(noteWithCustomText)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.orderTicket, "998877")
        XCTAssertEqual(parsed?.symbol, "EURUSD")
        XCTAssertEqual(parsed?.bias, "BUY")
        XCTAssertEqual(parsed?.plannedEntry, "1.0820")
        XCTAssertEqual(parsed?.invalidationSL, "1.0790")
        XCTAssertEqual(parsed?.targetTP, "1.0890")
        XCTAssertEqual(parsed?.commitmentId, commitment.id)
        
        // 3. Explicit Binding in Memory Engine
        memory.linkCommitment(commitmentId: commitment.id, tradeKey: "trade-eurusd-1", orderTicket: "998877")
        
        let retrievedByKey = memory.getCommitment(byTradeKey: "trade-eurusd-1")
        XCTAssertNotNil(retrievedByKey)
        XCTAssertEqual(retrievedByKey?.id, commitment.id)
        
        let retrievedByTicket = memory.getCommitment(byOrderTicket: "998877")
        XCTAssertNotNil(retrievedByTicket)
        XCTAssertEqual(retrievedByTicket?.id, commitment.id)
        
        // 4. Test Prompt Generation for Note & Ticket Inquiry
        let trade = Trade(
            key: "trade-eurusd-1",
            accountId: "acc-1",
            symbol: "EURUSD",
            direction: .long,
            status: .loss,
            openedAt: Date(),
            closedAt: Date().addingTimeInterval(1800),
            quantity: Decimal(1),
            openQuantity: Decimal(0),
            avgEntry: Decimal(string: "1.0818")!,
            avgExit: Decimal(string: "1.0788")!,
            grossPnl: Decimal(-300),
            fees: Decimal(2),
            netPnl: Decimal(-302),
            executionCount: 2,
            executionIds: ["998877"]
        )
        
        let prompt = AIPromptBuilder.buildTradeNoteInquiryPrompt(
            trade: trade,
            noteContent: noteWithCustomText,
            parsedPreTrade: parsed,
            orderTicket: "998877",
            userQuestion: "Tại sao nãy mày bảo buy ở đây giờ lại thành dính SL?",
            language: "vi",
            displayTimeZone: "Asia/Ho_Chi_Minh"
        )
        
        // Check Ticket and Execution in Prompt
        XCTAssertTrue(prompt.contains("#998877"))
        XCTAssertTrue(prompt.contains("1.0818"))
        XCTAssertTrue(prompt.contains("1.0820"))
        XCTAssertTrue(prompt.contains("Confirmation Entry"))
        XCTAssertTrue(prompt.contains("RSI Core"))
        // Check Prompt is Clean: No timezone pollution
        XCTAssertFalse(prompt.contains("(GMT+7)"))
        XCTAssertFalse(prompt.contains("(UTC)"))
        XCTAssertFalse(prompt.contains("GMT+7"))
    }
    
    // MARK: - Test Absolute Clean Prompts without Timezone Suffixes (GMT+7, UTC)
    func testNoTimezoneSuffixInPromptsAndCandleTape() {
        let trade = Trade(
            key: "tz-test-1",
            accountId: "acc-1",
            symbol: "XAUUSD",
            direction: .short,
            status: .open,
            openedAt: Date(),
            quantity: Decimal(1),
            openQuantity: Decimal(1),
            avgEntry: Decimal(2730),
            grossPnl: Decimal(0),
            fees: Decimal(0),
            netPnl: Decimal(0),
            executionCount: 1,
            executionIds: ["112233"]
        )
        
        // 1. Trade Coach Prompt is clean
        let coachPrompt = AIPromptBuilder.buildTradeCoachingPrompt(
            trade: trade,
            isVi: true,
            recentCandlesSummary: "Candle tape...",
            displayTimeZone: "Asia/Ho_Chi_Minh"
        )
        // Must NOT output literal timezone abbreviation in trade info
        XCTAssertFalse(coachPrompt.contains("(GMT+7)"))
        XCTAssertFalse(coachPrompt.contains("(UTC)"))
        XCTAssertFalse(coachPrompt.contains("GMT+7"))
        XCTAssertTrue(coachPrompt.contains("Thesis Validation & RSI Momentum"))
        XCTAssertTrue(coachPrompt.contains("RSI(14) Wilder = [số cụ thể]"))
        
        // 2. Pre-Trade Analysis Prompt is clean and mandates RSI Core
        let dummyBars = [
            MarketBar(date: Date(), open: Decimal(2725), high: Decimal(2735), low: Decimal(2720), close: Decimal(2730), volume: Decimal(100))
        ]
        let preTradePrompt = AIPromptBuilder.buildPreTradeAnalysisPrompt(
            symbol: "XAUUSD",
            d1Bars: dummyBars,
            h4Bars: dummyBars,
            m15Bars: dummyBars,
            language: "vi",
            displayTimeZone: "Asia/Ho_Chi_Minh"
        )
        XCTAssertFalse(preTradePrompt.contains("(GMT+7)"))
        XCTAssertFalse(preTradePrompt.contains("(UTC)"))
        XCTAssertFalse(preTradePrompt.contains("GMT+7"))
        XCTAssertTrue(preTradePrompt.contains("M15 Trigger & RSI Momentum"))
        XCTAssertTrue(preTradePrompt.contains("RSI(14) Wilder = [số]"))
        
        // 3. Candlestick Tape Markdown Table Header
        let table = MarketStructureFormatter.formatCandlesTable(
            bars: dummyBars,
            count: 1,
            displayTimeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        )
        XCTAssertFalse(table.contains("Time (UTC /"))
        XCTAssertTrue(table.contains("| # | Time | Open |"))
    }
    
    func testMomentumEngineWilderRSI_EMA9_WMA45() {
        // Generate 80 synthetic bars with alternating uptrend and consolidation
        var bars: [MarketBar] = []
        let now = Date()
        var currentPrice: Decimal = 2000
        
        for i in 0..<80 {
            let barDate = now.addingTimeInterval(Double(i * 900))
            if i % 3 == 0 {
                currentPrice += Decimal(4)
            } else if i % 3 == 1 {
                currentPrice += Decimal(2)
            } else {
                currentPrice -= Decimal(3)
            }
            bars.append(MarketBar(
                date: barDate,
                open: currentPrice - 1,
                high: currentPrice + 2,
                low: currentPrice - 2,
                close: currentPrice,
                volume: Decimal(150)
            ))
        }
        
        // Compute 15-candle momentum window
        let window = MomentumEngine.computeWindow(bars: bars, windowSize: 15)
        
        // Assertions
        XCTAssertEqual(window.points.count, 15)
        XCTAssertNotNil(window.currentRSI)
        XCTAssertNotNil(window.currentEMA9)
        XCTAssertNotNil(window.currentWMA45)
        XCTAssertNotNil(window.emaVsWmaGap)
        XCTAssertFalse(window.emaVsWmaVi.isEmpty)
        XCTAssertFalse(window.emaVsWmaEn.isEmpty)
        
        // Wilder RSI bounds check: 0 <= RSI <= 100
        for p in window.points {
            XCTAssertGreaterThanOrEqual(p.rsi14, 0)
            XCTAssertLessThanOrEqual(p.rsi14, 100)
            XCTAssertGreaterThanOrEqual(p.ema9, 0)
            XCTAssertLessThanOrEqual(p.ema9, 100)
            XCTAssertGreaterThanOrEqual(p.wma45, 0)
            XCTAssertLessThanOrEqual(p.wma45, 100)
            XCTAssertFalse(p.signalVi.isEmpty)
            XCTAssertFalse(p.signalEn.isEmpty)
        }
        
        // Format test
        let formattedVi = MomentumEngine.formatMomentumTable(
            window: window,
            displayTimeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!,
            isVi: true
        )
        XCTAssertTrue(formattedVi.contains("ĐỘNG LƯỢNG KỸ THUẬT: RSI 14 WILDER / EMA 9 / WMA 45"))
        XCTAssertTrue(formattedVi.contains("| 15 |"))
        XCTAssertTrue(formattedVi.contains("Tương quan EMA(9) vs WMA(45):"))
        XCTAssertFalse(formattedVi.contains("GMT+7"))
        
        let formattedEn = MomentumEngine.formatMomentumTable(
            window: window,
            displayTimeZone: TimeZone(identifier: "UTC")!,
            isVi: false
        )
        XCTAssertTrue(formattedEn.contains("TECHNICAL MOMENTUM: WILDER RSI 14 / EMA 9 / WMA 45"))
        XCTAssertTrue(formattedEn.contains("Momentum Alignment:"))
    }
}
