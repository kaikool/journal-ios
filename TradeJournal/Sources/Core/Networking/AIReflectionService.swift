import Foundation

public enum AIReflectionAction: String, Codable {
    case ask = "ask"
    case critique = "critique"
    case recap = "recap"
}

public struct AIReflectionResponse: Codable {
    public let action: String
    public let reflection: String
}

public actor AIReflectionService {
    public static let shared = AIReflectionService()
    
    private init() {}
    
    /// Requests AI reflection via Supabase Edge Function or offline coach heuristics
    public func requestReflection(
        action: AIReflectionAction,
        prompt: String? = nil,
        metrics: TradeMetrics? = nil,
        edgeScore: Double? = nil,
        supabaseUrl: String? = nil,
        authToken: String? = nil
    ) async throws -> String {
        guard let urlString = supabaseUrl, !urlString.isEmpty, let token = authToken, !token.isEmpty else {
            // Offline / Local Development Fallback Coach Heuristic
            return generateLocalCoachReflection(action: action, metrics: metrics, edgeScore: edgeScore, prompt: prompt)
        }
        
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
