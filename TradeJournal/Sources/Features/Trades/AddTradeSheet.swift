import SwiftUI

/// Manual trade entry sheet
/// Port 1:1 from `source-repo/apps/web/src/components/manual-trade-entry.tsx` & `add-trade-dialog.tsx`
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
    @State private var rating: Int = 0
    @State private var notes: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var mistakes: [String] = []
    @State private var mistakeInput: String = ""
    @State private var errorMessage: String? = nil
    
    private let commonSymbols = ["NQ", "ES", "EURUSD", "GBPUSD", "BTCUSDT", "ETHUSDT", "AAPL", "NVDA", "XAUUSD"]
    private let commonMistakes = ["FOMO", "Moved SL", "Held loser", "Counter-trend", "Oversized", "Early entry"]
    
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
    
    private var estimatedPnl: Decimal? {
        guard let exit = exitPrice, entryPrice > 0, quantity > 0 else { return nil }
        let diff = (direction == .long) ? (exit - entryPrice) : (entryPrice - exit)
        return (diff * quantity) - fee
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Account & Symbol
                Section("Account & Instrument") {
                    AppDropdownField(
                        label: "Account",
                        selection: $accountId,
                        options: dataStore.accounts.map { $0.id },
                        titleFor: { id in
                            if let acc = dataStore.accounts.first(where: { $0.id == id }) {
                                return "\(acc.name) (\(acc.currency))"
                            }
                            return id
                        }
                    )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Symbol (e.g. NQ, EURUSD, AAPL...)", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .font(AppTypography.subheadlineBold)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonSymbols, id: \.self) { sym in
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        symbol = sym
                                    } label: {
                                        Text(sym)
                                            .font(AppTypography.captionBold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(symbol == sym ? AppColors.brand : AppColors.cardBackground)
                                            .foregroundColor(symbol == sym ? .white : AppColors.primaryText)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(symbol == sym ? Color.clear : AppColors.border.opacity(0.5), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                    }
                }
                
                // Section 2: Position & Pricing
                Section("Position & Pricing") {
                    Picker("Direction", selection: $direction) {
                        Text("BUY / LONG").tag(TradeDirection.long)
                        Text("SELL / SHORT").tag(TradeDirection.short)
                    }
                    .pickerStyle(.segmented)
                    
                    Toggle("Closed position", isOn: $isClosed)
                    
                    HStack {
                        Text("Quantity:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Entry price:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Entry price", text: $entryPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if isClosed {
                        HStack {
                            Text("Exit price:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            TextField("Exit price", text: $exitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    HStack {
                        Text("Fees:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("0", text: $feeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if let pnl = estimatedPnl {
                        HStack {
                            Text("Estimated P&L:")
                                .font(AppTypography.captionBold)
                            Spacer()
                            Text(Formatters.formatPnL(pnl, currency: env.currentCurrency))
                                .font(AppTypography.headline.bold())
                                .foregroundColor(Formatters.pnlColor(pnl))
                        }
                    }
                }
                
                // Section 3: Execution Timestamps
                Section("Execution Timestamps") {
                    DatePicker("Opened at:", selection: $openedAt, displayedComponents: [.date, .hourAndMinute])
                    if isClosed {
                        DatePicker("Closed at:", selection: $closedAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                // Section 4: Risk Management & Strategy
                Section("Risk & Strategy") {
                    HStack {
                        Text("Stop Loss:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Optional", text: $stopLossText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Profit Target:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Optional", text: $profitTargetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    let playbookOptions = [""] + dataStore.playbooks.map { $0.id }
                    AppDropdownField(
                        label: "Playbook",
                        selection: $selectedPlaybookId,
                        options: playbookOptions,
                        titleFor: { id in
                            if id.isEmpty { return "None" }
                            return dataStore.playbooks.first(where: { $0.id == id })?.name ?? id
                        }
                    )
                }
                
                // Section 5: Discipline & Journal
                Section("Discipline & Journal") {
                    HStack {
                        Text("Rating:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundColor(star <= rating ? .yellow : AppColors.secondaryText)
                                .onTapGesture {
                                    rating = (rating == star) ? 0 : star
                                }
                        }
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(tags, id: \.self) { tag in
                                        AppBadge(text: "#\(tag)", color: AppColors.accent)
                                            .onTapGesture { tags.removeAll { $0 == tag } }
                                    }
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Add tag (e.g. fvg, scalp...)", text: $tagInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let clean = tagInput.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                                if !clean.isEmpty && !tags.contains(clean) {
                                    tags.append(clean)
                                    tagInput = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Mistakes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mistakes:")
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
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        if !mistakes.contains(m) { mistakes.append(m) }
                                    } label: {
                                        Text(m)
                                            .font(AppTypography.captionBold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(mistakes.contains(m) ? AppColors.loss.opacity(0.15) : AppColors.cardBackground)
                                            .foregroundColor(mistakes.contains(m) ? AppColors.loss : AppColors.secondaryText)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(mistakes.contains(m) ? AppColors.loss.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Other mistake...", text: $mistakeInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let clean = mistakeInput.trimmingCharacters(in: .whitespaces)
                                if !clean.isEmpty && !mistakes.contains(clean) {
                                    mistakes.append(clean)
                                    mistakeInput = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Notes Text Editor
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes on thesis & psychology:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        TextEditor(text: $notes)
                            .font(AppTypography.inputText)
                            .frame(minHeight: 80)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.border, lineWidth: 1))
                    }
                }
                
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
            .navigationTitle("Add Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Trade") {
                        saveTrade()
                    }
                    .font(AppTypography.headline)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if accountId.isEmpty {
                    accountId = dataStore.selectedAccountId
                }
            }
        }
    }
    
    private var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        quantity > 0 &&
        entryPrice > 0 &&
        (!isClosed || (exitPrice != nil && exitPrice! > 0))
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
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId
        )
        
        dismiss()
    }
}
