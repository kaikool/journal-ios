import SwiftUI
import Charts

public enum ReportMode: String, CaseIterable, Identifiable {
    case overview = "Tổng quan"
    case trends = "Xu hướng"
    case explorer = "Khám phá"
    case breakdown = "Phân rã"
    case cross = "Phân tích chéo"
    case compare = "So sánh"
    
    public var id: String { rawValue }
}

/// Màn hình Báo cáo và Phân tích chuyên sâu
/// Port 1:1 từ `source-repo/apps/web/src/app/reports/page.tsx`
public struct ReportsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedMode: ReportMode = .overview
    @State private var primaryDimension: Dimension = .symbol
    @State private var secondaryDimension: Dimension = .weekday
    @State private var showAiReflectionSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.filteredTrades
    }
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: trades)
    }
    
    private var groupResults: [GroupAnalysisResult] {
        let sec: Dimension? = selectedMode == .cross ? secondaryDimension : nil
        return TradeAnalysisEngine.analyzeGroups(
            trades: trades,
            primary: primaryDimension,
            secondary: sec,
            timeZone: env.currentTimeZone.identifier
        )
    }
    
    private var summaryKPIs: [(label: String, value: String, isNet: Bool)] {
        let s = metrics
        let pfStr: String = s.profitFactorIsInfinite ? "∞" : (s.profitFactor != nil ? String(format: "%.2f", NSDecimalNumber(decimal: s.profitFactor!).doubleValue) : "–")
        let netStr = s.netPnl >= 0 ? "+\(Formatters.currency(s.netPnl))" : Formatters.currency(s.netPnl)
        let wrStr = s.winRate != nil ? Formatters.percent(s.winRate) : "–"
        let volStr = "\(s.totalVolume.formatted())"
        
        let avgRealizedR = TradeAnalysisEngine.summarizeGroup(all: trades).avgRealizedR
        let avgPlannedR = TradeAnalysisEngine.summarizeGroup(all: trades).avgPlannedR
        let avgRStr = avgRealizedR != nil ? String(format: "%.2f R", avgRealizedR!) : "–"
        let avgPlanRStr = avgPlannedR != nil ? String(format: "%.2f R", avgPlannedR!) : "–"
        
        return [
            ("Lệnh đã đóng", "\(s.closedTrades)", false),
            ("Lợi nhuận ròng (Net P&L)", netStr, true),
            ("Tỷ lệ thắng (Win rate)", wrStr, false),
            ("Hệ số lợi nhuận (PF)", pfStr, false),
            ("Khối lượng vào lệnh", volStr, false),
            ("Kỳ vọng mỗi lệnh (Exp)", s.expectancy != nil ? Formatters.currency(s.expectancy!) : "–", false),
            ("Tỷ lệ R dự kiến (Plan R)", avgPlanRStr, false),
            ("Tỷ lệ R thực hiện (Real R)", avgRStr, false)
        ]
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header & Ask AI Action Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Báo Cáo & Phân Tích")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)
                            Text("Phân rã đa chiều và trích xuất lợi thế giao dịch (Edge)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button {
                            showAiReflectionSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Hỏi AI")
                            }
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Mode Selector (Port 1:1 từ thanh nút chọn mode của Reports)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ReportMode.allCases) { mode in
                                Button {
                                    selectedMode = mode
                                } label: {
                                    Text(mode.rawValue)
                                        .font(AppTypography.captionBold)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedMode == mode ? AppColors.accent : AppColors.cardBackground)
                                        .foregroundColor(selectedMode == mode ? .white : AppColors.primaryText)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedMode == mode ? Color.clear : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Nội dung theo từng chế độ
                    switch selectedMode {
                    case .overview:
                        overviewSection
                    case .trends:
                        trendsSection
                    case .explorer:
                        explorerSection
                    case .breakdown, .cross:
                        breakdownAndCrossSection
                    case .compare:
                        compareSection
                    }
                }
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAiReflectionSheet) {
                AIReflectionView()
            }
            .sheet(isPresented: $showExportSheet) {
                ReviewExportModal(title: "Báo cáo giao dịch", exportText: exportText)
            }
        }
    }
    
    // MARK: - Sections
    
    private var overviewSection: some View {
        VStack(spacing: 16) {
            // 8 KPI Summary Grid
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Chỉ số tổng hợp (Performance Summary)")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(summaryKPIs, id: \.label) { kpi in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kpi.label)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(kpi.value)
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(kpi.isNet ? (metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss) : AppColors.primaryText)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Biểu đồ ngày trong tuần
            let weekdayStats = AggregateEngine.byWeekday(trades: trades, timeZone: env.currentTimeZone)
            WeekdayChart(weekdays: weekdayStats, currency: env.currentCurrency)
                .padding(.horizontal, 16)
            
            // Biểu đồ phiên giao dịch
            let sessionStats = AggregateEngine.bySession(trades: trades)
            SessionBreakdownChart(sessions: sessionStats, currency: env.currentCurrency)
                .padding(.horizontal, 16)
        }
    }
    
    private var trendsSection: some View {
        VStack(spacing: 16) {
            // Đường cong lợi nhuận tích luỹ (Equity Curve)
            let overview = FinancialMetricsEngine.computeOverview(trades: trades, timeZone: env.currentTimeZone)
            let equityPoints = overview.curve.map { p in
                EquityPointItem(
                    date: p.timestamp,
                    dateKey: p.dateString,
                    netPnl: p.cumNetPnl,
                    cumulativePnl: p.cumNetPnl,
                    drawdown: Decimal.zero
                )
            }
            
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Đường cong vốn (Equity Curve)")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    EquityCurveChart(points: equityPoints, currency: env.currentCurrency)
                }
            }
            .padding(.horizontal, 16)
            
            // Biểu đồ sụt giảm vốn (Drawdown)
            DrawdownChart(points: equityPoints)
                .padding(.horizontal, 16)
        }
    }
    
    private var explorerSection: some View {
        VStack(spacing: 16) {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Khám phá lệnh (\(trades.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    if trades.isEmpty {
                        Text("Không có lệnh giao dịch nào khớp với bộ lọc.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(trades.prefix(30)) { t in
                                HStack {
                                    Text(t.status.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(t.netPnl >= 0 ? AppColors.profit.opacity(0.15) : AppColors.loss.opacity(0.15))
                                        .foregroundColor(t.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    
                                    Text(t.symbol)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(AppColors.primaryText)
                                    
                                    Spacer()
                                    
                                    Text(t.netPnl >= 0 ? "+\(Formatters.currency(t.netPnl))" : Formatters.currency(t.netPnl))
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(t.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                }
                                .padding(.vertical, 4)
                                
                                if t.id != trades.prefix(30).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var breakdownAndCrossSection: some View {
        VStack(spacing: 16) {
            // Dimension Pickers
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Thiết lập chiều phân tích")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nhóm theo (Cột 1)")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                            
                            Picker("Chiều 1", selection: $primaryDimension) {
                                ForEach(Dimension.allCases, id: \.self) { dim in
                                    Text(dim.label).tag(dim)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        if selectedMode == .cross {
                            Divider()
                                .frame(height: 36)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tiếp tục theo (Cột 2)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                
                                Picker("Chiều 2", selection: $secondaryDimension) {
                                    ForEach(Dimension.allCases, id: \.self) { dim in
                                        Text(dim.label).tag(dim)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Bảng kết quả phân rã chi tiết
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selectedMode == .cross ? "\(primaryDimension.label) × \(secondaryDimension.label)" : "Hiệu suất theo \(primaryDimension.label)")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    if groupResults.isEmpty {
                        Text("Không có dữ liệu lệnh phù hợp để phân rã.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(groupResults, id: \.row) { g in
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.column.isEmpty ? g.row : "\(g.row) / \(g.column)")
                                            .font(AppTypography.bodyBold)
                                            .foregroundColor(AppColors.primaryText)
                                        
                                        HStack(spacing: 6) {
                                            Text("\(g.summary.trades) lệnh")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppColors.secondaryText)
                                            
                                            if let wr = g.summary.winRate {
                                                Text("• Win \(Int(wr * 100))%")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(AppColors.primaryText)
                                            }
                                            
                                            if let r = g.summary.avgRealizedR {
                                                Text("• \(String(format: "%.1f", r))R")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(AppColors.secondaryText)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text(g.summary.netPnl >= 0 ? "+\(Formatters.currency(g.summary.netPnl))" : Formatters.currency(g.summary.netPnl))
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(g.summary.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                }
                                
                                if g.row != groupResults.last?.row {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var compareSection: some View {
        VStack(spacing: 16) {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("So sánh theo Chiến lược (Playbooks)")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    let pResults = TradeAnalysisEngine.analyzeGroups(trades: trades, primary: .playbook)
                    if pResults.isEmpty {
                        Text("Chưa có chiến lược nào được gán cho lệnh.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(pResults, id: \.row) { item in
                            HStack {
                                Text(item.row.isEmpty ? "Không có chiến lược" : item.row)
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(AppColors.primaryText)
                                Spacer()
                                Text(item.summary.netPnl >= 0 ? "+\(Formatters.currency(item.summary.netPnl))" : Formatters.currency(item.summary.netPnl))
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(item.summary.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
