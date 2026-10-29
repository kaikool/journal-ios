import Foundation

// MARK: - Pre-Trade Multi-Timeframe Prompt Builder Extension
// Integrates Algorithmic Market Structure Engine (MSS, Liquidity Sweeps, Fractal Swings, Candlestick Tape)
// and enforces Thesis Continuity across refreshes.
extension AIPromptBuilder {
    
    /// Assembles comprehensive multi-timeframe market structure prompt (D1, H4, H1, M15) for pre-trade forward bias
    public static func buildPreTradeAnalysisPrompt(
        symbol: String,
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar],
        marketSnapshot: MarketStateSnapshot? = nil,
        events: [ForexFactoryEvent] = [],
        language: String = "vi",
        sessionSummary: AIAccountSessionSummary? = nil,
        traderProfile: TraderProfileConfig? = nil,
        displayTimeZone: String = "UTC",
        previousAnalysis: String? = nil,
        liveCandleUpdate: String? = nil,
        hasImage: Bool = false
    ) -> String {
        let isVi = language == "vi"
        let sessionBlock = sessionSummary != nil ? AIAccountContextProvider.formatContextForPrompt(sessionSummary!, isVi: isVi) : ""
        
        func formatPrice(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        let currentPrice: String = {
            if let last = m15Bars.last ?? h4Bars.last ?? d1Bars.last {
                return formatPrice(last.close)
            }
            return "N/A"
        }()
        
        // 1. D1 Analysis (Macro Trend & Daily Regime)
        let d1PDH: String
        let d1PDL: String
        let d1PDC: String
        let d1ADR: String
        if d1Bars.count >= 2 {
            let prevDay = d1Bars[d1Bars.count - 2]
            d1PDH = formatPrice(prevDay.high)
            d1PDL = formatPrice(prevDay.low)
            d1PDC = formatPrice(prevDay.close)
            
            let lookback = min(14, d1Bars.count - 1)
            let ranges = d1Bars.suffix(lookback).map { $0.high - $0.low }
            let avgRange = ranges.reduce(Decimal.zero, +) / Decimal(lookback)
            d1ADR = formatPrice(avgRange)
        } else {
            d1PDH = "N/A"
            d1PDL = "N/A"
            d1PDC = "N/A"
            d1ADR = "N/A"
        }
        
        // 2. Dynamic EMA 21 & EMA 50 Multi-Timeframe Trend Engine
        let displayTz = TimeZone(identifier: displayTimeZone) ?? .current
        let tzAbbr = displayTz.abbreviation() ?? "Local"
        let tzIdent = displayTz.identifier
        
        let emaAnalysis = MovingAverageEngine.analyzeMultiTimeframe(
            barsD1: d1Bars,
            barsH4: h4Bars,
            barsH1: h1Bars,
            barsM15: m15Bars,
            symbol: symbol
        )
        
        // 3. Institutional Liquidity & Sweep Engine (PDH/PDL, EQH/EQL, SFP Sweeps)
        let liquidity = LiquidityEngine.analyzeLiquidity(
            symbol: symbol,
            barsM15: m15Bars,
            barsH4: h4Bars,
            barsD1: d1Bars
        )
        
        let pwhStr = liquidity.pwh.map { formatPrice($0) } ?? "N/A"
        let pwlStr = liquidity.pwl.map { formatPrice($0) } ?? "N/A"
        
        let nearestBSLStr: String = {
            if let bsl = liquidity.nearestBSL {
                let dist = liquidity.distanceToBSLPips.map { " (cách \(formatPrice($0)) giá)" } ?? ""
                return "\(bsl.label) tại \(formatPrice(bsl.price))\(dist)"
            }
            return isVi ? "Không có mốc BSL gần" : "No nearby BSL pool"
        }()
        
        let nearestSSLStr: String = {
            if let ssl = liquidity.nearestSSL {
                let dist = liquidity.distanceToSSLPips.map { " (cách \(formatPrice($0)) giá)" } ?? ""
                return "\(ssl.label) tại \(formatPrice(ssl.price))\(dist)"
            }
            return isVi ? "Không có mốc SSL gần" : "No nearby SSL pool"
        }()
        
        let sweepsStr: String = {
            if liquidity.recentSweeps.isEmpty {
                return isVi ? "Không có nhịp quét gần đây" : "No recent sweeps"
            }
            return liquidity.recentSweeps.prefix(3).map { sw in
                let typeStr = sw.sweepType == .buySideSwept ? "Quét đỉnh (Bearish SFP)" : "Quét đáy (Bullish SFP)"
                return "\(sw.levelName) [\(typeStr)] tại \(formatPrice(sw.sweptPrice)), râu \(formatPrice(sw.wickExtreme))"
            }.joined(separator: "\n- ")
        }()
        
        let emaAndLiquidityBlockVi = """
        [XU HƯỚNG ĐỘNG LỰC EMA 21 & EMA 50 ĐA KHUNG THỜI GIAN]:
        - D1: \(emaAnalysis.d1?.summary ?? "N/A")
        - H4: \(emaAnalysis.h4?.summary ?? "N/A")
        - H1: \(emaAnalysis.h1?.summary ?? "N/A")
        - M15: \(emaAnalysis.m15?.summary ?? "N/A")
        - Đánh giá đồng thuận: \(emaAnalysis.alignmentSummary)
        
        [THANH KHOẢN TỔ CHỨC & VÙNG QUÉT SFP (LIQUIDITY & SWEEPS)]:
        - Đỉnh/Đáy ngày trước: PDH = \(d1PDH) | PDL = \(d1PDL)
        - Đỉnh/Đáy tuần trước: PWH = \(pwhStr) | PWL = \(pwlStr)
        - Vùng thanh khoản Mua (BSL) gần nhất: \(nearestBSLStr)
        - Vùng thanh khoản Bán (SSL) gần nhất: \(nearestSSLStr)
        - Các nhịp quét thanh khoản gần nhất:
        - \(sweepsStr)
        """
        
        let emaAndLiquidityBlockEn = """
        [DYNAMIC EMA 21 & EMA 50 MULTI-TIMEFRAME TREND ALIGNMENT]:
        - D1: \(emaAnalysis.d1?.summary ?? "N/A")
        - H4: \(emaAnalysis.h4?.summary ?? "N/A")
        - H1: \(emaAnalysis.h1?.summary ?? "N/A")
        - M15: \(emaAnalysis.m15?.summary ?? "N/A")
        - Alignment: \(emaAnalysis.alignmentSummary)
        
        [INSTITUTIONAL LIQUIDITY POOLS & SFP SWEEPS]:
        - Previous Day High/Low: PDH = \(d1PDH) | PDL = \(d1PDL)
        - Previous Week High/Low: PWH = \(pwhStr) | PWL = \(pwlStr)
        - Nearest Buy-Side Liquidity (BSL): \(nearestBSLStr)
        - Nearest Sell-Side Liquidity (SSL): \(nearestSSLStr)
        - Recent Institutional Sweeps:
        - \(sweepsStr)
        """
        
        // 4. M15 Technical Momentum (Wilder RSI 14 / EMA 9 of RSI / WMA 45 of RSI across 10-candle window)
        let momentumWindow = MomentumEngine.computeWindow(bars: m15Bars, windowSize: 10)
        let momentumBlock = MomentumEngine.formatMomentumTable(
            window: momentumWindow,
            displayTimeZone: displayTz,
            isVi: isVi
        )
        
        // 5. Market State Snapshot (Objective facts across H4 structure, M15 structure, sweeps, momentum, catalysts)
        let snapshot = marketSnapshot ?? MarketStateSnapshotBuilder.computeSnapshot(
            symbol: symbol,
            barsH4: h4Bars,
            barsM15: m15Bars,
            events: events,
            referenceDate: Date()
        )
        let marketFactsBlock = MarketStateSnapshotBuilder.formatForPrompt(snapshot, isVi: isVi)
        
        // Trader Profile Snippet
        var profileSnippet = ""
        if let prof = traderProfile {
            let playbooks = prof.primaryPlaybooks.trimmingCharacters(in: .whitespaces)
            let risk = prof.maxRiskPerTrade.trimmingCharacters(in: .whitespaces)
            let leaks = prof.knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces)
            if isVi {
                profileSnippet = """
                HỒ SƠ TRADER:
                - Playbook ưu tiên: \(playbooks.isEmpty ? "Price Action & SMC" : playbooks)
                - Ngân sách rủi ro mỗi lệnh: \(risk.isEmpty ? "1R chuẩn" : risk)
                - Lỗ hổng tâm lý nhận diện: \(leaks.isEmpty ? "Không có" : leaks)
                """
            } else {
                profileSnippet = """
                TRADER PROFILE & RISK PARAMETERS:
                - Declared Playbooks: \(playbooks.isEmpty ? "Price Action & SMC" : playbooks)
                - Risk Per Trade: \(risk.isEmpty ? "1R Standard" : risk)
                - Known Psychological Leaks: \(leaks.isEmpty ? "None" : leaks)
                """
            }
        }
        
        // Long-term memories and adaptive lessons for this symbol
        let lessonsBlock = AIAdvisorMemoryEngine.shared.formatMemoriesForPrompt(
            symbol: symbol,
            isVi: isVi,
            maxItems: 4
        )
        
        let complianceBlock = AIAdvisorMemoryEngine.shared.formatComplianceBlock(
            symbol: symbol,
            isVi: isVi
        )
        
        let researchBlock = AIResearchWorkspaceEngine.shared.formatProjectsForPrompt(
            symbol: symbol,
            isVi: isVi
        )
        
        // Live Candle Update Snippet (for follow-up inquiries)
        var liveUpdateBlock = ""
        if let update = liveCandleUpdate, !update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isVi {
                liveUpdateBlock = """
                
                [DIỄN BIẾN GIÁ THỰC TẾ MỚI NHẤT TẠI THỜI ĐIỂM CHAT]:
                \"\"\"
                \(update)
                \"\"\"
                ⚠️ ĐÂY LÀ HÀNH ĐỘNG GIÁ THỰC TẾ VỪA XẢY RA: Đối chiếu ngay sự thay đổi của giá so với kế hoạch ban đầu!
                """
            } else {
                liveUpdateBlock = """
                
                [LIVE MARKET PRICE ACTION AT MOMENT OF INQUIRY]:
                \"\"\"
                \(update)
                \"\"\"
                ⚠️ LATEST PRICE DEVELOPMENT: Cross-reference this live market shift against your initial setup!
                """
            }
        }

        // Thesis Continuity Snippet (when refreshed)
        var thesisContinuityBlock = ""
        if let prev = previousAnalysis, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let condensedPrev = prev.count > 1500
                ? String(prev.prefix(1500)) + "\n[...trích lược luận điểm trước...]"
                : prev
            if isVi {
                thesisContinuityBlock = """
                
                [LUẬN ĐIỂM ĐÁNH GIÁ ĐÃ ĐƯA RA TRƯỚC ĐÓ (THESIS CONTINUITY)]:
                \"\"\"
                \(condensedPrev)
                \"\"\"
                
                ⚠️ YÊU CẦU BẮT BUỘC VỀ TÍNH NHẤT QUÁN & TRÁCH NHIỆM CỐ VẤN:
                - Đây là lượt LÀM MỚI (REFRESH) hoặc trao đổi tiếp theo cho \(symbol).
                - Hãy đối chiếu các nến mới xuất hiện so với Kế hoạch vào lệnh trước đó:
                  1. Điều kiện kích hoạt (Trigger) bạn đề ra trước đó ĐÃ XẢY RA CHƯA?
                  2. Kế hoạch trước đó (BUY / SELL / ĐỨNG NGOÀI) tiếp tục ĐƯỢC CỦNG CỐ hay ĐÃ BỊ VI PHẠM CẤU TRÚC?
                  3. NGUYÊN TẮC TRÁCH NHIỆM: Tuyệt đối không được 'lật kèo' hay vô cớ trách trader. Nếu trader đã vào lệnh theo đúng tư vấn ban đầu, bạn phải nhận trách nhiệm kế hoạch và chỉ tập trung vào giải pháp quản trị rủi ro!
                """
            } else {
                thesisContinuityBlock = """
                
                [PREVIOUS ANALYSIS THESIS (FOR LOGICAL CONTINUITY)]:
                \"\"\"
                \(condensedPrev)
                \"\"\"
                
                ⚠️ MANDATORY THESIS CONTINUITY & ADVISOR ACCOUNTABILITY:
                - This is an active REFRESH / UPDATE of your pre-trade market bias for \(symbol).
                - Cross-examine the newly printed candle bars against your previous trading plan:
                  1. Have the entry triggers or liquidity sweeps specified in your previous thesis occurred?
                  2. Is your previous directive (BUY / SELL / FLAT) confirmed, progressing, or structurally invalidated?
                  3. ADVISOR ACCOUNTABILITY: Do not arbitrarily flip stance or accuse the trader of indiscipline if they followed your prior advice. Evaluate market changes objectively!
                """
            }
        }
        
        let visionBlockVi = hasImage ? """
        
        ẢNH CHART ĐA KHUNG ĐÍNH KÈM (TRI-PANEL VISION CANVAS):
        Ảnh đính kèm là ảnh trực quan hợp nhất các khung thời gian của \(symbol):
        - Khung vĩ mô: Nến ngày thể hiện xu hướng vĩ mô (Macro Regime), PDH, PDL.
        - Khung trung gian: Nến 4 giờ thể hiện cấu trúc sóng (Swing High/Low) và vùng Cung/Cầu tổ chức (Order Blocks).
        - Khung thực thi: Nến 15 phút thể hiện hành động giá vi mô, điểm quét thanh khoản (Liquidity Sweeps) và cấu trúc vào lệnh.
        """ : ""
        
        let visionBlockEn = hasImage ? """
        
        ATTACHED MULTI-TIMEFRAME VISION ASSET (TRI-PANEL CANVAS):
        The attached image is a high-resolution Tri-Panel Chart showing:
        - Macro Panel: D1 Daily Macro Regime & Trend
        - Intermediate Panel: H4 4-Hour Swing Structure & Institutional Order Blocks
        - Execution Panel: M15 15-Minute Execution Timing & Liquidity Sweeps
        """ : ""
        
        if isVi {
            return """
            \(sessionBlock)\(profileSnippet.isEmpty ? "" : profileSnippet + "\n\n")PHÂN TÍCH CẤU TRÚC THỊ TRƯỜNG ĐA KHUNG THỜI GIAN (MARKET STRUCTURE & BIAS):
            - Cặp tiền / Tài sản: \(symbol)
            - Giá thị trường hiện tại: \(currentPrice)
            
            [QUY TẮC BẮT BUỘC VỀ VÀO LỆNH ĐA KHUNG THỜI GIAN (H4 VS M15 SMC EXECUTION)]:
            ⚠️ PHƯƠNG PHÁP GIAO DỊCH CỦA TRADER & PHÂN ĐỊNH VAI TRÒ ĐA KHUNG THỜI GIAN:
            - Khung thời gian thực thi lệnh (Execution Timeframe): M15.
            - Chiến thuật giao dịch: Trader giao dịch cả THUẬN XU HƯỚNG (FOLLOW-TREND) và NGHỊCH XU HƯỚNG (COUNTER-TREND) của H4 trên khung M15.
            - Vai trò của H4 (HTF): Xác định xu hướng vĩ mô (Order Flow) và các vùng Cung/Cầu tổ chức (Supply/Demand, Swing Highs/Lows, Order Blocks, Liquidity Pools).
              👉 CÁC VÙNG CẢN H4 NÀY ĐÓNG VAI TRÒ LÀ MỤC TIÊU ĐẶT TAKE PROFIT (TP) HOẶC STOP LOSS (SL).
            - Vai trò của M15 (LTF): Là khung thời gian quyết định kích hoạt vào lệnh (Entry Trigger) và xác định mức cắt lỗ (SL).
              • Lệnh Thuận xu hướng (Follow-Trend): Khi M15 sau nhịp hồi phục tiếp tục xác nhận cùng chiều Order Flow H4 (BOS M15, Sweep râu M15).
              • Lệnh Nghịch xu hướng (Counter-Trend): Khi giá phản ứng tại các vùng cản Cung/Cầu H4 và M15 xuất hiện cấu trúc đảo chiều (MSS M15, CHoCH M15, Sweep SFP M15, RSI phân kỳ). Khi đó ĐƯỢC PHÉP VÀO LỆNH NGHỊCH XU HƯỚNG H4 để đánh nhịp hồi về vùng cản H4 đối diện!
            
            • Giá thị trường hiện tại (Live Market Price): \(currentPrice)
            • Khung D1 (Vĩ mô): Đỉnh hôm trước (PDH): \(d1PDH) | Đáy hôm trước (PDL): \(d1PDL) | Đóng cửa (PDC): \(d1PDC) | ADR 14 ngày: \(d1ADR)
            
            \(emaAndLiquidityBlockVi)\(marketFactsBlock)
            
            \(momentumBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(lessonsBlock)\(complianceBlock)\(researchBlock)\(visionBlockVi)
            
            NHIỆM VỤ CỦA RISK AI (PHÂN TÍCH ĐÓN ĐẦU ĐỂ RA QUYẾT ĐỊNH VÀO LỆNH):
            Hãy đưa ra bản phân tích đa khung chuyên sâu theo trường phái Smart Money Concepts (SMC) và Price Action tổ chức theo đúng cấu trúc sau:
            
            ### 1. Xu hướng vĩ mô & Biên độ ngày (D1 Macro Bias)
            - Phe Mua (Bulls) hay phe Bán (Bears) đang kiểm soát xu hướng chủ đạo D1? Giá đang nằm ở nửa trên (Premium) hay nửa dưới (Discount) của biên độ?
            - Các mốc PDH (\(d1PDH)) và PDL (\(d1PDL)) đóng vai trò nam châm hút thanh khoản ra sao?
            
            ### 2. Cấu trúc sóng H4 & Vùng Cung/Cầu tổ chức (H4 Structure & Key Barriers for TP/SL)
            - Cấu trúc H4 đang trong pha nào (Mở rộng sóng Expansion hay Sóng hồi Retracement)? Xu hướng Order Flow chủ đạo là gì?
            - Xác định các vùng Cung / Cầu (Supply & Demand Zones), Order Blocks (OB) và các mốc cản Swing High/Low quan trọng trên H4.
            - Nêu rõ: Các mốc cản H4 này sẽ là MỤC TIÊU CHỐT LỜI (TP1 / TP2) hoặc NGƯỠNG BẢO VỆ DỪNG LỖ (SL) cho lệnh giao dịch.
            
            ### 3. Cấu trúc vào lệnh & Động lượng nến M15 (M15 Trigger & RSI Momentum)
            - Phân tích cấu trúc M15: Đang thuận xu hướng H4 (Follow-trend) hay đang tạo cấu trúc đảo chiều tại cản H4 (Counter-trend)?
            - Trích dẫn ngắn gọn hành động giá làm bằng chứng (tập trung vào mức giá phản ứng, quét râu hoặc phá vỡ, không lặp lại thời gian tràn lan).
            - Xác định rõ: Nến quét râu từ chối giá (Wick Liquidity Sweep) hay nến đóng thân xác nhận (Body Close Confirmation)?
            - Phân tích Động lượng RSI Core (BẮT BUỘC TRÍCH DẪN SỐ LIỆU TỪ BẢNG ĐỘNG LƯỢNG M15 BÊN TRÊN):
              • BẮT BUỘC GHI RÕ SỐ LIỆU: RSI(14) Wilder = [số], EMA(9) = [số], WMA(45) = [số] tại nến mới nhất.
              • So sánh EMA(9) với WMA(45) (Lớn hơn, nhỏ hơn hay đang hội tụ sát nhau?):
                - Nếu EMA9 > WMA45: Nền trung hạn nghiêng về Tăng. Nếu RSI giảm dưới EMA9 thì đây là nhịp hồi để mua tiếp hay cảnh báo gãy sóng?
                - Nếu EMA9 < WMA45: Nền trung hạn nghiêng về Giảm. Kịch bản mua có bị ngược đà không?
                - Nếu EMA9 và WMA45 sát nhau: Trạng thái co thắt động lượng (Squeeze). Khả năng bứt phá và rủi ro quét 2 đầu ra sao?
              • Vị thế 3 đường & Phân kỳ: RSI đang nằm trên hay dưới EMA9 và WMA45? Trạng thái đà (Mở rộng tăng/giảm, Giao cắt Cross, Quá mua >70 / Quá bán <30)? Có phân kỳ đỉnh/đáy cảnh báo đảo chiều không?
              • Kết luận động lượng: Động lượng RSI có đồng thuận ủng hộ kịch bản vào lệnh không hay đang cảnh báo rủi ro?
            - Đưa ra phán quyết thời điểm: Vào lệnh bây giờ là sớm rủi ro (front-running) hay đã có xác nhận kỷ luật (confirmation)?
            
            ### 4. Khuyến nghị hành động & Kế hoạch lệnh cụ thể (Actionable Recommendation)
            - ĐƯA RA KẾT LUẬN RÕ RÀNG: [BUY (LONG) / SELL (SHORT) / FLAT (ĐỨNG NGOÀI)].
            - GHI RÕ LOẠI SETUP: [THUẬN XU HƯỚNG H4 (FOLLOW-TREND)] hay [NGHỊCH XU HƯỚNG H4 / ĐÁNH SÓNG HỒI TỪ CẢN H4 (COUNTER-TREND)].
            - Nếu KHUYẾN NGHỊ VÀO LỆNH (BUY hoặc SELL):
              • Điểm vào tối ưu (Optimal Entry Zone) & Tín hiệu kích hoạt (M15 Confirmation Trigger): Nêu rõ vùng giá vào lệnh và tín hiệu kích hoạt trên M15 (ví dụ: Chờ nến M15 test FVG hoặc đóng cửa xác nhận tại [vùng giá]).
              • Điểm cắt lỗ bắt buộc (Structural Invalidation SL): Mức giá cụ thể đặt theo vi phạm cấu trúc M15.
              • Mục tiêu chốt lời (Targets): TP 1 và TP 2 đặt tại các vùng Cản / Supply - Demand / Đỉnh đáy của H4 đã xác định ở Mục 2.
              • Tỷ lệ R:R dự kiến: Tối thiểu bao nhiêu R.
            - Nếu KHUYẾN NGHỊ FLAT (ĐỨNG NGOÀI):
              • Giải thích cụ thể điều kiện M15 gì cần chờ đợi thêm trước khi vào lệnh.
            
            ⚠️ YÊU CẦU BẮT BUỘC: Trình bày cô đọng, sắc bén và BẮT BUỘC hoàn thành trọn vẹn cả 4 phần trên (đặc biệt là Phần 4: Vùng vào lệnh, Cắt lỗ SL, Chốt lời TP1/TP2, Tỷ lệ R:R). Tuyệt đối không dừng lại giữa chừng!
            
            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng]
            """
        } else {
            return """
            \(sessionBlock)\(profileSnippet.isEmpty ? "" : profileSnippet + "\n\n")PRE-TRADE MULTI-TIMEFRAME MARKET STRUCTURE & BIAS ANALYSIS:
            - Symbol / Instrument: \(symbol)
            - Live Market Price: \(currentPrice)
            
            [MANDATORY MULTI-TIMEFRAME SMC EXECUTION PROTOCOL (H4 VS M15)]:
            ⚠️ TRADER METHODOLOGY & MULTI-TIMEFRAME ROLE SEPARATION:
            - Execution Timeframe: M15.
            - Strategy: The trader trades both FOLLOW-TREND and COUNTER-TREND of H4 on the M15 timeframe.
            - Role of H4 (HTF): Establishes macro Order Flow and key Supply/Demand zones (Swing Highs/Lows, Order Blocks, Liquidity Pools).
              👉 THESE H4 LEVELS SERVE STRICTLY AS TARGET BARRIERS FOR TAKE PROFIT (TP) OR STOP LOSS (SL).
            - Role of M15 (LTF): Direct execution timeframe for trade entry trigger and Stop Loss placement.
              • Follow-Trend Trades: When M15 pulls back and confirms continuation aligned with H4 Order Flow (M15 BOS, sweep).
              • Counter-Trend Trades: When price reacts at an H4 Supply/Demand zone and M15 forms a reversal structure (M15 MSS, CHoCH, SFP wick rejection, RSI divergence). In this case, entering a counter-trend trade toward the opposing H4 barrier is 100% authorized!
            
            • Live Market Price: \(currentPrice)
            • D1 Frame (Macro): Previous Day High (PDH): \(d1PDH) | Previous Day Low (PDL): \(d1PDL) | Previous Day Close (PDC): \(d1PDC) | 14-Day ADR: \(d1ADR)
            
            \(emaAndLiquidityBlockEn)\(marketFactsBlock)
            
            \(momentumBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(lessonsBlock)\(complianceBlock)\(researchBlock)\(visionBlockEn)
            
            TASK: INSTITUTIONAL SMC PRE-TRADE BIAS & ACTIONABLE PLAN:
            
            ### 1. D1 Macro Regime & Directional Bias
            - Which participant (Bulls or Bears) holds dominance on the higher timeframe? Is current price operating in Premium or Discount territory?
            - Evaluate PDH (\(d1PDH)) and PDL (\(d1PDL)) as primary liquidity objectives.
            
            ### 2. H4 Swing Structure & Key Institutional Barriers (For TP/SL Targets)
            - What phase is H4 operating in (Expansion or Retracement)? What is the dominant higher timeframe Order Flow?
            - Map out major H4 Supply & Demand zones, unmitigated Order Blocks, and Swing Highs/Lows.
            - Clearly state: These H4 levels serve as TARGET BARRIERS for Take Profit (TP1 / TP2) or protective Stop Loss (SL).
            
            ### 3. M15 Execution Trigger & RSI Core Momentum
            - Analyze M15 structure: Is it setting up Follow-trend continuation or Counter-trend retracement off an H4 barrier?
            - Cite concise price action as evidence (focus on price reaction, wick sweeps, and structure levels; do not over-quote time).
            - Distinguish clearly: Is it a Wick Liquidity Sweep or a Body Close confirmation?
            - RSI Core Momentum Assessment (MANDATORY METRIC CITATION FROM MOMENTUM TABLE ABOVE):
              • MANDATORY METRIC CITATION: State exact numbers: Wilder RSI(14) = [value], EMA(9) = [value], WMA(45) = [value] for latest candle.
              • Compare EMA(9) vs WMA(45) (Greater, lesser, or converging Squeeze?):
                - If EMA9 > WMA45: Intermediate baseline favors Bulls. Is a dip below EMA9 a pullback or structural momentum loss?
                - If EMA9 < WMA45: Intermediate baseline favors Bears. Would buying fight the intermediate baseline?
                - If EMA9 & WMA45 are close: Momentum compression (Squeeze). How should trader manage breakout risk?
              • 3-Line Alignment & Relative Positioning: Is RSI operating above or below EMA9 and WMA45? Any divergences warning of reversal?
              • Momentum Verdict: Does technical momentum support or invalidate the intended setup?
            - Does entering now constitute disciplined confirmation or impatient front-running?
            
            ### 4. Actionable Directive & Execution Blueprint
            - DELIVER A DECISIVE VERDICT: [BUY (LONG) / SELL (SHORT) / FLAT (NO SETUP)].
            - SPECIFY SETUP TYPE: [FOLLOW-TREND CONTINUATION] or [COUNTER-TREND REVERSAL FROM H4 BARRIER].
            - If EXECUTABLE SETUP (BUY or SELL):
              • Optimal Entry Zone & M15 Confirmation Trigger: State entry zone and M15 candle trigger (e.g. enter on M15 test of FVG or close confirmation).
              • Structural Invalidation (SL): Anchored to M15 structural invalidation level.
              • Profit Targets (TP1 & TP2): Anchored to H4 Supply/Demand barriers identified in Section 2.
              • Projected Risk-to-Reward (R:R): Expected ratio.
            - If FLAT:
              • Clearly state the mandatory M15 trigger required before entering.
            
            > [Single non-negotiable operational directive]
            """
        }
    }
}
