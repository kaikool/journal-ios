import SwiftUI

/// Manual trade entry sheet
/// Built with Apple HIG standards and modular trade form components:
/// - Clean card-based structure (TradeFormCardContainer)
/// - Prioritizes Forex pairs & Gold (XAUUSD) first, with Crypto/Indices option
/// - Interactive Playbook rule checklist directly inside Add Trade
/// - Custom Apple HIG direction selector (BUY / LONG & SELL / SHORT)
/// - Modern inline date & time pickers with quick presets
/// - Live estimated Net P&L calculation banner
public struct AddTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var accountId: String = ""
    @State private var symbol: String = ""
    @State private var direction: TradeDirection = .long
    @State private var isClosed: Bool = true
    @State private var quantityText: String = "1"
    @State private var entryPriceText: String = ""
    @State private var exitPriceText: String = ""
    @State private var openedAt: Date = Date()
    @State private var closedAt: Date = Date()
    @State private var feeText: String = "0"
    @State private var stopLossText: String = ""
    @State private var profitTargetText: String = ""
    @State private var selectedPlaybookId: String = ""
    @State private var ruleAssessments: [String: Bool] = [:]
    @State private var rating: Int = 0
    @State private var notes: String = ""
    @State private var tags: [String] = []
    @State private var mistakes: [String] = []
    @State private var showCryptoSymbols: Bool = false
    @State private var errorMessage: String? = nil
    
    public init(initialDate: Date = Date()) {
        _openedAt = State(initialValue: initialDate)
        _closedAt = State(initialValue: initialDate)
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
                // Custom Navigation Header
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
                    
                    Text("ADD TRADE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        saveTrade()
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
                        // Section 1: Account & Symbol
                        accountAndSymbolCard
                        
                        // Section 2: Position & Pricing
                        positionAndPricingCard
                        
                        // Section 3: Execution Timestamps
                        TradeTimestampsCard(openedAt: $openedAt, closedAt: $closedAt, isClosed: isClosed)
                        
                        // Section 4: Risk & Playbook Checklist
                        riskAndPlaybookCard
                        
                        // Section 5: Discipline & Journal Notes
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
                if accountId.isEmpty {
                    accountId = dataStore.selectedAccountId == "all"
                        ? (dataStore.accounts.first?.id ?? "")
                        : dataStore.selectedAccountId
                }
                if selectedPlaybookId.isEmpty, let defId = dataStore.defaultPlaybook?.id {
                    selectedPlaybookId = defId
                }
            }
        }
    }
    
    // MARK: - 1. Account & Symbol Card
    private var accountAndSymbolCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCOUNT & INSTRUMENT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                let accountOptions = dataStore.accounts.map { $0.id }
                AppDropdownField(
                    label: "Account",
                    selection: $accountId,
                    options: accountOptions,
                    titleFor: { id in
                        if let acc = dataStore.accounts.first(where: { $0.id == id }) {
                            return "\(acc.name) (\(acc.currency))"
                        }
                        return id
                    },
                    iconFor: { _ in "creditcard" }
                )
                
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
                
                // Direction Selector
                HStack(spacing: 8) {
                    Button {
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        direction = .long
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("BUY / LONG")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(direction == .long ? AppColors.profit : AppColors.secondaryBackground)
                        .foregroundColor(direction == .long ? .white : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        direction = .short
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("SELL / SHORT")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(direction == .short ? AppColors.loss : AppColors.secondaryBackground)
                        .foregroundColor(direction == .short ? .white : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // Closed Position Toggle
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
                
                // Numeric Fields Grid
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
                
                // Live Estimated P&L Banner
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
    
    private func saveTrade() {
        guard isValid else {
            errorMessage = "Please enter valid symbol, quantity, and price."
            return
        }
        
        let targetAccId = accountId.isEmpty ? dataStore.selectedAccountId : accountId
        
        dataStore.addManualTrade(
            accountId: targetAccId,
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: isClosed ? exitPrice : nil,
            openedAt: openedAt,
            closedAt: isClosed ? closedAt : nil,
            fee: fee,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            tags: tags,
            mistakes: mistakes,
            rating: rating > 0 ? rating : nil,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            ruleAssessments: ruleAssessments
        )
        
        dismiss()
    }
}
