import Foundation

// MARK: - Automated Trader Behavioral Leak Mining Engine
// Analyzes thousands of historical closed trades from The5ers, Exness, cTrader, and manual logs
// to extract authentic empirical trading leaks (toxic time windows, revenge trades, R:R asymmetry).
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
    }
    
    /// Mines the user's historical trades for authentic behavioral vulnerabilities.
    public static func mineLeaks(
        from trades: [Trade],
        targetSymbol: String? = nil,
        timeZone: TimeZone = .current
    ) -> BehaviorMiningResult {
        let closedTrades = trades.filter { ($0.status != .open || $0.closedAt != nil) && $0.netPnl != 0 }
        guard closedTrades.count >= 10 else {
            return BehaviorMiningResult(
                totalTradesAnalyzed: closedTrades.count,
                worstTimeWindowVi: nil,
                worstTimeWindowEn: nil,
                revengeTradingLeakVi: nil,
                revengeTradingLeakEn: nil,
                rrAsymmetryLeakVi: nil,
                rrAsymmetryLeakEn: nil,
                toxicSymbolLeakVi: nil,
                toxicSymbolLeakEn: nil
            )
        }
        
        let calendar = Calendar.current
        
        // 1. Hourly Performance Analysis (Worst 3-hour window)
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
            if total >= 5 && stat.pnl < minHourPnl {
                minHourPnl = stat.pnl
                worstHour = h
            }
        }
        
        var worstTimeVi: String? = nil
        var worstTimeEn: String? = nil
        if let wh = worstHour, let stat = hourlyStats[wh] {
            let total = stat.wins + stat.losses
            let winRate = total > 0 ? Int((Double(stat.wins) / Double(total)) * 100) : 0
            let startH = String(format: "%02d:00", wh)
            let endH = String(format: "%02d:00", (wh + 1) % 24)
            worstTimeVi = "Khung giờ \(startH) - \(endH) có Win Rate thấp nhất (\(winRate)%, \(total) lệnh), gây sụt giảm PnL lớn"
            worstTimeEn = "Time window \(startH) - \(endH) has lowest Win Rate (\(winRate)%, \(total) trades), causing severe PnL drawdown"
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
        if revengeTradesCount >= 5 {
            let lossRate = Int((Double(revengeLosses) / Double(revengeTradesCount)) * 100)
            if lossRate >= 60 || revengePnl < 0 {
                revengeVi = "Phát hiện \(revengeTradesCount) lệnh vào vội trong vòng 15 phút sau lệnh thua: Tỷ lệ thua lên tới \(lossRate)% (tâm lý trả thù thị trường)"
                revengeEn = "Detected \(revengeTradesCount) rapid re-entries within 15m of a loss: Loss rate is \(lossRate)% (revenge trading pattern)"
            }
        }
        
        // 3. R:R Asymmetry (Cutting winners early vs holding losers)
        let wins = closedTrades.filter { $0.netPnl > 0 }
        let losses = closedTrades.filter { $0.netPnl < 0 }
        var rrVi: String? = nil
        var rrEn: String? = nil
        if !wins.isEmpty && !losses.isEmpty {
            let avgWin = wins.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(wins.count)
            let avgLoss = abs(losses.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(losses.count))
            if avgLoss > 0 {
                let ratio = (avgWin / avgLoss as NSDecimalNumber).doubleValue
                if ratio < 1.0 {
                    let avgWinStr = String(format: "$%.1f", (avgWin as NSDecimalNumber).doubleValue)
                    let avgLossStr = String(format: "$%.1f", (avgLoss as NSDecimalNumber).doubleValue)
                    rrVi = "Lệch tỷ lệ R:R: Lãi trung bình chỉ đạt \(avgWinStr) trong khi lỗ trung bình lên tới \(avgLossStr) (thói quen chốt non gồng lỗ)"
                    rrEn = "Asymmetric R:R: Average win is \(avgWinStr) while average loss is \(avgLossStr) (premature profit taking vs holding losses)"
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
            if stat.count >= 5 && stat.pnl < minSymPnl {
                minSymPnl = stat.pnl
                toxicSym = sym
            }
        }
        
        var toxicVi: String? = nil
        var toxicEn: String? = nil
        if let ts = toxicSym, minSymPnl < -200 {
            let lossStr = String(format: "$%.0f", abs((minSymPnl as NSDecimalNumber).doubleValue))
            toxicVi = "Cặp tiền gây sụt giảm vốn nhiều nhất: \(ts) (-\(lossStr))"
            toxicEn = "Instrument with deepest cumulative drawdown: \(ts) (-\(lossStr))"
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
            toxicSymbolLeakEn: toxicEn
        )
    }
    
    /// Formats behavioral insights directly for system prompts.
    public static func formatForPrompt(result: BehaviorMiningResult, isVi: Bool) -> String {
        var items: [String] = []
        if let t = isVi ? result.worstTimeWindowVi : result.worstTimeWindowEn { items.append("- " + t) }
        if let r = isVi ? result.revengeTradingLeakVi : result.revengeTradingLeakEn { items.append("- " + r) }
        if let rr = isVi ? result.rrAsymmetryLeakVi : result.rrAsymmetryLeakEn { items.append("- " + rr) }
        if let tox = isVi ? result.toxicSymbolLeakVi : result.toxicSymbolLeakEn { items.append("- " + tox) }
        
        guard !items.isEmpty else { return "" }
        
        let header = isVi
            ? "\n[THỐNG KÊ LỖI GIAO DỊCH TỪ LỊCH SỬ \(result.totalTradesAnalyzed) LỆNH]:\n"
            : "\n[HISTORICAL EXECUTION LEAKS FROM \(result.totalTradesAnalyzed) TRADES]:\n"
        
        let footer = isVi
            ? "[CHỈ ĐẠO QUẢN TRỊ RỦI RO]: Đối chiếu kế hoạch vào lệnh với các điểm yếu lịch sử trên. Từ chối thiết lập lệnh nếu chuẩn bị tái phạm.\n"
            : "[RISK DIRECTIVE]: Cross-examine trading plan against historical leaks. Reject setups if repeating past vulnerabilities.\n"
            
        return header + items.joined(separator: "\n") + "\n" + footer
    }
}
