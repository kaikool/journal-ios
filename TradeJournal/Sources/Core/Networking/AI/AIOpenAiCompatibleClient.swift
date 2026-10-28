import Foundation

// MARK: - OpenAI-Compatible & Anthropic Client Implementation
extension AIReflectionService {
    
    // MARK: - OpenAI-Compatible Chat Completions
    func callOpenAiCompatible(
        endpoint: String,
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi",
        traderProfile: TraderProfileConfig? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        conversationHistory: [AICoachMessage]? = nil
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
        
        var activeSystemPrompt = AIPromptBuilder.getSystemPrompt(language: language)
        if language == "vi" {
            activeSystemPrompt = "⚠️ BẮT BUỘC: Bạn PHẢI trả lời 100% bằng TIẾNG VIỆT mạch lạc, sắc bén, đúng thuật ngữ tài chính. Tuyệt đối KHÔNG trả lời bằng tiếng Anh và KHÔNG được lặp từ hay phát sinh chuỗi suy nghĩ nội bộ ('also mention').\n\n" + activeSystemPrompt
        }
        let userContent = AIPromptBuilder.buildTraderContext(
            action: action,
            prompt: prompt,
            metrics: metrics,
            edgeScore: edgeScore,
            language: language,
            traderProfile: traderProfile,
            sessionSummary: sessionSummary
        )
        
        let isGroq = endpoint.contains("groq.com")
        let isGroqVisionSupported = model.contains("scout") || model.contains("vision")
        let allowImages = !isGroq || isGroqVisionSupported

        let userMessageContent: Any
        if allowImages, let images = chartImagesBase64, !images.isEmpty {
            var parts: [[String: Any]] = [
                ["type": "text", "text": userContent]
            ]
            for b64 in images {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
            userMessageContent = parts
        } else if allowImages, let b64 = chartImageBase64, !b64.isEmpty {
            userMessageContent = [
                ["type": "text", "text": userContent],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
            ]
        } else {
            userMessageContent = userContent
        }
        
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": activeSystemPrompt]
        ]
        
        let validHistory = (conversationHistory ?? []).filter { !$0.content.hasPrefix("⚠️") }
        if !validHistory.isEmpty {
            // 1. PINNED COMMITMENT ANCHOR: Preserve initial thesis so AI never loses memory across long multi-turn sessions
            var unpinnedHistory = validHistory
            if let initialAnchor = validHistory.first, initialAnchor.role == "assistant" {
                let trimmedAnchor = initialAnchor.content.count > 1500
                    ? String(initialAnchor.content.prefix(1500)) + "\n[...trích lược luận điểm cam kết gốc...]"
                    : initialAnchor.content
                
                let anchorNotice = language == "vi"
                    ? """
                    [NEO CAM KẾT GỐC ĐÃ ĐƯA RA (COMMITTED ANCHOR THESIS)]:
                    \"\"\"
                    \(trimmedAnchor)
                    \"\"\"
                    ⚠️ NGUYÊN TẮC BẮT BUỘC VỀ TÍNH NHẤT QUÁN & THÍCH ỨNG:
                    - Đây là luận điểm cam kết gốc của bạn cho phiên phân tích này.
                    - BẮT BUỘC giữ tính nhất quán kỹ thuật với kế hoạch này.
                    - Không được lật kèo hoặc xin lỗi chỉ vì trader nghi ngờ hay chất vấn.
                    - Chỉ tuyên bố BÁC BỎ (INVALIDATED) khi giá thực tế đã phá vỡ mốc dừng lỗ (SL) cấu trúc hoặc xuất hiện tín hiệu đảo chiều rõ ràng.
                    """
                    : """
                    [COMMITTED ANCHOR THESIS (PERSISTENT CONTEXT)]:
                    \"\"\"
                    \(trimmedAnchor)
                    \"\"\"
                    ⚠️ MANDATORY ANCHOR CONSISTENCY & ADAPTATION PROTOCOL:
                    - This is your initial committed thesis for this symbol and session.
                    - Maintain technical consistency with this plan. Do NOT apologize or flip-flop under user pressure.
                    - Declare INVALIDATED only if live market price action has broken your structural Stop Loss or confirmed an opposing regime shift.
                    """
                apiMessages.append(["role": "system", "content": anchorNotice])
                unpinnedHistory.removeFirst()
            }
            
            // 2. Apply Sliding Window of recent turns (e.g. 4 messages = 2 exchanges for inquiries)
            let windowSize = action == .ask ? 4 : 6
            let windowMessages = Array(unpinnedHistory.suffix(windowSize))
            
            // If earlier messages exist, prepend a concise rolling summary notice
            if unpinnedHistory.count > windowSize {
                let olderMessages = Array(unpinnedHistory.prefix(unpinnedHistory.count - windowSize))
                let olderSummary = olderMessages
                    .filter { $0.role == "user" }
                    .map { "• Inquiry: \"\($0.content.prefix(80))...\"" }
                    .joined(separator: "\n")
                
                let summaryNotice = language == "vi"
                    ? "[TÓM TẮT CÁC CÂU HỎI TRƯỚC ĐÓ CỦA TRADER]:\n\(olderSummary)"
                    : "[SUMMARY OF EARLIER TRADER INQUIRIES]:\n\(olderSummary)"
                
                apiMessages.append(["role": "system", "content": summaryNotice])
            }
            
            var userAppended = false
            for (idx, msg) in windowMessages.enumerated() {
                let isLast = (idx == windowMessages.count - 1)
                if isLast && msg.role == "user" {
                    // For latest question, pass userMessageContent with image
                    apiMessages.append(["role": "user", "content": userMessageContent])
                    userAppended = true
                } else {
                    // Truncate overly long previous turns in history to prevent 8k TPM limit exhaustion
                    if msg.content.count > 1400 {
                        let trimmed = String(msg.content.prefix(1400)) + "\n[...trích lược ngữ cảnh trước...]"
                        apiMessages.append(["role": msg.role, "content": trimmed])
                    } else {
                        apiMessages.append(["role": msg.role, "content": msg.content])
                    }
                }
            }
            if !userAppended {
                apiMessages.append(["role": "user", "content": userMessageContent])
            }
        } else {
            apiMessages.append(["role": "user", "content": userMessageContent])
        }
        
        var payload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.1
        ]
        
