import Foundation

// MARK: - Pre-Trade Multi-Timeframe Prompt Builder Extension
// Integrates Algorithmic Market Structure Engine (MSS, Liquidity Sweeps, Fractal Swings)
// and enforces clean, institutional, zero-fluff Pre-Trade forward planning on H1 execution.
extension AIPromptBuilder {
    
    /// Assembles a streamlined, high-signal multi-timeframe market structure prompt (D1, H4, H1) for pre-trade forward bias
    public static func buildPreTradeAnalysisPrompt(
        symbol: String,
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar] = [],
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
        
        func formatPrice(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        // Prioritize H1 execution bars as requested
        let execBars = !h1Bars.isEmpty ? h1Bars : m15Bars
        
        let currentPrice: String = {
            if let last = execBars.last ?? h4Bars.last ?? d1Bars.last {
                return formatPrice(last.close)
            }
            return "N/A"
        }()
        
        // 1. D1 Macro Range (PDH / PDL / PDC / 14-day ADR)
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
        
        // 2. Trend & Momentum Analysis (EMA 21/50 Multi-Timeframe)
        let emaAnalysis = MovingAverageEngine.analyzeMultiTimeframe(
            barsD1: d1Bars,
            barsH4: h4Bars,
            barsH1: h1Bars,
            barsM15: m15Bars,
            symbol: symbol
        )
        
        // 3. Institutional Liquidity & SFP Sweeps on H1 Execution Timeframe
        let liquidity = LiquidityEngine.analyzeLiquidity(
            symbol: symbol,
            barsM15: execBars,
            barsH4: h4Bars,
            barsD1: d1Bars
        )
        
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
            return liquidity.recentSweeps.prefix(2).map { sw in
                let typeStr = sw.sweepType == .buySideSwept ? "Quét đỉnh (Bearish SFP)" : "Quét đáy (Bullish SFP)"
                return "\(sw.levelName) [\(typeStr)] tại \(formatPrice(sw.sweptPrice)), râu \(formatPrice(sw.wickExtreme))"
            }.joined(separator: "; ")
        }()
        
