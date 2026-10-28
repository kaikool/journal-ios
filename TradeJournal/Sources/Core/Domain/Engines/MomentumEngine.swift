import Foundation

/// Core domain indicator engine for Welles Wilder's RSI (14), EMA (9) of RSI, and WMA (45) of RSI.
/// Provides deterministic mathematical momentum modeling over a sliding window of 15 candles.
/// Re-uses existing candle data fetched from OANDA/Binance with zero duplicate network calls.
public struct MomentumEngine: Sendable {
    
    // MARK: - Models
    
    public struct MomentumPoint: Sendable, Codable, Equatable {
        public let date: Date
        public let close: Decimal
        public let rsi14: Decimal
        public let ema9: Decimal
        public let wma45: Decimal
        public let signalVi: String
        public let signalEn: String
        
        public init(
            date: Date,
            close: Decimal,
            rsi14: Decimal,
            ema9: Decimal,
            wma45: Decimal,
            signalVi: String,
            signalEn: String
        ) {
            self.date = date
            self.close = close
            self.rsi14 = rsi14
            self.ema9 = ema9
            self.wma45 = wma45
            self.signalVi = signalVi
            self.signalEn = signalEn
        }
    }
    
    public struct MomentumWindow: Sendable, Equatable {
        public let points: [MomentumPoint]
        public let currentRSI: Decimal?
        public let currentEMA9: Decimal?
        public let currentWMA45: Decimal?
        public let emaVsWmaGap: Decimal?
        public let emaVsWmaVi: String
        public let emaVsWmaEn: String
        public let alignmentVi: String
        public let alignmentEn: String
        public let divergenceVi: String?
        public let divergenceEn: String?
        
        public init(
            points: [MomentumPoint],
            currentRSI: Decimal?,
            currentEMA9: Decimal?,
            currentWMA45: Decimal?,
            emaVsWmaGap: Decimal? = nil,
            emaVsWmaVi: String = "",
            emaVsWmaEn: String = "",
            alignmentVi: String,
            alignmentEn: String,
            divergenceVi: String? = nil,
            divergenceEn: String? = nil
        ) {
            self.points = points
            self.currentRSI = currentRSI
            self.currentEMA9 = currentEMA9
            self.currentWMA45 = currentWMA45
            self.emaVsWmaGap = emaVsWmaGap
            self.emaVsWmaVi = emaVsWmaVi
            self.emaVsWmaEn = emaVsWmaEn
            self.alignmentVi = alignmentVi
            self.alignmentEn = alignmentEn
            self.divergenceVi = divergenceVi
            self.divergenceEn = divergenceEn
        }
    }
    
    // MARK: - Core Computation
    
