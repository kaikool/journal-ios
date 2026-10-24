import Foundation

// MARK: - AI Reflection Categories (100% English UI)
public enum AIReflectionCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case cadence = "Cadence & Review"
    case execution = "Trade & Execution"
    case psychology = "Psychology & Leaks"
    case risk = "Risk & Prop Firm"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "sparkles"
        case .cadence: return "calendar.badge.clock"
        case .execution: return "chart.bar.xaxis"
        case .psychology: return "brain.head.profile"
        case .risk: return "shield.checkered"
        }
    }
}

// MARK: - AI Reflection Template Definition (100% English UI)
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

// MARK: - Pre-built 11 Specialized Templates
public struct AIReflectionTemplates {
    
    public static let all: [AIReflectionTemplate] = [
        // 1. Cadence & Reviews
        AIReflectionTemplate(
            id: "daily_recap",
            title: "Daily Trading Recap",
            subtitle: "Structured day review: 2 key strengths & 1 primary discipline takeaway",
            icon: "doc.text.magnifyingglass",
            category: .cadence,
            action: .recap,
            tag: "#ai-daily-recap",
            notePrefix: "[AI Daily Recap]"
        ),
        AIReflectionTemplate(
            id: "weekly_audit",
            title: "Weekly Performance Audit",
            subtitle: "Diagnose overall weekly rhythm, profit factor trend, best vs worst day",
            icon: "calendar",
            category: .cadence,
            action: .recap,
            tag: "#ai-weekly-audit",
            notePrefix: "[AI Weekly Audit]"
        ),
        AIReflectionTemplate(
            id: "pre_market_prep",
            title: "Pre-Market Mindset & Prep",
            subtitle: "Review previous session leaks to establish 2 non-negotiable rules for today",
            icon: "sunrise.fill",
            category: .cadence,
            action: .critique,
            tag: "#ai-pre-market",
            notePrefix: "[AI Pre-Market Prep]"
        ),
        
        // 2. Execution & Setups
        AIReflectionTemplate(
            id: "trade_post_mortem",
            title: "Single Trade Post-Mortem",
            subtitle: "Anatomical audit of latest trade: entry, exit, planned vs realized R:R",
            icon: "scope",
            category: .execution,
            action: .critique,
            tag: "#ai-trade-critique",
            notePrefix: "[AI Trade Critique]"
        ),
        AIReflectionTemplate(
            id: "risk_reward_audit",
            title: "Realized Risk/Reward Audit",
            subtitle: "Audit average win vs loss ratio and mathematical expectancy",
            icon: "scalemass.fill",
            category: .execution,
            action: .critique,
            tag: "#ai-rr-audit",
            notePrefix: "[AI R:R Audit]"
        ),
        AIReflectionTemplate(
            id: "playbook_edge",
            title: "Playbook & Setup Edge Evaluation",
            subtitle: "Evaluate setup profitability to identify your true mathematical edge",
            icon: "book.pages.fill",
            category: .execution,
            action: .critique,
            tag: "#ai-playbook-edge",
            notePrefix: "[AI Playbook Edge]"
        ),
        
        // 3. Psychology & Leaks
        AIReflectionTemplate(
            id: "leak_detector",
            title: "Capital Leak Detector",
            subtitle: "Pinpoint top behavioral mistake categories draining your account balance",
            icon: "exclamationmark.triangle.fill",
            category: .psychology,
            action: .critique,
            tag: "#ai-leak-detector",
            notePrefix: "[AI Leak Audit]"
        ),
        AIReflectionTemplate(
            id: "revenge_tilt_check",
            title: "Revenge & Tilt Diagnostic",
            subtitle: "Scan for emotional revenge entries, rapid-fire trading, or lot size surges after losses",
            icon: "flame.fill",
            category: .psychology,
            action: .critique,
            tag: "#ai-tilt-diagnostic",
            notePrefix: "[AI Tilt Diagnostic]"
        ),
        AIReflectionTemplate(
            id: "session_vulnerability",
            title: "Session & Time Vulnerability",
            subtitle: "Identify your most profitable sessions vs leak-prone hours to avoid overtrading",
            icon: "clock.badge.exclamationmark",
            category: .psychology,
            action: .ask,
            tag: "#ai-session-leak",
            notePrefix: "[AI Session Vulnerability]"
        ),
        
        // 4. Risk & Prop Firm
        AIReflectionTemplate(
            id: "prop_drawdown_guard",
            title: "Prop Firm Drawdown Guard",
            subtitle: "Calculate safety buffer against daily & overall drawdown limits (The5ers/FTMO)",
            icon: "shield.lefthalf.filled",
            category: .risk,
            action: .critique,
            tag: "#ai-prop-guard",
            notePrefix: "[AI Prop Guard]"
        ),
        AIReflectionTemplate(
            id: "lot_size_consistency",
            title: "Position Sizing Consistency",
            subtitle: "Ensure risk per trade and lot sizing remains disciplined between winners and losers",
            icon: "chart.pie.fill",
            category: .risk,
            action: .critique,
            tag: "#ai-size-consistency",
            notePrefix: "[AI Size Consistency]"
        )
    ]
    
