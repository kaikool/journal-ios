import Foundation

public struct MarketBar: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64 { timestamp }
    public let timestamp: Int64 // ms epoch
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    public let volume: Decimal
    
    public init(timestamp: Int64, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Decimal) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

public struct ReplayFrame: Sendable {
    public let visibleBars: [MarketBar]
    public let throughTimestamp: Int64
    public let activeFills: [Execution]
    public let unrealizedPnl: Decimal
    
    public init(visibleBars: [MarketBar], throughTimestamp: Int64, activeFills: [Execution], unrealizedPnl: Decimal) {
        self.visibleBars = visibleBars
        self.throughTimestamp = throughTimestamp
        self.activeFills = activeFills
        self.unrealizedPnl = unrealizedPnl
    }
}

public enum TradeReplayEngine {
    
    public static func frame(
        bars: [MarketBar],
        fills: [Execution],
        trade: Trade,
        barIndex: Int,
        barDurationMs: Int64 = 60_000
    ) -> ReplayFrame {
        let clampedIndex = max(0, min(bars.count, barIndex))
        let visible = Array(bars.prefix(clampedIndex))
        
        guard let lastBar = visible.last else {
            return ReplayFrame(
                visibleBars: [],
                throughTimestamp: 0,
                activeFills: [],
                unrealizedPnl: 0
            )
        }
        
        let through = lastBar.timestamp + barDurationMs
        let currentFills = fills.filter { Int64($0.executedAt.timeIntervalSince1970 * 1000) <= through }
        
        // Calculate unrealized P&L at current bar close
        var unrealized: Decimal = 0
        if trade.direction == .long {
            unrealized = (lastBar.close - trade.avgEntry) * trade.quantity
        } else {
            unrealized = (trade.avgEntry - lastBar.close) * trade.quantity
        }
        
        return ReplayFrame(
            visibleBars: visible,
            throughTimestamp: through,
            activeFills: currentFills,
            unrealizedPnl: unrealized
        )
    }
}