    /// Computes Wilder RSI (14), EMA 9 of RSI, and WMA 45 of RSI across all bars,
    /// returning a snapshot window of the most recent `windowSize` candles (default: 15).
    public static func computeWindow(bars: [MarketBar], windowSize: Int = 15) -> MomentumWindow {
        guard bars.count >= 2 else {
            return MomentumWindow(
                points: [],
                currentRSI: nil,
                currentEMA9: nil,
                currentWMA45: nil,
                alignmentVi: "Chưa đủ dữ liệu nến",
                alignmentEn: "Insufficient candle history"
            )
        }
        
        // 1. Calculate Wilder's RSI (14)
        let rsiSeries = computeWilderRSI(bars: bars, period: 14)
        guard !rsiSeries.isEmpty else {
            return MomentumWindow(
                points: [],
                currentRSI: nil,
                currentEMA9: nil,
                currentWMA45: nil,
                alignmentVi: "Chưa đủ dữ liệu tính RSI",
                alignmentEn: "Insufficient data for RSI"
            )
        }
        
        // 2. Calculate EMA 9 of RSI 14
        let ema9Values = computeEMA(values: rsiSeries.map(\.rsi), period: 9)
        
        // 3. Calculate WMA 45 of RSI 14
        let wma45Values = computeWMA(values: rsiSeries.map(\.rsi), period: 45)
        
        // 4. Combine into MomentumPoints
        var allPoints: [MomentumPoint] = []
        let total = rsiSeries.count
        
        for i in 0..<total {
            let item = rsiSeries[i]
            let rsi = round2(item.rsi)
            let ema = round2(ema9Values[i])
            let wma = round2(wma45Values[i])
            
            let prevRsi = i > 0 ? rsiSeries[i - 1].rsi : item.rsi
            let prevEma = i > 0 ? ema9Values[i - 1] : ema9Values[i]
            
            let (sigVi, sigEn) = classifySignal(
                rsi: rsi,
                ema: ema,
                wma: wma,
                prevRsi: prevRsi,
                prevEma: prevEma
            )
            
            allPoints.append(MomentumPoint(
                date: item.date,
                close: item.close,
                rsi14: rsi,
                ema9: ema,
                wma45: wma,
                signalVi: sigVi,
                signalEn: sigEn
            ))
        }
        
        // 5. Extract sliding window (15 recent candles)
        let slice = Array(allPoints.suffix(max(1, windowSize)))
        let last = slice.last
        
        let (alignVi, alignEn) = classifyAlignment(
            rsi: last?.rsi14,
            ema: last?.ema9,
            wma: last?.wma45
        )
        
        let (emaWmaGap, emaWmaVi, emaWmaEn) = classifyEmaVsWma(
            ema: last?.ema9,
            wma: last?.wma45
        )
        
        let (divVi, divEn) = detectDivergence(points: slice)
        
        return MomentumWindow(
            points: slice,
            currentRSI: last?.rsi14,
            currentEMA9: last?.ema9,
            currentWMA45: last?.wma45,
            emaVsWmaGap: emaWmaGap,
            emaVsWmaVi: emaWmaVi,
            emaVsWmaEn: emaWmaEn,
            alignmentVi: alignVi,
            alignmentEn: alignEn,
            divergenceVi: divVi,
            divergenceEn: divEn
        )
    }
    
    // MARK: - 1. Welles Wilder's RSI (14) & Moving Averages (EMA / WMA)
    
    public enum RSIMAType: String, CaseIterable, Identifiable, Sendable {
        case ema = "EMA"
        case wma = "WMA"
        case none = "OFF"
        
        public var id: String { rawValue }
    }
    
    /// Computes Exponential Moving Average (EMA) of an optional series (e.g. RSI).
    /// Maintains 1:1 index alignment with the input series.
    public static func computeEMA(series: [Double?], period: Int = 14) -> [Double?] {
        guard period > 0, !series.isEmpty else {
            return Array(repeating: nil, count: series.count)
        }
        
        var results: [Double?] = Array(repeating: nil, count: series.count)
        let alpha = 2.0 / Double(period + 1)
        
        var validIndices: [Int] = []
        var validValues: [Double] = []
        
        for (i, val) in series.enumerated() {
            guard let v = val else { continue }
            validIndices.append(i)
            validValues.append(v)
            
            if validValues.count == period {
                // Initial EMA is the Simple Moving Average of the first `period` valid values
                let initialSMA = validValues.reduce(0.0, +) / Double(period)
                results[i] = initialSMA
            } else if validValues.count > period {
                guard let prevIdx = validIndices.dropLast().last, let prevEMA = results[prevIdx] else { continue }
                let currentEMA = (v * alpha) + (prevEMA * (1.0 - alpha))
                results[i] = currentEMA
            }
        }
        
        return results
    }
    
    /// Computes Weighted Moving Average (WMA) of an optional series (e.g. RSI).
    /// Weights increase linearly from 1 to period with denominator = period * (period + 1) / 2.
    public static func computeWMA(series: [Double?], period: Int = 14) -> [Double?] {
        guard period > 0, !series.isEmpty else {
            return Array(repeating: nil, count: series.count)
        }
        
        var results: [Double?] = Array(repeating: nil, count: series.count)
        let denominator = Double(period * (period + 1)) / 2.0
        
        var validValues: [Double] = []
        
        for (i, val) in series.enumerated() {
            guard let v = val else { continue }
            validValues.append(v)
            
            if validValues.count >= period {
                let window = validValues.suffix(period)
                var weightedSum = 0.0
                for (weightIdx, item) in window.enumerated() {
                    let weight = Double(weightIdx + 1)
                    weightedSum += item * weight
                }
                results[i] = weightedSum / denominator
            }
        }
        
        return results
    }
    
