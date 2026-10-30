import Foundation

// MARK: - Single Trade Audit Prompt Builder Extension
extension AIPromptBuilder {
    
    /// Generates objective forensic critique prompt for open and closed positions
    public static func buildTradeCoachingPrompt(
        trade: Trade,
        isVi: Bool,
        recentCandlesSummary: String?,
        bars: [MarketBar]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        displayTimeZone: String = "UTC",
        linkedPreTradePlan: AdvisorCommitmentRecord? = nil,
        excursion: TradeExcursion? = nil
    ) -> String {
        let isOpen = trade.status == .open || trade.closedAt == nil
        let pnlVal = NSDecimalNumber(decimal: trade.netPnl).doubleValue
        let pnlStr = (trade.netPnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
        let volumeStr = String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)
        let entryStr = Formatters.price(trade.avgEntry, symbol: trade.symbol)
        let latestBar = bars?.last
        let curLivePrice = latestBar?.close
        let curLivePriceStr = curLivePrice.map { Formatters.price($0, symbol: trade.symbol) }
        let exitStr = trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? (isOpen ? (curLivePriceStr ?? "Live / Market") : "N/A")
        let slStr = trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? (isVi ? "Chưa cài SL" : "Not Set")
        let tpStr = trade.profitTarget.map { Formatters.price($0, symbol: trade.symbol) } ?? (isVi ? "Chưa cài TP" : "Not Set")
        let mistakes = trade.mistakes.isEmpty ? (isVi ? "Không ghi nhận" : "None") : trade.mistakes.joined(separator: ", ")
        let notes = (trade.notes?.isEmpty ?? true) ? (isVi ? "Không có ghi chú" : "None") : trade.notes!
        
        let liveDeltaInfo: String = {
            guard isOpen, let cp = curLivePrice else { return "" }
            let spec = AssetContractEngine.spec(for: trade.symbol)
            let pipUnit = spec.pipSize > 0 ? spec.pipSize : Decimal(string: "0.0001")!
            let priceDelta = (trade.direction == .short) ? (trade.avgEntry - cp) : (cp - trade.avgEntry)
            let pips = (priceDelta / pipUnit as NSDecimalNumber).doubleValue
            let pipsStr = String(format: "%@%.1f pips", pips >= 0 ? "+" : "", pips)
            
            var res = isVi ? " (Biên độ: \(pipsStr)" : " (Delta: \(pipsStr)"
            if let sl = trade.stopLoss {
                let distSl = (abs(cp - sl) / pipUnit as NSDecimalNumber).doubleValue
                res += isVi ? " | Cách SL: \(String(format: "%.1f", distSl)) pips" : " | Dist to SL: \(String(format: "%.1f", distSl)) pips"
            }
            if let tp = trade.profitTarget {
                let distTp = (abs(tp - cp) / pipUnit as NSDecimalNumber).doubleValue
                res += isVi ? " | Cách TP: \(String(format: "%.1f", distTp)) pips" : " | Dist to TP: \(String(format: "%.1f", distTp)) pips"
            }
            res += ")"
            return res
        }()
        
        let displayTz = TimeZone(identifier: displayTimeZone) ?? .current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.timeZone = displayTz
        let openedAtStr = df.string(from: trade.openedAt)
        let closedAtStr = trade.closedAt.map { df.string(from: $0) } ?? (isVi ? "Đang mở" : "Open")
        
        let preTrade = linkedPreTradePlan ?? AIAdvisorMemoryEngine.shared.getCommitmentForTrade(trade) ?? AIAdvisorMemoryEngine.shared.getLatestCommitment(for: trade.symbol, beforeOrNear: trade.openedAt)
        var preTradeBlock = ""
        if let pt = preTrade {
            let ptTimeStr = df.string(from: pt.timestamp)
            if isVi {
                preTradeBlock = """
                
                [LỊCH SỬ KẾ HOẠCH PRE-TRADE ĐÃ TƯ VẤN (PRE-TRADE COMMITMENT)]:
                • Thời điểm bạn tư vấn: \(ptTimeStr)
                • Kế hoạch bạn đã khuyến nghị: \(pt.bias) tại vùng [\(pt.plannedEntry ?? "Thị trường")], Cắt lỗ SL: [\(pt.invalidationSL ?? "Theo cấu trúc")], TP: [\(pt.targetTP ?? "Vùng thanh khoản")]
                • Tóm tắt chỉ đạo của bạn: "\(pt.thesisSummary)"
                """
            } else {
                preTradeBlock = """
                
                [YOUR PREVIOUS PRE-TRADE ADVISORY COMMITMENT]:
                • Time of Analysis: \(ptTimeStr)
                • Your Recommended Setup: \(pt.bias) at [\(pt.plannedEntry ?? "Market")], SL: [\(pt.invalidationSL ?? "Structural")], TP: [\(pt.targetTP ?? "Liquidity")]
                • Directive Summary: "\(pt.thesisSummary)"
                """
            }
        }
        
        // Pre-Entry Price Trajectory & Confirmation Entry Audit
        let trajectoryBlock = computePreEntryTrajectory(
            trade: trade,
            plannedZone: preTrade?.plannedEntry,
            bars: bars,
            displayTimeZone: displayTz,
            isVi: isVi
        )
        
        // Candlestick Tape Markdown Table (Optimized to 5 key bars surrounding execution to honor strict 6k token budget)
        let candlesTableBlock: String = {
            guard let b = bars, !b.isEmpty else { return "" }
            let table = CandleTapeFormatter.formatCandlesTable(
                bars: b,
                count: 5,
                symbol: trade.symbol,
                displayTimeZone: displayTz
            )
            return isVi ? """
            
            [BẢNG BĂNG GIÁ NẾN M15 QUANH ĐIỂM VÀO LỆNH (5 NẾN QUAN TRỌNG)]:
            \(table)
            """ : """
            
            [M15 CANDLESTICK TAPE SURROUNDING ENTRY (LAST 5 BARS)]:
            \(table)
            """
        }()
        
        // Technical Momentum Table (Wilder RSI 14 / EMA 9 / WMA 45 across 5-candle window)
        let momentumBlock: String = {
            guard let b = bars, !b.isEmpty else { return "" }
            let window = MomentumEngine.computeWindow(bars: b, windowSize: 5)
            let formatted = MomentumEngine.formatMomentumTable(
                window: window,
                displayTimeZone: displayTz,
                isVi: isVi
            )
            return formatted.isEmpty ? "" : "\n\n" + formatted
        }()
        
        let lessonsBlock = AIAdvisorMemoryEngine.shared.formatMemoriesForPrompt(
            symbol: trade.symbol,
            isVi: isVi,
            maxItems: 4
        )
        
        let complianceBlock = AIAdvisorMemoryEngine.shared.formatComplianceBlock(
            symbol: trade.symbol,
            isVi: isVi
        )
        
        // Maximum Adverse / Favorable Excursions (MAE / MFE)
        let excursionBlock: String = {
            let est: ExcursionEstimate? = {
                if let e = excursion?.estimate { return e }
                if let b = bars, !b.isEmpty, trade.avgEntry > 0 {
                    return TradeReplayEngine.estimateExcursions(trade: trade, fills: [], bars: b)
                }
                return nil
            }()
            guard let e = est, (e.mae != nil || e.mfe != nil) else { return "" }
            
            let pnlFmt = { (val: Decimal?) -> String in
                guard let v = val else { return "N/A" }
                let num = NSDecimalNumber(decimal: v).doubleValue
                return (v >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(num))
            }
            let maeStr = pnlFmt(e.mae)
            let mfeStr = pnlFmt(e.mfe)
            let maePts = e.maePoints.map { Formatters.points($0) } ?? "N/A"
            let mfePts = e.mfePoints.map { Formatters.points($0) } ?? "N/A"
            
            if isVi {
                return "\n- Mức sụt giảm tối đa khi giữ lệnh (MAE Drawdown): \(maeStr) (\(maePts) pts)\n- Lợi nhuận cực đại tiềm năng khi giữ lệnh (MFE Runup): \(mfeStr) (\(mfePts) pts)"
            } else {
                return "\n- Max Adverse Excursion (MAE Drawdown): \(maeStr) (\(maePts) pts)\n- Max Favorable Excursion (MFE Runup): \(mfeStr) (\(mfePts) pts)"
            }
        }()
        
        let durationStr: String = {
            let diff: TimeInterval
            if let closed = trade.closedAt {
                diff = closed.timeIntervalSince(trade.openedAt)
            } else {
                diff = Date().timeIntervalSince(trade.openedAt)
            }
            if diff <= 0 { return "< 1m" }
            let mins = Int(diff / 60)
            let hours = mins / 60
            let days = hours / 24
            if days > 0 {
                let remHours = hours % 24
                return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
            } else if hours > 0 {
                let remMins = mins % 60
                return remMins > 0 ? "\(hours)h \(remMins)m" : "\(hours)h"
            } else {
                return "\(max(1, mins))m"
            }
        }()
        
        let risk1RStr: String = {
            guard let sl = trade.stopLoss else { return isVi ? "Chưa rõ (Không cài SL)" : "Undefined (No SL)" }
            let dist = abs(trade.avgEntry - sl)
            let mult = trade.contractMultiplier ?? Decimal(1)
            let riskUsd = dist * trade.quantity * mult
            let riskUsdVal = NSDecimalNumber(decimal: riskUsd).doubleValue
            if riskUsdVal > 0 {
                return "$\(String(format: "%.2f", riskUsdVal))"
            }
            return isVi ? "Không đáng kể" : "Negligible"
        }()
        
        let realizedRStr: String = {
            guard let sl = trade.stopLoss else { return "N/A" }
            let dist = abs(trade.avgEntry - sl)
            let mult = trade.contractMultiplier ?? Decimal(1)
            let riskUsd = dist * trade.quantity * mult
            if riskUsd > 0 {
                let r = trade.netPnl / riskUsd
                let rVal = NSDecimalNumber(decimal: r).doubleValue
                return String(format: "%@%.2fR", rVal >= 0 ? "+" : "", rVal)
            }
            return "N/A"
        }()
        
        let feesVal = NSDecimalNumber(decimal: trade.fees).doubleValue
        let swapVal = NSDecimalNumber(decimal: trade.swap ?? Decimal.zero).doubleValue
        let feesStr = "$\(String(format: "%.2f", feesVal))"
        let swapStr = "$\(String(format: "%.2f", swapVal))"
        
        let isShort = trade.direction == .short
        let directionStrVi = isShort ? "SELL / SHORT (BÁN KHỐNG - Kỳ vọng giá GIẢM)" : "BUY / LONG (MUA - Kỳ vọng giá TĂNG)"
        let directionStrEn = isShort ? "SELL / SHORT (Short position - Expects price to FALL)" : "BUY / LONG (Long position - Expects price to RISE)"
        
        let directionWarningVi = isShort
            ? "⚠️ CẢNH BÁO QUAN TRỌNG VỀ CHIỀU LỆNH: Đây là lệnh BÁN (SELL / SHORT). Lợi nhuận sinh ra khi giá GIẢM (Giá hiện tại hoặc Giá ra < Giá vào = CÓ LÃI). Take Profit (TP) phải nằm DƯỚI giá vào, Stop Loss (SL) phải nằm TRÊN giá vào. Tuyệt đối KHÔNG ĐƯỢC phân tích nhầm thành lệnh MUA (BUY)."
            : "⚠️ CẢNH BÁO QUAN TRỌNG VỀ CHIỀU LỆNH: Đây là lệnh MUA (BUY / LONG). Lợi nhuận sinh ra khi giá TĂNG (Giá hiện tại hoặc Giá ra > Giá vào = CÓ LÃI). Take Profit (TP) nằm TRÊN giá vào, Stop Loss (SL) nằm DƯỚI giá vào."
        
        let directionWarningEn = isShort
            ? "CRITICAL DIRECTION DIRECTIVE: THIS IS A SHORT / SELL TRADE. Profit occurs strictly when the price DROPS (Current/Exit price < Entry price = Profit). Take Profit (TP) is BELOW Entry; Stop Loss (SL) is ABOVE Entry. NEVER evaluate this as a BUY trade."
            : "CRITICAL DIRECTION DIRECTIVE: THIS IS A LONG / BUY TRADE. Profit occurs strictly when the price RISES. Take Profit (TP) is ABOVE Entry; Stop Loss (SL) is BELOW Entry."
        
        let candleInfo = recentCandlesSummary ?? (isVi ? "Không có chuỗi nến số hóa (Dựa vào thông số lệnh và ảnh biểu đồ đính kèm nếu có)." : "No numeric candle feed (Rely on trade metrics and attached chart image if present).")
        
        let tradesToday = sessionSummary?.totalTradesToday ?? 0
        let winsToday = sessionSummary?.winsToday ?? 0
        let lossesToday = sessionSummary?.lossesToday ?? 0
        let beToday = sessionSummary?.breakevensToday ?? 0
        let openToday = sessionSummary?.openTradesToday ?? 0
        let todayTradesDesc = isVi
            ? "Tổng \(tradesToday) lệnh (\(winsToday) Thắng | \(lossesToday) Thua | \(beToday) Hòa) | Lệnh đang chạy: \(openToday)"
            : "Total \(tradesToday) trades (\(winsToday) W | \(lossesToday) L | \(beToday) BE) | Active Open: \(openToday)"
        let pnlTodayVal = sessionSummary != nil ? NSDecimalNumber(decimal: sessionSummary!.netPnlToday).doubleValue : 0.0
        let pnlTodayStr = (pnlTodayVal >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlTodayVal))
        let streak = sessionSummary?.currentStreakToday ?? 0
        let streakStr: String = {
            if streak > 0 { return isVi ? "Thắng \(streak) lệnh liên tiếp (+)" : "\(streak) wins in a row (+)" }
            if streak < 0 { return isVi ? "⚠️ Đang thua \(abs(streak)) lệnh liên tiếp (-)" : "⚠️ In a \(abs(streak))-loss losing streak (-)" }
            return isVi ? "Chưa có chuỗi lệnh hôm nay" : "No active streak today"
        }()
        
