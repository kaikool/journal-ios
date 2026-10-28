import Foundation

// MARK: - AI Reflection Categories (100% English UI)
public enum AIReflectionCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case cadence = "Session Recap"
    case execution = "Trade Audit"
    case psychology = "Leaks & Discipline"
    case risk = "Risk & Prop Guard"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "sparkles"
        case .cadence: return "calendar.badge.clock"
        case .execution: return "scope"
        case .psychology: return "brain.head.profile"
        case .risk: return "shield.checkered"
        }
    }
}

// MARK: - AI Reflection Template Definition
public struct AIReflectionTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let category: AIReflectionCategory
    public let action: AIReflectionAction
    public let tag: String
    public let notePrefix: String
    
    public init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        category: AIReflectionCategory,
        action: AIReflectionAction,
        tag: String,
        notePrefix: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.action = action
        self.tag = tag
        self.notePrefix = notePrefix
    }
}

// MARK: - Specialized Coaching Templates
public struct AIReflectionTemplates {
    
    public static let all: [AIReflectionTemplate] = [
        // 1. Session Recap
        AIReflectionTemplate(
            id: "daily_recap",
            title: "Session Recap",
            subtitle: "Review execution, profit & loss, and discipline on your latest trades",
            icon: "doc.text.magnifyingglass",
            category: .cadence,
            action: .recap,
            tag: "#ai-session-recap",
            notePrefix: "[AI Session Recap]"
        ),
        // 2. Single Trade Critique
        AIReflectionTemplate(
            id: "trade_post_mortem",
            title: "Trade Post-Mortem",
            subtitle: "Deep-dive into your latest closed trade: entry quality, exit, and R:R",
            icon: "scope",
            category: .execution,
            action: .critique,
            tag: "#ai-trade-audit",
            notePrefix: "[AI Trade Post-Mortem]"
        ),
        // 2B. Pre-Trade Market Structure Bias
        AIReflectionTemplate(
            id: "pre_trade_market_bias",
            title: "Pre-Trade Market Bias",
            subtitle: "Multi-timeframe liquidity sweep, supply/demand, and entry setup analysis (D1, H4, M15)",
            icon: "scope",
            category: .execution,
            action: .ask,
            tag: "#pre-trade-market-bias",
            notePrefix: "[Pre-Trade Market Bias]"
        ),
        // 3. Leaks & Psychology
        AIReflectionTemplate(
            id: "leak_detector",
            title: "Leaks & Psychology",
            subtitle: "Diagnose top loss drivers, tilt vulnerability, and rule breaks",
            icon: "exclamationmark.shield",
            category: .psychology,
            action: .critique,
            tag: "#ai-leaks-audit",
            notePrefix: "[AI Leak Audit]"
        ),
        // 4. Prop Firm & Risk Guard
        AIReflectionTemplate(
            id: "prop_drawdown_guard",
            title: "Risk & Prop Guard",
            subtitle: "Drawdown defense, position sizing limits, and capital preservation",
            icon: "shield.checkered",
            category: .risk,
            action: .critique,
            tag: "#ai-prop-guard",
            notePrefix: "[AI Prop Guard]"
        ),
        // 5. Risk / Reward Optimization
        AIReflectionTemplate(
            id: "risk_reward_audit",
            title: "R:R & Expectancy",
            subtitle: "Assess payoff asymmetry: are big losses eroding consecutive winning trades?",
            icon: "chart.bar.xaxis",
            category: .execution,
            action: .critique,
            tag: "#ai-rr-audit",
            notePrefix: "[AI RR Audit]"
        ),
        // 6. Lot Size Consistency
        AIReflectionTemplate(
            id: "lot_size_consistency",
            title: "Lot Sizing Audit",
            subtitle: "Verify uniform risk sizing vs arbitrary lot spikes on losing trades",
            icon: "chart.pie.fill",
            category: .risk,
            action: .critique,
            tag: "#ai-sizing-audit",
            notePrefix: "[AI Sizing Audit]"
        )
    ]
    
    // MARK: - Format Numbers (Strictly at most 2 Decimals)
    private static func formatPnl(_ decimal: Decimal) -> String {
        let val = NSDecimalNumber(decimal: decimal).doubleValue
        return (decimal >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(val))
    }
    
    private static func format2Dec(_ decimal: Decimal) -> String {
        let val = NSDecimalNumber(decimal: decimal).doubleValue
        return String(format: "%.2f", val)
    }
    
