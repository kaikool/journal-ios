import Foundation

// MARK: - AI Prompt Builder Candle Series, Trajectory & Ensemble Synthesis Helpers
extension AIPromptBuilder {

    // MARK: - Live Unclosed Candle Dynamics Helper
    public static func buildLiveUnclosedCandlePulse(bar: MarketBar?, isVi: Bool) -> String {
        guard let b = bar else {
            return isVi ? "Chưa có dữ liệu nến sống" : "No live candle data"
        }
        let fmt = Formatters.rawPrice
        
        let delta = b.close - b.open
        let deltaStr = (delta >= 0 ? "+" : "") + fmt(delta)
        let bodyType = delta >= 0 ? (isVi ? "TĂNG" : "BULLISH") : (isVi ? "GIẢM" : "BEARISH")
        
        let upperWick = b.high - max(b.open, b.close)
        let lowerWick = min(b.open, b.close) - b.low
        let upperWickStr = fmt(upperWick)
        let lowerWickStr = fmt(lowerWick)
        
        let rejectionDesc: String = {
            if upperWick > lowerWick * 2 && upperWick > 0 {
                return isVi ? "Râu trên dài (\(upperWickStr)) -> Phe Bán đang từ chối giá cao" : "Long upper wick (\(upperWickStr)) -> Sellers rejecting highs"
            }
            if lowerWick > upperWick * 2 && lowerWick > 0 {
                return isVi ? "Râu dưới dài (\(lowerWickStr)) -> Phe Mua đang từ chối giá thấp (Rút chân)" : "Long lower wick (\(lowerWickStr)) -> Buyers rejecting lows"
            }
            return isVi ? "Thân nến đang phát triển cân bằng" : "Developing candle body"
        }()
        
        if isVi {
            return "  - Nến hiện tại: Mở: \(fmt(b.open)) | Cao: \(fmt(b.high)) | Thấp: \(fmt(b.low)) | Hiện tại: \(fmt(b.close))\n  - Trạng thái nến sống: [\(bodyType) \(deltaStr)] | Râu trên: \(upperWickStr) | Râu dưới: \(lowerWickStr)\n  - Hành vi giá sống: \(rejectionDesc)"
        } else {
            return "  - Live Candle: O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | Live: \(fmt(b.close))\n  - Real-time State: [\(bodyType) \(deltaStr)] | Upper Wick: \(upperWickStr) | Lower Wick: \(lowerWickStr)\n  - Live Action Insight: \(rejectionDesc)"
        }
    }

    // MARK: - 3-Candle H4 Summary Helper
    public static func buildH4CandleSummary(bars: [MarketBar], count: Int = 3, isVi: Bool = true) -> String {
        guard !bars.isEmpty else { return isVi ? "Không có dữ liệu nến H4" : "No H4 candle data" }
        let slice = bars.suffix(count)
        let fmt = Formatters.rawPrice
        
        let n = slice.count
        var lines: [String] = []
        for (idx, b) in slice.enumerated() {
            let offset = n - 1 - idx
            let label = offset == 0 ? (isVi ? "H4 [Nến hiện tại]" : "H4 [Live Candle]") : "H4 [-\(offset * 4)h]"
            lines.append("  - \(label): O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | C: \(fmt(b.close))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 24-Candle H1 Execution Series Helper (OHLC + Wilder RSI 14)
    public static func buildH1CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 24,
        symbol: String = "",
        isVi: Bool = true
    ) -> String {
        guard !bars.isEmpty else { return isVi ? "Không có dữ liệu nến H1" : "No H1 candle data" }
        
        let momentumWindow = MomentumEngine.computeWindow(bars: bars, windowSize: count)
        
        let n = bars.count
        let takeCount = min(count, n)
        let startIndex = n - takeCount
        
        let rsiMap: [Int64: Decimal] = {
            var map: [Int64: Decimal] = [:]
            for p in momentumWindow.points {
                map[Int64(p.date.timeIntervalSince1970 * 1000)] = p.rsi14
            }
            return map
        }()
        
        let fmt = Formatters.rawPrice
        
        var lines: [String] = []
        for i in startIndex..<n {
            let bar = bars[i]
            let offset = n - 1 - i
            let timeLabel = offset == 0 ? (isVi ? "[Nến sống]" : "[Live]") : "[-t-\(offset)h]"
            
            let rsiVal: String = {
                if let r = rsiMap[bar.timestamp] {
                    return String(format: "%.1f", (r as NSDecimalNumber).doubleValue)
                }
                let ptIndex = i - (n - momentumWindow.points.count)
                if ptIndex >= 0 && ptIndex < momentumWindow.points.count {
                    let r = momentumWindow.points[ptIndex].rsi14
                    return String(format: "%.1f", (r as NSDecimalNumber).doubleValue)
                }
                return "N/A"
            }()
            
            let num = lines.count + 1
            let numStr = num < 10 ? "0\(num)" : "\(num)"
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close)) | RSI: \(rsiVal)"
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }

    // MARK: - 16-Candle M15 Micro-Execution Series Helper
    public static func buildM15CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 16,
        symbol: String = "",
        isVi: Bool = true
    ) -> String {
        guard !bars.isEmpty else { return isVi ? "Không có dữ liệu nến M15" : "No M15 candle data" }
        
        let n = bars.count
        let takeCount = min(count, n)
        let startIndex = n - takeCount
        
        let fmt = Formatters.rawPrice
        
        var lines: [String] = []
        for i in startIndex..<n {
            let bar = bars[i]
            let offset = n - 1 - i
            let timeLabel = offset == 0 ? (isVi ? "[Nến sống]" : "[Live]") : "[-t-\(offset * 15)m]"
            let num = lines.count + 1
            let numStr = num < 10 ? "0\(num)" : "\(num)"
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close))"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Multi-Model Ensemble Distillation & Synthesis Prompt (RISK AI)
    public static func distillAnalysis(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 6000 {
            return clean
        }
        return String(clean.prefix(6000)) + "\n[...cắt ngắn để tối ưu ngữ cảnh...]"
    }
    
