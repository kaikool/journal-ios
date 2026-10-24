import Foundation

public enum AIReflectionAction: String, Codable, Sendable {
    case ask = "ask"
    case critique = "critique"
    case recap = "recap"
}

public struct AIReflectionResponse: Codable, Sendable {
    public let action: String
    public let reflection: String
}

public actor AIReflectionService {
    public static let shared = AIReflectionService()
    
    // Official API endpoints
    public static let githubEndpoint = "https://models.github.ai/inference/chat/completions"
    public static let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    public static let groqEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    public static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    public static let openAiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private func getSystemPrompt(language: String) -> String {
        if language == "vi" {
            return """
            Bạn là Trợ lý AI Huấn luyện viên Kỷ luật Giao dịch (Trading Discipline Coach) chuyên nghiệp.
            NGUYÊN TẮC: Bạn chỉ phân tích dựa trên 100% dữ liệu thực tế được cung cấp; không bịa đặt thị trường hay đưa lời khuyên chung chung.
            NGÔN NGỮ: Trả lời 100% bằng TIẾNG VIỆT, sử dụng thuật ngữ trading chuẩn xác (Stop Loss, Take Profit, Win Rate, Risk/Reward, Drawdown, Entry, Exit, FOMO, Revenge).
            ĐỊNH DẠNG BẮT BUỘC (MARKDOWN THỊ GIÁC CHO MOBILE):
            1. Sử dụng tiêu đề cấp 3 (###) kèm icon cho từng phân đoạn:
               ### 📊 TỔNG QUAN HIỆU SUẤT
               ### 💡 ĐIỂM SÁNG KỶ LUẬT
               ### ⚠️ CẢNH BÁO RỦI RO & LỖ HỔNG
               ### 🎯 QUY TẮC HÀNH ĐỘNG
            2. Các con số và chỉ số then chốt PHẢI được in đậm trong các gạch đầu dòng (• **Tỷ lệ thắng:** 65.0% | **P&L:** +$350).
            3. Luôn cô đọng 1 quy tắc kỷ luật quan trọng nhất vào khối trích dẫn:
            > ⚠️ **Quy tắc vàng:** [Nội dung quy tắc cốt lõi]
            4. Tuyệt đối KHÔNG viết một đoạn văn dài liên tục. Giữ câu văn súc tích, đanh thép, chuyên nghiệp.
            """
        } else {
            return """
            You are an elite, disciplined Prop Trading Coach embedded into a trader's journal.
            PRINCIPLES: Ground every statement 100% in the actual trade statistics provided. Never invent data or assume unstated market context.
            LANGUAGE: Respond 100% in professional English.
            MANDATORY MOBILE-FRIENDLY MARKDOWN FORMATTING:
            1. Use level-3 headers (###) with appropriate emojis for structured sections:
               ### 📊 PERFORMANCE OVERVIEW
               ### 💡 DISCIPLINE STRENGTHS
               ### ⚠️ RISK & BEHAVIORAL WARNINGS
               ### 🎯 ACTIONABLE PROTOCOL
            2. Present key figures in bold inside clean bullet points (• **Win Rate:** 65.0% | **Net P&L:** +$350).
            3. Always highlight the single most important rule inside a quote block:
            > ⚠️ **Core Rule:** [Single non-negotiable rule]
            4. Never write continuous walls of unformatted text. Keep paragraphs punchy and actionable.
            """
        }
    }
    
    private init() {}
    
    /// Requests AI reflection via user-configured AI provider (Gemini, Groq, OpenRouter, OpenAI, Anthropic, Custom)
    /// Gracefully falls back to local coach heuristics if unconfigured or offline.
    public func requestReflection(
        action: AIReflectionAction,
        prompt: String? = nil,
        metrics: TradeMetrics? = nil,
        edgeScore: Double? = nil,
        supabaseUrl: String? = nil,
        authToken: String? = nil,
        overrideConfig: AiSettingsConfig? = nil,
        language: String? = nil
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
        
        switch config.provider {
        case "github":
            guard !config.githubKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [GitHub Token Not Configured] Go to Settings > AI to enter your GitHub Personal Access Token (PAT).\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.githubEndpoint,
                    apiKey: config.githubKey,
                    model: config.model.isEmpty ? "gpt-4o" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                AppLogger.warning("GitHub Models request failed: \(error.localizedDescription). Falling back to local coach.")
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [GitHub AI Notice: \(error.localizedDescription)]\n\n" + local
            }
            
        case "gemini":
            guard !config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [Google Gemini Key Not Configured] Go to Settings > AI to enter your free API key from aistudio.google.com for live AI coaching.\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.geminiEndpoint,
                    apiKey: config.geminiKey,
                    model: config.model.isEmpty ? "gemini-2.0-flash" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                AppLogger.warning("Google Gemini request failed: \(error.localizedDescription). Falling back to local coach.")
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [Google Gemini Notice: \(error.localizedDescription)]\n\n" + local
            }
            
        case "groq":
            let activeKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            let requestedModel = config.model.isEmpty ? "openai/gpt-oss-120b" : config.model
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: activeKey,
                    model: requestedModel,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: activeLang
                )
            } catch {
                AppLogger.warning("Groq request with model '\(requestedModel)' failed: \(error.localizedDescription). Searching for active Groq models...")
                
                // 1. Dynamic Discovery: If model was decommissioned, renamed or not found, query Groq /models
                if let freshModel = await fetchBestActiveGroqModel(apiKey: activeKey), freshModel != requestedModel {
                    do {
                        AppLogger.info("Retrying Groq with dynamically discovered active model: \(freshModel)")
                        return try await callOpenAiCompatible(
                            endpoint: Self.groqEndpoint,
                            apiKey: activeKey,
                            model: freshModel,
                            action: action,
                            prompt: prompt,
                            metrics: metrics,
                            edgeScore: edgeScore,
                            language: activeLang
                        )
                    } catch {
                        AppLogger.warning("Groq retry with dynamic model '\(freshModel)' failed: \(error.localizedDescription)")
                    }
                }
                
                // 2. High Availability Failover: Automatically route to OpenRouter free tier before falling back to local
                AppLogger.info("Failing over from Groq to OpenRouter dynamic free router...")
                let orKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
                if let orResult = try? await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: orKey,
                    model: "openrouter/free",
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: activeLang
                ) {
                    return orResult
                }
                
                AppLogger.warning("Groq & failover failed. Falling back to local coach.")
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [Groq Notice: \(error.localizedDescription)]\n\n" + local
            }
            
        case "openrouter":
            let activeKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: activeKey,
                    model: config.model.isEmpty ? "openrouter/free" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: activeLang
                )
            } catch {
                AppLogger.warning("OpenRouter request failed: \(error.localizedDescription). Falling back to local coach.")
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [OpenRouter Notice: \(error.localizedDescription)]\n\n" + local
            }
            
        case "openai":
            guard !config.openaiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [OpenAI Key Not Configured] Enter your API key in Settings > AI.\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.openAiEndpoint,
                    apiKey: config.openaiKey,
                    model: config.model.isEmpty ? "gpt-4o-mini" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [OpenAI Error: \(error.localizedDescription)]\n\n" + local
            }
            
        case "anthropic":
            guard !config.anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [Anthropic Key Not Configured] Enter your API key in Settings > AI.\n\n" + local
            }
            do {
                return try await callAnthropic(
                    apiKey: config.anthropicKey,
                    model: config.model.isEmpty ? "claude-3-5-sonnet-20241022" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [Anthropic Error: \(error.localizedDescription)]\n\n" + local
            }
            
        case "custom":
            guard !config.customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [Custom Endpoint Not Configured] Enter your custom API URL in Settings > AI.\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: config.customEndpoint,
                    apiKey: config.customKey,
                    model: config.model.isEmpty ? "default" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [Custom Model Error: \(error.localizedDescription)]\n\n" + local
            }
            
        default:
            if let urlString = supabaseUrl, !urlString.isEmpty, let token = authToken, !token.isEmpty {
                return try await callSupabaseEdgeFunction(
                    urlString: urlString,
                    token: token,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            }
            return generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
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
            return try await callOpenAiCompatible(
                endpoint: Self.geminiEndpoint,
                apiKey: config.geminiKey,
                model: config.model.isEmpty ? "gemini-2.0-flash" : config.model,
                action: .ask,
                prompt: "Say 'Google Gemini connected successfully.' and state your model name in one sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "groq":
            let activeKey = config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultGroqKey : config.groqKey.trimmingCharacters(in: .whitespaces)
            return try await callOpenAiCompatible(
                endpoint: Self.groqEndpoint,
                apiKey: activeKey,
                model: config.model.isEmpty ? "openai/gpt-oss-120b" : config.model,
                action: .ask,
                prompt: "Say 'Groq connected successfully.' and state your model name in one sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "openrouter":
            let activeKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
            return try await callOpenAiCompatible(
                endpoint: Self.openRouterEndpoint,
                apiKey: activeKey,
                model: config.model.isEmpty ? "openrouter/free" : config.model,
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
    
    // MARK: - OpenAI-Compatible Chat Completions (Gemini, Groq, OpenRouter, OpenAI, Custom)
    
    private func callOpenAiCompatible(
        endpoint: String,
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi"
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.addValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("https://tradejournal.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("TradeJournal", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 45
        
        let activeSystemPrompt = getSystemPrompt(language: language)
        let userContent = buildTraderContext(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: language)
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": activeSystemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 410 {
            throw NSError(domain: "AIInference", code: 410, userInfo: [NSLocalizedDescriptionKey: "GitHub Models preview was retired on July 30, 2026. For GitHub/Microsoft models, use Azure AI Foundry or a custom endpoint."])
        }
        
        if httpResponse.statusCode != 200 {
            let errorDetails = parseApiErrorMessage(from: data, statusCode: httpResponse.statusCode)
            throw NSError(domain: "AIInference", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
        
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let text = decoded.choices.first?.message.content, !text.isEmpty else {
            if let rawText = String(data: data, encoding: .utf8), !rawText.isEmpty {
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "OK" {
                    throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Endpoint returned text 'OK' instead of chat payload. Note: GitHub Models preview was retired on July 30, 2026. Please configure an Azure AI Foundry or custom proxy endpoint."])
                }
                throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Invalid response format: \(trimmed.prefix(120))"])
            }
            throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Model returned an empty response."])
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Anthropic Messages API
    
    private func callAnthropic(
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey.trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 45
        
        let userContent = buildTraderContext(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore)
        let payload: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 1024,
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorDetails = parseApiErrorMessage(from: data, statusCode: httpResponse.statusCode)
            throw NSError(domain: "Anthropic", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
        
        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable {
                let text: String?
            }
            let content: [ContentBlock]
        }
        
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first?.text, !text.isEmpty else {
            throw NSError(domain: "Anthropic", code: 204, userInfo: [NSLocalizedDescriptionKey: "Anthropic returned an empty response."])
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Dynamic Groq Model Discovery & Auto-Healing
    
    private func fetchBestActiveGroqModel(apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        
        struct GroqModelItem: Decodable {
            let id: String
            let active: Bool?
            let context_window: Int?
        }
        struct GroqModelList: Decodable {
            let data: [GroqModelItem]
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let list = try JSONDecoder().decode(GroqModelList.self, from: data)
            
            // Filter active chat/text completion models (exclude audio, guard, speech models)
            let candidates = list.data.filter { item in
                let lower = item.id.lowercased()
                let isActive = item.active ?? true
                guard isActive else { return false }
                guard !lower.contains("whisper"),
                      !lower.contains("guard"),
                      !lower.contains("orpheus"),
                      !lower.contains("embedding"),
                      !lower.contains("tts"),
                      !lower.contains("stt") else { return false }
                return true
            }
            
            // Score candidates based on capability and context window
            let sorted = candidates.sorted { a, b in
                scoreGroqCandidate(a.id, context: a.context_window ?? 0) > scoreGroqCandidate(b.id, context: b.context_window ?? 0)
            }
            
            return sorted.first?.id
        } catch {
            AppLogger.warning("Failed to auto-discover Groq models: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func scoreGroqCandidate(_ id: String, context: Int) -> Int {
        var score = context / 1000
        let lower = id.lowercased()
        if lower.contains("120b") { score += 500 }
        else if lower.contains("70b") { score += 400 }
        else if lower.contains("27b") { score += 300 }
        else if lower.contains("20b") { score += 200 }
        else if lower.contains("8b") { score += 100 }
        if lower.contains("gpt-oss") || lower.contains("qwen") || lower.contains("llama") { score += 50 }
        return score
    }
    
    // MARK: - Legacy Supabase Edge Function Fallback
    
    private func callSupabaseEdgeFunction(
        urlString: String,
        token: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?
    ) async throws -> String {
        guard let endpoint = URL(string: "\(urlString)/functions/v1/ai-reflection") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        var payload: [String: Any] = ["action": action.rawValue]
        if let p = prompt {
            payload["prompt"] = p
        }
        if let m = metrics {
            payload["scopeSummary"] = [
                "totalTrades": m.totalTrades,
                "winRate": m.winRate ?? 0.0,
                "profitFactor": m.profitFactor ?? 0.0,
                "netPnl": NSDecimalNumber(decimal: m.netPnl).doubleValue,
                "maxDrawdownPct": m.maxDrawdownPct ?? 0.0,
                "edgeScore": edgeScore ?? 0.0
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
        }
        
        let decoded = try JSONDecoder().decode(AIReflectionResponse.self, from: data)
        return decoded.reflection
    }
    
    // MARK: - Prompt & Error Builders
    
    private func buildTraderContext(action: AIReflectionAction, prompt: String?, metrics: TradeMetrics?, edgeScore: Double?, language: String = "vi") -> String {
        let isVi = language == "vi"
        var context = ""
        if let m = metrics {
            let wr = (m.winRate ?? 0.0) * 100
            let pf = m.profitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
            let score = edgeScore.map { "\(Int($0))" } ?? "N/A"
            let dd = m.maxDrawdownPct.map { String(format: "%.1f%%", $0) } ?? "N/A"
            
            if isVi {
                context += """
                DỮ LIỆU HIỆU SUẤT TRADER (TRADER PERFORMANCE CONTEXT):
                - Tổng số lệnh đã đóng: \(m.totalTrades)
                - Lệnh Thắng: \(m.wins) | Lệnh Thua: \(m.losses) | Hòa vốn: \(m.breakevens)
                - Tỷ lệ thắng (Win Rate): \(String(format: "%.1f%%", wr))
                - Hệ số lợi nhuận (Profit Factor): \(pf)
                - Lợi nhuận ròng tích lũy (Net P&L): \(m.netPnl >= 0 ? "+" : "")\(m.netPnl)
                - Sụt giảm vốn tối đa (Max Drawdown): \(dd)
                - Điểm lợi thế (Edge Score): \(score)/100
                - Lệnh thắng lớn nhất: \(m.largestWin) | Lệnh thua lớn nhất: \(m.largestLoss)
                - Chuỗi thắng lớn nhất: \(m.maxWinStreak) | Chuỗi thua lớn nhất: \(m.maxLossStreak)
                - Tổng chi phí/phí giao dịch: \(m.fees.map { "\($0)" } ?? "0")
                
                """
            } else {
                context += """
                TRADER PERFORMANCE CONTEXT:
                - Total Closed Trades: \(m.totalTrades)
                - Wins: \(m.wins) | Losses: \(m.losses) | Breakeven: \(m.breakevens)
                - Win Rate: \(String(format: "%.1f%%", wr))
                - Profit Factor: \(pf)
                - Net Cumulative P&L: \(m.netPnl >= 0 ? "+" : "")\(m.netPnl)
                - Max Drawdown: \(dd)
                - Edge Score: \(score)/100
                - Largest Win: \(m.largestWin) | Largest Loss: \(m.largestLoss)
                - Max Win Streak: \(m.maxWinStreak) | Max Loss Streak: \(m.maxLossStreak)
                - Total Fees: \(m.fees.map { "\($0)" } ?? "0")
                
                """
            }
        }
        
        if let p = prompt, !p.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(context)\(p)"
        }
        
        switch action {
        case .recap:
            return isVi ? "\(context)YÊU CẦU: Hãy cung cấp một bản đúc kết ngày giao dịch súc tích: 1) Tóm tắt hiệu suất. 2) Hai điểm làm tốt. 3) Một bài học kỷ luật then chốt." : "\(context)TASK: Provide a concise, structured recap of the trading day. State: 1) Performance summary grounded strictly in the data. 2) Two key strengths observed. 3) One discipline / risk management improvement area. Be concise and actionable."
            
        case .critique:
            return isVi ? "\(context)YÊU CẦU: Đưa ra nhận xét huấn luyện nghiêm khắc và mang tính xây dựng. Chỉ ra các thiên kiến tâm lý (chịu lỗ quá đà, tâm lý chuỗi thua, tần suất giao dịch) và các quy tắc cần điều chỉnh." : "\(context)TASK: Deliver a sharp, constructive coaching critique. Point out behavioral biases (e.g., loss tolerance, streak psychology, trade frequency) and state exact rule adjustments."
            
        case .ask:
            return isVi ? "\(context)CÂU HỎI CỦA TRADER: \"\(prompt ?? "")\"\nYÊU CẦU: Trả lời trực diện câu hỏi dựa trên các con số hiệu suất thực tế được cung cấp." : "\(context)USER QUESTION: \"\(prompt ?? "")\"\nTASK: Answer the trader's question directly using only the performance data provided. Cite the exact figures and give specific, actionable advice."
        }
    }
    
    private func parseApiErrorMessage(from data: Data, statusCode: Int) -> String {
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = jsonArray.first {
            if let errorObj = first["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                return msg
            }
            if let msg = first["message"] as? String {
                return msg
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                return msg
            }
            if let msg = json["message"] as? String {
                return msg
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text.prefix(200) + (text.count > 200 ? "..." : "")
        }
        return "Server responded with HTTP \(statusCode)"
    }
    
    private func generateLocalCoachReflection(
        action: AIReflectionAction,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        prompt: String?
    ) -> String {
        guard let m = metrics else {
            return "Insufficient trade data for analysis. Please record or import trades to analyze performance."
        }
        
        let wr = (m.winRate ?? 0.0) * 100
        let pf = m.profitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
        let score = edgeScore.map { "\(Int($0))" } ?? "N/A"
        
        switch action {
        case .ask:
            return """
            [Internal Performance Analysis]
            Your question: "\(prompt ?? "")"
            
            Actual trading data:
            - Total closed trades: \(m.totalTrades)
            - Win Rate: \(String(format: "%.1f%%", wr)) (\(m.wins)W / \(m.losses)L / \(m.breakevens)BE)
            - Profit Factor: \(pf)
            - Edge Score v2: \(score)/100
            
            Summary:
            \(wr >= 50.0 ? "The trading system maintains a solid win rate." : "Win rate is below 50%; optimize trade entries and focus on favorable R:R ratios.")
            \(m.losses > 0 ? "Largest loss recorded is \(m.largestLoss). Strict stop loss adherence is essential." : "No losing trades recorded in this period.")
            """
            
        case .critique:
            return """
            [Coach Perspective]
            Reviewing the overall performance:
            1. Streaks: Longest win streak is \(m.maxWinStreak) trades, longest loss streak is \(m.maxLossStreak) trades.
            2. Edge Score reached \(score)/100.
            3. Recommendation: Maintain disciplined position sizing. Never revenge trade or scale up sizing after drawdowns.
            """
            
        case .recap:
            return """
            [Performance Summary]
            - Net Cumulative P&L: \(m.netPnl >= 0 ? "+" : "")\(m.netPnl)
            - Largest win: \(m.largestWin) | Largest loss: \(m.largestLoss)
            - Total fees paid: \(m.fees.map { "\($0)" } ?? "0")
            - Total trade volume: \(m.totalVolume)
            
            Assessment: \(m.netPnl >= 0 ? "Profitable period. Maintain playbook execution rules." : "Net negative period. Review rule-violating trades and tighten risk parameters.")
            """
        }
    }
}
