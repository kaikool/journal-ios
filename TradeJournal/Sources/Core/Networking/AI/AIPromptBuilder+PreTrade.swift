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
        
        let execBars = !h1Bars.isEmpty ? h1Bars : m15Bars
        
        let currentPrice: String = {
            if let last = execBars.last ?? h4Bars.last ?? d1Bars.last {
                return Formatters.price(last.close, symbol: symbol)
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
            d1PDH = Formatters.price(prevDay.high, symbol: symbol)
            d1PDL = Formatters.price(prevDay.low, symbol: symbol)
            d1PDC = Formatters.price(prevDay.close, symbol: symbol)
            
            let lookback = min(14, d1Bars.count - 1)
            let ranges = d1Bars.suffix(lookback).map { $0.high - $0.low }
            let avgRange = ranges.reduce(Decimal.zero, +) / Decimal(lookback)
            d1ADR = Formatters.price(avgRange, symbol: symbol)
        } else {
            d1PDH = "N/A"
            d1PDL = "N/A"
            d1PDC = "N/A"
            d1ADR = "N/A"
        }
        
        // Key H4 High & Low Levels (Direct Price Range Scanning)
        let h4SwingHighStr: String = {
            if let maxBar = h4Bars.suffix(24).max(by: { $0.high < $1.high }) {
                return Formatters.price(maxBar.high, symbol: symbol)
            }
            return "N/A"
        }()
        let h4SwingLowStr: String = {
            if let minBar = h4Bars.suffix(24).min(by: { $0.low < $1.low }) {
                return Formatters.price(minBar.low, symbol: symbol)
            }
            return "N/A"
        }()
        
        // 3a. Recent H4 Candles (Last 3 bars OHLC)
        let h4CandlesSummary = buildH4CandleSummary(bars: h4Bars, count: 3, isVi: isVi)
        
        // 3b. 24-Candle H1 Execution Series (OHLC + Wilder RSI 14)
        let h1CandlesSummary = buildH1CandleSeriesSummary(bars: execBars, count: 24, symbol: symbol, isVi: isVi)
        
        // 3c. 16-Candle M15 Micro-Execution Series (OHLC)
        let m15CandlesSummary = buildM15CandleSeriesSummary(bars: m15Bars, count: 16, symbol: symbol, isVi: isVi)
        
        // 3d. Live Unclosed Candle Dynamics (Current Price Action Pulse)
        let liveCandlePulse = buildLiveUnclosedCandlePulse(bar: execBars.last ?? m15Bars.last, isVi: isVi)
        
        // 4. H1 Momentum & 3-Line RSI System (Wilder RSI 14 / EMA 9 / WMA 45)
        let momentumWindow = MomentumEngine.computeWindow(bars: execBars, windowSize: 15)
        let rsiVal = momentumWindow.currentRSI.map { ($0 as NSDecimalNumber).doubleValue }
        let emaVal = momentumWindow.currentEMA9.map { ($0 as NSDecimalNumber).doubleValue }
        let wmaVal = momentumWindow.currentWMA45.map { ($0 as NSDecimalNumber).doubleValue }
        
        let rValStr = rsiVal.map { String(format: "%.1f", $0) } ?? "N/A"
        let eValStr = emaVal.map { String(format: "%.1f", $0) } ?? "N/A"
        let wValStr = wmaVal.map { String(format: "%.1f", $0) } ?? "N/A"
        let alignmentDesc = isVi ? momentumWindow.alignmentVi : momentumWindow.alignmentEn
        let emaVsWmaDesc = isVi ? momentumWindow.emaVsWmaVi : momentumWindow.emaVsWmaEn
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
                    ? "\n[CẢNH BÁO HẠN MỨC LỖ NGÀY]: Mức lỗ hôm nay đã chạm ngưỡng cho phép (\(String(format: "%.1f", todayLossPct))% >= \(String(format: "%.1f", maxDailyLossPct))%). AI CẢNH BÁO RỦI RO CAO: Khuyến nghị cân nhắc dừng giao dịch hoặc chỉ đi volume tối thiểu (giảm 50% lot) để bảo vệ tài khoản; quyền quyết định vào lệnh thuộc về trader.\n"
                    : "\n[DAILY LOSS WARNING]: Daily loss has reached limit (\(String(format: "%.1f", todayLossPct))% >= \(String(format: "%.1f", maxDailyLossPct))%). HIGH RISK CAUTION: Recommend pausing or strictly reducing volume by 50% to preserve capital; decision remains with the trader.\n"
            } else if streak <= -2 {
                return isVi
                    ? "\n[LƯU Ý TÂM LÝ & QUẢN TRỊ RỦI RO]: Trader đang có chuỗi thua \(abs(streak)) lệnh liên tiếp hôm nay. AI cảnh báo tâm lý và khuyến nghị giảm khối lượng giao dịch. Nếu thị trường có setup đẹp thì đưa ra kịch bản rõ ràng kèm mức rủi ro kiểm soát chặt chẽ.\n"
                    : "\n[PSYCHOLOGY & RISK CAUTION]: Trader is on a \(abs(streak))-loss streak. AI warns of psychological bias and recommends reduced volume. If a high-probability setup exists, provide clear parameters with strictly controlled risk.\n"
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
        - Mục tiêu Tỷ lệ Risk/Reward tham chiếu: 1:\(String(format: "%.1f", targetRR)) (Cấu hình theo hồ sơ trader)
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
        - Target Risk/Reward Ratio Benchmark: 1:\(String(format: "%.1f", targetRR)) (Configured in trader profile)
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
        
        let footprintBlockVi: String = {
            if let snap = marketSnapshot, !snap.keyLevels.isEmpty {
                let lvls = snap.keyLevels.prefix(6).map { "\($0.label): \(Formatters.price($0.price))" }.joined(separator: " | ")
                let pats = snap.detectedPatterns.isEmpty ? "Không có mẫu nến đặc biệt gần cản" : snap.detectedPatterns.prefix(3).map { $0.summary }.joined(separator: " • ")
                let mig = snap.valueMigration ?? "Cân bằng / Dao động"
                return """
                  Mốc cản then chốt: \(lvls)
                  Xu hướng giá trị phiên (Value Migration): [\(mig)]
                  Hành vi nến Price Action tại cản: \(pats)
                """
            }
            return "  Mốc cản then chốt: Đang cập nhật từ Footprint Engine"
        }()
        
        let footprintBlockEn: String = {
            if let snap = marketSnapshot, !snap.keyLevels.isEmpty {
                let lvls = snap.keyLevels.prefix(6).map { "\($0.label): \(Formatters.price($0.price))" }.joined(separator: " | ")
                let pats = snap.detectedPatterns.isEmpty ? "None near key barriers" : snap.detectedPatterns.prefix(3).map { $0.summary }.joined(separator: " • ")
                let mig = snap.valueMigration ?? "Balanced / Ranging"
                return """
                  Key Levels (POC/VA): \(lvls)
                  Value Migration: [\(mig)]
                  Candlestick Price Action at Key Levels: \(pats)
                """
            }
            return "  Key Levels: Updating from Footprint Engine"
        }()
        
        if isVi {
            return """
            [THÔNG TIN TÀI KHOẢN VÀ TRẠNG THÁI RỦI RO]:
            - Số dư thực tế: \(realBalStr) \(equityStr)
            - Trạng thái lệnh hôm nay: \(todayTradesDesc)
            - PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakStr)
            - \(dailyBufferStr)\(riskGuardrailWarning)
            \(contractSizingBlockVi)
            \(behavioralLeaksBlock)
            [CẤU TRÚC GIÁ THỰC TẾ & HỆ THỐNG ĐỘNG LƯỢNG 3 ĐƯỜNG RSI]:
            - Cặp tiền: \(symbol) | Thị giá hiện tại: \(currentPrice)

            - Mốc Giá trị Then chốt Footprint (Session POCs & Naked POCs):
            \(footprintBlockVi)

            - Khung D1 (Mốc then chốt):
              Đỉnh PDH: \(d1PDH) | Đáy PDL: \(d1PDL) | Giá đóng PDC: \(d1PDC) | ADR 14 ngày: \(d1ADR)

            - Khung H4 (Biên độ sóng & Cản TP/SL):
              Đỉnh cao nhất (24 bar): \(h4SwingHighStr) | Đáy thấp nhất (24 bar): \(h4SwingLowStr)
              3 nến H4 gần nhất:
            \(h4CandlesSummary)

            - Khung H1 (Thực thi và Động lượng):
              Hệ thống 3 đường Động lượng RSI (Wilder RSI 14 / EMA 9 / WMA 45):
                • Giá trị: RSI(14) = \(rValStr) | EMA(9) = \(eValStr) | WMA(45) = \(wValStr)
                • Cấu trúc sắp xếp: \(alignmentDesc)
                • Nền trung hạn (EMA 9 vs WMA 45): \(emaVsWmaDesc)
                • Tín hiệu phân kỳ: [\(divStr)]
              Mốc tham chiếu then chốt: Đỉnh H4: \(h4SwingHighStr) | Đáy H4: \(h4SwingLowStr) | PDH: \(d1PDH) | PDL: \(d1PDL)

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
            TRIẾT LÝ GIAO DỊCH VÀ NGUYÊN TẮC HÀNH ĐỘNG QUYẾT ĐOÁN:
            1. ƯU TIÊN ĐƯA RA KẾ HOẠCH GIAO DỊCH CỤ THỂ (BUY HOẶC SELL):
               - Thị trường dao động giữa các vùng đỉnh đáy then chốt (Swing High / Swing Low, PDH / PDL). Việc giá nằm giữa hai mốc là trạng thái bình thường; tuyệt đối không dùng đó làm lý do để đứng ngoài (FLAT).
               - Nhà giao dịch chuyên nghiệp tìm kiếm điểm vào lệnh tối ưu tại các nhịp kiểm tra lại (retest) vùng cản cấu trúc bị phá vỡ, hoặc giao dịch theo đà bứt phá cấu trúc (Break of Structure).
            2. ĐỊNH HƯỚNG THEO CẤU TRÚC THỊ TRƯỜNG & HÀNH ĐỘNG GIÁ:
               - KỊCH BẢN BUY: Khi D1/H4 cấu trúc TĂNG (Đỉnh đáy nâng dần hoặc bứt phá Swing High) và H1/M15 có nến từ chối giảm (rút râu dưới, pinbar, nhấn chìm tăng): Chủ động lập kế hoạch BUY với Entry tại vùng hỗ trợ / retest cấu trúc, SL dưới đáy gần nhất, TP tại Swing High (\(h4SwingHighStr)) hoặc PDH (\(d1PDH)).
               - KỊCH BẢN SELL: Khi D1/H4 cấu trúc GIẢM (Đỉnh đáy hạ dần hoặc bứt phá Swing Low) và H1/M15 có nến từ chối tăng (rút râu trên, pinbar, nhấn chìm giảm): Chủ động lập kế hoạch SELL với Entry tại vùng kháng cự / retest cấu trúc, SL trên đỉnh gần nhất, TP tại Swing Low (\(h4SwingLowStr)) hoặc PDL (\(d1PDL)).
            3. NGUYÊN TẮC HỆ THỐNG 3 ĐƯỜNG ĐỘNG LƯỢNG RSI (RSI 14 / EMA 9 / WMA 45):
               - TĂNG ÁP ĐẢO (BULLISH ALIGNMENT): Khi RSI > EMA 9 > WMA 45 -> Động lượng phe mua thống trị. Canh BUY thuận đà hoặc khi RSI bật tăng từ EMA 9 / WMA 45.
               - GIẢM ÁP ĐẢO (BEARISH ALIGNMENT): Khi RSI < EMA 9 < WMA 45 -> Động lượng phe bán áp đảo. Canh SELL thuận đà hoặc khi RSI quay đầu giảm từ EMA 9 / WMA 45.
               - SÓNG HỒI KỸ THUẬT (COUNTER-TREND):
                 • Nếu RSI > EMA 9 nhưng DƯỚI WMA 45: Nhịp hồi tăng ngắn hạn trong xu hướng giảm lớn (WMA 45 là cản động lượng). Không mua đuổi, canh SELL tại cản kháng cự cấu trúc.
                 • Nếu RSI < EMA 9 nhưng TRÊN WMA 45: Nhịp điều chỉnh giảm lành mạnh trong xu hướng tăng lớn (WMA 45 là hỗ trợ động lượng). Canh BUY khi RSI cắt ngược lên EMA 9.
               - CO THẮT NÉN ĐỘNG LƯỢNG (SQUEEZE): Khi EMA 9 và WMA 45 hội tụ sát nhau (chênh lệch < 1.0 điểm) -> Động lượng nén chặt chuẩn bị bùng nổ sóng mới theo hướng phá vỡ cấu trúc.
            4. QUY ĐỊNH VỀ KẾT LUẬN FLAT (ĐỨNG NGOÀI):
               - CHỈ ĐƯỢC KẾT LUẬN FLAT trong trường hợp duy nhất: Thị trường hoàn toàn không có biên độ biến động (thị trường ngày lễ hoặc biên độ cả ngày nhỏ hơn 15% ADR) hoặc sắp công bố tin tức cực kỳ nguy hiểm trong vòng 15 phút.
               - Trong mọi điều kiện thị trường có sóng bình thường: BẮT BUỘC ĐƯA RA HƯỚNG LỆNH CỤ THỂ (BUY hoặc SELL)!

            NHIỆM VỤ PHÂN TÍCH VÀ LẬP KẾ HOẠCH GIAO DỊCH (4 PHẦN):

            ### 1. Cấu trúc D1
            - Xu hướng D1: Cấu trúc đỉnh đáy D1, biên độ dao động PDH (\(d1PDH)) / PDL (\(d1PDL)) và mức ADR (\(d1ADR)).
            - Xác định phe chủ đạo đang kiểm soát thị trường.

            ### 2. Cấu trúc H4 & Mức Cản Then Chốt
            - Cấu trúc sóng H4: Đỉnh Swing High (\(h4SwingHighStr)) và Đáy Swing Low (\(h4SwingLowStr)).
            - Trạng thái giá: Đang bám sóng tiếp diễn, đang trong nhịp hồi điều chỉnh (pullback), hay đang test cản.
            - Xác định các vùng cản chốt lời tiềm năng theo cấu trúc.

            ### 3. Tín hiệu vào lệnh H1/M15
            - Hành động giá nến H1/M15: Nến từ chối tại hỗ trợ/kháng cự, nến nhấn chìm, hoặc lực đẩy phá vỡ.
            - Động lượng 3 đường RSI (14, EMA 9, WMA 45): Đang ở trạng thái Tăng áp đảo, Giảm áp đảo, Sóng hồi kỹ thuật, hay Squeeze co thắt; có phân kỳ đảo chiều không.
            - Xác định thời điểm và vùng kích hoạt lệnh tối ưu.

            ### 4. Kế hoạch giao dịch & Quản trị rủi ro
            - Hướng lệnh: [BUY hoặc SELL] (Chỉ chọn FLAT nếu thị trường chết thanh khoản < 15% ADR)
            - Điểm vào tối ưu (Entry): [Mức giá cụ thể]
            - Dừng lỗ (Stop Loss): [Mức giá cụ thể]
            - Chốt lời (Take Profit): TP 1 tại [Mức giá] | TP 2 tại [Mức giá nếu có]
            - Khối lượng (Volume): [Khối lượng lot cụ thể, ví dụ: 0.50 lot]
            - Tỷ lệ R:R: [1:\(String(format: "%.1f", targetRR))]
            - Quản lý lệnh: [1-2 câu ngắn gọn về dời SL bảo vệ vị thế khi nến xác nhận]

            QUY TẮC BẮT BUỘC KHI TRÌNH BÀY PHẦN 4 (NGHIÊM NGẶT):
            Chỉ xuất các mốc giá và thông số rõ ràng, dứt khoát, chuẩn phong cách quỹ tài chính. TUYỆT ĐỐI KHÔNG viết kèm các câu giải thích rườm rà trong ngoặc đơn như "(tính toán chính xác dựa trên...)", "(bảo vệ phía trên...)", "(theo công thức...)". Mọi phân tích giải thích đã có ở mục 1, 2, 3; phần 4 là bảng lệnh thực thi trực tiếp, đơn giản và sạch sẽ.

            BẮT BUỘC KẾT THÚC BẰNG BẢNG THÔNG SỐ SETUP ĐÚNG ĐỊNH DẠNG SAU:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY hoặc SELL hoặc FLAT]
            - Balance: \(realBalStr)
            - Entry: [Mức giá hoặc vùng giá vào lệnh]
            - Stop loss: [Mức giá SL cụ thể]
            - Take profit 1: [Mức giá TP 1]
            - Take profit 2: [Mức giá TP 2 nếu có, nếu không ghi None]
            - R:R Ratio: 1:\(String(format: "%.1f", targetRR))
            - Volume: [Khối lượng lot khuyến nghị tính theo số tiền rủi ro \(targetRiskDollarsStr), ví dụ 1.00 lot]
            - Date time: [Thời gian hiện tại]

            ```json
            {
              "direction": "[BUY hoặc SELL hoặc FLAT]",
              "entry": [mức giá entry dạng số hoặc null],
              "stopLoss": [mức giá sl dạng số hoặc null],
              "takeProfit1": [mức giá tp1 dạng số hoặc null],
              "takeProfit2": [mức giá tp2 dạng số hoặc null],
              "riskRewardRatio": "1:\(String(format: "%.1f", targetRR))",
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
            [FACTUAL MARKET STRUCTURE & 3-LINE RSI MOMENTUM]:
            - Symbol: \(symbol) | Current Price: \(currentPrice)

            - Footprint Key Levels (Session POCs & Naked POCs):
            \(footprintBlockEn)

            - D1 Key Reference Levels:
              PDH: \(d1PDH) | PDL: \(d1PDL) | PDC: \(d1PDC) | 14-Day ADR: \(d1ADR)

            - H4 24-Bar Range & Target Barriers:
              Highest High: \(h4SwingHighStr) | Lowest Low: \(h4SwingLowStr)
              Recent 3 H4 Bars:
            \(h4CandlesSummary)

            - H1 Execution & Momentum:
              3-Line RSI Momentum System (Wilder RSI 14 / EMA 9 / WMA 45):
                • Values: RSI(14) = \(rValStr) | EMA(9) = \(eValStr) | WMA(45) = \(wValStr)
                • Alignment: \(alignmentDesc)
                • Baseline (EMA 9 vs WMA 45): \(emaVsWmaDesc)
                • Divergence: [\(divStr)]
              Key Reference Levels: H4 High: \(h4SwingHighStr) | H4 Low: \(h4SwingLowStr) | PDH: \(d1PDH) | PDL: \(d1PDL)

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
            DECISIVE ACTION PHILOSOPHY:
            1. MANDATORY DECISIVE BIAS (BUY OR SELL):
               - Markets naturally oscillate between daily and weekly highs and lows. The fact that price is between Swing High and Swing Low is entirely normal; never use that to excuse standing aside (FLAT).
               - Elite traders hunt for optimal entries on retests of broken structural levels or trend breakouts.
            2. MARKET STRUCTURE & PRICE ACTION ALIGNMENT:
               - BUY BIAS: When D1/H4 structure is BULLISH (Higher Highs / Higher Lows or breaking Swing High) and H1/M15 prints bullish rejection wicks, pinbars, or engulfing candles at support: Formulate an actionable BUY setup with Entry at retest/support, SL below structural swing low, and TP at Swing High (\(h4SwingHighStr)) or PDH (\(d1PDH)).
               - SELL BIAS: When D1/H4 structure is BEARISH (Lower Highs / Lower Lows or breaking Swing Low) and H1/M15 prints bearish rejection wicks, pinbars, or engulfing candles at resistance: Formulate an actionable SELL setup with Entry at retest/resistance, SL above structural swing high, and TP at Swing Low (\(h4SwingLowStr)) or PDL (\(d1PDL)).
            3. 3-LINE RSI MOMENTUM SYSTEM (WILDER RSI 14 / EMA 9 / WMA 45):
               - STRONG BULLISH: RSI > EMA 9 > WMA 45 -> Buyers dominate. Buy in trend direction or when RSI bounces off EMA 9 / WMA 45.
               - STRONG BEARISH: RSI < EMA 9 < WMA 45 -> Sellers dominate. Sell in trend direction or when RSI rolls over from EMA 9 / WMA 45.
               - COUNTER-TREND REBOUND: RSI above EMA 9 but below WMA 45 -> Short-term counter-trend retracement in macro downtrend. Do not chase; sell near structural resistance.
               - SQUEEZE: EMA 9 & WMA 45 converging (gap < 1.0 pt) -> Momentum compression preceding structural expansion.
            4. STRICT RULES ON "FLAT":
               - FLAT is ONLY permitted if the market is completely dead (< 15% of ADR) or major high-impact news is due within 15 minutes. In all normal conditions, an actionable BUY or SELL plan is MANDATORY.

            TASK: INSTITUTIONAL PRE-TRADE PLAN (4 SECTIONS):

            ### 1. D1 Structure
            - Evaluate macro structure, key PDH (\(d1PDH)) / PDL (\(d1PDL)) boundaries, and ADR (\(d1ADR)).

            ### 2. H4 Structure & Key Barriers
            - Map H4 swing high (\(h4SwingHighStr)) and swing low (\(h4SwingLowStr)).
            - Identify pullback retest zones and structural targets.

            ### 3. H1/M15 Confirmation & Trigger
            - Read live candle pulse, price action rejection wicks at support/resistance, and 3-line RSI momentum state (RSI 14 / EMA 9 / WMA 45).

            ### 4. Trade Plan & Risk Management
            - Verdict: [BUY or SELL] (Only FLAT if dead volatility < 15% ADR)
            - Entry: [Precise price]
            - Stop Loss: [Precise SL price]
            - Take Profit: TP 1 at [Price] | TP 2 at [Price if any]
            - Volume: [Lot size, e.g. 0.50 lot]
            - R:R Ratio: [1:\(String(format: "%.1f", targetRR))]
            - Trade Management: [1-2 concise sentences on trailing SL]

            STRICT FORMATTING RULE FOR SECTION 4:
            State clear, exact numbers and directives. STRICTLY PROHIBIT verbose parenthetical justifications like "(calculated based on...)", "(protecting above...)", or "(according to profile...)". Keep it clean, direct, and institutional.

            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY or SELL or FLAT]
            - Balance: \(realBalStr)
            - Entry: [Entry price]
            - Stop loss: [Specific SL price]
            - Take profit 1: [Specific TP1 price]
            - Take profit 2: [Specific TP2 price if any, otherwise None]
            - R:R Ratio: 1:\(String(format: "%.1f", targetRR))
            - Volume: [Recommended lots based on \(targetRiskDollarsStr) risk]
            - Date time: [Current date and time]

            ```json
            {
              "direction": "[BUY or SELL or FLAT]",
              "entry": [numeric entry price or null],
              "stopLoss": [numeric SL price or null],
              "takeProfit1": [numeric TP1 price or null],
              "takeProfit2": [numeric TP2 price or null],
              "riskRewardRatio": "1:\(String(format: "%.1f", targetRR))",
              "volume": "[e.g. 1.00 lot]"
            }
            ```

            > [Single non-negotiable operational directive of an elite institutional trader]
            """
        }
    }
}

