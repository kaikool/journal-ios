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
        case "ensemble":
            // Route general reflection/coaching to Groq 120B with fallback to Gemini
            let activeGroqKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            if !activeGroqKey.isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.groqEndpoint,
                        apiKey: activeGroqKey,
                        model: "openai/gpt-oss-120b",
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
                    AppLogger.warning("Groq ensemble general call failed: \(error.localizedDescription). Falling back to default provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: activeMetrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile, chartImageBase64: chartImageBase64, chartImagesBase64: chartImagesBase64, sessionSummary: activeSessionSummary, conversationHistory: conversationHistory)
            
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
            let activeGeminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
            if !activeGeminiKey.isEmpty {
                do {
                    let geminiModel: String = {
                        let m = config.model.trimmingCharacters(in: .whitespaces)
                        if m.isEmpty || m == "auto" || m == "default" || m == "gemini-2.0-flash" || m == "gemini-1.5-flash" || m == "gemini-2.5-flash" {
                            return "gemini-3.5-flash-lite"
                        }
                        return m
                    }()
                    return try await callOpenAiCompatible(
                        endpoint: Self.geminiEndpoint,
                        apiKey: activeGeminiKey,
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
            let hasImages = (chartImagesBase64?.isEmpty == false)
            let hasSingle = (chartImageBase64?.isEmpty == false)
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
            let hasImages = (chartImagesBase64?.isEmpty == false) || (chartImageBase64?.isEmpty == false)
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
        case "ensemble":
            let activeGroqKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            if !activeGroqKey.isEmpty {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: activeGroqKey,
                    model: "openai/gpt-oss-120b",
                    action: .ask,
                    prompt: "Say 'RISK AI Multi-Model Ensemble connected successfully.' in one short sentence.",
                    metrics: nil,
                    edgeScore: nil
                )
            } else {
                let activeGeminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
                return try await callOpenAiCompatible(
                    endpoint: Self.geminiEndpoint,
                    apiKey: activeGeminiKey,
                    model: "gemini-3.5-flash-lite",
                    action: .ask,
                    prompt: "Say 'RISK AI Engine connected successfully.' in one short sentence.",
                    metrics: nil,
                    edgeScore: nil
                )
            }
            
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
            let activeGeminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
            guard !activeGeminiKey.isEmpty else {
                throw NSError(domain: "Gemini", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your Google Gemini API key from aistudio.google.com."])
            }
            let geminiModel = (config.model.isEmpty || config.model == "auto" || config.model == "default" || config.model == "gemini-2.0-flash" || config.model == "gemini-1.5-flash" || config.model == "gemini-2.5-flash") ? "gemini-3.5-flash-lite" : config.model
            return try await callOpenAiCompatible(
                endpoint: Self.geminiEndpoint,
                apiKey: activeGeminiKey,
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
        
        // Multi-Model Parallel Ensemble for Trade Coaching (GPT-120B, Qwen-27B, Gemini-3.5-Flash-Lite)
        let groqKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
        let groqBackupKey = config.groqBackupKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqBackupKey : config.groqBackupKey.trimmingCharacters(in: .whitespaces)
        let geminiKey = config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGeminiKey : config.geminiKey.trimmingCharacters(in: .whitespaces)
        let effectiveGroqKey = !groqKey.isEmpty ? groqKey : groqBackupKey
        
        if !effectiveGroqKey.isEmpty {
            async let worker1 = self.callModelSafe(
                endpoint: Self.groqEndpoint,
                apiKey: effectiveGroqKey,
                model: "openai/gpt-oss-120b",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: nil,
                sessionSummary: sessionSummary,
                conversationHistory: nil
            )
            async let worker2 = self.callModelSafe(
                endpoint: Self.groqEndpoint,
                apiKey: effectiveGroqKey,
                model: "qwen/qwen3.8-27b",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: nil,
                sessionSummary: sessionSummary,
                conversationHistory: nil
            )
            async let worker3 = self.callModelSafe(
                endpoint: Self.geminiEndpoint,
                apiKey: geminiKey,
                model: "gemini-3.5-flash-lite",
                action: .critique,
                prompt: prompt,
                metrics: metrics,
                language: activeLang,
                traderProfile: nil,
                sessionSummary: sessionSummary,
                conversationHistory: nil
            )
            
            let (res1, res2, res3) = await (worker1, worker2, worker3)
            let validAnalyses = [res1, res2, res3].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            if validAnalyses.count >= 2 {
                let synthesisPrompt = AIPromptBuilder.buildCoachingEnsembleSynthesisPrompt(
                    trade: trade,
                    analyses: validAnalyses,
                    isVi: isVi
                )
                
                // Synthesis via Chief Risk Officer Lead Model
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
                        traderProfile: nil,
                        chartImageBase64: nil,
                        chartImagesBase64: nil,
                        sessionSummary: sessionSummary,
                        conversationHistory: nil
                    )
                } catch {
                    AppLogger.warning("Trade Coaching synthesis failed: \(error.localizedDescription). Falling back to longest valid analysis...")
                    if let best = validAnalyses.max(by: { $0.count < $1.count }) {
                        return best
                    }
                }
            } else if let single = validAnalyses.first {
                return single
            }
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
    
    // MARK: - Pre-Trade Multi-Timeframe Analysis Request (3-Model Consensus Ensemble)
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
            return ("openai/gpt-oss-120b", "qwen/qwen3.8-27b")
        case .ask:
            // High speed 27B/20B model for conversational inquiries (< 0.5s latency, complete answers without truncation)
            return ("qwen/qwen3.8-27b", "openai/gpt-oss-20b")
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
