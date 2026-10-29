import SwiftUI
import UIKit

// MARK: - Pre-Trade Multi-Timeframe Market Structure & Bias Analyzer (Apple HIG)
// Coordinates D1 macro regime, H4 order blocks, and M15 execution structure to deliver actionable setups
public struct PreTradeAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedSymbol: String = "XAUUSD"
    @State private var customSymbolText: String = ""
    @State private var selectedTimeframe: String = "15m" // "15m", "4h", "1d", "all"
    
    @State private var d1Bars: [MarketBar] = []
    @State private var h4Bars: [MarketBar] = []
    @State private var h1Bars: [MarketBar] = []
    @State private var m15Bars: [MarketBar] = []
    @State private var activeProvider: String = ""
    
    @State private var analysisResult: String = ""
    @State private var isLoadingData: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var followUpMessages: [AICoachMessage] = []
    @State private var followUpQuery: String = ""
    @State private var isSubmittingFollowUp: Bool = false
    
    @State private var activeChartSnapshot: UIImage? = nil
    @State private var showFullScreenChart: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var userAttachedImage: UIImage? = nil
    
    @State private var isSavedToNotebook: Bool = false
    @State private var showCopiedAlert: Bool = false
    @State private var showLinkTicketSheet: Bool = false
    @State private var createdNoteId: String? = nil
    
    public init(initialSymbol: String = "XAUUSD") {
        self._selectedSymbol = State(initialValue: initialSymbol)
    }
    
    private var activeBars: [MarketBar] {
        switch selectedTimeframe {
        case "1d": return d1Bars
        case "4h": return h4Bars
        case "1h": return h1Bars
        default: return m15Bars
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Symbol Selection & Quick Switcher
                    PreTradeSymbolSelectorCard(
                        selectedSymbol: $selectedSymbol,
                        customSymbolText: $customSymbolText,
                        onSelectSymbol: { sym in
                            onSymbolSelected(sym)
                        },
                        onSubmitCustom: submitCustomSymbol
                    )
                    
                    // 2. Multi-Timeframe Chart Vision Card
                    PreTradeChartCard(
                        symbol: selectedSymbol,
                        selectedTimeframe: $selectedTimeframe,
                        activeBars: activeBars,
                        d1Bars: d1Bars,
                        h4Bars: h4Bars,
                        h1Bars: h1Bars,
                        m15Bars: m15Bars,
                        activeProvider: activeProvider,
                        onEnlarge: {
                            if let snapshot = (userAttachedImage ?? renderActiveSnapshot()) {
                                self.activeChartSnapshot = snapshot
                                self.showFullScreenChart = true
                            }
                        },
                        onAttachPhoto: { showPhotoPicker = true }
                    )
                    
                    // 3. Quantitative Dynamic EMA Trend & Liquidity Summary
                    if !d1Bars.isEmpty || !h4Bars.isEmpty || !h1Bars.isEmpty || !m15Bars.isEmpty {
                        PreTradeContextMetricsCard(
                            d1Bars: d1Bars,
                            h4Bars: h4Bars,
                            h1Bars: h1Bars,
                            m15Bars: m15Bars,
                            symbol: selectedSymbol
                        )
                    }
                    
                    // 4. Loading, Error, AI Decision Document, or Action CTA Card
                    if isAnalyzing || isLoadingData {
                        PreTradeLoadingCard(isLoadingData: isLoadingData)
                    } else if let error = errorMessage {
                        PreTradeErrorCard(message: error, onRetry: {
                            Task {
                                await fetchAllTimeframeBars(for: selectedSymbol, forceRefresh: true)
                                await runFullAnalysis()
                            }
                        })
                    } else if !analysisResult.isEmpty {
                        AIDocumentReaderView(text: analysisResult)
                        
                        // Follow-up discussion section
                        PreTradeFollowUpSection(
                            analysisResult: analysisResult,
                            followUpMessages: $followUpMessages,
                            followUpQuery: $followUpQuery,
                            isSubmitting: isSubmittingFollowUp,
                            onResetThread: {
                                followUpMessages = []
                                followUpQuery = ""
                                let cacheKey = "pretrade_\(selectedSymbol)"
                                AICoachSessionStore.shared.save(key: cacheKey, result: analysisResult, followUps: [])
                            },
                            onSubmit: submitFollowUp
                        )
                        
                        // Bottom action buttons
                        PreTradeActionBar(
                            isSavedToNotebook: isSavedToNotebook,
                            showCopiedAlert: showCopiedAlert,
                            onSaveNotebook: saveToNotebook,
                            onLinkTicket: {
                                showLinkTicketSheet = true
                            },
                            onCopy: copyToClipboard,
                            onRegenerate: {
                                followUpMessages = []
                                Task {
                                    await fetchAllTimeframeBars(for: selectedSymbol, forceRefresh: true)
                                    await runFullAnalysis()
                                }
                            }
                        )
                    } else {
                        // User-triggered analysis card (no unprompted AI executions)
                        analyzeCtaCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("Market Structure Bias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(AppColors.secondaryBackground.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showFullScreenChart) {
                if let img = activeChartSnapshot ?? renderActiveSnapshot() ?? userAttachedImage {
                    FullScreenChartLightboxView(image: img)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                UIKitImagePicker(isPresented: $showPhotoPicker) { data, _ in
                    if let img = UIImage(data: data) {
                        self.userAttachedImage = img
                        self.activeChartSnapshot = img
                        Task { await runFullAnalysis() }
                    }
                }
            }
            .sheet(isPresented: $showLinkTicketSheet) {
                if let noteId = createdNoteId {
                    LinkNoteToTradeSheet(
                        noteId: noteId,
                        noteTitle: "[Pre-Trade Bias] \(selectedSymbol)",
                        currentTradeKey: nil
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .task {
            onSymbolSelected(selectedSymbol)
        }
    }
    
    // MARK: - Action CTA Card
    private var analyzeCtaCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Institutional Structure Audit")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Cross-references D1 macro trend, H4 swing structure, and M15 execution trigger.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                
                Button(action: {
                    Task { await runFullAnalysis() }
                }) {
                    Text("Analyze Market Bias")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(AppColors.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)
        }
    }
    
    private func onSymbolSelected(_ sym: String) {
        selectedSymbol = sym
        let cacheKey = "pretrade_\(sym)"
        if let cached = AICoachSessionStore.shared.get(key: cacheKey) {
            self.analysisResult = cached.result
            self.followUpMessages = cached.followUps
        } else {
            self.analysisResult = ""
            self.followUpMessages = []
        }
        Task { await fetchAllTimeframeBars(for: sym) }
    }
    
    private func submitCustomSymbol() {
        let clean = customSymbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        customSymbolText = ""
        onSymbolSelected(clean)
    }
    
    // MARK: - Follow-Up Actions
    private func submitFollowUp() {
        let q = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSubmittingFollowUp else { return }
        
        let userMsg = AICoachMessage(role: "user", content: q)
        // Keep front-end messages clean (only user questions and AI replies)
        self.followUpMessages.append(userMsg)
        self.followUpQuery = ""
        self.isSubmittingFollowUp = true
        
        let currentSymbol = self.selectedSymbol
        
        Task {
            // 1. Fetch freshest M15 candles, or fallback to current m15Bars
            var activeBars = self.m15Bars
            if let freshM15 = try? await MarketDataService.shared.fetchBarsForSymbol(
                symbol: currentSymbol,
                config: dataStore.marketConnections,
                resolution: "15m",
                count: 100,
                forceRefresh: true
            ), !freshM15.bars.isEmpty {
                activeBars = freshM15.bars
                await MainActor.run {
                    self.m15Bars = freshM15.bars
                }
            }
            
            let displayTz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
            var liveContext = ""
            if let latest = activeBars.last {
                let d = (latest.close as NSDecimalNumber).doubleValue
                let priceStr = d >= 100 ? String(format: "%.2f", d) : String(format: "%.5f", d)
                let openStr = Formatters.price(latest.open)
                let highStr = Formatters.price(latest.high)
                let lowStr = Formatters.price(latest.low)
                
                let candleTape = CandleTapeFormatter.formatCandlesTable(
                    bars: activeBars,
                    count: 10,
                    symbol: selectedSymbol,
                    displayTimeZone: displayTz
                )
                
                let window = MomentumEngine.computeWindow(bars: activeBars, windowSize: 15)
                let momTable = MomentumEngine.formatMomentumTable(
                    window: window,
                    displayTimeZone: displayTz,
                    isVi: dataStore.aiSettings.language == "vi"
                )
                
                let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
                if isVi {
                    liveContext = """
                    [DỮ LIỆU THỊ TRƯỜNG & BĂNG NẾN THỰC TẾ TẠI THỜI ĐIỂM HỎI ĐÁP]:
                    • Cặp tiền / Tài sản: \(currentSymbol)
                    • Giá thị trường cập nhật mới nhất: \(priceStr)
                    • Nến M15 mới nhất: Mở \(openStr) | Cao \(highStr) | Thấp \(lowStr) | Đóng \(priceStr)
                    
                    BẢNG BĂNG GIÁ 10 NẾN M15 MỚI NHẤT:
                    \(candleTape)
                    
                    BẢNG ĐỘNG LƯỢNG M15 (RSI 14 WILDER / EMA 9 / WMA 45):
                    \(momTable)
                    """
                } else {
                    liveContext = """
                    [REAL-TIME MARKET & CANDLESTICK DATA AT MOMENT OF INQUIRY]:
                    • Symbol: \(currentSymbol)
                    • Latest Market Price: \(priceStr)
                    • Latest M15 Bar: Open \(openStr) | High \(highStr) | Low \(lowStr) | Close \(priceStr)
                    
                    RECENT 10 M15 CANDLESTICKS TAPE:
                    \(candleTape)
                    
                    TECHNICAL MOMENTUM TABLE (RSI 14 / EMA 9 / WMA 45):
                    \(momTable)
                    """
                }
            }
            
            let attachedImageB64 = userAttachedImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
            
            // Backend context: push condensed initial analysis and live market update invisibly to AI
            var historyToSend: [AICoachMessage] = []
            if !self.analysisResult.isEmpty {
                let condensed = self.analysisResult.count > 1200
                    ? String(self.analysisResult.prefix(1200)) + "\n[...Ngữ cảnh nhận định ban đầu...]"
                    : self.analysisResult
                historyToSend.append(AICoachMessage(role: "assistant", content: condensed))
            }
            historyToSend.append(contentsOf: self.followUpMessages)
            
            var augmentedPrompt = q
            if !liveContext.isEmpty {
                augmentedPrompt = "\(q)\n\n\(liveContext)"
            }
            let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
            if isVi {
                augmentedPrompt += """
                
                [CHỈ DẪN BẮT BUỘC VỀ BẢN LĨNH & THÍCH ỨNG THEO CẤU TRÚC]:
                1. CẤM XIN LỖI / NỊNH TRADER: Tuyệt đối không nói 'Tôi xin lỗi', 'Tôi nhầm' khi bị trader chất vấn hay nghi ngờ.
                2. ĐỐI CHIẾU VỚI KẾ HOẠCH GỐC & GIÁ HIỆN TẠI:
                   • Nếu cấu trúc thị trường VẪN BẢO TOÀN (giá chưa vi phạm mốc Invalidation SL): Giữ vững lập trường, giải thích điềm tĩnh nhịp biến động hiện tại là nhịp hồi hay bẫy thanh khoản bình thường.
                   • Nếu thị trường ĐÃ THAY ĐỔI & VI PHẠM CẤU TRÚC (giá đóng nến qua mốc SL hoặc cấu trúc M15 bị gãy ngược chiều): Không cố chấp mù quáng! Hãy dứt khoát công bố kế hoạch ban đầu ĐÃ BỊ THỊ TRƯỜNG BÁC BỎ (INVALIDATED) do nến thực tế phá vỡ mức giá cụ thể nào, và chuyển ngay lập tức sang phương án QUẢN TRỊ RỦI RO / ĐỨNG NGOÀI (FLAT).
                3. Định dạng: Trả lời 100% bằng TIẾNG VIỆT, đi thẳng vào câu hỏi, súc tích bằng Markdown (tiêu đề `###`, gạch đầu dòng `•`, bảng so sánh nếu cần).
                """
            } else {
                augmentedPrompt += """
                
                [MANDATORY CONVICTION & EVIDENCE-BASED ADAPTATION PROTOCOL]:
                1. ZERO APOLOGY: Never apologize or say 'I was wrong' simply because the trader challenges your view.
                2. CROSS-EXAMINE WITH COMMITTED ANCHOR & LIVE CANDLES:
                   • If market structure remains INTACT (price has not breached the structural Invalidation SL): Maintain professional conviction and explain why the current retest/pullback is technically expected within probabilistic variance.
                   • If market has CHANGED & INVALIDATED structure (price closed beyond the SL or formed an opposing MSS): Do NOT be dogmatic! Explicitly declare the setup INVALIDATED citing the exact violation price, and transition stance to RISK DEFENSE / FLAT.
                3. Formatting: Answer directly and concisely in Markdown (headers `###`, bullet points `•`, tables if helpful).
                """
            }
            
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: augmentedPrompt,
                    metrics: nil,
                    edgeScore: nil,
                    language: dataStore.aiSettings.language,
                    chartImageBase64: attachedImageB64,
                    chartImagesBase64: nil,
                    sessionSummary: nil,
                    conversationHistory: historyToSend
                )
                await MainActor.run {
                    self.followUpMessages.append(AICoachMessage(role: "assistant", content: response))
                    self.isSubmittingFollowUp = false
                    self.isSavedToNotebook = false
                    let cacheKey = "pretrade_\(self.selectedSymbol)"
                    AICoachSessionStore.shared.save(key: cacheKey, result: self.analysisResult, followUps: self.followUpMessages)
                }
            } catch {
                await MainActor.run {
                    self.followUpMessages.append(AICoachMessage(role: "assistant", content: "Error: \(error.localizedDescription)"))
                    self.isSubmittingFollowUp = false
                }
            }
        }
    }
    
    // MARK: - Market Fetching & Analysis Execution
    private func fetchAllTimeframeBars(for sym: String, forceRefresh: Bool = false) async {
        await MainActor.run {
            self.isLoadingData = true
            self.errorMessage = nil
            self.isSavedToNotebook = false
        }
        
        let config = dataStore.marketConnections
        
        do {
            async let d1Task = MarketDataService.shared.fetchBarsForSymbol(symbol: sym, config: config, resolution: "1d", count: 30, forceRefresh: forceRefresh)
            async let h4Task = MarketDataService.shared.fetchBarsForSymbol(symbol: sym, config: config, resolution: "4h", count: 36, forceRefresh: forceRefresh)
            async let h1Task = MarketDataService.shared.fetchBarsForSymbol(symbol: sym, config: config, resolution: "1h", count: 48, forceRefresh: forceRefresh)
            async let m15Task = MarketDataService.shared.fetchBarsForSymbol(symbol: sym, config: config, resolution: "15m", count: 100, forceRefresh: forceRefresh)
            
            let (d1Res, h4Res, h1Res, m15Res) = try await (d1Task, h4Task, h1Task, m15Task)
            
            await MainActor.run {
                self.d1Bars = d1Res.bars
                self.h4Bars = h4Res.bars
                self.h1Bars = h1Res.bars
                self.m15Bars = m15Res.bars
                self.activeProvider = m15Res.provider
                self.isLoadingData = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoadingData = false
                self.isAnalyzing = false
            }
        }
    }
    
    private func runFullAnalysis() async {
        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
        }
        
        // Ensure bars are loaded before formulating bias
        if d1Bars.isEmpty || h4Bars.isEmpty || h1Bars.isEmpty || m15Bars.isEmpty {
            await fetchAllTimeframeBars(for: selectedSymbol, forceRefresh: false)
        }
        
        guard !d1Bars.isEmpty || !h4Bars.isEmpty || !h1Bars.isEmpty || !m15Bars.isEmpty else {
            await MainActor.run {
                self.errorMessage = dataStore.aiSettings.language == "vi"
                    ? "Không thể tải dữ liệu nến cho \(selectedSymbol). Vui lòng thử lại sau giây lát."
                    : "Unable to stream candle data for \(selectedSymbol). Please retry in a moment."
                self.isAnalyzing = false
            }
            return
        }
        
        let activeSnap = renderActiveSnapshot()
        await MainActor.run {
            self.activeChartSnapshot = activeSnap
        }
        
        // Only encode image if user explicitly attached a photo
        let singleChartBase64 = userAttachedImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        let prevAnalysis = analysisResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : analysisResult
        
        do {
            let response = try await AIReflectionService.shared.requestPreTradeMarketAnalysis(
                symbol: selectedSymbol,
                d1Bars: d1Bars,
                h4Bars: h4Bars,
                h1Bars: h1Bars,
                m15Bars: m15Bars,
                language: dataStore.aiSettings.language,
                chartImageBase64: singleChartBase64,
                chartImagesBase64: nil,
                conversationHistory: followUpMessages,
                previousAnalysis: prevAnalysis
            )
            await MainActor.run {
                self.analysisResult = response
                self.isAnalyzing = false
                let cacheKey = "pretrade_\(self.selectedSymbol)"
                AICoachSessionStore.shared.save(key: cacheKey, result: response, followUps: self.followUpMessages)
                
                // Persist structured advisor commitment so Trade Coach can automatically link and honor it
                let commitment = AIAdvisorMemoryEngine.shared.extractCommitment(from: response, symbol: self.selectedSymbol)
                AIAdvisorMemoryEngine.shared.saveCommitment(commitment)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    // MARK: - Individual Timeframe Chart Snapshot Renderers (100% Off-Screen)
    @MainActor
    private func renderChartSnapshot(bars: [MarketBar], timeframe: String) -> UIImage? {
        guard !bars.isEmpty else { return nil }
        let chart = MarketCandleChartView(
            bars: Array(bars.suffix(36)),
            symbol: selectedSymbol,
            timeframe: timeframe
        )
        .frame(width: 440, height: 260)
        .background(AppColors.cardBackground)
        
        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2.0
        return renderer.uiImage
    }
    
    @MainActor
    private func renderAllThreeTimeframeSnapshots() -> [String] {
        var base64List: [String] = []
        if !d1Bars.isEmpty, let img = renderChartSnapshot(bars: d1Bars, timeframe: "D1"), let b64 = img.jpegData(compressionQuality: 0.85)?.base64EncodedString() {
            base64List.append(b64)
        }
        if !h4Bars.isEmpty, let img = renderChartSnapshot(bars: h4Bars, timeframe: "H4"), let b64 = img.jpegData(compressionQuality: 0.85)?.base64EncodedString() {
            base64List.append(b64)
        }
        if !h1Bars.isEmpty, let img = renderChartSnapshot(bars: h1Bars, timeframe: "H1"), let b64 = img.jpegData(compressionQuality: 0.85)?.base64EncodedString() {
            base64List.append(b64)
        }
        if !m15Bars.isEmpty, let img = renderChartSnapshot(bars: m15Bars, timeframe: "M15"), let b64 = img.jpegData(compressionQuality: 0.85)?.base64EncodedString() {
            base64List.append(b64)
        }
        return base64List
    }
    
    // MARK: - Multi-Timeframe Tri-Panel Fallback Snapshot Renderer (100% Off-Screen)
    @MainActor
    private func renderMultiTimeframeSnapshot() -> UIImage? {
        guard !d1Bars.isEmpty || !h4Bars.isEmpty || !m15Bars.isEmpty else { return nil }
        let canvas = MultiTimeframeTriVisionCanvas(
            symbol: selectedSymbol,
            d1Bars: d1Bars,
            h4Bars: h4Bars,
            h1Bars: h1Bars,
            m15Bars: m15Bars
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0
        return renderer.uiImage
    }
    
    // MARK: - Single Tab Snapshot Renderer
    @MainActor
    private func renderActiveSnapshot() -> UIImage? {
        guard !activeBars.isEmpty else { return nil }
        let tfTitle: String = {
            switch selectedTimeframe {
            case "1d": return "D1"
            case "4h": return "H4"
            case "1h": return "H1"
            default: return "M15"
            }
        }()
        let chart = MarketCandleChartView(
            bars: activeBars,
            symbol: selectedSymbol,
            timeframe: tfTitle
        )
        .frame(width: 420, height: 260)
        .background(AppColors.cardBackground)
        
        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2.0
        return renderer.uiImage
    }
    
    // MARK: - Document Content Builder
    private func fullAnalysisContent() -> String {
        var fullText = analysisResult
        let followUps = followUpMessages.filter { $0.content != analysisResult }
        if !followUps.isEmpty {
            fullText += "\n\n### Follow-Up Discussion\n"
            for msg in followUps {
                if msg.role == "user" {
                    fullText += "\n• **Trader**: \(msg.content)\n"
                } else {
                    fullText += "\n• **Risk AI**: \(msg.content)\n"
                }
            }
        }
        return fullText
    }
    
    // MARK: - Actions
    private func saveToNotebook() {
        guard !analysisResult.isEmpty else { return }
        let folderName = "Trade Insights"
        let folder: NotebookFolder
        if let existing = dataStore.folders.first(where: { $0.name.lowercased() == folderName.lowercased() }) {
            folder = existing
        } else {
            do {
                folder = try dataStore.createFolder(name: folderName)
            } catch {
                AppLogger.warning("Failed to create folder: \(error.localizedDescription)")
                return
            }
        }
        
        let dateStr = JournalIds.todayDateString()
        let title = "[Pre-Trade Bias] \(selectedSymbol) (\(dateStr))"
        
        let tags = ["#pre-trade-bias", "#market-structure", "#\(selectedSymbol.lowercased())"]
        let content = fullAnalysisContent()
        
        do {
            if let existingId = createdNoteId {
                _ = try dataStore.patchNote(
                    id: existingId,
                    title: title,
                    content: content,
                    tags: tags,
                    folderId: folder.id
                )
            } else {
                let note = try dataStore.createNote(
                    folderId: folder.id,
                    title: title,
                    content: content,
                    tags: tags,
                    tradeKey: nil,
                    dayDate: dateStr
                )
                createdNoteId = note.id
            }
            isSavedToNotebook = true
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            AppLogger.warning("Failed to save note: \(error.localizedDescription)")
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = fullAnalysisContent()
        showCopiedAlert = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
}
