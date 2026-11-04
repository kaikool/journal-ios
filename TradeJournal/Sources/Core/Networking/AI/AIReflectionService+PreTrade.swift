import Foundation

// MARK: - Pre-Trade Multi-Timeframe Analysis Request (3-Model Consensus Ensemble)
extension AIReflectionService {
    
    // MARK: - Safe Model Execution for Multi-Model Ensemble
    private func callModelSafe(
        endpoint: String,
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String,
        metrics: TradeMetrics?,
        language: String,
        traderProfile: TraderProfileConfig?,
        sessionSummary: AIAccountSessionSummary?,
        conversationHistory: [AICoachMessage]?
    ) async -> String? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            return try await callOpenAiCompatible(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                action: action,
                prompt: prompt,
                metrics: metrics,
                edgeScore: nil,
                language: language,
                traderProfile: traderProfile,
                chartImageBase64: nil,
                chartImagesBase64: nil,
                sessionSummary: sessionSummary,
                conversationHistory: conversationHistory
            )
        } catch {
            AppLogger.warning("Ensemble worker '\(model)' encountered error: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func requestPreTradeMarketAnalysis(
        symbol: String,
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar],
        language: String? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        conversationHistory: [AICoachMessage] = [],
        previousAnalysis: String? = nil
    ) async throws -> String {
        let (config, sessionSummary, metrics, traderProfile, displayTimeZone, events, historicalTrades) = await MainActor.run { () -> (AiSettingsConfig, AIAccountSessionSummary, TradeMetrics, TraderProfileConfig, String, [ForexFactoryEvent], [Trade]) in
            let ds = TradeDataStore.shared
            let cfg = ds.aiSettings
            let summary = AIAccountContextProvider.captureContext(dataStore: ds)
            let m = FinancialMetricsEngine.computeMetrics(trades: ds.filteredTrades)
            let prof = cfg.traderProfile
            let tz = ds.generalSettings.displayTimeZone
            let evs = ForexFactoryService.shared.usdEvents
            let trades = ds.trades
            return (cfg, summary, m, prof, tz, evs, trades)
        }
        
        let activeLang = language ?? config.language
        let isVi = activeLang == "vi"
        let hasImage = (chartImageBase64?.isEmpty == false) || (chartImagesBase64?.isEmpty == false)
        let prompt = AIPromptBuilder.buildPreTradeAnalysisPrompt(
            symbol: symbol,
            d1Bars: d1Bars,
            h4Bars: h4Bars,
            h1Bars: h1Bars,
            m15Bars: m15Bars,
            events: events,
            language: activeLang,
            sessionSummary: sessionSummary,
            traderProfile: traderProfile,
            displayTimeZone: displayTimeZone,
            previousAnalysis: previousAnalysis,
            hasImage: hasImage,
            historicalTrades: historicalTrades
        )
        
        // 1. Resolve API Keys for Ensemble Execution
        let groqKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
        let groqBackupKey = config.groqBackupKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqBackupKey : config.groqBackupKey.trimmingCharacters(in: .whitespaces)
        let geminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
        let effectiveGroqKey = !groqKey.isEmpty ? groqKey : groqBackupKey
        
        // 2. Multi-Model Parallel Ensemble: Run 3 independent workers concurrently
        if !effectiveGroqKey.isEmpty {
            async let worker1 = self.callModelSafe(
                endpoint: Self.groqEndpoint,
                apiKey: effectiveGroqKey,
                model: "openai/gpt-oss-120b",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: traderProfile,
                sessionSummary: sessionSummary,
                conversationHistory: conversationHistory
            )
            async let worker2 = self.callModelSafe(
                endpoint: Self.groqEndpoint,
                apiKey: effectiveGroqKey,
                model: "qwen/qwen3.8-27b",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: traderProfile,
                sessionSummary: sessionSummary,
                conversationHistory: conversationHistory
            )
            async let worker3 = self.callModelSafe(
                endpoint: Self.geminiEndpoint,
                apiKey: geminiKey,
                model: "gemini-3.5-flash-lite",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: traderProfile,
                sessionSummary: sessionSummary,
                conversationHistory: conversationHistory
            )
            
            let (res1, res2, res3) = await (worker1, worker2, worker3)
            let validAnalyses = [res1, res2, res3].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            if validAnalyses.count >= 2 {
                let currentPriceStr: String = {
                    if let lastBar = m15Bars.last ?? h1Bars.last ?? h4Bars.last ?? d1Bars.last {
                        let d = (lastBar.close as NSDecimalNumber).doubleValue
                        if d >= 1000 { return String(format: "%.2f", d) }
                        if d >= 100 { return String(format: "%.2f", d) }
                        if d >= 10 { return String(format: "%.3f", d) }
                        return String(format: "%.5f", d)
                    }
                    return "Market Price"
                }()
                
                let balStr = sessionSummary.balance.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? "$100,000.00"
                let riskNum = traderProfile.numericRiskPercent
                let targetRiskDollars: Decimal = {
                    if let bal = sessionSummary.balance, bal > 0 {
                        return bal * (riskNum / 100)
                    }
                    return 0
                }()
                let targetRiskDollarsStr = String(format: "$%.2f", (targetRiskDollars as NSDecimalNumber).doubleValue)
                
                func fmtP(_ p: Decimal?) -> String {
                    guard let p = p else { return "N/A" }
                    return Formatters.price(p, symbol: symbol)
                }
                
                let d1High = d1Bars.suffix(2).first?.high
                let d1Low = d1Bars.suffix(2).first?.low
                let h4High = h4Bars.suffix(24).map(\.high).max()
                let h4Low = h4Bars.suffix(24).map(\.low).min()
                
                let execBars = !h1Bars.isEmpty ? h1Bars : m15Bars
                let momWin = MomentumEngine.computeWindow(bars: execBars, windowSize: 15)
                let rVal = momWin.currentRSI.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
                let eVal = momWin.currentEMA9.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
                let wVal = momWin.currentWMA45.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
                let alignStr = isVi ? momWin.alignmentVi : momWin.alignmentEn
                let emaWmaStr = isVi ? momWin.emaVsWmaVi : momWin.emaVsWmaEn
                let divStr = isVi ? (momWin.divergenceVi ?? "Không có phân kỳ") : (momWin.divergenceEn ?? "None")
                
                let technicalGroundTruth = isVi ? """
                • D1:  Đỉnh PDH = \(fmtP(d1High)) | Đáy PDL = \(fmtP(d1Low))
                • H4:  Biên độ 24 nến: Cao nhất = \(fmtP(h4High)) | Thấp nhất = \(fmtP(h4Low))
                • Động lượng 3 đường RSI H1: RSI(14) = \(rVal) | EMA(9) = \(eVal) | WMA(45) = \(wVal)
                • Trạng thái 3 đường RSI: \(alignStr)
                • Nền động lượng (EMA 9 vs WMA 45): \(emaWmaStr)
                • Phân kỳ RSI: \(divStr)
                """ : """
                • D1:  PDH = \(fmtP(d1High)) | PDL = \(fmtP(d1Low))
                • H4:  24-Bar Range: High = \(fmtP(h4High)) | Low = \(fmtP(h4Low))
                • H1 3-Line RSI Momentum: RSI(14) = \(rVal) | EMA(9) = \(eVal) | WMA(45) = \(wVal)
                • 3-Line RSI Alignment: \(alignStr)
                • Momentum Baseline (EMA 9 vs WMA 45): \(emaWmaStr)
                • RSI Divergence: \(divStr)
                """
                
                let synthesisPrompt = AIPromptBuilder.buildEnsembleSynthesisPrompt(
                    symbol: symbol,
                    currentPrice: currentPriceStr,
                    balance: balStr,
                    riskDollars: targetRiskDollarsStr,
                    riskPercent: riskNum,
                    targetRR: traderProfile.targetRiskRewardRatio,
                    analyses: validAnalyses,
                    isVi: isVi,
                    technicalGroundTruth: technicalGroundTruth
                )
                
                // VÒNG 2: Chief Risk Officer Synthesizer (Qwen-27B on Groq, fallback to GPT-120B then Gemini)
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.groqEndpoint,
                        apiKey: effectiveGroqKey,
                        model: "qwen/qwen3.8-27b",
                        action: .critique,
                        prompt: synthesisPrompt,
                        metrics: metrics,
                        edgeScore: nil,
                        language: activeLang,
                        traderProfile: traderProfile,
                        chartImageBase64: nil,
                        chartImagesBase64: nil,
                        sessionSummary: nil,
                        conversationHistory: nil
                    )
                } catch {
                    AppLogger.warning("Qwen ensemble synthesis failed: \(error.localizedDescription). Falling back to GPT-120B...")
                    do {
                        return try await callOpenAiCompatible(
                            endpoint: Self.groqEndpoint,
                            apiKey: effectiveGroqKey,
                            model: "openai/gpt-oss-120b",
                            action: .critique,
                            prompt: synthesisPrompt,
                            metrics: metrics,
                            edgeScore: nil,
                            language: activeLang,
                            traderProfile: traderProfile,
                            chartImageBase64: nil,
                            chartImagesBase64: nil,
                            sessionSummary: nil,
                            conversationHistory: nil
                        )
                    } catch {
                        AppLogger.warning("Groq ensemble synthesis failed: \(error.localizedDescription). Falling back to Gemini synthesis...")
                        if !geminiKey.isEmpty {
                            do {
                                return try await callOpenAiCompatible(
                                    endpoint: Self.geminiEndpoint,
                                    apiKey: geminiKey,
                                    model: "gemini-3.5-flash-lite",
                                    action: .critique,
                                    prompt: synthesisPrompt,
                                    metrics: metrics,
                                    edgeScore: nil,
                                    language: activeLang,
                                    traderProfile: traderProfile,
                                    chartImageBase64: nil,
                                    chartImagesBase64: nil,
                                    sessionSummary: nil,
                                    conversationHistory: nil
                                )
                            } catch {
                                AppLogger.warning("Gemini ensemble synthesis failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                if let best = validAnalyses.first {
                    return best
                }
            } else if let single = validAnalyses.first {
                return single
            }
        }
        
        // Single provider or fallback pipeline
        return try await requestReflection(
            action: .critique,
            prompt: prompt,
            metrics: metrics,
            edgeScore: nil,
            language: activeLang,
            chartImageBase64: chartImageBase64,
            chartImagesBase64: chartImagesBase64,
            sessionSummary: nil,
            conversationHistory: conversationHistory
        )
    }
}