        // Intelligent token boundaries to guarantee requests NEVER breach Groq's strict 7,000 TPM limit
        if isGroq {
            var totalChars = 0
            for msg in apiMessages {
                if let str = msg["content"] as? String {
                    totalChars += str.count
                } else if let parts = msg["content"] as? [[String: Any]] {
                    for p in parts {
                        if let text = p["text"] as? String {
                            totalChars += text.count
                        }
                    }
                }
            }
            
            // Conservative token estimation (~3.2 chars per token for multilingual content)
            let estimatedPromptTokens = Int(Double(totalChars) / 3.2)
            
            // Groq free tier rejects ANY request where (prompt_tokens + max_tokens) > 7,000.
            // We budget a maximum combined footprint of 5,800 tokens to ensure absolute safety.
            let safeCeiling = 5800
            let availableOutputTokens = max(350, safeCeiling - estimatedPromptTokens)
            
            if model.contains("qwen3.8-27b") {
                payload["max_tokens"] = min(900, availableOutputTokens)
            } else {
                let defaultCap = action == .critique ? 1400 : 1600
                payload["max_tokens"] = min(defaultCap, availableOutputTokens)
            }
        }
        
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
            AppLogger.error("AI inference error [\(model)] HTTP \(httpResponse.statusCode): \(errorDetails)")
            throw NSError(domain: "AIInference", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
        
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let role: String?
                    let content: String?
                    let reasoning: String?
                    let reasoning_content: String?
                }
                let message: Message
            }
            let choices: [Choice]?
        }
        
        if let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
           let firstChoice = decoded.choices?.first {
            let rawContent = firstChoice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawReasoning = firstChoice.message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawReasoningContent = firstChoice.message.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var valid: String? = nil
            if let rc = rawContent, !rc.isEmpty {
                valid = rc
            } else if let rr = rawReasoning ?? rawReasoningContent, !rr.isEmpty {
                let isEnglishScratchpad = (language == "vi" && (rr.contains("The user") || rr.contains("also mention") || rr.contains("I need to") || rr.contains("I should")))
                if !isEnglishScratchpad {
                    valid = rr
                }
            }
            
            if let valid = valid, !valid.isEmpty {
                return try sanitizeAndValidateResponse(valid)
            }
        }
        
        // Dynamic JSON Dictionary Fallback
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any] {
            if let content = msg["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try sanitizeAndValidateResponse(content)
            }
            let reasoning = (msg["reasoning"] as? String) ?? (msg["reasoning_content"] as? String)
            if let rr = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !rr.isEmpty {
                let isEnglishScratchpad = (language == "vi" && (rr.contains("The user") || rr.contains("also mention") || rr.contains("I need to") || rr.contains("I should")))
                if !isEnglishScratchpad {
                    return try sanitizeAndValidateResponse(rr)
                }
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
    func callAnthropic(
        apiKey: String,
        model: String,
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi",
        traderProfile: TraderProfileConfig? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        conversationHistory: [AICoachMessage]? = nil
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
        
        let userContent = AIPromptBuilder.buildTraderContext(
            action: action,
            prompt: prompt,
            metrics: metrics,
            edgeScore: edgeScore,
            language: language,
            traderProfile: traderProfile,
            sessionSummary: sessionSummary
        )
        var activeSystemPrompt = AIPromptBuilder.getSystemPrompt(language: language)
        if language == "vi" {
            activeSystemPrompt = "⚠️ BẮT BUỘC: Bạn PHẢI trả lời 100% bằng TIẾNG VIỆT mạch lạc, sắc bén, đúng thuật ngữ tài chính. Tuyệt đối KHÔNG trả lời bằng tiếng Anh và KHÔNG được lặp từ hay phát sinh chuỗi suy nghĩ nội bộ ('also mention').\n\n" + activeSystemPrompt
        }
        
        let userMessageContent: Any
        if let images = chartImagesBase64, !images.isEmpty {
            var parts: [[String: Any]] = [
                ["type": "text", "text": userContent]
            ]
            for b64 in images {
                parts.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": b64
                    ]
                ])
            }
            userMessageContent = parts
        } else if let b64 = chartImageBase64, !b64.isEmpty {
            userMessageContent = [
                ["type": "text", "text": userContent],
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": b64
                    ]
                ]
            ]
        } else {
            userMessageContent = userContent
        }
        
        var anthropicMessages: [[String: Any]] = []
        if let history = conversationHistory, !history.isEmpty {
            let windowSize = 6
            let windowMessages = Array(history.suffix(windowSize))
            for (idx, msg) in windowMessages.enumerated() {
                let isLast = (idx == windowMessages.count - 1)
                if isLast && msg.role == "user" {
                    anthropicMessages.append(["role": "user", "content": userMessageContent])
                } else {
                    anthropicMessages.append(["role": msg.role, "content": msg.content])
                }
            }
        } else {
            anthropicMessages.append(["role": "user", "content": userMessageContent])
        }
        
        let payload: [String: Any] = [
            "model": model,
            "system": activeSystemPrompt,
            "messages": anthropicMessages,
            "max_tokens": 2500,
            "temperature": 0.1
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
    
    // MARK: - Response Sanitization & Safety Guardrail Filter
    func sanitizeAndValidateResponse(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // Reject raw safety moderation verdicts or refusals
        if lower.contains("user safety: safe") || lower == "safe" || lower == "unsafe" || lower == "user safety: safe\nresponse safety: safe" || lower.hasPrefix("i'm sorry, but i can't help with that") || lower.hasPrefix("i cannot provide financial advice") {
            throw NSError(
                domain: "AIInference",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Model returned safety evaluation/refusal rather than analysis. Failing over to alternative model."]
            )
        }
        
        // Clean leading safety tags if accompanied by real content
        var lines = trimmed.components(separatedBy: .newlines)
        while let first = lines.first {
            let fl = first.trimmingCharacters(in: .whitespaces).lowercased()
            if fl.hasPrefix("user safety:") || fl.hasPrefix("response safety:") || fl == "safe" || fl.isEmpty {
                lines.removeFirst()
            } else {
                break
            }
        }
        
        let cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 20 {
            throw NSError(
                domain: "AIInference",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "AI response was too short or lacked substantive analysis. Failing over to alternative model."]
            )
        }
        return cleaned
    }
    
    // MARK: - Error Message Parsing
    func parseApiErrorMessage(from data: Data, statusCode: Int) -> String {
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
}
