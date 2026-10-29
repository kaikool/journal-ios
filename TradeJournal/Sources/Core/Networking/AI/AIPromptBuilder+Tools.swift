import Foundation

// MARK: - AI Tool Capabilities & Formatting Extension (Module F)
extension AIPromptBuilder {
    
    /// Formats deterministic tool descriptions for AI prompt inclusion
    public static func formatToolCapabilities(isVi: Bool = true) -> String {
        if isVi {
            return """
            
            [CÔNG CỤ TÍNH TOÁN XÁC THỰC SỐ LIỆU (DETERMINISTIC TOOLS)]:
            Hệ thống cung cấp sẵn các công cụ trích xuất dữ liệu thực tế (Tuyệt đối không tự bịa số liệu):
            • `query_trades`: Truy vấn và tính toán Win Rate, Profit Factor, P&L ròng của các lệnh trong quá khứ.
            • `query_market_structure`: Xác định đỉnh/đáy Swing, trạng thái MSS và các đợt quét thanh khoản (Sweeps).
            • `query_trade_excursions`: Đo lường sụt giảm tối đa (MAE) và lợi nhuận tiềm năng cực đại (MFE).
            • `query_memories`: Truy xuất bài học từ sai lầm quá khứ, cam kết kỷ luật và quy tắc đã thống nhất.
            • `query_research_projects`: Kiểm tra tiến độ và kết quả xác minh các giả thuyết nghiên cứu dài hạn.
            • `query_economic_calendar`: Tra cứu các sự kiện kinh tế Đỏ (High Impact) và thời gian đếm ngược.
            """
        } else {
            return """
            
            [DETERMINISTIC FACTUAL TOOLS]:
            The system provides exact calculation tools (Never guess or hallucinate metrics):
            • `query_trades`: Queries and computes exact Win Rate, Profit Factor, and net P&L across historical trades.
            • `query_market_structure`: Measures Swing Highs/Lows, MSS status, and liquidity sweeps.
            • `query_trade_excursions`: Measures exact Max Adverse Excursion (MAE) and Max Favorable Excursion (MFE).
            • `query_memories`: Retrieves persistent failure lessons, discipline commitments, and verified rules.
            • `query_research_projects`: Checks empirical research hypotheses, sample progress, and validation results.
            • `query_economic_calendar`: Checks upcoming High-Impact macro events and exact release countdowns.
            """
        }
    }
}
