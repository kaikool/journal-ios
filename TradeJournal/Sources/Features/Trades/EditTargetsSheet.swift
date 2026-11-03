import SwiftUI

/// Dedicated, high-precision sheet for editing Stop Loss and Profit Target (Take Profit)
/// Provides real-time Risk / Reward (R:R) analytics, risk amount calculation, and 1-tap R presets.
/// Correctly distinguishes between initial downside stop loss, breakeven protection, and trailing profit lock.
/// Invariant: Directly updates trade annotations without mutating executions or account state.
public struct EditTargetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let trade: Trade
    var onSave: ((Trade) -> Void)?
    
    @State private var stopLossText: String
    @State private var profitTargetText: String
    @State private var errorMessage: String?
    
    public init(trade: Trade, onSave: ((Trade) -> Void)? = nil) {
        self.trade = trade
        self.onSave = onSave
        self._stopLossText = State(initialValue: Formatters.formatDecimalInput(trade.stopLoss, maxDecimals: 5))
        self._profitTargetText = State(initialValue: Formatters.formatDecimalInput(trade.profitTarget, maxDecimals: 5))
    }
    
    // MARK: - Computed Properties
    private var symbolSpec: AssetContractEngine.SymbolSpec {
        AssetContractEngine.spec(for: trade.symbol)
    }
    
    private var stopLoss: Decimal? {
        let clean = stopLossText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty, let val = Decimal(string: clean), val > 0 else { return nil }
        return val
    }
    
    private var profitTarget: Decimal? {
        let clean = profitTargetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty, let val = Decimal(string: clean), val > 0 else { return nil }
        return val
    }
    
    private var entryPrice: Decimal {
        trade.avgEntry
    }
    
    private var isStopLossInProfit: Bool {
        guard let sl = stopLoss, entryPrice > 0 else { return false }
        if trade.direction == .long {
            return sl > entryPrice
        } else {
            return sl < entryPrice
        }
    }
    
    private var isStopLossAtBreakeven: Bool {
        guard let sl = stopLoss, entryPrice > 0 else { return false }
        return abs(sl - entryPrice) <= Decimal(0.00001)
    }
    
    private var riskDistance: Decimal? {
        guard let sl = stopLoss, entryPrice > 0 else { return nil }
        if isStopLossInProfit || isStopLossAtBreakeven { return 0 }
        return abs(entryPrice - sl)
    }
    
    private var targetDistance: Decimal? {
        guard let tp = profitTarget, entryPrice > 0 else { return nil }
        return abs(tp - entryPrice)
    }
    
    private var activeVolume: Decimal {
        (trade.status == .open && trade.openQuantity > 0) ? trade.openQuantity : trade.quantity
    }
    
    private var riskAmount: Decimal? {
        guard let sl = stopLoss, entryPrice > 0, activeVolume > 0 else { return nil }
        if isStopLossInProfit || isStopLossAtBreakeven { return 0 }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: activeVolume,
            entryPrice: entryPrice,
            exitPrice: sl,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return abs(gross)
    }
    
    private var lockedProfitAmount: Decimal? {
        guard isStopLossInProfit, let sl = stopLoss, entryPrice > 0, activeVolume > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: activeVolume,
            entryPrice: entryPrice,
            exitPrice: sl,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return max(0, gross)
    }
    
    private var targetAmount: Decimal? {
        guard let tp = profitTarget, entryPrice > 0, activeVolume > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: activeVolume,
            entryPrice: entryPrice,
            exitPrice: tp,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return max(0, gross)
    }
    
    private var plannedR: Decimal? {
        if isStopLossInProfit || isStopLossAtBreakeven { return nil }
        guard let rDist = riskDistance, let tDist = targetDistance, rDist > 0 else { return nil }
        return tDist / rDist
    }
    
    private var isProfitTargetValidDirection: Bool {
        guard let tp = profitTarget else { return true }
        if trade.direction == .long {
            return tp > entryPrice
        } else {
            return tp < entryPrice
        }
    }
    
    // MARK: - Body
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    tradeSummaryCard
                    
                    stopLossCard
                    
                    profitTargetCard
                    
                    rrAnalysisCard
                }
                .padding(16)
            }
            .background(AppColors.background)
            .navigationTitle("Edit Targets (R:R)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save") {
                        saveTargets()
                    }
                }
            }
        }
    }
    
    // MARK: - 1. Trade Summary Card
    private var tradeSummaryCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(AppTypography.rowPrimary)
                            .foregroundColor(AppColors.primaryText)
                        
                        AppBadge(
                            trade.direction.rawValue.uppercased(),
                            variant: trade.direction == .long ? .profit : .loss
                        )
                    }
                    
                    Spacer()
                    
                    AppBadge(
                        trade.status == .open ? "ACTIVE TRADE" : "CLOSED TRADE",
                        variant: trade.status == .open ? .profit : .secondary
                    )
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry Price")
                            .font(AppTypography.statLabel)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(entryPrice, symbol: trade.symbol))
                            .font(AppTypography.statValue)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(trade.isPartiallyClosed ? "Active Volume" : "Volume")
                            .font(AppTypography.statLabel)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(Formatters.formatDecimal(activeVolume, maxDecimals: 3)) lots")
                            .font(AppTypography.statValue)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                if trade.isPartiallyClosed {
                    Divider().background(AppColors.border.opacity(0.4))
                    HStack {
                        Text("Banked Realized Profit")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(trade.netPnl))
                    }
                }
            }
        }
    }
    
    // MARK: - 2. Stop Loss Card
    private var stopLossCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: isStopLossInProfit ? "shield.lefthalf.filled.badge.checkmark" : (isStopLossAtBreakeven ? "shield.checkmark.fill" : "shield.slash.fill"))
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(isStopLossInProfit ? AppColors.profit : (isStopLossAtBreakeven ? AppColors.brand : AppColors.loss))
                    Text(isStopLossInProfit ? "STOP LOSS (TRAILING PROFIT LOCK)" : (isStopLossAtBreakeven ? "STOP LOSS (BREAKEVEN)" : "STOP LOSS (RISK)"))
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if stopLoss != nil {
                        ModalCloseButton(action: { stopLossText = "" })
                    }
                }
                
                TradeNumericInputBlock(
                    title: "Stop Loss Price",
                    subtitle: "\(symbolSpec.defaultDecimals) decimals",
                    text: $stopLossText,
                    placeholder: "e.g. \(Formatters.formatDecimal(entryPrice * 0.99, maxDecimals: symbolSpec.defaultDecimals))"
                )
                
                if isStopLossInProfit {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Locked Profit")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            Text(lockedProfitAmount.map { "+\(Formatters.formatCurrency($0, currency: env.currentCurrency))" } ?? "–")
                                .font(AppTypography.statValueMedium)
                                .foregroundColor(AppColors.profit)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Capital at Risk")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            Text("$0.00 (Risk-Free)")
                                .font(AppTypography.statValue)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                    .appSubCardStyle(cornerRadius: 8, padding: 10)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.profit)
                        Text("Trailing Stop: Stop Loss is above entry (Buy) / below entry (Sell). Guaranteed profit locked in!")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.profit)
                    }
                } else if isStopLossAtBreakeven {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop Mode")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            Text("Breakeven")
                                .font(AppTypography.statValueMedium)
                                .foregroundColor(AppColors.brand)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Capital at Risk")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            Text("$0.00 (Risk-Free)")
                                .font(AppTypography.statValue)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                    .appSubCardStyle(cornerRadius: 8, padding: 10)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkmark.fill")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.brand)
                        Text("Breakeven Stop: Position is 100% protected against capital downside.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.brand)
                    }
                } else if let rAmt = riskAmount, let rDist = riskDistance {
                    if trade.isPartiallyClosed && trade.status == .open {
                        if trade.netPnl >= rAmt {
                            let netOutcome = trade.netPnl - rAmt
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Capital at Risk")
                                        .font(AppTypography.statLabel)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("$0.00 (Risk-Free)")
                                        .font(AppTypography.statValue)
                                        .foregroundColor(AppColors.profit)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Net Outcome on SL")
                                        .font(AppTypography.statLabel)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("+\(Formatters.formatCurrency(netOutcome, currency: env.currentCurrency))")
                                        .font(AppTypography.statValueMedium)
                                        .foregroundColor(AppColors.profit)
                                }
                            }
                            .appSubCardStyle(cornerRadius: 8, padding: 10)
                        } else {
                            let netRisk = rAmt - trade.netPnl
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Net Risk at Stake")
                                        .font(AppTypography.statLabel)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("-\(Formatters.formatCurrency(netRisk, currency: env.currentCurrency))")
                                        .font(AppTypography.statValue)
                                        .foregroundColor(AppColors.loss)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Active SL Loss")
                                        .font(AppTypography.statLabel)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("-\(Formatters.formatCurrency(rAmt, currency: env.currentCurrency))")
                                        .font(AppTypography.statValueMedium)
                                        .foregroundColor(AppColors.loss)
                                }
                            }
                            .appSubCardStyle(cornerRadius: 8, padding: 10)
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Risk Distance")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(Formatters.formatDecimal(rDist, maxDecimals: symbolSpec.defaultDecimals)) pts")
                                    .font(AppTypography.statValueMedium)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Risk at Stake (1R)")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("-\(Formatters.formatCurrency(rAmt, currency: env.currentCurrency))")
                                    .font(AppTypography.statValue)
                                    .foregroundColor(AppColors.loss)
                            }
                        }
                        .appSubCardStyle(cornerRadius: 8, padding: 10)
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Profit Target Card
    private var profitTargetCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "target")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.profit)
                    Text("PROFIT TARGET (REWARD)")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if profitTarget != nil {
                        ModalCloseButton(action: { profitTargetText = "" })
                    }
                }
                
                TradeNumericInputBlock(
                    title: "Take Profit Price",
                    subtitle: "\(symbolSpec.defaultDecimals) decimals",
                    text: $profitTargetText,
                    placeholder: "e.g. \(Formatters.formatDecimal(entryPrice * 1.02, maxDecimals: symbolSpec.defaultDecimals))"
                )
                
                if let tAmt = targetAmount, let tDist = targetDistance {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target Distance")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            Text("\(Formatters.formatDecimal(tDist, maxDecimals: symbolSpec.defaultDecimals)) pts")
                                .font(AppTypography.statValueMedium)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(trade.isPartiallyClosed ? "Total Potential" : "Planned Reward")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                            let totalTarget = trade.isPartiallyClosed ? (trade.netPnl + tAmt) : tAmt
                            Text("+\(Formatters.formatCurrency(totalTarget, currency: env.currentCurrency))")
                                .font(AppTypography.statValue)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                    .appSubCardStyle(cornerRadius: 8, padding: 10)
                }
                
                if !isProfitTargetValidDirection {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.warning)
                        Text(trade.direction == .long ? "Profit target should be above entry price for Buy trades." : "Profit target should be below entry price for Sell trades.")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.warning)
                    }
                }
                
                // Quick R Presets (Only applicable when Stop Loss defines a downside risk distance)
                if !isStopLossInProfit && !isStopLossAtBreakeven, let rDist = riskDistance, rDist > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUICK TARGET PRESETS")
                            .font(AppTypography.cardHeaderUppercase)
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                        
                        HStack(spacing: 8) {
                            presetButton(ratio: 1.0, title: "1.0 R")
                            presetButton(ratio: 1.5, title: "1.5 R")
                            presetButton(ratio: 2.0, title: "2.0 R")
                            presetButton(ratio: 3.0, title: "3.0 R")
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private func presetButton(ratio: Decimal, title: String) -> some View {
        AppFilterChip(title, isSelected: true, height: 32) {
            applyRPreset(ratio: ratio)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func applyRPreset(ratio: Decimal) {
        guard let rDist = riskDistance, rDist > 0 else { return }
        let targetDist = rDist * ratio
        let calculatedPrice: Decimal = (trade.direction == .long) ? (entryPrice + targetDist) : (entryPrice - targetDist)
        profitTargetText = Formatters.formatDecimalInput(calculatedPrice, maxDecimals: symbolSpec.defaultDecimals)
    }
    
    // MARK: - 4. Risk / Reward Analysis
    private var rrAnalysisCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PLANNED RISK / REWARD")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if isStopLossInProfit {
                        Text("Risk-Free (Locked Profit)")
                            .font(AppTypography.statValueMedium)
                            .foregroundColor(AppColors.profit)
                    } else if isStopLossAtBreakeven {
                        Text("Risk-Free (Breakeven)")
                            .font(AppTypography.statValueMedium)
                            .foregroundColor(AppColors.brand)
                    } else if let pR = plannedR {
                        let plannedVal = (pR as NSDecimalNumber).doubleValue
                        Text(String(format: "1 : %.2f R", plannedVal))
                            .font(AppTypography.displayMedium)
                            .foregroundColor(plannedVal >= 1.5 ? AppColors.profit : (plannedVal >= 1.0 ? AppColors.brand : .orange))
                    } else {
                        Text("Set SL & TP to calculate")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                if isStopLossInProfit || isStopLossAtBreakeven {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(AppColors.profit.opacity(0.85))
                            .frame(height: 6)
                        
                        HStack {
                            Text("Capital Risk: $0.00 (Risk-Free)")
                                .font(AppTypography.badgeStandard)
                                .foregroundColor(AppColors.profit)
                            Spacer()
                            if let tAmt = targetAmount {
                                Text("Potential: +\(Formatters.formatCurrency(tAmt, currency: env.currentCurrency))")
                                    .font(AppTypography.badgeStandard)
                                    .foregroundColor(AppColors.profit)
                            } else {
                                Text(isStopLossInProfit ? "Locked Profit Runner" : "Breakeven Protected")
                                    .font(AppTypography.badgeStandard)
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                    }
                } else if let pR = plannedR {
                    let plannedVal = max(0.1, (pR as NSDecimalNumber).doubleValue)
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                Capsule()
                                    .fill(AppColors.loss.opacity(0.85))
                                    .frame(width: max(28, geo.size.width * CGFloat(1.0 / (1.0 + plannedVal))))
                                Capsule()
                                    .fill(AppColors.profit.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 6)
                        
                        HStack {
                            Text("1R Risk")
                                .font(AppTypography.badgeStandard)
                                .foregroundColor(AppColors.loss)
                            Spacer()
                            Text("\(Formatters.formatDecimal(Decimal(plannedVal), maxDecimals: 1))R Reward")
                                .font(AppTypography.badgeStandard)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Save
    private func saveTargets() {
        dataStore.updateTradeAnnotations(
            key: trade.key,
            notes: trade.notes,
            tags: trade.tags,
            mistakes: trade.mistakes,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            rating: trade.rating,
            playbookId: trade.playbookId,
            reviewedAt: Date()
        )
        
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            onSave?(updated)
        }
        
        dismiss()
    }
}
