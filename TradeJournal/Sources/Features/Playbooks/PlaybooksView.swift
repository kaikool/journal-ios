import SwiftUI

/// Màn hình quản lý chiến lược giao dịch & đo lường kỷ luật tuân thủ quy tắc
/// Port 1:1 từ `source-repo/apps/web/src/app/playbooks` & `adherence.ts`
public struct PlaybooksView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showNewPlaybookSheet: Bool = false
    
    public init() {}
    
    private var adherenceSummaries: [PlaybookAdherenceSummary] {
        AdherenceEngine.analyzeAdherence(
            playbooks: dataStore.playbooks,
            trades: dataStore.filteredTrades,
            assessments: dataStore.playbookAssessments
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Playbooks",
                showFilters: false
            ) {
                AppButton("New playbook", icon: "plus", style: .primary) {
                    showNewPlaybookSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    
                    if dataStore.playbooks.isEmpty {
                        emptyState
                    } else {
                        playbooksList
                    }
                }
                .padding(14)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewPlaybookSheet) {
            NewPlaybookSheet { newPb in
                dataStore.savePlaybook(newPb)
            }
        }
    }
    
    @ViewBuilder
    private var headerCard: some View {
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
    }
    
    @ViewBuilder
    private var emptyState: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "Chưa có Playbook",
            message: "Tạo chiến lược giao dịch đầu tiên để theo dõi tỷ lệ tuân thủ kỷ luật."
        )
        .padding(.top, 40)
    }
    
    @ViewBuilder
    private var playbooksList: some View {
        ForEach(adherenceSummaries) { summary in
            let pbTrades = tradesForPlaybook(summary.playbook.id)
            NavigationLink(destination: PlaybookDetailView(
                playbook: summary.playbook,
                summary: summary,
                trades: pbTrades
            )) {
                playbookCard(summary: summary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func tradesForPlaybook(_ playbookId: String) -> [Trade] {
        dataStore.filteredTrades.filter { $0.playbookId == playbookId }
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let playbook: Playbook
    let summary: PlaybookAdherenceSummary
    let trades: [Trade]
    
    @State private var showDeleteAlert = false
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoCard
                rulesCard
                tradesSection
                deleteButton
            }
            .padding()
        }
        .navigationTitle(playbook.title)
        .background(AppColors.background)
        .alert("Xóa playbook “\(playbook.title)”? ", isPresented: $showDeleteAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa", role: .destructive) {
                dataStore.deletePlaybook(id: playbook.id)
                dismiss()
            }
        } message: {
            Text("Chiến lược này và các đánh giá quy tắc liên quan sẽ bị xóa.")
        }
    }
    
    @ViewBuilder
    private var infoCard: some View {
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
    }
    
    @ViewBuilder
    private var rulesCard: some View {
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
                    if index < playbook.rules.count - 1 {
                        Divider().background(AppColors.border.opacity(0.4))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var tradesSection: some View {
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
                    tradeCard(trade)
                }
            }
        }
    }
    
    @ViewBuilder
    private func tradeCard(_ trade: Trade) -> some View {
        let isLong = trade.direction == .long
        let dirColor = isLong ? AppColors.accent : AppColors.warning
        
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(trade.symbol)
                        .font(AppTypography.subheadlineBold)
                    AppBadge(
                        text: trade.direction.rawValue.uppercased(),
                        color: dirColor
                    )
                    Spacer()
                    Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(Formatters.pnlColor(trade.netPnl))
                }
                
                // Rule checkboxes for this trade
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(playbook.rules, id: \.self) { rule in
                        ruleCheckboxRow(trade: trade, rule: rule)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleCheckboxRow(trade: Trade, rule: String) -> some View {
        let followed = dataStore.playbookAssessments.first(where: {
            $0.tradeKey == trade.key && $0.playbookId == playbook.id && $0.rule == rule
        })?.followed ?? false
        
        HStack {
            Image(systemName: followed ? "checkmark.square.fill" : "square")
                .foregroundColor(followed ? AppColors.profit : AppColors.secondaryText)
                .onTapGesture {
                    dataStore.setRuleAssessment(tradeKey: trade.key, playbookId: playbook.id, rule: rule, followed: !followed)
                }
            Text(rule)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryText)
        }
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive, action: { showDeleteAlert = true }) {
            HStack {
                Image(systemName: "trash")
                Text("Xóa Playbook Này")
            }
            .font(AppTypography.captionBold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppColors.loss.opacity(0.1))
            .foregroundColor(AppColors.loss)
            .cornerRadius(12)
        }
        .padding(.top, 8)
    }
}

// MARK: - New Playbook Sheet

public struct NewPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var rules: [String] = []
    @State private var currentRuleInput: String = ""
    
    var onSave: (Playbook) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Tên & Mô tả") {
                    TextField("Tên Playbook (VD: London Breakout)", text: $title)
                    TextField("Mô tả chiến lược...", text: $description)
                }
                
                Section("Quy tắc bắt buộc") {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack {
                            Text("\(index + 1). \(rule)")
                                .font(AppTypography.caption)
                            Spacer()
                            Button(action: { rules.remove(at: index) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(AppColors.loss)
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Thêm quy tắc mới...", text: $currentRuleInput)
                        Button("Thêm") {
                            let clean = currentRuleInput.trimmingCharacters(in: .whitespaces)
                            if !clean.isEmpty {
                                rules.append(clean)
                                currentRuleInput = ""
                            }
                        }
                        .disabled(currentRuleInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Tạo Playbook Mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let pb = Playbook(
                            title: title.isEmpty ? "New Playbook" : title,
                            description: description,
                            rules: rules
                        )
                        onSave(pb)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
