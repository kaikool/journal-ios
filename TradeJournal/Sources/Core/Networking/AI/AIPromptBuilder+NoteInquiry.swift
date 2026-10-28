import Foundation

// MARK: - Trade Note & Order Ticket AI Inquiry Prompt Builder
extension AIPromptBuilder {
    
    /// Constructs a specialized prompt for continuous AI inquiry on a trade,
    /// directly evaluating the trade execution against the Pre-Trade Bias recorded in notes,
    /// complete with pre-entry candlestick trajectory and confirmation entry audit.
    public static func buildTradeNoteInquiryPrompt(
        trade: Trade,
        noteContent: String,
        parsedPreTrade: ParsedPreTradeNote?,
        orderTicket: String?,
        userQuestion: String? = nil,
        bars: [MarketBar]? = nil,
        language: String = "vi",
        displayTimeZone: String = "UTC"
    ) -> String {
        let isVi = language == "vi"
        let displayTz = TimeZone(identifier: displayTimeZone) ?? .current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.timeZone = displayTz
        
        let hasExecutedTrade = trade.avgEntry > 0 && trade.key != "note-trade"
        let openedAtStr = df.string(from: trade.openedAt)
        let closedAtStr = trade.closedAt.map { df.string(from: $0) } ?? (isVi ? "Đang mở" : "Open")
        let ticketStr = orderTicket ?? trade.executionIds.first ?? trade.id
        let pnlStr = Formatters.currency(trade.netPnl)
        let entryStr = Formatters.price(trade.avgEntry)
        let exitStr = trade.avgExit.map { Formatters.price($0) } ?? (trade.status == .open ? (isVi ? "Đang mở" : "Open") : "N/A")
        let dirStr = trade.direction == .short ? "SELL (SHORT)" : "BUY (LONG)"
        
        var planBlock = ""
        if let plan = parsedPreTrade {
            if isVi {
                planBlock = """
                [KẾ HOẠCH PRE-TRADE BIAS ĐÃ LƯU TRONG GHI CHÚ (NOTE)]:
                • Symbol: \(plan.symbol.isEmpty ? trade.symbol : plan.symbol) | Bias đã chọn: \(plan.bias)
                • Vùng vào lệnh dự kiến (Planned Entry): \(plan.plannedEntry ?? "Thị trường")
                • Cắt lỗ dự kiến (Planned SL): \(plan.invalidationSL ?? "Theo cấu trúc")
                • Chốt lời dự kiến (Planned TP): \(plan.targetTP ?? "Vùng thanh khoản")
                • Luận điểm phân tích: \(plan.thesisSummary)
                """
            } else {
                planBlock = """
                [PRE-TRADE BIAS RECORDED IN NOTE]:
                • Symbol: \(plan.symbol.isEmpty ? trade.symbol : plan.symbol) | Bias: \(plan.bias)
                • Planned Entry Zone: \(plan.plannedEntry ?? "Market")
                • Planned Stop Loss: \(plan.invalidationSL ?? "Structural")
                • Planned Take Profit: \(plan.targetTP ?? "Liquidity Pool")
                • Stated Thesis: \(plan.thesisSummary)
                """
            }
        }
        
        // 1. Pre-Entry Price Trajectory & Confirmation Entry Audit (only when actual trade executed)
        let trajectoryBlock = hasExecutedTrade ? computePreEntryTrajectory(
            trade: trade,
            plannedZone: parsedPreTrade?.plannedEntry,
            bars: bars,
            displayTimeZone: displayTz,
            isVi: isVi
        ) : ""
        
        // 2. Candlestick Tape Markdown Table
        let candlesTableBlock: String = {
            guard let b = bars, !b.isEmpty else { return "" }
            let table = CandleTapeFormatter.formatCandlesTable(
                bars: b,
                count: 14,
                symbol: trade.symbol,
                displayTimeZone: displayTz
            )
            return isVi ? """
            
            [BẢNG BĂNG GIÁ NẾN M15 THỰC TẾ XUNG QUANH THỜI ĐIỂM VÀO LỆNH]:
            \(table)
            """ : """
            
            [ACTUAL M15 CANDLESTICK TAPE SURROUNDING EXECUTION]:
            \(table)
            """
        }()
        
        // 3. Technical Momentum Table (Wilder RSI 14 / EMA 9 / WMA 45 across 15-candle window)
        let momentumBlock: String = {
            guard let b = bars, !b.isEmpty else { return "" }
            let window = MomentumEngine.computeWindow(bars: b, windowSize: 15)
            let formatted = MomentumEngine.formatMomentumTable(
                window: window,
                displayTimeZone: displayTz,
                isVi: isVi
            )
            return formatted.isEmpty ? "" : "\n\n" + formatted
        }()
        
        let questionBlock: String
        if let q = userQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isVi {
                questionBlock = """
                
                [CÂU HỎI TIẾP THEO CỦA TRADER TRONG BUỔI TRAO ĐỔI]:
                "\(q)"
                """
            } else {
                questionBlock = """
                
                [TRADER'S FOLLOW-UP INQUIRY]:
                "\(q)"
                """
            }
        } else {
            questionBlock = ""
        }
        
