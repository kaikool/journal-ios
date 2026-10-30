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
                        // 5. Pre-Trade Action Bar (Save Note, Link Trade, Copy, Regenerate) - Placed RIGHT ON TOP of AI Result
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
                        
                        // 6. Structured Section Cards Reader
                        AIDocumentReaderView(text: analysisResult)
                        
                        // 7. Follow-up conversation turns (message bubbles in scroll view)
                        PreTradeFollowUpSection(
                            analysisResult: analysisResult,
                            followUpMessages: followUpMessages
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
            .safeAreaInset(edge: .bottom) {
                if !analysisResult.isEmpty && !isAnalyzing && !isLoadingData {
                    PreTradeBottomFloatingInput(
                        followUpQuery: $followUpQuery,
                        isSubmitting: isSubmittingFollowUp,
                        hasHistory: !followUpMessages.isEmpty,
                        onResetThread: {
                            followUpMessages = []
                            followUpQuery = ""
                            let cacheKey = "pretrade_\(selectedSymbol)"
                            AICoachSessionStore.shared.save(key: cacheKey, result: analysisResult, followUps: [])
                        },
                        onSubmit: submitFollowUp
                    )
                }
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
            .fullScreenCover(isPresented: $showFullScreenChart) {
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
        Task { await fetchAllTimeframeBars(for: sym, forceRefresh: true) }
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
            // 1. Fetch freshest H1 candles, or fallback to current h1Bars
            var activeBars = self.h1Bars
            if let freshH1 = try? await MarketDataService.shared.fetchBarsForSymbol(
                symbol: currentSymbol,
                config: dataStore.marketConnections,
                resolution: "1h",
                count: 48,
                forceRefresh: true
            ), !freshH1.bars.isEmpty {
                activeBars = freshH1.bars
                await MainActor.run {
                    self.h1Bars = freshH1.bars
                }
            }
            
            let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
            
            // 2. Capture Real Account, Today's Execution Stats & Prop Firm Buffer
            let sessionSummary = await MainActor.run {
                AIAccountContextProvider.captureContext(dataStore: self.dataStore)
            }
            
            let accName = sessionSummary.accountName ?? "Exness"
            let propFirm = sessionSummary.propFirmName
            let isProp = propFirm != nil && !propFirm!.isEmpty
            let accCategory = isProp
                ? (isVi ? "Quỹ Cấp Vốn (\(propFirm!))" : "Prop Firm (\(propFirm!))")
                : (isVi ? "Tài khoản Cá nhân (\(accName.contains("Exness") ? "Exness" : "Broker"))" : "Personal Brokerage (\(accName.contains("Exness") ? "Exness" : "Broker"))")
            
            let balVal = sessionSummary.balance.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? "N/A"
            let eqVal = sessionSummary.equity.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? balVal
            
            let pnlToday = NSDecimalNumber(decimal: sessionSummary.netPnlToday).doubleValue
            let pnlTodayStr = (pnlToday >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlToday))
            let streakToday = sessionSummary.currentStreakToday
            let streakDesc: String = {
                if streakToday > 0 { return isVi ? "Thắng \(streakToday) lệnh liên tiếp (+)" : "\(streakToday) wins in a row (+)" }
                if streakToday < 0 { return isVi ? "⚠️ Đang thua \(abs(streakToday)) lệnh liên tiếp (-)" : "⚠️ In a \(abs(streakToday))-loss streak (-)" }
                return isVi ? "Chưa có chuỗi lệnh hôm nay" : "No streak today"
            }()
            
            let bufferStr: String = {
                if let buf = sessionSummary.dailyLossBufferRemainingUsd {
                    let limit = sessionSummary.dailyLossLimitUsd.map { String(format: "$%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? (isVi ? "Quy định" : "Rule")
                    let bufVal = (buf as NSDecimalNumber).doubleValue
                    return isVi
                        ? "Hạn mức lỗ ngày: \(limit) | Đệm lỗ còn lại hôm nay: $\(String(format: "%.2f", bufVal))"
                        : "Daily Limit: \(limit) | Remaining Buffer: $\(String(format: "%.2f", bufVal))"
                }
                return isVi ? "Hạn mức rủi ro ngày: Tối đa 2-3 lệnh (2-3% vốn)" : "Daily Risk Budget: Max 2-3 trades (2-3% capital)"
            }()
            
            let isRiskBreached = streakToday <= -2 || (sessionSummary.dailyLossBufferRemainingUsd != nil && sessionSummary.dailyLossBufferRemainingUsd! <= 0)
            let riskAlert = isRiskBreached
                ? (isVi
                    ? "\n🚨 CẢNH BÁO RỦI RO ĐỎ: Trader đang dính chuỗi thua hoặc đệm lỗ ngày đã cạn. AI BẮT BUỘC KHUYẾN NGHỊ ĐỨNG NGOÀI (FLAT), TUYỆT ĐỐI KHÔNG GỢI Ý MỞ LỆNH MỚI!\n"
                    : "\n🚨 CRITICAL RISK GUARDRAIL: Trader is on a losing streak or daily buffer exhausted. AI MUST ADVISE FLAT (STAND ASIDE), NO NEW TRADES!\n")
                : ""
            
            // 3. Multi-Timeframe Context: H4 Context & 15-Candle H1 Series
            let h4EMA = MovingAverageEngine.analyzeTimeframe(bars: self.h4Bars, timeframe: "H4", symbol: currentSymbol)
            let h4_21 = h4EMA?.ema21.map { Formatters.price($0, symbol: currentSymbol) } ?? "N/A"
            let h4_50 = h4EMA?.ema50.map { Formatters.price($0, symbol: currentSymbol) } ?? "N/A"
            let h4Trend = h4EMA?.trend.label ?? "N/A"
            let h4Candles = AIPromptBuilder.buildH4CandleSummary(bars: self.h4Bars, count: 3, isVi: isVi)
            
            let h1Series = AIPromptBuilder.buildH1CandleSeriesSummary(bars: activeBars, count: 15, symbol: currentSymbol, isVi: isVi)
            
            let latestClose = activeBars.last.map { Formatters.price($0.close, symbol: currentSymbol) } ?? "N/A"
            
            var liveContext = ""
            if isVi {
                liveContext = """
                [TRẠNG THÁI TÀI KHOẢN & RỦI RO HÔM NAY]:
                • Tài khoản: \(accName) | Phân loại: \(accCategory) | Nền tảng: cTrader / Terminal
                • Số dư: \(balVal) | Vốn ròng: \(eqVal)
                • Trạng thái lệnh hôm nay: \(sessionSummary.totalTradesToday) lệnh (\(sessionSummary.winsToday) Thắng | \(sessionSummary.lossesToday) Thua | \(sessionSummary.breakevensToday) Hòa) | Đang chạy: \(sessionSummary.openTradesToday)
                • PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakDesc)
                • \(bufferStr)\(riskAlert)
                [CẤU TRÚC ĐA KHUNG VÀ HÀNH ĐỘNG GIÁ THỜI GIAN THỰC]:
                • Cặp tiền: \(currentSymbol) | Thị giá hiện tại: \(latestClose)
                • Khung H4: Xu hướng [\(h4Trend)] | EMA(21) = \(h4_21) | EMA(50) = \(h4_50)
                • 3 nến H4 gần nhất:
                \(h4Candles)

                • Chuỗi 15 nến H1 gần nhất (OHLC + EMA 21/50 + RSI 14):
                \(h1Series)
                """
            } else {
                liveContext = """
                [ACCOUNT & TODAY'S RISK CONTEXT]:
                • Account: \(accName) | Category: \(accCategory) | Platform: cTrader / Terminal
                • Balance: \(balVal) | Equity: \(eqVal)
                • Today's Execution: \(sessionSummary.totalTradesToday) trades (\(sessionSummary.winsToday) W | \(sessionSummary.lossesToday) L | \(sessionSummary.breakevensToday) BE) | Active Open: \(sessionSummary.openTradesToday)
                • Net P&L Today: \(pnlTodayStr) | Current Streak: \(streakDesc)
                • \(bufferStr)\(riskAlert)
                [MULTI-TIMEFRAME & REAL-TIME PRICE ACTION]:
                • Symbol: \(currentSymbol) | Current Price: \(latestClose)
                • H4 Frame: Trend [\(h4Trend)] | EMA(21) = \(h4_21) | EMA(50) = \(h4_50)
                • Recent 3 H4 Bars:
                \(h4Candles)

                • Recent 15-Candle H1 Execution Series (OHLC + EMA 21/50 + Wilder RSI 14):
                \(h1Series)
                """
            }
            
            let attachedImageB64 = userAttachedImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
            
            // Backend context: push condensed initial analysis and live market update invisibly to AI
            var historyToSend: [AICoachMessage] = []
            if !self.analysisResult.isEmpty {
                let condensed = self.analysisResult.count > 1000
                    ? String(self.analysisResult.prefix(1000)) + "\n[...trích lược kế hoạch ban đầu...]"
                    : self.analysisResult
                historyToSend.append(AICoachMessage(role: "assistant", content: condensed))
            }
            historyToSend.append(contentsOf: self.followUpMessages)
            
            var augmentedPrompt = q
            if !liveContext.isEmpty {
                augmentedPrompt = "\(q)\n\n\(liveContext)"
            }
            if isVi {
                augmentedPrompt += """
                
                ⚠️ YÊU CẦU: Trả lời trực diện, ngắn gọn, súc tích bằng tiếng Việt. Đối chiếu biến động giá hiện tại với mốc Invalidation SL và điểm kích hoạt trong kế hoạch ban đầu để xác định kế hoạch còn hiệu lực hay đã bị thị trường bác bỏ.
                """
            } else {
                augmentedPrompt += """
                
                ⚠️ DIRECTIVE: Answer directly and concisely. Cross-reference current price with the structural Invalidation SL and entry triggers from the original plan to state if the thesis remains valid or is invalidated.
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
        
        // Always ensure we have the freshest bars before formulating bias
        await fetchAllTimeframeBars(for: selectedSymbol, forceRefresh: true)
        
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
                
                // Capture account balance for setup record
                let session = AIAccountContextProvider.captureContext(dataStore: self.dataStore)
                let balStr = session.balance.map { Formatters.formatCurrency($0, currency: session.accountCurrency) }
                
                // Persist structured advisor commitment so Trade Coach can automatically link and honor it
                let commitment = AIAdvisorMemoryEngine.shared.extractCommitment(
                    from: response,
                    symbol: self.selectedSymbol,
                    fallbackBalance: balStr
                )
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
