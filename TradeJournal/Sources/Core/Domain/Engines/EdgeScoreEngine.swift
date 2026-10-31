import Foundation

public struct EdgeScoreComponents: Equatable {
    public let winRate: Double
    public let profitFactor: Double
    public let avgWinLoss: Double
    public let drawdown: Double
    public let recovery: Double
    public let consistency: Double
}

public struct EdgeScore: Equatable {
    public let version: Int
    /// Normalized score between 0 and 100, or nil if fewer than 5 closed trades
    public let score: Double?
    public let components: EdgeScoreComponents
    public let closedTrades: Int
}

public typealias EdgeScoreResult = EdgeScore

extension EdgeScore {
    public var breakdown: EdgeScoreComponents? {
        score != nil ? components : nil
    }
}

/// Proprietary composite Edge Score engine evaluating statistical trading edge
public enum EdgeScoreEngine {
    public static let version = 2
    
    public static let weights: [String: Double] = [
        "winRate": 15,
        "profitFactor": 25,
        "avgWinLoss": 20,
        "drawdown": 15,
        "recovery": 10,
        "consistency": 15
    ]
    
    private static func clamp01(_ value: Double) -> Double {
        return min(max(value, 0.0), 1.0)
    }
    
    public static func computeEdgeScore(metrics: TradeMetrics) -> EdgeScore {
        let winRateScore = clamp01((metrics.winRate ?? 0) / 0.6) * 100
        
        let pf = metrics.profitFactorIsInfinite ? 3.0 : (metrics.profitFactor ?? 0)
        let profitFactorScore = clamp01(pf / 3.0) * 100
        
        let avgWinLossScore = clamp01((metrics.avgWinLossRatio ?? 0) / 2.5) * 100
        
        let ddPct = metrics.maxDrawdownPct
        let drawdownScore: Double
        if let ddPct = ddPct {
            drawdownScore = (1.0 - clamp01(ddPct / 0.25)) * 100
        } else {
            drawdownScore = 50.0
        }
        
        let recoveryScore: Double
        if metrics.maxDrawdown > 0 {
            recoveryScore = clamp01((metrics.recoveryFactor ?? 0) / 3.0) * 100
        } else if metrics.netPnl > 0 {
            recoveryScore = 100.0
        } else {
            recoveryScore = 0.0
        }
        
        let concentration = metrics.profitConcentration
        let consistencyScore: Double
        if let concentration = concentration {
            if concentration <= 0.15 {
                consistencyScore = 100.0
            } else {
                consistencyScore = (1.0 - clamp01((concentration - 0.15) / 0.85)) * 100
            }
        } else {
            consistencyScore = 0.0
        }
        
        let components = EdgeScoreComponents(
            winRate: winRateScore,
            profitFactor: profitFactorScore,
            avgWinLoss: avgWinLossScore,
            drawdown: drawdownScore,
            recovery: recoveryScore,
            consistency: consistencyScore
        )
        
        let wWin = weights["winRate"] ?? 0.25
        let wPF = weights["profitFactor"] ?? 0.20
        let wAWL = weights["avgWinLoss"] ?? 0.20
        let wDD = weights["drawdown"] ?? 0.15
        let wRec = weights["recovery"] ?? 0.10
        let wCon = weights["consistency"] ?? 0.10
        let totalWeight = weights.values.reduce(0.0, +)
        let safeTotal = totalWeight > 0 ? totalWeight : 1.0
        let weighted = (
            components.winRate * wWin +
            components.profitFactor * wPF +
            components.avgWinLoss * wAWL +
            components.drawdown * wDD +
            components.recovery * wRec +
            components.consistency * wCon
        ) / safeTotal
        
        let finalScore: Double? = metrics.closedTrades >= 5 ? weighted : nil
        
        return EdgeScore(
            version: version,
            score: finalScore,
            components: components,
            closedTrades: metrics.closedTrades
        )
    }
}
