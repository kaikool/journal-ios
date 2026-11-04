import Foundation

// MARK: - Pre-Trade Multi-Timeframe Analysis Request (3-Model Consensus Ensemble)
extension AIReflectionService {

    // MARK: - Unified Multi-Model Parallel Ensemble Execution & Synthesis
    func resolveEnsembleApiKeys(from config: AiSettingsConfig) -> (groq: String, gemini: String) {
        let groqKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
        let groqBackupKey = config.groqBackupKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqBackupKey : config.groqBackupKey.trimmingCharacters(in: .whitespaces)
        let geminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
        let effectiveGroqKey = !groqKey.isEmpty ? groqKey : groqBackupKey
        return (effectiveGroqKey, geminiKey)
    }

    func runParallelEnsembleWorkers(
        groqKey: String,
        geminiKey: String,
        prompt: String,
        metrics: TradeMetrics?,
        language: String,
        traderProfile: TraderProfileConfig?,
        sessionSummary: AIAccountSessionSummary?,
        conversationHistory: [AICoachMessage]?
    ) async -> [String] {
        guard !groqKey.isEmpty else { return [] }
        async let worker1 = self.callModelSafe(
            endpoint: Self.groqEndpoint,
            apiKey: groqKey,
            model: "openai/gpt-oss-120b",
            action: .critique,
            prompt: prompt,
            metrics: metrics,
            language: language,
            traderProfile: traderProfile,
            sessionSummary: sessionSummary,
            conversationHistory: conversationHistory
        )
        async let worker2 = self.callModelSafe(
            endpoint: Self.groqEndpoint,
            apiKey: groqKey,
            model: "qwen/qwen3.8-27b",
            action: .critique,
            prompt: prompt,
            metrics: metrics,
            language: language,
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
            language: language,
            traderProfile: traderProfile,
            sessionSummary: sessionSummary,
            conversationHistory: conversationHistory
        )
        let (res1, res2, res3) = await (worker1, worker2, worker3)
        return [res1, res2, res3].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func runEnsembleSynthesizer(
        synthesisPrompt: String,
        validAnalyses: [String],
        groqKey: String,
        geminiKey: String,
        metrics: TradeMetrics?,
        language: String,
        traderProfile: TraderProfileConfig?,
        sessionSummary: AIAccountSessionSummary?,
        conversationHistory: [AICoachMessage]?
    ) async -> String? {
        // VÒNG 2: Chief Risk Officer Synthesizer (Qwen-27B on Groq, fallback to GPT-120B then Gemini)
        do {
            return try await callOpenAiCompatible(
                endpoint: Self.groqEndpoint,
                apiKey: groqKey,
                model: "qwen/qwen3.8-27b",
                action: .critique,
                prompt: synthesisPrompt,
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
            AppLogger.warning("Qwen ensemble synthesis failed: \(error.localizedDescription). Falling back to GPT-120B...")
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: groqKey,
                    model: "openai/gpt-oss-120b",
                    action: .critique,
                    prompt: synthesisPrompt,
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
                            language: language,
                            traderProfile: traderProfile,
                            chartImageBase64: nil,
                            chartImagesBase64: nil,
                            sessionSummary: sessionSummary,
                            conversationHistory: conversationHistory
                        )
                    } catch {
                        AppLogger.warning("Gemini ensemble synthesis failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        return validAnalyses.first
    }

    func callModelSafe(
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

    // MARK: - Dedicated Single Trade AI Coaching
    public func requestTradeCoaching(
        trade: Trade,
        language: String? = nil,
        recentCandlesSummary: String? = nil,
        bars: [MarketBar]? = nil,
        chartImageBase64: String? = nil,
        linkedPreTradePlan: AdvisorCommitmentRecord? = nil
    ) async throws -> String {
        let (config, sessionSummary, metrics, displayTimeZone) = await MainActor.run { () -> (AiSettingsConfig, AIAccountSessionSummary, TradeMetrics, String) in
            let ds = TradeDataStore.shared
            let cfg = ds.aiSettings
            let summary = AIAccountContextProvider.captureContext(targetAccountId: trade.accountId, dataStore: ds)
            let accountTrades = trade.accountId.isEmpty ? ds.trades : ds.trades.filter { TradeDataStore.isSameAccountId($0.accountId, trade.accountId) }
            let m = FinancialMetricsEngine.computeMetrics(trades: accountTrades)
            let tz = ds.generalSettings.displayTimeZone
            return (cfg, summary, m, tz)
        }
        let activeLang = language ?? config.language
        let isVi = activeLang == "vi"

        let footprintData = await { () -> (levels: [KeyLevel], profiles: [SessionProfileSnapshot], devList: [DevelopingProfile], patterns: [DetectedCandlePattern]) in
            guard let b = bars, !b.isEmpty else { return ([], [], [], []) }
            let res = await SessionFootprintCoordinator.shared.loadKeyLevels(for: trade.symbol, recentBars: b)
            let pats = SessionFootprintCoordinator.shared.scanConfluentPatterns(bars: b, keyLevels: res.levels)
            return (res.levels, res.profiles, res.developingProfiles, pats)
        }()

        let prompt = AIPromptBuilder.buildTradeCoachingPrompt(
            trade: trade,
            isVi: isVi,
            recentCandlesSummary: recentCandlesSummary,
            bars: bars,
            sessionSummary: sessionSummary,
            displayTimeZone: displayTimeZone,
            linkedPreTradePlan: linkedPreTradePlan,
            keyLevels: footprintData.levels,
            sessionProfiles: footprintData.profiles,
            developingProfiles: footprintData.devList,
            detectedPatterns: footprintData.patterns
        )
        
        let keys = resolveEnsembleApiKeys(from: config)
        let validAnalyses = await runParallelEnsembleWorkers(
            groqKey: keys.groq,
            geminiKey: keys.gemini,
            prompt: prompt,
            metrics: metrics,
            language: activeLang,
            traderProfile: nil,
            sessionSummary: sessionSummary,
            conversationHistory: nil
        )
        
        if validAnalyses.count >= 2 {
            let synthesisPrompt = AIPromptBuilder.buildCoachingEnsembleSynthesisPrompt(
                trade: trade,
                analyses: validAnalyses,
                isVi: isVi
            )
            if let synthesized = await runEnsembleSynthesizer(
                synthesisPrompt: synthesisPrompt,
                validAnalyses: validAnalyses,
                groqKey: keys.groq,
                geminiKey: keys.gemini,
                metrics: metrics,
                language: activeLang,
                traderProfile: nil,
                sessionSummary: sessionSummary,
                conversationHistory: nil
            ) {
                return synthesized
            }
        } else if let single = validAnalyses.first {
            return single
        }
        
        return try await requestReflection(
            action: .critique,
            prompt: prompt,
            metrics: metrics,
            edgeScore: nil,
            language: activeLang,
            chartImageBase64: chartImageBase64,
            sessionSummary: sessionSummary
        )
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
        
        let keys = resolveEnsembleApiKeys(from: config)
        let validAnalyses = await runParallelEnsembleWorkers(
            groqKey: keys.groq,
            geminiKey: keys.gemini,
            prompt: prompt,
            metrics: metrics,
            language: activeLang,
            traderProfile: traderProfile,
            sessionSummary: sessionSummary,
            conversationHistory: conversationHistory
        )
        
        if validAnalyses.count >= 2 {
            let currentPriceStr = (m15Bars.last ?? h1Bars.last ?? h4Bars.last ?? d1Bars.last).map { Formatters.rawPrice($0.close) } ?? "Market Price"
            let balStr = sessionSummary.balance.map { Formatters.formatCurrency($0, currency: sessionSummary.accountCurrency) } ?? "$100,000.00"
            let riskNum = traderProfile.numericRiskPercent
            let targetRiskDollars: Decimal = {
                if let bal = sessionSummary.balance, bal > 0 {
                    return bal * (riskNum / 100)
                }
                return 0
            }()
            let targetRiskDollarsStr = String(format: "$%.2f", (targetRiskDollars as NSDecimalNumber).doubleValue)
            
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
            • D1:  Đỉnh PDH = \(Formatters.price(d1High, symbol: symbol)) | Đáy PDL = \(Formatters.price(d1Low, symbol: symbol))
            • H4:  Biên độ 24 nến: Cao nhất = \(Formatters.price(h4High, symbol: symbol)) | Thấp nhất = \(Formatters.price(h4Low, symbol: symbol))
            • Động lượng 3 đường RSI H1: RSI(14) = \(rVal) | EMA(9) = \(eVal) | WMA(45) = \(wVal)
            • Trạng thái 3 đường RSI: \(alignStr)
            • Nền động lượng (EMA 9 vs WMA 45): \(emaWmaStr)
            • Phân kỳ RSI: \(divStr)
            """ : """
            • D1:  PDH = \(Formatters.price(d1High, symbol: symbol)) | PDL = \(Formatters.price(d1Low, symbol: symbol))
            • H4:  24-Bar Range: High = \(Formatters.price(h4High, symbol: symbol)) | Low = \(Formatters.price(h4Low, symbol: symbol))
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
            
            if let synthesized = await runEnsembleSynthesizer(
                synthesisPrompt: synthesisPrompt,
                validAnalyses: validAnalyses,
                groqKey: keys.groq,
                geminiKey: keys.gemini,
                metrics: metrics,
                language: activeLang,
                traderProfile: traderProfile,
                sessionSummary: nil,
                conversationHistory: nil
            ) {
                return synthesized
            }
        } else if let single = validAnalyses.first {
            return single
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
