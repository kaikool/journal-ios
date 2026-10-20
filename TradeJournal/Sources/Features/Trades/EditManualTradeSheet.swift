import SwiftUI

/// Sheet for editing any trade (manual or reconstructed) with full CRUD support
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
    @State private var tagInput: String = ""
    @State private var mistakes: [String]
    @State private var mistakeInput: String = ""
    @State private var showCryptoSymbols: Bool = false
    @State private var errorMessage: String? = nil
    
    private let forexSymbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "NZDUSD"]
    private let cryptoIndicesSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "NQ", "ES", "US30"]
    private let commonMistakes = ["FOMO", "Moved SL", "Held loser", "Counter-trend", "Oversized", "Early entry", "No plan", "Chased"]
    
    public init(trade: Trade, onSave: ((Trade) -> Void)? = nil) {
        self.trade = trade
        self.onSave = onSave
        
        _symbol = State(initialValue: trade.symbol)
        _direction = State(initialValue: trade.direction)
        _isClosed = State(initialValue: trade.closedAt != nil || trade.avgExit != nil)
        _quantityText = State(initialValue: "\(trade.quantity)")
        _entryPriceText = State(initialValue: "\(trade.avgEntry)")
        _exitPriceText = State(initialValue: trade.avgExit.map { "\($0)" } ?? "")
        _openedAt = State(initialValue: trade.openedAt)
        _closedAt = State(initialValue: trade.closedAt ?? trade.openedAt)
        _feeText = State(initialValue: "\(trade.fees)")
        _stopLossText = State(initialValue: trade.stopLoss.map { "\($0)" } ?? "")
        _profitTargetText = State(initialValue: trade.profitTarget.map { "\($0)" } ?? "")
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
    
    private var estimatedPnl: Decimal? {
        guard let exit = exitPrice, entryPrice > 0, quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exit,
            customMultiplier: dataStore.multipliers[symbol.uppercased().trimmingCharacters(in: .whitespaces)],
            conversionRates: dataStore.currencyConversion.rates
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
            ZStack {
                AppColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppColors.loss)
                                Text(error)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.loss)
                                Spacer()
                            }
                            .padding(12)
                            .background(AppColors.loss.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        
                        assetAndDirectionCard
                        executionAndPricingCard
                        timingCard
                        riskAndTargetsCard
                        playbookCard
                        disciplineAndNotesCard
                        
                        Spacer(minLength: 32)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondaryText)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .font(AppTypography.bodyBold)
                    .foregroundColor(isValid ? AppColors.brand : AppColors.secondaryText.opacity(0.5))
                    .disabled(!isValid)
                }
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
        cardContainer {
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
                        .background(direction == .short ? AppColors.warning : AppColors.secondaryBackground)
                        .foregroundColor(direction == .short ? .white : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // Symbol Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbol / Pair")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("e.g. XAUUSD, EURUSD", text: $symbol)
                        .font(AppTypography.inputText)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                        )
                    
                    // Quick Selector Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(forexSymbols, id: \.self) { sym in
                                Button {
                                    symbol = sym
                                } label: {
                                    Text(sym)
                                        .font(.system(size: 11, weight: symbol.uppercased() == sym ? .bold : .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(symbol.uppercased() == sym ? AppColors.brand.opacity(0.15) : AppColors.secondaryBackground)
                                        .foregroundColor(symbol.uppercased() == sym ? AppColors.brand : AppColors.primaryText)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Position Size
                VStack(alignment: .leading, spacing: 6) {
                    Text("Position Size (Lots / Contracts / Units)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("1.0", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .font(AppTypography.inputText)
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
    
    // MARK: - 2. Execution & Pricing Card
    private var executionAndPricingCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("EXECUTION & PRICING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Entry Price
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Entry Price")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("\(symbolSpec.defaultDecimals) decimals")
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.mutedText)
                    }
                    
                    TextField(symbolSpec.pricePlaceholder, text: $entryPriceText)
                        .keyboardType(.decimalPad)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                        )
                }
                
                // Closed Trade Toggle
                Toggle(isOn: $isClosed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trade is Closed")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("Turn off if this position is still open")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .tint(AppColors.brand)
                
                // Exit Price (if closed)
                if isClosed {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Exit Price")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text("\(symbolSpec.defaultDecimals) decimals")
                                .font(.system(size: 9))
                                .foregroundColor(AppColors.mutedText)
                        }
                        
                        TextField(symbolSpec.pricePlaceholder, text: $exitPriceText)
                            .keyboardType(.decimalPad)
                            .font(AppTypography.inputText)
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                            )
                    }
                }
                
                // Commission & Fees
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Commission / Fees (\(env.currentCurrency))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("0.00", text: $feeText)
                        .keyboardType(.decimalPad)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                        )
                }
                
                // Live Estimated PnL Banner
                if let estPnl = estimatedPnl {
                    Divider().background(AppColors.border.opacity(0.5))
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Estimated Net P&L")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                if let deltaStr = estimatedDeltaText {
                                    Text("· \(deltaStr)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Formatters.pnlColor(estPnl))
                                }
                            }
                            
                            Text(Formatters.formatPnL(estPnl, currency: env.currentCurrency))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(Formatters.pnlColor(estPnl))
                            
                            Text("\(symbolSpec.cleanSymbol): \(quantity) lot · \(symbolSpec.lotDescription)")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                        AppBadge(
                            text: estPnl >= 0 ? "WIN" : "LOSS",
                            color: estPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                    }
                    .padding(10)
                    .background((estPnl >= 0 ? AppColors.profit : AppColors.loss).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
    
    // MARK: - 3. Timing Card
    private var timingCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("TIMING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                DatePicker("Opened At", selection: $openedAt, displayedComponents: [.date, .hourAndMinute])
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .tint(AppColors.brand)
                
                if isClosed {
                    DatePicker("Closed At", selection: $closedAt, displayedComponents: [.date, .hourAndMinute])
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .tint(AppColors.brand)
                }
            }
        }
    }
    
    // MARK: - 4. Risk & Targets Card
    private var riskAndTargetsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("RISK & TARGETS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stop Loss")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("Optional", text: $stopLossText)
                            .keyboardType(.decimalPad)
                            .font(AppTypography.inputText)
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Take Profit")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("Optional", text: $profitTargetText)
                            .keyboardType(.decimalPad)
                            .font(AppTypography.inputText)
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
    }
    
    // MARK: - 5. Playbook Card
    private var playbookCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("PLAYBOOK & SETUP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Playbook Picker
                Menu {
                    Button("No Playbook") {
                        selectedPlaybookId = ""
                    }
                    ForEach(dataStore.playbooks) { pb in
                        Button(pb.title) {
                            selectedPlaybookId = pb.id
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Assigned Playbook")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text(selectedPlaybook?.title ?? "None Selected")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(selectedPlaybook != nil ? AppColors.brand : AppColors.primaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
                }
                
                // Interactive Playbook Checklist
                if let pb = selectedPlaybook, !pb.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PLAYBOOK RULES CHECKLIST")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.brand)
                                .tracking(0.5)
                            Spacer()
                            let followedCount = pb.rules.filter { ruleAssessments[$0] == true }.count
                            Text("\(followedCount)/\(pb.rules.count) Met")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(followedCount == pb.rules.count ? AppColors.profit : AppColors.secondaryText)
                        }
                        
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
    
    // MARK: - 6. Discipline & Notes Card
    private var disciplineAndNotesCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
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
                                        .font(.system(size: 11, weight: isAdded ? .bold : .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(isAdded ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                        .foregroundColor(isAdded ? AppColors.loss : AppColors.secondaryText)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(tags, id: \.self) { t in
                                    AppBadge(text: "#\(t)", color: AppColors.brand)
                                        .onTapGesture { tags.removeAll { $0 == t } }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Add a tag (e.g. breakout)", text: $tagInput)
                            .font(AppTypography.inputText)
                            .padding(8)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                            )
                        
                        Button("Add") {
                            let clean = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty && !tags.contains(clean) {
                                tags.append(clean)
                                tagInput = ""
                            }
                        }
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(AppColors.brand.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
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
    
    private func saveChanges() {
        guard isValid else {
            errorMessage = "Please enter valid symbol, quantity, and price."
            return
        }
        
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        
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
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            tags: tags,
            mistakes: mistakes,
            rating: rating > 0 ? rating : nil,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId
        )
        
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
        
        // Return updated trade
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) ??
                         dataStore.trades.first(where: { $0.accountId == trade.accountId && $0.symbol == cleanSymbol }) {
            onSave?(updated)
        }
        
        dismiss()
    }
}
