import SwiftUI

// MARK: - 1. Reusable Apple HIG Card Container for Trade Forms
public struct TradeFormCardContainer<Content: View>: View {
    @ViewBuilder public let content: () -> Content
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
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
}

// MARK: - 2. Reusable Standard Numeric Input Block
public struct TradeNumericInputBlock: View {
    public let title: String
    public let subtitle: String?
    @Binding public var text: String
    public let placeholder: String
    
    public init(title: String, subtitle: String? = nil, text: Binding<String>, placeholder: String) {
        self.title = title
        self.subtitle = subtitle
        self._text = text
        self.placeholder = placeholder
    }
    
    public var body: some View {
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
            
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(AppTypography.number(14, weight: .semibold))
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
}

// MARK: - 3. Instrument / Symbol Selector Component
public struct TradeSymbolSelector: View {
    @Binding public var symbol: String
    @Binding public var showCryptoSymbols: Bool
    
    public static let forexSymbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "NZDUSD"]
    public static let cryptoIndicesSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "NQ", "ES", "US30"]
    
    public init(symbol: Binding<String>, showCryptoSymbols: Binding<Bool>) {
        self._symbol = symbol
        self._showCryptoSymbols = showCryptoSymbols
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Symbol")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                TextField("Enter symbol (e.g. XAUUSD, EURUSD)...", text: $symbol)
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.8), lineWidth: 0.5)
                    )
            }
            
            // Quick Instrument Selector Chips
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("POPULAR INSTRUMENTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.mutedText)
                        .tracking(0.5)
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showCryptoSymbols.toggle()
                    } label: {
                        Text(showCryptoSymbols ? "Forex/Gold" : "Crypto/Indices")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.brand)
                    }
                }
                
                let activeList = showCryptoSymbols ? Self.cryptoIndicesSymbols : Self.forexSymbols
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeList, id: \.self) { sym in
                            let isSelected = symbol.uppercased() == sym
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                symbol = sym
                            } label: {
                                Text(sym)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? AppColors.brand : AppColors.secondaryBackground)
                                    .foregroundColor(isSelected ? .white : AppColors.primaryText)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.clear : AppColors.border.opacity(0.7), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - 4. Live Estimated Net P&L Banner
public struct TradeEstimatedPnlBanner: View {
    public let estimatedPnl: Decimal?
    public let estimatedDeltaText: String?
    public let symbolSpec: AssetContractEngine.SymbolSpec
    public let quantity: Decimal
    public let reportingCurrency: String
    
    public init(
        estimatedPnl: Decimal?,
        estimatedDeltaText: String?,
        symbolSpec: AssetContractEngine.SymbolSpec,
        quantity: Decimal,
        reportingCurrency: String
    ) {
        self.estimatedPnl = estimatedPnl
        self.estimatedDeltaText = estimatedDeltaText
        self.symbolSpec = symbolSpec
        self.quantity = quantity
        self.reportingCurrency = reportingCurrency
    }
    
