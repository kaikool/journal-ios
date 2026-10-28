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
        let wr = String(format: "%.2f%%", (metrics.winRate ?? 0) * 100)
        let pnl = metrics.netPnl
        let pnlVal = NSDecimalNumber(decimal: pnl).doubleValue
        let pnlStr = (pnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
        return "\(activeAccountName) • \(count) Trades • WR: \(wr) • P&L: \(pnlStr)"
    }
    
    public var body: some View {
        HStack {
            Text(scopeSummaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
    }
}

public struct AIReflectionPreTradeBanner: View {
    public let onOpenPreTrade: () -> Void
    
    public init(onOpenPreTrade: @escaping () -> Void) {
        self.onOpenPreTrade = onOpenPreTrade
    }
    
    public var body: some View {
        AppCard {
            Button(action: onOpenPreTrade) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Pre-Trade Market Bias")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Text("D1 • H4 • M15")
                                .font(AppTypography.badgeMicro)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.brand.opacity(0.12))
                                .foregroundColor(AppColors.brand)
                                .cornerRadius(4)
                        }
                        
                        Text("Scan multi-timeframe liquidity sweeps, order blocks & setups")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .buttonStyle(.plain)
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
            Button(action: onOpenMemory) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.secondaryBackground)
                            .frame(width: 36, height: 36)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
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
                .padding(10)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Research Lab Card
            Button(action: onOpenResearch) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.brand.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "flask.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Research Lab")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("\(projectCount) active hypotheses")
                            .font(AppTypography.microCaption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                .padding(10)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
