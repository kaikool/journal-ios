import SwiftUI

// MARK: - Trade AI Coach Context Card
// Displays high-level trade execution parameters, live P&L, and direction indicators
public struct TradeAICoachContextCard: View {
    public let trade: Trade
    public let isOpen: Bool
    
    public init(trade: Trade, isOpen: Bool) {
        self.trade = trade
        self.isOpen = isOpen
    }
    
    public var body: some View {
        AppCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(AppTypography.rowPrimary)
                            .foregroundColor(AppColors.primaryText)
                        
                        let isShort = trade.direction == .short
                        AppBadge(isShort ? "SELL" : "BUY", style: isShort ? .loss : .brand)
                        
                        AppBadge(isOpen ? "LIVE POSITION" : "CLOSED AUDIT", style: isOpen ? .profit : .neutral)
                    }
                    
                    let volStr = Formatters.formatDecimal(trade.quantity, maxDecimals: 2)
                    let entryStr = Formatters.price(trade.avgEntry, symbol: trade.symbol)
                    let exitStr = trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? (isOpen ? "Live" : "N/A")
                    
                    Text("\(volStr) lots • Entry: \(entryStr) → \(exitStr)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                let pnlStr = Formatters.formatPnL(trade.netPnl, currency: trade.currency ?? "USD")
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pnlStr)
                        .font(AppTypography.number(15, weight: .bold))
                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColors.profit)
                            .frame(width: 5, height: 5)
                        Text("RISK AI")
                            .font(AppTypography.badgeMicro)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Trader Profile Compliance Pill
public struct TradeAICoachCompliancePill: View {
    public let profile: TraderProfileConfig
    public let onTap: () -> Void
    
    public init(profile: TraderProfileConfig, onTap: @escaping () -> Void) {
        self.profile = profile
        self.onTap = onTap
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.text.rectangle")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brand)
            
            Text("Profile:")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
            
            Text("\(profile.tradingStyle) • Max Risk \(profile.maxRiskPerTrade)")
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText)
        }
        .appCardStyle(cornerRadius: 8, padding: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            NativeHaptics.lightImpact()
            onTap()
        }
    }
}