    public static func buildEnsembleSynthesisPrompt(
        symbol: String,
        currentPrice: String,
        balance: String,
        riskDollars: String,
        riskPercent: Decimal,
        targetRR: Double,
        analyses: [String],
        isVi: Bool = true,
        technicalGroundTruth: String? = nil
    ) -> String {
        var analysesBlock = ""
        for (idx, a) in analyses.enumerated() {
            let num = idx + 1
            analysesBlock += """
            ==================================================
            [GÓC NHÌN PHÂN TÍCH ĐỘC LẬP \(num)]:
            \(distillAnalysis(a))
            
            """
        }
        
        let targetRRStr = String(format: "%.1f", targetRR)
        let groundTruthSection = technicalGroundTruth.map { gt in
            isVi ? """
            [BẢNG THAM CHIẾU KỸ THUẬT CHUẨN XÁC TỪ SÀN (GROUND TRUTH)]:
            \(gt)
            QUY TẮC BẮT BUỘC VỀ DỮ LIỆU KỸ THUẬT:
            Mọi mốc giá Entry, Stop Loss, Take Profit và đặc biệt là mốc EMA 21, EMA 50, và trạng thái 3 đường RSI (RSI 14 / EMA 9 / WMA 45) BẮT BUỘC PHẢI KHỚP CHÍNH XÁC với BẢNG THAM CHIẾU KỸ THUẬT ở trên. TUYỆT ĐỐI KHÔNG tự bịa ra hoặc làm tròn sai lệch mốc EMA 21/50.
            """ : """
            [AUTHORITATIVE TECHNICAL GROUND TRUTH (BROKER FEED)]:
            \(gt)
            MANDATORY TECHNICAL DATA ACCURACY:
            All price levels for Entry, Stop Loss, Take Profit, and specifically EMA 21, EMA 50, and 3-line RSI (RSI 14 / EMA 9 / WMA 45) MUST EXACTLY MATCH THE GROUND TRUTH TABLE ABOVE. Never hallucinate or alter moving average values.
            """
        } ?? ""
        
        if isVi {
            return """
            BẠN LÀ RISK AI - GIÁM ĐỐC QUẢN TRỊ RỦI RO & TỐI ƯU HÓA LỆNH CỦA QUỸ ĐẦU TƯ TÀI CHÍNH (CHIEF RISK OFFICER).

            [BỐI CẢNH THỊ TRƯỜNG & TÀI KHOẢN]:
            - Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)
            - Số dư tài khoản: \(balance) | Ngân sách rủi ro tối đa: \(riskDollars) (\(riskPercent)% vốn)
            - Mục tiêu tỷ lệ Risk/Reward tham chiếu: 1:\(targetRRStr)
            \(groundTruthSection)
            Dưới đây là \(analyses.count) bản phân tích kỹ thuật độc lập được lập từ cùng một tập dữ liệu nến (D1, H4, H1, M15), tin tức kinh tế và quy tắc tài khoản cho cặp \(symbol):

            \(analysesBlock)==================================================

            [NHIỆM VỤ TỔNG HỢP & NGUYÊN TẮC PHÂN XỬ BẮT BUỘC]:
            Nhiệm vụ của bạn là đối chiếu các góc nhìn trên để đúc kết thành MỘT BẢN PHÂN TÍCH DUY NHẤT VÀ CHẶT CHẼ NHẤT mang tên RISK AI.
            Tuyệt đối không nhắc đến "góc nhìn 1/2/3", "mô hình AI", hay bất kỳ từ ngữ "hội đồng" nào. Bạn chính là thực thể RISK AI duy nhất phát ngôn trực tiếp với trader.

            BẮT BUỘC ÁP DỤNG BỘ QUY TẮC 4 TẦNG HÀNH ĐỘNG QUYẾT ĐOÁN:

            1. PHÂN XỬ CẤU TRÚC XU HƯỚNG D1 & H4:
            - Xác định xu hướng chủ đạo qua liên kết EMA 21 & EMA 50.
            - Nếu EMA D1/H4 thiên TĂNG: Định hướng chủ đạo là BUY (Long) khi giá hồi về các vùng hỗ trợ EMA.
            - Nếu EMA D1/H4 thiên GIẢM: Định hướng chủ đạo là SELL (Short) khi giá hồi lên các vùng kháng cự EMA.

            2. PHÂN XỬ CẤU TRÚC H4 & CÁC VÙNG CẢN QUAN TRỌNG:
            - VÙNG GIÁ QUAN TÂM: Là các mốc giá kiểm tra EMA 21/50 hoặc Swing High/Low có sự đồng thuận cao nhất để thiết lập điểm vào (Entry).
            - CẢN QUAN TRỌNG: Mốc đỉnh/đáy đối diện dùng làm mục tiêu Chốt Lời (TP 1 / TP 2) để bảo vệ lợi nhuận.

            3. PHÂN XỬ TÍN HIỆU H1/M15 & HỆ THỐNG 3 ĐƯỜNG RSI:
            - Kết hợp hành động giá nến với hệ thống 3 đường RSI (RSI 14 / EMA 9 / WMA 45).
            - Nếu tín hiệu H1/M15 đã có nến xác nhận hoặc chạm vùng EMA và RSI ủng hộ: Cho phép vào lệnh Market.
            - Nếu giá đang lưng chừng hoặc cần điểm vào đẹp hơn: Thiết lập lệnh CHỜ (Limit Order) tại vùng kiểm tra EMA 21/50 thay vì đứng ngoài!

            4. PHÂN XỬ KẾ HOẠCH GIAO DỊCH & QUẢN TRỊ RỦI RO (QUYẾT ĐOÁN):
            - Điểm Dừng Lỗ (Stop Loss): BẮT BUỘC CHỌN MỐC SL AN TOÀN VÀ KỶ LUẬT NHẤT.
            - BẮT BUỘC ĐƯA RA HƯỚNG LỆNH CỤ THỂ (BUY hoặc SELL) bám sát xu hướng chủ đạo của EMA:
              + Tuyệt đối KHÔNG được kết luận FLAT chỉ vì giá đang nằm giữa Swing High và Swing Low.
              + Nếu có bất đồng ý kiến về rủi ro: VẪN ĐƯA RA LỆNH BUY hoặc SELL nhưng khuyến nghị vào lệnh bằng lệnh chờ Limit tại vùng EMA và giảm 50% khối lượng (Volume).
              + Chỉ kết luận FLAT khi thị trường hoàn toàn bất động / biên độ sideway cực hẹp không có sóng giao dịch.
            - Tỷ lệ R:R: Tối ưu điểm Entry và SL để hướng tới mục tiêu R:R tối thiểu 1:\(targetRRStr) theo hồ sơ trader.

            --------------------------------------------------
            ĐỊNH DẠNG ĐẦU RA BẮT BUỘC (ĐÚNG CHUẨN 4 PHẦN CHUYÊN NGHIỆP):

            ### 1. Cấu trúc D1
            (Phân tích xu hướng chủ đạo D1, vị trí so với EMA 21/50 và biên độ PDH/PDL).

            ### 2. Cấu trúc H4 & Các Vùng Giá Trị
            - Vùng giá nên quan sát: [Chỉ rõ các mốc giá cụ thể của vùng hỗ trợ/kháng cự EMA 21/50 và Swing High/Low]
            - Mốc chốt chặn rủi ro: [Chỉ rõ mốc giá vi phạm cấu trúc để đặt Stop Loss]

            ### 3. Tín hiệu vào lệnh H1/M15
            (Đánh giá hành động giá nến H1/M15, phản ứng tại EMA, và hệ thống 3 đường RSI 14 / EMA 9 / WMA 45).

            ### 4. Kế hoạch giao dịch & Quản trị rủi ro
            - Hướng lệnh: [BUY hoặc SELL] (Chỉ chọn FLAT nếu thị trường chết thanh khoản)
            - Điểm vào tối ưu (Entry): [Mức giá cụ thể]
            - Dừng lỗ (Stop Loss): [Mức giá cụ thể]
            - Chốt lời (Take Profit): TP 1 tại [Mức giá] | TP 2 tại [Mức giá nếu có]
            - Khối lượng (Volume): [Khối lượng lot cụ thể, ví dụ: 0.50 lot]
            - Tỷ lệ R:R: [1:\(targetRRStr)]
            - Quản lý lệnh: [1-2 câu ngắn gọn về dời SL bảo vệ vị thế khi nến xác nhận]

            QUY TẮC BẮT BUỘC CHO PHẦN 4:
            Chỉ xuất thông số rõ ràng, dứt khoát, chuẩn phong cách quỹ tài chính. TUYỆT ĐỐI KHÔNG viết kèm các giải thích rườm rà trong ngoặc đơn như "(tính toán chính xác dựa trên...)", "(bảo vệ phía trên...)", "(theo hồ sơ...)".

            BẮT BUỘC KẾT THÚC BẰNG BẢNG THÔNG SỐ VÀ KHỐI JSON:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY hoặc SELL hoặc FLAT]
            - Balance: \(balance)
            - Entry: [Mức giá hoặc null]
            - Stop loss: [Mức giá hoặc null]
            - Take profit 1: [Mức giá hoặc null]
            - Take profit 2: [Mức giá hoặc None]
            - R:R Ratio: 1:\(targetRRStr)
            - Volume: [Khối lượng lot khuyến nghị tính theo số tiền rủi ro \(riskDollars), ví dụ 0.50 lot]
            - Date time: [Thời gian hiện tại]

            ```json
            {
              "direction": "[BUY hoặc SELL hoặc FLAT]",
              "entry": [mức giá dạng số hoặc null],
              "stopLoss": [mức giá dạng số hoặc null],
              "takeProfit1": [mức giá dạng số hoặc null],
              "takeProfit2": [mức giá dạng số hoặc null],
              "riskRewardRatio": "1:\(targetRRStr)",
              "volume": "[ví dụ 0.50 lot]"
            }
            ```

            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng của nhà giao dịch chuyên nghiệp]
            """
        } else {
            return """
            YOU ARE RISK AI - CHIEF RISK OFFICER & TRADE SIZING STRATEGIST FOR INSTITUTIONAL CAPITAL.

            [MARKET & CAPITAL CONTEXT]:
            - Symbol: \(symbol) | Current Price: \(currentPrice)
            - Account Balance: \(balance) | Max Risk Budget: \(riskDollars) (\(riskPercent)%)
            - Target Risk/Reward Ratio Benchmark: 1:\(targetRRStr)
            \(groundTruthSection)
            Below are \(analyses.count) independent technical evaluations generated from identical multi-timeframe candles (D1, H4, H1, M15), economic news, and account risk guardrails for \(symbol):

            \(analysesBlock)==================================================

            [RECONCILIATION DIRECTIVE & STRICT CONFLICT RESOLUTION RULES]:
            Synthesize the independent perspectives above into ONE SINGLE AUTHORITATIVE PRE-TRADE PLAN as RISK AI.
            Never mention "Perspective 1/2/3", "AI models", or "council". You speak with one single voice as RISK AI.

            APPLY THE 4-TIER DECISIVE CONFLICT RESOLUTION PROTOCOL:
            1. D1 & H4 TREND RESOLUTION:
            - Determine macro trend based on multi-timeframe EMA 21 and EMA 50 alignment.
            - If D1/H4 is BULLISH: Primary directive is BUY on pullbacks to EMA support.
            - If D1/H4 is BEARISH: Primary directive is SELL on rallies to EMA resistance.

            2. H4 STRUCTURE & KEY PRICE BARRIERS:
            - KEY AREAS OF INTEREST: Highest-consensus EMA 21/50 test levels and structural swing points.
            - OPPOSING BARRIERS: Treat opposing swing highs/lows as Take Profit targets.

            3. H1/M15 CONFIRMATION & 3-LINE RSI RESOLUTION:
            - Evaluate live candle price action against 3-line RSI momentum state (RSI 14 / EMA 9 / WMA 45).
            - If price has reached the EMA value zone with rejection: Permit Market entry.
            - If price is extended: Mandate condition-based pending Limit orders at the EMA pullback level rather than standing aside!

            4. TRADE PLAN & STOP LOSS RESOLUTION (MANDATE DECISIVE ACTION):
            - STOP LOSS PLACEMENT: Select the safest, most disciplined structural stop loss.
            - MANDATE ACTIONABLE SETUP (BUY OR SELL):
              + NEVER default to FLAT merely because price is between Swing High and Swing Low.
              + If dissenting views express risk caution: Still maintain directional bias with reduced volume (50%) and pending limit entry at EMA support/resistance.
              + Only conclude FLAT if market volatility is genuinely dead (< 15% of ADR).
            - RISK/REWARD: Align entry and SL to achieve target 1:\(targetRRStr) R:R.

            OUTPUT FORMAT (STANDARD 4 SECTIONS):
            ### 1. D1 Structure
            ### 2. H4 Structure & Key Zones
            - Key Areas of Interest: [Specific price levels]
            - Structural Invalidation Level: [Specific price level]
            ### 3. H1/M15 Entry Confirmations
            (Read live candle pulse, reaction at EMA, and 3-line RSI momentum).
            ### 4. Trade Plan & Risk Management
            - Verdict: [BUY or SELL] (Only FLAT if dead volatility < 15% ADR)
            - Entry: [Precise price]
            - Stop Loss: [Precise SL price]
            - Take Profit: TP 1 at [Price] | TP 2 at [Price if any]
            - Volume: [Lot size, e.g. 0.50 lot]
            - R:R Ratio: [1:\(targetRRStr)]
            - Trade Management: [1-2 concise sentences on trailing SL]

            STRICT FORMATTING RULE FOR SECTION 4:
            State clear, exact numbers and directives. STRICTLY PROHIBIT verbose parenthetical justifications like "(calculated based on...)", "(protecting above...)", or "(according to profile...)". Keep it clean, direct, and institutional.

            CONCLUDE WITH [PRE-TRADE SETUP SPECIFICATION] AND JSON BLOCK.
            """
        }
    }

