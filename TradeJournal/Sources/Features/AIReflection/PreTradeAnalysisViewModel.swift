import SwiftUI
import UIKit
import Combine

public enum PreTradeFullScreenModal: Identifiable {
    case lightbox(UIImage)
    case landscapeChart

    public var id: String {
        switch self {
        case .lightbox: return "lightbox"
        case .landscapeChart: return "landscapeChart"
        }
    }
}

/// Encapsulates state and business logic for Pre-Trade Multi-Timeframe Analysis
@MainActor
public final class PreTradeAnalysisViewModel: ObservableObject {
    @Published public var selectedSymbol: String
    @Published public var customSymbolText: String = ""
    @Published public var selectedTimeframe: String = "15m" // "15m", "4h", "1d", "all"
    
    @Published public var d1Bars: [MarketBar] = []
    @Published public var h4Bars: [MarketBar] = []
    @Published public var h1Bars: [MarketBar] = []
    @Published public var m15Bars: [MarketBar] = []
    @Published public var activeProvider: String = ""
    
    @Published public var analysisResult: String = ""
    @Published public var currentCommitment: AdvisorCommitmentRecord? = nil
    @Published public var isLoadingData: Bool = false
    @Published public var isAnalyzing: Bool = false
    @Published public var errorMessage: String? = nil
    
    @Published public var followUpMessages: [AICoachMessage] = []
    @Published public var followUpQuery: String = ""
    @Published public var isSubmittingFollowUp: Bool = false
    
    @Published public var activeChartSnapshot: UIImage? = nil
    @Published public var activeFullScreenModal: PreTradeFullScreenModal? = nil
    @Published public var showPhotoPicker: Bool = false
    @Published public var userAttachedImage: UIImage? = nil
    
    @Published public var isSavedToNotebook: Bool = false
    @Published public var showCopiedAlert: Bool = false
    @Published public var showLinkTicketSheet: Bool = false
    @Published public var createdNoteId: String? = nil
    @Published public var isChartInteracting: Bool = false
    
    public init(initialSymbol: String = "XAUUSD") {
        self.selectedSymbol = initialSymbol
    }
    
    public var activeBars: [MarketBar] {
        switch selectedTimeframe {
        case "1d": return d1Bars
        case "4h": return h4Bars
        case "1h": return h1Bars
        default: return m15Bars
        }
    }
    
    public func onSymbolSelected(_ sym: String, dataStore: TradeDataStore) {
        selectedSymbol = sym
        let cacheKey = "pretrade_\(sym)"
        if let cached = AICoachSessionStore.shared.get(key: cacheKey) {
            self.analysisResult = cached.result
            self.followUpMessages = cached.followUps
            self.currentCommitment = extractCommitmentSafely(from: cached.result, symbol: sym, dataStore: dataStore)
        } else {
            self.analysisResult = ""
            self.followUpMessages = []
            self.currentCommitment = nil
        }
        Task { await fetchAllTimeframeBars(for: sym, forceRefresh: true, dataStore: dataStore) }
    }
    
