import Foundation

/// Central coordinator for AI Trading Reflection, Risk Management Audits & Coaching
/// Supports multi-provider inference (Groq, OpenAI, Gemini, OpenRouter, Anthropic, Custom)
/// with automated multi-tier failover and offline heuristic fallback.
public actor AIReflectionService {
    public static let shared = AIReflectionService()
    
    // Official API endpoints
    public static let githubEndpoint = "https://models.github.ai/inference/chat/completions"
    public static let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    public static let groqEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    public static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    public static let openAiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    /// Requests AI reflection via user-configured AI provider (Gemini, Groq, OpenRouter, OpenAI, Anthropic, Custom)
    /// Gracefully falls back to bulletproof fallback pipeline if unconfigured or offline.
    public func requestReflection(
        action: AIReflectionAction,
        prompt: String? = nil,
        metrics: TradeMetrics? = nil,
        edgeScore: Double? = nil,
        supabaseUrl: String? = nil,
        authToken: String? = nil,
        overrideConfig: AiSettingsConfig? = nil,
        language: String? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        conversationHistory: [AICoachMessage]? = nil
    ) async throws -> String {
        var config: AiSettingsConfig
        if let override = overrideConfig {
            config = override
        } else {
            config = await MainActor.run { TradeDataStore.shared.aiSettings }
        }
        if let lang = language {
            config.language = lang
        }
        let activeLang = config.language.isEmpty ? "vi" : config.language
        let profile = config.traderProfile
        
        let (activeSessionSummary, activeMetrics) = await MainActor.run { () -> (AIAccountSessionSummary, TradeMetrics?) in
            let summary = sessionSummary ?? AIAccountContextProvider.captureContext()
            let m = metrics ?? FinancialMetricsEngine.computeMetrics(trades: TradeDataStore.shared.trades)
            return (summary, m)
        }
        
        switch config.provider {
        case "github":
            if !config.githubKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.githubEndpoint,
                        apiKey: config.githubKey,
                        model: config.model.isEmpty ? "gpt-4o" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("GitHub Models failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
        case "gemini":
            if !config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    let geminiModel: String = {
                        let m = config.model.trimmingCharacters(in: .whitespaces)
                        if m.isEmpty || m == "gemini-2.0-flash" || m == "gemini-1.5-flash" || m == "gemini-2.5-flash" {
                            return "gemini-3.5-flash-lite"
                        }
                        return m
                    }()
                    return try await callOpenAiCompatible(
                        endpoint: Self.geminiEndpoint,
                        apiKey: config.geminiKey,
                        model: geminiModel,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("Gemini failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
        case "groq":
            let activeKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            let (primaryGroqModel, fallbackGroqModel) = Self.resolveOptimalGroqModel(action: action, userRequestedModel: config.model)
            
            // Multimodal Vision: If chart image is attached and user has custom OpenRouter key, try vision model
            let hasImages = (chartImagesBase64 != nil && !chartImagesBase64!.isEmpty)
            let hasSingle = (chartImageBase64 != nil && !chartImageBase64!.isEmpty)
            let customOrKey = config.openrouterKey.trimmingCharacters(in: .whitespaces)
            let hasCustomOrKey = !customOrKey.isEmpty && customOrKey != AiSettingsConfig.defaultOpenRouterKey
            if (hasImages || hasSingle) && hasCustomOrKey {
                let (visionModel, _) = Self.resolveOptimalOpenRouterModel(action: action, hasImages: true, userRequestedModel: "")
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.openRouterEndpoint,
                        apiKey: customOrKey,
                        model: visionModel,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("Multimodal vision request with '\(visionModel)' failed: \(error.localizedDescription). Proceeding with deep numerical & structural risk audit via Groq...")
                }
            }
            
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: activeKey,
                    model: primaryGroqModel,
                    action: action,
                    prompt: prompt,
                    metrics: activeMetrics,
                    edgeScore: edgeScore,
                    language: activeLang,
                    traderProfile: profile,
                    chartImageBase64: nil,
                    sessionSummary: activeSessionSummary,
                    conversationHistory: conversationHistory
                )
            } catch {
                let nsError = error as NSError
                let isRateLimitOrAuth = (nsError.code == 429 || nsError.code == 401 || error.localizedDescription.contains("429") || error.localizedDescription.localizedCaseInsensitiveContains("rate limit"))
                
                AppLogger.warning("Groq request with primary model '\(primaryGroqModel)' failed: \(error.localizedDescription) (rateLimitOrAuth: \(isRateLimitOrAuth))")
                
                let backupKey = config.groqBackupKey.trimmingCharacters(in: .whitespaces)
                let effectiveBackupKey = backupKey.isEmpty ? AiSettingsConfig.defaultGroqBackupKey : backupKey
                
                // If primary key encountered a rate limit (HTTP 429) or auth error (401), IMMEDIATELY fail over to backup key
                if isRateLimitOrAuth && !effectiveBackupKey.isEmpty && effectiveBackupKey != activeKey {
                    AppLogger.warning("Primary Groq key rate limited/unauthorized. Failing over IMMEDIATELY to backup Groq key...")
                    for bModel in [primaryGroqModel, fallbackGroqModel, "openai/gpt-oss-20b"] {
                        do {
                            return try await callOpenAiCompatible(
                                endpoint: Self.groqEndpoint,
                                apiKey: effectiveBackupKey,
                                model: bModel,
                                action: action,
                                prompt: prompt,
                                metrics: activeMetrics,
                                edgeScore: edgeScore,
                                language: activeLang,
                                traderProfile: profile,
                                chartImageBase64: nil,
                                sessionSummary: activeSessionSummary,
                                conversationHistory: conversationHistory
                            )
                        } catch {
                            AppLogger.warning("Backup Groq key with model '\(bModel)' also failed: \(error.localizedDescription)")
                        }
                    }
                }
                
                // If not a key-level rate limit, try alternative resilient models on activeKey
                if !isRateLimitOrAuth {
                    for fbModel in [fallbackGroqModel, "openai/gpt-oss-20b"] {
                        do {
                            return try await callOpenAiCompatible(
                                endpoint: Self.groqEndpoint,
                                apiKey: activeKey,
                                model: fbModel,
                                action: action,
                                prompt: prompt,
                                metrics: activeMetrics,
                                edgeScore: edgeScore,
                                language: activeLang,
                                traderProfile: profile,
                                chartImageBase64: nil,
                                sessionSummary: activeSessionSummary,
                                conversationHistory: conversationHistory
                            )
                        } catch {
                            AppLogger.warning("Active Groq key fallback model '\(fbModel)' failed: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Retry with backup Groq key across models if not already tried above
                if !isRateLimitOrAuth && !effectiveBackupKey.isEmpty && effectiveBackupKey != activeKey {
                    AppLogger.warning("Retrying with backup Groq key...")
                    for bModel in [primaryGroqModel, fallbackGroqModel, "openai/gpt-oss-20b"] {
                        do {
                            return try await callOpenAiCompatible(
                                endpoint: Self.groqEndpoint,
                                apiKey: effectiveBackupKey,
                                model: bModel,
                                action: action,
                                prompt: prompt,
                                metrics: activeMetrics,
                                edgeScore: edgeScore,
                                language: activeLang,
                                traderProfile: profile,
                                chartImageBase64: nil,
                                sessionSummary: activeSessionSummary,
                                conversationHistory: conversationHistory
                            )
                        } catch {
                            AppLogger.warning("Backup Groq key model '\(bModel)' failed: \(error.localizedDescription)")
                        }
                    }
                }
                
                AppLogger.warning("All immediate Groq attempts exhausted. Retrying with active discovery and failover pipeline...")
                return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            }
            
        case "openrouter":
            let activeKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
            let hasImages = (chartImagesBase64 != nil && !chartImagesBase64!.isEmpty) || (chartImageBase64 != nil && !chartImageBase64!.isEmpty)
            let (primaryORModel, fallbackORModel) = Self.resolveOptimalOpenRouterModel(action: action, hasImages: hasImages, userRequestedModel: config.model)
            
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: activeKey,
                    model: primaryORModel,
                    action: action,
                    prompt: prompt,
                    metrics: activeMetrics,
                    edgeScore: edgeScore,
                    language: activeLang,
                    traderProfile: profile,
                    chartImageBase64: chartImageBase64,
                    chartImagesBase64: chartImagesBase64,
                    sessionSummary: activeSessionSummary,
                    conversationHistory: conversationHistory
                )
            } catch {
                AppLogger.warning("OpenRouter primary model '\(primaryORModel)' failed: \(error.localizedDescription). Trying fallback model '\(fallbackORModel)'...")
                if let res = try? await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: activeKey,
                    model: fallbackORModel,
                    action: action,
                    prompt: prompt,
                    metrics: activeMetrics,
                    edgeScore: edgeScore,
                    language: activeLang,
                    traderProfile: profile,
                    chartImageBase64: chartImageBase64,
                    chartImagesBase64: chartImagesBase64,
                    sessionSummary: activeSessionSummary,
                    conversationHistory: conversationHistory
                ) {
                    return res
                }
                return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            }
            
        case "openai":
            if !config.openaiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.openAiEndpoint,
                        apiKey: config.openaiKey,
                        model: config.model.isEmpty ? "gpt-4o-mini" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("OpenAI failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
        case "anthropic":
            if !config.anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callAnthropic(
                        apiKey: config.anthropicKey,
                        model: config.model.isEmpty ? "claude-3-5-sonnet-20241022" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("Anthropic failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
        case "custom":
            if !config.customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: config.customEndpoint,
                        apiKey: config.customKey,
                        model: config.model.isEmpty ? "default" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: activeMetrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: activeSessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("Custom endpoint failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
        default:
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
        }
    }
    
    /// Tests provider connectivity with a test prompt
    public func testConnection(config: AiSettingsConfig) async throws -> String {
        switch config.provider {
        case "github":
            guard !config.githubKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "GitHub", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your GitHub Personal Access Token (PAT)."])
            }
            return try await callOpenAiCompatible(
                endpoint: Self.githubEndpoint,
                apiKey: config.githubKey,
                model: config.model.isEmpty ? "gpt-4o" : config.model,
                action: .ask,
                prompt: "Say 'GitHub connected successfully.' and state your model name in one short sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "gemini":
            guard !config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "Gemini", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your Google Gemini API key from aistudio.google.com."])
            }
            let geminiModel = (config.model.isEmpty || config.model == "gemini-2.0-flash" || config.model == "gemini-1.5-flash" || config.model == "gemini-2.5-flash") ? "gemini-3.5-flash-lite" : config.model
            return try await callOpenAiCompatible(
                endpoint: Self.geminiEndpoint,
                apiKey: config.geminiKey,
                model: geminiModel,
                action: .ask,
                prompt: "Say 'Google Gemini connected successfully.' and state your model name in one sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "groq":
            let activeKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            let testModel = (config.model.isEmpty || config.model == "auto" || config.model == "default") ? "qwen/qwen3.8-27b" : config.model
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: activeKey,
                    model: testModel,
                    action: .ask,
                    prompt: "Say 'Groq connected successfully.' and state your model name in one sentence.",
                    metrics: nil,
                    edgeScore: nil
                )
            } catch {
                let backupKey = config.groqBackupKey.trimmingCharacters(in: .whitespaces)
                let effectiveBackupKey = backupKey.isEmpty ? AiSettingsConfig.defaultGroqBackupKey : backupKey
                if !effectiveBackupKey.isEmpty && effectiveBackupKey != activeKey {
                    return try await callOpenAiCompatible(
                        endpoint: Self.groqEndpoint,
                        apiKey: effectiveBackupKey,
                        model: testModel,
                        action: .ask,
                        prompt: "Say 'Groq connected successfully via backup key.' and state your model name in one sentence.",
                        metrics: nil,
                        edgeScore: nil
                    )
                }
                throw error
            }
            
        case "openrouter":
            let activeKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
            var reqModel = (config.model.isEmpty || config.model == "auto" || config.model == "default") ? "nvidia/nemotron-3.5-lightning:free" : config.model
            if reqModel == "openrouter/free" || reqModel.contains("content-safety") {
                reqModel = "nvidia/nemotron-3.5-lightning:free"
            }
            return try await callOpenAiCompatible(
                endpoint: Self.openRouterEndpoint,
                apiKey: activeKey,
                model: reqModel,
                action: .ask,
                prompt: "Say 'OpenRouter connected successfully.' and state your model name in one sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "openai":
            guard !config.openaiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "OpenAI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your OpenAI API key."])
            }
            return try await callOpenAiCompatible(
                endpoint: Self.openAiEndpoint,
                apiKey: config.openaiKey,
                model: config.model.isEmpty ? "gpt-4o-mini" : config.model,
                action: .ask,
                prompt: "Say 'OpenAI connection verified successfully.' in one short sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "anthropic":
            guard !config.anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "Anthropic", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your Anthropic API key."])
            }
            return try await callAnthropic(
                apiKey: config.anthropicKey,
                model: config.model.isEmpty ? "claude-3-5-sonnet-20241022" : config.model,
                action: .ask,
                prompt: "Say 'Anthropic connection verified successfully.' in one short sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "custom":
            guard !config.customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "CustomAI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your custom API Endpoint URL."])
            }
            return try await callOpenAiCompatible(
                endpoint: config.customEndpoint,
                apiKey: config.customKey,
                model: config.model.isEmpty ? "default" : config.model,
                action: .ask,
                prompt: "Say 'Custom endpoint connected successfully.' in one short sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        default:
            throw NSError(domain: "AI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unknown AI provider: \(config.provider)"])
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
        
        let prompt = AIPromptBuilder.buildTradeCoachingPrompt(
            trade: trade,
            isVi: isVi,
            recentCandlesSummary: recentCandlesSummary,
            bars: bars,
            sessionSummary: sessionSummary,
            displayTimeZone: displayTimeZone,
            linkedPreTradePlan: linkedPreTradePlan
        )
        
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
    
    // MARK: - Pre-Trade Multi-Timeframe Analysis Request
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
        let (config, sessionSummary, metrics, traderProfile, displayTimeZone, events) = await MainActor.run { () -> (AiSettingsConfig, AIAccountSessionSummary, TradeMetrics, TraderProfileConfig, String, [ForexFactoryEvent]) in
            let ds = TradeDataStore.shared
            let cfg = ds.aiSettings
            let summary = AIAccountContextProvider.captureContext(dataStore: ds)
            let m = FinancialMetricsEngine.computeMetrics(trades: ds.filteredTrades)
            let prof = cfg.traderProfile
            let tz = ds.generalSettings.displayTimeZone
            let evs = ForexFactoryService.shared.usdEvents
            return (cfg, summary, m, prof, tz, evs)
        }
        
        let activeLang = language ?? config.language
        let hasImage = (chartImageBase64 != nil && !chartImageBase64!.isEmpty) || (chartImagesBase64 != nil && !chartImagesBase64!.isEmpty)
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
            hasImage: hasImage
        )
        
        return try await requestReflection(
            action: .critique,
            prompt: prompt,
            metrics: metrics,
            edgeScore: nil,
            language: activeLang,
            chartImageBase64: chartImageBase64,
            chartImagesBase64: chartImagesBase64,
            sessionSummary: nil, // Session summary is already comprehensively formatted into prompt
            conversationHistory: conversationHistory
        )
    }
    
    // MARK: - Intelligent Task-Based Model Orchestrator (Groq & OpenRouter)
    
    /// Intelligently resolves the most capable active model on Groq based on task requirements
    public static func resolveOptimalGroqModel(action: AIReflectionAction, userRequestedModel: String) -> (primary: String, fallback: String) {
        let clean = userRequestedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty && clean != "openai/gpt-oss-120b" && clean != "openai/gpt-oss-20b" && clean != "qwen/qwen3.8-27b" && clean != "default" && clean != "auto" {
            return (clean, "openai/gpt-oss-120b")
        }
        
        switch action {
        case .critique:
            // High capacity 120B reasoning model with 3,200 token budget guarantees complete, untruncated 4-section Pre-Trade SMC analysis
            return ("openai/gpt-oss-120b", "openai/gpt-oss-20b")
        case .ask:
            // High speed 20B reasoning model for conversational inquiries (1.5s latency, complete answers without truncation)
            return ("openai/gpt-oss-20b", "openai/gpt-oss-120b")
        case .recap:
            // Comprehensive 120B reasoning model for daily forensic recap
            return ("openai/gpt-oss-120b", "openai/gpt-oss-20b")
        }
    }
    
    /// Intelligently resolves the most capable active model on OpenRouter based on task requirements & modality
    public static func resolveOptimalOpenRouterModel(action: AIReflectionAction, hasImages: Bool, userRequestedModel: String) -> (primary: String, fallback: String) {
        let clean = userRequestedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasImages {
            return ("nvidia/nemotron-3.5-super-vl:free", "nvidia/nemotron-3.5-lightning:free")
        }
        
        if !clean.isEmpty && clean != "nvidia/nemotron-3.5-super-vl:free" && clean != "nvidia/nemotron-3.5-lightning:free" && clean != "openrouter/free" && !clean.contains("content-safety") && clean != "auto" {
            return (clean, "nvidia/nemotron-3.5-lightning:free")
        }
        
        switch action {
        case .critique:
            return ("nvidia/nemotron-3.5-lightning:free", "nvidia/nemotron-3.5-super-vl:free")
        case .ask:
            return ("nvidia/nemotron-3.5-lightning:free", "nvidia/nemotron-3.5-super-vl:free")
        case .recap:
            return ("nvidia/nemotron-3.5-lightning:free", "nvidia/nemotron-3.5-super-vl:free")
        }
    }
}
