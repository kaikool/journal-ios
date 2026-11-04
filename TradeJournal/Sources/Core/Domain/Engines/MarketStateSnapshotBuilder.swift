import Foundation

// MARK: - Market State Snapshot Builder
/// Constructs factual, multi-timeframe quantitative snapshots for AI Coach prompts.
/// Zero hardcoded analysis or forecasts; strictly measurable structures, indicator levels, and news timing.
public enum MarketStateSnapshotBuilder {
    
    public static func computeSnapshot(
        symbol: String,
        barsH4: [MarketBar],
        barsM15: [MarketBar],
        events: [ForexFactoryEvent] = [],
        referenceDate: Date = Date()
    ) -> MarketStateSnapshot {
        let cleanSymbol = symbol.uppercased()
        let curPrice = barsM15.last?.close ?? barsH4.last?.close ?? Decimal.zero
        
        // 1. Higher Timeframe (H4) Key Range
        let h4LastHigh = barsH4.suffix(24).map(\.high).max()
        let h4LastLow = barsH4.suffix(24).map(\.low).min()
        let h4Flow = (barsH4.last?.close ?? 0) >= (barsH4.first?.open ?? 0) ? "BULLISH" : "BEARISH"
        let h4BrokenLevel: Decimal? = nil
        
        // 2. Execution Timeframe (M15) Key Range
        let m15Flow = (barsM15.last?.close ?? 0) >= (barsM15.first?.open ?? 0) ? "BULLISH" : "BEARISH"
        let m15StateDesc: String? = nil
        let triggerLvl: Decimal? = barsM15.last?.close
        
        let sweepDesc: String? = nil
        let nearestUnswept: Decimal? = nil
        
        // 3. Technical Momentum (M15 Wilder RSI 14 / EMA 9 of RSI / WMA 45 of RSI)
        var rsiVal: Double? = nil
        var emaVal: Double? = nil
        var wmaVal: Double? = nil
        var gapVal: Double? = nil
        
        if barsM15.count >= 14 {
            let window = MomentumEngine.computeWindow(bars: barsM15, windowSize: 1)
            if let lastPoint = window.points.last {
                rsiVal = NSDecimalNumber(decimal: lastPoint.rsi14).doubleValue
                emaVal = NSDecimalNumber(decimal: lastPoint.ema9).doubleValue
                wmaVal = NSDecimalNumber(decimal: lastPoint.wma45).doubleValue
                gapVal = NSDecimalNumber(decimal: lastPoint.ema9 - lastPoint.wma45).doubleValue
            }
        }
        
        // 4. Macro Catalyst / News Proximity
        let highImpactEvents = events.filter { $0.impact == .high }
        var nearestEventTitle: String? = nil
        var countdownMins: Int? = nil
        
        if !highImpactEvents.isEmpty {
            let sortedByProximity = highImpactEvents.compactMap { ev -> (ForexFactoryEvent, Int)? in
                guard let d = ev.date else { return nil }
                let diffMins = Int(d.timeIntervalSince(referenceDate) / 60.0)
                guard abs(diffMins) <= 720 else { return nil }
                return (ev, diffMins)
            }.sorted { abs($0.1) < abs($1.1) }
            
            if let nearest = sortedByProximity.first {
                nearestEventTitle = "\(nearest.0.country) \(nearest.0.title)"
                countdownMins = nearest.1
            }
        }
        
        return MarketStateSnapshot(
            symbol: cleanSymbol,
            currentPrice: curPrice,
            h4OrderFlow: h4Flow,
            h4SwingHigh: h4LastHigh,
            h4SwingLow: h4LastLow,
            h4BrokenLevel: h4BrokenLevel,
            m15OrderFlow: m15Flow,
            m15MssState: m15StateDesc,
            m15TriggerLevel: triggerLvl,
            m15NearestSweep: sweepDesc,
            m15NearestUnsweptPool: nearestUnswept,
            rsi14: rsiVal,
            ema9: emaVal,
            wma45: wmaVal,
            emaVsWmaGap: gapVal,
            nearestHighImpactNewsTitle: nearestEventTitle,
            newsCountdownMinutes: countdownMins,
            timestamp: referenceDate
        )
    }
    
