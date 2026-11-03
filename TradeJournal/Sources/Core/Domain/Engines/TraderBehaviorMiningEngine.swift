import Foundation

// MARK: - Automated Trader Behavioral Leak Mining Engine
// Analyzes all historical trades across all accounts (The5ers, Exness, cTrader, manual)
// to extract authentic empirical behavioral vulnerabilities (toxic time windows, revenge trades,
// R:R asymmetry, overtrading, stop loss widening, streak tilt, impulse sizing).
public enum TraderBehaviorMiningEngine {
    
    public struct BehaviorMiningResult: Sendable, Equatable {
        public let totalTradesAnalyzed: Int
        public let worstTimeWindowVi: String?
        public let worstTimeWindowEn: String?
        public let revengeTradingLeakVi: String?
        public let revengeTradingLeakEn: String?
        public let rrAsymmetryLeakVi: String?
        public let rrAsymmetryLeakEn: String?
        public let toxicSymbolLeakVi: String?
        public let toxicSymbolLeakEn: String?
        public let overtradingLeakVi: String?
        public let overtradingLeakEn: String?
        public let movingOrNoStopLossLeakVi: String?
        public let movingOrNoStopLossLeakEn: String?
        public let streakTiltLeakVi: String?
        public let streakTiltLeakEn: String?
        public let positionSizingLeakVi: String?
        public let positionSizingLeakEn: String?
        public let weekendHoldingLeakVi: String?
        public let weekendHoldingLeakEn: String?
        public let fomoChasingLeakVi: String?
        public let fomoChasingLeakEn: String?
        
        /// Array of concise behavior names identified from history (for UI badges and clean trader profile storage)
        public let detectedBehaviorNames: [String]
        
        /// Formatted summary string to auto-populate traderProfile.knownPsychologicalLeaks
        public var detectedBehaviorSummary: String {
            if detectedBehaviorNames.isEmpty {
                return "Disciplined Execution (No Critical Leaks Detected)"
            }
            return detectedBehaviorNames.joined(separator: ", ")
        }
    }
    
    /// Mines all historical trades across all accounts for authentic behavioral vulnerabilities.
    public static func mineLeaks(
        from trades: [Trade],
        targetSymbol: String? = nil,
        timeZone: TimeZone = .current
    ) -> BehaviorMiningResult {
        let closedTrades = trades.filter { ($0.status != .open || $0.closedAt != nil) && $0.netPnl != 0 }
        guard closedTrades.count >= 5 else {
            return BehaviorMiningResult(
                totalTradesAnalyzed: closedTrades.count,
                worstTimeWindowVi: nil,
                worstTimeWindowEn: nil,
                revengeTradingLeakVi: nil,
                revengeTradingLeakEn: nil,
                rrAsymmetryLeakVi: nil,
                rrAsymmetryLeakEn: nil,
                toxicSymbolLeakVi: nil,
                toxicSymbolLeakEn: nil,
                overtradingLeakVi: nil,
                overtradingLeakEn: nil,
                movingOrNoStopLossLeakVi: nil,
                movingOrNoStopLossLeakEn: nil,
                streakTiltLeakVi: nil,
                streakTiltLeakEn: nil,
                positionSizingLeakVi: nil,
                positionSizingLeakEn: nil,
                weekendHoldingLeakVi: nil,
                weekendHoldingLeakEn: nil,
                fomoChasingLeakVi: nil,
                fomoChasingLeakEn: nil,
                detectedBehaviorNames: []
            )
        }
        
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var detectedNames: [String] = []
        
        // 1. Hourly Performance Analysis (Worst 1-hour window)
        var hourlyStats: [Int: (pnl: Decimal, wins: Int, losses: Int)] = [:]
        for t in closedTrades {
            let hour = calendar.component(.hour, from: t.openedAt)
            var cur = hourlyStats[hour] ?? (pnl: 0, wins: 0, losses: 0)
            cur.pnl += t.netPnl
            if t.netPnl > 0 { cur.wins += 1 } else { cur.losses += 1 }
            hourlyStats[hour] = cur
        }
        
        var worstHour: Int? = nil
        var minHourPnl = Decimal.zero
        for (h, stat) in hourlyStats {
            let total = stat.wins + stat.losses
            if total >= 3 && stat.pnl < minHourPnl {
                let winRate = Int((Double(stat.wins) / Double(total)) * 100)
                if winRate <= 40 || stat.pnl <= -100 {
                    minHourPnl = stat.pnl
                    worstHour = h
                }
            }
        }
        
        var worstTimeVi: String? = nil
        var worstTimeEn: String? = nil
        if let wh = worstHour, let stat = hourlyStats[wh] {
            let total = stat.wins + stat.losses
            let winRate = total > 0 ? Int((Double(stat.wins) / Double(total)) * 100) : 0
            let startH = String(format: "%02d:00", wh)
            let endH = String(format: "%02d:00", (wh + 1) % 24)
            worstTimeVi = "Khung giờ \(startH) - \(endH) có Win Rate thấp nhất (\(winRate)%, \(total) lệnh), sụt giảm PnL $\(String(format: "%.0f", abs((stat.pnl as NSDecimalNumber).doubleValue)))"
            worstTimeEn = "Time window \(startH) - \(endH) has lowest Win Rate (\(winRate)%, \(total) trades), drawdown -$\(String(format: "%.0f", abs((stat.pnl as NSDecimalNumber).doubleValue)))"
            detectedNames.append("Toxic Hour (\(startH)-\(endH))")
        }
        
        // 2. Revenge Trading Pattern (Trades entered within 15 mins of a loss)
        let sorted = closedTrades.sorted { ($0.closedAt ?? $0.openedAt) < ($1.closedAt ?? $1.openedAt) }
        var revengeTradesCount = 0
        var revengeLosses = 0
        var revengePnl = Decimal.zero
        
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if prev.netPnl < 0, let prevClose = prev.closedAt {
                let diffSec = curr.openedAt.timeIntervalSince(prevClose)
                if diffSec > 0 && diffSec <= 900 { // within 15 mins
                    revengeTradesCount += 1
                    revengePnl += curr.netPnl
                    if curr.netPnl < 0 { revengeLosses += 1 }
                }
            }
        }
        
