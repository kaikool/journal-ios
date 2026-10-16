import SwiftUI

public struct PlaybooksView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var playbooks: [Playbook] = [
        Playbook(
            id: "pb-1",
            title: "Liquidity Sweep & FVG",
            description: "Quét thanh khoản phiên Á hoặc đỉnh/đáy ngày hôm trước kết hợp Fair Value Gap.",
            rules: [
                "Giá đã quét liquidity pool rõ ràng",
                "Khung M5/M15 xuất hiện Market Structure Shift (MSS)",
                "Entry tại FVG hoặc Order Block",
                "Stop loss đặt sau điểm swing high/low",
                "RR tối thiểu 1:2"
            ],
            targetWinRate: 0.60
        ),
        Playbook(
            id: "pb-2",
            title: "London Open Breakout",
            description: "Đánh theo đà bứt phá biên độ phiên Á khi phiên London mở cửa (08:00 UTC).",
            rules: [
                "Biên độ phiên Á hẹp (< 30 pips / điểm)",
                "Cây nến H1 đầu tiên đóng dứt khoát ngoài biên độ",
                "Volume đột biến xác nhận",
                "Không giữ lệnh qua tin tức lớn"
            ],
            targetWinRate: 0.55
        )
    ]
    
    @State private var assessments: [PlaybookRuleAssessment] = []
    @State private var showNewPlaybookSheet: Bool = false
    
    public init() {}
    
    private var adherenceSummaries: [PlaybookAdherenceSummary] {
        AdherenceEngine.analyzeAdherence(
            playbooks: playbooks,
            trades: dataStore.filteredTrades,
            assessments: assessments
        )
    }
    
    public var body: some View {
        ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "book.pages.fill")
                                    .foregroundColor(AppColors.accent)
                                Text("Playbooks & Kỷ Luật Tuân Thủ")
                                    .font(AppTypography.headline)
                            }
                            Text("Đo lường sự khác biệt về kết quả tài chính giữa việc tuân thủ 100% quy tắc và việc phá vỡ nguyên tắc.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    if playbooks.isEmpty {
                        EmptyStateView(
                            icon: "book.closed",
                            title: "Chưa có Playbook",
                            message: "Tạo chiến lược giao dịch đầu tiên để theo dõi tỷ lệ tuân thủ kỷ luật."
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(adherenceSummaries) { summary in
                            NavigationLink(destination: PlaybookDetailView(
                                playbook: summary.playbook,
                                summary: summary,
                                trades: dataStore.filteredTrades.filter { $0.playbookId == summary.playbook.id },
                                assessments: $assessments
                            )) {
                                playbookCard(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Playbooks")
            .background(AppColors.background)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showNewPlaybookSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewPlaybookSheet) {
                NewPlaybookSheet { newPb in
                    playbooks.append(newPb)
                }
            }
    }
    
    private func playbookCard(summary: PlaybookAdherenceSummary) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.playbook.title)
                            .font(AppTypography.subheadlineBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("\(summary.playbook.rules.count) quy tắc • \(summary.totalTrades) lệnh")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if let rate = summary.overallAdherenceRate {
                        AppBadge(
                            text: "\(Int(rate * 100))% Tuân thủ",
                            color: rate >= 0.8 ? AppColors.profit : (rate >= 0.5 ? AppColors.accent : AppColors.loss)
                        )
                    } else {
                        AppBadge(text: "Chưa đánh giá", color: AppColors.secondaryText)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Compare followed vs broken PnL
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Khi tuân thủ quy tắc")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: env.currentCurrency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Khi phá vỡ quy tắc")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: env.currentCurrency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenBroken))
                    }
                }
            }
        }
    }
}

// MARK: - Playbook Detail View

public struct PlaybookDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let playbook: Playbook
    let summary: PlaybookAdherenceSummary
    let trades: [Trade]
    @Binding var assessments: [PlaybookRuleAssessment]
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Info Card
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mô tả chiến lược")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(playbook.description)
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                // Rules Checklist Card
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quy tắc bắt buộc (\(playbook.rules.count))")
                            .font(AppTypography.headline)
                        
                        ForEach(Array(playbook.rules.enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.accent)
                                Text(rule)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.primaryText)
                                Spacer()
                            }
                            Divider().background(AppColors.border.opacity(0.4))
                        }
                    }
                }
                
                // Trades Under Playbook
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lệnh thuộc Playbook này (\(trades.count))")
                        .font(AppTypography.headline)
                        .padding(.horizontal, 4)
                    
                    if trades.isEmpty {
                        Text("Chưa có lệnh nào được gán vào playbook này.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.horizontal, 4)
                    } else {
                        ForEach(trades) { trade in
                            AppCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(trade.symbol)
                                            .font(AppTypography.subheadlineBold)
                                        AppBadge(
                                            text: trade.direction.rawValue.uppercased(),
                                            color: trade.direction == .long ? AppColors.profit : AppColors.loss
                                        )
                                        Spacer()
                                        Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                                            .font(AppTypography.subheadlineBold)
                                            .foregroundColor(Formatters.pnlColor(trade.netPnl))
                                    }
                                    
                                    // Rule checkboxes for this trade
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(playbook.rules, id: \.self) { rule in
                                            let followed = assessments.first(where: {
                                                $0.tradeKey == trade.key && $0.playbookId == playbook.id && $0.rule == rule
                                            })?.followed ?? false
                                            
                                            HStack {
                                                Image(systemName: followed ? "checkmark.square.fill" : "square")
                                                    .foregroundColor(followed ? AppColors.profit : AppColors.secondaryText)
                                                    .onTapGesture {
                                                        toggleRule(tradeKey: trade.key, rule: rule, current: followed)
                                                    }
                                                Text(rule)
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(AppColors.primaryText)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(playbook.title)
        .background(AppColors.background)
    }
    
    private func toggleRule(tradeKey: String, rule: String, current: Bool) {
        if let idx = assessments.firstIndex(where: { $0.tradeKey == tradeKey && $0.playbookId == playbook.id && $0.rule == rule }) {
            assessments[idx] = PlaybookRuleAssessment(tradeKey: tradeKey, playbookId: playbook.id, rule: rule, followed: !current)
        } else {
            assessments.append(PlaybookRuleAssessment(tradeKey: tradeKey, playbookId: playbook.id, rule: rule, followed: true))
        }
    }
}

// MARK: - New Playbook Sheet

public struct NewPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var newRuleText: String = ""
    @State private var rules: [String] = []
    
    var onSave: (Playbook) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin chiến lược") {
                    TextField("Tên Playbook (VD: ICT Silver Bullet)", text: $title)
                    TextField("Mô tả tóm tắt", text: $description)
                }
                
                Section("Danh sách quy tắc") {
                    ForEach(rules, id: \.self) { rule in
                        Text(rule)
                    }
                    .onDelete { indices in
                        rules.remove(atOffsets: indices)
                    }
                    
                    HStack {
                        TextField("Thêm quy tắc mới...", text: $newRuleText)
                        Button("Thêm") {
                            guard !newRuleText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            rules.append(newRuleText.trimmingCharacters(in: .whitespaces))
                            newRuleText = ""
                        }
                    }
                }
            }
            .navigationTitle("Tạo Playbook mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let pb = Playbook(title: title, description: description, rules: rules)
                        onSave(pb)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
            }
        }
    }
}
