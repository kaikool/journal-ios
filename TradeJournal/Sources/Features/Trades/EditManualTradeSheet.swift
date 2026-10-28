import SwiftUI

/// Sheet for editing any trade (manual or reconstructed) with full CRUD support
/// Standardized with Apple HIG and modular trade form components.
public struct EditManualTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public let trade: Trade
    public var onSave: ((Trade) -> Void)?
    
    @State private var symbol: String
    @State private var direction: TradeDirection
    @State private var isClosed: Bool
    @State private var quantityText: String
    @State private var entryPriceText: String
    @State private var exitPriceText: String
    @State private var openedAt: Date
    @State private var closedAt: Date
    @State private var feeText: String
    @State private var stopLossText: String
    @State private var profitTargetText: String
    @State private var selectedPlaybookId: String
    @State private var ruleAssessments: [String: Bool] = [:]
    @State private var rating: Int
    @State private var notes: String
    @State private var tags: [String]
    @State private var mistakes: [String]
    @State private var showCryptoSymbols: Bool = false
    @State private var errorMessage: String? = nil
    
    public init(trade: Trade, onSave: ((Trade) -> Void)? = nil) {
        self.trade = trade
        self.onSave = onSave
        
        _symbol = State(initialValue: trade.symbol)
        _direction = State(initialValue: trade.direction)
        _isClosed = State(initialValue: trade.closedAt != nil || trade.avgExit != nil)
        _quantityText = State(initialValue: Formatters.formatDecimalInput(trade.quantity, maxDecimals: 4))
        _entryPriceText = State(initialValue: Formatters.formatDecimalInput(trade.avgEntry, maxDecimals: 5))
        _exitPriceText = State(initialValue: Formatters.formatDecimalInput(trade.avgExit, maxDecimals: 5))
        _openedAt = State(initialValue: trade.openedAt)
        _closedAt = State(initialValue: trade.closedAt ?? trade.openedAt)
        _feeText = State(initialValue: Formatters.formatDecimalInput(trade.fees, maxDecimals: 2))
        _stopLossText = State(initialValue: Formatters.formatDecimalInput(trade.stopLoss, maxDecimals: 5))
        _profitTargetText = State(initialValue: Formatters.formatDecimalInput(trade.profitTarget, maxDecimals: 5))
        _selectedPlaybookId = State(initialValue: trade.playbookId ?? "")
        _rating = State(initialValue: trade.rating ?? 0)
        _notes = State(initialValue: trade.notes ?? "")
        _tags = State(initialValue: trade.tags)
        _mistakes = State(initialValue: trade.mistakes)
    }
    
    private var quantity: Decimal {
        Decimal(string: quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    
    private var entryPrice: Decimal {
        Decimal(string: entryPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    
    private var exitPrice: Decimal? {
        guard isClosed, !exitPriceText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: exitPriceText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var fee: Decimal {
        Decimal(string: feeText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    
    private var stopLoss: Decimal? {
        guard !stopLossText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: stopLossText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var profitTarget: Decimal? {
        guard !profitTargetText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: profitTargetText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var symbolSpec: AssetContractEngine.SymbolSpec {
        AssetContractEngine.spec(for: symbol)
    }
    
    private var isSyncedTrade: Bool {
        trade.accountId.hasPrefix("the5ers_") ||
        trade.accountId.hasPrefix("ctrader_") ||
        trade.key.hasPrefix("the5ers_") ||
        trade.key.hasPrefix("ctrader_") ||
        (dataStore.accounts.first(where: { $0.id == trade.accountId })?.kind == .sync)
    }
    
    private var accountName: String {
        dataStore.accounts.first(where: { $0.id == trade.accountId })?.name ??
        (trade.accountId.hasPrefix("the5ers_") ? "The5ers" : "Broker")
    }
    
    private var estimatedPnl: Decimal? {
        guard let exit = exitPrice, entryPrice > 0, quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exit,
            customMultiplier: AssetContractEngine.customMultiplier(for: symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return gross - fee
    }
    
    private var estimatedDeltaText: String? {
        guard let exit = exitPrice, entryPrice > 0 else { return nil }
        return AssetContractEngine.formatDeltaText(
            symbol: symbol,
            entryPrice: entryPrice,
            exitPrice: exit,
            direction: direction
        )
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
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
                    
                    Text("EDIT TRADE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        saveChanges()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isValid ? .white : AppColors.secondaryText.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isValid ? AppColors.brand : AppColors.secondaryBackground)
                            .clipShape(Capsule())
                    }
                    .disabled(!isValid)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColors.cardBackground)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Form Content
                ScrollView {
                    VStack(spacing: 14) {
                        if isSyncedTrade {
                            HStack(spacing: 10) {
                                Image(systemName: "link.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.brand)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Broker Synced Trade (\(accountName))")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(AppColors.primaryText)
                                    Text("Financial execution fills are managed by your broker. Targets, strategy, playbook, and journal notes are fully editable.")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(AppColors.brand.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.brand.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        // Section 1: Asset & Direction
                        assetAndDirectionCard
                            .disabled(isSyncedTrade)
                            .opacity(isSyncedTrade ? 0.75 : 1.0)
                        
                        // Section 2: Position & Pricing
                        positionAndPricingCard
                            .disabled(isSyncedTrade)
                            .opacity(isSyncedTrade ? 0.75 : 1.0)
                        
                        // Section 3: Execution Timestamps
                        TradeTimestampsCard(openedAt: $openedAt, closedAt: $closedAt, isClosed: isClosed)
                            .disabled(isSyncedTrade)
                            .opacity(isSyncedTrade ? 0.75 : 1.0)
                        
                        // Section 4: Risk & Playbook Checklist (Always Editable)
                        riskAndPlaybookCard
                        
                        // Section 5: Discipline & Notes (Always Editable)
                        TradeDisciplineAndNotesCard(
                            rating: $rating,
                            mistakes: $mistakes,
                            tags: $tags,
                            notes: $notes
                        )
                        
                        if let err = errorMessage {
                            Text(err)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.loss)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppColors.background)
            }
            .onAppear {
                loadExistingAssessments()
            }
        }
    }
    
    private func loadExistingAssessments() {
        for assessment in dataStore.playbookAssessments where assessment.tradeKey == trade.key {
            ruleAssessments[assessment.rule] = assessment.followed
        }
    }
    
    // MARK: - 1. Asset & Direction Card
    private var assetAndDirectionCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("ASSET & DIRECTION")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Direction Selector
                HStack(spacing: 8) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        direction = .long
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("BUY / LONG")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(direction == .long ? AppColors.brand : AppColors.secondaryBackground)
                        .foregroundColor(direction == .long ? .white : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        direction = .short
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("SELL / SHORT")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(direction == .short ? AppColors.loss : AppColors.secondaryBackground)
                        .foregroundColor(direction == .short ? .white : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                TradeSymbolSelector(symbol: $symbol, showCryptoSymbols: $showCryptoSymbols)
            }
        }
    }
    
    // MARK: - 2. Position & Pricing Card
    private var positionAndPricingCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("POSITION & PRICING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Toggle(isOn: $isClosed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trade is Closed")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                        Text(isClosed ? "Calculates realized net P&L and metrics" : "Tracked as an open position")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .tint(AppColors.brand)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TradeNumericInputBlock(
                        title: "Quantity / Lots",
                        subtitle: symbolSpec.lotDescription,
                        text: $quantityText,
                        placeholder: "0.25"
                    )
                    TradeNumericInputBlock(
                        title: "Entry Price",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $entryPriceText,
                        placeholder: symbolSpec.pricePlaceholder
                    )
                    if isClosed {
                        TradeNumericInputBlock(
                            title: "Exit Price",
                            subtitle: "\(symbolSpec.defaultDecimals) decimals",
                            text: $exitPriceText,
                            placeholder: symbolSpec.pricePlaceholder
                        )
                    }
                    TradeNumericInputBlock(
                        title: "Fees & Commission",
                        subtitle: "Total fees",
                        text: $feeText,
                        placeholder: "0.00"
                    )
                }
                
                TradeEstimatedPnlBanner(
                    estimatedPnl: estimatedPnl,
                    estimatedDeltaText: estimatedDeltaText,
                    symbolSpec: symbolSpec,
                    quantity: quantity,
                    reportingCurrency: env.currentCurrency
                )
            }
        }
    }
    
    // MARK: - 3. Risk & Playbook Card
    private var riskAndPlaybookCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("STRATEGY & PLAYBOOK")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TradeNumericInputBlock(
                        title: "Stop Loss (Price)",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $stopLossText,
                        placeholder: "Optional"
                    )
                    TradeNumericInputBlock(
                        title: "Profit Target (Price)",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $profitTargetText,
                        placeholder: "Optional"
                    )
                }
                
                TradePlaybookRulesCard(
                    selectedPlaybookId: $selectedPlaybookId,
                    ruleAssessments: $ruleAssessments,
                    playbooks: dataStore.playbooks
                )
            }
        }
    }
    
    // MARK: - Validation & Save
    private var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        quantity > 0 &&
        entryPrice > 0 &&
        (!isClosed || (exitPrice.map { $0 > 0 } ?? false))
    }
    
    private var hasExecutionParametersChanged: Bool {
        if isSyncedTrade { return false }
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        if trade.symbol != cleanSymbol { return true }
        if trade.direction != direction { return true }
        if trade.quantity != quantity { return true }
        if trade.avgEntry != entryPrice { return true }
        if trade.avgExit != (isClosed ? exitPrice : nil) { return true }
        if abs(trade.openedAt.timeIntervalSince(openedAt)) > 2 { return true }
        if trade.fees != fee { return true }
        if let origClose = trade.closedAt {
            if !isClosed { return true }
            if abs(origClose.timeIntervalSince(closedAt)) > 2 { return true }
        } else if isClosed {
            return true
        }
        return false
    }

    private func saveChanges() {
        guard isValid else {
            errorMessage = "Please enter valid symbol, quantity, and price."
            return
        }
        
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let trimmedNote = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = (trimmedNote.isEmpty || trimmedNote.hasPrefix("Position synced from")) ? nil : trimmedNote
        
        if hasExecutionParametersChanged {
            // Truly a manual trade whose financial fills were edited by the user
            dataStore.updateManualTrade(
                key: trade.key,
                symbol: cleanSymbol,
                direction: direction,
                quantity: quantity,
                entryPrice: entryPrice,
                exitPrice: isClosed ? exitPrice : nil,
                openedAt: openedAt,
                closedAt: isClosed ? closedAt : nil,
                fee: fee,
                notes: finalNotes,
                tags: tags,
                mistakes: mistakes,
                rating: rating > 0 ? rating : nil,
                stopLoss: stopLoss,
                profitTarget: profitTarget,
                playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId
            )
        } else {
            // Synced trade OR manual trade where only annotations/targets changed
            // Safely update annotations in-place WITHOUT touching executions or rebuilding account!
            dataStore.updateTradeAnnotations(
                key: trade.key,
                notes: finalNotes,
                tags: tags,
                mistakes: mistakes,
                stopLoss: stopLoss,
                profitTarget: profitTarget,
                rating: rating > 0 ? rating : nil,
                playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
                reviewedAt: Date()
            )
        }
        
        // Save rule assessments if playbook assigned
        if !selectedPlaybookId.isEmpty {
            for (rule, followed) in ruleAssessments {
                dataStore.setRuleAssessment(
                    tradeKey: trade.key,
                    playbookId: selectedPlaybookId,
                    rule: rule,
                    followed: followed
                )
            }
        }
        
        // Return updated trade (guaranteed matching key!)
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            onSave?(updated)
        }
        
        dismiss()
    }
}
