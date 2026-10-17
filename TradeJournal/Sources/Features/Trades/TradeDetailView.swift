import SwiftUI

/// Màn hình chi tiết giao dịch (Trade Detail)
/// Port 1:1 từ `source-repo/apps/web/src/app/trades/[key]/page.tsx`
public struct TradeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State var trade: Trade
    @State private var showReplayView: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var newTag: String = ""
    @State private var newMistake: String = ""
    @State private var noteContent: String = ""
    @State private var stopLossText: String = ""
    @State private var profitTargetText: String = ""
    @State private var selectedPlaybookId: String = ""
    
    public init(trade: Trade) {
        self._trade = State(initialValue: trade)
        self._noteContent = State(initialValue: trade.notes ?? "")
        self._stopLossText = State(initialValue: trade.stopLoss != nil ? "\(trade.stopLoss!)" : "")
        self._profitTargetText = State(initialValue: trade.profitTarget != nil ? "\(trade.profitTarget!)" : "")
        self._selectedPlaybookId = State(initialValue: trade.playbookId ?? "")
    }
    
    private var fills: [Execution] {
        dataStore.executions
            .filter { trade.executionIds.contains($0.id) }
            .sorted { $0.executedAt < $1.executedAt }
    }
    
    private var activePlaybook: Playbook? {
        dataStore.playbooks.first(where: { $0.id == trade.playbookId })
    }
    
    // Risk calculations
    private var riskAmount: Decimal? {
        guard let sl = trade.stopLoss, trade.avgEntry > 0 else { return nil }
        let perUnit = abs(trade.avgEntry - sl)
        return perUnit * trade.quantity
    }
    
    private var realizedR: Decimal? {
        guard let sl = trade.stopLoss, let exit = trade.avgExit, trade.avgEntry > 0 else { return nil }
        let riskPerUnit = abs(trade.avgEntry - sl)
        guard riskPerUnit > 0 else { return nil }
        let gainPerUnit = (trade.direction == .long) ? (exit - trade.avgEntry) : (trade.avgEntry - exit)
        return gainPerUnit / riskPerUnit
    }
    
    private var plannedR: Decimal? {
        guard let sl = trade.stopLoss, let tp = trade.profitTarget, trade.avgEntry > 0 else { return nil }
        let riskPerUnit = abs(trade.avgEntry - sl)
        guard riskPerUnit > 0 else { return nil }
        let targetPerUnit = abs(tp - trade.avgEntry)
        return targetPerUnit / riskPerUnit
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "\(trade.symbol) · \(trade.direction.rawValue.uppercased())",
                showFilters: false
            ) {
                AppButton("Replay", icon: "play.fill", style: .primary) {
                    showReplayView = true
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                // Header PnL Card
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(trade.symbol)
                                .font(AppTypography.headline)
                            AppBadge(
                                text: trade.direction.rawValue.uppercased(),
                                color: trade.direction == .long ? AppColors.accent : AppColors.warning
                            )
                            AppBadge(
                                text: trade.status.rawValue.uppercased(),
                                color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                            )
                            Spacer()
                            Button(action: { showReplayView = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                    Text("Replay")
                                }
                                .font(AppTypography.captionBold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.accent.opacity(0.15))
                                .foregroundColor(AppColors.accent)
                                .cornerRadius(12)
                            }
                        }
                        
                        Divider().background(AppColors.border)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lãi/Lỗ Ròng")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                    .foregroundColor(Formatters.pnlColor(trade.netPnl))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Khối lượng")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(trade.quantity)")
                                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                }
                
                // Pricing & Execution Details
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Thông số vào / ra lệnh")
                            .font(AppTypography.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Giá vào TB")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(trade.avgEntry)")
                                    .font(AppTypography.subheadlineBold)
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Giá ra TB")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(trade.avgExit != nil ? "\(trade.avgExit!)" : "Đang mở")
                                    .font(AppTypography.subheadlineBold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Phí GD")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))
                                    .font(AppTypography.subheadlineBold)
                            }
                        }
                        
                        Divider().background(AppColors.border.opacity(0.5))
                        
                        HStack {
                            Text("Thời gian mở:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                                .font(AppTypography.caption)
                        }
                        
                        if let closedAt = trade.closedAt {
                            HStack {
                                Text("Thời gian đóng:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text(Formatters.formatDateTime(closedAt, timeZone: env.currentTimeZone))
                                    .font(AppTypography.caption)
                            }
                        }
                    }
                }
                
                // Execution Legs List (Port 1:1 from source-repo Execution table)
                if !fills.isEmpty {
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lịch sử khớp lệnh (\(fills.count) lần khớp)")
                                .font(AppTypography.headline)
                            
                            ForEach(fills) { fill in
                                HStack {
                                    AppBadge(
                                        fill.side == .buy ? "BUY" : "SELL",
                                        color: fill.side == .buy ? AppColors.accent : AppColors.warning
                                    )
                                    Text("\(fill.quantity) @ \(fill.price)")
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(Formatters.formatCurrency(fill.fee, currency: env.currentCurrency))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(Formatters.formatDateTime(fill.executedAt, timeZone: env.currentTimeZone))
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                if fill.id != fills.last?.id {
                                    Divider().background(AppColors.border.opacity(0.3))
                                }
                            }
                        }
                    }
                }
                
                // Risk & Reward Section
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quản trị rủi ro (R:R)")
                            .font(AppTypography.headline)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stop Loss")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                TextField("Chưa đặt", text: $stopLossText)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.decimalPad)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Take Profit")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                TextField("Chưa đặt", text: $profitTargetText)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.decimalPad)
                            }
                            
                            VStack {
                                Text(" ")
                                    .font(AppTypography.caption)
                                Button("Lưu") {
                                    persistTradeUpdates()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.accent)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            if let risk = riskAmount {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rủi ro (1R):")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(risk, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.loss)
                                }
                            }
                            if let pR = plannedR {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Planned R:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(String(format: "%.2fR", (pR as NSDecimalNumber).doubleValue))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                            if let rR = realizedR {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Realized R:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(String(format: "%.2fR", (rR as NSDecimalNumber).doubleValue))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(rR >= 0 ? AppColors.profit : AppColors.loss)
                                }
                            }
                        }
                    }
                }
                
                // Playbook Checklist
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Chiến lược (Playbook)")
                                .font(AppTypography.headline)
                            Spacer()
                            Picker("Playbook", selection: $selectedPlaybookId) {
                                Text("Không chọn").tag("")
                                ForEach(dataStore.playbooks) { pb in
                                    Text(pb.name).tag(pb.id)
                                }
                            }
                            .onChange(of: selectedPlaybookId) {
                                trade.playbookId = selectedPlaybookId.isEmpty ? nil : selectedPlaybookId
                                persistTradeUpdates()
                            }
                        }
                        
                        if let pb = activePlaybook {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quy tắc tuân thủ:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                ForEach(pb.rules, id: \.self) { rule in
                                    let isChecked = dataStore.playbookAssessments.first(where: {
                                        $0.tradeKey == trade.key && $0.playbookId == pb.id && $0.rule == rule
                                    })?.followed ?? false
                                    
                                    HStack {
                                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                            .foregroundColor(isChecked ? AppColors.profit : AppColors.secondaryText)
                                            .onTapGesture {
                                                dataStore.setRuleAssessment(
                                                    tradeKey: trade.key,
                                                    playbookId: pb.id,
                                                    rule: rule,
                                                    followed: !isChecked
                                                )
                                            }
                                        Text(rule)
                                            .font(AppTypography.caption)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Annotations: Mistakes, Tags & Rating
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Đánh giá kỷ luật & Sai lầm")
                            .font(AppTypography.headline)
                        
                        // Rating
                        HStack {
                            Text("Đánh giá:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= (trade.rating ?? 0) ? "star.fill" : "star")
                                    .foregroundColor(star <= (trade.rating ?? 0) ? .yellow : AppColors.secondaryText)
                                    .onTapGesture {
                                        trade.rating = (trade.rating == star) ? nil : star
                                        persistTradeUpdates()
                                    }
                            }
                        }
                        
                        // Tags
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(trade.tags, id: \.self) { tag in
                                        AppBadge(text: "#\(tag)", color: AppColors.accent)
                                            .onTapGesture {
                                                trade.tags.removeAll { $0 == tag }
                                                persistTradeUpdates()
                                            }
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("Thêm tag...", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                Button("Thêm") {
                                    let clean = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                                    if !clean.isEmpty && !trade.tags.contains(clean) {
                                        trade.tags.append(clean)
                                        newTag = ""
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                        
                        // Mistakes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sai lầm vi phạm:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(trade.mistakes, id: \.self) { mistake in
                                        AppBadge(text: "⚠️ \(mistake)", color: AppColors.loss)
                                            .onTapGesture {
                                                trade.mistakes.removeAll { $0 == mistake }
                                                persistTradeUpdates()
                                            }
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("VD: FOMO, Dời SL...", text: $newMistake)
                                    .textFieldStyle(.roundedBorder)
                                Button("Thêm") {
                                    let clean = newMistake.trimmingCharacters(in: .whitespaces)
                                    if !clean.isEmpty && !trade.mistakes.contains(clean) {
                                        trade.mistakes.append(clean)
                                        newMistake = ""
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Notes Section (TextEditor with persistent save)
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Ghi chú phân tích & Nhật ký lệnh")
                                .font(AppTypography.headline)
                            Spacer()
                            Button("Lưu ghi chú") {
                                persistTradeUpdates()
                            }
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.accent)
                        }
                        
                        TextEditor(text: $noteContent)
                            .frame(minHeight: 90)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.border.opacity(0.5), lineWidth: 1))
                    }
                }
                
                // Attachments & Screenshots
                AppCard {
                    AttachmentsSectionView(
                        ownerType: "trade",
                        ownerId: trade.key,
                        title: "Ảnh biểu đồ & Bằng chứng vào lệnh"
                    )
                }
                
                // Delete Trade Button
                Button(role: .destructive, action: { showDeleteAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Xóa Giao Dịch Này")
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
            .padding(14)
        }
        .background(AppColors.background)
    }
    .background(AppColors.background)
    .navigationDestination(isPresented: $showReplayView) {
            TradeReplayView(trade: trade, executions: fills)
        }
        .alert("Xóa giao dịch \(trade.symbol)?", isPresented: $showDeleteAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa vĩnh viễn", role: .destructive) {
                dataStore.deleteTrade(key: trade.key)
                dismiss()
            }
        } message: {
            Text("Lệnh này và các khớp lệnh liên quan sẽ bị xóa khỏi tài khoản.")
        }
    }
    
    private func persistTradeUpdates() {
        let sl = Decimal(string: stopLossText.replacingOccurrences(of: ",", with: "."))
        let tp = Decimal(string: profitTargetText.replacingOccurrences(of: ",", with: "."))
        let notesToSave = noteContent.trimmingCharacters(in: .whitespaces).isEmpty ? nil : noteContent
        
        dataStore.updateTradeAnnotations(
            key: trade.key,
            notes: notesToSave,
            tags: trade.tags,
            mistakes: trade.mistakes,
            stopLoss: sl,
            profitTarget: tp,
            rating: trade.rating,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            reviewedAt: Date()
        )
        
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            self.trade = updated
        }
    }
}
