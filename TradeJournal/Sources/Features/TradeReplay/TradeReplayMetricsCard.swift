import SwiftUI

/// Top Header Card showing real-time playback P&L and bar progress
public struct TradeReplayHeaderCard: View {
    public let trade: Trade
    public let frame: ReplayFrame
    public let bars: [MarketBar]
    public let currentStep: Int
    public let isLoadingCandles: Bool
    public let reportingCurrency: String
    
    public init(
        trade: Trade,
        frame: ReplayFrame,
        bars: [MarketBar],
        currentStep: Int,
        isLoadingCandles: Bool,
        reportingCurrency: String
    ) {
        self.trade = trade
        self.frame = frame
        self.bars = bars
        self.currentStep = currentStep
        self.isLoadingCandles = isLoadingCandles
        self.reportingCurrency = reportingCurrency
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(AppTypography.headline)
                        
                        AppBadge(
                            text: trade.direction.rawValue.uppercased(),
                            color: trade.direction == .long ? AppColors.profit : AppColors.loss
                        )
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        let isEnd = (bars.isEmpty || currentStep >= bars.count) && trade.status != .open
                        let title: String = {
                            if !frame.hasEntered { return "WAITING FOR ENTRY" }
                            if isEnd || frame.hasExited { return "NET P&L" }
                            return "UNREALIZED P&L"
                        }()
                        Text(title)
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.secondaryText)
                        
                        let displayPnl: Decimal = {
                            if !frame.hasEntered { return 0 }
                            if isEnd || frame.hasExited || bars.isEmpty { return trade.netPnl }
                            return frame.unrealizedPnl
                        }()
                        Text(Formatters.formatPnL(displayPnl, currency: reportingCurrency))
                            .font(AppTypography.financialNumber(size: 18, weight: .bold))
                            .foregroundColor(!frame.hasEntered ? AppColors.secondaryText : Formatters.pnlColor(displayPnl))
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Entry:")
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(trade.avgEntry))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("•")
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                        
                        Text("Qty:")
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatNumber(trade.quantity))
                            .foregroundColor(AppColors.primaryText)
                    }
                    .font(AppTypography.caption)
                    .lineLimit(1)
                    
                    Spacer()
                    
                    if let curBar = frame.currentBar {
                        HStack(spacing: 4) {
                            Text("Bar:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text(Formatters.price(curBar.close))
                                .font(AppTypography.captionBold)
                                .foregroundColor(curBar.isUp ? AppColors.profit : AppColors.loss)
                        }
                        .lineLimit(1)
                    } else if isLoadingCandles {
                        Text("Loading…")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                }
                .minimumScaleFactor(0.85)
            }
        }
    }
}

/// Excursion Estimates Card (MAE & MFE metrics)
public struct TradeReplayExcursionCard: View {
    public let excursionEstimate: ExcursionEstimate?
    public let isLoadingCandles: Bool
    public let barsCount: Int
    public let reportingCurrency: String
    
    public init(
        excursionEstimate: ExcursionEstimate?,
        isLoadingCandles: Bool,
        barsCount: Int,
        reportingCurrency: String
    ) {
        self.excursionEstimate = excursionEstimate
        self.isLoadingCandles = isLoadingCandles
        self.barsCount = barsCount
        self.reportingCurrency = reportingCurrency
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("EXCURSION ESTIMATES (MAE & MFE)")
                        .font(AppTypography.cardTitle)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("Extremes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    // MAE (Drawdown)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MAE (Drawdown)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                        
                        if let mae = excursionEstimate?.mae {
                            Text(Formatters.formatPnL(mae, currency: reportingCurrency))
                                .font(AppTypography.financialNumber(size: 17, weight: .bold))
                                .foregroundColor(AppColors.loss)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            
                            if let p = excursionEstimate?.maePrice {
                                let ptsText = excursionEstimate?.maePoints.map { " (-\(Formatters.formatNumber($0)) pts)" } ?? ""
                                Text("Low: \(Formatters.price(p))\(ptsText)")
                                    .font(AppTypography.number(10, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        } else if isLoadingCandles && barsCount == 0 {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7)
                                Text("Calculating…")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .frame(height: 24)
                        } else {
                            Text("Unavailable")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 48)
                    
                    // MFE (Runup)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MFE (Runup)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                        
                        if let mfe = excursionEstimate?.mfe {
                            Text(Formatters.formatPnL(mfe, currency: reportingCurrency))
                                .font(AppTypography.financialNumber(size: 17, weight: .bold))
                                .foregroundColor(AppColors.profit)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            
                            if let p = excursionEstimate?.mfePrice {
                                let ptsText = excursionEstimate?.mfePoints.map { " (+\(Formatters.formatNumber($0)) pts)" } ?? ""
                                Text("High: \(Formatters.price(p))\(ptsText)")
                                    .font(AppTypography.number(10, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        } else if isLoadingCandles && barsCount == 0 {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7)
                                Text("Calculating…")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .frame(height: 24)
                        } else {
                            Text("Unavailable")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
