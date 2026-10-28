import SwiftUI

// MARK: - Notebook Note & Order Ticket AI Inquiry Sheet
/// Provides continuous, contextual inquiry with AI Coach inside the Notebook note.
/// Links the Pre-Trade thesis with the executed Order Ticket, live M15 updates,
/// and saves actionable lessons back into the note.
public struct NoteAIInquirySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public let noteId: String
    public let noteTitle: String
    @Binding public var noteContent: String
    @State public var tradeKey: String?
    public var onSave: () -> Void
    
    @State private var messages: [AICoachMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSavedToast: Bool = false
    @State private var showLinkTradeSheet: Bool = false
    
    public init(
        noteId: String,
        noteTitle: String,
        noteContent: Binding<String>,
        tradeKey: String? = nil,
        onSave: @escaping () -> Void
    ) {
        self.noteId = noteId
        self.noteTitle = noteTitle
        self._noteContent = noteContent
        self._tradeKey = State(initialValue: tradeKey)
        self.onSave = onSave
    }
    
    private var linkedTrade: Trade? {
        guard let key = tradeKey, !key.isEmpty else { return nil }
        return dataStore.trades.first(where: {
            $0.key == key || $0.executionIds.contains(key) || $0.id == key
        })
    }
    
    private var ticket: String {
        linkedTrade?.executionIds.first ?? linkedTrade?.id ?? tradeKey ?? "N/A"
    }
    
    private var parsedPlan: ParsedPreTradeNote? {
        PreTradeNoteBinding.parseFromNote(noteContent)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Context Header Banner
                contextHeaderBanner
                
                Divider()
                
                // 2. Chat History
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty && isLoading {
                                initialLoadingState
                            } else {
                                ForEach(messages) { msg in
                                    messageRow(msg)
                                        .id(msg.id)
                                }
                            }
                            
                            if isLoading && !messages.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AI Coach is examining note & execution...")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // 3. Quick Chips
                quickChipsBar
                
                Divider()
                
                // 4. Input Area
                inputArea
            }
            .navigationTitle("Note AI Inquiry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        NoteInquirySessionStore.shared.clear(noteId: noteId)
                        self.messages = []
                        Task { await startInitialAssessment() }
                    } label: {
                        Label("Re-analyze", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveLessonToNoteAndMemory) {
                        HStack(spacing: 5) {
                            Image(systemName: showSavedToast ? "checkmark.circle.fill" : "bookmark.fill")
                                .font(.system(size: 11))
                            Text(showSavedToast ? "Saved" : "Save Lesson")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(showSavedToast ? AppColors.profit : AppColors.brand)
                    }
                    .disabled(messages.isEmpty || showSavedToast || isLoading)
                }
            }
            .sheet(isPresented: $showLinkTradeSheet) {
                LinkNoteToTradeSheet(
                    noteId: noteId,
                    noteTitle: noteTitle,
                    currentTradeKey: tradeKey,
                    onLinked: { trade, _ in
                        self.tradeKey = trade.key
                        NoteInquirySessionStore.shared.clear(noteId: noteId)
                        self.messages = []
                        Task { await startInitialAssessment() }
                    },
                    onUnlinked: {
                        self.tradeKey = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task {
                let cached = NoteInquirySessionStore.shared.getMessages(noteId: noteId)
                let validCached = cached.filter { !$0.content.hasPrefix("⚠️") }
                if !validCached.isEmpty {
                    self.messages = validCached
                } else {
                    self.messages = []
                    await startInitialAssessment()
                }
            }
        }
    }
    
    // MARK: - Subviews (Minimalist Single-Line Header)
    
    private var contextHeaderBanner: some View {
        HStack(spacing: 8) {
            if let trade = linkedTrade {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(trade.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Text(trade.direction == .short ? "SELL" : "BUY")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(trade.direction == .short ? AppColors.loss : AppColors.profit)
                        .lineLimit(1)
                    
                    Text("Entry \(Formatters.price(trade.avgEntry))")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                Text(Formatters.currency(trade.netPnl))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    .lineLimit(1)
                
                Button {
                    showLinkTradeSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } else {
                Text(noteTitle.isEmpty ? "Notebook Note" : noteTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Button {
                    showLinkTradeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text("Link Trade")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
    }
    
    private var initialLoadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
                .padding(.top, 24)
            Text("AI is examining Note & Plan...")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    private func messageRow(_ msg: AICoachMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == "user" {
                Spacer(minLength: 32)
                Text(msg.content)
                    .font(AppTypography.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.brand)
                        Text("Risk AI Coach")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                    }
                    
                    JournalNotesMarkdownView(text: msg.content)
                }
                .padding(12)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
                
                Spacer(minLength: 24)
            }
        }
    }
    
    private var quickChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickChipButton("Kế hoạch này đúng hay sai do đâu?")
                if linkedTrade != nil {
                    quickChipButton("Lệnh này có vào đúng kế hoạch không?")
                    quickChipButton("SL và điểm thoát đã hợp lý chưa?")
                }
                quickChipButton("Bài học cho các lệnh tiếp theo là gì?")
                quickChipButton("Cập nhật diễn biến thị trường M15")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(AppColors.secondaryBackground.opacity(0.2))
    }
    
    private func quickChipButton(_ prompt: String) -> some View {
        Button(action: {
            inputText = prompt
            submitInquiry()
        }) {
            Text(prompt)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
        }
        .disabled(isLoading)
    }
    
    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Ask AI about this note, execution, or plan...", text: $inputText)
                .font(AppTypography.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.secondaryBackground)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                )
                .onSubmit { submitInquiry() }
            
            Button(action: submitInquiry) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(10)
        .background(AppColors.cardBackground)
    }
    
    // MARK: - Actions
    
    private var detectedSymbol: String {
        if let sym = linkedTrade?.symbol, !sym.isEmpty, sym != "Asset", sym != "Pre-Trade" {
            return sym
        }
        if let planSym = parsedPlan?.symbol, !planSym.isEmpty {
            return planSym
        }
        let clean = noteTitle
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
        let words = clean.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let excluded: Set<String> = ["PRE-TRADE", "BIAS", "NOTE", "AUDIT", "REVIEW", "INSIGHTS", "TRADE", "DAY", "DAILY", "RISK", "AI"]
        for w in words {
            let u = w.uppercased()
            if !excluded.contains(u) && u.count >= 3 && u.count <= 10 && u.range(of: "^[A-Z0-9_]+$", options: .regularExpression) != nil {
                return u
            }
        }
        for line in noteContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.localizedCaseInsensitiveContains("Cặp tiền") || trimmed.localizedCaseInsensitiveContains("Symbol") {
                if let colon = trimmed.firstIndex(of: ":") {
                    let token = String(trimmed[trimmed.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces).first?
                        .trimmingCharacters(in: CharacterSet.alphanumerics.inverted) ?? ""
                    if token.count >= 3 && token.count <= 10 {
                        return token.uppercased()
                    }
                }
            }
        }
        return "XAUUSD"
    }
    
    private func fetchBarsForAudit(trade: Trade) async -> [MarketBar]? {
        let sym = detectedSymbol
        if trade.avgEntry > 0 && !trade.symbol.isEmpty && trade.symbol != "Asset" && trade.symbol != "Pre-Trade" {
            if let res = try? await MarketDataService.shared.fetchBarsForTrade(
                trade: trade,
                config: dataStore.marketConnections,
                resolution: "15m"
            ), !res.bars.isEmpty {
                return res.bars
            }
        }
        if let res = try? await MarketDataService.shared.fetchBarsForSymbol(
            symbol: sym,
            config: dataStore.marketConnections,
            resolution: "15m",
            count: 100
        ), !res.bars.isEmpty {
            return res.bars
        }
        return nil
    }
    
    private func startInitialAssessment() async {
        isLoading = true
        let trade = linkedTrade ?? dummyTradeForNote()
        let bars = await fetchBarsForAudit(trade: trade)
        
        let prompt = AIPromptBuilder.buildTradeNoteInquiryPrompt(
            trade: trade,
            noteContent: noteContent,
            parsedPreTrade: parsedPlan,
            orderTicket: ticket,
            userQuestion: nil,
            bars: bars,
            language: dataStore.aiSettings.language.isEmpty ? "vi" : dataStore.aiSettings.language,
            displayTimeZone: dataStore.generalSettings.displayTimeZone
        )
        
        do {
            let response = try await AIReflectionService.shared.requestReflection(
                action: .critique,
                prompt: prompt,
                language: dataStore.aiSettings.language,
                conversationHistory: messages
            )
            
            await MainActor.run {
                messages.append(AICoachMessage(role: "assistant", content: response))
                isLoading = false
                NoteInquirySessionStore.shared.saveMessages(noteId: noteId, messages: messages)
            }
        } catch {
            await MainActor.run {
                messages.append(AICoachMessage(
                    role: "assistant",
                    content: "⚠️ Không thể kết nối AI Coach: \(error.localizedDescription)"
                ))
                isLoading = false
                NoteInquirySessionStore.shared.saveMessages(noteId: noteId, messages: messages)
            }
        }
    }
    
    private func submitInquiry() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !isLoading else { return }
        
        let userMsg = AICoachMessage(role: "user", content: text)
        messages.append(userMsg)
        NoteInquirySessionStore.shared.saveMessages(noteId: noteId, messages: messages)
        inputText = ""
        isLoading = true
        
        let trade = linkedTrade ?? dummyTradeForNote()
        
        Task {
            let isFollowUp = messages.count > 1
            let bars = await fetchBarsForAudit(trade: trade)
            let prompt: String
            if isFollowUp {
                var candleContext = ""
                if let b = bars, !b.isEmpty {
                    let displayTz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
                    let tape = CandleTapeFormatter.formatCandlesTable(bars: b, count: 8, symbol: trade.symbol, displayTimeZone: displayTz)
                    candleContext = "\n\n[BẢNG NẾN M15 THỰC TẾ GẦN NHẤT]:\n\(tape)"
                }
                
                let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
                if isVi {
                    prompt = """
                    CÂU HỎI TIẾP THEO CỦA TRADER: "\(text)"
                    
                    NGỮ CẢNH KẾ HOẠCH & GHI CHÚ:
                    • Tiêu đề: \(noteTitle)
                    • Cặp tiền / Mã: \(detectedSymbol)
                    • Vé lệnh: \(ticket)
                    • Kế hoạch: \(parsedPlan?.bias ?? "FLAT") | Mục tiêu TP: \(parsedPlan?.targetTP ?? "N/A") | Cắt lỗ SL: \(parsedPlan?.invalidationSL ?? "N/A")\(candleContext)
                    
                    YÊU CẦU TRẢ LỜI:
                    - BẮT BUỘC TRẢ LỜI 100% BẰNG TIẾNG VIỆT, đi thẳng vào câu hỏi, súc tích và chuẩn xác. Tuyệt đối không trả lời bằng tiếng Anh.
                    - Sử dụng Markdown đẹp: tiêu đề ngắn (`###`), gạch đầu dòng (`•`), hoặc bảng Markdown (`| Cột 1 | Cột 2 |`) nếu so sánh các kịch bản hoặc mức giá.
                    - Không lặp lại toàn bộ bài phân tích cũ, chỉ giải quyết thắc mắc hiện tại và các hành động xử lý rủi ro cụ thể dựa trên diễn biến nến thực tế.
                    """
                } else {
                    prompt = """
                    TRADER'S FOLLOW-UP INQUIRY: "\(text)"
                    
                    NOTE & PLAN CONTEXT:
                    • Title: \(noteTitle)
                    • Symbol: \(detectedSymbol)
                    • Ticket: \(ticket)
                    • Plan: \(parsedPlan?.bias ?? "FLAT") | Target: \(parsedPlan?.targetTP ?? "N/A") | Invalidation: \(parsedPlan?.invalidationSL ?? "N/A")\(candleContext)
                    
                    RESPONSE REQUIREMENTS:
                    - Answer directly, concisely, and precisely in Markdown format.
                    - Use short headers (`###`), bullet points (`•`), or tables if comparing scenarios.
                    - Focus strictly on answering the inquiry and providing actionable risk adjustments based on actual candle action.
                    """
                }
            } else {
                prompt = AIPromptBuilder.buildTradeNoteInquiryPrompt(
                    trade: trade,
                    noteContent: noteContent,
                    parsedPreTrade: parsedPlan,
                    orderTicket: ticket,
                    userQuestion: text,
                    bars: bars,
                    language: dataStore.aiSettings.language.isEmpty ? "vi" : dataStore.aiSettings.language,
                    displayTimeZone: dataStore.generalSettings.displayTimeZone
                )
            }
            
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: prompt,
                    language: dataStore.aiSettings.language,
                    conversationHistory: messages
                )
                
                await MainActor.run {
                    messages.append(AICoachMessage(role: "assistant", content: response))
                    isLoading = false
                    NoteInquirySessionStore.shared.saveMessages(noteId: noteId, messages: messages)
                }
            } catch {
                await MainActor.run {
                    messages.append(AICoachMessage(
                        role: "assistant",
                        content: "⚠️ Request failed: \(error.localizedDescription)"
                    ))
                    isLoading = false
                    NoteInquirySessionStore.shared.saveMessages(noteId: noteId, messages: messages)
                }
            }
        }
    }
    
    private func saveLessonToNoteAndMemory() {
        guard let lastAssistant = messages.last(where: { $0.role == "assistant" }) else { return }
        
        let content = lastAssistant.content
        let lessonText: String
        if let part4 = content.components(separatedBy: "### 4").last {
            lessonText = part4.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            lessonText = content.components(separatedBy: .newlines).suffix(3).joined(separator: " ")
        }
        
        let cleanLesson = lessonText.prefix(250).description
        guard !cleanLesson.isEmpty else { return }
        
        let sym = linkedTrade?.symbol ?? "Pre-Trade"
        
        // 1. Save to AIAdvisorMemoryEngine
        let lesson = TraderAILesson(
            symbol: sym,
            setupType: "\(sym) \(linkedTrade?.direction == .short ? "SELL" : "BUY")",
            mistakeTag: linkedTrade?.mistakes.first,
            lesson: cleanLesson,
            context: "Note: \(noteTitle)"
        )
        AIAdvisorMemoryEngine.shared.saveLesson(lesson)
        
        // 2. Append to noteContent (in Notebook Note)
        let lessonMarkdown = "\n\n> **[AI LESSON LEARNED]**\n> \(cleanLesson)"
        if !noteContent.contains(cleanLesson) {
            noteContent += lessonMarkdown
            onSave()
        }
        
        withAnimation {
            showSavedToast = true
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSavedToast = false
            }
        }
    }
    
    private func dummyTradeForNote() -> Trade {
        Trade(
            key: tradeKey ?? "note-trade",
            accountId: "default",
            symbol: detectedSymbol,
            direction: .long,
            status: .open,
            openedAt: Date(),
            quantity: 1,
            openQuantity: 1,
            avgEntry: 0,
            grossPnl: 0,
            fees: 0,
            netPnl: 0,
            executionCount: 1,
            executionIds: [ticket]
        )
    }
}
