import SwiftUI

/// Trade detail view implementing Apple Human Interface Guidelines:
/// Clean hierarchy, generous breathing room (thoáng), high contrast, and accessible key-value rows.
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
    @State private var stopLossText: String = ""
    @State private var profitTargetText: String = ""
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
        self._stopLossText = State(initialValue: Formatters.formatDecimalInput(trade.stopLoss, maxDecimals: 5))
        self._profitTargetText = State(initialValue: Formatters.formatDecimalInput(trade.profitTarget, maxDecimals: 5))
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
    
    // MARK: - Apple HIG Inset Grouped Section Card
    private func sectionCard<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = title {
                Text(t.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, 4)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Apple HIG Labeled Row Helper
    private func infoRow(label: String, value: String, valueColor: Color = AppColors.primaryText, secondaryValue: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            HStack(spacing: 6) {
                Text(value)
                    .font(AppTypography.subheadlineBold)
                    .monospacedDigit()
                    .foregroundColor(valueColor)
                
                if let sec = secondaryValue {
                    Text(sec)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding(.vertical, 7)
    }
    
    // MARK: - Main Body
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - 1. Hero Overview (Airy, prominent, clean)
                heroSection
                
                // MARK: - 2. Financial & Execution Performance
                financialPerformanceSection
                
                // MARK: - 3. Risk Management & Targets
                riskManagementSection
                
                // MARK: - 4. Discipline, Rating & Strategy
                disciplineSection
                
                // MARK: - 5. Journal Notes
                notesSection
                
                // MARK: - 6. Attachments & Screenshots
                attachmentsSection
                
                // MARK: - 7. Actions (Replay & Delete)
                bottomActionsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 40)
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
                self.stopLossText = Formatters.formatDecimalInput(updated.stopLoss, maxDecimals: 5)
                self.profitTargetText = Formatters.formatDecimalInput(updated.profitTarget, maxDecimals: 5)
                self.selectedPlaybookId = updated.playbookId ?? ""
            }
        }
    }
    
    // MARK: - 1. Top Hero Section
    private var heroSection: some View {
        VStack(spacing: 8) {
            AppMonetaryText(
                Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                isPrivate: env.isPrivacyModeEnabled,
                font: .system(size: 32, weight: .bold, design: .rounded),
                color: Formatters.pnlColor(trade.netPnl)
            )
            
            HStack(spacing: 8) {
                Text(trade.direction == .long ? "BUY / LONG" : "SELL / SHORT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                    .clipShape(Capsule())
                
                AppBadge(
                    text: trade.status.rawValue.uppercased(),
                    color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                )
                
                Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.secondaryText)
                
                if let dur = tradeDurationString {
                    Text("•")
                        .foregroundColor(AppColors.secondaryText.opacity(0.4))
                    Text(dur)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    
    // MARK: - 2. Financial & Execution Performance
    private var financialPerformanceSection: some View {
        sectionCard(title: "Execution & Financials") {
            infoRow(
                label: "Gross P&L",
                value: Formatters.formatPnL(trade.grossPnl, currency: env.currentCurrency),
                valueColor: Formatters.pnlColor(trade.grossPnl)
            )
            Divider().background(AppColors.border.opacity(0.3))
            
            infoRow(
                label: "Fees & Commissions",
                value: Formatters.formatCurrency(trade.fees, currency: env.currentCurrency),
                valueColor: trade.fees > 0 ? AppColors.warning : AppColors.primaryText
            )
            
            if trade.swapAmount != 0 {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Overnight Swap",
                    value: Formatters.formatPnL(trade.swapAmount, currency: env.currentCurrency),
                    valueColor: trade.swapAmount < 0 ? AppColors.warning : AppColors.profit
                )
            }
            
            Divider().background(AppColors.border.opacity(0.3))
            infoRow(
                label: "Net Realized P&L",
                value: Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                valueColor: Formatters.pnlColor(trade.netPnl)
            )
            
            Divider().background(AppColors.border.opacity(0.3))
            infoRow(
                label: "Avg Entry Price",
                value: Formatters.price(trade.avgEntry),
                secondaryValue: Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone)
            )
            
            if let exit = trade.avgExit {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Avg Exit Price",
                    value: Formatters.price(exit),
                    secondaryValue: trade.closedAt != nil ? Formatters.formatDateTime(trade.closedAt!, timeZone: env.currentTimeZone) : nil
                )
            }
            
            if let ticket = ticketDisplay {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Order Ticket",
                    value: "#\(ticket)"
                )
            }
        }
    }
    
    // MARK: - 3. Risk Management & Targets
    private var riskManagementSection: some View {
        sectionCard(title: "Risk & Return (R:R)") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stop Loss")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    TextField("Not set", text: $stopLossText)
                        .font(AppTypography.bodyBold)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .keyboardType(.decimalPad)
                        .onSubmit { persistTradeUpdates() }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profit Target")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    TextField("Not set", text: $profitTargetText)
                        .font(AppTypography.bodyBold)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .keyboardType(.decimalPad)
                        .onSubmit { persistTradeUpdates() }
                }
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    persistTradeUpdates()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(AppColors.brand)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ApplePressableButtonStyle())
                .padding(.top, 18)
            }
            .padding(.vertical, 4)
            
            if let risk = riskAmount {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Risk at Stake (1R)",
                    value: Formatters.formatCurrency(risk, currency: env.currentCurrency),
                    valueColor: AppColors.loss
                )
            }
            
            if let pR = plannedR {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Planned R:R",
                    value: String(format: "%.2fR", (pR as NSDecimalNumber).doubleValue),
                    valueColor: AppColors.brand
                )
            }
            
            if let rR = realizedR {
                Divider().background(AppColors.border.opacity(0.3))
                infoRow(
                    label: "Realized Return",
                    value: String(format: "%+.2fR", (rR as NSDecimalNumber).doubleValue),
                    valueColor: rR >= 0 ? AppColors.profit : AppColors.loss
                )
            }
        }
    }
    
    // MARK: - 4. Discipline, Rating & Strategy
    private var disciplineSection: some View {
        sectionCard(title: "Discipline & Strategy Review") {
            // Rating row
            HStack {
                Text("Execution Rating")
                    .font(AppTypography.subheadline)
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
            .padding(.vertical, 7)
            
            Divider().background(AppColors.border.opacity(0.3))
            
            // Playbook row
            HStack {
                Text("Playbook")
                    .font(AppTypography.subheadline)
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
            .padding(.vertical, 7)
            
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
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
            
            Divider().background(AppColors.border.opacity(0.3))
            
            // Mistakes row
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mistakes & Biases")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Button {
                        showAddMistakeInput.toggle()
                    } label: {
                        Image(systemName: showAddMistakeInput ? "chevron.up" : "plus.circle")
                            .font(.system(size: 14))
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
                
                // Quick tap presets
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
                    .padding(.vertical, 2)
                }
                
                if showAddMistakeInput {
                    HStack(spacing: 6) {
                        TextField("e.g. FOMO, Moved SL...", text: $newMistake)
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
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 7)
            
            Divider().background(AppColors.border.opacity(0.3))
            
            // Tags row
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tags")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Button {
                        showAddTagInput.toggle()
                    } label: {
                        Image(systemName: showAddTagInput ? "chevron.up" : "plus.circle")
                            .font(.system(size: 14))
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
                
                // Quick tap presets
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
                    .padding(.vertical, 2)
                }
                
                if showAddTagInput {
                    HStack(spacing: 6) {
                        TextField("Add tag...", text: $newTag)
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
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 7)
        }
    }
    
    // MARK: - 5. Journal Notes
    private var notesSection: some View {
        sectionCard(title: "Journal Notes & Analysis") {
            HStack {
                Spacer()
                Button("Save Notes") {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    persistTradeUpdates()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.brand)
            }
            .padding(.bottom, 6)
            
            ZStack(alignment: .topLeading) {
                if noteContent.isEmpty {
                    Text("Document your setup thesis, entry trigger, emotions, or lessons learned...")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                }
                
                TextEditor(text: $noteContent)
                    .font(AppTypography.inputText)
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(Color.clear)
            }
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - 6. Attachments & Screenshots
    private var attachmentsSection: some View {
        sectionCard(title: "Attachments & Screenshots") {
            AttachmentsSectionView(
                ownerType: "trade",
                ownerId: trade.key,
                title: "Chart Screenshots"
            )
        }
    }
    
    // MARK: - 7. Bottom Actions (Replay & Delete)
    private var bottomActionsSection: some View {
        VStack(spacing: 12) {
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
        .padding(.top, 4)
    }
    
    // MARK: - Persistence Helper
    private func persistTradeUpdates() {
        let sl = Decimal(string: stopLossText.replacingOccurrences(of: ",", with: "."))
        let tp = Decimal(string: profitTargetText.replacingOccurrences(of: ",", with: "."))
        let trimmedNote = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesToSave = trimmedNote.isEmpty || trimmedNote.hasPrefix("Position synced from") ? nil : trimmedNote
        
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
