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
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(trade.direction == .long ? "BUY" : "SELL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                            .clipShape(Capsule())
                        
                        Text("\(Formatters.formatNumber(trade.quantity)) Lots")
                            .font(AppTypography.number(11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    AppBadge(
                        text: trade.status.rawValue.uppercased(),
                        color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                    )
                }
                
                AppMonetaryText(
                    Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 32, weight: .bold),
                    color: Formatters.pnlColor(trade.netPnl)
                )
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                            .font(AppTypography.caption)
                    }
                    .foregroundColor(AppColors.secondaryText)
                    
                    if let dur = durationString {
                        Text("•")
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 11))
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
