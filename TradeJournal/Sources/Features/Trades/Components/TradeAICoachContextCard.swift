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
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        let isShort = trade.direction == .short
                        Text(isShort ? "SELL" : "BUY")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isShort ? AppColors.warning.opacity(0.12) : AppColors.brand.opacity(0.12))
                            .foregroundColor(isShort ? AppColors.warning : AppColors.brand)
                            .cornerRadius(4)
                        
                        Text(isOpen ? "OPEN POSITION" : "CLOSED")
                            .font(AppTypography.badgeMicro)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(isOpen ? AppColors.brand : AppColors.secondaryText)
                            .cornerRadius(4)
                    }
                    
                    let volStr = String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)
                    let entryStr = Formatters.price(trade.avgEntry, symbol: trade.symbol)
                    let exitStr = trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? (isOpen ? "Live" : "N/A")
                    
                    Text("\(volStr) lots • Entry: \(entryStr) → \(exitStr)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                let pnlVal = NSDecimalNumber(decimal: trade.netPnl).doubleValue
                let pnlStr = (trade.netPnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
                
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
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                
                Text("Profile:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                Text("\(profile.tradingStyle) • Max Risk \(profile.maxRiskPerTrade)")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColors.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}