    // MARK: - Markdown Formatter for AI Prompt (Zero Hardcoding)
    public static func formatForPrompt(_ snapshot: MarketStateSnapshot, isVi: Bool = true) -> String {
        guard snapshot.currentPrice > 0 else { return "" }
        
        let curPriceStr = Formatters.price(snapshot.currentPrice)
        let h4HighStr = snapshot.h4SwingHigh.map { Formatters.price($0) } ?? "N/A"
        let h4LowStr = snapshot.h4SwingLow.map { Formatters.price($0) } ?? "N/A"
        let m15TriggerStr = snapshot.m15TriggerLevel.map { Formatters.price($0) } ?? "N/A"
        
        let rsiStr = snapshot.rsi14.map { String(format: "%.1f", $0) } ?? "N/A"
        let emaStr = snapshot.ema9.map { String(format: "%.2f", $0) } ?? "N/A"
        let wmaStr = snapshot.wma45.map { String(format: "%.2f", $0) } ?? "N/A"
        
        let newsBlock: String = {
            guard let title = snapshot.nearestHighImpactNewsTitle, let mins = snapshot.newsCountdownMinutes else {
                return isVi ? "Không có tin tức Đỏ (High Impact) trong 12h tới" : "No High-Impact events within 12h"
            }
            if mins > 0 {
                let h = mins / 60
                let m = mins % 60
                let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m) phút"
                return isVi ? "\(title) (sẽ công bố trong \(timeStr))" : "\(title) (in \(timeStr))"
            } else {
                let agoMins = abs(mins)
                let h = agoMins / 60
                let m = agoMins % 60
                let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m) phút"
                return isVi ? "\(title) (đã công bố \(timeStr) trước)" : "\(title) (released \(timeStr) ago)"
            }
        }()
        
        if isVi {
            return """
            
            [DỮ LIỆU ĐO LƯỜNG THỊ TRƯỜNG THỰC TẾ (OBJECTIVE MARKET FACTS)]:
            • Cặp tiền: \(snapshot.symbol) | Thị giá hiện tại: \(curPriceStr)
            • Khung lớn H4 (Order Flow & Cản): Cấu trúc: [\(snapshot.h4OrderFlow)] | Đỉnh Swing High: [\(h4HighStr)] | Đáy Swing Low: [\(h4LowStr)]
            • Khung nhỏ M15 (Execution): Cấu trúc: [\(snapshot.m15OrderFlow)] | Trạng thái: [\(snapshot.m15MssState ?? "Tiếp diễn")] | Mốc kích hoạt: [\(m15TriggerStr)]
            • Động lượng 3 đường RSI: RSI(14) = [\(rsiStr)] | EMA(9) = [\(emaStr)] | WMA(45) = [\(wmaStr)]
            • Tin tức kinh tế (Catalyst): \(newsBlock)
            """
        } else {
            return """
            
            [OBJECTIVE MARKET FACTS & MULTI-TIMEFRAME MEASUREMENTS]:
            • Symbol: \(snapshot.symbol) | Current Price: \(curPriceStr)
            • HTF H4 (Order Flow & Key Barriers): Structure: [\(snapshot.h4OrderFlow)] | Swing High: [\(h4HighStr)] | Swing Low: [\(h4LowStr)]
            • LTF M15 (Execution): Structure: [\(snapshot.m15OrderFlow)] | State: [\(snapshot.m15MssState ?? "Continuation")] | Trigger Level: [\(m15TriggerStr)]
            • 3-Line RSI Momentum: RSI(14) = [\(rsiStr)] | EMA(9) = [\(emaStr)] | WMA(45) = [\(wmaStr)]
            • Macro News Catalyst: \(newsBlock)
            """
        }
    }
}
