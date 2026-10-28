import Foundation

// MARK: - Multi-Dimensional Performance Models (Form Definition)

public struct DimensionMetric: Equatable, Sendable {
    public let label: String
    public let totalTrades: Int
    public let winRate: Double // 0.0 - 100.0%
    public let netPnl: Decimal
    public let profitFactor: Double?
    public let avgTradePnl: Decimal
    
    public init(label: String, totalTrades: Int, winRate: Double, netPnl: Decimal, profitFactor: Double?, avgTradePnl: Decimal) {
        self.label = label
        self.totalTrades = totalTrades
        self.winRate = winRate
        self.netPnl = netPnl
        self.profitFactor = profitFactor
        self.avgTradePnl = avgTradePnl
    }
}

public struct ExcursionAnalyticsSummary: Equatable, Sendable {
    public let sampleSize: Int
    public let avgMaeDollar: Decimal?        // Mean adverse excursion (drawdown while holding)
    public let avgMfeDollar: Decimal?        // Mean favorable excursion (max runup while holding)
    public let captureEfficiencyPct: Double? // Realized Net PnL / MFE
    public let worstMaeDollar: Decimal?      // Extreme single trade drawdown
    
    public init(sampleSize: Int, avgMaeDollar: Decimal?, avgMfeDollar: Decimal?, captureEfficiencyPct: Double?, worstMaeDollar: Decimal?) {
        self.sampleSize = sampleSize
        self.avgMaeDollar = avgMaeDollar
        self.avgMfeDollar = avgMfeDollar
        self.captureEfficiencyPct = captureEfficiencyPct
        self.worstMaeDollar = worstMaeDollar
    }
}

public struct MultiDimensionalAnalyticsSnapshot: Equatable, Sendable {
    public let totalTrades: Int
    public let closedTrades: Int
    public let overallWinRate: Double
    public let overallNetPnl: Decimal
    public let overallProfitFactor: Double?
    public let bySession: [DimensionMetric]
    public let byDayOfWeek: [DimensionMetric]
    public let byDirection: [DimensionMetric]
    public let byDurationBucket: [DimensionMetric]
    public let excursionSummary: ExcursionAnalyticsSummary?
    
    public init(
        totalTrades: Int,
        closedTrades: Int,
        overallWinRate: Double,
        overallNetPnl: Decimal,
        overallProfitFactor: Double?,
        bySession: [DimensionMetric],
        byDayOfWeek: [DimensionMetric],
        byDirection: [DimensionMetric],
        byDurationBucket: [DimensionMetric],
        excursionSummary: ExcursionAnalyticsSummary?
    ) {
        self.totalTrades = totalTrades
        self.closedTrades = closedTrades
        self.overallWinRate = overallWinRate
        self.overallNetPnl = overallNetPnl
        self.overallProfitFactor = overallProfitFactor
        self.bySession = bySession
        self.byDayOfWeek = byDayOfWeek
        self.byDirection = byDirection
        self.byDurationBucket = byDurationBucket
        self.excursionSummary = excursionSummary
    }
}

// MARK: - Trade Analytics Aggregator
/// High-performance deterministic aggregation engine.
/// Computes factual multidimensional distributions for AI Coach consumption without hardcoded opinions.
public enum TradeAnalyticsAggregator {
    