    public func extractCommitmentSafely(from text: String, symbol: String, dataStore: TradeDataStore) -> AdvisorCommitmentRecord? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let session = AIAccountContextProvider.captureContext(dataStore: dataStore)
        let balStr = session.balance.map { Formatters.formatCurrency($0, currency: session.accountCurrency) }
        let riskPct = dataStore.aiSettings.traderProfile.numericRiskPercent
        let targetRR = dataStore.aiSettings.traderProfile.targetRiskRewardRatio
        return AIAdvisorMemoryEngine.shared.extractCommitment(
            from: text,
            symbol: symbol,
            fallbackBalance: balStr,
            accountBalance: session.balance,
            riskPercentage: riskPct,
            targetRiskRewardRatio: targetRR
        )
    }
    
    public func submitCustomSymbol(dataStore: TradeDataStore) {
        let clean = customSymbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        customSymbolText = ""
        onSymbolSelected(clean, dataStore: dataStore)
    }
    
    public func submitFollowUp(dataStore: TradeDataStore) {
        let q = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSubmittingFollowUp else { return }
        
        let userMsg = AICoachMessage(role: "user", content: q)
        self.followUpMessages.append(userMsg)
        self.followUpQuery = ""
        self.isSubmittingFollowUp = true
        
        let currentSymbol = self.selectedSymbol
        
        Task {
            var activeBars = self.h1Bars
            if let freshH1 = try? await AppServices.current.marketData.fetchBarsForSymbol(
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
            let sessionSummary = await MainActor.run {
                AIAccountContextProvider.captureContext(dataStore: dataStore)
            }
            
            let liveContext = self.buildFollowUpLiveContext(
                sessionSummary: sessionSummary,
                currentSymbol: currentSymbol,
                activeBars: activeBars,
                isVi: isVi
            )
            
            let attachedImageB64 = userAttachedImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
            
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
                
                [YEU CAU]: Tra loi truc dien, ngan gon, dung thuat ngu tai chinh. Doi chieu bien dong gia hien tai voi moc Invalidation SL va diem kich hoat trong ke hoach ban dau de xac dinh ke hoach con hieu luc hay da bi thi truong bac bo.
                """
            } else {
                augmentedPrompt += """
                
                [DIRECTIVE]: Answer directly and concisely. Cross-reference current price with the structural Invalidation SL and entry triggers from the original plan to state if the thesis remains valid or is invalidated.
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
    
    public func fetchAllTimeframeBars(for sym: String, forceRefresh: Bool = false, dataStore: TradeDataStore) async {
        await MainActor.run {
            self.isLoadingData = true
            self.errorMessage = nil
            self.isSavedToNotebook = false
        }
        
        let config = dataStore.marketConnections
        
        do {
            async let d1Task = AppServices.current.marketData.fetchBarsForSymbol(symbol: sym, config: config, resolution: "1d", count: 100, forceRefresh: forceRefresh)
            async let h4Task = AppServices.current.marketData.fetchBarsForSymbol(symbol: sym, config: config, resolution: "4h", count: 150, forceRefresh: forceRefresh)
            async let h1Task = AppServices.current.marketData.fetchBarsForSymbol(symbol: sym, config: config, resolution: "1h", count: 150, forceRefresh: forceRefresh)
            async let m15Task = AppServices.current.marketData.fetchBarsForSymbol(symbol: sym, config: config, resolution: "15m", count: 150, forceRefresh: forceRefresh)
            
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
    
    public func runFullAnalysis(dataStore: TradeDataStore) async {
        await MainActor.run {
            self.isAnalyzing = true
            self.errorMessage = nil
        }
        
        await fetchAllTimeframeBars(for: selectedSymbol, forceRefresh: true, dataStore: dataStore)
        
        guard !d1Bars.isEmpty || !h4Bars.isEmpty || !h1Bars.isEmpty || !m15Bars.isEmpty else {
            await MainActor.run {
                self.errorMessage = dataStore.aiSettings.language == "vi"
                    ? "Không thể tải dữ liệu nến cho \(selectedSymbol). Vui lòng thử lại sau giây lát."
                    : "Unable to stream candle data for \(selectedSymbol). Please retry in a moment."
                self.isAnalyzing = false
            }
            return
        }
        
        do {
            let response = try await AIReflectionService.shared.requestPreTradeMarketAnalysis(
                symbol: selectedSymbol,
                d1Bars: d1Bars,
                h4Bars: h4Bars,
                h1Bars: h1Bars,
                m15Bars: m15Bars,
                language: dataStore.aiSettings.language,
                chartImageBase64: nil,
                chartImagesBase64: nil,
                conversationHistory: followUpMessages,
                previousAnalysis: nil
            )
            await MainActor.run {
                self.analysisResult = response
                self.isAnalyzing = false
                let cacheKey = "pretrade_\(self.selectedSymbol)"
                AICoachSessionStore.shared.save(key: cacheKey, result: response, followUps: self.followUpMessages)
                
                let session = AIAccountContextProvider.captureContext(dataStore: dataStore)
                let balStr = session.balance.map { Formatters.formatCurrency($0, currency: session.accountCurrency) }
                let riskPct = dataStore.aiSettings.traderProfile.numericRiskPercent
                let targetRR = dataStore.aiSettings.traderProfile.targetRiskRewardRatio
                
                let commitment = AIAdvisorMemoryEngine.shared.extractCommitment(
                    from: response,
                    symbol: self.selectedSymbol,
                    fallbackBalance: balStr,
                    accountBalance: session.balance,
                    riskPercentage: riskPct,
                    targetRiskRewardRatio: targetRR
                )
                self.currentCommitment = commitment
                AIAdvisorMemoryEngine.shared.saveCommitment(commitment)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    public func fullAnalysisContent() -> String {
        var fullText = AIDocumentParser.stripTechnicalMetadata(from: analysisResult)
        let followUps = followUpMessages.filter { $0.content != analysisResult }
        if !followUps.isEmpty {
            fullText += "\n\n### Follow-Up Discussion\n"
            for msg in followUps {
                if msg.role == "user" {
                    fullText += "\n• **Trader**: \(msg.content)\n"
                } else {
                    fullText += "\n• **Risk AI**: \(AIDocumentParser.stripTechnicalMetadata(from: msg.content))\n"
                }
            }
        }
        return fullText
    }
    
    public func saveToNotebook(dataStore: TradeDataStore) {
        guard !analysisResult.isEmpty else { return }
        let dateStr = JournalIds.todayDateString()
        let title = "[Pre-Trade Bias] \(selectedSymbol) (\(dateStr))"
        let tags = ["#pre-trade-bias", "#market-structure", "#\(selectedSymbol.lowercased())"]
        if let note = dataStore.upsertNotebookNoteInFolder(
            folderName: "Trade Insights",
            existingNoteId: createdNoteId,
            title: title,
            content: fullAnalysisContent(),
            tags: tags,
            dayDate: dateStr
        ) {
            createdNoteId = note.id
            isSavedToNotebook = true
        }
    }
    
    public func copyToClipboard() {
        TradeDataStore.copyToClipboard(fullAnalysisContent()) { [weak self] show in
            Task { @MainActor in
                self?.showCopiedAlert = show
            }
        }
    }
    
    private func buildFollowUpLiveContext(
        sessionSummary: AIAccountSessionSummary,
        currentSymbol: String,
        activeBars: [MarketBar],
        isVi: Bool
    ) -> String {
        let accName = sessionSummary.accountName ?? "Exness"
        let propFirm = sessionSummary.propFirmName
        let isProp = propFirm?.isEmpty == false
        let firmName = propFirm ?? ""
        let accCategory = isProp
            ? (isVi ? "Quỹ Cấp Vốn (\(firmName))" : "Prop Firm (\(firmName))")
            : (isVi ? "Tài khoản Cá nhân (\(accName.contains("Exness") ? "Exness" : "Broker"))" : "Personal Brokerage (\(accName.contains("Exness") ? "Exness" : "Broker"))")
        
        let balVal = sessionSummary.balance.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? "N/A"
        let eqVal = sessionSummary.equity.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? balVal
        
        let pnlTodayStr = Formatters.formatPnL(sessionSummary.netPnlToday, currency: sessionSummary.accountCurrency)
        let streakToday = sessionSummary.currentStreakToday
        let streakDesc: String = {
            if streakToday > 0 { return isVi ? "Thắng \(streakToday) lệnh liên tiếp (+)" : "\(streakToday) wins in a row (+)" }
            if streakToday < 0 { return isVi ? "Đang thua \(abs(streakToday)) lệnh liên tiếp (-)" : "In a \(abs(streakToday))-loss streak (-)" }
            return isVi ? "Chưa có chuỗi lệnh hôm nay" : "No streak today"
        }()
        
        let bufferStr: String = {
            if let buf = sessionSummary.dailyLossBufferRemainingUsd {
                let limit = sessionSummary.dailyLossLimitUsd.map { Formatters.formatCurrency($0, currency: "USD") } ?? (isVi ? "Quy định" : "Rule")
                let formattedBuf = Formatters.formatCurrency(buf, currency: "USD")
                return isVi
                    ? "Hạn mức lỗ ngày: \(limit) | Đệm lỗ còn lại hôm nay: \(formattedBuf)"
                    : "Daily Limit: \(limit) | Remaining Buffer: \(formattedBuf)"
            }
            return isVi ? "Hạn mức rủi ro ngày: Tối đa 2-3 lệnh (2-3% vốn)" : "Daily Risk Budget: Max 2-3 trades (2-3% capital)"
        }()
        
        let isRiskBreached = streakToday <= -2 || (sessionSummary.dailyLossBufferRemainingUsd.map { $0 <= 0 } ?? false)
        let riskAlert = isRiskBreached
            ? (isVi
                ? "\n[CẢNH BÁO RỦI RO]: Trader đang có chuỗi thua hoặc đệm lỗ ngày đã chạm ngưỡng. AI BẮT BUỘC KHUYẾN NGHỊ ĐỨNG NGOÀI (FLAT), KHÔNG MỞ LỆNH MỚI.\n"
                : "\n[CRITICAL RISK GUARDRAIL]: Trader is on a losing streak or daily buffer exhausted. AI MUST ADVISE FLAT (STAND ASIDE), NO NEW TRADES.\n")
            : ""
        
        let h4High = self.h4Bars.suffix(24).map(\.high).max().map { Formatters.price($0, symbol: currentSymbol) } ?? "N/A"
        let h4Low = self.h4Bars.suffix(24).map(\.low).min().map { Formatters.price($0, symbol: currentSymbol) } ?? "N/A"
        let h4Candles = AIPromptBuilder.buildH4CandleSummary(bars: self.h4Bars, count: 3, isVi: isVi)
        let h1Series = AIPromptBuilder.buildH1CandleSeriesSummary(bars: activeBars, count: 15, symbol: currentSymbol, isVi: isVi)
        let latestClose = activeBars.last.map { Formatters.price($0.close, symbol: currentSymbol) } ?? "N/A"
        
        if isVi {
            return """
            [TRẠNG THÁI TÀI KHOẢN & RỦI RO HÔM NAY]:
            • Tài khoản: \(accName) | Phân loại: \(accCategory) | Nền tảng: cTrader / Terminal
            • Số dư: \(balVal) | Vốn ròng: \(eqVal)
            • Trạng thái lệnh hôm nay: \(sessionSummary.totalTradesToday) lệnh (\(sessionSummary.winsToday) Thắng | \(sessionSummary.lossesToday) Thua | \(sessionSummary.breakevensToday) Hòa) | Đang chạy: \(sessionSummary.openTradesToday)
            • PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakDesc)
            • \(bufferStr)\(riskAlert)
            [CẤU TRÚC ĐA KHUNG VÀ HÀNH ĐỘNG GIÁ THỜI GIAN THỰC]:
            • Cặp tiền: \(currentSymbol) | Thị giá hiện tại: \(latestClose)
            • Khung H4: Biên độ 24 nến: Cao nhất = \(h4High) | Thấp nhất = \(h4Low)
            • 3 nến H4 gần nhất:
            \(h4Candles)

            • Chuỗi 15 nến H1 gần nhất (OHLC + Wilder RSI 14):
            \(h1Series)
            """
        } else {
            return """
            [ACCOUNT & TODAY'S RISK CONTEXT]:
            • Account: \(accName) | Category: \(accCategory) | Platform: cTrader / Terminal
            • Balance: \(balVal) | Equity: \(eqVal)
            • Today's Execution: \(sessionSummary.totalTradesToday) trades (\(sessionSummary.winsToday) W | \(sessionSummary.lossesToday) L | \(sessionSummary.breakevensToday) BE) | Active Open: \(sessionSummary.openTradesToday)
            • Net P&L Today: \(pnlTodayStr) | Current Streak: \(streakDesc)
            • \(bufferStr)\(riskAlert)
            [MULTI-TIMEFRAME & REAL-TIME PRICE ACTION]:
            • Symbol: \(currentSymbol) | Current Price: \(latestClose)
            • H4 Frame: 24-Bar Range: High = \(h4High) | Low = \(h4Low)
            • Recent 3 H4 Bars:
            \(h4Candles)

            • Recent 15-Candle H1 Execution Series (OHLC + Wilder RSI 14):
            \(h1Series)
            """
        }
    }
}