    /// Computes Welles Wilder's RSI (14) series across all provided bars.
    /// Returns an array of optional Double matching the bar count (nil for initial 14 warmup bars).
    public static func computeRSISeries(bars: [MarketBar], period: Int = 14) -> [Double?] {
        guard bars.count > period else {
            return Array(repeating: nil, count: bars.count)
        }
        
        var gains: [Double] = []
        var losses: [Double] = []
        
        for i in 1..<bars.count {
            let diff = (bars[i].close as NSDecimalNumber).doubleValue - (bars[i - 1].close as NSDecimalNumber).doubleValue
            if diff > 0 {
                gains.append(diff)
                losses.append(0)
            } else if diff < 0 {
                gains.append(0)
                losses.append(abs(diff))
            } else {
                gains.append(0)
                losses.append(0)
            }
        }
        
        var avgGain = gains.prefix(period).reduce(0, +) / Double(period)
        var avgLoss = losses.prefix(period).reduce(0, +) / Double(period)
        
        var results: [Double?] = Array(repeating: nil, count: period)
        
        let firstRSI: Double = {
            if avgLoss == 0 { return avgGain == 0 ? 50.0 : 100.0 }
            if avgGain == 0 { return 0.0 }
            let rs = avgGain / avgLoss
            return max(0.0, min(100.0, 100.0 - (100.0 / (1.0 + rs))))
        }()
        results.append(firstRSI)
        
        let pMinusOne = Double(period - 1)
        let pDouble = Double(period)
        
        for i in period..<gains.count {
            let g = gains[i]
            let l = losses[i]
            avgGain = ((avgGain * pMinusOne) + g) / pDouble
            avgLoss = ((avgLoss * pMinusOne) + l) / pDouble
            
            let rsi: Double = {
                if avgLoss == 0 { return avgGain == 0 ? 50.0 : 100.0 }
                if avgGain == 0 { return 0.0 }
                let rs = avgGain / avgLoss
                return max(0.0, min(100.0, 100.0 - (100.0 / (1.0 + rs))))
            }()
            results.append(rsi)
        }
        
        return results
    }
    
    private struct RSIRawItem {
        let date: Date
        let close: Decimal
        let rsi: Decimal
    }
    
    private static func computeWilderRSI(bars: [MarketBar], period: Int = 14) -> [RSIRawItem] {
        guard bars.count > period else { return [] }
        
        var gains: [Decimal] = []
        var losses: [Decimal] = []
        
        for i in 1..<bars.count {
            let diff = bars[i].close - bars[i - 1].close
            if diff > 0 {
                gains.append(diff)
                losses.append(Decimal.zero)
            } else if diff < 0 {
                gains.append(Decimal.zero)
                losses.append(abs(diff))
            } else {
                gains.append(Decimal.zero)
                losses.append(Decimal.zero)
            }
        }
        
        // Initial Average Gain & Loss (SMA of first `period` changes)
        var avgGain = gains.prefix(period).reduce(Decimal.zero, +) / Decimal(period)
        var avgLoss = losses.prefix(period).reduce(Decimal.zero, +) / Decimal(period)
        
        var results: [RSIRawItem] = []
        
        // First RSI value at bar index `period`
        let firstRSI = calculateRSIFromAverages(avgGain: avgGain, avgLoss: avgLoss)
        results.append(RSIRawItem(
            date: bars[period].date,
            close: bars[period].close,
            rsi: firstRSI
        ))
        
        let periodMinusOne = Decimal(period - 1)
        let periodDec = Decimal(period)
        
        // Subsequent values using Wilder's RMA Smoothing: (prevAvg * 13 + current) / 14
        for i in period..<gains.count {
            let barIndex = i + 1
            let g = gains[i]
            let l = losses[i]
            
            avgGain = ((avgGain * periodMinusOne) + g) / periodDec
            avgLoss = ((avgLoss * periodMinusOne) + l) / periodDec
            
            let rsi = calculateRSIFromAverages(avgGain: avgGain, avgLoss: avgLoss)
            results.append(RSIRawItem(
                date: bars[barIndex].date,
                close: bars[barIndex].close,
                rsi: rsi
            ))
        }
        
        return results
    }
    