    public static func computeSnapshot(
        trades: [Trade],
        excursions: [TradeExcursion] = [],
        timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .current
    ) -> MultiDimensionalAnalyticsSnapshot {
        let closed = trades.filter { $0.status != .open && $0.closedAt != nil }
        guard !closed.isEmpty else {
            return MultiDimensionalAnalyticsSnapshot(
                totalTrades: trades.count,
                closedTrades: 0,
                overallWinRate: 0.0,
                overallNetPnl: 0,
                overallProfitFactor: nil,
                bySession: [],
                byDayOfWeek: [],
                byDirection: [],
                byDurationBucket: [],
                excursionSummary: nil
            )
        }
        
        // 1. Overall Metrics
        let wins = closed.filter { $0.netPnl > 0 }.count
        let winRate = (Double(wins) / Double(closed.count)) * 100.0
        let netPnl = closed.reduce(Decimal.zero) { $0 + $1.netPnl }
        let grossProfit = closed.filter { $0.netPnl > 0 }.reduce(Decimal.zero) { $0 + $1.netPnl }
        let grossLoss = closed.filter { $0.netPnl < 0 }.reduce(Decimal.zero) { $0 + abs($1.netPnl) }
        let pf: Double? = grossLoss > 0 ? NSDecimalNumber(decimal: grossProfit / grossLoss).doubleValue : (grossProfit > 0 ? 999.0 : nil)
        
        // 2. By Trading Session (UTC based)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        
        var asianTrades: [Trade] = []
        var londonTrades: [Trade] = []
        var nyTrades: [Trade] = []
        
        for t in closed {
            let hour = calendar.component(.hour, from: t.openedAt)
            if hour >= 0 && hour < 8 {
                asianTrades.append(t)
            } else if hour >= 8 && hour < 13 {
                londonTrades.append(t)
            } else {
                nyTrades.append(t)
            }
        }
        
        let sessionMetrics: [DimensionMetric] = [
            computeMetric(label: "Asian (00:00 - 08:00 UTC)", trades: asianTrades),
            computeMetric(label: "London (08:00 - 13:00 UTC)", trades: londonTrades),
            computeMetric(label: "New York (13:00 - 24:00 UTC)", trades: nyTrades)
        ].filter { $0.totalTrades > 0 }
        
        // 3. By Day of Week
        let daysOfWeek = [
            (2, "Thứ Hai (Monday)"),
            (3, "Thứ Ba (Tuesday)"),
            (4, "Thứ Tư (Wednesday)"),
            (5, "Thứ Năm (Thursday)"),
            (6, "Thứ Sáu (Friday)")
        ]
        var dayMetrics: [DimensionMetric] = []
        for (weekday, label) in daysOfWeek {
            let dTrades = closed.filter { calendar.component(.weekday, from: $0.openedAt) == weekday }
            if !dTrades.isEmpty {
                dayMetrics.append(computeMetric(label: label, trades: dTrades))
            }
        }
        
        // 4. By Direction (Long vs Short)
        let longTrades = closed.filter { $0.direction == .long }
        let shortTrades = closed.filter { $0.direction == .short }
        var dirMetrics: [DimensionMetric] = []
        if !longTrades.isEmpty { dirMetrics.append(computeMetric(label: "LONG (Mua)", trades: longTrades)) }
        if !shortTrades.isEmpty { dirMetrics.append(computeMetric(label: "SHORT (Bán)", trades: shortTrades)) }
        
        // 5. By Holding Duration
        var scalpTrades: [Trade] = []
        var intradayTrades: [Trade] = []
        var swingTrades: [Trade] = []
        for t in closed {
            let durMs = t.durationMs ?? Int64((t.closedAt?.timeIntervalSince(t.openedAt) ?? 0) * 1000)
            if durMs < 15 * 60 * 1000 {
                scalpTrades.append(t)
            } else if durMs <= 4 * 3600 * 1000 {
                intradayTrades.append(t)
            } else {
                swingTrades.append(t)
            }
        }
        var durMetrics: [DimensionMetric] = []
        if !scalpTrades.isEmpty { durMetrics.append(computeMetric(label: "Scalp (< 15 phút)", trades: scalpTrades)) }
        if !intradayTrades.isEmpty { durMetrics.append(computeMetric(label: "Intraday (15 phút - 4 giờ)", trades: intradayTrades)) }
        if !swingTrades.isEmpty { durMetrics.append(computeMetric(label: "Swing (> 4 giờ)", trades: swingTrades)) }
        
        // 6. Excursion Summary (MAE / MFE)
        let excursionSummary: ExcursionAnalyticsSummary? = {
            guard !excursions.isEmpty else { return nil }
            var totalMae = Decimal.zero
            var totalMfe = Decimal.zero
            var worstMae = Decimal.zero
            var validCount = 0
            
            for exc in excursions {
                if let est = exc.estimate {
                    if let m = est.mae {
                        totalMae += m
                        if m < worstMae { worstMae = m }
                    }
                    if let f = est.mfe {
                        totalMfe += f
                    }
                    validCount += 1
                }
            }
            guard validCount > 0 else { return nil }
            let avgMae = totalMae / Decimal(validCount)
            let avgMfe = totalMfe / Decimal(validCount)
            let efficiencyPct: Double? = (totalMfe > 0) ? (NSDecimalNumber(decimal: (netPnl / totalMfe) * 100).doubleValue) : nil
            
            return ExcursionAnalyticsSummary(
                sampleSize: validCount,
                avgMaeDollar: avgMae,
                avgMfeDollar: avgMfe,
                captureEfficiencyPct: efficiencyPct,
                worstMaeDollar: worstMae
            )
        }()
        
        return MultiDimensionalAnalyticsSnapshot(
            totalTrades: trades.count,
            closedTrades: closed.count,
            overallWinRate: winRate,
            overallNetPnl: netPnl,
            overallProfitFactor: pf,
            bySession: sessionMetrics,
            byDayOfWeek: dayMetrics,
            byDirection: dirMetrics,
            byDurationBucket: durMetrics,
            excursionSummary: excursionSummary
        )
    }
    
