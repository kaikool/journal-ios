import SwiftUI

// MARK: - Dedicated Behavioral Leaks & Risk Mining Sheet
// Surfaces empirical behavioral leaks (worst trading hours, revenge trading, R:R asymmetry, toxic symbols)
// calculated directly by TraderBehaviorMiningEngine from closed trade history.
public struct TraderBehavioralLeaksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.filteredTrades
    }
    
    private var miningResult: TraderBehaviorMiningEngine.BehaviorMiningResult {
        let tz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
        return TraderBehaviorMiningEngine.mineLeaks(from: trades, timeZone: tz)
    }
    
    private var hasAnyLeak: Bool {
        miningResult.worstTimeWindowEn != nil ||
        miningResult.revengeTradingLeakEn != nil ||
        miningResult.rrAsymmetryLeakEn != nil ||
        miningResult.toxicSymbolLeakEn != nil
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Guidance Card
                    headerOverviewCard
                    
                    if miningResult.totalTradesAnalyzed < 10 {
                        // Empty State: Not enough trade data
                        AppCard {
                            AppEmptyState(
                                icon: "shield.checkerboard",
                                title: "Insufficient Trade History",
                                message: "TraderBehaviorMiningEngine requires at least 10 closed trades to accurately detect behavioral vulnerabilities. Currently analyzed: \(miningResult.totalTradesAnalyzed) trades."
                            )
                        }
                    } else if !hasAnyLeak {
                        // Clean discipline state
                        AppCard {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(AppTypography.displayHero)
                                    .foregroundColor(AppColors.profit)
                                
                                Text("No Critical Leaks Detected")
                                    .font(AppTypography.cardHeader)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Text("Across \(miningResult.totalTradesAnalyzed) analyzed trades, no statistically significant revenge trading, toxic hours, or asymmetric risk habits were detected.")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    } else {
                        // Mined Leaks List
                        if let worstTime = miningResult.worstTimeWindowEn {
                            leakCard(
                                title: "Worst Trading Window",
                                icon: "clock.badge.exclamationmark",
                                badgeText: "Time Decay",
                                badgeVariant: .loss,
                                description: worstTime,
                                recommendation: "Avoid initiating new risk during this timeframe. Statistical edge is severely negative."
                            )
                        }
                        
                        if let revenge = miningResult.revengeTradingLeakEn {
                            leakCard(
                                title: "Revenge Trading Pattern",
                                icon: "flame.fill",
                                badgeText: "High Vulnerability",
                                badgeVariant: .loss,
                                description: revenge,
                                recommendation: "Enforce a mandatory 30-minute cooldown protocol immediately after any realized loss."
                            )
                        }
                        
                        if let rrLeak = miningResult.rrAsymmetryLeakEn {
                            leakCard(
                                title: "Risk:Reward Asymmetry",
                                icon: "arrow.left.arrow.right",
                                badgeText: "Cut Winners Early",
                                badgeVariant: .neutral,
                                description: rrLeak,
                                recommendation: "Use structured limit take-profits and stop moving take-profit targets closer prematurely."
                            )
                        }
                        
                        if let toxic = miningResult.toxicSymbolLeakEn {
                            leakCard(
                                title: "Toxic Instrument",
                                icon: "xmark.octagon.fill",
                                badgeText: "Negative Drift",
                                badgeVariant: .loss,
                                description: toxic,
                                recommendation: "Consider blacklisting or reducing position size by 50% until edge is re-validated in backtesting."
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 32)
            }
            .background(AppColors.background)
            .navigationTitle("Behavioral Leaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header Overview Card
    private var headerOverviewCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.loss.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "waveform.path.ecg")
                        .font(AppTypography.cardHeader)
                        .foregroundColor(AppColors.loss)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Empirical Leak Mining")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.primaryText)
                        
                        Spacer()
                        
                        AppBadge("\(miningResult.totalTradesAnalyzed) Trades", style: .brand)
                    }
                    
                    Text("Automated mathematical audit of your historical trading habits to identify statistical drawdown points.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Leak Card Builder
    private func leakCard(
        title: String,
        icon: String,
        badgeText: String,
        badgeVariant: AppBadge.Variant,
        description: String,
        recommendation: String
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(AppTypography.rowTitle)
                        .foregroundColor(AppColors.loss)
                    
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    AppBadge(badgeText, variant: badgeVariant)
                }
                
                Divider()
                    .background(AppColors.border.opacity(0.35))
                
                Text(description)
                    .font(AppTypography.formLabel)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(2)
                
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.brand)
                        .padding(.top, 2)
                    
                    Text(recommendation)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
