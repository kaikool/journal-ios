import Foundation

// MARK: - Candlestick Pattern Recognition Engine
/// Quantitatively detects high-conviction single-candle and multi-candle Price Action formations.
/// Evaluates price action confluence against institutional Key Levels (Session POCs, Naked POCs, PDH/PDL).
public enum CandlePatternEngine {
    
    // MARK: - 1. Single Bar Pattern Detection
    public static func detectSingleBarPattern(
        bar: MarketBar,
        prevBar: MarketBar? = nil,
        atr: Decimal? = nil
    ) -> [CandlePatternType] {
        var patterns: [CandlePatternType] = []
        let range = bar.high - bar.low
        guard range > .zero else { return patterns }
        
        let body = abs(bar.close - bar.open)
        let upperWick = bar.high - max(bar.close, bar.open)
        let lowerWick = min(bar.close, bar.open) - bar.low
        
        // 1. Bullish Pinbar / Hammer (Long lower wick, small body at the top)
        if lowerWick >= (range * Decimal(string: "0.60")!) &&
            body <= (range * Decimal(string: "0.25")!) &&
            upperWick <= (range * Decimal(string: "0.15")!) {
            patterns.append(.bullishPinbar)
        }
        
        // 2. Bearish Pinbar / Shooting Star (Long upper wick, small body at the bottom)
        if upperWick >= (range * Decimal(string: "0.60")!) &&
            body <= (range * Decimal(string: "0.25")!) &&
            lowerWick <= (range * Decimal(string: "0.15")!) {
            patterns.append(.bearishPinbar)
        }
        
        // 3. Marubozu (Strong directional expansion candle with minimal wicks)
        if body >= (range * Decimal(string: "0.80")!) &&
            upperWick <= (range * Decimal(string: "0.10")!) &&
            lowerWick <= (range * Decimal(string: "0.10")!) {
            if bar.close > bar.open {
                patterns.append(.marubozuBullish)
            } else {
                patterns.append(.marubozuBearish)
            }
        }
        
        // 4. Doji (Indecision / compression)
        if body <= (range * Decimal(string: "0.10")!) &&
            upperWick >= (range * Decimal(string: "0.35")!) &&
            lowerWick >= (range * Decimal(string: "0.35")!) {
            patterns.append(.doji)
        }
        
        // 5. Engulfing Patterns (Requires previous bar)
        if let prev = prevBar {
            let prevRange = prev.high - prev.low
            let prevBody = abs(prev.close - prev.open)
            
            if prevRange > .zero {
                // Bullish Engulfing: Previous red, current green completely engulfing previous body
                if !prev.isUp && bar.isUp &&
                    bar.close > prev.open &&
                    bar.open <= prev.close &&
                    body >= prevBody {
                    patterns.append(.bullishEngulfing)
                }
                
                // Bearish Engulfing: Previous green, current red completely engulfing previous body
                if prev.isUp && !bar.isUp &&
                    bar.close < prev.open &&
                    bar.open >= prev.close &&
                    body >= prevBody {
                    patterns.append(.bearishEngulfing)
                }
                
                // Inside Bar: Current bar is entirely contained within previous bar's range
                if bar.high <= prev.high && bar.low >= prev.low {
                    patterns.append(.insideBar)
                }
            }
        }
        
        return patterns
    }