    private static func calculateRSIFromAverages(avgGain: Decimal, avgLoss: Decimal) -> Decimal {
        if avgLoss == 0 {
            return avgGain == 0 ? Decimal(50) : Decimal(100)
        }
        if avgGain == 0 {
            return Decimal(0)
        }
        let rs = avgGain / avgLoss
        let rsi = Decimal(100) - (Decimal(100) / (Decimal(1) + rs))
        return min(Decimal(100), max(Decimal(0), rsi))
    }
    
    // MARK: - 2. EMA Calculation (EMA 9 of RSI)
    
    private static func computeEMA(values: [Decimal], period: Int = 9) -> [Decimal] {
        guard !values.isEmpty else { return [] }
        if values.count == 1 { return values }
        
        let alpha = Decimal(2) / Decimal(period + 1)
        let oneMinusAlpha = Decimal(1) - alpha
        
        var emaSeries: [Decimal] = []
        emaSeries.reserveCapacity(values.count)
        
        // Seed with running average until `period`
        var currentEMA = values[0]
        emaSeries.append(currentEMA)
        
        for i in 1..<values.count {
            if i < period {
                // Adaptive initialization during warmup
                let sum = values.prefix(i + 1).reduce(Decimal.zero, +)
                currentEMA = sum / Decimal(i + 1)
            } else {
                currentEMA = (values[i] * alpha) + (currentEMA * oneMinusAlpha)
            }
            emaSeries.append(currentEMA)
        }
        
        return emaSeries
    }
    
    // MARK: - 3. WMA Calculation (WMA 45 of RSI)
    
    private static func computeWMA(values: [Decimal], period: Int = 45) -> [Decimal] {
        guard !values.isEmpty else { return [] }
        
        var wmaSeries: [Decimal] = []
        wmaSeries.reserveCapacity(values.count)
        
        for i in 0..<values.count {
            let windowLen = min(period, i + 1)
            let denom = Decimal((windowLen * (windowLen + 1)) / 2)
            
            var weightedSum = Decimal.zero
            for offset in 0..<windowLen {
                let weight = Decimal(windowLen - offset)
                let val = values[i - offset]
                weightedSum += val * weight
            }
            
            let wma = denom > 0 ? (weightedSum / denom) : values[i]
            wmaSeries.append(wma)
        }
        
        return wmaSeries
    }
    
    // MARK: - Signal & Alignment Classification
    
    private static func classifySignal(
        rsi: Decimal,
        ema: Decimal,
        wma: Decimal,
        prevRsi: Decimal,
        prevEma: Decimal
    ) -> (vi: String, en: String) {
        if prevRsi <= prevEma && rsi > ema {
            return ("Bullish Cross ▲ (RSI cắt lên EMA9)", "Bullish Cross ▲ (RSI crossed above EMA9)")
        }
        if prevRsi >= prevEma && rsi < ema {
            return ("Bearish Cross ▼ (RSI cắt xuống EMA9)", "Bearish Cross ▼ (RSI crossed below EMA9)")
        }
        if rsi >= Decimal(70) {
            return ("Quá mua (>70) ⚠️", "Overbought (>70) ⚠️")
        }
        if rsi <= Decimal(30) {
            return ("Quá bán (<30) ⚠️", "Oversold (<30) ⚠️")
        }
        if rsi > ema && ema > wma {
            return ("Đà tăng mở rộng (RSI > EMA > WMA)", "Bullish Expansion (RSI > EMA > WMA)")
        }
        if rsi < ema && ema < wma {
            return ("Đà giảm mở rộng (RSI < EMA < WMA)", "Bearish Expansion (RSI < EMA < WMA)")
        }
        if rsi > ema {
            return ("Hồi phục ngắn hạn (RSI > EMA9)", "Short-term Rebound (RSI > EMA9)")
        } else {
            return ("Hạ nhiệt động lượng (RSI < EMA9)", "Momentum Cooling (RSI < EMA9)")
        }
    }
    