        // 4. H1 Momentum Metrics
        let momentumWindow = MomentumEngine.computeWindow(bars: execBars, windowSize: 10)
        let rsiStr = momentumWindow.currentRSI.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let ema9Str = momentumWindow.currentEMA9.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let wma45Str = momentumWindow.currentWMA45.map { String(format: "%.1f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let momAlignStr = isVi ? momentumWindow.alignmentVi : momentumWindow.alignmentEn
        let divStr = isVi ? (momentumWindow.divergenceVi ?? "Không có") : (momentumWindow.divergenceEn ?? "None")
        
        // 5. Macro News Catalyst
        let newsBlock: String = {
            let now = Date()
            let highImpacts = events.filter { $0.impact == .high }
            if let nextEvent = highImpacts.first(where: { ($0.date ?? Date.distantPast) > now }) {
                let diffMin = Int(nextEvent.date!.timeIntervalSince(now) / 60)
                let timeDesc = diffMin >= 60 ? "\(diffMin / 60)h \(diffMin % 60)m" : "\(diffMin) phút"
                return isVi
                    ? "⚠️ Tin đỏ: \(nextEvent.title) (\(nextEvent.country)) sẽ công bố trong \(timeDesc)"
                    : "⚠️ High-Impact News: \(nextEvent.title) (\(nextEvent.country)) in \(timeDesc)"
            }
            return isVi ? "Không có tin tức Đỏ (High Impact) trong 12h tới" : "No High-Impact events within 12h"
        }()
        
        // 6. Active Account Context & Trader Profile Integration
        let accNameStr: String = {
            if let name = sessionSummary?.accountName, !name.isEmpty {
                return "(\(name))"
            }
            return ""
        }()
        
        let realBalStr: String = {
            if let bal = sessionSummary?.balance {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return Formatters.formatCurrency(bal, currency: curr)
            }
            return "N/A"
        }()
        
        let equityStr: String = {
            if let eq = sessionSummary?.equity, let bal = sessionSummary?.balance, eq != bal {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return "| Vốn ròng (Equity): \(Formatters.formatCurrency(eq, currency: curr))"
            }
            return ""
        }()
        
        let riskPctStr = traderProfile?.maxRiskPerTrade.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? traderProfile!.maxRiskPerTrade.trimmingCharacters(in: .whitespaces)
            : "1.0% vốn"
        
        let riskDollarStr: String = {
            if let bal = sessionSummary?.balance {
                let balNum = NSDecimalNumber(decimal: bal).doubleValue
                let riskVal = balNum * 0.01
                return String(format: " (~$%.2f)", riskVal)
            }
            return ""
        }()
        
        let propBufferStr: String = {
            guard let limit = sessionSummary?.dailyLossLimitUsd else { return "" }
            let buf = sessionSummary?.dailyLossBufferRemainingUsd ?? limit
            let bufVal = NSDecimalNumber(decimal: buf).doubleValue
            let firm = sessionSummary?.propFirmName ?? "Quỹ"
            return isVi ? " | Hạn mức lỗ ngày còn lại (\(firm)): $\(String(format: "%.2f", bufVal))" : " | Remaining Daily Buffer (\(firm)): $\(String(format: "%.2f", bufVal))"
        }()
        
        let tradingStyleStr = traderProfile?.tradingStyle.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? traderProfile!.tradingStyle.trimmingCharacters(in: .whitespaces)
            : "Day Trader / Swing Trader"
            
        let strategyStr = traderProfile?.primaryPlaybooks.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? traderProfile!.primaryPlaybooks.trimmingCharacters(in: .whitespaces)
            : "SMC, Price Action, Support & Resistance"
            
        let leaksStr = traderProfile?.knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? traderProfile!.knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces)
            : "Dời SL, chốt non, FOMO"
            
        let customNotesStr = traderProfile?.customMemoryNotes.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? traderProfile!.customMemoryNotes.trimmingCharacters(in: .whitespaces)
            : "Tỷ lệ R:R >= 2:1, bảo vệ vốn khi thị trường giằng co, không bao giờ trả thù lệnh"
        
        // 7. Symbol Lessons (Max 2 concise principles)
        let symbolLessonsBlock: String = {
            let memories = AIAdvisorMemoryEngine.shared.getSelectiveMemoriesForPrompt(symbol: symbol, maxItems: 2)
            guard !memories.isEmpty else { return "" }
            let items = memories.map { "• \($0.content)" }.joined(separator: "\n")
            return isVi
                ? "\n[BÀI HỌC KINH NGHIỆM ĐÃ LƯU CHO \(symbol)]:\n\(items)\n"
                : "\n[HISTORICAL LESSONS FOR \(symbol)]:\n\(items)\n"
        }()
        
        // 8. Follow-up Live Update (If conversational inquiry)
        var liveUpdateBlock = ""
        if let update = liveCandleUpdate, !update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liveUpdateBlock = isVi
                ? "\n[HÀNH ĐỘNG GIÁ THỰC TẾ VỪA CẬP NHẬT]:\n\(update)\n"
                : "\n[LIVE MARKET PRICE ACTION UPDATE]:\n\(update)\n"
        }
        
