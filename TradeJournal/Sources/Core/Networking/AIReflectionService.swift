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
    public static let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    public static let groqEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    public static let openRouterEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    public static let openAiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private let systemPrompt = """
    You are the reflection layer of a disciplined trader's journal.
    You see only the trader's own recorded data — trades, stats, and notes. Ground every
    statement in those numbers; never invent trades, prices, or market context you weren't given.
    Be direct, specific, and objective like an elite prop trading coach: cite the numbers, identify behavioral patterns, and specify clear improvements. No generic platitudes, no disclaimers about trading risks. Keep it concise, structured, and actionable.
    """
    
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
        overrideConfig: AiSettingsConfig? = nil
    ) async throws -> String {
        let config: AiSettingsConfig
        if let override = overrideConfig {
            config = override
        } else {
            config = await MainActor.run { TradeDataStore.shared.aiSettings }
        }
        
        switch config.provider {
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
            guard !config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [Groq Key Not Configured] Go to Settings > AI to enter your free Groq API key from console.groq.com for ultra-fast AI coaching.\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: config.groqKey,
                    model: config.model.isEmpty ? "llama-3.3-70b-versatile" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
            } catch {
                AppLogger.warning("Groq request failed: \(error.localizedDescription). Falling back to local coach.")
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "⚠️ [Groq Notice: \(error.localizedDescription)]\n\n" + local
            }
            
        case "openrouter":
            guard !config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                let local = generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
                return "ℹ️ [OpenRouter Key Not Configured] Go to Settings > AI to enter your OpenRouter API key from openrouter.ai/keys.\n\n" + local
            }
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.openRouterEndpoint,
                    apiKey: config.openrouterKey,
                    model: config.model.isEmpty ? "deepseek/deepseek-r1:free" : config.model,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore
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
            guard !config.groqKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "Groq", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your Groq API key from console.groq.com."])
            }
            return try await callOpenAiCompatible(
                endpoint: Self.groqEndpoint,
                apiKey: config.groqKey,
                model: config.model.isEmpty ? "llama-3.3-70b-versatile" : config.model,
                action: .ask,
                prompt: "Say 'Groq connected successfully.' and state your model name in one sentence.",
                metrics: nil,
                edgeScore: nil
            )
            
        case "openrouter":
            guard !config.openrouterKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw NSError(domain: "OpenRouter", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter your OpenRouter API key from openrouter.ai/keys."])
            }
            return try await callOpenAiCompatible(
                endpoint: Self.openRouterEndpoint,
                apiKey: config.openrouterKey,
                model: config.model.isEmpty ? "deepseek/deepseek-r1:free" : config.model,
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
        edgeScore: Double?
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        
        let userContent = buildTraderContext(action: action, prompt: prompt, metrics: metrics, edgeScore: edgeScore)
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
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
        
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
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
    
    private func buildTraderContext(action: AIReflectionAction, prompt: String?, metrics: TradeMetrics?, edgeScore: Double?) -> String {
        var context = ""
        if let m = metrics {
            let wr = (m.winRate ?? 0.0) * 100
            let pf = m.profitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
            let score = edgeScore.map { "\(Int($0))" } ?? "N/A"
            let dd = m.maxDrawdownPct.map { String(format: "%.1f%%", $0) } ?? "N/A"
            
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
        
        switch action {
        case .recap:
            let userNote = prompt.map { "Trader's Note: \"\($0)\"\n" } ?? ""
            return "\(context)\(userNote)TASK: Provide a concise, structured recap of the trading day. State: 1) Performance summary grounded strictly in the data. 2) Two key strengths observed. 3) One discipline / risk management improvement area. Be concise and actionable."
            
        case .critique:
            let userNote = prompt.map { "Focus Area: \"\($0)\"\n" } ?? ""
            return "\(context)\(userNote)TASK: Deliver a sharp, constructive coaching critique. Point out behavioral biases (e.g., loss tolerance, streak psychology, trade frequency) and state exact rule adjustments."
            
        case .ask:
            return "\(context)USER QUESTION: \"\(prompt ?? "")\"\nTASK: Answer the trader's question directly using only the performance data provided. Cite the exact figures and give specific, actionable advice."
        }
    }
    
    private func parseApiErrorMessage(from data: Data, statusCode: Int) -> String {
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