    private static func classifyEmaVsWma(ema: Decimal?, wma: Decimal?) -> (gap: Decimal?, vi: String, en: String) {
        guard let e = ema, let w = wma else {
            return (nil, "Chưa đủ dữ liệu", "Insufficient data")
        }
        let gap = round2(e - w)
        let gapVal = NSDecimalNumber(decimal: gap).doubleValue
        let gapStr = String(format: "%@%.2f", gapVal >= 0 ? "+" : "", gapVal)
        
        if gapVal > 1.0 {
            return (gap, "EMA(9) > WMA(45) [Chênh lệch: \(gapStr) pts] (Nền động lượng trung hạn nghiêng về TĂNG)", "EMA(9) > WMA(45) [Gap: \(gapStr) pts] (Intermediate baseline favors BULLISH)")
        } else if gapVal < -1.0 {
            return (gap, "EMA(9) < WMA(45) [Chênh lệch: \(gapStr) pts] (Nền động lượng trung hạn nghiêng về GIẢM)", "EMA(9) < WMA(45) [Gap: \(gapStr) pts] (Intermediate baseline favors BEARISH)")
        } else {
            return (gap, "EMA(9) và WMA(45) SÁT NHAU / HỘI TỤ [Chênh lệch: \(gapStr) pts] (Biên độ co thắt Squeeze - tích lũy chuẩn bị bứt phá)", "EMA(9) & WMA(45) CONVERGING / SQUEEZE [Gap: \(gapStr) pts] (Momentum compression - imminent expansion)")
        }
    }
    
    private static func classifyAlignment(
        rsi: Decimal?,
        ema: Decimal?,
        wma: Decimal?
    ) -> (vi: String, en: String) {
        guard let r = rsi, let e = ema, let w = wma else {
            return ("Chưa xác định", "Undefined")
        }
        if r > e && e > w {
            return ("XU HƯỚNG TĂNG ÁP ĐẢO (BULLISH ALIGNMENT): RSI > EMA9 > WMA45", "STRONG BULLISH ALIGNMENT: RSI > EMA9 > WMA45")
        }
        if r < e && e < w {
            return ("XU HƯỚNG GIẢM ÁP ĐẢO (BEARISH ALIGNMENT): RSI < EMA9 < WMA45", "STRONG BEARISH ALIGNMENT: RSI < EMA9 < WMA45")
        }
        if r > e && e <= w {
            return ("SÓNG HỒI TĂNG (COUNTER-TREND REBOUND): RSI vượt EMA9 nhưng còn dưới WMA45", "COUNTER-TREND REBOUND: RSI above EMA9 but below WMA45")
        }
        if r < e && e >= w {
            return ("SÓNG HỒI GIẢM (COUNTER-TREND PULLBACK): RSI mất EMA9 nhưng còn trên WMA45", "COUNTER-TREND PULLBACK: RSI below EMA9 but above WMA45")
        }
        return ("ĐỘNG LƯỢNG NÉN / TRUNG TÍNH (COMPRESSION)", "COMPRESSION / NEUTRAL")
    }
    
    // MARK: - Divergence Detection (over 15-candle window)
    
    private static func detectDivergence(points: [MomentumPoint]) -> (vi: String?, en: String?) {
        guard points.count >= 8 else { return (nil, nil) }
        
        let mid = points.count / 2
        let firstHalf = Array(points.prefix(mid))
        let secondHalf = Array(points.suffix(from: mid))
        
        guard let maxPrice1 = firstHalf.map(\.close).max(),
              let maxPrice2 = secondHalf.map(\.close).max(),
              let minPrice1 = firstHalf.map(\.close).min(),
              let minPrice2 = secondHalf.map(\.close).min(),
              let maxRsi1 = firstHalf.map(\.rsi14).max(),
              let maxRsi2 = secondHalf.map(\.rsi14).max(),
              let minRsi1 = firstHalf.map(\.rsi14).min(),
              let minRsi2 = secondHalf.map(\.rsi14).min() else {
            return (nil, nil)
        }
        
        // Bearish Divergence: Price higher high, RSI lower high (by at least 2.5 pts)
        if maxPrice2 > maxPrice1 && maxRsi2 < (maxRsi1 - Decimal(string: "2.5")!) {
            return (
                "⚠️ PHÂN KỲ GIẢM (BEARISH DIVERGENCE): Giá tạo đỉnh mới cao hơn nhưng RSI(14) suy yếu tạo đỉnh thấp hơn!",
                "⚠️ BEARISH DIVERGENCE: Price reached higher high while RSI(14) printed a lower high!"
            )
        }
        
        // Bullish Divergence: Price lower low, RSI higher low (by at least 2.5 pts)
        if minPrice2 < minPrice1 && minRsi2 > (minRsi1 + Decimal(string: "2.5")!) {
            return (
                "🚀 PHÂN KỲ TĂNG (BULLISH DIVERGENCE): Giá tạo đáy mới thấp hơn nhưng RSI(14) nâng đáy cao hơn!",
                "🚀 BULLISH DIVERGENCE: Price reached lower low while RSI(14) printed a higher low!"
            )
        }
        
        return (nil, nil)
    }
    