    // MARK: - Pre-Entry Candlestick Trajectory & Confirmation Entry Audit Computation
    public static func computePreEntryTrajectory(
        trade: Trade,
        plannedZone: String?,
        bars: [MarketBar]?,
        displayTimeZone: TimeZone,
        isVi: Bool
    ) -> String {
        guard let allBars = bars, !allBars.isEmpty else { return "" }

        let entryDate = trade.openedAt
        let preBars = allBars.filter { $0.date <= entryDate }
        let relevantBars = preBars.isEmpty ? Array(allBars.suffix(12)) : Array(preBars.suffix(12))
        guard !relevantBars.isEmpty else { return "" }

        let maxHigh = relevantBars.map(\.high).max() ?? trade.avgEntry
        let minLow = relevantBars.map(\.low).min() ?? trade.avgEntry
        let maxHighStr = Formatters.price(maxHigh)
        let minLowStr = Formatters.price(minLow)
        let entryStr = Formatters.price(trade.avgEntry)
        let plannedEntry = plannedZone?.isEmpty == false ? (plannedZone ?? "") : (isVi ? "Vùng kỹ thuật" : "Technical setup zone")

        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        df.timeZone = displayTimeZone
        let entryTime = df.string(from: trade.openedAt)

        let isShort = trade.direction == .short
        let extremePriceStr = isShort ? maxHighStr : minLowStr
        let zoneActionStrVi = isShort
            ? "TĂNG CHẠM CỰC ĐẠI: \(maxHighStr) (TEST/QUÉT VÙNG CUNG)"
            : "GIẢM CHẠM CỰC TIỂU: \(minLowStr) (TEST/QUÉT VÙNG CẦU)"
        let zoneActionStrEn = isShort
            ? "rallied to peak at \(maxHighStr) (TESTED SUPPLY)"
            : "dropped to trough at \(minLowStr) (TESTED DEMAND)"

        let setupTypeVi = isShort ? "vùng cung" : "vùng cầu"
        let setupActionVi = isShort ? "bán dưới vùng cung" : "mua trên vùng cầu"
        let setupActionEn = isShort ? "selling below supply" : "buying above demand"

        if isVi {
            return """

            [HÀNH TRÌNH GIÁ TRƯỚC KHI VÀO LỆNH (PRE-ENTRY PRICE TRAJECTORY & CONFIRMATION AUDIT)]:
            • Thời điểm vào lệnh: lúc \(entryTime) ở mức giá \(entryStr)
            • Diễn biến nến M15 trước lệnh: Cao nhất: \(maxHighStr) | Thấp nhất: \(minLowStr)
            • ĐỐI CHIẾU THỰC TẾ VỚI KẾ HOẠCH:
              - Kế hoạch dự kiến: [\(plannedEntry)]
              - Thực tế thị trường: Nến M15 ĐÃ TỪNG \(zoneActionStrVi)!
              - Sau khi chạm mốc \(extremePriceStr), giá đảo chiều đóng nến tại \(entryStr) -> Trader vào lệnh theo đúng TÍN HIỆU XÁC NHẬN (CONFIRMATION ENTRY / MSS)!

            [NGUYÊN TẮC THỰC THI]: Giá đã kiểm tra \(setupTypeVi) (\(extremePriceStr)) rồi mới xác nhận ở \(entryStr). Đây là lệnh xác nhận kỷ luật, không phê phán là vào sớm hay \(setupActionVi).
            """
        } else {
            return """

            [PRE-ENTRY PRICE TRAJECTORY & CONFIRMATION AUDIT]:
            • Execution Time: \(entryTime) at \(entryStr)
            • Pre-Entry M15 Range: High: \(maxHighStr) | Low: \(minLowStr)
            • THESIS RECONCILIATION:
              - Planned Zone: [\(plannedEntry)]
              - Reality: Price DID \(zoneActionStrEn)!
              - Execution: After testing \(extremePriceStr), price rejected and closed at \(entryStr) -> Trader executed on disciplined CONFIRMATION ENTRY.

            [EXECUTION PRINCIPLE]: Price tested \(extremePriceStr) before confirmation at \(entryStr). This is a disciplined confirmation entry, do not evaluate as premature entry or "\(setupActionEn)".
            """
        }
    }

