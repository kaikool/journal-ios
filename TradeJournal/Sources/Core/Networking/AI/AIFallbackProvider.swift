import Foundation

// MARK: - Bulletproof Failover Pipeline & Local Heuristics
extension AIReflectionService {
    
    // MARK: - Bulletproof Default High-Availability Pipeline
    func callDefaultProvider(
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String,
        traderProfile: TraderProfileConfig? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        conversationHistory: [AICoachMessage]? = nil
    ) async throws -> String {
        var lastCapturedError: Error?
        
        // Attempt 1: Groq High-Capability Multi-Model Pipeline (avoids 1,000 OTPM truncation)
        let groqCandidates = ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
        
        for gModel in groqCandidates {
            do {
                return try await callOpenAiCompatible(
                    endpoint: Self.groqEndpoint,
                    apiKey: AiSettingsConfig.defaultGroqKey,
                    model: gModel,
                    action: action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: language,
                    traderProfile: traderProfile,
                    chartImageBase64: nil,
                    sessionSummary: sessionSummary,
                    conversationHistory: conversationHistory
                )
            } catch {
                lastCapturedError = error
                AppLogger.warning("Groq default key model '\(gModel)' failed: \(error.localizedDescription)")
            }
        }
        
        // Attempt 2: Groq Backup Key with full model failover suite
        let backupKey = AiSettingsConfig.defaultGroqBackupKey.trimmingCharacters(in: .whitespaces)
        if !backupKey.isEmpty {
            for bModel in groqCandidates {
                do {
                    return try await callOpenAiCompatible(
                        endpoint: Self.groqEndpoint,
                        apiKey: backupKey,
                        model: bModel,
                        action: action,
                        prompt: prompt,
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: language,
                        traderProfile: traderProfile,
                        chartImageBase64: nil,
                        sessionSummary: sessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    lastCapturedError = error
                    AppLogger.warning("Groq backup key model '\(bModel)' failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Attempt 3: High-capacity OpenRouter Free Tier Fallback (up to 1,000,000 token context, no 7k TPM limit)
        let orKey = AiSettingsConfig.defaultOpenRouterKey.trimmingCharacters(in: .whitespaces)
        if !orKey.isEmpty {
            let freeModels = ["nvidia/nemotron-3.5-lightning:free", "nvidia/nemotron-3.5-super-vl:free", "liquid/lfm-2.5-2.6b:free"]
            for orModel in freeModels {
                do {
                    AppLogger.warning("Groq rate limited or exhausted. Seamlessly failing over to OpenRouter free model '\(orModel)'...")
                    return try await callOpenAiCompatible(
                        endpoint: Self.openRouterEndpoint,
                        apiKey: orKey,
                        model: orModel,
                        action: action,
                        prompt: prompt,
                        metrics: metrics,
                        edgeScore: edgeScore,
                        language: language,
                        traderProfile: traderProfile,
                        chartImageBase64: chartImageBase64,
                        chartImagesBase64: chartImagesBase64,
                        sessionSummary: sessionSummary,
                        conversationHistory: conversationHistory
                    )
                } catch {
                    AppLogger.warning("OpenRouter fallback model '\(orModel)' failed: \(error.localizedDescription)")
                }
            }
        }
        
        // If all provider tiers failed, surface the real error
        if let err = lastCapturedError {
            throw err
        }
        
        throw NSError(
            domain: "AIReflectionService",
            code: 503,
            userInfo: [NSLocalizedDescriptionKey: "AI inference service is currently unreachable. Please verify your internet connection or Groq API keys in Settings > AI Assistant."]
        )
    }
    
    // MARK: - Dynamic Groq Model Discovery & Auto-Healing
    func fetchBestActiveGroqModel(apiKey: String) async -> String? {
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
    func callSupabaseEdgeFunction(
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
    
    // MARK: - Offline Local Heuristics
    func generateLocalCoachReflection(
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