    // MARK: - 2. Multi-Bar Pattern Detection (2 to 3 bars)
    public static func detectMultiBarPatterns(
        bars: [MarketBar],
        atr: Decimal? = nil
    ) -> [DetectedCandlePattern] {
        guard bars.count >= 2 else { return [] }
        var detected: [DetectedCandlePattern] = []
        
        let count = bars.count
        let lastIdx = count - 1
        let current = bars[lastIdx]
        let prev = bars[lastIdx - 1]
        
        let tolerance: Decimal = {
            if let a = atr, a > .zero {
                return a * Decimal(string: "0.08")!
            }
            return current.close * Decimal(string: "0.0003")!
        }()
        
        // 1. Tweezer Bottom (2-Bar Low Equality Rejection)
        let lowDiff = abs(current.low - prev.low)
        let curLowerWick = min(current.close, current.open) - current.low
        let prevLowerWick = min(prev.close, prev.open) - prev.low
        let curRange = current.high - current.low
        let prevRange = prev.high - prev.low
        
        if lowDiff <= tolerance && curRange > .zero && prevRange > .zero {
            if curLowerWick >= (curRange * Decimal(string: "0.30")!) &&
                prevLowerWick >= (prevRange * Decimal(string: "0.30")!) {
                detected.append(DetectedCandlePattern(
                    type: .tweezerBottom,
                    barTimestamp: current.timestamp,
                    price: current.low,
                    summary: "Tweezer Bottom floor rejection test at \(current.low)"
                ))
            }
        }
        
        // 2. Tweezer Top (2-Bar High Equality Rejection)
        let highDiff = abs(current.high - prev.high)
        let curUpperWick = current.high - max(current.close, current.open)
        let prevUpperWick = prev.high - max(prev.close, prev.open)
        
        if highDiff <= tolerance && curRange > .zero && prevRange > .zero {
            if curUpperWick >= (curRange * Decimal(string: "0.30")!) &&
                prevUpperWick >= (prevRange * Decimal(string: "0.30")!) {
                detected.append(DetectedCandlePattern(
                    type: .tweezerTop,
                    barTimestamp: current.timestamp,
                    price: current.high,
                    summary: "Tweezer Top ceiling rejection test at \(current.high)"
                ))
            }
        }
        
        // 3. Three-Bar Formations (Morning Star, Evening Star, Soldiers/Crows)
        if count >= 3 {
            let bar1 = bars[lastIdx - 2]
            let bar2 = bars[lastIdx - 1]
            let bar3 = bars[lastIdx]
            
            let r1 = bar1.high - bar1.low
            let r2 = bar2.high - bar2.low
            let r3 = bar3.high - bar3.low
            let b1 = abs(bar1.close - bar1.open)
            let b2 = abs(bar2.close - bar2.open)
            let b3 = abs(bar3.close - bar3.open)
            
            if r1 > .zero && r2 > .zero && r3 > .zero {
                // Morning Star (Bearish -> Indecision -> Strong Bullish)
                if !bar1.isUp && b1 >= (r1 * Decimal(string: "0.50")!) &&
                    b2 <= (r2 * Decimal(string: "0.35")!) &&
                    bar2.low <= bar1.low &&
                    bar3.isUp && bar3.close >= (bar1.close + (b1 * Decimal(string: "0.50")!)) {
                    detected.append(DetectedCandlePattern(
                        type: .morningStar,
                        barTimestamp: bar3.timestamp,
                        price: bar3.close,
                        summary: "Morning Star bullish reversal formation"
                    ))
                }
                
                // Evening Star (Bullish -> Indecision -> Strong Bearish)
                if bar1.isUp && b1 >= (r1 * Decimal(string: "0.50")!) &&
                    b2 <= (r2 * Decimal(string: "0.35")!) &&
                    bar2.high >= bar1.high &&
                    !bar3.isUp && bar3.close <= (bar1.close - (b1 * Decimal(string: "0.50")!)) {
                    detected.append(DetectedCandlePattern(
                        type: .eveningStar,
                        barTimestamp: bar3.timestamp,
                        price: bar3.close,
                        summary: "Evening Star bearish reversal formation"
                    ))
                }
                
                // Three White Soldiers (Three consecutive strong bullish bars)
                if bar1.isUp && bar2.isUp && bar3.isUp &&
                    bar3.close > bar2.close && bar2.close > bar1.close &&
                    b1 >= (r1 * Decimal(string: "0.60")!) &&
                    b2 >= (r2 * Decimal(string: "0.60")!) &&
                    b3 >= (r3 * Decimal(string: "0.60")!) {
                    detected.append(DetectedCandlePattern(
                        type: .threeWhiteSoldiers,
                        barTimestamp: bar3.timestamp,
                        price: bar3.close,
                        summary: "Three White Soldiers bullish trend expansion"
                    ))
                }
                
                // Three Black Crows (Three consecutive strong bearish bars)
                if !bar1.isUp && !bar2.isUp && !bar3.isUp &&
                    bar3.close < bar2.close && bar2.close < bar1.close &&
                    b1 >= (r1 * Decimal(string: "0.60")!) &&
                    b2 >= (r2 * Decimal(string: "0.60")!) &&
                    b3 >= (r3 * Decimal(string: "0.60")!) {
                    detected.append(DetectedCandlePattern(
                        type: .threeBlackCrows,
                        barTimestamp: bar3.timestamp,
                        price: bar3.close,
                        summary: "Three Black Crows bearish trend expansion"
                    ))
                }
            }
        }
        
        return detected
    }

