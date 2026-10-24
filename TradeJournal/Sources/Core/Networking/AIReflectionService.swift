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
            Bạn là Trợ lý Huấn luyện viên Kỷ luật Giao dịch (Professional Trading Discipline & Risk Coach).
            NGUYÊN TẮC CỐT LÕI:
            1. PHÂN TÍCH CHUYÊN SÂU HÀNH VI & KỶ LUẬT: Đi sâu vào phản xạ tâm lý (FOMO, sợ thua, gồng lỗ, chốt non, trả thù thị trường), chiến thuật thực tế và bảo vệ vốn bền vững cho tài khoản/quỹ Prop Firm. Không bao giờ nhận xét chung chung, sáo rỗng.
            2. QUY TẮC ĐỊNH DẠNG SỐ CHUẨN XÁC: Mọi con số tính toán (P&L, tỷ lệ %, drawdown, số lot, chi phí) BẮT BUỘC chỉ hiển thị TỐI ĐA 2 CHỮ SỐ THẬP PHÂN (ví dụ: +$350.25, 62.50%, 0.50 lots, drawdown 1.85%). Không bao giờ để số thập phân dài dòng. (Tỷ giá FX có thể giữ 4-5 số thập phân).
            3. ĐỊNH DẠNG MARKDOWN GỌN GÀNG CHO MOBILE:
               - Tiêu đề từng phần dùng ### kèm icon (ví dụ: ### 📊 ĐÁNH GIÁ THỰC CHIẾN)
               - Gạch đầu dòng rõ ràng: dùng dấu • duy nhất, in đậm chỉ số then chốt (• **P&L:** +$350.00 | **Khối lượng:** 0.50 lots)
               - Tuyệt đối KHÔNG sử dụng hai dấu hoa thị liền nhau như "* *" hoặc lặp lại dấu bullet.
               - Trích dẫn 1 quy tắc kỷ luật hành động quan trọng nhất vào khối:
               > ⚠️ **Quy tắc kỷ luật:** [1 hành động bất di bất dịch cho phiên tới]
            4. Trả lời 100% bằng TIẾNG VIỆT, dùng các thuật ngữ trading chuẩn (Stop Loss, Take Profit, Win Rate, Risk/Reward, Drawdown, Entry, Exit).
            5. NHẬN DIỆN CHIỀU LỆNH CHUẨN XÁC: Luôn kiểm tra kỹ vị thế là BUY hay SELL/SHORT. Với lệnh SELL/SHORT: Lãi khi giá giảm, Lỗ khi giá tăng; TP nằm dưới giá vào, SL nằm trên giá vào. Tuyệt đối không bao giờ phân tích nhầm lẫn lệnh SELL thành lệnh BUY.
            """
        } else {
            return """
            You are an elite Prop Firm Trading Discipline & Risk Management Coach.
            CORE PRINCIPLES:
            1. DEEP BEHAVIORAL & PSYCHOLOGICAL CRITIQUE: Analyze emotional reactions (FOMO, revenge trading, holding losers, premature profit taking), trade execution quality, and sustainable capital preservation. Never give generic, empty platitudes.
            2. STRICT 2-DECIMAL PLACES RULE: All calculated figures (P&L, percentages, drawdown, volume lots, commissions) MUST be formatted to AT MOST 2 DECIMAL PLACES (e.g. +$350.25, 62.50%, 0.50 lots, -1.85% drawdown). Never output long raw decimals. (FX exchange rates may retain 4-5 decimals).
            3. CLEAN MOBILE MARKDOWN FORMATTING:
               - Section headers using ### with emojis (e.g. ### 📊 EXECUTION AUDIT)
               - Clean bullet points using a single • with bold figures (• **Net P&L:** +$350.00 | **Size:** 0.50 lots)
               - Never output doubled asterisks like "* *" or duplicate bullets.
               - Highlight the single most critical discipline rule in a blockquote:
               > ⚠️ **Core Discipline Rule:** [Single non-negotiable directive for the next session]
            4. Respond 100% in professional English.
            5. STRICT TRADE DIRECTION ACCURACY: Always strictly verify whether a position is BUY or SELL/SHORT. For SELL/SHORT trades: profit occurs when price drops (Entry > Exit = Profit), TP is strictly below Entry, and SL is strictly above Entry. Never invert or confuse trade direction.
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
        
        let profile = config.traderProfile
        
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
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile
                    )
                } catch {
                    AppLogger.warning("GitHub Models failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            
        case "gemini":
            if !config.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.geminiEndpoint,
                        apiKey: config.geminiKey,
                        model: config.model.isEmpty ? "gemini-2.0-flash" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile
                    )
                } catch {
                    AppLogger.warning("Gemini failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            
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
                    language: activeLang,
                    traderProfile: profile
                )
            } catch {
                AppLogger.warning("Groq request with model '\(requestedModel)' failed: \(error.localizedDescription). Retrying with active discovery and failover...")
                return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            }
            
        case "openrouter":
            let activeKey = config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty ? AiSettingsConfig.defaultOpenRouterKey : config.openrouterKey.trimmingCharacters(in: .whitespaces)
            let requestedModel = config.model.isEmpty ? "openrouter/free" : config.model
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: activeKey,
                    model: requestedModel,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: activeLang,
                    traderProfile: profile
                )
            } catch {
                AppLogger.warning("OpenRouter request failed: \(error.localizedDescription). Falling back to default AI provider...")
                return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
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
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile
                    )
                } catch {
                    AppLogger.warning("OpenAI failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            
        case "anthropic":
            if !config.anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callAnthropic(
                        apiKey: config.anthropicKey,
                        model: config.model.isEmpty ? "claude-3-5-sonnet-20241022" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: activeLang
                    )
                } catch {
                    AppLogger.warning("Anthropic failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            
        case "custom":
            if !config.customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: config.customEndpoint,
                        apiKey: config.customKey,
                        model: config.model.isEmpty ? "default" : config.model,
                        action: action,
                        prompt: prompt,
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: activeLang,
                        traderProfile: profile
                    )
                } catch {
                    AppLogger.warning("Custom endpoint failed: \(error.localizedDescription). Falling back to default AI provider...")
                }
            }
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
            
        default:
            return try await callDefaultProvider(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: activeLang, traderProfile: profile)
        }
    }
    
    // MARK: - Bulletproof Default High-Availability Pipeline
    private func callDefaultProvider(
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String,
        traderProfile: TraderProfileConfig? = nil
    ) async throws -> String {
        // Attempt 1: Fast High-Quality Groq
        do {
            return try await callOpenAiCompatible(
                endpoint: Self.groqEndpoint,
                apiKey: AiSettingsConfig.defaultGroqKey,
                model: "openai/gpt-oss-120b",
                action: action,
                prompt: prompt,
                metrics: metrics,
                edgeScore: edgeScore,
                language: language,
                traderProfile: traderProfile
            )
        } catch {
            AppLogger.warning("Default Groq attempt failed: \(error.localizedDescription). Attempting OpenRouter free tier...")
        }
        
        // Attempt 2: OpenRouter Dynamic Free Models
        do {
            return try await callOpenAiCompatible(
                endpoint: Self.openRouterEndpoint,
                apiKey: AiSettingsConfig.defaultOpenRouterKey,
                model: "openrouter/free",
                action: action,
                prompt: prompt,
                metrics: metrics,
                edgeScore: edgeScore,
                language: language,
                traderProfile: traderProfile
            )
        } catch {
            AppLogger.warning("Default OpenRouter attempt failed: \(error.localizedDescription).")
        }
        
        throw NSError(
            domain: "AIReflectionService",
            code: 503,
            userInfo: [NSLocalizedDescriptionKey: "AI inference service is currently unreachable. Please check your internet connection or verify your API keys in Settings > AI Assistant."]
        )
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
        language: String = "vi",
        traderProfile: TraderProfileConfig? = nil
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
        let userContent = buildTraderContext(
            action: action,
            prompt: prompt,
            metrics: metrics,
            edgeScore: edgeScore,
            language: language,
            traderProfile: traderProfile
        )
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
                    let role: String?
                    let content: String?
                    let reasoning: String?
                }
                let message: Message
            }
            let choices: [Choice]?
        }
        
        if let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
           let firstChoice = decoded.choices?.first {
            let candidateText = firstChoice.message.content ?? firstChoice.message.reasoning
            if let valid = candidateText?.trimmingCharacters(in: .whitespacesAndNewlines), !valid.isEmpty {
                return valid
            }
        }
        
        // Dynamic JSON Dictionary Fallback
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any] {
            if let content = msg["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let reasoning = msg["reasoning"] as? String, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if let rawText = String(data: data, encoding: .utf8), !rawText.isEmpty {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "OK" {
                throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Endpoint returned text 'OK' instead of chat payload. Please verify your AI provider endpoint."])
            }
            throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Invalid response format: \(trimmed.prefix(120))"])
        }
        throw NSError(domain: "AIInference", code: 204, userInfo: [NSLocalizedDescriptionKey: "Model returned an empty response."])
    }
    
    // MARK: - Anthropic Messages API
    
    private func callAnthropic(
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi"
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
        
        let userContent = buildTraderContext(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore, language: language)
        let activeSystemPrompt = getSystemPrompt(language: language)
        let payload: [String: Any] = [
            "model": model,
            "system": activeSystemPrompt,
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
    
    private func buildTraderContext(
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi",
        traderProfile: TraderProfileConfig? = nil
    ) -> String {
        let isVi = language == "vi"
        var context = ""
        
        // 1. Persistent Trader Context & Memory
        if let prof = traderProfile {
            context += """
            TRADER PROFILE & STRATEGY MEMORY:
            - Trading Style: \(prof.tradingStyle)
            - Goal / Prop Firm: \(prof.accountObjective)
            - Setups & Playbooks: \(prof.primaryPlaybooks)
            - Risk Budget: \(prof.maxRiskPerTrade)
            - Known Leaks & Biases: \(prof.knownPsychologicalLeaks)
            - Personal Notes: \(prof.customMemoryNotes)
            
            """
        }
        
        // 2. Performance Metrics (Strictly 2 Decimal Places)
        if let m = metrics {
            let wr = String(format: "%.2f%%", (m.winRate ?? 0.0) * 100)
            let pf = m.profitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
            let score = edgeScore.map { String(format: "%.2f", $0) } ?? "N/A"
            let dd = m.maxDrawdownPct.map { String(format: "%.2f%%", $0) } ?? "N/A"
            let netPnl = String(format: "%.2f", NSDecimalNumber(decimal: m.netPnl).doubleValue)
            let largestWin = String(format: "%.2f", NSDecimalNumber(decimal: m.largestWin).doubleValue)
            let largestLoss = String(format: "%.2f", NSDecimalNumber(decimal: m.largestLoss).doubleValue)
            let fees = String(format: "%.2f", NSDecimalNumber(decimal: m.fees ?? Decimal.zero).doubleValue)
            
            if isVi {
                context += """
                DỮ LIỆU HIỆU SUẤT TRADER (TRADER PERFORMANCE CONTEXT):
                - Tổng số lệnh đã đóng: \(m.totalTrades)
                - Lệnh Thắng: \(m.wins) | Lệnh Thua: \(m.losses) | Hòa vốn: \(m.breakevens)
                - Tỷ lệ thắng (Win Rate): \(wr)
                - Hệ số lợi nhuận (Profit Factor): \(pf)
                - Lợi nhuận ròng tích lũy (Net P&L): \(m.netPnl >= 0 ? "+" : "")$\(netPnl)
                - Sụt giảm vốn tối đa (Max Drawdown): \(dd)
                - Điểm lợi thế (Edge Score): \(score)/100
                - Lệnh thắng lớn nhất: +$\(largestWin) | Lệnh thua lớn nhất: -$\(largestLoss)
                - Chuỗi thắng lớn nhất: \(m.maxWinStreak) | Chuỗi thua lớn nhất: \(m.maxLossStreak)
                - Tổng chi phí/phí giao dịch: $\(fees)
                
                """
            } else {
                context += """
                TRADER PERFORMANCE CONTEXT:
                - Total Closed Trades: \(m.totalTrades)
                - Wins: \(m.wins) | Losses: \(m.losses) | Breakeven: \(m.breakevens)
                - Win Rate: \(wr)
                - Profit Factor: \(pf)
                - Net Cumulative P&L: \(m.netPnl >= 0 ? "+" : "")$\(netPnl)
                - Max Drawdown: \(dd)
                - Edge Score: \(score)/100
                - Largest Win: +$\(largestWin) | Largest Loss: -$\(largestLoss)
                - Max Win Streak: \(m.maxWinStreak) | Max Loss Streak: \(m.maxLossStreak)
                - Total Fees: $\(fees)
                
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
    
    // MARK: - Dedicated Single Trade AI Coaching
    public func requestTradeCoaching(
        trade: Trade,
        language: String? = nil,
        recentCandlesSummary: String? = nil
    ) async throws -> String {
        let config = await MainActor.run { TradeDataStore.shared.aiSettings }
        let activeLang = language ?? config.language
        let isVi = activeLang == "vi"
        
        let isOpen = trade.status == .open || trade.closedAt == nil
        let pnlVal = NSDecimalNumber(decimal: trade.netPnl).doubleValue
        let pnlStr = (trade.netPnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
        let volumeStr = String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)
        let entryStr = Formatters.price(trade.avgEntry)
        let exitStr = trade.avgExit.map { Formatters.price($0) } ?? (isOpen ? "Open / Market" : "N/A")
        let slStr = trade.stopLoss.map { Formatters.price($0) } ?? (isVi ? "Chưa cài SL" : "Not Set")
        let tpStr = trade.profitTarget.map { Formatters.price($0) } ?? (isVi ? "Chưa cài TP" : "Not Set")
        let mistakes = trade.mistakes.isEmpty ? (isVi ? "Không ghi nhận" : "None") : trade.mistakes.joined(separator: ", ")
        let notes = (trade.notes?.isEmpty ?? true) ? (isVi ? "Không có ghi chú" : "None") : trade.notes!
        
        let isShort = trade.direction == .short
        let directionStrVi = isShort ? "SELL / SHORT (BÁN KHỐNG - Kỳ vọng giá GIẢM)" : "BUY / LONG (MUA - Kỳ vọng giá TĂNG)"
        let directionStrEn = isShort ? "SELL / SHORT (Short position - Expects price to FALL)" : "BUY / LONG (Long position - Expects price to RISE)"
        
        let directionWarningVi = isShort
            ? "⚠️ CẢNH BÁO QUAN TRỌNG VỀ CHIỀU LỆNH: Đây là lệnh BÁN (SELL / SHORT). Lợi nhuận sinh ra khi giá GIẢM (Giá hiện tại hoặc Giá ra < Giá vào = CÓ LÃI). Take Profit (TP) phải nằm DƯỚI giá vào, Stop Loss (SL) phải nằm TRÊN giá vào. Tuyệt đối KHÔNG ĐƯỢC phân tích nhầm thành lệnh MUA (BUY)."
            : "⚠️ CẢNH BÁO QUAN TRỌNG VỀ CHIỀU LỆNH: Đây là lệnh MUA (BUY / LONG). Lợi nhuận sinh ra khi giá TĂNG (Giá hiện tại hoặc Giá ra > Giá vào = CÓ LÃI). Take Profit (TP) nằm TRÊN giá vào, Stop Loss (SL) nằm DƯỚI giá vào."
        
        let directionWarningEn = isShort
            ? "CRITICAL DIRECTION DIRECTIVE: THIS IS A SHORT / SELL TRADE. Profit occurs strictly when the price DROPS (Current/Exit price < Entry price = Profit). Take Profit (TP) is BELOW Entry; Stop Loss (SL) is ABOVE Entry. NEVER evaluate this as a BUY trade."
            : "CRITICAL DIRECTION DIRECTIVE: THIS IS A LONG / BUY TRADE. Profit occurs strictly when the price RISES. Take Profit (TP) is ABOVE Entry; Stop Loss (SL) is BELOW Entry."
        
        let candleInfo = recentCandlesSummary ?? (isVi ? "Không có dữ liệu nến ngoài" : "No external candle feed")
        
        let prompt: String
        if isOpen {
            prompt = isVi ? """
            LỆNH ĐANG MỞ CẦN TƯ VẤN (LIVE OPEN POSITION):
            - Cặp tiền: \(trade.symbol) | Vị thế: \(directionStrVi) | Khối lượng: \(volumeStr) lots
            - Giá vào (Entry): \(entryStr) | Giá thị trường hiện tại: \(exitStr)
            - Lợi nhuận tạm tính: \(pnlStr)
            - Cắt lỗ (SL): \(slStr) | Chốt lời (TP): \(tpStr)
            - Ghi chú trader: \(notes)
            - Tóm tắt nến 12h qua: \(candleInfo)
            
            \(directionWarningVi)
            
            NHIỆM VỤ TƯ VẤN LỆNH MỞ (LIVE POSITION ADVISORY):
            1. Trạng thái vị thế & Cấu trúc thị trường: Đánh giá vị thế hiện tại dựa trên giá vào và kế hoạch.
            2. Chiến lược Chốt lời (TP) & Dời SL: Tư vấn cụ thể nên chốt lời ở đâu, khi nào, có nên chốt non 1 phần hay dời SL về hòa vốn (Breakeven).
            3. Quản trị rủi ro: Đưa ra lời khuyên bảo vệ vốn trước các biến động phiên tiếp theo.
            """ : """
            LIVE OPEN POSITION ADVISORY:
            - Symbol: \(trade.symbol) | Direction: \(directionStrEn) | Volume: \(volumeStr) lots
            - Entry Price: \(entryStr) | Current Price: \(exitStr)
            - Unrealized P&L: \(pnlStr)
            - Stop Loss: \(slStr) | Take Profit: \(tpStr)
            - Trader Notes: \(notes)
            - 12h Candlestick Context: \(candleInfo)
            
            \(directionWarningEn)
            
            TASK: OPEN TRADE MANAGEMENT & RISK PROTOCOL
            1. Position Health & Market Structure: Evaluate open position relative to entry and targets.
            2. Take Profit & Trailing Stop Strategy: Advise exactly where and when to take partial or full TP, and whether to trail SL to breakeven.
            3. Risk Control & Preservation: Prescribe non-negotiable rules to avoid turning a winning trade into a loss.
            """
        } else {
            prompt = isVi ? """
            LỆNH ĐÃ ĐÓNG CẦN MỔ XẺ (COMPLETED TRADE AUDIT):
            - Cặp tiền: \(trade.symbol) | Vị thế: \(directionStrVi) | Khối lượng: \(volumeStr) lots
            - Giá vào (Entry): \(entryStr) -> Giá thoát (Exit): \(exitStr)
            - Lợi nhuận thực tế: \(pnlStr)
            - Kế hoạch SL: \(slStr) | Kế hoạch TP: \(tpStr)
            - Lỗi ghi nhận: \(mistakes)
            - Ghi chú trader: \(notes)
            - Tóm tắt nến thị trường: \(candleInfo)
            
            \(directionWarningVi)
            
            NHIỆM VỤ MỔ XẺ LỆNH & BÀI HỌC KỶ LUẬT (POST-MORTEM & LESSONS):
            1. Đánh giá Khớp lệnh vs Kế hoạch: Phân tích điểm vào và điểm ra (thoát non, gồng lỗ hay tuân thủ kế hoạch).
            2. Thiên kiến tâm lý & Sai lầm: Chỉ rõ tâm lý chi phối trong lệnh này (FOMO, sợ thua, thiếu kiên nhẫn).
            3. Bài học cốt lõi: Đưa ra 1 quy tắc hành động duy nhất để không lặp lại sai lầm trong các lệnh tương tự.
            """ : """
            COMPLETED TRADE POST-MORTEM & AUDIT:
            - Symbol: \(trade.symbol) | Direction: \(directionStrEn) | Volume: \(volumeStr) lots
            - Entry Price: \(entryStr) -> Exit Price: \(exitStr)
            - Realized Net P&L: \(pnlStr)
            - Planned SL: \(slStr) | Planned TP: \(tpStr)
            - Logged Mistakes: \(mistakes)
            - Trader Notes: \(notes)
            - Candlestick Context: \(candleInfo)
            
            \(directionWarningEn)
            
            TASK: FORENSIC POST-MORTEM & ACTIONABLE LESSONS
            1. Execution vs Plan: Evaluate entry timing and exit quality.
            2. Psychological & Discipline Breakdown: Pinpoint the exact behavioral bias at play.
            3. Non-Negotiable Rule: Formulate 1 core rule to avoid repeating this mistake on future setups.
            """
        }
        
        return try await requestReflection(
            action: .critique,
            prompt: prompt,
            metrics: nil,
            edgeScore: nil,
            language: activeLang
        )
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
