import Foundation

// MARK: - Pre-Trade Multi-Timeframe Prompt Builder Extension
// Integrates Master Institutional Trader Persona, Dynamic Contract Sizing,
// Empirical Behavioral Leak Mining, and Live Price Action Dynamics (H1/M15).
extension AIPromptBuilder {
    
    /// Assembles a streamlined, high-signal multi-timeframe market structure prompt (D1, H4, H1, M15) for pre-trade forward planning.
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
        hasImage: Bool = false,
        historicalTrades: [Trade] = []
    ) -> String {
        let isVi = language == "vi"
        
        func formatPrice(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
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
                return isVi ? "Chua du du lieu nen tinh EMA 21/50" : "Insufficient bars for EMA 21/50"
            }
            let p21 = formatPrice(e21)
            let p50 = formatPrice(e50)
            let cur = snap.currentPrice
            let dist = cur - e21
            let distVal = formatPrice(abs(dist))
            
            let posDesc: String
            if isVi {
                posDesc = dist >= 0 ? "Gia tren EMA 21 (+\(distVal))" : "Gia duoi EMA 21 (-\(distVal))"
            } else {
                posDesc = dist >= 0 ? "Price above EMA 21 (+\(distVal))" : "Price below EMA 21 (-\(distVal))"
            }
            
            let spreadDesc: String
            if isVi {
                spreadDesc = e21 >= e50 ? "EMA 21 > EMA 50 (Thien Tang)" : "EMA 21 < EMA 50 (Thien Giam)"
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
        
        // 3. Institutional Liquidity & SFP Sweeps
        let liquidity = LiquidityEngine.analyzeLiquidity(
            symbol: symbol,
            barsM15: execBars,
            barsH4: h4Bars,
            barsD1: d1Bars
        )
        
        // 3b. Recent H4 Candles (Last 3 bars OHLC)
        let h4CandlesSummary = buildH4CandleSummary(bars: h4Bars, count: 3, isVi: isVi)
        
        // 3c. 24-Candle H1 Execution Series (OHLC + EMA 21/50 + Wilder RSI 14)
        let h1CandlesSummary = buildH1CandleSeriesSummary(bars: execBars, count: 24, symbol: symbol, isVi: isVi)
        
        // 3d. 16-Candle M15 Micro-Execution Series
        let m15CandlesSummary = buildM15CandleSeriesSummary(bars: m15Bars, count: 16, symbol: symbol, isVi: isVi)
        
        // 3e. Live Unclosed Candle Dynamics (Current Price Action Pulse)
        let liveCandlePulse = buildLiveUnclosedCandlePulse(bar: execBars.last ?? m15Bars.last, isVi: isVi)
        
        let nearestBSLStr: String = {
            if let bsl = liquidity.nearestBSL {
                let dist = liquidity.distanceToBSLPips.map { " (khoảng cách \(formatPrice($0)))" } ?? ""
                return "\(bsl.label) tại \(formatPrice(bsl.price))\(dist)"
            }
            return isVi ? "Không có mốc BSL gần" : "No nearby BSL pool"
        }()
        
        let nearestSSLStr: String = {
            if let ssl = liquidity.nearestSSL {
                let dist = liquidity.distanceToSSLPips.map { " (khoảng cách \(formatPrice($0)))" } ?? ""
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
                    ? "[LỊCH TIN TỨC]: \(nextEvent.title) (\(nextEvent.country)) công bố trong \(timeDesc)"
                    : "[CATALYST EVENT]: \(nextEvent.title) (\(nextEvent.country)) in \(timeDesc)"
            }
            return isVi ? "Không có tin tức quan trọng trong 12h tới" : "No high-impact events within 12h"
        }()
        
        // 6. Active Account Context & Mathematical Risk Guardrails
        let tradesToday = sessionSummary?.totalTradesToday ?? 0
        let winsToday = sessionSummary?.winsToday ?? 0
        let lossesToday = sessionSummary?.lossesToday ?? 0
        let beToday = sessionSummary?.breakevensToday ?? 0
        let openToday = sessionSummary?.openTradesToday ?? 0
        
        let todayTradesDesc = isVi
            ? "Tổng \(tradesToday) lệnh (\(winsToday) Thắng | \(lossesToday) Thua | \(beToday) Hoà) | Lệnh đang mở: \(openToday)"
            : "Total \(tradesToday) trades (\(winsToday) W | \(lossesToday) L | \(beToday) BE) | Open: \(openToday)"
            
        let pnlTodayVal = sessionSummary.map { NSDecimalNumber(decimal: $0.netPnlToday).doubleValue } ?? 0.0
        let pnlTodayStr = (pnlTodayVal >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlTodayVal))
        
        let streak = sessionSummary?.currentStreakToday ?? 0
        let streakStr: String = {
            if streak > 0 { return isVi ? "Thắng \(streak) lệnh liên tiếp (+)" : "\(streak) wins in a row (+)" }
            if streak < 0 { return isVi ? "Đang thua \(abs(streak)) lệnh liên tiếp (-)" : "In a \(abs(streak))-loss losing streak (-)" }
            return isVi ? "Chưa có chuỗi lệnh hôm nay" : "No active streak today"
        }()
        
        let balVal = sessionSummary?.balance.map { ($0 as NSDecimalNumber).doubleValue } ?? 0.0
        let maxDailyLossPct = traderProfile?.maxDailyLossPercent ?? 3.0
        let todayLossPct: Double = {
            if balVal > 0 && pnlTodayVal < 0 {
                return (abs(pnlTodayVal) / balVal) * 100.0
            }
            return 0.0
        }()
        
        let isDailyLossLimitBreached: Bool = {
            if let buf = sessionSummary?.dailyLossBufferRemainingUsd, (buf as NSDecimalNumber).doubleValue <= 0 {
                return true
            }
            if balVal > 0 && todayLossPct >= maxDailyLossPct {
                return true
            }
            return false
        }()
        
        let dailyBufferStr: String = {
            if let buf = sessionSummary?.dailyLossBufferRemainingUsd {
                let limit = sessionSummary?.dailyLossLimitUsd.map { String(format: "$%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? (isVi ? "Theo quy định" : "Rule-based")
                let bufVal = (buf as NSDecimalNumber).doubleValue
                return isVi
                    ? "Hạn mức lỗ ngày: \(limit) | Đệm lỗ còn lại: $\(String(format: "%.2f", bufVal)) (Tối đa \(String(format: "%.1f", maxDailyLossPct))% vốn)"
                    : "Daily Loss Limit: \(limit) | Remaining Buffer: $\(String(format: "%.2f", bufVal)) (Max \(String(format: "%.1f", maxDailyLossPct))%)"
            }
            return isVi
                ? "Hạn mức rủi ro ngày: Tối đa \(String(format: "%.1f", maxDailyLossPct))% vốn | Đang lỗ \(String(format: "%.1f", todayLossPct))%"
                : "Daily Risk Budget: Max \(String(format: "%.1f", maxDailyLossPct))% | Currently down \(String(format: "%.1f", todayLossPct))%"
        }()
        
        let riskGuardrailWarning: String = {
            if isDailyLossLimitBreached {
                return isVi
                    ? "\n[CẢNH BÁO VI PHẠM HẠN MỨC LỖ NGÀY]: Mức lỗ hôm nay đã chạm hoặc vượt giới hạn tối đa cho phép (\(String(format: "%.1f", todayLossPct))% >= \(String(format: "%.1f", maxDailyLossPct))%). AI BẮT BUỘC TƯ VẤN ĐỨNG NGOÀI (FLAT / HALT), TUYỆT ĐỐI KHÔNG MỞ THÊM LỆNH MỚI ĐỂ BẢO VỆ VỐN.\n"
                    : "\n[CRITICAL MAX DAILY LOSS BREACH]: Daily loss has reached or exceeded max limit (\(String(format: "%.1f", todayLossPct))% >= \(String(format: "%.1f", maxDailyLossPct))%). AI MUST ADVISE FLAT (HALT), NO NEW TRADES ALLOWED.\n"
            } else if streak <= -2 {
                return isVi
                    ? "\n[LƯU Ý TÂM LÝ & QUẢN TRỊ RỦI RO]: Trader đang có chuỗi thua \(abs(streak)) lệnh liên tiếp hôm nay. Chưa vi phạm hạn mức lỗ ngày (\(String(format: "%.1f", todayLossPct))% / \(String(format: "%.1f", maxDailyLossPct))%). AI CẦN KHẮT KHE TUYỆT ĐỐI VỚI ĐIỀU KIỆN VÀO LỆNH, chỉ gợi ý setup nếu cấu trúc nến và R:R đạt chuẩn tối đa, ngược lại ưu tiên đứng ngoài (FLAT).\n"
                    : "\n[PSYCHOLOGY & RISK CAUTION]: Trader is on a \(abs(streak))-loss streak. Daily loss limit not yet breached (\(String(format: "%.1f", todayLossPct))% / \(String(format: "%.1f", maxDailyLossPct))%). Scrutinize setups strictly; prioritize standing aside (FLAT) unless structure and R:R are pristine.\n"
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
                return "| Von rong (Equity): \(Formatters.formatCurrency(eq, currency: curr))"
            }
            return ""
        }()
        
        // Authoritative Contract Specs & Mathematically Grounded Risk
        let instrumentSpec = AssetContractEngine.spec(for: symbol)
        let numericRisk = traderProfile?.numericRiskPercent ?? Decimal(1.0)
        let targetRR = traderProfile?.targetRiskRewardRatio ?? 3.0
        let targetRiskDollars: Decimal = {
            if let bal = sessionSummary?.balance, bal > 0 {
                return bal * (numericRisk / 100)
            }
            return 0
        }()
        let targetRiskDollarsStr = String(format: "$%.2f", (targetRiskDollars as NSDecimalNumber).doubleValue)
        
        let contractSizingBlockVi = """
        [QUY CÁCH HỢP ĐỒNG VÀ TOÁN HỌC KHỐI LƯỢNG LỆNH (ASSET CONTRACT SIZING)]:
        - Tài sản: \(symbol) | Nhóm: \(instrumentSpec.assetCategory.rawValue)
        - Kích thước hợp đồng chuẩn (1.00 lot): \(instrumentSpec.contractSize) đơn vị
        - Bước giá Pip: \(instrumentSpec.pipSize)
        - Số dư thực tế: \(realBalStr) \(equityStr)
        - Tỷ lệ rủi ro cài đặt: \(numericRisk)% vốn
        - Ngân sách rủi ro tối đa: \(targetRiskDollarsStr) USD (Số tiền lỗ tối đa nếu chạm SL)
        - Mục tiêu Tỷ lệ Risk/Reward bắt buộc: Tối thiểu 1:\(String(format: "%.1f", targetRR)) (BẮT BUỘC TUÂN THỦ)
        - CÔNG THỨC TOÁN HỌC TÍNH SỐ LOT:
          Số Lot = (Số tiền rủi ro $) / (|Entry - SL| x Kích thước hợp đồng x Tỷ giá quy đổi)
          Lưu ý: Khi đưa ra thông số Volume trong Setup, bắt buộc tính theo số tiền rủi ro \(targetRiskDollarsStr) ở trên.
        """
        
        let contractSizingBlockEn = """
        [AUTHORITATIVE CONTRACT SIZING & MATHEMATICAL RISK PARAMETERS]:
        - Instrument: \(symbol) | Asset Class: \(instrumentSpec.assetCategory.rawValue)
        - Standard Contract Size (1.00 lot): \(instrumentSpec.contractSize) units
        - Pip Size: \(instrumentSpec.pipSize)
        - Authoritative Balance: \(realBalStr) \(equityStr)
        - Configured Risk Per Trade: \(numericRisk)%
        - Max Risk Dollar Budget: \(targetRiskDollarsStr) USD (Maximum allowed loss at Stop Loss)
        - Mandatory Target Risk/Reward Ratio: Minimum 1:\(String(format: "%.1f", targetRR)) (NON-NEGOTIABLE)
        - MATHEMATICAL POSITION SIZING FORMULA:
          Lots = (Risk Budget $) / (|Entry - SL| x Contract Size x Conversion Rate)
        """
        
        // 7. Empirical Behavioral Leaks Mined from Database
        let behavioralLeaksBlock: String = {
            guard !historicalTrades.isEmpty else { return "" }
            let mining = TraderBehaviorMiningEngine.mineLeaks(from: historicalTrades, targetSymbol: symbol)
            return TraderBehaviorMiningEngine.formatForPrompt(result: mining, isVi: isVi)
        }()
        
        // 8. Follow-up Live Update & Thesis Continuity
        var liveUpdateBlock = ""
        if let update = liveCandleUpdate, !update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liveUpdateBlock = isVi
                ? "\n[DIỄN BIẾN GIÁ THỰC TẾ VỪA CẬP NHẬT]:\n\(update)\n"
                : "\n[LIVE MARKET PRICE ACTION UPDATE]:\n\(update)\n"
        }
        
        var thesisContinuityBlock = ""
        if let prev = previousAnalysis, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let condensedPrev = prev.count > 600
                ? String(prev.prefix(600)) + "\n[...trích lược kế hoạch trước...]"
                : prev
            thesisContinuityBlock = isVi
                ? "\n[KẾ HOẠCH ĐÃ ĐƯA RA TRƯỚC ĐÓ]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n[ĐỐI CHIẾU]: Kiểm tra nến mới xem điều kiện kích hoạt đã diễn ra chưa, hay cấu trúc ban đầu đã bị vi phạm.\n"
                : "\n[PRIOR TRADING PLAN]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n[CONTINUITY]: Check if the entry trigger occurred or if the structure was invalidated.\n"
        }
        
        if isVi {
            return """
            [THÔNG TIN TÀI KHOẢN VÀ TRẠNG THÁI RỦI RO]:
            - Số dư thực tế: \(realBalStr) \(equityStr)
            - Trạng thái lệnh hôm nay: \(todayTradesDesc)
            - PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakStr)
            - \(dailyBufferStr)\(riskGuardrailWarning)
            \(contractSizingBlockVi)
            \(behavioralLeaksBlock)
            [CẤU TRÚC THỊ TRƯỜNG VÀ CHỈ BÁO KỸ THUẬT (EMA 21/50 & RSI 14)]:
            - Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)

            - Khung D1 (Macro Bias): Xu hướng [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              EMA D1: \(d1EMAStr)
              Mốc giá then chốt: Đỉnh PDH: \(d1PDH) | Đáy PDL: \(d1PDL) | ADR 14 ngày: \(d1ADR)

            - Khung H4 (Cấu trúc sóng và Cản TP/SL): Xu hướng [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              EMA H4: \(h4EMAStr)
              Mốc giá then chốt: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              3 nến H4 gần nhất:
            \(h4CandlesSummary)

            - Khung H1 (Thực thi và Động lượng): Xu hướng [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              EMA H1: \(h1EMAStr)
              RSI(14) Wilder: Mức hiện tại: \(rsiStr) | Signal: \(rsiSignalStr) | Phân kỳ: [\(divStr)]
              Vùng thanh khoản: BSL gần nhất: \(nearestBSLStr) | SSL gần nhất: \(nearestSSLStr)
              Quét thanh khoản SFP: \(sweepsStr)

            - HÀNH ĐỘNG GIÁ SỐNG (LIVE CANDLE PULSE):
            \(liveCandlePulse)

            - Chuỗi 24 nến H1 gần nhất (24 giờ giao dịch liên tục):
            \(h1CandlesSummary)

            - Chuỗi 16 nến M15 gần nhất (4 giờ vi mô thực thi):
            \(m15CandlesSummary)

            - Tin tức kinh tế: \(newsBlock)
            \(liveUpdateBlock)\(thesisContinuityBlock)
            VAI TRÒ VÀ NGUYÊN TẮC CỦA NHÀ GIAO DỊCH CHUYÊN NGHIỆP:
            Bạn là một Senior Institutional Portfolio Manager & Master Trader (Chuyên gia Phân tích & Quản lý Quỹ).
            Triết lý giao dịch:
            1. Giao dịch là bài toán bảo vệ vốn và chờ đợi lợi thế bất đối xứng. Thà đứng ngoài (FLAT) còn hơn vào một lệnh kém chất lượng hoặc R:R không đạt chuẩn.
            2. Luôn nhìn thị trường bằng con mắt hoài nghi, bóc tách bẫy thanh khoản của phe tổ chức.
            3. Phản biện toàn diện: Từ cấu trúc xu hướng, bẫy thanh khoản, đến tín hiệu kích hoạt nến sống và tỷ lệ R:R.

            NHIỆM VỤ PHÂN TÍCH VÀ LẬP KẾ HOẠCH GIAO DỊCH (4 PHẦN):

            ### 1. Cấu trúc D1
            - Xu hướng D1: Vị trí sóng, khoảng cách so với EMA(21) D1 và các mốc thanh khoản PDH (\(d1PDH)) / PDL (\(d1PDL)).
            - Đánh giá xung đột đa khung: D1 tăng nhưng H4 suy kiệt hoặc đang tiếp cận cản lớn thì tuyệt đối không đu đỉnh.

            ### 2. Cấu trúc H4 & Vùng Cung Cầu
            - Cấu trúc sóng H4: Đỉnh/đáy Swing, các vùng Cung/Cầu tổ chức then chốt (Order Block, Fair Value Gap) và bẫy thanh khoản phe nhỏ lẻ (Equal Highs/Lows).
            - Nếu giá đang ở vùng tranh chấp không có lợi thế cấu trúc: Nêu rõ không có cơ sở thiết lập cản tin cậy.

            ### 3. Tín hiệu vào lệnh H1/M15
            - Hành động giá nến H1/M15 thời gian thực: Thân nến, râu nến từ chối giá, tín hiệu quét thanh khoản (SFP) hoặc xác nhận cấu trúc (MSS/CHoCH).
            - Không đoán đỉnh đáy, không vào lệnh đón đầu khi nến chưa xác nhận. Nếu chưa có tín hiệu kích hoạt: Bắt buộc đứng ngoài (FLAT).

            ### 4. Kế hoạch giao dịch & Quản lý vốn
            - KẾT LUẬN RÕ RÀNG: [BUY (LONG) / SELL (SHORT) / FLAT (ĐỨNG NGOÀI)].
            - KHÓA CHẶT TỶ LỆ R:R: Tối thiểu 1:\(String(format: "%.1f", targetRR)).
              NGUYÊN TẮC TỪ CHỐI: Nếu khoảng cách từ Entry tới cản TP1 không đủ đạt tỷ lệ R:R 1:\(String(format: "%.1f", targetRR)): Bắt buộc kết luận FLAT (Đứng ngoài), từ chối vào lệnh kém chất lượng và giải thích rõ vùng giá nào mới đạt chuẩn.
            - NẾU KHUYẾN NGHỊ VÀO LỆNH (BUY/SELL):
              - Điểm vào tối ưu (Entry).
              - Cắt lỗ bắt buộc (Structural Invalidation SL): Mức giá SL cụ thể vi phạm cấu trúc.
              - Chốt lời (Targets): TP 1 và TP 2 tại cản H4.
              - Khối lượng (Volume): Tính chính xác số lot theo mức rủi ro \(numericRisk)% và số tiền rủi ro \(targetRiskDollarsStr).
              - Tỷ lệ R:R thực tế đạt được: [Ghi rõ số R:R, ví dụ 1:3.2].
            - NẾU KHUYẾN NGHỊ FLAT (ĐỨNG NGOÀI): Giải thích rõ điều kiện nến/cản gì cần kiên nhẫn chờ thêm.

            BẮT BUỘC KẾT THÚC BẰNG BẢNG THÔNG SỐ SETUP ĐÚNG ĐỊNH DẠNG SAU:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY hoặc SELL hoặc FLAT]
            - Balance: \(realBalStr)
            - Entry: [Mức giá hoặc vùng giá vào lệnh]
            - Stop loss: [Mức giá SL cụ thể]
            - Take profit 1: [Mức giá TP 1]
            - Take profit 2: [Mức giá TP 2 nếu có, nếu không ghi None]
            - R:R Ratio: [Tỷ lệ R:R, ví dụ 1:3.2]
            - Volume: [Khối lượng lot khuyến nghị tính theo số tiền rủi ro \(targetRiskDollarsStr), ví dụ 1.00 lot]
            - Date time: [Thời gian hiện tại]

            ```json
            {
              "direction": "[BUY hoặc SELL hoặc FLAT]",
              "entry": [mức giá entry dạng số hoặc null],
              "stopLoss": [mức giá sl dạng số hoặc null],
              "takeProfit1": [mức giá tp1 dạng số hoặc null],
              "takeProfit2": [mức giá tp2 dạng số hoặc null],
              "riskRewardRatio": "[ví dụ 1:3.2]",
              "volume": "[ví dụ 1.00 lot]"
            }
            ```

            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng của nhà giao dịch chuyên nghiệp]
            """
        } else {
            return """
            [ACCOUNT CONTEXT & RISK PROFILE]:
            - Authoritative Balance: \(realBalStr) \(equityStr)
            - Today's Trade Activity: \(todayTradesDesc)
            - Today's Net P&L: \(pnlTodayStr) | Current Streak: \(streakStr)
            - \(dailyBufferStr)\(riskGuardrailWarning)
            \(contractSizingBlockEn)
            \(behavioralLeaksBlock)
            [MARKET STRUCTURE & INDICATORS (EMA 21/50 & RSI 14)]:
            - Symbol: \(symbol) | Current Price: \(currentPrice)

            - D1 Macro Bias: Trend [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              EMA D1: \(d1EMAStr)
              Key Levels: PDH: \(d1PDH) | PDL: \(d1PDL) | 14-Day ADR: \(d1ADR)

            - H4 Swing Structure & Barriers: Trend [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              EMA H4: \(h4EMAStr)
              Key Swing Levels: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              Recent 3 H4 Bars:
            \(h4CandlesSummary)

            - H1 Execution & Momentum: Trend [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              EMA H1: \(h1EMAStr)
              Wilder RSI(14): Current: \(rsiStr) | Signal: \(rsiSignalStr) | Divergence: [\(divStr)]
              Liquidity: BSL: \(nearestBSLStr) | SSL: \(nearestSSLStr) | Sweeps: \(sweepsStr)

            - LIVE CANDLE PULSE:
            \(liveCandlePulse)

            - Recent 24 H1 Candles (24-Hour Continuous Market Cycle):
            \(h1CandlesSummary)

            - Recent 16 M15 Candles (4-Hour Micro Execution):
            \(m15CandlesSummary)

            - Catalyst News: \(newsBlock)
            \(liveUpdateBlock)\(thesisContinuityBlock)
            ROLE & INSTITUTIONAL MINDSET:
            You are a SENIOR INSTITUTIONAL PORTFOLIO MANAGER & MASTER TRADER.
            Core philosophy:
            1. Capital preservation and asymmetric edge come first. Standing aside (FLAT) is far better than taking low-quality or sub-3R trades.
            2. Maintain a skeptical institutional mindset, identifying retail traps set by Smart Money.
            3. Full-spectrum critique: from trend exhaustion and fake barriers to live tape reading and strict R:R.

            TASK: INSTITUTIONAL PRE-TRADE PLAN (4 SECTIONS):

            ### 1. D1 Structure
            - Evaluate current trend stage: Healthy expansion or overextended and due for exhaustion?
            - Identify multi-timeframe conflicts: Never buy into HTF resistance.
            - Key liquidity targets: Potential draw on liquidity at PDH (\(d1PDH)) or PDL (\(d1PDL)).

            ### 2. H4 Structure & Key Zones
            - Differentiate retail liquidity traps (Equal Highs/Lows) from genuine institutional Order Blocks and Fair Value Gaps.
            - Confirm key structural invalidation levels for Stop Loss placement.

            ### 3. H1/M15 Confirmation & Trigger
            - Read live unclosed candle pulse and wick dynamics. Look for displacement and SFP sweeps. Forbid front-running.
            - If no valid entry trigger is formed: Conclude FLAT (stand aside).

            ### 4. Trade Plan & Risk Management
            - Decisive Verdict: [BUY / SELL / FLAT].
            - Strict R:R Enforcement: Minimum 1:\(String(format: "%.1f", targetRR)). If setup space to TP1 cannot yield at least 1:\(String(format: "%.1f", targetRR)), conclude FLAT immediately.
            - If BUY/SELL: Specific Entry, Invalidation SL, TP1 & TP2, and calculated volume for \(numericRisk)% risk (\(targetRiskDollarsStr) budget).
            - If FLAT: State specific conditions to wait for.

            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY or SELL or FLAT]
            - Balance: \(realBalStr)
            - Entry: [Entry price]
            - Stop loss: [Specific SL price]
            - Take profit 1: [Specific TP1 price]
            - Take profit 2: [Specific TP2 price if any, otherwise None]
            - R:R Ratio: [Expected R:R ratio, e.g. 1:3.2]
            - Volume: [Recommended lots based on \(targetRiskDollarsStr) risk]
            - Date time: [Current date and time]

            ```json
            {
              "direction": "[BUY or SELL or FLAT]",
              "entry": [numeric entry price or null],
              "stopLoss": [numeric SL price or null],
              "takeProfit1": [numeric TP1 price or null],
              "takeProfit2": [numeric TP2 price or null],
              "riskRewardRatio": "[e.g. 1:3.2]",
              "volume": "[e.g. 1.00 lot]"
            }
            ```

            > [Single non-negotiable operational directive of an elite institutional trader]
            """
        }
    }

    // MARK: - Live Unclosed Candle Dynamics Helper
    public static func buildLiveUnclosedCandlePulse(bar: MarketBar?, isVi: Bool) -> String {
        guard let b = bar else {
            return isVi ? "Chưa có dữ liệu nến sống" : "No live candle data"
        }
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
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
            lines.append("  - \(label): O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | C: \(fmt(b.close))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 24-Candle H1 Execution Series Helper (OHLC + EMA 21/50 + Wilder RSI 14)
    public static func buildH1CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 24,
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
            let timeLabel = offset == 0 ? (isVi ? "[Nến sống]" : "[Live]") : "[-t-\(offset)h]"
            
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
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close)) | EMA21: \(e21Str) | EMA50: \(e50Str) | RSI: \(rsiVal)"
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
            let timeLabel = offset == 0 ? (isVi ? "[Nến sống]" : "[Live]") : "[-t-\(offset * 15)m]"
            let num = lines.count + 1
            let numStr = num < 10 ? "0\(num)" : "\(num)"
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close))"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
