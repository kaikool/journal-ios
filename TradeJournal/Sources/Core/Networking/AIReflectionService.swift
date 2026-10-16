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
                "winRate": (m.winRate as NSDecimalNumber).doubleValue,
                "profitFactor": m.profitFactor,
                "netPnl": (m.netPnl as NSDecimalNumber).doubleValue,
                "maxDrawdownPct": m.maxDrawdownPct,
                "edgeScore": edgeScore
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
            return "Chưa có đủ dữ liệu giao dịch để phân tích. Hãy thực hiện hoặc import ít nhất một chu kỳ giao dịch."
        }
        
        let wr = (m.winRate as NSDecimalNumber).doubleValue * 100
        let pf = m.profitFactor != nil ? String(format: "%.2f", m.profitFactor!) : "N/A"
        let score = edgeScore != nil ? "\(Int(edgeScore!))" : "N/A"
        
        switch action {
        case .ask:
            return """
            [Phân tích nội bộ]
            Câu hỏi của bạn: "\(prompt ?? "")"
            
            Dữ liệu thực tế:
            - Tổng số lệnh: \(m.totalTrades) lệnh
            - Tỷ lệ thắng (Win Rate): \(String(format: "%.1f%%", wr)) (\(m.winningTrades)W / \(m.losingTrades)L / \(m.breakevenTrades)BE)
            - Profit Factor: \(pf)
            - Điểm Edge Score v2: \(score)/100
            
            Nhận định:
            \(wr >= 50.0 ? "Hệ thống đang có tỷ lệ thắng ổn định." : "Tỷ lệ thắng dưới 50%, cần tối ưu lại điểm vào lệnh và quản lý tỷ lệ R:R.")
            \(m.loss > 0 ? "Tổng lỗ lũy kế hiện tại là \(m.loss). Cắt lỗ nghiêm ngặt là yếu tố then chốt." : "Chưa có lệnh lỗ nào được ghi nhận.")
            """
            
        case .critique:
            return """
            [Góc nhìn Huấn luyện viên]
            Nhìn vào bức tranh tổng thể:
            1. Chuỗi lệnh: Chuỗi thắng dài nhất là \(m.maxConsecutiveWins) lệnh, chuỗi thua dài nhất là \(m.maxConsecutiveLosses) lệnh.
            2. Điểm Edge Score đạt \(score)/100.
            3. Khuyến nghị: Giữ kỷ luật kích thước vị thế (position sizing), không tăng khối lượng sau chuỗi thua để tránh hiện tượng Revenge Trading.
            """
            
        case .recap:
            return """
            [Tổng kết hiệu suất]
            - Tổng lợi nhuận ròng: \(m.netPnl >= 0 ? "+" : "")\(m.netPnl)
            - Lãi gộp: \(m.profit) | Lỗ gộp: \(m.loss)
            - Phí giao dịch đã trả: \(m.fees)
            - Khối lượng giao dịch: \(m.totalVolume)
            
            Đánh giá: \(m.netPnl >= 0 ? "Kỳ giao dịch sinh lời dương. Tiếp tục duy trì quy tắc của Playbook." : "Kỳ giao dịch đang âm ròng. Đề xuất rà soát lại các lệnh vi phạm quy tắc.")
            """
        }
    }
}
