import SwiftUI

/// Dedicated, high-precision sheet for editing Stop Loss and Profit Target (Take Profit)
/// Provides real-time Risk / Reward (R:R) analytics, risk amount calculation, and 1-tap R presets.
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
    
    private var riskDistance: Decimal? {
        guard let sl = stopLoss, entryPrice > 0 else { return nil }
        return abs(entryPrice - sl)
    }
    
    private var targetDistance: Decimal? {
        guard let tp = profitTarget, entryPrice > 0 else { return nil }
        return abs(tp - entryPrice)
    }
    
    private var riskAmount: Decimal? {
        guard let sl = stopLoss, entryPrice > 0, trade.quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: trade.quantity,
            entryPrice: entryPrice,
            exitPrice: sl,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return abs(gross)
    }
    
    private var targetAmount: Decimal? {
        guard let tp = profitTarget, entryPrice > 0, trade.quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: trade.quantity,
            entryPrice: entryPrice,
            exitPrice: tp,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return max(0, gross)
    }
    
    private var plannedR: Decimal? {
        guard let rDist = riskDistance, let tDist = targetDistance, rDist > 0 else { return nil }
        return tDist / rDist
    }
    
    private var isStopLossValidDirection: Bool {
        guard let sl = stopLoss else { return true }
        if trade.direction == .long {
            return sl < entryPrice
        } else {
            return sl > entryPrice
        }
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
            VStack(spacing: 0) {
                headerBar
                
                Divider().background(AppColors.border.opacity(0.5))
                
                ScrollView {
                    VStack(spacing: 14) {
                        tradeSummaryCard
                        
                        stopLossCard
                        
                        profitTargetCard
                        
                        rrAnalysisCard
                    }
                    .padding(16)
                }
            }
            .background(AppColors.background)
        }
    }
    
    // MARK: - Header
    private var headerBar: some View {
        HStack(alignment: .center) {
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dismiss()
            } label: {
                Text("Cancel")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            Text("EDIT TARGETS (R:R)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .tracking(0.5)
            
            Spacer()
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                saveTargets()
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(AppColors.brand)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
    }
    
    // MARK: - 1. Trade Summary Card
    private var tradeSummaryCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(trade.direction.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(trade.direction == .long ? AppColors.profit.opacity(0.15) : AppColors.loss.opacity(0.15))
                            .foregroundColor(trade.direction == .long ? AppColors.profit : AppColors.loss)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                    
                    Text(trade.status == .open ? "ACTIVE TRADE" : "CLOSED TRADE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trade.status == .open ? AppColors.profit : AppColors.secondaryText)
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry Price")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(entryPrice))
                            .font(AppTypography.number(14, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Volume")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(Formatters.formatDecimal(trade.quantity, maxDecimals: 3)) lots")
                            .font(AppTypography.number(14, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
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
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.loss)
                    Text("STOP LOSS (RISK)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if stopLoss != nil {
                        Button {
                            stopLossText = ""
                        } label: {
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                TradeNumericInputBlock(
                    title: "Stop Loss Price",
                    subtitle: "\(symbolSpec.defaultDecimals) decimals",
                    text: $stopLossText,
                    placeholder: "e.g. \(Formatters.formatDecimal(entryPrice * 0.99, maxDecimals: symbolSpec.defaultDecimals))"
                )
                
                if let rAmt = riskAmount, let rDist = riskDistance {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Risk Distance")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text("\(Formatters.formatDecimal(rDist, maxDecimals: symbolSpec.defaultDecimals)) pts")
                                .font(AppTypography.number(12, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Risk at Stake (1R)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text("-\(Formatters.formatCurrency(rAmt, currency: env.currentCurrency))")
                                .font(AppTypography.number(13, weight: .bold))
                                .foregroundColor(AppColors.loss)
                        }
                    }
                    .padding(10)
                    .background(AppColors.loss.opacity(0.08))
                    .cornerRadius(8)
                }
                
                if !isStopLossValidDirection {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(trade.direction == .long ? "Stop loss should be below entry price for Buy trades." : "Stop loss should be above entry price for Sell trades.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.profit)
                    Text("PROFIT TARGET (REWARD)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if profitTarget != nil {
                        Button {
                            profitTargetText = ""
                        } label: {
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
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
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text("\(Formatters.formatDecimal(tDist, maxDecimals: symbolSpec.defaultDecimals)) pts")
                                .font(AppTypography.number(12, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Planned Reward")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text("+\(Formatters.formatCurrency(tAmt, currency: env.currentCurrency))")
                                .font(AppTypography.number(13, weight: .bold))
                                .foregroundColor(AppColors.profit)
                        }
                    }
                    .padding(10)
                    .background(AppColors.profit.opacity(0.08))
                    .cornerRadius(8)
                }
                
                if !isProfitTargetValidDirection {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(trade.direction == .long ? "Profit target should be above entry price for Buy trades." : "Profit target should be below entry price for Sell trades.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                
                // Quick R Presets (Based on Stop Loss distance)
                if let rDist = riskDistance, rDist > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUICK TARGET PRESETS")
                            .font(.system(size: 10, weight: .bold))
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
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            applyRPreset(ratio: ratio)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(AppColors.brand.opacity(0.12))
                .cornerRadius(6)
        }
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    if let pR = plannedR {
                        let plannedVal = (pR as NSDecimalNumber).doubleValue
                        Text(String(format: "1 : %.2f R", plannedVal))
                            .font(AppTypography.number(14, weight: .bold))
                            .foregroundColor(plannedVal >= 1.5 ? AppColors.profit : (plannedVal >= 1.0 ? AppColors.brand : .orange))
                    } else {
                        Text("Set SL & TP to calculate")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                if let pR = plannedR {
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
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.loss)
                            Spacer()
                            Text(String(format: "%.1fR Reward", plannedVal))
                                .font(.system(size: 10, weight: .semibold))
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