    // MARK: - 3. Confluence Detection at Institutional Key Levels
    /// Scans recent bars and checks whether any detected candlestick pattern formed
    /// directly upon a Key Level (Session POC, Daily/Weekly POC, Naked POC, PDH, PDL).
    public static func scanPatternsWithKeyLevelConfluence(
        bars: [MarketBar],
        keyLevels: [KeyLevel],
        atr: Decimal? = nil,
        lookbackBars: Int = 12
    ) -> [DetectedCandlePattern] {
        guard !bars.isEmpty && !keyLevels.isEmpty else { return [] }
        
        var results: [DetectedCandlePattern] = []
        let startIndex = max(1, bars.count - lookbackBars)
        
        let defaultTolerance: Decimal = {
            if let a = atr, a > .zero {
                return a * Decimal(string: "0.25")!
            }
            return (bars.last?.close ?? Decimal(1.0)) * Decimal(string: "0.0008")!
        }()
        
        for i in startIndex..<bars.count {
            let bar = bars[i]
            let prevBar = bars[i - 1]
            
            // Single bar patterns
            let singleTypes = detectSingleBarPattern(bar: bar, prevBar: prevBar, atr: atr)
            for pType in singleTypes {
                // Match with key levels
                for level in keyLevels {
                    let priceDiff: Decimal
                    if pType.isBullish {
                        // Bullish pattern: low should touch or approach key level
                        priceDiff = abs(bar.low - level.price)
                    } else if pType.isBearish {
                        // Bearish pattern: high should touch or approach key level
                        priceDiff = abs(bar.high - level.price)
                    } else {
                        // Neutral (Inside bar / Doji)
                        priceDiff = min(abs(bar.low - level.price), abs(bar.high - level.price))
                    }
                    
                    if priceDiff <= defaultTolerance {
                        let levelName = level.label
                        let action = pType.isBullish ? "Support Rejection" : (pType.isBearish ? "Resistance Rejection" : "Consolidation")
                        let summary = "\(pType.rawValue) at \(levelName) (\(level.price)) - \(action)"
                        
                        results.append(DetectedCandlePattern(
                            type: pType,
                            barTimestamp: bar.timestamp,
                            price: bar.close,
                            confluenceKeyLevel: level,
                            summary: summary
                        ))
                    }
                }
            }
            
            // Multi-bar patterns up to bar i
            let slice = Array(bars[0...i])
            let multiPatterns = detectMultiBarPatterns(bars: slice, atr: atr)
            for mPat in multiPatterns {
                for level in keyLevels {
                    let priceDiff = min(abs(bar.low - level.price), abs(bar.high - level.price))
                    if priceDiff <= defaultTolerance {
                        results.append(DetectedCandlePattern(
                            type: mPat.type,
                            barTimestamp: mPat.barTimestamp,
                            price: mPat.price,
                            confluenceKeyLevel: level,
                            summary: "\(mPat.summary) confluent with \(level.label) (\(level.price))"
                        ))
                    }
                }
            }
        }
        
        return results
    }
}
