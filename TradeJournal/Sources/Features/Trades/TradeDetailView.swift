import SwiftUI

/// Trade detail view matching 100% of `source-repo/apps/web/src/app/trades/[key]/page.tsx`
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
    
    public init(trade: Trade, isModal: Bool = false) {
        self.isModal = isModal
        self._trade = State(initialValue: trade)
        self._noteContent = State(initialValue: trade.notes ?? "")
        self._stopLossText = State(initialValue: Formatters.formatDecimalInput(trade.stopLoss, maxDecimals: 5))
        self._profitTargetText = State(initialValue: Formatters.formatDecimalInput(trade.profitTarget, maxDecimals: 5))
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
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header PnL Card
                    cardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
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
                                
                                Spacer()
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Net P&L")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    AppMonetaryText(
                                        Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                                        isPrivate: env.isPrivacyModeEnabled,
                                        font: AppTypography.financialNumber(size: 26, weight: .bold),
                                        color: Formatters.pnlColor(trade.netPnl)
                                    )
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("Volume")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(trade.quantity)")
                                        .font(AppTypography.financialNumber(size: 22, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                            
                            // Visual Financial Breakdown (Gross - Fees = Net)
                            VStack(spacing: 8) {
                                HStack {
                                    Text("FINANCIAL BREAKDOWN")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text("Gross - Fees = Net")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                                
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Gross P&L")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Spacer()
                                        AppMonetaryText(
                                            Formatters.formatPnL(trade.grossPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.subheadlineBold,
                                            color: Formatters.pnlColor(trade.grossPnl)
                                        )
                                        .lineLimit(1)
                                    }
                                    
                                    HStack {
                                        Text("Fees & Costs")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Spacer()
                                        Text(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))
                                            .font(AppTypography.subheadlineBold)
                                            .monospacedDigit()
                                            .foregroundColor(trade.fees > 0 ? AppColors.warning : AppColors.primaryText)
                                            .lineLimit(1)
                                    }
                                    
                                    Divider().background(AppColors.border.opacity(0.4))
                                    
                                    HStack {
                                        Text("Net Realized P&L")
                                            .font(AppTypography.captionBold)
                                            .foregroundColor(AppColors.primaryText)
                                        Spacer()
                                        AppMonetaryText(
                                            Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.subheadlineBold,
                                            color: Formatters.pnlColor(trade.netPnl)
                                        )
                                        .lineLimit(1)
                                    }
                                }
                                .padding(12)
                                .background(AppColors.secondaryBackground.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                    
                    // Pricing & Execution Details
                    cardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Execution Details")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Avg entry")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.price(trade.avgEntry))
                                        .font(AppTypography.subheadlineBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 3) {
                                    Text("Avg exit")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(trade.avgExit.map(Formatters.price) ?? "Open")
                                        .font(AppTypography.subheadlineBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 3) {
                                    Text("Gross P&L")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    AppMonetaryText(
                                        Formatters.formatPnL(trade.grossPnl, currency: env.currentCurrency),
                                        isPrivate: env.isPrivacyModeEnabled,
                                        font: AppTypography.subheadlineBold,
                                        color: Formatters.pnlColor(trade.grossPnl)
                                    )
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("Fees")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))
                                        .font(AppTypography.subheadlineBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack {
                                Text("Opened at:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                                    .font(AppTypography.caption)
                                    .monospacedDigit()
                                    .foregroundColor(AppColors.primaryText)
                            }
                            
                            if let closedAt = trade.closedAt {
                                HStack {
                                    Text("Closed at:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(Formatters.formatDateTime(closedAt, timeZone: env.currentTimeZone))
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                        }
                    }
                    
                    // Execution Legs List
                    if !fills.isEmpty {
                        cardContainer {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "arrow.triangle.swap")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text("Executions (\(fills.count) legs)")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
                                
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
                                            .font(AppTypography.captionBold)
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.primaryText)
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(Formatters.formatCurrency(fill.fee, currency: env.currentCurrency))
                                                .font(AppTypography.caption)
                                                .monospacedDigit()
                                                .foregroundColor(AppColors.secondaryText)
                                            Text(Formatters.formatDateTime(fill.executedAt, timeZone: env.currentTimeZone))
                                                .font(.system(size: 9))
                                                .monospacedDigit()
                                                .foregroundColor(AppColors.secondaryText)
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
                    
                    // Risk & Reward Section
                    cardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.brand)
                                Text("Risk & Reward (R:R)")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            
                            HStack(alignment: .bottom, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stop Loss")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    TextField("Not set", text: $stopLossText)
                                        .font(AppTypography.body)
                                        .monospacedDigit()
                                        .padding(.horizontal, 10)
                                        .frame(height: 38)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .keyboardType(.decimalPad)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Profit Target")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    TextField("Not set", text: $profitTargetText)
                                        .font(AppTypography.body)
                                        .monospacedDigit()
                                        .padding(.horizontal, 10)
                                        .frame(height: 38)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .keyboardType(.decimalPad)
                                }
                                
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    persistTradeUpdates()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Save")
                                            .font(AppTypography.captionBold)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(AppColors.brand)
                                    .foregroundColor(AppColors.brandTextOnDark)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(color: AppColors.brand.opacity(0.25), radius: 3, x: 0, y: 1.5)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                                .fixedSize()
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack(spacing: 18) {
                                if let risk = riskAmount {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Risk (1R):")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(Formatters.formatCurrency(risk, currency: env.currentCurrency))
                                            .font(AppTypography.captionBold)
                                            .monospacedDigit()
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
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.brand)
                                    }
                                }
                                if let rR = realizedR {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Realized R:")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(String(format: "%.2fR", (rR as NSDecimalNumber).doubleValue))
                                            .font(AppTypography.captionBold)
                                            .monospacedDigit()
                                            .foregroundColor(rR >= 0 ? AppColors.profit : AppColors.loss)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Playbook Checklist
                    cardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "book.pages")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text("Playbook")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
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
                                    Text("Rule Checklist:")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.secondaryText)
                                    
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
                                                    .font(.system(size: 16))
                                                Text(rule)
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(AppColors.primaryText)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Annotations: Mistakes, Tags & Rating
                    cardContainer {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "flame")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.brand)
                                Text("Discipline & Execution Review")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            
                            // Rating
                            HStack(spacing: 8) {
                                Text("Rating:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= (trade.rating ?? 0) ? "star.fill" : "star")
                                        .foregroundColor(star <= (trade.rating ?? 0) ? .yellow : AppColors.secondaryText.opacity(0.4))
                                        .font(.system(size: 16))
                                        .onTapGesture {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            trade.rating = (trade.rating == star) ? nil : star
                                            persistTradeUpdates()
                                        }
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            // Tags
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tags:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                if !trade.tags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(trade.tags, id: \.self) { tag in
                                                HStack(spacing: 4) {
                                                    Text("#\(tag)")
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 8, weight: .bold))
                                                }
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(AppColors.brand)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppColors.brand.opacity(0.12))
                                                .clipShape(Capsule())
                                                .onTapGesture {
                                                    #if canImport(UIKit)
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    #endif
                                                    trade.tags.removeAll { $0 == tag }
                                                    persistTradeUpdates()
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    TextField("Add tag...", text: $newTag)
                                        .font(AppTypography.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        let clean = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                                        if !clean.isEmpty && !trade.tags.contains(clean) {
                                            trade.tags.append(clean)
                                            newTag = ""
                                            persistTradeUpdates()
                                        }
                                    } label: {
                                        Text("Add")
                                            .font(AppTypography.captionBold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(AppColors.brand)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            // Mistakes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Mistakes:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                if !trade.mistakes.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(trade.mistakes, id: \.self) { mistake in
                                                HStack(spacing: 4) {
                                                    Text("⚠️ \(mistake)")
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 8, weight: .bold))
                                                }
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(AppColors.loss)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AppColors.loss.opacity(0.12))
                                                .clipShape(Capsule())
                                                .onTapGesture {
                                                    #if canImport(UIKit)
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    #endif
                                                    trade.mistakes.removeAll { $0 == mistake }
                                                    persistTradeUpdates()
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    TextField("e.g. FOMO, Moved SL...", text: $newMistake)
                                        .font(AppTypography.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        let clean = newMistake.trimmingCharacters(in: .whitespaces)
                                        if !clean.isEmpty && !trade.mistakes.contains(clean) {
                                            trade.mistakes.append(clean)
                                            newMistake = ""
                                            persistTradeUpdates()
                                        }
                                    } label: {
                                        Text("Add")
                                            .font(AppTypography.captionBold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(AppColors.loss)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                    }
                    
                    // Notes Section (TextEditor with persistent save)
                    cardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "note.text")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.brand)
                                Text("Trade Notes & Analysis")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                                Spacer()
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    persistTradeUpdates()
                                } label: {
                                    Text("Save notes")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.brand)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                            
                            TextEditor(text: $noteContent)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                                    )
                        }
                    }
                    
                    // Attachments & Screenshots
                    cardContainer {
                        AttachmentsSectionView(
                            ownerType: "trade",
                            ownerId: trade.key,
                            title: "Attachments & Screenshots"
                        )
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
                            Text("Delete trade")
                        }
                        .font(AppTypography.captionBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.loss.opacity(0.12))
                        .foregroundColor(AppColors.loss)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
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
        .interactiveEdgeBack(onBack: { dismiss() })
        .enableNativePopGesture()
        .fullScreenCover(isPresented: $showReplayView) {
            TradeReplayView(trade: trade, executions: fills)
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
                self.noteContent = updated.notes ?? ""
                self.stopLossText = Formatters.formatDecimalInput(updated.stopLoss, maxDecimals: 5)
                self.profitTargetText = Formatters.formatDecimalInput(updated.profitTarget, maxDecimals: 5)
                self.selectedPlaybookId = updated.playbookId ?? ""
            }
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