    // MARK: - Multi-Model Ensemble Distillation & Synthesis for Trade Coaching (RISK AI)
    public static func buildCoachingEnsembleSynthesisPrompt(
        trade: Trade,
        analyses: [String],
        isVi: Bool = true
    ) -> String {
        var analysesBlock = ""
        for (idx, a) in analyses.enumerated() {
            let num = idx + 1
            analysesBlock += """
            ==================================================
            [GÓC NHÌN PHÂN TÍCH ĐỘC LẬP \(num)]:
            \(AIPromptBuilder.distillAnalysis(a))

            """
        }

        let isShort = trade.direction == .short
        let dirStr = isShort ? "SELL" : "BUY"
        let entryStr = Formatters.price(trade.avgEntry, symbol: trade.symbol)
        let slStr = trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "None"
        let pnlStr = Formatters.currency(trade.netPnl)
        let isOpen = trade.closedAt == nil

        if isVi {
            return """
            BẠN LÀ RISK AI - GIÁM ĐỐC QUẢN TRỊ RỦI RO & HUẤN LUYỆN VIÊN TRƯỞNG (CHIEF RISK OFFICER).

            [THÔNG SỐ VỊ THẾ GIAO DỊCH]:
            • Cặp tiền: \(trade.symbol) | Vị thế: [\(dirStr)] | Khối lượng: \(trade.quantity) lots
            • Giá vào (Entry): \(entryStr) | Mức SL hiện tại: \(slStr) | Trạng thái: [\(isOpen ? "ĐANG MỞ (LIVE)" : "ĐÃ ĐÓNG (CLOSED)")]
            • PnL: \(pnlStr)

            Dưới đây là \(analyses.count) góc nhìn phân tích độc lập từ các mô hình kỹ thuật đối với vị thế trên:

            \(analysesBlock)==================================================

            [NGUYÊN TẮC TỔNG HỢP VÀ ĐIỀU PHỐI ĐỘC LẬP]:
            Tổng hợp và đúc kết thành MỘT BẢN ĐÁNH GIÁ CHUYÊN NGHIỆP DUY NHẤT dưới tư cách RISK AI.
            Tuyệt đối KHÔNG nhắc đến "Góc nhìn 1/2/3", "các mô hình AI", hay "hội đồng". Bạn phát ngôn với một tiếng nói duy nhất là RISK AI.

            NGUYÊN TẮC BẢO VỆ RỦI RO VÀ TƯ DUY GIAO DỊCH CHUYÊN NGHIỆP:
            1. BẢO TOÀN VỊ THẾ & TRAILING STOP:
               - Khi lệnh \(dirStr) có SL đã được dời vượt qua giá vào theo chiều có lợi (đối với SELL: SL nằm dưới giá vào; đối với BUY: SL nằm trên giá vào): ĐÂY LÀ HÀNH ĐỘNG DỜI SL DƯƠNG / TRAILING STOP ĐỂ BẢO VỆ VỐN VÀ KHÓA LÃI (RISK-FREE). BẮT BUỘC công nhận đây là kỹ năng quản trị rủi ro an toàn tuyệt đối, TUYỆT ĐỐI KHÔNG ĐƯỢC coi là lỗi kỹ thuật hay sai chiều.
               - Nếu có góc nhìn độc lập nào hiểu nhầm việc kéo SL bảo vệ thành lỗi kỹ thuật: BẮT BUỘC BÁC BỎ sự hiểu nhầm đó và khẳng định vị thế đã an toàn.
            2. CĂN CỨ VÀO ĐỘNG LƯỢNG VÀ CẤU TRÚC ĐA KHUNG:
               - Kết hợp hành động giá nến và hệ thống 3 đường Động lượng RSI để đưa ra chỉ đạo hành động cụ thể.

            ĐỊNH DẠNG ĐẦU RA CHUẨN:
            \(isOpen ? """
            ### 1. Thẩm định tính hợp lý của vị thế & Động lượng nến
            ### 2. Cấu trúc thị trường & Mức cản then chốt
            ### 3. Điểm vô hiệu hóa cấu trúc & Kế hoạch bảo vệ vốn
            ### 4. Đối chiếu Hồ sơ Trader & Phòng chống lỗi tâm lý

            [LIVE POSITION DIRECTIVE]
            - Action: [HOLD hoặc PARTIAL TP hoặc MOVE SL TO BE hoặc CLOSE NOW]
            - Current Price: [Thị giá hiện tại]
            - Adjusted SL: [Mức SL khuyến nghị]
            - Partial Close Volume: [Khối lượng chốt nếu có, nếu không ghi Không]
            - Next Target: [Vùng giá mục tiêu tiếp theo]
            """ : """
            ### 1. Đánh giá chất lượng điểm vào & Động lượng nến
            ### 2. Đánh giá quản trị lệnh & Điểm thoát
            ### 3. Cấu trúc thị trường & Bài học thực chiến
            ### 4. Kỷ luật vốn & Phòng chống tái phạm
            """)

            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng của nhà giao dịch chuyên nghiệp]
            """
        } else {
            return """
            YOU ARE RISK AI - CHIEF RISK OFFICER & MASTER TRADING COACH.

            [TRADE CONTEXT]:
            • Symbol: \(trade.symbol) | Direction: [\(dirStr)] | Volume: \(trade.quantity) lots
            • Entry: \(entryStr) | Stop Loss: \(slStr) | Status: [\(isOpen ? "LIVE OPEN" : "CLOSED")]
            • PnL: \(pnlStr)

            Below are \(analyses.count) independent technical reviews of this position:

            \(analysesBlock)==================================================

            [SYNTHESIS & RESOLUTION DIRECTIVE]:
            Synthesize the independent reviews into ONE SINGLE AUTHORITATIVE COACHING PLAN as RISK AI.
            Never mention "Perspective 1/2/3" or "AI models". You speak with one single voice as RISK AI.

            PROFESSIONAL CAPITAL PRESERVATION DIRECTIVES:
            1. POSITIVE SL & TRAILING STOP PRESERVATION:
               - When a \(dirStr) trade has its Stop Loss moved past entry into profit (for SELL: SL below entry; for BUY: SL above entry): THIS IS A TRAILING STOP / POSITIVE LOCK TO SECURE PROFIT (RISK-FREE). Mandate recognition of this as professional capital preservation, NOT an execution error.
               - Overrule any dissenting view that misinterprets trailing stop loss protection.

            CONCLUDE WITH STANDARD SECTIONS AND FINAL DIRECTIVE BLOCK.
            """
        }
    }

