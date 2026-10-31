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
        
        // 3b. Recent H4 Candles (Last 3 bars OHLC)
        let h4CandlesSummary = buildH4CandleSummary(bars: h4Bars, count: 3, isVi: isVi)
        
        // 3c. 15-Candle H1 Execution Series (OHLC + EMA 21/50 + Wilder RSI 14)
        let h1CandlesSummary = buildH1CandleSeriesSummary(bars: execBars, count: 15, symbol: symbol, isVi: isVi)
        
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
            if let nextEvent = highImpacts.first(where: { ($0.date ?? Date.distantPast) > now }),
               let eventDate = nextEvent.date {
                let diffMin = Int(eventDate.timeIntervalSince(now) / 60)
                let timeDesc = diffMin >= 60 ? "\(diffMin / 60)h \(diffMin % 60)m" : "\(diffMin) phút"
                return isVi
                    ? "⚠️ Tin đỏ: \(nextEvent.title) (\(nextEvent.country)) sẽ công bố trong \(timeDesc)"
                    : "⚠️ High-Impact News: \(nextEvent.title) (\(nextEvent.country)) in \(timeDesc)"
            }
            return isVi ? "Không có tin tức Đỏ (High Impact) trong 12h tới" : "No High-Impact events within 12h"
        }()
        
        // 6. Active Account Context, Broker vs Prop Firm, and Today's Performance
        let accName = sessionSummary?.accountName ?? "Exness"
        let propFirm = sessionSummary?.propFirmName
        let isProp = propFirm?.isEmpty == false
        
        let accountCategoryStr: String = {
            if isProp, let firm = propFirm {
                let phase = sessionSummary?.stepOrPhaseName.map { " - \($0)" } ?? ""
                return isVi ? "Quỹ Cấp Vốn (\(firm)\(phase))" : "Prop Firm Account (\(firm)\(phase))"
            } else {
                let broker = accName.lowercased().contains("exness") ? "Exness" : "Broker tiêu chuẩn"
                return isVi ? "Tài khoản Cá nhân (\(broker))" : "Personal Brokerage (\(broker))"
            }
        }()
        
        let platformDesc = "cTrader / Broker Terminal"
        
        let tradesToday = sessionSummary?.totalTradesToday ?? 0
        let winsToday = sessionSummary?.winsToday ?? 0
        let lossesToday = sessionSummary?.lossesToday ?? 0
        let beToday = sessionSummary?.breakevensToday ?? 0
        let openToday = sessionSummary?.openTradesToday ?? 0
        
        let todayTradesDesc = isVi
            ? "Tổng \(tradesToday) lệnh (\(winsToday) Thắng | \(lossesToday) Thua | \(beToday) Hòa) | Lệnh đang chạy: \(openToday)"
            : "Total \(tradesToday) trades (\(winsToday) W | \(lossesToday) L | \(beToday) BE) | Active Open: \(openToday)"
            
        let pnlTodayVal = sessionSummary.map { NSDecimalNumber(decimal: $0.netPnlToday).doubleValue } ?? 0.0
        let pnlTodayStr = (pnlTodayVal >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlTodayVal))
        
        let streak = sessionSummary?.currentStreakToday ?? 0
        let streakStr: String = {
            if streak > 0 { return isVi ? "Thắng \(streak) lệnh liên tiếp (+)" : "\(streak) wins in a row (+)" }
            if streak < 0 { return isVi ? "⚠️ Đang thua \(abs(streak)) lệnh liên tiếp (-)" : "⚠️ In a \(abs(streak))-loss losing streak (-)" }
            return isVi ? "Chưa có chuỗi lệnh hôm nay" : "No active streak today"
        }()
        
        let dailyBufferStr: String = {
            if let buf = sessionSummary?.dailyLossBufferRemainingUsd {
                let limit = sessionSummary?.dailyLossLimitUsd.map { String(format: "$%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? (isVi ? "Theo quy định" : "Rule-based")
                let bufVal = (buf as NSDecimalNumber).doubleValue
                return isVi
                    ? "Hạn mức lỗ ngày: \(limit) | Đệm lỗ còn lại hôm nay: $\(String(format: "%.2f", bufVal))"
                    : "Daily Loss Limit: \(limit) | Remaining Buffer: $\(String(format: "%.2f", bufVal))"
            }
            return isVi
                ? "Hạn mức rủi ro ngày: 2-3 lệnh (tối đa 2-3% vốn) | Đang tuân thủ kỷ luật"
                : "Daily Risk Budget: 2-3 trades (max 2-3% capital) | Disciplined"
        }()
        
        let isStreakOrBufferBreached = streak <= -2 || (sessionSummary?.dailyLossBufferRemainingUsd.map { $0 <= 0 } ?? false)
        
        let riskGuardrailWarning: String = {
            if isStreakOrBufferBreached {
                return isVi
                    ? "\n🚨 CẢNH BÁO RỦI RO ĐỎ TỪ HỆ THỐNG: Trader đang dính chuỗi thua (-2 trở lên) hoặc đệm lỗ ngày đã cạn. AI BẮT BUỘC KHUYẾN NGHỊ ĐỨNG NGOÀI (FLAT), TUYỆT ĐỐI KHÔNG GỢI Ý MỞ LỆNH MỚI ĐỂ TRÁNH TRẢ THÙ THỊ TRƯỜNG (REVENGE TRADING)!\n"
                    : "\n🚨 CRITICAL RISK GUARDRAIL: Trader is on a losing streak (-2 or worse) or daily loss buffer is exhausted. AI MUST STRICTLY ADVISE FLAT (STAND ASIDE), ZERO NEW TRADES TO PREVENT REVENGE TRADING!\n"
            }
            return ""
        }()
        
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
        
        let riskPctStr = (traderProfile?.maxRiskPerTrade.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "1.0% vốn"
        
        let riskDollarStr: String = {
            if let bal = sessionSummary?.balance {
                let balNum = NSDecimalNumber(decimal: bal).doubleValue
                let riskVal = balNum * 0.01
                return String(format: " (~$%.2f)", riskVal)
            }
            return ""
        }()
        
        let tradingStyleStr = (traderProfile?.tradingStyle.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Day Trader / Swing Trader"
            
        let strategyStr = (traderProfile?.primaryPlaybooks.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? (isVi ? "Price Action, Cấu trúc thị trường H4/H1" : "Price Action, H4/H1 Market Structure")
            
        let leaksStr = (traderProfile?.knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Dời SL, chốt non, FOMO, Trả thù lệnh"
            
        let customNotesStr = (traderProfile?.customMemoryNotes.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Tỷ lệ R:R >= 2:1, bảo vệ vốn khi thị trường giằng co, không bao giờ trả thù lệnh"
        
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
            [THÔNG TIN TÀI KHOẢN & TRẠNG THÁI RỦI RO HÔM NAY]:
            • Số dư thực tế: \(realBalStr) \(equityStr)
            • Trạng thái lệnh hôm nay: \(todayTradesDesc)
            • PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakStr)
            • \(dailyBufferStr)
            • Ngân sách rủi ro mỗi lệnh: \(riskPctStr)\(riskDollarStr)
            • Phong cách giao dịch: \(tradingStyleStr)
            • Chiến lược & Playbook ưu tiên: \(strategyStr)
            • Lỗ hổng tâm lý cần triệt tiêu: \(leaksStr)
            • Kỷ luật cá nhân: \(customNotesStr)\(riskGuardrailWarning)
            [CẤU TRÚC THỊ TRƯỜNG & HỆ THỐNG CHỈ BÁO KỸ THUẬT (EMA 21/50 & RSI 14)]:
            • Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)

            • Khung D1 (Macro Bias): Xu hướng [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              - Chỉ báo EMA D1: \(d1EMAStr)
              - Mức giá quan trọng: Đỉnh PDH: \(d1PDH) | Đáy PDL: \(d1PDL) | ADR 14 ngày: \(d1ADR)

            • Khung H4 (Cấu trúc sóng & Cản TP/SL): Xu hướng [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              - Chỉ báo EMA H4: \(h4EMAStr)
              - Mức giá then chốt: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              - 3 nến H4 gần nhất (Hành vi nến khung lớn):
            \(h4CandlesSummary)

            • Khung H1 (Thực thi, Động lượng & Kích hoạt lệnh): Xu hướng [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              - Chỉ báo EMA H1: \(h1EMAStr)
              - Chỉ báo Động lượng RSI(14) (Wilder):
                • Mức RSI hiện tại: \(rsiStr)
                • Đường tín hiệu RSI Signal (EMA 9): \(rsiSignalStr)
                • Phân kỳ động lượng (Divergence): [\(divStr)]
              - Vùng thanh khoản: BSL gần nhất: \(nearestBSLStr) | SSL gần nhất: \(nearestSSLStr)
              - Quét thanh khoản (SFP Sweeps): \(sweepsStr)

            • Chuỗi 15 nến H1 gần nhất (OHLC + EMA 21/50 + RSI 14):
            \(h1CandlesSummary)

            • Tin tức kinh tế (Catalyst): \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            NHIỆM VỤ PHÂN TÍCH ĐÓN ĐẦU & THIẾT LẬP KẾ HOẠCH (PRE-TRADE ACTION PLAN):
            Phân tích ngắn gọn, trực diện theo đúng 4 mục (không lặp lại thông tin hồ sơ tài khoản) và kết thúc bằng bảng thông số [PRE-TRADE SETUP SPECIFICATION]:

            ### 1. Xu hướng vĩ mô D1 & Định hướng dòng tiền
            - Phe nào đang kiểm soát (Bulls hay Bears)? Giá đang ở vùng Premium hay Discount?
            - Đánh giá vị thế giá so với EMA(21) và EMA(50) D1 (Mở rộng xu hướng hay đang pullback về EMA)?
            - Mục tiêu thanh khoản ngày: Khả năng tìm về PDH (\(d1PDH)) hoặc PDL (\(d1PDL)).

            ### 2. Cấu trúc sóng & Vùng cản then chốt H4
            - Xu hướng H4 đang là TĂNG, GIẢM hay ĐI NGANG theo cấu trúc sóng và cụm EMA 21/50?
            - Đánh giá 3 nến H4 gần nhất: Có xuất hiện nến từ chối (Rejection wick) hay nến đóng cửa xác nhận tại cản / EMA 21-50 không?
            - Nhận diện các VÙNG CẢN H4 (Swing High: \(h4SwingHighStr), Swing Low: \(h4SwingLowStr), Supply/Demand, FVG) để làm MỤC TIÊU CHỐT LỜI (TP1/TP2) hoặc CẮT LỖ (SL).

            ### 3. Cấu trúc thực thi H1 qua Chuỗi 15 nến
            - Dựa vào diễn biến chuỗi nến H1 và H4 ở trên (giá Mở, Cao, Thấp, Đóng và cụm EMA 21/50, RSI) để phân tích Price Action: Nến vừa đóng có rút chân/từ chối cản tại EMA 21/50 hay bứt phá dứt khoát? Giá đang bám EMA hay bị dãn biên độ (Overextended)?
            - Động lượng RSI(14) H1: Nhìn quỹ đạo RSI qua 15 nến, RSI đang tăng hay giảm? Có phân kỳ đảo chiều (Bullish/Bearish Divergence) hoặc giao cắt Signal line để kích hoạt lệnh không?
            - Bẫy thanh khoản & Tín hiệu kích hoạt: Đã có nhịp quét thanh khoản (SFP Sweep) hoặc nến xác nhận chưa, hay vào lệnh sớm có rủi ro bị bẫy quét SL?

            ### 4. Khuyến nghị & Kế hoạch lệnh cụ thể
            - KẾT LUẬN RÕ RÀNG: [BUY (LONG) / SELL (SHORT) / FLAT (ĐỨNG NGOÀI)].
            ⚠️ NGUYÊN TẮC QUẢN TRỊ RỦI RO NGHIÊM NGẶT: Nếu hôm nay trader đã dính chuỗi thua (-2 trở lên) hoặc đệm lỗ ngày đã cạn, BẮT BUỘC KẾT LUẬN FLAT (ĐỨNG NGOÀI) để bảo vệ tài khoản, TUYỆT ĐỐI KHÔNG GỢI Ý MỞ LỆNH!
            - LOẠI SETUP: [THUẬN XU HƯỚNG THEO CỤM EMA H4/H1] hoặc [NGHỊCH XU HƯỚNG / SÓNG HỒI TỪ CẢN H4 KÈM PHÂN KỲ RSI].
            - Nếu KHUYẾN NGHỊ VÀO LỆNH (BUY/SELL):
              • Điểm vào tối ưu (Entry) & Tín hiệu nến H1 / RSI kích hoạt (Trigger).
              • Cắt lỗ bắt buộc (Structural Invalidation SL): Mức giá SL cụ thể theo vi phạm cấu trúc nến hoặc mốc EMA then chốt.
              • Mục tiêu chốt lời (Targets): TP 1 và TP 2 đặt tại các vùng Cản H4 ở Mục 2.
              • Tỷ lệ Risk/Reward (R:R) dự kiến.
            - Nếu KHUYẾN NGHỊ FLAT (ĐỨNG NGOÀI): Nêu rõ điều kiện H1 / RSI / EMA hoặc tâm lý cần chờ thêm trước khi vào lệnh.

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
            [ACCOUNT CONTEXT & TODAY'S RISK PROFILE]:
            • Authoritative Balance: \(realBalStr) \(equityStr)
            • Today's Trade Activity: \(todayTradesDesc)
            • Today's Net P&L: \(pnlTodayStr) | Current Streak: \(streakStr)
            • \(dailyBufferStr)
            • Risk Budget Per Trade: \(riskPctStr)\(riskDollarStr)
            • Trading Style: \(tradingStyleStr)
            • Primary Playbooks & Strategy: \(strategyStr)
            • Known Leaks: \(leaksStr)
            • Discipline Notes: \(customNotesStr)\(riskGuardrailWarning)
            [MARKET STRUCTURE & TECHNICAL INDICATORS (EMA 21/50 & RSI 14)]:
            • Symbol: \(symbol) | Current Price: \(currentPrice)

            • D1 Frame (Macro Bias): Trend [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              - D1 EMA Levels: \(d1EMAStr)
              - Macro Key Levels: PDH: \(d1PDH) | PDL: \(d1PDL) | 14-day ADR: \(d1ADR)

            • H4 Frame (Key Barriers for TP/SL): Trend [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              - H4 EMA Levels: \(h4EMAStr)
              - Key Swing Levels: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              - Recent 3 H4 Bars:
            \(h4CandlesSummary)

            • H1 Frame (Execution, Momentum & Entry Triggers): Trend [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              - H1 EMA Levels: \(h1EMAStr)
              - Wilder RSI(14) Momentum:
                • Current RSI: \(rsiStr)
                • RSI Signal Line (EMA 9): \(rsiSignalStr)
                • Momentum Divergence: [\(divStr)]
              - Liquidity Pools: Nearest BSL: \(nearestBSLStr) | Nearest SSL: \(nearestSSLStr)
              - Recent SFP Sweeps: \(sweepsStr)

            • Recent 15-Candle H1 Execution Series (OHLC + EMA 21/50 + Wilder RSI 14):
            \(h1CandlesSummary)

            • Macro News Catalyst: \(newsBlock)
            \(symbolLessonsBlock)\(liveUpdateBlock)\(thesisContinuityBlock)\(visionNote)
            TASK: PRE-TRADE MARKET BIAS & ACTIONABLE PLAN:
            Provide a razor-sharp, institutional analysis across the 4 sections below, concluding with the [PRE-TRADE SETUP SPECIFICATION] block:

            ### 1. D1 Macro Regime & Directional Bias
            - Which participant controls the market (Bulls or Bears)? Is price operating in Premium or Discount?
            - Evaluate price position relative to D1 EMA(21) and EMA(50) (Trend expansion or retracement)?
            - Daily liquidity draw: Probability of tagging PDH (\(d1PDH)) or PDL (\(d1PDL)).

            ### 2. H4 Swing Structure & Key Barriers
            - What is the H4 trend according to swing structure and EMA 21/50 dynamic alignment?
            - Assess recent 3 H4 candles: Is there an upper/lower wick rejection or confirmed close against the EMA 21-50 zone?
            - Identify key H4 barriers (Swing High: \(h4SwingHighStr), Swing Low: \(h4SwingLowStr), Supply/Demand zones, FVG) as TARGET BARRIERS for TP1/TP2 or protective SL.

            ### 3. H1 Execution Across 15-Candle Series
            - Analyze Price Action based on the 15-candle H1 and H4 sequences above (OHLC, EMA 21/50, RSI): Did the recent bar reject at EMA 21/50 or break cleanly? Is price riding or overextended from EMA 21?
            - H1 RSI(14) Trajectory: Looking at the 15-bar RSI values, is momentum expanding or stalling? Does divergence or a signal line crossover confirm an entry?
            - Traps & Execution Timing: Has an SFP sweep occurred or has an H1 confirmation candle closed, or does entering early carry high risk of being stopped out?

            ### 4. Actionable Trade Setup & Recommendation
            - DECISIVE VERDICT: [BUY (LONG) / SELL (SHORT) / FLAT (NO SETUP)].
            ⚠️ STRICT CAPITAL PRESERVATION: If trader has hit a losing streak (-2 or worse) or depleted the daily buffer, MANDATORY VERDICT IS FLAT. Do NOT issue new trade setups!
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
    
    // MARK: - Higher-Timeframe H4 Candle Summary Helper
    public static func buildH4CandleSummary(bars: [MarketBar], count: Int = 3, isVi: Bool = true) -> String {
        guard !bars.isEmpty else { return isVi ? "Không có dữ liệu nến H4" : "No H4 candle data" }
        let takeCount = min(count, bars.count)
        let slice = Array(bars.suffix(takeCount))
        
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        let n = slice.count
        var lines: [String] = []
        for (idx, b) in slice.enumerated() {
            let offset = n - 1 - idx
            let label = offset == 0 ? (isVi ? "H4 [Nến hiện tại]" : "H4 [Live Candle]") : "H4 [-\(offset * 4)h]"
            lines.append("  • \(label): O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | C: \(fmt(b.close))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 15-Candle H1 Execution Series Helper (OHLC + EMA 21/50 + Wilder RSI 14)
    public static func buildH1CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 15,
        symbol: String = "",
        isVi: Bool = true
    ) -> String {
        guard !bars.isEmpty else { return isVi ? "Không có dữ liệu nến H1" : "No H1 candle data" }
        
        let ema21 = MovingAverageEngine.calculateEMA(period: 21, bars: bars)
        let ema50 = MovingAverageEngine.calculateEMA(period: 50, bars: bars)
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
        
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        var lines: [String] = []
        for i in startIndex..<n {
            let bar = bars[i]
            let offset = n - 1 - i
            let timeLabel = offset == 0 ? (isVi ? "[Hiện tại]" : "[Live]") : "[-t-\(offset)h]"
            
            let e21Str = i < ema21.count ? fmt(ema21[i]) : "N/A"
            let e50Str = i < ema50.count ? fmt(ema50[i]) : "N/A"
            
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
            let line = "  • #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close)) | EMA21: \(e21Str) | EMA50: \(e50Str) | RSI: \(rsiVal)"
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }
}
