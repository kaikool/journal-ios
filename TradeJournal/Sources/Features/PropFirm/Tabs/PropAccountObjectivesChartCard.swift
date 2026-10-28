import SwiftUI
import Charts

// MARK: - Active Prop Account Visual Objectives & Risk Charts
// MARK: - Active Prop Account Visual Objectives & Risk Charts

internal struct PropAccountObjectivesChartCard: View {
    let acc: PropAccountItem
    
    private var balMinor: Int64 { acc.balanceMinor ?? acc.sizeMinor ?? 0 }
    private var eqMinor: Int64 { acc.equityMinor ?? balMinor }
    private var sizeMinor: Int64 { acc.sizeMinor ?? 0 }
    private var netPnlMinor: Int64 {
        if let np = acc.netPnlMinor { return np }
        if sizeMinor > 0 { return balMinor - sizeMinor }
        return 0
    }
    
    private var targetMinor: Int64 { acc.profitTargetMinor ?? 0 }
    private var dailyLossMinor: Int64 { acc.maxDailyLossMinor ?? 0 }
    private var maxLossMinor: Int64 { acc.maxLossMinor ?? 0 }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("PROGRAM OBJECTIVES & RISK LIMITS")
                    .font(AppTypography.cardHeader)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
            }
            .padding(.top, 2)
            
            // 1. Profit Target Progress
            if targetMinor > 0 {
                let targetDec = Decimal(targetMinor) / 100
                let currentProfitDec = Decimal(max(0, netPnlMinor)) / 100
                let isProfit = netPnlMinor > 0
                let progressRatio = isProfit ? min(1.0, Double(netPnlMinor) / Double(targetMinor)) : 0.0
                
                VStack(spacing: 4) {
                    HStack {
                        Text("Profit Target")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("+\(Formatters.formatCurrency(currentProfitDec, currency: acc.currency)) / +\(Formatters.formatCurrency(targetDec, currency: acc.currency))")
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(isProfit ? AppColors.profit : AppColors.primaryText)
                            
                            if isProfit {
                                Text("(\(Int(progressRatio * 100))%)")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.secondaryBackground)
                            Capsule()
                                .fill(AppColors.profit)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progressRatio))))
                        }
                    }
                    .frame(height: 4)
                }
            }
            
            // 2. Max Drawdown Buffer
            if maxLossMinor > 0 {
                let maxLossDec = Decimal(maxLossMinor) / 100
                let currentLossMinor = max(Int64(0), -netPnlMinor)
                let bufferRemainingMinor = max(Int64(0), maxLossMinor - currentLossMinor)
                let bufferRemainingDec = Decimal(bufferRemainingMinor) / 100
                let bufferRatio = max(0.0, min(1.0, Double(bufferRemainingMinor) / Double(maxLossMinor)))
                
                VStack(spacing: 4) {
                    HStack {
                        Text("Max Drawdown Buffer")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("\(Formatters.formatCurrency(bufferRemainingDec, currency: acc.currency)) remaining (of \(Formatters.formatCurrency(maxLossDec, currency: acc.currency)))")
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(bufferRatio < 0.25 ? AppColors.loss : AppColors.primaryText)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.secondaryBackground)
                            Capsule()
                                .fill(bufferRatio < 0.25 ? AppColors.loss : (bufferRatio < 0.5 ? Color.orange : AppColors.brand))
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(bufferRatio))))
                        }
                    }
                    .frame(height: 4)
                }
            }
            
            // 3. Daily Loss Limit
            if dailyLossMinor > 0 {
                let dailyLimitDec = Decimal(dailyLossMinor) / 100
                VStack(spacing: 4) {
                    HStack {
                        Text("Daily Loss Limit")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("-\(Formatters.formatCurrency(dailyLimitDec, currency: acc.currency)) cap")
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Capsule()
                        .fill(AppColors.secondaryBackground)
                        .overlay(
                            Capsule().fill(Color.orange.opacity(0.85)),
                            alignment: .leading
                        )
                        .frame(height: 4)
                }
            }
            
            // 4. Minimum Winning Days
            if let winDays = acc.winningDays {
                let minDays = acc.minTradingDays ?? 3
                VStack(spacing: 4) {
                    HStack {
                        Text("Minimum Winning Days")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(winDays) / \(minDays) days")
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(winDays >= minDays ? AppColors.profit : AppColors.primaryText)
                            
                            if winDays >= minDays {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.profit)
                                    .font(.system(size: 11))
                            }
                        }
                    }
                    
                    HStack(spacing: 4) {
                        ForEach(1...max(1, minDays), id: \.self) { day in
                            Capsule()
                                .fill(day <= winDays ? AppColors.profit : AppColors.secondaryBackground)
                                .frame(height: 4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