    public var body: some View {
        if let pnl = estimatedPnl {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
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
                    
                    Text(Formatters.formatPnL(pnl, currency: reportingCurrency))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Formatters.pnlColor(pnl))
                    
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

// MARK: - 5. Execution Timestamps Card
public struct TradeTimestampsCard: View {
    @Binding public var openedAt: Date
    @Binding public var closedAt: Date
    public let isClosed: Bool
    
    public init(openedAt: Binding<Date>, closedAt: Binding<Date>, isClosed: Bool) {
        self._openedAt = openedAt
        self._closedAt = closedAt
        self.isClosed = isClosed
    }
    
    public var body: some View {
        TradeFormCardContainer {
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
                    
                    presetButton("Now") {
                        openedAt = Date()
                        if isClosed { closedAt = Date() }
                    }
                    presetButton("-15m") {
                        openedAt = Date().addingTimeInterval(-900)
                    }
                    presetButton("-1h") {
                        openedAt = Date().addingTimeInterval(-3600)
                    }
                    presetButton("-4h") {
                        openedAt = Date().addingTimeInterval(-14400)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private func presetButton(_ label: String, action: @escaping () -> Void) -> some View {
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
}

// MARK: - 6. Playbook & Execution Rules Card
public struct TradePlaybookRulesCard: View {
    @Binding public var selectedPlaybookId: String
    @Binding public var ruleAssessments: [String: Bool]
    public let playbooks: [Playbook]
    
    public init(
        selectedPlaybookId: Binding<String>,
        ruleAssessments: Binding<[String: Bool]>,
        playbooks: [Playbook]
    ) {
        self._selectedPlaybookId = selectedPlaybookId
        self._ruleAssessments = ruleAssessments
        self.playbooks = playbooks
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playbook Dropdown
            let playbookOptions = [""] + playbooks.map { $0.id }
            AppDropdownField(
                label: "Trading Playbook",
                selection: $selectedPlaybookId,
                options: playbookOptions,
                titleFor: { id in
                    if id.isEmpty { return "None (No playbook selected)" }
                    return playbooks.first(where: { $0.id == id })?.name ?? id
                },
                iconFor: { id in id.isEmpty ? "minus.circle" : "book.pages" }
            )
            .onChange(of: selectedPlaybookId) { newId in
                if let pb = playbooks.first(where: { $0.id == newId }) {
                    for rule in pb.rules {
                        if ruleAssessments[rule] == nil {
                            ruleAssessments[rule] = false
                        }
                    }
                }
            }
            
            // Rules Checklist
            if let pb = playbooks.first(where: { $0.id == selectedPlaybookId }), !pb.rules.isEmpty {
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
                        
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            let allFollowed = pb.rules.allSatisfy { ruleAssessments[$0] == true }
                            for rule in pb.rules {
                                ruleAssessments[rule] = !allFollowed
                            }
                        } label: {
                            Text(pb.rules.allSatisfy { ruleAssessments[$0] == true } ? "Clear All" : "Select All")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
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
                                        .font(AppTypography.caption)
                                        .foregroundColor(isFollowed ? AppColors.primaryText : AppColors.secondaryText)
                                        .strikethrough(!isFollowed && ruleAssessments[rule] != nil ? false : false)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(isFollowed ? AppColors.profit.opacity(0.08) : AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isFollowed ? AppColors.profit.opacity(0.3) : Color.clear, lineWidth: 0.5)
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

// MARK: - 7. Discipline, Mistakes & Notes Card
public struct TradeDisciplineAndNotesCard: View {
    @Binding public var rating: Int
    @Binding public var mistakes: [String]
    @Binding public var tags: [String]
    @Binding public var notes: String
    
    @State private var tagInput: String = ""
    @State private var mistakeInput: String = ""
    
    public static let commonMistakes: [String] = [
        "FOMO", "Moved SL", "Held loser", "Counter-trend",
        "Oversized", "Early entry", "No plan", "Chased",
        "Hesitation", "Wide Spread Slippage"
    ]
    
    public init(
        rating: Binding<Int>,
        mistakes: Binding<[String]>,
        tags: Binding<[String]>,
        notes: Binding<String>
    ) {
        self._rating = rating
        self._mistakes = mistakes
        self._tags = tags
        self._notes = notes
    }
    
    public var body: some View {
        TradeFormCardContainer {
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
                            ForEach(Self.commonMistakes, id: \.self) { m in
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
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(AppColors.brand.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(AppColors.brand.opacity(0.25), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // Notes multiline editor with Office-style formatting & preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thesis & Execution Notes")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    RichNoteEditor(
                        text: $notes,
                        placeholder: "What was your edge? Why did you enter and exit here?",
                        minHeight: 85,
                        allowPreviewToggle: true
                    )
                }
            }
        }
    }
}
