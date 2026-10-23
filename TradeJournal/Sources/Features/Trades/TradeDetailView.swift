import SwiftUI

/// Trade detail view implementing Apple Human Interface Guidelines:
/// High contrast, breathable card containers, balanced 2-column metric tiles,
/// and design DNA 100% unified with DashboardView.
public struct TradeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let isModal: Bool
    @State var trade: Trade
    @State private var showReplayView: Bool = false
    @State private var showEditTradeSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var newTag: String = ""
    @State private var newMistake: String = ""
    @State private var noteContent: String = ""
    @State private var selectedPlaybookId: String = ""
    @State private var showAddTagInput: Bool = false
    @State private var showAddMistakeInput: Bool = false
    
    private let commonMistakes = [
        "FOMO",
        "Chased Entry",
        "Moved SL",
        "Early Exit",
        "Overtrading",
        "Revenge",
        "No Plan"
    ]
    
    private let commonTags = [
        "Trend Follow",
        "Breakout",
        "Reversal",
        "News Event",
        "Key Level"
    ]
    
    public init(trade: Trade, isModal: Bool = false) {
        self.isModal = isModal
        self._trade = State(initialValue: trade)
        let cleanNote: String = {
            guard let notes = trade.notes else { return "" }
            if notes.hasPrefix("Position synced from") { return "" }
            return notes
        }()
        self._noteContent = State(initialValue: cleanNote)
        self._selectedPlaybookId = State(initialValue: trade.playbookId ?? "")
    }
    
    private var ticketDisplay: String? {
        if let firstId = trade.executionIds.first, !firstId.isEmpty {
            return Formatters.formatEntityId(firstId)
        }
        return nil
    }
    
    private var tradeDurationString: String? {
        guard let closedAt = trade.closedAt else { return "Open" }
        let diff = closedAt.timeIntervalSince(trade.openedAt)
        if diff <= 0 { return "< 1m" }
        let mins = Int(diff / 60)
        let hours = mins / 60
        let days = hours / 24
        if days > 0 {
            let remHours = hours % 24
            return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
        } else if hours > 0 {
            let remMins = mins % 60
            return remMins > 0 ? "\(hours)h \(remMins)m" : "\(hours)h"
        } else {
            return "\(max(1, mins))m"
        }
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
    
    // MARK: - Dashboard-Grade Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Dashboard-Grade Stat Header
    private func statHeader(_ title: String, icon: String, actionTitle: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
            
            Spacer()
            
            if let at = actionTitle, let action = onAction {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(at)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppColors.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.brand.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(ApplePressableButtonStyle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(AppColors.secondaryBackground.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Dashboard-Grade Metric Tile
    private func metricTile(
        label: String,
        value: String,
        color: Color = AppColors.primaryText,
        subtext: String? = nil,
        valueFont: Font = AppTypography.bodyBold
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if let sub = subtext, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Main Body
    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 1. Hero Overview Card
                heroSection
                
                // 2. Financial & Execution Performance (2x2 Balanced Tiles)
                financialPerformanceSection
                
                // 3. Risk Management & Targets (2x2 Balanced Tiles + Visual Bar)
                riskManagementSection
                
                // 4. Discipline, Rating & Strategy Review
                disciplineSection
                
                // 5. Journal Notes
                notesSection
                
                // 6. Attachments & Screenshots
                attachmentsSection
                
                // 7. Actions (Replay & Delete)
                bottomActionsSection
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView(
                title: trade.symbol,
                showFilters: false,
                onBack: { dismiss() },
                isModal: isModal
            ) {
                AppActionPill("Edit", icon: "pencil") {
                    showEditTradeSheet = true
                }
                AppActionPill("Replay", icon: "play.fill") {
                    showReplayView = true
                }
            }
        }
        .background(AppColors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveEdgeBack(onBack: isModal ? nil : { dismiss() })
        .enableNativePopGesture()
        .sheet(isPresented: $showReplayView) {
            TradeReplayView(trade: trade, executions: fills, isModal: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete trade \(trade.symbol)?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete permanently", role: .destructive) {
                dataStore.deleteTrade(key: trade.key)
                dismiss()
            }
        } message: {
            Text("This trade and its associated executions will be permanently removed.")
        }
        .sheet(isPresented: $showEditTradeSheet) {
            EditManualTradeSheet(trade: trade) { updated in
                self.trade = updated
                let cleanNote: String = {
                    guard let notes = updated.notes else { return "" }
                    if notes.hasPrefix("Position synced from") { return "" }
                    return notes
                }()
                self.noteContent = cleanNote
                self.selectedPlaybookId = updated.playbookId ?? ""
            }
        }
    }
    
    // MARK: - 1. Hero Summary Card
    private var heroSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text(trade.symbol)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(trade.direction == .long ? "BUY" : "SELL")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                            .clipShape(Capsule())
                        
                        Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    AppBadge(
                        text: trade.status.rawValue.uppercased(),
                        color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                    )
                }
                
                AppMonetaryText(
                    Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 32, weight: .bold),
                    color: Formatters.pnlColor(trade.netPnl)
                )
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10.5))
                        Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                            .font(.system(size: 11.5))
                    }
                    .foregroundColor(AppColors.secondaryText)
                    
                    if let dur = tradeDurationString {
                        Text("•")
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 10.5))
                            Text(dur)
                                .font(.system(size: 11.5))
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }
    
    // MARK: - 2. Financial & Execution Performance
    private var financialPerformanceSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                statHeader("Execution & Financials", icon: "dollarsign.circle")
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricTile(
                        label: "Gross P&L",
                        value: Formatters.formatPnL(trade.grossPnl, currency: env.currentCurrency),
                        color: Formatters.pnlColor(trade.grossPnl)
                    )
                    metricTile(
                        label: "Fees & Commissions",
                        value: Formatters.formatCurrency(trade.fees, currency: env.currentCurrency),
                        color: trade.fees > 0 ? AppColors.warning : AppColors.primaryText
                    )
                    metricTile(
                        label: "Net Realized P&L",
                        value: Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                        color: Formatters.pnlColor(trade.netPnl)
                    )
                    if trade.swapAmount != 0 {
                        metricTile(
                            label: "Overnight Swap",
                            value: Formatters.formatPnL(trade.swapAmount, currency: env.currentCurrency),
                            color: trade.swapAmount < 0 ? AppColors.warning : AppColors.profit
                        )
                    } else if let ticket = ticketDisplay {
                        metricTile(
                            label: "Order Ticket",
                            value: "#\(ticket)"
                        )
                    } else {
                        metricTile(
                            label: "Duration",
                            value: tradeDurationString ?? "–"
                        )
                    }
                    metricTile(
                        label: "Avg Entry Price",
                        value: Formatters.price(trade.avgEntry),
                        subtext: Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone)
                    )
                    metricTile(
                        label: "Avg Exit Price",
                        value: trade.avgExit.map { Formatters.price($0) } ?? "Open",
                        subtext: trade.closedAt != nil ? Formatters.formatDateTime(trade.closedAt!, timeZone: env.currentTimeZone) : nil
                    )
                }
            }
        }
    }
    
    // MARK: - 3. Risk Management & Targets
    private var riskManagementSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                statHeader("Risk & Return (R:R)", icon: "shield.lefthalf.filled", actionTitle: "Edit Targets") {
                    showEditTradeSheet = true
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricTile(
                        label: "Stop Loss",
                        value: trade.stopLoss.map { Formatters.price($0) } ?? "Not set",
                        color: trade.stopLoss != nil ? AppColors.primaryText : AppColors.secondaryText
                    )
                    metricTile(
                        label: "Profit Target",
                        value: trade.profitTarget.map { Formatters.price($0) } ?? "Not set",
                        color: trade.profitTarget != nil ? AppColors.primaryText : AppColors.secondaryText
                    )
                    metricTile(
                        label: "Risk at Stake (1R)",
                        value: riskAmount.map { Formatters.formatCurrency($0, currency: env.currentCurrency) } ?? "–",
                        color: riskAmount != nil ? AppColors.loss : AppColors.secondaryText
                    )
                    metricTile(
                        label: "Realized Return",
                        value: realizedR.map { String(format: "%+.2f R", ($0 as NSDecimalNumber).doubleValue) } ?? (plannedR.map { String(format: "Planned %.2f R", ($0 as NSDecimalNumber).doubleValue) } ?? "–"),
                        color: (realizedR ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                    )
                }
                
                // Visual R:R comparison bar when both targets exist
                if let pR = plannedR {
                    let plannedVal = max(0.1, (pR as NSDecimalNumber).doubleValue)
                    VStack(spacing: 4) {
                        HStack {
                            Text("Risk / Reward Ratio")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(String(format: "1 : %.2f R", plannedVal))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(AppColors.brand)
                        }
                        
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                Capsule()
                                    .fill(AppColors.loss.opacity(0.8))
                                    .frame(width: max(24, geo.size.width * CGFloat(1.0 / (1.0 + plannedVal))))
                                Capsule()
                                    .fill(AppColors.profit.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - 4. Discipline, Rating & Strategy
    private var disciplineSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                statHeader("Discipline & Playbook", icon: "book.pages")
                
                // Execution Rating row
                HStack {
                    Text("Execution Rating")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= (trade.rating ?? 0) ? "star.fill" : "star")
                                .foregroundColor(star <= (trade.rating ?? 0) ? .yellow : AppColors.secondaryText.opacity(0.3))
                                .font(.system(size: 18))
                                .onTapGesture {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    trade.rating = (trade.rating == star) ? nil : star
                                    persistTradeUpdates()
                                }
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Playbook Strategy
                HStack {
                    Text("Playbook Strategy")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    AppleMenuChip(
                        selectionText: activePlaybook?.name ?? "None",
                        icon: "book.pages"
                    ) {
                        Button("None") {
                            selectedPlaybookId = ""
                            trade.playbookId = nil
                            persistTradeUpdates()
                        }
                        ForEach(dataStore.playbooks) { pb in
                            Button(pb.name) {
                                selectedPlaybookId = pb.id
                                trade.playbookId = pb.id
                                persistTradeUpdates()
                            }
                        }
                    }
                }
                
                if let pb = activePlaybook {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pb.rules, id: \.self) { rule in
                            let isChecked = dataStore.playbookAssessments.first(where: {
                                $0.tradeKey == trade.key && $0.playbookId == pb.id && $0.rule == rule
                            })?.followed ?? false
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                dataStore.setRuleAssessment(
                                    tradeKey: trade.key,
                                    playbookId: pb.id,
                                    rule: rule,
                                    followed: !isChecked
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isChecked ? AppColors.profit : AppColors.secondaryText)
                                        .font(.system(size: 15))
                                    Text(rule)
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.primaryText)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Mistakes Identified
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mistakes Identified")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Button {
                            showAddMistakeInput.toggle()
                        } label: {
                            Image(systemName: showAddMistakeInput ? "chevron.up" : "plus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                    
                    if !trade.mistakes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(trade.mistakes, id: \.self) { mistake in
                                    HStack(spacing: 4) {
                                        Text("⚠️ \(mistake)")
                                        Image(systemName: "xmark")
                                            .font(.system(size: 7, weight: .bold))
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.loss)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.loss.opacity(0.12))
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        trade.mistakes.removeAll { $0 == mistake }
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(commonMistakes, id: \.self) { m in
                                let isAdded = trade.mistakes.contains(m)
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    if isAdded {
                                        trade.mistakes.removeAll { $0 == m }
                                    } else {
                                        trade.mistakes.append(m)
                                    }
                                    persistTradeUpdates()
                                } label: {
                                    Text(m)
                                        .font(.system(size: 11, weight: isAdded ? .bold : .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isAdded ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                        .foregroundColor(isAdded ? AppColors.loss : AppColors.secondaryText)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                    
                    if showAddMistakeInput {
                        HStack(spacing: 6) {
                            TextField("Custom mistake...", text: $newMistake)
                                .font(AppTypography.caption)
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            Button("Add") {
                                let clean = newMistake.trimmingCharacters(in: .whitespaces)
                                if !clean.isEmpty && !trade.mistakes.contains(clean) {
                                    trade.mistakes.append(clean)
                                    newMistake = ""
                                    persistTradeUpdates()
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(AppColors.loss)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .padding(.top, 2)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Strategy Tags
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Strategy Tags")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Button {
                            showAddTagInput.toggle()
                        } label: {
                            Image(systemName: showAddTagInput ? "chevron.up" : "plus.circle")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                    
                    if !trade.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(trade.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                        Image(systemName: "xmark")
                                            .font(.system(size: 7, weight: .bold))
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.brand)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.brand.opacity(0.12))
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        trade.tags.removeAll { $0 == tag }
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(commonTags, id: \.self) { t in
                                let isAdded = trade.tags.contains(t)
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    if isAdded {
                                        trade.tags.removeAll { $0 == t }
                                    } else {
                                        trade.tags.append(t)
                                    }
                                    persistTradeUpdates()
                                } label: {
                                    Text("#\(t)")
                                        .font(.system(size: 11, weight: isAdded ? .bold : .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isAdded ? AppColors.brand.opacity(0.15) : AppColors.secondaryBackground)
                                        .foregroundColor(isAdded ? AppColors.brand : AppColors.secondaryText)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                    
                    if showAddTagInput {
                        HStack(spacing: 6) {
                            TextField("Custom tag...", text: $newTag)
                                .font(AppTypography.caption)
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            Button("Add") {
                                let clean = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                                if !clean.isEmpty && !trade.tags.contains(clean) {
                                    trade.tags.append(clean)
                                    newTag = ""
                                    persistTradeUpdates()
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(AppColors.brand)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
    
    // MARK: - 5. Journal Notes
    private var notesSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader("Journal Notes", icon: "note.text", actionTitle: "Save Notes") {
                    persistTradeUpdates()
                }
                
                ZStack(alignment: .topLeading) {
                    if noteContent.isEmpty {
                        Text("Document setup thesis, entry triggers, emotion state, or lessons learned...")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $noteContent)
                        .font(AppTypography.inputText)
                        .frame(minHeight: 100)
                        .padding(4)
                        .background(Color.clear)
                }
                .background(AppColors.secondaryBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - 6. Attachments & Screenshots
    private var attachmentsSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader("Chart Screenshots", icon: "photo.stack")
                AttachmentsSectionView(
                    ownerType: "trade",
                    ownerId: trade.key,
                    title: ""
                )
            }
        }
    }
    
    // MARK: - 7. Bottom Actions (Replay & Delete)
    private var bottomActionsSection: some View {
        VStack(spacing: 10) {
            Button {
                showReplayView = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Launch Interactive Replay")
                        .font(AppTypography.subheadlineBold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AppColors.brand)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                showDeleteAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("Delete Trade")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppColors.loss.opacity(0.1))
                .foregroundColor(AppColors.loss)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
    
    // MARK: - Persistence Helper
    private func persistTradeUpdates() {
        let trimmedNote = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesToSave = trimmedNote.isEmpty || trimmedNote.hasPrefix("Position synced from") ? nil : trimmedNote
        
        dataStore.updateTradeAnnotations(
            key: trade.key,
            notes: notesToSave,
            tags: trade.tags,
            mistakes: trade.mistakes,
            stopLoss: trade.stopLoss,
            profitTarget: trade.profitTarget,
            rating: trade.rating,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            reviewedAt: Date()
        )
        
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            self.trade = updated
        }
    }
}