    // MARK: - Prompt Builder
    public static func buildTemplatePrompt(
        template: AIReflectionTemplate,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        trades: [Trade],
        language: String
    ) -> String {
        let isVi = language == "vi"
        let langInstruction = isVi ? "\nLƯU Ý QUAN TRỌNG: Hãy trả lời 100% bằng TIẾNG VIỆT, dùng các thuật ngữ trading chuẩn xác (Stop Loss, Take Profit, Win Rate, Risk/Reward, Drawdown, Entry, Exit)." : "\nIMPORTANT: Respond 100% in English using professional trading terminology."
        
        switch template.id {
        case "daily_recap":
            let todayStr = JournalIds.todayDateString()
            let todayTrades = trades.filter { t in
                guard let close = t.closedAt else { return false }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: close) == todayStr
            }
            let count = todayTrades.count
            let pnl = todayTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
            let wins = todayTrades.filter { $0.netPnl > 0 }.count
            let losses = todayTrades.filter { $0.netPnl < 0 }.count
            
            return """
            TODAY'S RECORDED TRADING DATA (\(todayStr)):
            - Closed Trades Today: \(count) (Wins: \(wins) | Losses: \(losses))
            - Net Daily P&L: \(pnl >= 0 ? "+" : "")\(pnl)
            
            TASK: DAILY TRADING RECAP
            1. Performance & Execution Summary: Assess discipline and adherence to rules today.
            2. Two Key Strengths: Highlight 2 execution or risk strengths grounded strictly in the data.
            3. One Discipline Improvement: Define 1 non-negotiable rule or risk adjustment for tomorrow.
            \(langInstruction)
            """
            
        case "weekly_audit":
            return """
            TASK: WEEKLY PERFORMANCE AUDIT
            Review overall performance metrics (Total Trades, Win Rate, Profit Factor, Edge Score, Max Drawdown):
            1. Trajectory Trend: Diagnose whether current performance is improving, consolidating, or deteriorating.
            2. Risk/Reward Symmetry: Evaluate payoff balance between winners and losers.
            3. Actionable Goal: Prescribe 1 specific behavioral goal to boost mathematical expectancy for next week.
            \(langInstruction)
            """
            
        case "pre_market_prep":
            return """
            TASK: PRE-MARKET MINDSET & PROTOCOL PREPARATION
            Review recent session context, streaks, and current drawdown:
            1. Psychological Hazards: Warn against emotional biases entering the upcoming session.
            2. Core Directives: Establish exactly 2 Non-negotiable Rules for today's trading.
            3. Circuit Breaker: Specify a strict daily max loss threshold where the trader must stop trading.
            \(langInstruction)
            """
            
        case "trade_post_mortem":
            let lastTrade = trades.first(where: { $0.closedAt != nil })
            let symbol = lastTrade?.symbol ?? "N/A"
            let pnl = lastTrade?.netPnl ?? Decimal.zero
            let side = lastTrade?.side.uppercased() ?? "N/A"
            let entry = lastTrade?.entryPrice ?? Decimal.zero
            let exit = lastTrade?.avgExit.map { "\($0)" } ?? "N/A"
            let mistakes = lastTrade?.mistakes.joined(separator: ", ") ?? ""
            
            return """
            LATEST CLOSED TRADE DETAILS:
            - Symbol: \(symbol) | Side: \(side) | P&L: \(pnl >= 0 ? "+" : "")\(pnl)
            - Entry Price: \(entry) | Exit Price: \(exit)
            - Logged Mistakes: \(mistakes.isEmpty ? "None" : mistakes)
            
            TASK: SINGLE TRADE POST-MORTEM
            1. Entry & Exit Assessment: Analyze execution quality at market entry and exit.
            2. Discipline Audit: Check for early profit-taking or excessive holding of losses beyond planned parameters.
            3. Takeaway: Provide 1 objective coaching rule for executing similar setups in the future.
            \(langInstruction)
            """
            
        case "risk_reward_audit":
            return """
            TASK: RISK/REWARD & EXPECTANCY AUDIT
            Analyze current Win Rate, Largest Win, Largest Loss, and Net P&L:
            1. System Dependency: Determine if profitability relies on high win-rate or positive payout ratio.
            2. Payoff Asymmetry: Check if rare large losses are canceling out consecutive winning trades.
            3. Optimization: Recommend the minimum target realized R:R for consistent capital compounding.
            \(langInstruction)
            """
            
        case "playbook_edge":
            return """
            TASK: PLAYBOOK & STATISTICAL EDGE EVALUATION
            Based on trade history and Edge Score v2:
            1. Edge Verification: Evaluate whether trade history demonstrates a statistically verifiable edge.
            2. Performance Drag: Identify the single biggest leak dragging down the Edge Score.
            3. Refinement: Provide 1 actionable step to filter out low-probability trades.
            \(langInstruction)
            """
            
        case "leak_detector":
            let allMistakes = trades.flatMap { $0.mistakes }
            let mistakeCounts = Dictionary(grouping: allMistakes, by: { $0 }).mapValues { $0.count }
            let sortedMistakes = mistakeCounts.sorted { $0.value > $1.value }.prefix(3)
            let mistakeSummary = sortedMistakes.isEmpty ? "No mistake tags logged yet" : sortedMistakes.map { "\($0.key): \($0.value) times" }.joined(separator: ", ")
            
            return """
            RECORDED MISTAKE FREQUENCY:
            - Top logged mistakes: \(mistakeSummary)
            
            TASK: CAPITAL LEAK DETECTION
            1. Root Cause: Diagnose the underlying psychological driver (FOMO, fear of losing, impatience).
            2. Equity Impact: Quantify the behavioral drag on trading capital.
            3. Barrier Protocol: Prescribe a concrete rule to eliminate this recurring error.
            \(langInstruction)
            """
            
        case "revenge_tilt_check":
            return """
            TASK: REVENGE TRADING & TILT DIAGNOSTIC
            Using Max Loss Streak and Max Drawdown:
            1. Vulnerability Assessment: Check for signs of emotional escalation following losing trades.
            2. Compounding Risks: Warn against sizing inflation or rapid-fire re-entries.
            3. Protocol: Formulate an exact 3-step circuit breaker when suffering 2 consecutive losses.
            \(langInstruction)
            """
            
        case "session_vulnerability":
            return """
            TASK: SESSION & TIME MANAGEMENT ANALYSIS
            1. Session Focus: Analyze execution during peak liquidity sessions (London/NY overlaps) vs off-hours.
            2. Overtrading Prevention: Warn against low-probability consolidation trading during dead hours.
            3. Recommended Window: Recommend an optimal 2-3 hour window of maximum mental acuity.
            \(langInstruction)
            """
            
        case "prop_drawdown_guard":
            let dd = metrics?.maxDrawdownPct.map { String(format: "%.1f%%", $0) } ?? "0%"
            let pnl = metrics?.netPnl ?? Decimal.zero
            return """
            CURRENT RISK & CAPITAL BUFFER:
            - Max Drawdown: \(dd) | Net Cumulative P&L: \(pnl >= 0 ? "+" : "")\(pnl)
            
            TASK: PROP FIRM DRAWDOWN GUARD (THE5ERS / FTMO)
            1. Buffer Status: Evaluate distance to daily limit (typically 5%) and maximum limit (typically 10%).
            2. Sizing Recommendation: Prescribe maximum recommended risk percentage on the next trade to ensure survival.
            3. Drawdown Protocol: Outline a defensive step-down plan if drawdown exceeds 3%.
            \(langInstruction)
            """
            
        case "lot_size_consistency":
            return """
            TASK: POSITION SIZING & RISK CONSISTENCY AUDIT
            1. Risk Uniformity: Evaluate the necessity of uniform risk per trade vs arbitrary lot sizes.
            2. Fatal Pitfall: Check for the classic pitfall: micro lots on winners, inflated lots when trying to break even.
            3. Standard Formula: Outline a strict position sizing formula based on distance to Stop Loss.
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
            let pnl = m.netPnl
            pnlStr = (pnl >= 0 ? "+" : "") + "\(pnl)"
            wrStr = String(format: "%.0f%%", (m.winRate ?? 0.0) * 100)
        } else {
            pnlStr = "0"
            wrStr = "0%"
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