        // 9. Thesis Continuity (If refreshing prior plan)
        var thesisContinuityBlock = ""
        if let prev = previousAnalysis, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let condensedPrev = prev.count > 600
                ? String(prev.prefix(600)) + "\n[...trích lược kế hoạch trước...]"
                : prev
            thesisContinuityBlock = isVi
                ? "\n[KẾ HOẠCH ĐÃ ĐƯA RA LẦN TRƯỚC]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n⚠️ ĐỐI CHIẾU: Kiểm tra nến mới xem điều kiện vào lệnh (Trigger) đã xảy ra chưa, hay cấu trúc ban đầu đã bị vi phạm (Invalidated)?\n"
                : "\n[PRIOR TRADING PLAN]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n⚠️ CONTINUITY: Check if the entry trigger was met or if the prior setup was structurally invalidated.\n"
        }
        
        let visionNote = hasImage
            ? (isVi ? "\n[ẢNH BIỂU ĐỒ ĐÍNH KÈM]: Phân tích trực quan Tri-Panel đính kèm (D1 vĩ mô, H4 cấu trúc, H1 thực thi).\n" : "\n[ATTACHED CHART IMAGE]: Refer to attached Tri-Panel visual chart.\n")
            : ""
            
        // Final Assembly
        if isVi {
            return """
            [THÔNG TIN TÀI KHOẢN & QUẢN TRỊ RỦI RO]:
            • Tài khoản & Số dư thực tế: \(realBalStr != "N/A" ? "\(realBalStr) \(accNameStr) \(equityStr)" : "[Chưa kết nối]")\(propBufferStr)
            • Ngân sách rủi ro mỗi lệnh: \(riskPctStr)\(riskDollarStr)
            • Phong cách giao dịch: \(tradingStyleStr)
            • Chiến lược & Playbook ưu tiên: \(strategyStr)
            • Lỗ hổng tâm lý cần triệt tiêu: \(leaksStr)
            • Kỷ luật cá nhân: \(customNotesStr)

            [CẤU TRÚC THỊ TRƯỜNG & DỮ LIỆU ĐO LƯỜNG THỰC TẾ]:
            • Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)
            • Khung D1 (Macro): Xu hướng [\(emaAnalysis.d1?.summary ?? "N/A")] | Đỉnh PDH: \(d1PDH) | Đáy PDL: \(d1PDL) | ADR 14 ngày: \(d1ADR)
            • Khung H4 (Cấu trúc sóng & Cản TP/SL): Xu hướng [\(emaAnalysis.h4?.summary ?? "N/A")] | Swing High: \(d1PDH) | Swing Low: \(d1PDL)
            • Khung H1 (Thực thi & Tín hiệu kích hoạt): Xu hướng [\(emaAnalysis.h1?.summary ?? "N/A")]
              - Vùng thanh khoản: BSL gần nhất: \(nearestBSLStr) | SSL gần nhất: \(nearestSSLStr)
              - Quét thanh khoản (SFP Sweeps): \(sweepsStr)
            • Động lượng H1: RSI(14) = \(rsiStr) | EMA(9) = \(ema9Str) | WMA(45) = \(wma45Str) | Trạng thái: [\(momAlignStr)] | Phân kỳ: [\(divStr)]
            • Tin tức kinh tế (Catalyst): \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            NHIỆM VỤ PHÂN TÍCH ĐÓN ĐẦU & THIẾT LẬP KẾ HOẠCH (PRE-TRADE ACTION PLAN):
            Phân tích ngắn gọn, trực diện theo đúng 4 mục (không lặp lại thông tin hồ sơ tài khoản) và kết thúc bằng bảng thông số [PRE-TRADE SETUP SPECIFICATION]:

            ### 1. Xu hướng vĩ mô D1 & Định hướng dòng tiền (Macro Bias)
            - Phe nào đang kiểm soát (Bulls hay Bears)? Giá đang ở vùng Premium hay Discount?
            - Mục tiêu thanh khoản ngày: Khả năng tìm về PDH (\(d1PDH)) hoặc PDL (\(d1PDL)).

            ### 2. Cấu trúc sóng & Vùng cản then chốt H4 (Key Barriers)
            - Xu hướng H4 đang là TĂNG, GIẢM hay ĐI NGANG?
            - Nhận diện các VÙNG CẢN H4 (Đỉnh/Đáy Swing, Supply/Demand, FVG) để làm MỤC TIÊU CHỐT LỜI (TP1/TP2) hoặc CẮT LỖ (SL).

            ### 3. Cấu trúc thực thi H1 & Bẫy thanh khoản (Execution & Traps)
            - Cấu trúc H1: Xác nhận thuận xu hướng H4 (Follow-trend) hay xuất hiện tín hiệu đảo chiều tại cản H4 (MSS / SFP / Phân kỳ RSI) để đánh sóng hồi nghịch xu hướng (Counter-trend)?
            - Bẫy thanh khoản & Tín hiệu kích hoạt: Đã có nến H1 xác nhận hay vào lệnh sớm có rủi ro bị quét SL?

            ### 4. Khuyến nghị & Kế hoạch lệnh cụ thể (Actionable Recommendation)
            - KẾT LUẬN RÕ RÀNG: [BUY (LONG) / SELL (SHORT) / FLAT (ĐỨNG NGOÀI)].
            - LOẠI SETUP: [THUẬN XU HƯỚNG H4] hoặc [NGHỊCH XU HƯỚNG H4 / SÓNG HỒI TỪ CẢN H4].
            - Nếu KHUYẾN NGHỊ VÀO LỆNH (BUY/SELL):
              • Điểm vào tối ưu (Entry) & Tín hiệu nến H1 kích hoạt (Trigger).
              • Cắt lỗ bắt buộc (Structural Invalidation SL): Mức giá SL cụ thể theo vi phạm H1.
              • Mục tiêu chốt lời (Targets): TP 1 và TP 2 đặt tại các vùng Cản H4 ở Mục 2.
              • Tỷ lệ Risk/Reward (R:R) dự kiến.
            - Nếu KHUYẾN NGHỊ FLAT (ĐỨNG NGOÀI): Nêu rõ điều kiện H1 cần chờ thêm trước khi vào lệnh.

            BẮT BUỘC KẾT THÚC BẰNG KHỐI THÔNG SỐ SETUP ĐÚNG ĐỊNH DẠNG SAU:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY hoặc SELL hoặc FLAT]
            - Balance: \(realBalStr != "N/A" ? realBalStr : "[Số dư]")
            - Entry: [Mức giá hoặc vùng giá vào lệnh]
            - Stop loss: [Mức giá SL cụ thể]
            - Take profit 1: [Mức giá TP 1]
            - Take profit 2: [Mức giá TP 2 nếu có, nếu không ghi Không]
            - Volume: [Khối lượng lot khuyến nghị tính theo số dư thực tế \(realBalStr) và \(riskPctStr) rủi ro, ví dụ 0.25 lot]
            - Date time: [Thời gian hiện tại]

            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng]
            """
        } else {
            return """
            [ACCOUNT CONTEXT & RISK SIZING]:
            • Real Balance: \(realBalStr != "N/A" ? "\(realBalStr) \(accNameStr) \(equityStr)" : "[Not configured]")\(propBufferStr)
            • Risk Budget Per Trade: \(riskPctStr)\(riskDollarStr)
            • Trading Style: \(tradingStyleStr)
            • Primary Playbooks: \(strategyStr)
            • Known Leaks: \(leaksStr)
            • Discipline Notes: \(customNotesStr)

            [MARKET STRUCTURE & OBJECTIVE MEASUREMENTS]:
            • Symbol: \(symbol) | Current Price: \(currentPrice)
            • D1 Frame (Macro): Trend [\(emaAnalysis.d1?.summary ?? "N/A")] | PDH: \(d1PDH) | PDL: \(d1PDL) | 14-day ADR: \(d1ADR)
            • H4 Frame (Key Barriers for TP/SL): Trend [\(emaAnalysis.h4?.summary ?? "N/A")] | Swing High: \(d1PDH) | Swing Low: \(d1PDL)
            • H1 Frame (Execution & Entry Triggers): Trend [\(emaAnalysis.h1?.summary ?? "N/A")]
              - Liquidity Pools: Nearest BSL: \(nearestBSLStr) | Nearest SSL: \(nearestSSLStr)
              - Recent SFP Sweeps: \(sweepsStr)
            • H1 Momentum: RSI(14) = \(rsiStr) | EMA(9) = \(ema9Str) | WMA(45) = \(wma45Str) | State: [\(momAlignStr)] | Divergence: [\(divStr)]
            • Macro News Catalyst: \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            TASK: PRE-TRADE SMC MARKET BIAS & ACTIONABLE PLAN:
            Provide a razor-sharp, institutional analysis across the 4 sections below, concluding with the [PRE-TRADE SETUP SPECIFICATION] block:

            ### 1. D1 Macro Regime & Directional Bias
            - Which participant controls the market (Bulls or Bears)? Is price operating in Premium or Discount?
            - Daily liquidity draw: Probability of tagging PDH (\(d1PDH)) or PDL (\(d1PDL)).

            ### 2. H4 Swing Structure & Key Barriers (TP/SL Targets)
            - What is the H4 trend (Bullish, Bearish, or Consolidation)?
            - Identify key H4 Supply/Demand zones, Order Blocks, and Swing Highs/Lows that serve as TARGET BARRIERS for TP1/TP2 or protective SL.

            ### 3. H1 Execution Trigger & Traps
            - H1 Structure: Does it confirm H4 Follow-Trend continuation, or show a reversal setup (MSS/SFP/Divergence) off an H4 barrier for a Counter-Trend retracement?
            - Traps & Execution Timing: Is there clear H1 candle confirmation, or does entering now risk getting stopped out by a sweep?

            ### 4. Actionable Directive & Execution Blueprint
            - DECISIVE VERDICT: [BUY (LONG) / SELL (SHORT) / FLAT (NO SETUP)].
            - SETUP TYPE: [FOLLOW-TREND CONTINUATION] or [COUNTER-TREND REVERSAL FROM H4 BARRIER].
            - If EXECUTABLE SETUP (BUY/SELL):
              • Optimal Entry Zone & H1 Confirmation Trigger.
              • Structural Invalidation (SL): Specific price level based on H1 structure failure.
              • Profit Targets (TP1 & TP2): Anchored to H4 key barriers from Section 2.
              • Projected Risk-to-Reward (R:R).
            - If FLAT: State clearly what H1 price development is required before entering.

            MANDATORY: CONCLUDE WITH THIS PRE-TRADE SETUP SPECIFICATION BLOCK:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY or SELL or FLAT]
            - Balance: \(realBalStr != "N/A" ? realBalStr : "[Balance]")
            - Entry: [Entry price or zone]
            - Stop loss: [Specific SL price]
            - Take profit 1: [Specific TP1 price]
            - Take profit 2: [Specific TP2 price if any, otherwise None]
            - Volume: [Recommended lots computed from real balance \(realBalStr) and \(riskPctStr) risk, e.g. 0.25 lot]
            - Date time: [Current date and time]

            > [Single non-negotiable operational directive]
            """
        }
    }
}
