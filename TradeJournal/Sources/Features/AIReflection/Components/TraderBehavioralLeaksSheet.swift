import SwiftUI

// MARK: - Dedicated Behavioral Leaks & Risk Mining Sheet
// Surfaces empirical behavioral leaks (worst trading hours, revenge trading, R:R asymmetry, toxic symbols)
// calculated directly by TraderBehaviorMiningEngine from closed trade history.
public struct TraderBehavioralLeaksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.trades
    }
    
    private var miningResult: TraderBehaviorMiningEngine.BehaviorMiningResult {
        let tz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
        return TraderBehaviorMiningEngine.mineLeaks(from: trades, timeZone: tz)
    }
    
    private var hasAnyLeak: Bool {
        !miningResult.detectedBehaviorNames.isEmpty
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Guidance Card
                    headerOverviewCard
                    
                    if miningResult.totalTradesAnalyzed < 5 {
                        // Empty State: Not enough trade data
                        AppCard {
                            AppEmptyState(
                                icon: "shield.checkerboard",
                                title: "Insufficient Trade History",
                                message: "TraderBehaviorMiningEngine requires at least 5 closed trades to accurately detect behavioral vulnerabilities. Currently analyzed: \(miningResult.totalTradesAnalyzed) trades across all accounts."
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
                                
                                Text("Across \(miningResult.totalTradesAnalyzed) analyzed trades across all accounts, no statistically significant revenge trading, toxic hours, or asymmetric risk habits were detected.")
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
                        
                        if let ot = miningResult.overtradingLeakEn {
                            leakCard(
                                title: "Overtrading & Session Fatigue",
                                icon: "arrow.triangle.swap",
                                badgeText: "High Frequency",
                                badgeVariant: .loss,
                                description: ot,
                                recommendation: "Cap daily executions at 3 trades. Cease trading when intraday target or loss threshold is reached."
                            )
                        }
                        
                        if let sl = miningResult.movingOrNoStopLossLeakEn {
                            leakCard(
                                title: "Stop Loss Discipline Breach",
                                icon: "shield.slash.fill",
                                badgeText: "Undefined Risk",
                                badgeVariant: .loss,
                                description: sl,
                                recommendation: "Always set Stop Loss at order placement. Never widen or remove Stop Loss while holding drawdown."
                            )
                        }
                        
                        if let st = miningResult.streakTiltLeakEn {
                            leakCard(
                                title: "Losing Streak Tilt",
                                icon: "exclamationmark.octagon.fill",
                                badgeText: "Tilt Vulnerability",
                                badgeVariant: .loss,
                                description: st,
                                recommendation: "Mandatory walk-away protocol: Halt all trading for the day after 2-3 consecutive losses."
                            )
                        }
                        
                        if let sz = miningResult.positionSizingLeakEn {
                            leakCard(
                                title: "Impulse Sizing & Martingale",
                                icon: "scalemass.fill",
                                badgeText: "Sizing Spike",
                                badgeVariant: .loss,
                                description: sz,
                                recommendation: "Strictly adhere to fixed % risk per trade. Never increase lot size to revenge-recover past losses."
                            )
                        }
                        
                        if let wk = miningResult.weekendHoldingLeakEn {
                            leakCard(
                                title: "Weekend Holding Risk",
                                icon: "calendar.badge.exclamationmark",
                                badgeText: "Gap Exposure",
                                badgeVariant: .loss,
                                description: wk,
                                recommendation: "Close all day trades before Friday market close to prevent adverse opening price gaps."
                            )
                        }
                        
                        if let fm = miningResult.fomoChasingLeakEn {
                            leakCard(
                                title: "FOMO & Chased Entries",
                                icon: "bolt.fill",
                                badgeText: "Late Entry",
                                badgeVariant: .loss,
                                description: fm,
                                recommendation: "Wait for market structure pullbacks to key levels. Never buy green expansion candles or chase missed moves."
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
