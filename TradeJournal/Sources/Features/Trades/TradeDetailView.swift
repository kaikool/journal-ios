import SwiftUI

public enum TradeDetailTab: String, CaseIterable, Identifiable {
    case analysis = "Analysis"
    case journal = "Journal"
    case media = "Media"
    
    public var id: String { rawValue }
}

/// Trade detail view matching institutional terminal design and Apple Human Interface Guidelines
public struct TradeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let isModal: Bool
    @State var trade: Trade
    @State private var selectedTab: TradeDetailTab = .analysis
    @State private var showReplayView: Bool = false
    @State private var showEditTradeSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var newTag: String = ""
    @State private var newMistake: String = ""
    @State private var noteContent: String = ""
    @State private var stopLossText: String = ""
    @State private var profitTargetText: String = ""
    @State private var selectedPlaybookId: String = ""
    
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
    
    private func ratingLabel(_ rating: Int?) -> String {
        guard let r = rating else { return "Tap stars to rate" }
        switch r {
        case 5: return "🌟 Flawless Execution"
        case 4: return "✨ Good Discipline"
        case 3: return "⚖️ Average Execution"
        case 2: return "⚠️ Rules Broken"
        case 1: return "🚨 Revenge / Emotional"
        default: return ""
        }
    }
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
    
    // MARK: - Main Body
    public var body: some View {
        VStack(spacing: 0) {
            // Sliding Segmented Navigation Bar (Analysis / Journal / Media)
            AppleSlidingSegmentedBar(
                selection: $selectedTab,
                items: TradeDetailTab.allCases,
                titleFor: { $0.rawValue }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            ScrollView {
                VStack(spacing: 12) {
                    // MARK: - Hero Performance Overview Card (Always Top)
                    heroPerformanceCard
                    
                    // MARK: - Active Tab Content
                    switch selectedTab {
                    case .analysis:
                        analysisTabView
                    case .journal:
                        journalTabView
                    case .media:
                        mediaTabView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView(
                title: "\(trade.symbol) · \(trade.direction.rawValue.uppercased())",
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
    
    // MARK: - 1. Hero Performance Overview Card
    private var heroPerformanceCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Title bar: Symbol, Direction, Status, Ticket, Duration
                HStack(spacing: 8) {
                    Text(trade.symbol)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text(trade.direction.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                        .clipShape(Capsule())
                    
                    AppBadge(
                        text: trade.status.rawValue.uppercased(),
                        color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                    )
                    
                    if let ticket = ticketDisplay {
                        Text("#\(ticket)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.secondaryBackground)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    if let duration = tradeDurationString {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(duration)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Primary Financial Metrics Row (Net PnL, Volume, Return)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Net Realized P&L")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        AppMonetaryText(
                            Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 20, weight: .bold),
                            color: Formatters.pnlColor(trade.netPnl)
                        )
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 2) {
                        Text("Volume")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Return")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        if let rR = realizedR {
                            Text(String(format: "%+.2fR", (rR as NSDecimalNumber).doubleValue))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(rR >= 0 ? AppColors.profit : AppColors.loss)
                        } else {
                            Text(trade.status == .win ? "Win" : (trade.status == .loss ? "Loss" : "BE"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                // Financial Breakdown Strip (Gross • Fees • Swap • Net)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gross")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        AppMonetaryText(
                            Formatters.formatPnL(trade.grossPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: .system(size: 12, weight: .semibold, design: .monospaced),
                            color: Formatters.pnlColor(trade.grossPnl)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 20).background(AppColors.border.opacity(0.4))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fees")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(trade.fees > 0 ? AppColors.warning : AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    
                    if trade.swapAmount != 0 {
                        Divider().frame(height: 20).background(AppColors.border.opacity(0.4))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Swap")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                            Text(Formatters.formatPnL(trade.swapAmount, currency: env.currentCurrency))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(trade.swapAmount < 0 ? AppColors.warning : AppColors.profit)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                    }
                    
                    Divider().frame(height: 20).background(AppColors.border.opacity(0.4))
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Net Realized")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        AppMonetaryText(
                            Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: .system(size: 12, weight: .bold, design: .monospaced),
                            color: Formatters.pnlColor(trade.netPnl)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppColors.secondaryBackground.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                )
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Execution Specifications (Entry, Exit, Open, Close)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Entry")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(trade.avgEntry))
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Exit")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(trade.avgExit.map(Formatters.price) ?? "Open")
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opened")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Closed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(trade.closedAt != nil ? Formatters.formatDateTime(trade.closedAt!, timeZone: env.currentTimeZone) : "Open")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                    }
                }
            }
        }
    }
    
    // MARK: - 2. Analysis Tab View (Risk Management & Fills)
    private var analysisTabView: some View {
        VStack(spacing: 12) {
            // Risk & Execution Setup Card
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.checkerboard")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Text("Risk & Execution Setup")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Spacer()
                        
                        if let rR = realizedR {
                            Text("Realized: \(String(format: "%+.2fR", (rR as NSDecimalNumber).doubleValue))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(rR >= 0 ? AppColors.profit : AppColors.loss)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((rR >= 0 ? AppColors.profit : AppColors.loss).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    
                    // Visual R:R Bar (if SL and TP are set)
                    if let pR = plannedR, let risk = riskAmount {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Risk (1.0R): \(Formatters.formatCurrency(risk, currency: env.currentCurrency))")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppColors.loss)
                                Spacer()
                                Text("Target: \(String(format: "%.2fR", (pR as NSDecimalNumber).doubleValue))")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppColors.brand)
                            }
                            
                            // Ratio progress bar
                            GeometryReader { geo in
                                let total = max(1.0, 1.0 + (pR as NSDecimalNumber).doubleValue)
                                let riskWidth = geo.size.width * CGFloat(1.0 / total)
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppColors.loss.opacity(0.8))
                                        .frame(width: max(24, riskWidth))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppColors.profit.opacity(0.8))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(8)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    // 2-Column Stop Loss & Take Profit Inputs with inline Save
                    HStack(alignment: .bottom, spacing: 10) {
                        // Stop Loss
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppColors.loss)
                                Text("Stop Loss")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            TextField("Not set", text: $stopLossText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                                )
                                .keyboardType(.decimalPad)
                                .onSubmit { persistTradeUpdates() }
                        }
                        
                        // Profit Target
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppColors.profit)
                                Text("Profit Target")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            TextField("Not set", text: $profitTargetText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                                )
                                .keyboardType(.decimalPad)
                                .onSubmit { persistTradeUpdates() }
                        }
                        
                        // Save Button
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            persistTradeUpdates()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(AppColors.brand)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    }
                    
                    // Risk Summary Metrics Strip
                    HStack(spacing: 14) {
                        if let risk = riskAmount {
                            HStack(spacing: 4) {
                                Text("Risk:")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(risk, currency: env.currentCurrency))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppColors.loss)
                            }
                        }
                        if let pR = plannedR {
                            HStack(spacing: 4) {
                                Text("Plan:")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(String(format: "%.2fR", (pR as NSDecimalNumber).doubleValue))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppColors.brand)
                            }
                        }
                        if let rR = realizedR {
                            HStack(spacing: 4) {
                                Text("Realized:")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(String(format: "%+.2fR", (rR as NSDecimalNumber).doubleValue))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(rR >= 0 ? AppColors.profit : AppColors.loss)
                            }
                        }
                    }
                }
            }
            
            // Order Executions & Legs Card
            cardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Text("Executions (\(max(1, fills.count)) legs)")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        Spacer()
                    }
                    
                    if fills.isEmpty {
                        HStack {
                            Text(trade.direction == .long ? "BUY" : "SELL")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                                .clipShape(Capsule())
                            
                            Text("\(Formatters.formatNumber(trade.quantity)) @ \(Formatters.price(trade.avgEntry))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                            
                            Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, 3)
                    } else {
                        ForEach(fills) { fill in
                            HStack {
                                Text(fill.side == .buy ? "BUY" : "SELL")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(fill.side == .buy ? AppColors.brand : AppColors.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((fill.side == .buy ? AppColors.brand : AppColors.warning).opacity(0.12))
                                    .clipShape(Capsule())
                                
                                Text("\(Formatters.formatNumber(fill.quantity)) @ \(Formatters.price(fill.price))")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 1) {
                                    if fill.fee > 0 {
                                        Text("Fee: \(Formatters.formatCurrency(fill.fee, currency: env.currentCurrency))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    Text(Formatters.formatDateTime(fill.executedAt, timeZone: env.currentTimeZone))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                            }
                            .padding(.vertical, 3)
                            
                            if fill.id != fills.last?.id {
                                Divider().background(AppColors.border.opacity(0.3))
                            }
                        }
                    }
                }
            }
            
            // Delete Trade Button
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                showDeleteAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete trade")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppColors.loss.opacity(0.1))
                .foregroundColor(AppColors.loss)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .padding(.top, 4)
        }
    }
    
    // MARK: - 3. Journal Tab View (Discipline, Mistakes, Notes)
    private var journalTabView: some View {
        VStack(spacing: 12) {
            // Discipline, Execution Rating & Playbook Card
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Text("Discipline & Execution Review")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        Spacer()
                    }
                    
                    // 5-Star Interactive Rating + Qualitative Label
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
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
                        
                        Text(ratingLabel(trade.rating))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    
                    Divider().background(AppColors.border.opacity(0.4))
                    
                    // Playbook Selection & Rules (Integrated seamlessly!)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Playbook Strategy:")
                                .font(.system(size: 11, weight: .medium))
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
                            VStack(alignment: .leading, spacing: 6) {
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
                                        HStack(spacing: 7) {
                                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isChecked ? AppColors.profit : AppColors.secondaryText)
                                                .font(.system(size: 14))
                                            Text(rule)
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.primaryText)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .background(AppColors.secondaryBackground.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            
            // Psychology, Mistakes & Tags Card (with Quick-tap Presets!)
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    // Mistakes Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("⚠️ Mistakes & Biases")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.loss)
                            Spacer()
                        }
                        
                        // Active Mistakes
                        if !trade.mistakes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(trade.mistakes, id: \.self) { mistake in
                                        HStack(spacing: 4) {
                                            Text(mistake)
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
                        
                        // Quick-tap Preset Mistakes
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonMistakes, id: \.self) { preset in
                                    let isSelected = trade.mistakes.contains(preset)
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        if isSelected {
                                            trade.mistakes.removeAll { $0 == preset }
                                        } else {
                                            trade.mistakes.append(preset)
                                        }
                                        persistTradeUpdates()
                                    } label: {
                                        Text(preset)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(isSelected ? AppColors.loss.opacity(0.2) : AppColors.secondaryBackground)
                                            .foregroundColor(isSelected ? AppColors.loss : AppColors.secondaryText)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule().stroke(isSelected ? AppColors.loss.opacity(0.5) : AppColors.border.opacity(0.4), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                        
                        // Custom Mistake input
                        HStack(spacing: 6) {
                            TextField("Add custom mistake...", text: $newMistake)
                                .font(AppTypography.caption)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            
                            if !newMistake.trimmingCharacters(in: .whitespaces).isEmpty {
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
                                .frame(height: 30)
                                .background(AppColors.loss)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                    
                    Divider().background(AppColors.border.opacity(0.4))
                    
                    // Tags Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("🏷️ Tags & Setup Types")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Spacer()
                        }
                        
                        // Active Tags
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
                        
                        // Quick-tap Preset Tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonTags, id: \.self) { preset in
                                    let isSelected = trade.tags.contains(preset)
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        if isSelected {
                                            trade.tags.removeAll { $0 == preset }
                                        } else {
                                            trade.tags.append(preset)
                                        }
                                        persistTradeUpdates()
                                    } label: {
                                        Text("#\(preset)")
                                            .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(isSelected ? AppColors.brand.opacity(0.2) : AppColors.secondaryBackground)
                                            .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule().stroke(isSelected ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.4), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                        
                        // Custom Tag input
                        HStack(spacing: 6) {
                            TextField("Add custom tag...", text: $newTag)
                                .font(AppTypography.caption)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            
                            if !newTag.trimmingCharacters(in: .whitespaces).isEmpty {
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
                                .frame(height: 30)
                                .background(AppColors.brand)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                }
            }
            
            // Trade Notes & Analysis Card
            cardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Text("Trade Notes & Analysis")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        Spacer()
                        Button("Save") {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            persistTradeUpdates()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    }
                    
                    ZStack(alignment: .topLeading) {
                        if noteContent.isEmpty {
                            Text("Document your trade thesis, emotions, entry trigger, or lessons learned...")
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
        }
    }
    
    // MARK: - 4. Media Tab View (Screenshots & Replay)
    private var mediaTabView: some View {
        VStack(spacing: 12) {
            // Interactive Trade Replay Launcher Banner
            cardContainer {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppColors.brand.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Trade Replay")
                            .font(AppTypography.subheadlineBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("Simulate price action bar-by-bar with entry, SL & TP markers.")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Button {
                        showReplayView = true
                    } label: {
                        Text("Replay")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(AppColors.brand)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            
            // Attachments & Screenshots
            cardContainer {
                AttachmentsSectionView(
                    ownerType: "trade",
                    ownerId: trade.key,
                    title: "Chart Screenshots & Documents"
                )
            }
        }
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