        let realBalStr: String = {
            if let bal = sessionSummary?.balance {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return Formatters.formatCurrency(bal, currency: curr)
            }
            return isVi ? "[Chưa kết nối]" : "[Not connected]"
        }()
        let equityStr: String = {
            if let eq = sessionSummary?.equity, let bal = sessionSummary?.balance, eq != bal {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return isVi ? "| Vốn ròng (Equity): \(Formatters.formatCurrency(eq, currency: curr))" : "| Equity: \(Formatters.formatCurrency(eq, currency: curr))"
            }
            return ""
        }()
        
        let h1SeriesStr: String = {
            guard let b = bars, !b.isEmpty else { return isVi ? "Không có dữ liệu nến H1" : "No H1 candle data" }
            return AIPromptBuilder.buildH1CandleSeriesSummary(bars: b, count: 15, symbol: trade.symbol, isVi: isVi)
        }()

        if isOpen {
            return isVi ? """
            [THÔNG TIN TÀI KHOẢN & TRẠNG THÁI RỦI RO HÔM NAY]:
            • Số dư thực tế: \(realBalStr) \(equityStr)
            • Trạng thái lệnh hôm nay: \(todayTradesDesc)
            • PnL ròng hôm nay: \(pnlTodayStr) | Chuỗi lệnh: \(streakStr)

            [THÔNG SỐ VỊ THẾ ĐANG MỞ (LIVE OPEN POSITION)]:
            • Cặp tiền: \(trade.symbol) | Chiều vị thế: \(directionStrVi) | Khối lượng: \(volumeStr) lots
            • Thời gian mở lệnh: \(openedAtStr) | Thời gian giữ lệnh: \(durationStr)
            • Giá vào (Entry): \(entryStr) | Thị giá hiện tại: \(exitStr)\(liveDeltaInfo)
            • Lợi nhuận tạm tính: \(pnlStr)\(excursionBlock)
            • Mức Cắt lỗ (SL): \(slStr) | Mức Chốt lời (TP): \(tpStr)
            • Mức rủi ro 1R tính toán: \(risk1RStr)
            • Chi phí sàn: \(feesStr) | Phí Swap: \(swapStr)
            • Ghi chú của trader: \(notes)\(preTradeBlock)\(lessonsBlock)\(complianceBlock)

            \(directionWarningVi)

            [DIỄN BIẾN CHUỖI 15 NẾN H1 GẦN NHẤT (OHLC + EMA 21/50 + WILDER RSI 14)]:
            \(h1SeriesStr)
            • Hướng dẫn phân tích: Dựa vào diễn biến chuỗi nến H1 ở trên để phân tích Price Action (rút râu, từ chối giá, cấu trúc nến, phân kỳ động lượng).

            NHIỆM VỤ CỦA RISK AI (CỐ VẤN QUẢN TRỊ RỦI RO ĐỘC LẬP):
            Phân tích sắc bén, khách quan, trực diện theo đúng 4 mục (không lặp lại thông tin hồ sơ tài khoản) và kết thúc bằng bảng chỉ đạo hành động [LIVE POSITION DIRECTIVE]:

            ### 1. Thẩm định tính hợp lý của vị thế & Động lượng nến
            - Vị thế [\(isShort ? "SELL" : "BUY")] tại \(entryStr) có hợp lý kỹ thuật và đúng với kế hoạch Pre-Trade đã cam kết không? Trader vào lệnh theo kịch bản xác nhận nến H1 hay vào vội vã cảm tính?
            - Phân tích động lượng H1 từ chuỗi 15 nến: Quỹ đạo RSI(14) và vị trí giá so với EMA(21) và EMA(50). Có xuất hiện phân kỳ cảnh báo đảo chiều không, hay động lượng vẫn đang gia tốc ủng hộ giữ vị thế [\(isShort ? "SELL" : "BUY")]?
            - Kết luận dứt khoát: [VỊ THẾ HỢP LÝ / CẦN PHÒNG THỦ CAO / SAI LẦM KỸ THUẬT].

            ### 2. Cấu trúc thị trường & Bối cảnh đa khung
            - Cấu trúc xu hướng khung lớn có tiếp tục ủng hộ lệnh này không hay giá đang tiệm cận vùng kháng cự/hỗ trợ mạnh hoặc vùng thanh khoản (BSL/SSL)?
            - Các vùng cản then chốt tiếp theo mà vị thế cần vượt qua hoặc có nguy cơ bị phản ứng đảo chiều?

            ### 3. Điểm vô hiệu hóa cấu trúc & Kế hoạch bảo vệ vốn
            - Mức giá cụ thể nào nếu nến H1 đóng cửa vi phạm sẽ BẺ GÃY cấu trúc của lệnh này (Structural Invalidation)?
            - Khuyến nghị hành động cụ thể ngay lúc này:
              • [GIỮ LỆNH (HOLD)]: Nếu cấu trúc và động lượng vẫn đồng thuận thuận chiều.
              • [DỜI SL VỀ HÒA VỐN (MOVE SL TO BE)]: Nếu biên độ lãi đã đủ điều kiện bảo vệ vốn an toàn.
              • [CHỐT LỜI MỘT PHẦN (PARTIAL TP)]: Nếu giá đang chạm cản nhạy cảm có râu từ chối.
              • [ĐÓNG LỆNH NGAY (CLOSE NOW)]: Nếu xuất hiện tín hiệu đảo chiều bất lợi hoặc vi phạm cấu trúc.

            ### 4. Đối chiếu Hồ sơ Trader & Phòng chống lỗi tâm lý
            - Khối lượng \(volumeStr) lots và rủi ro có tuân thủ quy tắc không? Có dấu hiệu FOMO hay lỗi tâm lý đã khai báo không?
            - Cảnh báo phòng ngừa các lỗi tâm lý quen thuộc của trader (như chốt non sớm vì sợ mất lãi tạm tính, hoặc không chịu chủ động kéo SL bảo vệ thành quả).

            BẮT BUỘC KẾT THÚC BẰNG KHỐI CHỈ ĐẠO HÀNH ĐỘNG ĐÚNG ĐỊNH DẠNG SAU:
            [LIVE POSITION DIRECTIVE]
            - Action: [HOLD hoặc PARTIAL TP hoặc MOVE SL TO BE hoặc CLOSE NOW]
            - Current Price: [Thị giá hiện tại]
            - Adjusted SL: [Mức SL mới khuyến nghị, ví dụ: Dời về \(entryStr) (BE), hoặc Giữ nguyên \(slStr)]
            - Partial Close Volume: [Khối lượng chốt nếu chọn Partial TP, ví dụ: 0.02 lot, nếu không ghi Không]
            - Next Target: [Vùng giá mục tiêu tiếp theo]

            > [Đúng 1 câu quy tắc kỷ luật hành động không khoan nhượng]
            """ : """
            [ACCOUNT CONTEXT & TODAY'S RISK PROFILE]:
            • Authoritative Balance: \(realBalStr) \(equityStr)
            • Today's Trade Activity: \(todayTradesDesc)
            • Net PnL Today: \(pnlTodayStr) | Current Streak: \(streakStr)

            [LIVE OPEN POSITION AUDIT]:
            • Symbol: \(trade.symbol) | Direction: \(directionStrEn) | Volume: \(volumeStr) lots
            • Opened At: \(openedAtStr) | Duration: \(durationStr)
            • Entry Price: \(entryStr) | Current Price: \(exitStr)\(liveDeltaInfo)
            • Unrealized P&L: \(pnlStr)\(excursionBlock)
            • Stop Loss: \(slStr) | Take Profit: \(tpStr)
            • Calculated 1R Risk: \(risk1RStr)
            • Fees: \(feesStr) | Swap: \(swapStr)
            • Trader Notes: \(notes)\(preTradeBlock)\(lessonsBlock)\(complianceBlock)

            \(directionWarningEn)

            [RECENT 15-CANDLE H1 EXECUTION SERIES (OHLC + EMA 21/50 + WILDER RSI 14)]:
            \(h1SeriesStr)
            • Analysis Directive: Analyze Price Action based on the 15-candle H1 series above (wicks, rejections, candle structure, momentum divergence).

            TASK: INDEPENDENT RISK ADVISORY AUDIT:
            Provide a razor-sharp, objective, institutional critique across the 4 sections below, concluding with the [LIVE POSITION DIRECTIVE] block:

            ### 1. Position Validity & Momentum
            - Is opening [\(isShort ? "SHORT" : "LONG")] at \(entryStr) technically rational and aligned with the Pre-Trade plan? Did trader enter on disciplined confirmation or impulse?
            - H1 Momentum across the 15 bars: RSI(14) trajectory and price relation to EMA(21) and EMA(50). Any threatening divergences or is momentum accelerating?
            - Decisive Verdict: [RATIONAL POSITION / DEFENSIVE STANCE REQUIRED / FLAWED SETUP].

            ### 2. Market Structure & Key Barriers
            - Does higher timeframe structure support holding, or is price running into major liquidity pools (BSL/SSL) or strong resistance?
            - Key upcoming barriers where price may react or reverse?

            ### 3. Structural Invalidation & Capital Defense
            - Exact price level representing structural invalidation where the setup must be aborted?
            - Immediate Actionable Directive:
              • [HOLD]: If structure and momentum remain fully intact toward TP.
              • [MOVE SL TO BE]: If profit runup is sufficient to secure risk-free status.
              • [PARTIAL TP]: If price is stalling at key barriers with rejection wicks.
              • [CLOSE NOW]: If momentum has completely inverted or broken structure.

            ### 4. Trader Profile Alignment & Discipline
            - Does volume of \(volumeStr) lots honor their declared risk budget? Any psychological leakage (premature profit taking, moving SL, or fear-driven decisions)?

            MANDATORY: CONCLUDE WITH THIS LIVE POSITION DIRECTIVE BLOCK:
            [LIVE POSITION DIRECTIVE]
            - Action: [HOLD or PARTIAL TP or MOVE SL TO BE or CLOSE NOW]
            - Current Price: [Current market price]
            - Adjusted SL: [Recommended SL level, e.g. Move to \(entryStr) (BE), or Keep \(slStr)]
            - Partial Close Volume: [Volume to close if Partial TP, e.g. 0.02 lot, otherwise None]
            - Next Target: [Next target price level]

            > [Single non-negotiable operational discipline rule]
            """
        } else {
            return isVi ? """
            LỆNH ĐÃ ĐÓNG CẦN KHÁM NGHIỆM CHI TIẾT (CLOSED TRADE POST-MORTEM):
            - Cặp tiền: \(trade.symbol) | Chiều vị thế: \(directionStrVi) | Khối lượng: \(volumeStr) lots
            - Thời gian: Mở \(openedAtStr) -> Đóng \(closedAtStr)
            - Giá vào (Entry): \(entryStr) -> Giá ra (Exit): \(exitStr)
            - Lợi nhuận thực tế: \(pnlStr)\(excursionBlock)
            - Mức SL dự kiến: \(slStr) | Mức TP dự kiến: \(tpStr)
            - Tỷ lệ R thực hiện: \(realizedRStr) (1R = \(risk1RStr)) | Thời gian giữ lệnh: \(durationStr)
            - Chi phí sàn: \(feesStr) | Phí Swap: \(swapStr)
            - Sai lầm trader tự ghi: \(mistakes)
            - Ghi chú trader: \(notes)
            - Tóm tắt nến quanh phiên: \(candleInfo)\(preTradeBlock)\(lessonsBlock)\(complianceBlock)
            \(trajectoryBlock)
            \(candlesTableBlock)\(momentumBlock)
            
            \(directionWarningVi)
            
            NHIỆM VỤ CỦA RISK AI (BẢN ĐÚC KẾT BÀI HỌC KỶ LUẬT):
            Nhận xét chuyên nghiệp, sắc bén theo 4 mục:
            
            ### 1. Đánh giá chất lượng điểm vào & Động lượng nến
            - Điểm vào có tuân thủ Playbook/kế hoạch không? Đối chiếu với hành động giá nến xác nhận quanh vùng cản.
            - Phân tích Động lượng RSI Core (BẮT BUỘC TRÍCH DẪN TỪ BẢNG ĐỘNG LƯỢNG):
              • BẮT BUỘC GHI RÕ SỐ LIỆU TẠI THỜI ĐIỂM VÀO: RSI(14) Wilder = [số], EMA(9) = [số], WMA(45) = [số].
              • So sánh EMA(9) vs WMA(45): Nền trung hạn ủng hộ Mua hay Bán hay đang nén Squeeze?
              • Tương quan 3 đường: RSI nằm trên/dưới EMA9 và WMA45? Có giao cắt hay phân kỳ bất lợi không?
              • Kết luận: Vào lệnh thuận dòng động lượng hay ngược đà RSI?
            
            ### 2. Đánh giá quản trị lệnh & Điểm thoát
            - Điểm thoát ở \(exitStr) là tuân thủ kế hoạch (chạm TP/SL chuẩn) hay do tâm lý (chốt non, gồng lỗ)?
            - Có hành vi dời SL, gỡ SL, hay nhồi lệnh vô kỷ luật không?
            
            ### 3. Cấu trúc thị trường & Bối cảnh đa khung
            - Thị trường đã đi đúng hay ngược phân tích? Điểm săn thanh khoản (Liquidity Sweep) nào đã tác động đến lệnh?
            
            ### 4. Phân loại sai lệch & Bài học kỷ luật
            - Nếu lệnh này thua lỗ hoặc thoát lệnh sai nguyên tắc, BẮT BUỘC PHÂN LOẠI theo 1 trong 4 nhóm:
              1. [Lỗi thực thi (Bad Execution)]: Vào lệnh sai điểm, trễ, đuổi giá (FOMO), chốt non, dời SL sai quy tắc.
              2. [Kế hoạch sai lệch (Flawed Plan)]: Giả định phân tích sai, đọc sai cấu trúc, bỏ qua cản HTF lớn.
              3. [Thị trường đổi pha (Regime Shift)]: Tin tức bất ngờ, bứt phá bất thường, biến động ngoài dự liệu.
              4. [Thua lỗ ngẫu nhiên (Random Loss)]: Thực hiện đúng 100% kế hoạch nhưng xác suất thống kê dừng lỗ.
            - Đối chiếu với [LỊCH SỬ TUÂN THỦ KỶ LUẬT & SAI LẦM QUÁ KHỨ]: Trader có tái phạm sai lầm cũ không?
            - Đúc kết đúng 1 bài học thực chiến súc tích nhất để nạp vào bộ nhớ kinh nghiệm dài hạn.
            """ : """
            CLOSED TRADE POST-MORTEM:
            - Symbol: \(trade.symbol) | Direction: \(directionStrEn) | Volume: \(volumeStr) lots
            - Timeline: Opened at \(openedAtStr) -> Closed at \(closedAtStr)
            - Entry Price: \(entryStr) -> Exit Price: \(exitStr)
            - Realized P&L: \(pnlStr)\(excursionBlock)
            - Planned SL: \(slStr) | Planned TP: \(tpStr)
            - Realized R: \(realizedRStr) (1R = \(risk1RStr)) | Duration: \(durationStr)
            - Fees: \(feesStr) | Swap: \(swapStr)
            - Self-Logged Mistakes: \(mistakes)
            - Trader Notes: \(notes)
            - Context: \(candleInfo)\(preTradeBlock)\(lessonsBlock)\(complianceBlock)
            \(trajectoryBlock)
            \(candlesTableBlock)\(momentumBlock)
            
            \(directionWarningEn)
            
            TASK: POST-TRADE FORENSIC DISCIPLINE AUDIT:
            
            ### 1. Entry Quality & Candlestick Momentum
            - Did this entry follow defined Playbook? Cross-examine with candle action and confirmed rejection at setup levels.
            - RSI Core Momentum (MANDATORY METRIC CITATION FROM TABLE):
              • State exact values at entry: RSI(14) = [value], EMA(9) = [value], WMA(45) = [value].
              • Compare EMA(9) vs WMA(45): Did intermediate baseline favor Bulls, Bears, or Squeeze?
              • 3-Line Alignment: Was RSI operating above/below EMA9 & WMA45? Any divergences?
              • Momentum Alignment Verdict: Was entry executed with or against prevailing momentum?
            
            ### 2. Execution & Exit Quality
            - Was the exit at \(exitStr) planned (hit TP/SL) or emotional (panicked early exit, widened SL)?
            
            ### 3. Market Structure & Multi-Timeframe Context
            - What structural event or liquidity sweep dictated the outcome?
            
            ### 4. Failure Classification & Discipline Takeaway
            - If this trade was a loss or suboptimal, CLASSIFY the primary cause into one of the four canonical modes:
              1. [Bad Execution]: Missed entry level, chasing price (FOMO), premature exit, or improper SL modification.
              2. [Flawed Plan]: Invalidation of initial thesis, structural misread, or ignoring major HTF barriers.
              3. [Regime Shift]: Unexpected news catalyst, volatility breakout, or liquidity drain.
              4. [Random Statistical Loss]: Flawless adherence to plan, but standard statistical distribution stop loss.
            - Audit against [LESSON COMPLIANCE & HISTORICAL ERROR AUDIT]: Did the trader repeat a previously flagged pitfall?
            - Synthesize the single most actionable lesson to persist into system memory.
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
        let plannedEntry = (plannedZone?.isEmpty ?? true) ? (isVi ? "Vùng kỹ thuật" : "Technical setup zone") : plannedZone!
        
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
            
            ⚠️ NGUYÊN TẮC: Giá đã chạm/quét \(setupTypeVi) (\(extremePriceStr)) rồi mới xác nhận ở \(entryStr). Đây là lệnh xác nhận kỷ luật, TUYỆT ĐỐI KHÔNG phê phán là vào sớm hay \(setupActionVi).
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
            
            ⚠️ PRINCIPLE: Price tested \(extremePriceStr) before confirmation at \(entryStr). This is a disciplined confirmation entry, NEVER accuse the trader of entering prematurely or "\(setupActionEn)".
            """
        }
    }
}
