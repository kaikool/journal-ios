import SwiftUI

/// Manual trade entry sheet
/// Re-designed from the ground up to adhere 1:1 with Apple HIG and app design system:
/// - Clean card-based structure (AppCard / cardContainer), eliminating system Form styling
/// - Prioritizes Forex pairs & Gold (XAUUSD) first, with Crypto as secondary
/// - Interactive Playbook rule checklist directly inside Add Trade so rules can be scored upon entry
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
    @State private var tagInput: String = ""
    @State private var mistakes: [String] = []
    @State private var mistakeInput: String = ""
    @State private var showCryptoSymbols: Bool = false
    @State private var errorMessage: String? = nil
    
    // Priority: Gold (XAUUSD) & Major Forex Pairs First
    private let forexSymbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "NZDUSD"]
    private let cryptoIndicesSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "NQ", "ES", "US30"]
    private let commonMistakes = ["FOMO", "Moved SL", "Held loser", "Counter-trend", "Oversized", "Early entry", "No plan", "Chased"]
    
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
    
    private var selectedPlaybook: Playbook? {
        dataStore.playbooks.first { $0.id == selectedPlaybookId }
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
                        
                        // Section 2: Position & Direction
                        positionAndPricingCard
                        
                        // Section 3: Execution Timestamps
                        executionTimestampsCard
                        
                        // Section 4: Risk & Playbook Checklist
                        riskAndPlaybookCard
                        
                        // Section 5: Discipline & Journal Notes
                        disciplineAndNotesCard
                        
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
                .background(AppColors.background)
            }
            .onAppear {
                if accountId.isEmpty {
                    accountId = dataStore.selectedAccountId == "all"
                        ? (dataStore.accounts.first?.id ?? "")
                        : dataStore.selectedAccountId
                }
            }
        }
    }
    
    // MARK: - 1. Account & Symbol Card
    private var accountAndSymbolCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCOUNT & INSTRUMENT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Account Dropdown
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
                
                // Symbol input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbol")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("Enter symbol (e.g. XAUUSD, EURUSD)...", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.5)
                        )
                }
                
                // Quick Symbol Chips (Forex & Gold First)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Forex & Metals")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                showCryptoSymbols.toggle()
                            }
                        } label: {
                            Text(showCryptoSymbols ? "Hide Crypto" : "More (Crypto & Indices)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(forexSymbols, id: \.self) { sym in
                                quickSymbolPill(sym)
                            }
                        }
                    }
                    
                    if showCryptoSymbols {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(cryptoIndicesSymbols, id: \.self) { sym in
                                    quickSymbolPill(sym)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
    
    private func quickSymbolPill(_ sym: String) -> some View {
        let isSelected = symbol == sym
        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            symbol = sym
        } label: {
            Text(sym)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.brand : AppColors.secondaryBackground)
                .foregroundColor(isSelected ? .white : AppColors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppColors.border.opacity(0.6), lineWidth: 0.5)
                )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
    
    // MARK: - 2. Position & Pricing Card
    private var positionAndPricingCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("POSITION & PRICING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Direction Selector (Apple HIG Buy / Sell pills)
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
                    numericInputBlock(
                        title: "Quantity / Lots",
                        subtitle: symbolSpec.lotDescription,
                        text: $quantityText,
                        placeholder: "0.25"
                    )
                    numericInputBlock(
                        title: "Entry Price",
                        subtitle: "\(symbolSpec.defaultDecimals) decimals",
                        text: $entryPriceText,
                        placeholder: symbolSpec.pricePlaceholder
                    )
                    if isClosed {
                        numericInputBlock(
                            title: "Exit Price",
                            subtitle: "\(symbolSpec.defaultDecimals) decimals",
                            text: $exitPriceText,
                            placeholder: symbolSpec.pricePlaceholder
                        )
                    }
                    numericInputBlock(
                        title: "Fees & Commission",
                        subtitle: "Total fees",
                        text: $feeText,
                        placeholder: "0.00"
                    )
                }
                
                // Live Estimated P&L Banner
                if let pnl = estimatedPnl {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("ESTIMATED NET P&L")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppColors.secondaryText)
                                    .tracking(0.5)
                                
                                if let deltaStr = estimatedDeltaText {
                                    Text("· \(deltaStr)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Formatters.pnlColor(pnl))
                                }
                            }
                            
                            Text(Formatters.formatPnL(pnl, currency: env.currentCurrency))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(Formatters.pnlColor(pnl))
                            
                            // Detailed specification formula breakdown
                            Text("\(symbolSpec.cleanSymbol): \(quantity) lot · \(symbolSpec.lotDescription)")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                        Image(systemName: pnl >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(pnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                    .padding(12)
                    .background((pnl >= 0 ? AppColors.profit : AppColors.loss).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
    
    private func numericInputBlock(title: String, subtitle: String? = nil, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.mutedText)
                        .lineLimit(1)
                }
            }
            
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border.opacity(0.8), lineWidth: 0.5)
                )
        }
    }
    
    // MARK: - 3. Execution Timestamps Card
    private var executionTimestampsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("EXECUTION TIMESTAMPS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                HStack {
                    Text("Opened at")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    DatePicker("", selection: $openedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(AppColors.brand)
                }
                
                if isClosed {
                    HStack {
                        Text("Closed at")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        DatePicker("", selection: $closedAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(AppColors.brand)
                    }
                }
                
                // Quick Time Presets
                HStack(spacing: 6) {
                    Text("Quick open:")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                    
                    timePresetButton("Now") {
                        openedAt = Date()
                        if isClosed { closedAt = Date() }
                    }
                    timePresetButton("-15m") {
                        openedAt = Date().addingTimeInterval(-900)
                    }
                    timePresetButton("-1h") {
                        openedAt = Date().addingTimeInterval(-3600)
                    }
                    timePresetButton("-4h") {
                        openedAt = Date().addingTimeInterval(-14400)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private func timePresetButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppColors.secondaryBackground)
                .foregroundColor(AppColors.secondaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Risk & Strategy Card (With Playbook Checklist)
    private var riskAndPlaybookCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("STRATEGY & PLAYBOOK")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Stop Loss & Profit Target
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    numericInputBlock(title: "Stop Loss (Price)", subtitle: "\(symbolSpec.defaultDecimals) decimals", text: $stopLossText, placeholder: "Optional")
                    numericInputBlock(title: "Profit Target (Price)", subtitle: "\(symbolSpec.defaultDecimals) decimals", text: $profitTargetText, placeholder: "Optional")
                }
                
                // Playbook Dropdown
                let playbookOptions = [""] + dataStore.playbooks.map { $0.id }
                AppDropdownField(
                    label: "Trading Playbook",
                    selection: $selectedPlaybookId,
                    options: playbookOptions,
                    titleFor: { id in
                        if id.isEmpty { return "None (No playbook selected)" }
                        return dataStore.playbooks.first(where: { $0.id == id })?.name ?? id
                    },
                    iconFor: { id in id.isEmpty ? "minus.circle" : "book.pages" }
                )
                .onChange(of: selectedPlaybookId) { newId in
                    if let pb = dataStore.playbooks.first(where: { $0.id == newId }) {
                        for rule in pb.rules {
                            if ruleAssessments[rule] == nil {
                                ruleAssessments[rule] = false
                            }
                        }
                    }
                }
                
                // Playbook Rules Checklist Section (Expands immediately when playbook is selected)
                if let pb = selectedPlaybook, !pb.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checklist")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.brand)
                            
                            let followedCount = pb.rules.filter { ruleAssessments[$0] == true }.count
                            Text("RULE CHECKLIST (\(followedCount)/\(pb.rules.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                                .tracking(0.5)
                            
                            Spacer()
                            
                            let pct = pb.rules.isEmpty ? 0.0 : (Double(followedCount) / Double(pb.rules.count) * 100)
                            Text(String(format: "%.0f%% followed", pct))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(pct >= 70 ? AppColors.profit : AppColors.brand)
                        }
                        
                        Text("Check off the setup rules you respected for this trade:")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                        
                        VStack(spacing: 6) {
                            ForEach(pb.rules, id: \.self) { rule in
                                let isFollowed = ruleAssessments[rule] ?? false
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    ruleAssessments[rule] = !isFollowed
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isFollowed ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(isFollowed ? AppColors.profit : AppColors.secondaryText.opacity(0.6))
                                        
                                        Text(rule)
                                            .font(.system(size: 13, weight: isFollowed ? .medium : .regular))
                                            .foregroundColor(isFollowed ? AppColors.primaryText : AppColors.secondaryText)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isFollowed ? AppColors.profit.opacity(0.08) : AppColors.secondaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(isFollowed ? AppColors.profit.opacity(0.3) : AppColors.border.opacity(0.5), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
    
    // MARK: - 5. Discipline & Notes Card
    private var disciplineAndNotesCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("DISCIPLINE & NOTES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Star Rating
                HStack {
                    Text("Execution Rating:")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 16))
                                .foregroundColor(star <= rating ? .yellow : AppColors.secondaryText.opacity(0.4))
                                .onTapGesture {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    rating = (rating == star) ? 0 : star
                                }
                        }
                    }
                }
                
                // Mistakes Quick Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mistakes Recorded")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if !mistakes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(mistakes, id: \.self) { m in
                                    AppBadge(text: "⚠️ \(m)", color: AppColors.loss)
                                        .onTapGesture { mistakes.removeAll { $0 == m } }
                                }
                            }
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(commonMistakes, id: \.self) { m in
                                let isAdded = mistakes.contains(m)
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    if isAdded {
                                        mistakes.removeAll { $0 == m }
                                    } else {
                                        mistakes.append(m)
                                    }
                                } label: {
                                    Text(m)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isAdded ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                        .foregroundColor(isAdded ? AppColors.loss : AppColors.secondaryText)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strategy & Setup Tags")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags, id: \.self) { tag in
                                    AppBadge(text: "#\(tag)", color: AppColors.brand)
                                        .onTapGesture { tags.removeAll { $0 == tag } }
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        TextField("Add tag (e.g. fvg, london, breakout...)", text: $tagInput)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        Button {
                            let clean = tagInput.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                            if !clean.isEmpty && !tags.contains(clean) {
                                tags.append(clean)
                                tagInput = ""
                            }
                        } label: {
                            Text("Add")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(AppColors.brand.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    }
                }
                
                // Notes multiline editor
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thesis & Execution Notes")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("What was your edge? Why did you enter and exit here?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(AppTypography.inputText)
                        .foregroundColor(AppColors.primaryText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                        )
                }
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
