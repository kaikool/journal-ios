import Foundation

// MARK: - Clean Candlestick Tape Formatter
// Formats factual price action candlestick details into markdown tables for AI prompts.
// Shows Open, High, Low, Close, Range, Direction, and Price Action Candlestick Notes.

public enum CandleTapeFormatter: Sendable {
    
    public static func formatCandlesTable(
        bars: [MarketBar],
        count: Int = 16,
        symbol: String? = nil,
        displayTimeZone: TimeZone = .current
    ) -> String {
        guard !bars.isEmpty else { return "No candle data available." }
        let slice = bars.suffix(max(1, count))
        
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = displayTimeZone
        
        var lines: [String] = [
            "| # | Time | Open | High | Low | Close | Range | Direction | Structure Note |",
            "|---|------|------|------|-----|-------|-------|-----------|----------------|"
        ]
        
        for (offset, bar) in slice.enumerated() {
            let timeStr = f.string(from: bar.date)
            let o = formatPrice(bar.open, symbol: symbol)
            let h = formatPrice(bar.high, symbol: symbol)
            let l = formatPrice(bar.low, symbol: symbol)
            let c = formatPrice(bar.close, symbol: symbol)
            let range = formatPrice(abs(bar.high - bar.low), symbol: symbol)
            
            let dir: String = {
                if bar.close > bar.open { return "BULLISH ▲" }
                if bar.close < bar.open { return "BEARISH ▼" }
                return "DOJI ▬"
            }()
            
            let note = describeCandleStructure(bar: bar)
            
            lines.append("| \(offset + 1) | \(timeStr) | \(o) | \(h) | \(l) | \(c) | \(range) | \(dir) | \(note) |")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func describeCandleStructure(bar: MarketBar) -> String {
        let range = bar.high - bar.low
        guard range > 0 else { return "Doji ▬" }
        
        let body = abs(bar.close - bar.open)
        let upperWick = bar.high - max(bar.open, bar.close)
        let lowerWick = min(bar.open, bar.close) - bar.low
        
        let bodyRatio = (body as NSDecimalNumber).doubleValue / (range as NSDecimalNumber).doubleValue
        let upperWickRatio = (upperWick as NSDecimalNumber).doubleValue / (range as NSDecimalNumber).doubleValue
        let lowerWickRatio = (lowerWick as NSDecimalNumber).doubleValue / (range as NSDecimalNumber).doubleValue
        
        if lowerWickRatio >= 0.60 {
            return "Bullish Pinbar / Lower Rejection"
        } else if upperWickRatio >= 0.60 {
            return "Bearish Pinbar / Upper Rejection"
        } else if bodyRatio >= 0.70 {
            return bar.close >= bar.open ? "Bullish Expansion" : "Bearish Expansion"
        } else if bodyRatio <= 0.15 {
            return "Doji / Indecision"
        }
        return "Normal"
    }
    
    private static func formatPrice(_ p: Decimal, symbol: String?) -> String {
        if let sym = symbol, !sym.isEmpty {
            return Formatters.price(p, symbol: sym)
        }
        let d = (p as NSDecimalNumber).doubleValue
        if d >= 500 { return String(format: "%.2f", d) }
        if d >= 10 { return String(format: "%.3f", d) }
        return String(format: "%.5f", d)
    }
}
