import SwiftUI

/// Hero summary card for Trade Detail View adhering to Apple HIG
public struct TradeDetailHeroCard: View {
    public let trade: Trade
    public let durationString: String?
    @EnvironmentObject private var env: AppEnvironment
    
    public init(trade: Trade, durationString: String?) {
        self.trade = trade
        self.durationString = durationString
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text(trade.symbol)
                            .font(AppTypography.rowPrimary)
                            .foregroundColor(AppColors.primaryText)
                        
                        AppBadge(
                            trade.direction == .long ? "BUY" : "SELL",
                            variant: trade.direction == .long ? .brand : .warning
                        )
                        
                        if trade.isPartiallyClosed {
                            AppBadge("PARTIAL", variant: .warning)
                            
                            if trade.status == .open {
                                Text("\(Formatters.formatNumber(trade.openQuantity)) / \(Formatters.formatNumber(trade.quantity)) Lots")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                            } else {
                                Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        } else {
                            Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    AppBadge(
                        text: trade.status.rawValue.uppercased(),
                        color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                    )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    AppMonetaryText(
                        Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.displayHeroLarge,
                        color: Formatters.pnlColor(trade.netPnl)
                    )
                    
                    if trade.status == .open && trade.isPartiallyClosed {
                        Text("Realized P&L (Partial Close)")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(AppTypography.caption)
                        Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                            .font(AppTypography.caption)
                    }
                    .foregroundColor(AppColors.secondaryText)
                    
                    if let dur = durationString {
                        Text("•")
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(AppTypography.caption)
                            Text(dur)
                                .font(AppTypography.caption)
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }
}
