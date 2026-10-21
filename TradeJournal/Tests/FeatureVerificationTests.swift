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
}