        // Long-term memories and lessons
        let lessonsBlock = AIAdvisorMemoryEngine.shared.formatMemoriesForPrompt(
            symbol: trade.symbol,
            isVi: true,
            maxItems: 4
        )
        
        let researchBlock = AIResearchWorkspaceEngine.shared.formatProjectsForPrompt(
            symbol: trade.symbol,
            isVi: isVi
        )
        
        let executionBlockVi = hasExecutedTrade ? """
        [THÔNG TIN LỆNH THỰC TẾ]:
        - Mã vé lệnh (Order Ticket): #\(ticketStr)
        - Cặp tiền / Tài sản: \(trade.symbol)
        - Hướng lệnh: \(dirStr)
        - Khối lượng: \(String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)) lots
        - Giá vào thực tế (Actual Entry): \(entryStr) lúc \(openedAtStr)
        - Giá đóng thực tế (Actual Exit): \(exitStr) lúc \(closedAtStr)
        - Kết quả tài chính: \(trade.status.rawValue.uppercased()) | Lợi nhuận ròng: \(pnlStr)
        """ : """
        [BỐI CẢNH GHI CHÚ / KẾ HOẠCH GIAO DỊCH]:
        - Trạng thái: Kế hoạch độc lập / Chưa khớp lệnh giao dịch thực tế trên tài khoản
        - Cặp tiền / Tài sản: \(trade.symbol)
        """
        
        let executionBlockEn = hasExecutedTrade ? """
        [ACTUAL EXECUTION DATA]:
        - Order Ticket: #\(ticketStr)
        - Instrument: \(trade.symbol)
        - Direction: \(dirStr)
        - Volume: \(String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)) lots
        - Actual Entry: \(entryStr) at \(openedAtStr)
        - Actual Exit: \(exitStr) at \(closedAtStr)
        - Financial Outcome: \(trade.status.rawValue.uppercased()) | Net P&L: \(pnlStr)
        """ : """
        [NOTE & PRE-TRADE CONTEXT]:
        - Status: Independent journal plan (No executed trade on account yet)
        - Instrument: \(trade.symbol)
        """
        
        let section1Vi = hasExecutedTrade ? """
        ### 1. Đối chiếu Kế hoạch Pre-Trade, Thực thi Lệnh & Động lượng RSI
        - Đối chiếu hành trình nến và điểm vào: Trước khi vào lệnh, giá đã từng test/quét vùng kế hoạch chưa? Điểm vào \(entryStr) là điểm vào xác nhận (Confirmation Entry) theo hành động giá nến hay vào lệnh tự phát?
        - Phân tích Động lượng RSI Core (BẮT BUỘC TRÍCH DẪN SỐ LIỆU TỪ BẢNG ĐỘNG LƯỢNG 15 NẾN):
          • BẮT BUỘC GHI RÕ SỐ LIỆU: RSI(14) Wilder = [số cụ thể], EMA(9) = [số cụ thể], WMA(45) = [số cụ thể] tại thời điểm vào lệnh.
          • So sánh EMA(9) với WMA(45): Lớn hơn, nhỏ hơn hay đang sát nhau (Squeeze)?
          • Tương quan 3 đường: RSI nằm trên hay dưới EMA9 và WMA45? Động lượng có đồng thuận ủng hộ điểm vào xác nhận này không?
        """ : """
        ### 1. Thẩm định Luận điểm Kế hoạch & Động lượng RSI M15 Hiện tại
        - Đánh giá tính khả thi và logic cấu trúc của kế hoạch trong ghi chú.
        - Phân tích Động lượng RSI Core (BẮT BUỘC TRÍCH DẪN SỐ LIỆU TỪ BẢNG ĐỘNG LƯỢNG 15 NẾN):
          • BẮT BUỘC GHI RÕ SỐ LIỆU: RSI(14) Wilder = [số cụ thể], EMA(9) = [số cụ thể], WMA(45) = [số cụ thể] tại nến mới nhất.
          • So sánh EMA(9) với WMA(45): Lớn hơn, nhỏ hơn hay đang sát nhau (Squeeze)?
          • Tương quan 3 đường: Động lượng RSI hiện tại ủng hộ hay cảnh báo rủi ro cho kịch bản này?
        """
        
