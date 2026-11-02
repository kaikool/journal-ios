import SwiftUI

// MARK: - AI Reflection Account Scope Header & Pre-Trade Banner
public struct AIReflectionScopeHeader: View {
    public let activeAccountName: String
    public let metrics: TradeMetrics
    
    public init(activeAccountName: String, metrics: TradeMetrics) {
        self.activeAccountName = activeAccountName
        self.metrics = metrics
    }
    
    private var scopeSummaryText: String {
        let count = metrics.totalTrades
        let wr = Formatters.formatPercent(metrics.winRate)
        let pnlStr = Formatters.formatPnL(metrics.netPnl, currency: "USD")
        return "\(activeAccountName) • \(count) Trades • WR: \(wr) • P&L: \(pnlStr)"
    }
    
    public var body: some View {
        HStack {
            Text(scopeSummaryText)
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Spacer()
        }
        .appCardStyle(cornerRadius: 10)
    }
}

public struct AIReflectionPreTradeBanner: View {
    public let onOpenPreTrade: () -> Void
    
    public init(onOpenPreTrade: @escaping () -> Void) {
        self.onOpenPreTrade = onOpenPreTrade
    }
    
    public var body: some View {
        AppCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Pre-Trade Market Bias")
                            .font(AppTypography.rowTitle)
                            .foregroundColor(AppColors.primaryText)
                        
                        AppBadge("D1 • H4 • M15", style: .brand)
                    }
                    
                    Text("Scan multi-timeframe liquidity sweeps, order blocks & setups")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NativeHaptics.lightImpact()
                onOpenPreTrade()
            }
        }
    }
}

// MARK: - Dedicated Behavioral Leaks Banner
public struct AIReflectionBehaviorLeaksBanner: View {
    public let onOpenLeaks: () -> Void
    
    public init(onOpenLeaks: @escaping () -> Void) {
        self.onOpenLeaks = onOpenLeaks
    }
    
    public var body: some View {
        AppCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.loss.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform.path.ecg")
                        .font(AppTypography.cardHeader)
                        .foregroundColor(AppColors.loss)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Behavioral Leaks & Risk Mining")
                            .font(AppTypography.rowTitle)
                            .foregroundColor(AppColors.primaryText)
                        
                        AppBadge("Engine", style: .brand)
                    }
                    
                    Text("Audit toxic hours, revenge trading & R:R asymmetry")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NativeHaptics.lightImpact()
                onOpenLeaks()
            }
        }
    }
}

// MARK: - AI Intelligence Cards (Long-Term Memory & Research Lab)
public struct AIReflectionIntelligenceCards: View {
    public let memoryCount: Int
    public let projectCount: Int
    public let onOpenMemory: () -> Void
    public let onOpenResearch: () -> Void
    
    public init(
        memoryCount: Int,
        projectCount: Int,
        onOpenMemory: @escaping () -> Void,
        onOpenResearch: @escaping () -> Void
    ) {
        self.memoryCount = memoryCount
        self.projectCount = projectCount
        self.onOpenMemory = onOpenMemory
        self.onOpenResearch = onOpenResearch
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Memory Card
            HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.secondaryBackground)
                            .frame(width: 36, height: 36)
                        Image(systemName: "brain.head.profile")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.brand)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Memory")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("\(memoryCount) rules & lessons")
                            .font(AppTypography.microCaption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                .appCardStyle(cornerRadius: 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    NativeHaptics.lightImpact()
                    onOpenMemory()
                }
            
            // Research Lab Card
            HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.brand.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "flask.fill")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.brand)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Research Lab")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("\(projectCount) setups & hypotheses")
                            .font(AppTypography.microCaption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                .appCardStyle(cornerRadius: 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    NativeHaptics.lightImpact()
                    onOpenResearch()
                }
        }
    }
}