    // MARK: - Footprint & Price Action Confluence Prompt Block
    public static func buildFootprintAndPatternsBlock(
        symbol: String,
        currentPrice: Decimal,
        keyLevels: [KeyLevel],
        sessionProfiles: [SessionProfileSnapshot],
        developingProfiles: [DevelopingProfile],
        patterns: [DetectedCandlePattern],
        isVi: Bool
    ) -> String {
        let weeklyPoc = sessionProfiles.first(where: { $0.sessionType == .weekly })?.pocPrice ?? developingProfiles.first(where: { $0.sessionType == .weekly })?.currentPoc
        let dailyPoc = sessionProfiles.first(where: { $0.sessionType == .daily })?.pocPrice ?? developingProfiles.first(where: { $0.sessionType == .daily })?.currentPoc
        let tokyoPoc = sessionProfiles.first(where: { $0.sessionType == .tokyo })?.pocPrice ?? developingProfiles.first(where: { $0.sessionType == .tokyo })?.currentPoc
        let londonPoc = sessionProfiles.first(where: { $0.sessionType == .london })?.pocPrice ?? developingProfiles.first(where: { $0.sessionType == .london })?.currentPoc
        let nyPoc = sessionProfiles.first(where: { $0.sessionType == .newYork })?.pocPrice ?? developingProfiles.first(where: { $0.sessionType == .newYork })?.currentPoc

        guard weeklyPoc != nil || dailyPoc != nil || tokyoPoc != nil || !keyLevels.isEmpty else {
            return ""
        }

        let staircaseBias: String = {
            if let w = weeklyPoc, let d = dailyPoc {
                if let t = tokyoPoc ?? londonPoc ?? nyPoc {
                    if t > d && d > w {
                        return isVi ? "BẬC THANG TĂNG GIÁ (Tokyo POC > Daily POC > Weekly POC) -> Dòng tiền liên tục nâng đáy giá trị lên cao hơn" : "BULLISH STAIRCASE (Tokyo POC > Daily POC > Weekly POC)"
                    } else if t < d && d < w {
                        return isVi ? "BẬC THANG GIẢM GIÁ (Tokyo POC < Daily POC < Weekly POC) -> Dòng tiền liên tục đè trần giá trị xuống thấp hơn" : "BEARISH STAIRCASE (Tokyo POC < Daily POC < Weekly POC)"
                    }
                }
                if d > w {
                    return isVi ? "DÒNG TIỀN NGÀY CAO HƠN TUẦN (Daily POC > Weekly POC) -> Thiên hướng Tăng" : "BULLISH BIAS (Daily POC > Weekly POC)"
                } else if d < w {
                    return isVi ? "DÒNG TIỀN NGÀY THẤP HƠN TUẦN (Daily POC < Weekly POC) -> Thiên hướng Giảm" : "BEARISH BIAS (Daily POC < Weekly POC)"
                }
            }
            return isVi ? "CÂN BẰNG / TÍCH LŨY (Overlapping Value Areas)" : "BALANCED / OVERLAPPING"
        }()

        var pocList: [String] = []
        if let w = weeklyPoc { pocList.append("Weekly POC: \(Formatters.price(w, symbol: symbol))") }
        if let d = dailyPoc { pocList.append("Daily POC: \(Formatters.price(d, symbol: symbol))") }
        if let t = tokyoPoc { pocList.append("Tokyo POC: \(Formatters.price(t, symbol: symbol))") }
        if let l = londonPoc { pocList.append("London POC: \(Formatters.price(l, symbol: symbol))") }
        if let n = nyPoc { pocList.append("New York POC: \(Formatters.price(n, symbol: symbol))") }

        let nakedPocs = sessionProfiles.filter { $0.isNaked }.prefix(3)
        let nakedStr = nakedPocs.map { "\($0.sessionType.shortCode) Naked POC: \(Formatters.price($0.pocPrice, symbol: symbol))" }.joined(separator: " | ")

        let filteredPats = patterns.filter { $0.type != .insideBar && $0.type != .doji }.prefix(4)
        let patternsStr: String = {
            if filteredPats.isEmpty {
                return isVi ? "Khong co mau nen dao chieu bat thuong tai can" : "No high-conviction candle patterns at key levels"
            }
            return filteredPats.map { pat in
                let lvlTag = pat.confluenceKeyLevel.map { "@ \($0.label)" } ?? ""
                return "\(pat.type.displayName) (\(pat.summary)) \(lvlTag)"
            }.joined(separator: "\n  - ")
        }()

        if isVi {
            return """


            [DỮ LIỆU ĐO LƯỜNG FOOTPRINT POC BẬC THANG & PRICE ACTION]:
            - Xu hướng Bậc thang Dòng tiền (Staircase Trend Bias): [\(staircaseBias)]
            - Các mốc POC phiên then chốt: \(pocList.joined(separator: " | "))
            - Mốc Naked POC chưa kiểm định (Nam châm thanh khoản): \(nakedStr.isEmpty ? "Không có" : nakedStr)
            - Hành vi nến Price Action tại cản Footprint:
              - \(patternsStr)
            """
        } else {
            return """


            [INSTITUTIONAL FOOTPRINT STAIRCASE POCS & PRICE ACTION CONFLUENCE]:
            - Staircase Trend Bias: [\(staircaseBias)]
            - Key Session POCs: \(pocList.joined(separator: " | "))
            - Untested (Naked) POC Liquidity Targets: \(nakedStr.isEmpty ? "None" : nakedStr)
            - Candlestick Price Action at Key Levels:
              - \(patternsStr)
            """
        }
    }
}
