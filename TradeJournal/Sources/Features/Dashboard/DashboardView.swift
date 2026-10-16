import SwiftUI
import Charts

public enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case week = "7 ngày"
    case month = "30 ngày"
    case quarter = "90 ngày"
    case ytd = "Năm nay"
    
    public var id: String { rawValue }
}

public enum DashboardChartTab: String, CaseIterable, Identifiable {
    case equity = "Đường cong vốn"
    case drawdown = "Drawdown"
    case session = "Phiên GD"
    case weekday = "Thứ trong tuần"
    
    public var id: String { rawValue }
}

public struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedTimeRange: DashboardTimeRange = .all
    @State private var selectedChartTab: DashboardChartTab = .equity
    @State private var showEdgeScoreBreakdown: Bool = false
    @State private var showAIReflection: Bool = false
    
    public init() {}
    
    private var scopedTrades: [Trade] {
        let baseTrades = dataStore.filteredTrades
        guard selectedTimeRange != .all else { return baseTrades }
        
        let now = Date()
        let calendar = Calendar.current
        let cutoff: Date
        
        switch selectedTimeRange {
        case .all:
            return baseTrades
        case .week:
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .quarter:
            cutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .ytd:
            let comps = calendar.dateComponents([.year], from: now)
            cutoff = calendar.date(from: comps) ?? now
        }
        
        return baseTrades.filter { $0.openedAt >= cutoff }
    }
    
    private var overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        let initialBalance = dataStore.selectedAccount?.initialBalance ?? 0
        return FinancialMetricsEngine.computeOverview(
            trades: scopedTrades,
            timeZone: env.currentTimeZone,
            initialBalance: initialBalance
        )
    }
    
    private var edgeResult: EdgeScoreResult {
        EdgeScoreEngine.computeEdgeScore(metrics: overview.metrics)
    }
    
    private var chartEquityPoints: [EquityPointItem] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        return overview.curve.compactMap { pt in
            let date = isoFormatter.date(from: pt.date) ?? Date()
            return EquityPointItem(
                date: date,
                dateKey: pt.date,
                netPnl: Decimal(pt.netPnl),
                cumulativePnl: Decimal(pt.cumulativePnl),
                drawdown: Decimal(pt.drawdown)
            )
        }
    }
    
    private var sessionStats: [BucketStats] {
        AggregateEngine.bySession(trades: scopedTrades)
    }
    
    private var weekdayStats: [BucketStats] {
        AggregateEngine.byWeekday(trades: scopedTrades, timeZone: env.currentTimeZone)
    }
    
    private var symbolStats: [BucketStats] {
        AggregateEngine.bySymbol(trades: scopedTrades)
    }
    
    public var body: some View {
        let metrics = overview.metrics
        
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Time Range Selector
                    Picker("Khoảng thời gian", selection: $selectedTimeRange) {
                        ForEach(DashboardTimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Main Net P&L Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("TỔNG LÃI/LỖ RÒNG")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Button(action: { env.togglePrivacyMode() }) {
                                    Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                            
                            HStack(alignment: .firstTextBaseline) {
                                Text(Formatters.pnl(metrics.netPnl, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled))
                                    .font(AppTypography.financialNumber(size: 32, weight: .bold))
                                    .foregroundColor(metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                
                                Spacer()
                                
                                if let initial = dataStore.selectedAccount?.initialBalance, initial > 0 {
                                    let pct = (metrics.netPnl as NSDecimalNumber).doubleValue / (initial as NSDecimalNumber).doubleValue
                                    AppBadge(
                                        text: String(format: "%+.1f%%", pct * 100),
                                        color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                    )
                                }
                            }
                            
                            Divider().background(AppColors.border)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lãi gộp")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(metrics.profit, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.profit)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Lỗ gộp")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(metrics.loss, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.loss)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Phí giao dịch")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(metrics.fees, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    
                    // Edge Score Card
                    AppCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Edge Score v2")
                                            .font(AppTypography.headline)
                                        Image(systemName: "info.circle")
                                            .font(.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    Text("Chấm điểm 6 trụ cột kỹ thuật")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                
                                Spacer()
                                
                                ZStack {
                                    Circle()
                                        .stroke(AppColors.secondaryBackground, lineWidth: 6)
                                        .frame(width: 52, height: 52)
                                    
                                    Circle()
                                        .trim(from: 0, to: CGFloat((edgeResult.score ?? 50.0) / 100.0))
                                        .stroke(
                                            (edgeResult.score ?? 0) >= 60 ? AppColors.profit : ((edgeResult.score ?? 0) >= 40 ? AppColors.accent : AppColors.loss),
                                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 52, height: 52)
                                    
                                    Text(edgeResult.score != nil ? "\(Int(edgeResult.score!))" : "N/A")
                                        .font(AppTypography.headline.bold())
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    showEdgeScoreBreakdown.toggle()
                                }
                            }
                            
                            if showEdgeScoreBreakdown, let breakdown = edgeResult.breakdown {
                                Divider().background(AppColors.border)
                                
                                VStack(spacing: 6) {
                                    scoreRow(title: "Win Rate (15đ)", value: breakdown.winRate, max: 15)
                                    scoreRow(title: "Profit Factor (25đ)", value: breakdown.profitFactor, max: 25)
                                    scoreRow(title: "Avg Win / Loss (20đ)", value: breakdown.avgWinLoss, max: 20)
                                    scoreRow(title: "Drawdown (15đ)", value: breakdown.drawdown, max: 15)
                                    scoreRow(title: "Recovery (10đ)", value: breakdown.recovery, max: 10)
                                    scoreRow(title: "Tính nhất quán (15đ)", value: breakdown.consistency, max: 15)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    
                    // Quick Stats 2x2 Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statTile(
                            title: "Win Rate",
                            value: Formatters.percentage(metrics.winRate),
                            color: AppColors.profit,
                            subtitle: "\(metrics.winningTrades)W / \(metrics.losingTrades)L / \(metrics.breakevenTrades)BE"
                        )
                        
                        statTile(
                            title: "Profit Factor",
                            value: metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "N/A"),
                            color: AppColors.accent,
                            subtitle: metrics.loss > 0 ? "Lãi/Lỗ: \(metrics.profitFactor ?? 0)" : "Không lỗ"
                        )
                        
                        statTile(
                            title: "Tổng Lệnh",
                            value: "\(metrics.totalTrades)",
                            color: AppColors.primaryText,
                            subtitle: "Khối lượng: \(metrics.totalVolume)"
                        )
                        
                        statTile(
                            title: "Max Drawdown",
                            value: metrics.maxDrawdownPct != nil ? String(format: "-%.1f%%", metrics.maxDrawdownPct! * 100) : "0.0%",
                            color: AppColors.loss,
                            subtitle: metrics.maxDrawdown != nil ? Formatters.formatCurrency(metrics.maxDrawdown!, currency: env.currentCurrency) : "-"
                        )
                        
                        statTile(
                            title: "Expectancy",
                            value: metrics.expectancy != nil ? Formatters.formatPnL(metrics.expectancy!, currency: env.currentCurrency) : "-",
                            color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss,
                            subtitle: "Kỳ vọng/lệnh"
                        )
                        
                        statTile(
                            title: "Streak Lãi / Lỗ",
                            value: "\(metrics.maxConsecutiveWins)W / \(metrics.maxConsecutiveLosses)L",
                            color: AppColors.secondaryText,
                            subtitle: "Chuỗi liên tiếp max"
                        )
                    }
                    
                    // Interactive Charts Section
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Phân tích biểu đồ")
                                    .font(AppTypography.headline)
                                Spacer()
                            }
                            
                            Picker("Tab biểu đồ", selection: $selectedChartTab) {
                                ForEach(DashboardChartTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            switch selectedChartTab {
                            case .equity:
                                EquityCurveChart(points: chartEquityPoints, currency: env.currentCurrency)
                            case .drawdown:
                                DrawdownChart(points: chartEquityPoints)
                            case .session:
                                SessionBreakdownChart(sessions: sessionStats, currency: env.currentCurrency)
                            case .weekday:
                                WeekdayChart(weekdays: weekdayStats, currency: env.currentCurrency)
                            }
                        }
                    }
                    
                    // Symbols Breakdown Card
                    if !symbolStats.isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Mã giao dịch hàng đầu")
                                    .font(AppTypography.headline)
                                
                                ForEach(symbolStats.prefix(5)) { sym in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sym.key)
                                                .font(AppTypography.subheadlineBold)
                                            Text("\(sym.trades) lệnh • KL: \(sym.volume)")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(Formatters.formatPnL(sym.netPnl, currency: env.currentCurrency))
                                                .font(AppTypography.subheadlineBold)
                                                .foregroundColor(Formatters.pnlColor(sym.netPnl))
                                            
                                            if let wr = sym.winRate {
                                                Text("WR \(Formatters.formatPercent(wr))")
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(AppColors.secondaryText)
                                            }
                                        }
                                    }
                                    Divider().background(AppColors.border.opacity(0.4))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .background(AppColors.background)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAIReflection = true }) {
                        Image(systemName: "sparkles")
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .sheet(isPresented: $showAIReflection) {
                AIReflectionView()
            }
        }
    }
    
    // MARK: - Subcomponents
    
    private func statTile(title: String, value: String, color: Color, subtitle: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Text(value)
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func scoreRow(title: String, value: Double, max: Double) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(String(format: "%.1f / %.0f", value, max))
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
        }
    }
}
