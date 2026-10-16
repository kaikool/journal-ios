import SwiftUI

/// Màn hình nhập giao dịch thủ công (Manual Trade Entry)
/// Port 1:1 từ `source-repo/apps/web/src/components/manual-trade-entry.tsx` & `add-trade-dialog.tsx`
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
    private let commonMistakes = ["FOMO", "Dời SL", "Gồng lỗ", "Đánh ngược trend", "Khối lượng quá lớn", "Vào lệnh sớm"]
    
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
                Section("Tài khoản & Mã giao dịch") {
                    Picker("Tài khoản", selection: $accountId) {
                        ForEach(dataStore.accounts) { acc in
                            Text("\(acc.name) (\(acc.currency))").tag(acc.id)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Mã (VD: NQ, EURUSD, AAPL...)", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .font(AppTypography.subheadlineBold)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonSymbols, id: \.self) { sym in
                                    Button(action: { symbol = sym }) {
                                        Text(sym)
                                            .font(AppTypography.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(symbol == sym ? AppColors.accent : AppColors.cardBackground)
                                            .foregroundColor(symbol == sym ? .white : AppColors.primaryText)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                // Section 2: Vị thế & Giá
                Section("Thông số lệnh") {
                    Picker("Hướng lệnh", selection: $direction) {
                        Text("MUA / LONG").tag(TradeDirection.long)
                        Text("BÁN / SHORT").tag(TradeDirection.short)
                    }
                    .pickerStyle(.segmented)
                    
                    Toggle("Đã đóng lệnh (Closed)", isOn: $isClosed)
                    
                    HStack {
                        Text("Khối lượng:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Giá vào (Entry):")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Giá khớp", text: $entryPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if isClosed {
                        HStack {
                            Text("Giá ra (Exit):")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            TextField("Giá chốt", text: $exitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    HStack {
                        Text("Phí giao dịch:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("0", text: $feeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if let pnl = estimatedPnl {
                        HStack {
                            Text("Lãi/Lỗ tạm tính:")
                                .font(AppTypography.captionBold)
                            Spacer()
                            Text(Formatters.formatPnL(pnl, currency: env.currentCurrency))
                                .font(AppTypography.headline.bold())
                                .foregroundColor(Formatters.pnlColor(pnl))
                        }
                    }
                }
                
                // Section 3: Thời gian
                Section("Thời gian khớp lệnh") {
                    DatePicker("Thời gian vào:", selection: $openedAt, displayedComponents: [.date, .hourAndMinute])
                    if isClosed {
                        DatePicker("Thời gian đóng:", selection: $closedAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                // Section 4: Quản trị rủi ro & Playbook
                Section("Quản trị rủi ro & Chiến lược") {
                    HStack {
                        Text("Stop Loss:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Không bắt buộc", text: $stopLossText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Take Profit:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        TextField("Không bắt buộc", text: $profitTargetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Chiến lược (Playbook)", selection: $selectedPlaybookId) {
                        Text("Không áp dụng").tag("")
                        ForEach(dataStore.playbooks) { pb in
                            Text(pb.name).tag(pb.id)
                        }
                    }
                }
                
                // Section 5: Đánh giá & Ghi chú
                Section("Đánh giá kỷ luật & Nhật ký") {
                    HStack {
                        Text("Đánh giá lệnh:")
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
                            TextField("Thêm tag (VD: fvg, scalping...)", text: $tagInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Thêm") {
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
                        Text("Sai lầm vi phạm:")
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
                                    Button(action: {
                                        if !mistakes.contains(m) { mistakes.append(m) }
                                    }) {
                                        Text(m)
                                            .font(AppTypography.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppColors.cardBackground)
                                            .foregroundColor(AppColors.secondaryText)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Sai lầm khác...", text: $mistakeInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Thêm") {
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
                        Text("Ghi chú lý do vào lệnh & tâm lý:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        TextEditor(text: $notes)
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
            .navigationTitle("Ghi Nhận Giao Dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu Giao Dịch") {
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
            errorMessage = "Vui lòng nhập đầy đủ mã, khối lượng và giá hợp lệ."
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
