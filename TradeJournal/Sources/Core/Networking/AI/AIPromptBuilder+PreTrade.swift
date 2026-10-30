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
        
        func formatEMALevels(_ snap: TimeframeEMASnapshot?, tfName: String) -> String {
            guard let snap = snap, let e21 = snap.ema21, let e50 = snap.ema50 else {
                return isVi ? "Chưa đủ dữ liệu nến tính EMA 21/50" : "Insufficient bars for EMA 21/50"
            }
            let p21 = formatPrice(e21)
            let p50 = formatPrice(e50)
            let cur = snap.currentPrice
            let dist = cur - e21
            let distVal = formatPrice(abs(dist))
            
            let posDesc: String
            if isVi {
                posDesc = dist >= 0 ? "Giá trên EMA 21 (+\(distVal) giá)" : "Giá dưới EMA 21 (-\(distVal) giá)"
            } else {
                posDesc = dist >= 0 ? "Price above EMA 21 (+\(distVal))" : "Price below EMA 21 (-\(distVal))"
            }
            
            let spreadDesc: String
            if isVi {
                spreadDesc = e21 >= e50 ? "EMA 21 > EMA 50 (Thiên Tăng)" : "EMA 21 < EMA 50 (Thiên Giảm)"
            } else {
                spreadDesc = e21 >= e50 ? "EMA 21 > EMA 50 (Bullish)" : "EMA 21 < EMA 50 (Bearish)"
            }
            
            return "EMA(21) = \(p21) | EMA(50) = \(p50) | \(posDesc) | \(spreadDesc)"
        }
        
        let d1EMAStr = formatEMALevels(emaAnalysis.d1, tfName: "D1")
        let h4EMAStr = formatEMALevels(emaAnalysis.h4, tfName: "H4")
        let h1EMAStr = formatEMALevels(emaAnalysis.h1, tfName: "H1")
        
        // Accurate H4 Swing High & Swing Low Detection
        let h4Pivots = LiquidityEngine.identifyPivots(bars: h4Bars, window: 2, timeframe: "H4")
        let h4SwingHighStr: String = {
            if let high = h4Pivots.filter({ $0.type == .buySide }).last?.price {
                return formatPrice(high)
            }
            if let maxBar = h4Bars.suffix(20).max(by: { $0.high < $1.high }) {
                return formatPrice(maxBar.high)
            }
            return "N/A"
        }()
        let h4SwingLowStr: String = {
            if let low = h4Pivots.filter({ $0.type == .sellSide }).last?.price {
                return formatPrice(low)
            }
            if let minBar = h4Bars.suffix(20).min(by: { $0.low < $1.low }) {
                return formatPrice(minBar.low)
            }
            return "N/A"
        }()
        
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
        
        // 4. H1 Momentum & RSI Metrics
        let momentumWindow = MomentumEngine.computeWindow(bars: execBars, windowSize: 10)
        let rsiVal = momentumWindow.currentRSI.map { ($0 as NSDecimalNumber).doubleValue }
        let rsiStr: String = {
            guard let val = rsiVal else { return "N/A" }
            let zone: String
            if isVi {
                if val >= 70 { zone = "Quá Mua (>70)" }
                else if val <= 30 { zone = "Quá Bán (<30)" }
                else if val >= 50 { zone = "Thiên Tăng / Phe Mua kiểm soát (50-70)" }
                else { zone = "Thiên Giảm / Phe Bán kiểm soát (30-50)" }
            } else {
                if val >= 70 { zone = "Overbought (>70)" }
                else if val <= 30 { zone = "Oversold (<30)" }
                else if val >= 50 { zone = "Bullish Control (50-70)" }
                else { zone = "Bearish Control (30-50)" }
            }
            return String(format: "%.1f (%@)", val, zone)
        }()
        
        let rsiSignalStr: String = {
            guard let rsi = rsiVal, let ema = momentumWindow.currentEMA9.map({ ($0 as NSDecimalNumber).doubleValue }) else {
                return "N/A"
            }
            let status: String
            if isVi {
                status = rsi >= ema ? "RSI trên Signal (Động lượng Mua)" : "RSI dưới Signal (Động lượng Bán)"
            } else {
                status = rsi >= ema ? "RSI above Signal (Bullish)" : "RSI below Signal (Bearish)"
            }
            return String(format: "%.1f [%@]", ema, status)
        }()
        
        let divStr = isVi ? (momentumWindow.divergenceVi ?? "Không có phân kỳ") : (momentumWindow.divergenceEn ?? "None")
        
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

            [CẤU TRÚC THỊ TRƯỜNG & HỆ THỐNG CHỈ BÁO KỸ THUẬT (EMA 21/50 & RSI 14)]:
            • Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)

            • Khung D1 (Macro Bias): Xu hướng [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              - Chỉ báo EMA D1: \(d1EMAStr)
              - Mức giá quan trọng: Đỉnh PDH: \(d1PDH) | Đáy PDL: \(d1PDL) | ADR 14 ngày: \(d1ADR)

            • Khung H4 (Cấu trúc sóng & Cản TP/SL): Xu hướng [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              - Chỉ báo EMA H4: \(h4EMAStr)
              - Mức giá then chốt: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)

            • Khung H1 (Thực thi, Động lượng & Tín hiệu kích hoạt lệnh): Xu hướng [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              - Chỉ báo EMA H1: \(h1EMAStr)
              - Chỉ báo Động lượng RSI(14) (Wilder):
                • Mức RSI hiện tại: \(rsiStr)
                • Đường tín hiệu RSI Signal (EMA 9): \(rsiSignalStr)
                • Phân kỳ động lượng (Divergence): [\(divStr)]
              - Vùng thanh khoản: BSL gần nhất: \(nearestBSLStr) | SSL gần nhất: \(nearestSSLStr)
              - Quét thanh khoản (SFP Sweeps): \(sweepsStr)

            • Tin tức kinh tế (Catalyst): \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            NHIỆM VỤ PHÂN TÍCH ĐÓN ĐẦU & THIẾT LẬP KẾ HOẠCH (PRE-TRADE ACTION PLAN):
            Phân tích ngắn gọn, trực diện theo đúng 4 mục (không lặp lại thông tin hồ sơ tài khoản) và kết thúc bằng bảng thông số [PRE-TRADE SETUP SPECIFICATION]:

            ### 1. Xu hướng vĩ mô D1 & Định hướng dòng tiền (Macro Bias)
            - Phe nào đang kiểm soát (Bulls hay Bears)? Giá đang ở vùng Premium hay Discount?
            - Đánh giá vị thế giá so với EMA(21) và EMA(50) D1 (Mở rộng xu hướng hay đang pullback về EMA)?
            - Mục tiêu thanh khoản ngày: Khả năng tìm về PDH (\(d1PDH)) hoặc PDL (\(d1PDL)).

            ### 2. Cấu trúc sóng & Vùng cản then chốt H4 (Key Barriers)
            - Xu hướng H4 đang là TĂNG, GIẢM hay ĐI NGANG theo cấu trúc sóng và cụm EMA 21/50?
            - Đánh giá cụm EMA 21/50 H4 như vùng hỗ trợ/kháng cự động (Dynamic Support/Resistance): Giá có đang phản ứng hoặc test lại vùng đệm EMA 21-50 này không?
            - Nhận diện các VÙNG CẢN H4 (Swing High: \(h4SwingHighStr), Swing Low: \(h4SwingLowStr), Supply/Demand, FVG) để làm MỤC TIÊU CHỐT LỜI (TP1/TP2) hoặc CẮT LỖ (SL).

            ### 3. Cấu trúc thực thi H1 & Tín hiệu chỉ báo (Execution, EMA & RSI)
            - Cấu trúc giá & EMA H1: Giá đang bám đường EMA nào? Có bị dãn biên độ (Overextended) quá xa EMA 21 không?
            - Động lượng RSI(14) H1: RSI đang ở vùng nào (Quá mua / Quá bán / Tích lũy)? Có xuất hiện Phân kỳ RSI (Bullish/Bearish Divergence) hay tín hiệu giao cắt Signal để kích hoạt lệnh không?
            - Bẫy thanh khoản & Tín hiệu kích hoạt: Đã có nhịp quét thanh khoản (SFP Sweep) hoặc nến H1 xác nhận chưa, hay vào lệnh sớm có rủi ro bị bẫy quét SL?

            ### 4. Khuyến nghị & Kế hoạch lệnh cụ thể (Actionable Recommendation)
            - KẾT LUẬN RÕ RÀNG: [BUY (LONG) / SELL (SHORT) / FLAT (ĐỨNG NGOÀI)].
            - LOẠI SETUP: [THUẬN XU HƯỚNG THEO CỤM EMA H4/H1] hoặc [NGHỊCH XU HƯỚNG / SÓNG HỒI TỪ CẢN H4 KÈM PHÂN KỲ RSI].
            - Nếu KHUYẾN NGHỊ VÀO LỆNH (BUY/SELL):
              • Điểm vào tối ưu (Entry) & Tín hiệu nến H1 / RSI kích hoạt (Trigger).
              • Cắt lỗ bắt buộc (Structural Invalidation SL): Mức giá SL cụ thể theo vi phạm cấu trúc nến hoặc mốc EMA then chốt.
              • Mục tiêu chốt lời (Targets): TP 1 và TP 2 đặt tại các vùng Cản H4 ở Mục 2.
              • Tỷ lệ Risk/Reward (R:R) dự kiến.
            - Nếu KHUYẾN NGHỊ FLAT (ĐỨNG NGOÀI): Nêu rõ điều kiện H1 / RSI / EMA cần chờ thêm trước khi vào lệnh.

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

            [MARKET STRUCTURE & TECHNICAL INDICATORS (EMA 21/50 & RSI 14)]:
            • Symbol: \(symbol) | Current Price: \(currentPrice)

            • D1 Frame (Macro Bias): Trend [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              - D1 EMA Levels: \(d1EMAStr)
              - Macro Key Levels: PDH: \(d1PDH) | PDL: \(d1PDL) | 14-day ADR: \(d1ADR)

            • H4 Frame (Key Barriers for TP/SL): Trend [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              - H4 EMA Levels: \(h4EMAStr)
              - Key Swing Levels: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)

            • H1 Frame (Execution, Momentum & Entry Triggers): Trend [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              - H1 EMA Levels: \(h1EMAStr)
              - Wilder RSI(14) Momentum:
                • Current RSI: \(rsiStr)
                • RSI Signal Line (EMA 9): \(rsiSignalStr)
                • Momentum Divergence: [\(divStr)]
              - Liquidity Pools: Nearest BSL: \(nearestBSLStr) | Nearest SSL: \(nearestSSLStr)
              - Recent SFP Sweeps: \(sweepsStr)

            • Macro News Catalyst: \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            TASK: PRE-TRADE SMC MARKET BIAS & ACTIONABLE PLAN:
            Provide a razor-sharp, institutional analysis across the 4 sections below, concluding with the [PRE-TRADE SETUP SPECIFICATION] block:

            ### 1. D1 Macro Regime & Directional Bias
            - Which participant controls the market (Bulls or Bears)? Is price operating in Premium or Discount?
            - Evaluate price position relative to D1 EMA(21) and EMA(50) (Trend expansion or retracement)?
            - Daily liquidity draw: Probability of tagging PDH (\(d1PDH)) or PDL (\(d1PDL)).

            ### 2. H4 Swing Structure & Key Barriers (TP/SL Targets)
            - What is the H4 trend according to swing structure and EMA 21/50 dynamic alignment?
            - Assess EMA 21/50 dynamic support/resistance: Is price currently testing or reacting to this EMA pocket?
            - Identify key H4 barriers (Swing High: \(h4SwingHighStr), Swing Low: \(h4SwingLowStr), Supply/Demand zones, FVG) as TARGET BARRIERS for TP1/TP2 or protective SL.

            ### 3. H1 Execution Trigger, EMA & RSI Dynamics
            - H1 Structure & EMAs: Is price riding the EMAs or overextended from EMA 21?
            - H1 RSI(14) Momentum: Is RSI overbought, oversold, or consolidating? Does divergence or a signal line crossover confirm an entry or warn of a reversal?
            - Traps & Execution Timing: Has an SFP sweep occurred or has an H1 confirmation candle closed, or does entering early carry high risk of being stopped out?

            ### 4. Actionable Directive & Execution Blueprint
            - DECISIVE VERDICT: [BUY (LONG) / SELL (SHORT) / FLAT (NO SETUP)].
            - SETUP TYPE: [FOLLOW-TREND CONTINUATION WITH EMAs] or [COUNTER-TREND REVERSAL FROM H4 BARRIER WITH RSI DIVERGENCE].
            - If EXECUTABLE SETUP (BUY/SELL):
              • Optimal Entry Zone & H1 Confirmation / RSI Trigger.
              • Structural Invalidation (SL): Specific price level based on H1 structure failure or key EMA invalidation.
              • Profit Targets (TP1 & TP2): Anchored to H4 key barriers from Section 2.
              • Projected Risk-to-Reward (R:R).
            - If FLAT: State clearly what H1 price/EMA/RSI development is required before entering.

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