    private static func computeMetric(label: String, trades: [Trade]) -> DimensionMetric {
        let count = trades.count
        guard count > 0 else {
            return DimensionMetric(label: label, totalTrades: 0, winRate: 0, netPnl: 0, profitFactor: nil, avgTradePnl: 0)
        }
        let wins = trades.filter { $0.netPnl > 0 }.count
        let winRate = (Double(wins) / Double(count)) * 100.0
        let net = trades.reduce(Decimal.zero) { $0 + $1.netPnl }
        let grossProfit = trades.filter { $0.netPnl > 0 }.reduce(Decimal.zero) { $0 + $1.netPnl }
        let grossLoss = trades.filter { $0.netPnl < 0 }.reduce(Decimal.zero) { $0 + abs($1.netPnl) }
        let pf: Double? = grossLoss > 0 ? NSDecimalNumber(decimal: grossProfit / grossLoss).doubleValue : (grossProfit > 0 ? 999.0 : nil)
        let avg = net / Decimal(count)
        
        return DimensionMetric(
            label: label,
            totalTrades: count,
            winRate: winRate,
            netPnl: net,
            profitFactor: pf,
            avgTradePnl: avg
        )
    }
    
    // MARK: - Markdown Table Formatter for AI Prompt (Zero Hardcoding)
    public static func formatSnapshotForPrompt(_ snapshot: MultiDimensionalAnalyticsSnapshot, isVi: Bool = true) -> String {
        guard snapshot.closedTrades > 0 else { return "" }
        
        let pnlFmt = { (val: Decimal) -> String in
            let num = NSDecimalNumber(decimal: val).doubleValue
            return (val >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(num))
        }
        let wrFmt = { (wr: Double) -> String in String(format: "%.1f%%", wr) }
        let pfFmt = { (pf: Double?) -> String in pf != nil ? String(format: "%.2f", pf!) : "N/A" }
        
        var output = ""
        if isVi {
            output += """
            
            [THỐNG KÊ HIỆU SUẤT ĐA CHIỀU (MULTI-DIMENSIONAL PERFORMANCE DATA)]:
            • Tổng số lệnh: \(snapshot.closedTrades) | Tỷ lệ thắng chung: \(wrFmt(snapshot.overallWinRate)) | Lợi nhuận ròng: \(pnlFmt(snapshot.overallNetPnl)) | Profit Factor: \(pfFmt(snapshot.overallProfitFactor))
            
            1. PHÂN BỐ THEO PHIÊN GIAO DỊCH (SESSIONS):
            | Phiên | Số lệnh | Tỷ lệ thắng | P&L ròng | Profit Factor |
            | :--- | :--- | :--- | :--- | :--- |
            """
            for m in snapshot.bySession {
                output += "\n| \(m.label) | \(m.totalTrades) | \(wrFmt(m.winRate)) | \(pnlFmt(m.netPnl)) | \(pfFmt(m.profitFactor)) |"
            }
            
            output += "\n\n2. PHÂN BỐ THEO THỨ TRONG TUẦN (DAYS OF WEEK):\n| Ngày | Số lệnh | Tỷ lệ thắng | P&L ròng | TB/Lệnh |\n| :--- | :--- | :--- | :--- | :--- |"
            for m in snapshot.byDayOfWeek {
                output += "\n| \(m.label) | \(m.totalTrades) | \(wrFmt(m.winRate)) | \(pnlFmt(m.netPnl)) | \(pnlFmt(m.avgTradePnl)) |"
            }
            
            output += "\n\n3. PHÂN BỐ THEO CHIỀU VỊ THẾ (LONG VS SHORT):\n| Chiều | Số lệnh | Tỷ lệ thắng | P&L ròng | Profit Factor |\n| :--- | :--- | :--- | :--- | :--- |"
            for m in snapshot.byDirection {
                output += "\n| \(m.label) | \(m.totalTrades) | \(wrFmt(m.winRate)) | \(pnlFmt(m.netPnl)) | \(pfFmt(m.profitFactor)) |"
            }
            
            output += "\n\n4. PHÂN BỐ THEO THỜI GIAN GIỮ LỆNH (HOLDING DURATION):\n| Khung thời gian | Số lệnh | Tỷ lệ thắng | P&L ròng |\n| :--- | :--- | :--- | :--- |"
            for m in snapshot.byDurationBucket {
                output += "\n| \(m.label) | \(m.totalTrades) | \(wrFmt(m.winRate)) | \(pnlFmt(m.netPnl)) |"
            }
            
            if let exc = snapshot.excursionSummary {
                let effStr = exc.captureEfficiencyPct.map { String(format: "%.1f%%", $0) } ?? "N/A"
                output += """
                
                
                5. CHỈ SỐ GỒNG LỖ VÀ GỒNG LÃI (MAE / MFE EXCURSIONS - \(exc.sampleSize) lệnh mẫu):
                • Sụt giảm tối đa trung bình khi giữ lệnh (Average MAE): \(pnlFmt(exc.avgMaeDollar ?? 0))
                • Lợi nhuận cực đại trung bình tiềm năng (Average MFE): \(pnlFmt(exc.avgMfeDollar ?? 0))
                • Hiệu suất hiện thực hóa lợi nhuận (Realized / MFE Efficiency): \(effStr)
                • Lệnh gồng lỗ sâu nhất (Worst Adverse Excursion): \(pnlFmt(exc.worstMaeDollar ?? 0))
                """
            }
        }
        
        return output
    }
}