        var revengeVi: String? = nil
        var revengeEn: String? = nil
        if revengeTradesCount >= 2 {
            let lossRate = Int((Double(revengeLosses) / Double(revengeTradesCount)) * 100)
            if lossRate >= 50 || revengePnl < 0 {
                revengeVi = "Phát hiện \(revengeTradesCount) lệnh vào vội trong 15 phút sau lệnh thua: Tỷ lệ thua \(lossRate)%, PnL âm $\(String(format: "%.0f", abs((revengePnl as NSDecimalNumber).doubleValue))) (tâm lý trả thù thị trường)"
                revengeEn = "Detected \(revengeTradesCount) rapid re-entries within 15m of a loss: Loss rate \(lossRate)%, PnL -$\(String(format: "%.0f", abs((revengePnl as NSDecimalNumber).doubleValue))) (revenge trading)"
                detectedNames.append("Revenge Trading")
            }
        }
        
        // 3. R:R Asymmetry (Cutting winners early vs holding losers)
        let wins = closedTrades.filter { $0.netPnl > 0 }
        let losses = closedTrades.filter { $0.netPnl < 0 }
        var rrVi: String? = nil
        var rrEn: String? = nil
        if wins.count >= 2 && losses.count >= 2 {
            let avgWin = wins.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(wins.count)
            let avgLoss = abs(losses.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(losses.count))
            if avgLoss > 0 {
                let ratio = (avgWin / avgLoss as NSDecimalNumber).doubleValue
                if ratio < 0.95 {
                    let avgWinStr = String(format: "$%.1f", (avgWin as NSDecimalNumber).doubleValue)
                    let avgLossStr = String(format: "$%.1f", (avgLoss as NSDecimalNumber).doubleValue)
                    rrVi = "Lệch tỷ lệ R:R: Lãi trung bình (\(avgWinStr)) nhỏ hơn lỗ trung bình (\(avgLossStr)) (thói quen chốt non gồng lỗ)"
                    rrEn = "Asymmetric R:R: Average win (\(avgWinStr)) is smaller than average loss (\(avgLossStr)) (cutting winners early, holding losers)"
                    detectedNames.append("Asymmetric R:R (Cut Winners Early)")
                }
            }
        }
        