    private static func formatPrice(_ decimal: Decimal) -> String {
        let val = NSDecimalNumber(decimal: decimal).doubleValue
        return String(format: "%g", val)
    }
    
    // MARK: - Format Recent Trades for Rich Prompt Injection
    public static func buildRecentTradesSnippet(trades: [Trade], limit: Int = 10) -> String {
        let sorted = trades.filter { $0.closedAt != nil }.sorted { ($0.closedAt ?? Date.distantPast) > ($1.closedAt ?? Date.distantPast) }
        guard !sorted.isEmpty else { return "No closed trades recorded in this scope." }
        
        let slice = sorted.prefix(limit)
        var lines: [String] = []
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let todayDayStr = JournalIds.todayDateString()
        let cal = Calendar.current
        let yesterdayDay = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterdayDayStr = dayFormatter.string(from: yesterdayDay)
        
        for (idx, t) in slice.enumerated() {
            let pnlStr = formatPnl(t.netPnl)
            let dateStr: String = {
                guard let close = t.closedAt else { return "N/A" }
                let dStr = dayFormatter.string(from: close)
                let timeStr = f.string(from: close)
                if dStr == todayDayStr {
                    return "TODAY \(timeStr)"
                } else if dStr == yesterdayDayStr {
                    return "YESTERDAY \(timeStr)"
                } else {
                    return "\(dStr) \(timeStr)"
                }
            }()
            let durationStr: String
            if let ms = t.durationMs {
                let mins = ms / 60000
                durationStr = mins >= 60 ? "\(mins/60)h \(mins%60)m" : "\(mins)m"
            } else {
                durationStr = "N/A"
            }
            let exitStr = t.avgExit.map { Formatters.price($0, symbol: t.symbol) } ?? "N/A"
            let slStr = t.stopLoss.map { " | SL: \(Formatters.price($0, symbol: t.symbol))" } ?? ""
            let tpStr = t.profitTarget.map { " | TP: \(Formatters.price($0, symbol: t.symbol))" } ?? ""
            let mistakesStr = t.mistakes.isEmpty ? "" : " | Mistakes: \(t.mistakes.joined(separator: ", "))"
            let notesStr = (t.notes?.isEmpty ?? true) ? "" : " | Note: \(t.notes!)"
            let volStr = format2Dec(t.quantity)
            let entryStr = Formatters.price(t.avgEntry, symbol: t.symbol)
            let sideStr = t.direction == .short ? "SELL" : "BUY"
            
            lines.append("Trade #\(idx + 1) [\(dateStr)] \(t.symbol) \(sideStr) \(volStr) lots | In: \(entryStr) -> Out: \(exitStr)\(slStr)\(tpStr) | P&L: \(pnlStr) (Hold: \(durationStr))\(mistakesStr)\(notesStr)")
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Smart Prompt Builder with Real Data Injection
    public static func buildTemplatePrompt(
        template: AIReflectionTemplate,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        trades: [Trade],
        language: String
    ) -> String {
        let isVi = language == "vi"
        let langInstruction = isVi
            ? "\nLƯU Ý QUAN TRỌNG: Hãy phân tích dựa trên 100% dữ liệu thực tế ở trên. Trả lời bằng TIẾNG VIỆT, dùng các thuật ngữ trading chuẩn (Stop Loss, Take Profit, Win Rate, Risk/Reward, Drawdown, Entry, Exit). Đưa ra nhận xét cụ thể cho từng cặp tiền/mã lệnh thực tế."
            : "\nIMPORTANT: Ground all critique 100% in the real trade data above. Cite specific symbols, prices, and outcomes in professional trading terminology."
        
        let sorted = trades.filter { $0.closedAt != nil }.sorted { ($0.closedAt ?? Date.distantPast) > ($1.closedAt ?? Date.distantPast) }
        
        switch template.id {
        case "daily_recap":
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let todayStr = JournalIds.todayDateString()
            
            // Check if there are trades closed today; if not, automatically analyze the most recent session with trades
            var sessionTrades = sorted.filter { t in
                guard let close = t.closedAt else { return false }
                return f.string(from: close) == todayStr
            }
            var sessionLabel = "Today (\(todayStr))"
            
            if sessionTrades.isEmpty, let latest = sorted.first, let close = latest.closedAt {
                let latestDateStr = f.string(from: close)
                sessionTrades = sorted.filter { t in
                    guard let c = t.closedAt else { return false }
                    return f.string(from: c) == latestDateStr
                }
                sessionLabel = "Latest Active Session (\(latestDateStr))"
            }
            
            let count = sessionTrades.count
            let pnl = sessionTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
            let wins = sessionTrades.filter { $0.netPnl > 0 }.count
            let losses = sessionTrades.filter { $0.netPnl < 0 }.count
            let tradeDetails = buildRecentTradesSnippet(trades: sessionTrades, limit: 10)
            
            return """
            TRADING SESSION ANALYZED: \(sessionLabel)
            - Total Closed Trades in Session: \(count) (Wins: \(wins) | Losses: \(losses))
            - Net Session P&L: \(formatPnl(pnl))
            
            SESSION TRADES BREAKDOWN:
            \(tradeDetails)
            
            TASK: SESSION RECAP & DISCIPLINE AUDIT
            1. Execution Assessment: Evaluate how well entries and exits matched discipline on the specific trades listed above.
            2. Strengths Observed: Identify 2 concrete execution or risk management actions that were executed well.
            3. Discipline Takeaway: Identify the primary leak or vulnerability and prescribe 1 non-negotiable rule for the next session.
            \(langInstruction)
            """
            
        case "trade_post_mortem":
            let lastTrade = sorted.first
            let symbol = lastTrade?.symbol ?? "N/A"
            let pnl = lastTrade?.netPnl ?? Decimal.zero
            let isShort = lastTrade?.direction == .short
            let side = isShort ? "SELL / SHORT (BÁN KHỐNG - Kỳ vọng giá GIẢM)" : "BUY / LONG (MUA - Kỳ vọng giá TĂNG)"
            let directionRule = isShort
                ? "⚠️ LƯU Ý QUAN TRỌNG: Đây là lệnh BÁN (SELL/SHORT). Trader có LÃI khi giá GIẢM (Giá thoát < Giá vào). TP nằm DƯỚI giá vào, SL nằm TRÊN giá vào. Tuyệt đối KHÔNG phân tích nhầm thành lệnh Mua."
                : "⚠️ LƯU Ý QUAN TRỌNG: Đây là lệnh MUA (BUY/LONG). Trader có LÃI khi giá TĂNG (Giá thoát > Giá vào). TP nằm TRÊN giá vào, SL nằm DƯỚI giá vào."
            let entry = lastTrade?.entryPrice ?? Decimal.zero
            let exit = lastTrade?.avgExit.map { formatPrice($0) } ?? "N/A"
            let sl = lastTrade?.stopLoss.map { formatPrice($0) } ?? "Not Set"
            let tp = lastTrade?.profitTarget.map { formatPrice($0) } ?? "Not Set"
            let quantity = lastTrade?.quantity ?? Decimal.zero
            let mistakes = lastTrade?.mistakes.joined(separator: ", ") ?? ""
            let notes = lastTrade?.notes ?? ""
            let recentList = buildRecentTradesSnippet(trades: sorted, limit: 5)
            
            return """
            TARGET TRADE TO AUDIT (LATEST CLOSED POSITION):
            - Symbol: \(symbol) | Side: \(side) | Volume: \(format2Dec(quantity)) lots
            - Entry Price: \(formatPrice(entry)) -> Exit Price: \(exit)
            - Planned Stop Loss: \(sl) | Planned Take Profit: \(tp)
            - Realized P&L: \(formatPnl(pnl))
            - Logged Mistakes: \(mistakes.isEmpty ? "None" : mistakes)
            - Trader Notes: \(notes.isEmpty ? "None" : notes)
            
            \(directionRule)
            
            PRIOR CONTEXT TRADES:
            \(recentList)
            
            TASK: CRITICAL FORENSIC POST-MORTEM & STRUCTURAL AUDIT
            1. Thesis Validation: Was entering \(side) at \(formatPrice(entry)) technically rational, aligned with HTF market structure, or was it an emotional FOMO/chasing mistake?
            2. Multi-Timeframe & Liquidity Context: Did the trade get trapped in a liquidity sweep, or fight a major support/resistance barrier?
            3. Execution & Discipline Audit: Evaluate exit quality—was the trade closed according to plan (TP/SL hit) or cut early/held through unnecessary drawdown?
            4. 1 Non-Negotiable Operational Rule: State 1 sharp, uncompromising discipline rule for future setups.
            \(langInstruction)
            """
            
        case "pre_trade_market_bias":
            return """
            FORWARD-LOOKING PRE-TRADE MARKET STRUCTURE & LIQUIDITY AUDIT (D1, H4, M15):
            - Horizon: Higher Timeframe Bias (D1), Institutional Order Flow (H4), Execution Trigger (M15).
            - Account Context: Ready to evaluate trade setups against risk budget and psychological discipline.
            
            TASK: PRE-TRADE MARKET BIAS & SETUP VALIDATION (NO emojis):
            
            ### 1. Higher Timeframe Market Regime & Macro Trend (D1)
            - What is the prevailing institutional trend on the Daily chart? Expansion, Retracement, or Range Consolidation?
            - Where are the Previous Day High (PDH) and Previous Day Low (PDL)?
            
            ### 2. Key Supply/Demand Blocks & Liquidity Map (H4)
            - Where are the unmitigated Order Blocks (OB) and Fair Value Gaps (FVG)?
            - Where do retail stop-loss clusters sit (Buy-side Liquidity / Equal Highs vs Sell-side Liquidity / Equal Lows)?
            - Has a liquidity sweep / stop hunt already occurred, or is price currently engineering liquidity to trap traders?
            
            ### 3. Actionable Setup & Entry Execution (M15)
            - Actionable verdict: [BUY / SELL / FLAT - NO EDGE].
            - If valid setup exists: What is the optimal Entry price, Structural Invalidation level (SL), and Take Profit target (TP 1, TP 2)?
            - What confirmation trigger (e.g., Market Structure Shift / displacement candle) is strictly required before pressing the trigger?
            
            ### 4. 1 Non-Negotiable Risk Directive
            - State 1 non-negotiable operational rule to protect capital on this setup.
            \(langInstruction)
            """
            
        case "leak_detector":
            let allMistakes = sorted.flatMap { $0.mistakes }
            let mistakeCounts = Dictionary(grouping: allMistakes, by: { $0 }).mapValues { $0.count }
            let sortedMistakes = mistakeCounts.sorted { $0.value > $1.value }
            let mistakeSummary = sortedMistakes.isEmpty ? "No manual mistake tags logged" : sortedMistakes.map { "\($0.key): \($0.value) times" }.joined(separator: ", ")
            
            // Extract largest losing trades
            let bigLosses = sorted.filter { $0.netPnl < 0 }.sorted { $0.netPnl < $1.netPnl }.prefix(5)
            let lossSummary = bigLosses.map { "#\($0.symbol) \($0.side) \(format2Dec($0.quantity)) lots: \(formatPnl($0.netPnl)) (Mistakes: \($0.mistakes.joined(separator: ", ")))" }.joined(separator: "\n")
            
            return """
            RECORDED MISTAKE FREQUENCY:
            - Top logged mistake tags: \(mistakeSummary)
            
            BIGGEST DRAWDOWN TRADES (LARGEST LOSSES):
            \(lossSummary.isEmpty ? "No losing trades found in journal" : lossSummary)
            
            TASK: CAPITAL LEAK & BEHAVIORAL DETECTION
            1. Core Leak Identification: Pinpoint the behavioral trigger (FOMO, fear of losing, moving SL, revenge) behind the biggest losses.
            2. Expectancy Impact: Quantify how these specific errors disproportionately damage overall account expectancy.
            3. Circuit Breaker Rule: Formulate 1 strict non-negotiable rule to eliminate this leak.
            \(langInstruction)
            """
            
        case "prop_drawdown_guard":
            let dd = metrics?.maxDrawdownPct.map { String(format: "%.2f%%", $0) } ?? "0.00%"
            let pnl = metrics?.netPnl ?? Decimal.zero
            let totalLosses = sorted.filter { $0.netPnl < 0 }.count
            let lossStreak = metrics?.maxLossStreak ?? 0
            let recentLosses = sorted.filter { $0.netPnl < 0 }.prefix(4).map { "\($0.symbol) \($0.side) \(format2Dec($0.quantity))L: \(formatPnl($0.netPnl))" }.joined(separator: ", ")
            
            return """
            ACCOUNT RISK & CAPITAL METRICS:
            - Max Cumulative Drawdown: \(dd)
            - Net Cumulative P&L: \(formatPnl(pnl))
            - Max Losing Streak: \(lossStreak) consecutive trades
            - Total Losing Trades: \(totalLosses)
            - Recent Loss Sample: \(recentLosses.isEmpty ? "None" : recentLosses)
            
            TASK: PROP FIRM DRAWDOWN DEFENSE (THE5ERS / FTMO PROTOCOL)
            1. Drawdown Safety Buffer: Evaluate current risk distance to the 5% daily limit and 10% maximum drawdown ceiling.
            2. Lot Sizing Cap: Prescribe the exact recommended risk percentage per trade (e.g. 0.25% - 0.50%) to withstand a 4-loss streak.
            3. Emergency Step-Down: Define an automatic pause rule if the account incurs 2 consecutive losses in one session.
            \(langInstruction)
            """
            
        case "risk_reward_audit":
            let wins = sorted.filter { $0.netPnl > 0 }
            let losses = sorted.filter { $0.netPnl < 0 }
            let avgWin = wins.isEmpty ? Decimal.zero : wins.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(wins.count)
            let avgLoss = losses.isEmpty ? Decimal.zero : abs(losses.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(losses.count))
            let wr = (metrics?.winRate ?? 0.0) * 100
            let recentBreakdown = buildRecentTradesSnippet(trades: sorted, limit: 6)
            
            return """
            PAYOFF ASYMMETRY METRICS:
            - Win Rate: \(String(format: "%.2f%%", wr))
            - Average Winning Trade: +$\(format2Dec(avgWin))
            - Average Losing Trade: -$\(format2Dec(avgLoss))
            - Largest Win: \(formatPnl(metrics?.largestWin ?? Decimal.zero)) | Largest Loss: \(formatPnl(metrics?.largestLoss ?? Decimal.zero))
            
            SAMPLE OF RECENT TRADES:
            \(recentBreakdown)
            
            TASK: RISK/REWARD & EXPECTANCY AUDIT
            1. Payoff Ratio Assessment: Determine if average winners sufficiently outweigh average losers.
            2. Outlier Drag: Check if rare large losses are canceling out multiple disciplined winning trades.
            3. Target R:R Guideline: Prescribe the minimum target realized R:R for consistent capital compounding.
            \(langInstruction)
            """
            
        case "lot_size_consistency":
            let recentLots = sorted.prefix(8).map { "\($0.symbol): \(format2Dec($0.quantity)) lots (P&L: \(formatPnl($0.netPnl)))" }.joined(separator: ", ")
            
            return """
            POSITION SIZING SAMPLE (LAST 8 TRADES):
            \(recentLots)
            
            TASK: POSITION SIZING & RISK CONSISTENCY AUDIT
            1. Lot Uniformity Check: Identify whether position size fluctuates arbitrarily between setups.
            2. Fatal Pitfall Warning: Warn against the classic trap of trading small on winners and sizing up on losers.
            3. Standard Formula: Outline a strict SL-distance based sizing formula to ensure uniform account risk.
            \(langInstruction)
            """
            
        case "pre_trade_market_bias":
            let topTradedSymbols = Array(Set(sorted.prefix(10).map { $0.symbol })).joined(separator: ", ")
            return """
            MULTI-TIMEFRAME PRE-TRADE MARKET STRUCTURE INQUIRY:
            - Primary symbols in recent trade history: \(topTradedSymbols.isEmpty ? "EURUSD, XAUUSD, GBPUSD" : topTradedSymbols)
            
            TASK: PRE-TRADE FORWARD-LOOKING MARKET STRUCTURE AUDIT (D1 - H4 - M15)
            1. Higher Timeframe Liquidity: Evaluate where institutional Stop Loss clusters (Buy-side / Sell-side liquidity) are resting.
            2. Supply / Demand Imbalance: Identify key Unmitigated Order Blocks (OB) and Fair Value Gaps (FVG).
            3. Execution Guidance: Prescribe whether trader should BUY, SELL, or FLAT with entry invalidation criteria.
            \(langInstruction)
            """
            
        default:
            return template.title
        }
    }
    
    // MARK: - Standardized Note Title Generator (100% English)
    public static func generateNoteTitle(
        template: AIReflectionTemplate,
        metrics: TradeMetrics?
    ) -> String {
        let prefix = template.notePrefix
        let dateStr = JournalIds.todayDateString()
        
        let pnlStr: String
        let wrStr: String
        if let m = metrics {
            pnlStr = formatPnl(m.netPnl)
            wrStr = String(format: "%.2f%%", (m.winRate ?? 0.0) * 100)
        } else {
            pnlStr = "$0.00"
            wrStr = "0.00%"
        }
        
        switch template.id {
        case "daily_recap":
            return "\(prefix) Day \(dateStr) (PnL: \(pnlStr) | WR: \(wrStr))"
        case "trade_post_mortem":
            return "\(prefix) Latest Trade (\(dateStr))"
        case "leak_detector":
            return "\(prefix) Capital Leak Audit (\(dateStr))"
        case "prop_drawdown_guard":
            return "\(prefix) Prop Guard (\(dateStr))"
        default:
            return "\(prefix) \(template.title) (\(dateStr))"
        }
    }
}