        let section1En = hasExecutedTrade ? """
        ### 1. Pre-Trade Plan vs. Execution Alignment & RSI Core Momentum
        - Cross-examine price action: Prior to execution, did price tap or sweep the planned zone? Does \(entryStr) represent a disciplined Confirmation Entry?
        - RSI Core Momentum Assessment (MANDATORY METRIC CITATION FROM 15-CANDLE TABLE):
          • MANDATORY METRIC CITATION: State exact numbers: Wilder RSI(14) = [value], EMA(9) = [value], WMA(45) = [value] at execution.
          • Compare EMA(9) vs WMA(45) (Greater, lesser, or converging Squeeze?):
          • 3-Line Alignment: Was RSI operating above or below EMA9 and WMA45? Did momentum support the execution?
        """ : """
        ### 1. Plan Thesis Assessment & Current M15 RSI Momentum
        - Evaluate structural validity and setup feasibility of the note plan.
        - RSI Core Momentum Assessment (MANDATORY METRIC CITATION FROM 15-CANDLE TABLE):
          • MANDATORY METRIC CITATION: State exact numbers: Wilder RSI(14) = [value], EMA(9) = [value], WMA(45) = [value] at latest candle.
          • Compare EMA(9) vs WMA(45) (Greater, lesser, or converging Squeeze?):
          • 3-Line Alignment: Does momentum support the scenario or warn of risk?
        """
        
        if isVi {
            return """
            HỘI THẢO PHẢN BIỆN LỆNH & GHI CHÚ GIAO DỊCH (TRADE NOTE & TICKET INQUIRY):
            
            \(executionBlockVi)
            
            \(planBlock)
            \(trajectoryBlock)
            \(candlesTableBlock)\(momentumBlock)
            
            [NỘI DUNG GHI CHÚ ĐẦY ĐỦ CỦA TRADER]:
            \"\"\"
            \(noteContent)
            \"\"\"
            \(lessonsBlock)\(researchBlock)\(questionBlock)
            
            CẤU TRÚC PHẢN HỒI:
            
            \(section1Vi)
            
            ### 2. Thẩm định Kịch bản AI & Kết quả Thực tế
            - Kịch bản ban đầu của AI đưa ra là ĐÚNG hay SAI?
            - Đánh giá khách quan nguyên nhân thành công hoặc thất bại (yếu tố cấu trúc thị trường, vùng thanh khoản hay phản ứng giá).
            
            ### 3. Trả lời Câu hỏi của Trader & Phương án Quản trị
            - Phản hồi trực diện, trung thực vào thắc mắc của trader (nếu có).
            - Đưa ra giải pháp xử lý hoặc cách xử lý tối ưu trong tình huống tương tự.
            
            ### 4. Bài học Đúc kết cho Lần sau (Actionable Lesson)
            - [Quy tắc ngắn gọn 1-2 câu để áp dụng cho các lệnh tương lai trên \(trade.symbol)]
            """
        } else {
            return """
            TRADE NOTE & ORDER TICKET INQUIRY AUDIT:
            
            \(executionBlockEn)
            
            \(planBlock)
            \(trajectoryBlock)
            \(candlesTableBlock)\(momentumBlock)
            
            [FULL NOTE CONTENT]:
            \"\"\"
            \(noteContent)
            \"\"\"
            \(lessonsBlock)\(researchBlock)\(questionBlock)
            
            STRUCTURE:
            
            \(section1En)
            ### 2. Thesis Outcome & Market Mechanics
            ### 3. Inquiry Response & Risk Assessment
            ### 4. Actionable Lesson
            """
        }
    }
}