        // 4. Toxic Symbol (Instrument with largest negative PnL)
        var symbolStats: [String: (pnl: Decimal, count: Int)] = [:]
        for t in closedTrades {
            let sym = t.symbol.uppercased()
            var cur = symbolStats[sym] ?? (pnl: 0, count: 0)
            cur.pnl += t.netPnl
            cur.count += 1
            symbolStats[sym] = cur
        }
        
        var toxicSym: String? = nil
        var minSymPnl = Decimal.zero
        for (sym, stat) in symbolStats {
            if stat.count >= 3 && stat.pnl < minSymPnl {
                minSymPnl = stat.pnl
                toxicSym = sym
            }
        }
        
        var toxicVi: String? = nil
        var toxicEn: String? = nil
        if let ts = toxicSym, minSymPnl <= -80 {
            let lossStr = String(format: "$%.0f", abs((minSymPnl as NSDecimalNumber).doubleValue))
            toxicVi = "Cặp tiền gây sụt giảm vốn nhiều nhất: \(ts) (-\(lossStr))"
            toxicEn = "Instrument with deepest cumulative drawdown: \(ts) (-\(lossStr))"
            detectedNames.append("Toxic Symbol (\(ts))")
        }
        
        // 5. Overtrading / High-Frequency Execution
        var tradesPerDay: [Date: [Trade]] = [:]
        for t in closedTrades {
            let day = calendar.startOfDay(for: t.openedAt)
            tradesPerDay[day, default: []].append(t)
        }
        
        var overtradingDaysCount = 0
        var overtradingDayPnl = Decimal.zero
        for (_, dayTrades) in tradesPerDay {
            if dayTrades.count >= 5 {
                overtradingDaysCount += 1
                let daySum = dayTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
                overtradingDayPnl += daySum
            }
        }
        
        var overtradingVi: String? = nil
        var overtradingEn: String? = nil
        if overtradingDaysCount >= 2 && overtradingDayPnl < 0 {
            let lossStr = String(format: "$%.0f", abs((overtradingDayPnl as NSDecimalNumber).doubleValue))
            overtradingVi = "Giao dịch quá tần suất: Xuất hiện \(overtradingDaysCount) ngày vào từ 5 lệnh trở lên dẫn tới lỗ ròng -$\(lossStr)"
            overtradingEn = "Overtrading: \(overtradingDaysCount) sessions had 5+ trades causing net drawdown -$\(lossStr)"
            detectedNames.append("Overtrading (High Frequency)")
        }
        
        // 6. Stop Loss Moving / Removal (Gồng lỗ hoặc nới SL)
        var movedSlCount = 0
        var noSlDeepLossCount = 0
        for t in closedTrades {
            if t.mistakes.contains(where: { $0.localizedCaseInsensitiveContains("sl") || $0.localizedCaseInsensitiveContains("stop") }) {
                movedSlCount += 1
            }
            if t.stopLoss == nil && t.netPnl < -50 {
                noSlDeepLossCount += 1
            }
        }
        
        var slLeakVi: String? = nil
        var slLeakEn: String? = nil
        if movedSlCount + noSlDeepLossCount >= 2 {
            let total = movedSlCount + noSlDeepLossCount
            slLeakVi = "Có \(total) lệnh vi phạm kỷ luật Stop Loss (nới SL hoặc không cài SL dẫn tới sụt giảm vốn sâu)"
            slLeakEn = "\(total) trades showed stop loss violations (widened SL or trading without stop loss leading to severe losses)"
            detectedNames.append("Moving / Removing Stop Loss")
        }
        
        // 7. Losing Streak Tilt (Tâm lý tiêu cực khi dính chuỗi thua liên tiếp)
        var maxLosingStreak = 0
        var currentLosingStreak = 0
        for t in sorted {
            if t.netPnl < 0 {
                currentLosingStreak += 1
                if currentLosingStreak > maxLosingStreak {
                    maxLosingStreak = currentLosingStreak
                }
            } else if t.netPnl > 0 {
                currentLosingStreak = 0
            }
        }
        