    // MARK: - Presentation & Table Formatter
    
    /// Formats the 15-candle momentum window into a clean markdown table with dual language support
    public static func formatMomentumTable(
        window: MomentumWindow,
        displayTimeZone: TimeZone = .current,
        isVi: Bool = true
    ) -> String {
        guard !window.points.isEmpty else { return "" }
        
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        df.timeZone = displayTimeZone
        
        let headerVi = """
        [ĐỘNG LƯỢNG KỸ THUẬT: RSI 14 WILDER / EMA 9 / WMA 45 (CỬA SỔ 15 NẾN M15)]:
        | # | Giờ | Giá đóng | RSI(14) | EMA(9) | WMA(45) | Trạng thái động lượng |
        |---|-----|----------|---------|--------|---------|------------------------|
        """
        
        let headerEn = """
        [TECHNICAL MOMENTUM: WILDER RSI 14 / EMA 9 / WMA 45 (15-CANDLE M15 WINDOW)]:
        | # | Time | Close | RSI(14) | EMA(9) | WMA(45) | Momentum State |
        |---|------|-------|---------|--------|---------|----------------|
        """
        
        var rows: [String] = []
        for (idx, p) in window.points.enumerated() {
            let timeStr = df.string(from: p.date)
            let closeStr = Formatters.price(p.close)
            let rsiStr = String(format: "%.2f", (p.rsi14 as NSDecimalNumber).doubleValue)
            let emaStr = String(format: "%.2f", (p.ema9 as NSDecimalNumber).doubleValue)
            let wmaStr = String(format: "%.2f", (p.wma45 as NSDecimalNumber).doubleValue)
            let sigStr = isVi ? p.signalVi : p.signalEn
            
            rows.append("| \(idx + 1) | \(timeStr) | \(closeStr) | \(rsiStr) | \(emaStr) | \(wmaStr) | \(sigStr) |")
        }
        
        let table = (isVi ? headerVi : headerEn) + "\n" + rows.joined(separator: "\n")
        
        let rVal = window.currentRSI.map { String(format: "%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let eVal = window.currentEMA9.map { String(format: "%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let wVal = window.currentWMA45.map { String(format: "%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? "N/A"
        let alignStr = isVi ? window.alignmentVi : window.alignmentEn
        let emaWmaStr = isVi ? window.emaVsWmaVi : window.emaVsWmaEn
        
        var summary = isVi ? """
        
        • Động lượng hiện tại (Nến mới nhất): RSI(14) = \(rVal) | EMA(9) = \(eVal) | WMA(45) = \(wVal)
        • Tương quan EMA(9) vs WMA(45): \(emaWmaStr)
        • Cấu trúc 3 đường: \(alignStr)
        """ : """
        
        • Latest Momentum Values: RSI(14) = \(rVal) | EMA(9) = \(eVal) | WMA(45) = \(wVal)
        • EMA(9) vs WMA(45) Baseline: \(emaWmaStr)
        • 3-Line Momentum Alignment: \(alignStr)
        """
        
        if let div = (isVi ? window.divergenceVi : window.divergenceEn) {
            summary += "\n• Tín hiệu phân kỳ: \(div)"
        }
        
        return table + "\n" + summary
    }
    
    // MARK: - Helpers
    
    private static func round2(_ value: Decimal) -> Decimal {
        var val = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &val, 2, .plain)
        return rounded
    }
}
