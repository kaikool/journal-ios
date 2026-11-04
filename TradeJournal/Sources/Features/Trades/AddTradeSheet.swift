import SwiftUI

/// Manual trade entry sheet
/// Built with Apple HIG standards and modular trade form components:
/// - Clean card-based structure (TradeFormCardContainer)
/// - Prioritizes Forex pairs & Gold (XAUUSD) first, with Crypto/Indices option
/// - Interactive Playbook rule checklist directly inside Add Trade
/// - Custom Apple HIG direction selector (BUY / LONG & SELL / SHORT)
/// - Modern inline date & time pickers with quick presets
/// - Live estimated Net P&L calculation banner
/// - MVVM ViewModel Architecture (AddTradeViewModel)
public struct AddTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @StateObject private var viewModel: AddTradeViewModel
    
    public init(initialDate: Date = Date()) {
        _viewModel = StateObject(wrappedValue: AddTradeViewModel(initialDate: initialDate))
    }
    
    private var quantity: Decimal { viewModel.quantity }
    private var entryPrice: Decimal { viewModel.entryPrice }
    private var exitPrice: Decimal? { viewModel.exitPrice }
    private var fee: Decimal { viewModel.fee }
    private var stopLoss: Decimal? { viewModel.stopLoss }
    private var profitTarget: Decimal? { viewModel.profitTarget }
    private var symbolSpec: AssetContractEngine.SymbolSpec { viewModel.symbolSpec }
    private var estimatedPnl: Decimal? { viewModel.estimatedPnl(dataStore: dataStore) }
    private var estimatedDeltaText: String? { viewModel.estimatedDeltaText }
    private var isValid: Bool { viewModel.isValid }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Section 1: Account & Symbol
                    accountAndSymbolCard
                    
                    // Section 2: Position & Pricing
                    positionAndPricingCard
                    
                    // Section 3: Execution Timestamps
                    TradeTimestampsCard(
                        openedAt: $viewModel.openedAt,
                        closedAt: $viewModel.closedAt,
                        isClosed: viewModel.isClosed
                    )
                    
                    // Section 4: Risk & Playbook Checklist
                    riskAndPlaybookCard
                    
                    // Section 5: Discipline & Journal Notes
                    TradeDisciplineAndNotesCard(
                        rating: $viewModel.rating,
                        mistakes: $viewModel.mistakes,
                        tags: $viewModel.tags,
                        notes: $viewModel.notes
                    )
                    
                    if let err = viewModel.errorMessage {
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
            .navigationTitle("New Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save", isEnabled: isValid) {
                        viewModel.saveTrade(dataStore: dataStore) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if viewModel.accountId.isEmpty {
                    viewModel.accountId = dataStore.selectedAccountId == "all"
                        ? (dataStore.accounts.first?.id ?? "")
                        : dataStore.selectedAccountId
                }
                if viewModel.selectedPlaybookId.isEmpty, let defId = dataStore.defaultPlaybook?.id {
                    viewModel.selectedPlaybookId = defId
                }
            }
        }
    }
    
    // MARK: - 1. Account & Symbol Card
    private var accountAndSymbolCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCOUNT & INSTRUMENT")
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                let accountOptions = dataStore.accounts.map { $0.id }
                AppDropdownField(
                    label: "Account",
                    selection: $viewModel.accountId,
                    options: accountOptions,
                    titleFor: { id in
                        if let acc = dataStore.accounts.first(where: { $0.id == id }) {
                            return "\(acc.name) (\(acc.currency))"
                        }
                        return id
                    },
                    iconFor: { _ in "creditcard" }
                )
                
                TradeSymbolSelector(
                    symbol: $viewModel.symbol,
                    showCryptoSymbols: $viewModel.showCryptoSymbols
                )
            }
        }
    }
    
    // MARK: - 2. Position & Pricing Card
    private var positionAndPricingCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("POSITION & PRICING")
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Direction Selector
                AppBinarySegmentedToggle(
                    selection: $viewModel.direction,
                    firstOption: .long,
                    firstTitle: "BUY / LONG",
                    firstIcon: "arrow.up.right",
                    firstActiveColor: AppColors.profit,
                    secondOption: .short,
                    secondTitle: "SELL / SHORT",
                    secondIcon: "arrow.down.right",
                    secondActiveColor: AppColors.loss
                )
                
                // Closed Position Toggle
                AppToggleRow(
                    "Trade is Closed",
                    subtitle: viewModel.isClosed ? "Calculates realized net P&L and metrics" : "Tracked as an open position",
                    isOn: $viewModel.isClosed
                )
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Numeric Fields Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TradeNumericInputBlock(
                        title: "Quantity / Lots",
                        subtitle: symbolSpec.lotDescription,
                        text: $viewModel.quantityText,
                        placeholder: "0.25"
                    )
                    TradeNumericInputBlock(
                        title: "Entry Price",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $viewModel.entryPriceText,
                        placeholder: symbolSpec.pricePlaceholder
                    )
                    if viewModel.isClosed {
                        TradeNumericInputBlock(
                            title: "Exit Price",
                            subtitle: "\(symbolSpec.defaultDecimals) decimals",
                            text: $viewModel.exitPriceText,
                            placeholder: symbolSpec.pricePlaceholder
                        )
                    }
                    TradeNumericInputBlock(
                        title: "Fees & Commission",
                        subtitle: "Total fees",
                        text: $viewModel.feeText,
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
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TradeNumericInputBlock(
                        title: "Stop Loss (Price)",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $viewModel.stopLossText,
                        placeholder: "Optional"
                    )
                    TradeNumericInputBlock(
                        title: "Profit Target (Price)",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $viewModel.profitTargetText,
                        placeholder: "Optional"
                    )
                }
                
                TradePlaybookRulesCard(
                    selectedPlaybookId: $viewModel.selectedPlaybookId,
                    ruleAssessments: $viewModel.ruleAssessments,
                    playbooks: dataStore.playbooks
                )
            }
        }
    }
}