        var streakTiltVi: String? = nil
        var streakTiltEn: String? = nil
        if maxLosingStreak >= 3 {
            streakTiltVi = "Dính chuỗi thua liên tiếp lên tới \(maxLosingStreak) lệnh, dễ dẫn tới tâm lý cay cú hoặc mất phương hướng"
            streakTiltEn = "Encountered losing streaks of \(maxLosingStreak) consecutive trades, triggering psychological tilt"
            detectedNames.append("Losing Streak Tilt (\(maxLosingStreak) losses)")
        }
        
        // 8. Sudden Position Sizing / Martingale (Nhồi volume bất thường)
        let quantities = closedTrades.map { ($0.quantity as NSDecimalNumber).doubleValue }.sorted()
        let medianQty = quantities[quantities.count / 2]
        var sizingSpikes = 0
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let currQty = (curr.quantity as NSDecimalNumber).doubleValue
            if prev.netPnl < 0 && currQty >= (medianQty * 1.8) && currQty > 0.05 {
                sizingSpikes += 1
            }
        }
        
        var sizingVi: String? = nil
        var sizingEn: String? = nil
        if sizingSpikes >= 2 {
            sizingVi = "Phát hiện \(sizingSpikes) lần tăng vọt volume bất thường ngay sau lệnh thua (dấu hiệu Martingale / nhồi lệnh)"
            sizingEn = "Detected \(sizingSpikes) volume spikes immediately following a loss (Martingale / impulse sizing behavior)"
            detectedNames.append("Impulse Position Sizing")
        }
        
        // 9. Weekend Holding Risk (Giữ lệnh qua kỳ nghỉ cuối tuần)
        var weekendTrades = 0
        var weekendLossPnl = Decimal.zero
        for t in closedTrades {
            let openWeekday = calendar.component(.weekday, from: t.openedAt) // 6 is Friday
            if openWeekday == 6, let closed = t.closedAt {
                let closeWeekday = calendar.component(.weekday, from: closed)
                if closeWeekday == 1 || closeWeekday == 2 || closed.timeIntervalSince(t.openedAt) > 172800 {
                    weekendTrades += 1
                    weekendLossPnl += t.netPnl
                }
            }
        }
        
        var weekendVi: String? = nil
        var weekendEn: String? = nil
        if weekendTrades >= 2 && weekendLossPnl < 0 {
            weekendVi = "Giữ lệnh qua kỳ nghỉ cuối tuần: \(weekendTrades) lệnh chịu rủi ro gap thị trường, gây thiệt hại $\(String(format: "%.0f", abs((weekendLossPnl as NSDecimalNumber).doubleValue)))"
            weekendEn = "Weekend holding risk: \(weekendTrades) trades held across weekend gap causing -$\(String(format: "%.0f", abs((weekendLossPnl as NSDecimalNumber).doubleValue)))"
            detectedNames.append("Weekend Holding Risk")
        }
        
        // 10. FOMO Chasing at Extremes
        var fomoCount = 0
        for t in closedTrades {
            if t.mistakes.contains(where: { $0.localizedCaseInsensitiveContains("fomo") || $0.localizedCaseInsensitiveContains("chase") }) {
                fomoCount += 1
            }
        }
        
        var fomoVi: String? = nil
        var fomoEn: String? = nil
        if fomoCount >= 2 {
            fomoVi = "Ghi nhận \(fomoCount) lần vào lệnh do tâm lý FOMO hoặc đuổi giá theo nến (Chased Entry)"
            fomoEn = "Recorded \(fomoCount) FOMO or chased entries entering at disadvantageous extremes"
            detectedNames.append("FOMO Chasing")
        }
        
        return BehaviorMiningResult(
            totalTradesAnalyzed: closedTrades.count,
            worstTimeWindowVi: worstTimeVi,
            worstTimeWindowEn: worstTimeEn,
            revengeTradingLeakVi: revengeVi,
            revengeTradingLeakEn: revengeEn,
            rrAsymmetryLeakVi: rrVi,
            rrAsymmetryLeakEn: rrEn,
            toxicSymbolLeakVi: toxicVi,
            toxicSymbolLeakEn: toxicEn,
            overtradingLeakVi: overtradingVi,
            overtradingLeakEn: overtradingEn,
            movingOrNoStopLossLeakVi: slLeakVi,
            movingOrNoStopLossLeakEn: slLeakEn,
            streakTiltLeakVi: streakTiltVi,
            streakTiltLeakEn: streakTiltEn,
            positionSizingLeakVi: sizingVi,
            positionSizingLeakEn: sizingEn,
            weekendHoldingLeakVi: weekendVi,
            weekendHoldingLeakEn: weekendEn,
            fomoChasingLeakVi: fomoVi,
            fomoChasingLeakEn: fomoEn,
            detectedBehaviorNames: detectedNames
        )
    }
    
    /// Mines leaks across ALL trades in TradeDataStore (across all accounts) and automatically updates & persists TraderProfile.
    @MainActor
    @discardableResult
    public static func mineAndSyncToProfile(dataStore: TradeDataStore = .shared) -> BehaviorMiningResult {
        // Read from ALL trades in the entire database across all accounts
        let allTrades = dataStore.trades
        let tz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
        let result = mineLeaks(from: allTrades, timeZone: tz)
        
        var profile = dataStore.aiSettings.traderProfile
        if !result.detectedBehaviorNames.isEmpty {
            profile.knownPsychologicalLeaks = result.detectedBehaviorSummary
        } else if result.totalTradesAnalyzed >= 5 {
            profile.knownPsychologicalLeaks = "Disciplined Execution (No Critical Leaks Detected)"
        }
        
        if profile.knownPsychologicalLeaks != dataStore.aiSettings.traderProfile.knownPsychologicalLeaks {
            dataStore.aiSettings.traderProfile = profile
            dataStore.saveToDisk()
        }
        
        return result
    }
    
    /// Formats behavioral insights directly for system prompts.
    public static func formatForPrompt(result: BehaviorMiningResult, isVi: Bool) -> String {
        var items: [String] = []
        if let t = isVi ? result.worstTimeWindowVi : result.worstTimeWindowEn { items.append("- " + t) }
        if let r = isVi ? result.revengeTradingLeakVi : result.revengeTradingLeakEn { items.append("- " + r) }
        if let rr = isVi ? result.rrAsymmetryLeakVi : result.rrAsymmetryLeakEn { items.append("- " + rr) }
        if let tox = isVi ? result.toxicSymbolLeakVi : result.toxicSymbolLeakEn { items.append("- " + tox) }
        if let ot = isVi ? result.overtradingLeakVi : result.overtradingLeakEn { items.append("- " + ot) }
        if let sl = isVi ? result.movingOrNoStopLossLeakVi : result.movingOrNoStopLossLeakEn { items.append("- " + sl) }
        if let st = isVi ? result.streakTiltLeakVi : result.streakTiltLeakEn { items.append("- " + st) }
        if let sz = isVi ? result.positionSizingLeakVi : result.positionSizingLeakEn { items.append("- " + sz) }
        if let wk = isVi ? result.weekendHoldingLeakVi : result.weekendHoldingLeakEn { items.append("- " + wk) }
        if let fm = isVi ? result.fomoChasingLeakVi : result.fomoChasingLeakEn { items.append("- " + fm) }
        
        guard !items.isEmpty else { return "" }
        
        let header = isVi
            ? "\n[THỐNG KÊ LỖI GIAO DỊCH TỰ ĐỘNG TỪ LỊCH SỬ TOÀN BỘ \(result.totalTradesAnalyzed) LỆNH]:\n"
            : "\n[HISTORICAL EXECUTION LEAKS MINED ACROSS ALL \(result.totalTradesAnalyzed) TRADES]:\n"
        
        let footer = isVi
            ? "[DỮ LIỆU THAM KHẢO HÀNH VI LỊCH SỬ]: Đối chiếu với các điểm yếu thống kê trên để cảnh báo rủi ro và tối ưu điểm vào lệnh / mức dừng lỗ, không dùng để cấm hoặc từ chối đưa ra kế hoạch giao dịch.\n"
            : "[HISTORICAL BEHAVIOR REFERENCE]: Cross-reference statistical weaknesses above to highlight risks and refine entry/SL levels. Do NOT use to forbid or refuse trade setups.\n"
            
        return header + items.joined(separator: "\n") + "\n" + footer
    }
}
