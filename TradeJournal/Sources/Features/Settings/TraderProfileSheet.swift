import SwiftUI
import UIKit

// MARK: - Dedicated Trader Profile & Discipline Configuration Sheet
// Pure trading methodology, risk parameters, and behavioral memory in English.
// Completely separated from technical AI provider / API keys settings.
public struct TraderProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var tradingStyle: String = ""
    @State private var accountObjective: String = ""
    @State private var primaryPlaybooks: String = ""
    @State private var maxRiskPerTrade: String = ""
    @State private var maxDailyLossPercentText: String = ""
    @State private var targetRiskRewardRatioText: String = ""
    @State private var knownPsychologicalLeaks: String = ""
    @State private var customMemoryNotes: String = ""
    
    @State private var showSavedToast: Bool = false
    @State private var showBehaviorLeaksSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Guidance Card
                    headerGuidanceCard
                    
                    // Card 1: Trading Style & Playbooks
                    styleAndPlaybooksCard
                    
                    // Card 2: Risk Budget & Objectives
                    riskAndObjectivesCard
                    
                    // Card 3: Behavioral Leaks & Non-Negotiable Rules
                    psychologyAndRulesCard
                    
                    // Save Button
                    saveButtonSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 32)
            }
            .background(AppColors.background)
            .navigationTitle("Trader Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save") {
                        saveProfile()
                    }
                }
            }
            .onAppear {
                loadProfile()
            }
            .sheet(isPresented: $showBehaviorLeaksSheet) {
                TraderBehavioralLeaksSheet()
            }
        }
    }
    
    // MARK: - 1. Header Guidance Card
    private var headerGuidanceCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.text.rectangle")
                    .font(AppTypography.displayMedium)
                    .foregroundColor(AppColors.brand)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trader Profile & Discipline Rules")
                        .font(AppTypography.cardHeader)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Risk AI enforces these parameters when auditing trade thesis, sizing limits, and behavioral compliance.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 2. Style & Playbooks Card
    private var styleAndPlaybooksCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Methodology & playbooks", icon: "chart.line.uptrend.xyaxis")
                
                // Trading Style
                VStack(alignment: .leading, spacing: 6) {
                    AppFormField(
                        "Trading Style & Timeframe",
                        text: $tradingStyle,
                        placeholder: "e.g. Day Trader / Scalper (M5, M15, H1)",
                        height: 42
                    )
                    
                    // Quick Preset Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            presetStyleChip("Day Trader (M15)")
                            presetStyleChip("Scalper (M1-M5)")
                            presetStyleChip("Swing Trader (H4-D1)")
                        }
                    }
                    .padding(.top, 2)
                }
                
                // Primary Playbooks
                AppFormField(
                    "Primary Playbooks & Technical Setups",
                    text: $primaryPlaybooks,
                    placeholder: "e.g. Price Action, Support & Resistance, Liquidity Sweeps, FVG",
                    height: 42
                )
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 3. Risk & Objectives Card
    private var riskAndObjectivesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Risk budget & account targets", icon: "shield")
                
                // Max Risk per Trade
                VStack(alignment: .leading, spacing: 6) {
                    AppFormField(
                        "Maximum Risk Per Trade",
                        text: $maxRiskPerTrade,
                        placeholder: "e.g. 0.5% - 1.0% per trade (Strict Stop Loss)",
                        height: 42
                    )
                    
                    // Quick Risk Chips
                    HStack(spacing: 6) {
                        presetRiskChip("0.5% / trade")
                        presetRiskChip("1.0% / trade")
                        presetRiskChip("1.5% / trade")
                    }
                    .padding(.top, 2)
                }
                
                // Maximum Daily Loss Limit (%)
                AppFormField(
                    "Maximum Daily Loss Limit (%)",
                    text: $maxDailyLossPercentText,
                    placeholder: "e.g. 3.0 (Trading halts when daily loss is breached)",
                    height: 42
                )
                
                // Target Risk:Reward Ratio
                AppFormField(
                    "Target Risk:Reward Ratio",
                    text: $targetRiskRewardRatioText,
                    placeholder: "e.g. 2.0 (for 1:2 R:R) or 1.5, 3.0",
                    height: 42
                )
                
                // Account Objective
                AppFormField(
                    "Account Objective & Max Drawdown",
                    text: $accountObjective,
                    placeholder: "e.g. The5ers 100K High Stakes (Max 5% Daily Loss)",
                    height: 42
                )
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 4. Psychology & Rules Card
    private var psychologyAndRulesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Psychological leaks & non-negotiables", icon: "exclamationmark.triangle")
                
                // Known Psychological Leaks
                VStack(alignment: .leading, spacing: 6) {
                    AppFormField(
                        "Known Behavioral Leaks & Biases",
                        text: $knownPsychologicalLeaks,
                        placeholder: "e.g. Widening Stop Loss, Premature Profit Taking, FOMO re-entry",
                        height: 42
                    )
                    
                    HStack {
                        Spacer()
                        AppActionPill("Mine Historical Leaks", icon: "sparkles") {
                            showBehaviorLeaksSheet = true
                        }
                    }
                }
                
                // Custom Memory Directives
                VStack(alignment: .leading, spacing: 6) {
                    Text("Non-Negotiable Operational Rules")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    AppTextField("e.g. Minimum 2:1 R:R. Stop trading after 2 consecutive losses.", text: $customMemoryNotes)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 5. Save Button Section
    private var saveButtonSection: some View {
        VStack(spacing: 8) {
            AppPrimaryButton(
                showSavedToast ? "Profile Saved" : "Save Profile",
                icon: showSavedToast ? "checkmark" : "square.and.arrow.down",
                fullWidth: true,
                height: 42
            ) {
                guard !showSavedToast else { return }
                saveProfile()
            }
        }
    }
    
    // MARK: - Helper UI Builders
    private func presetStyleChip(_ style: String) -> some View {
        AppFilterChip(style, isSelected: tradingStyle == style) {
            tradingStyle = style
        }
    }
    
    private func presetRiskChip(_ risk: String) -> some View {
        AppFilterChip(risk, isSelected: maxRiskPerTrade == risk) {
            maxRiskPerTrade = risk
        }
    }
    
    // MARK: - Data Handlers
    private func loadProfile() {
        let prof = dataStore.aiSettings.traderProfile
        tradingStyle = prof.tradingStyle
        accountObjective = prof.accountObjective
        primaryPlaybooks = prof.primaryPlaybooks
        maxRiskPerTrade = prof.maxRiskPerTrade
        maxDailyLossPercentText = String(format: "%.1f", prof.maxDailyLossPercent)
        targetRiskRewardRatioText = String(format: "%.1f", prof.targetRiskRewardRatio)
        knownPsychologicalLeaks = prof.knownPsychologicalLeaks
        customMemoryNotes = prof.customMemoryNotes
    }
    
    private func saveProfile() {
        var conf = dataStore.aiSettings
        let cleanDaily = maxDailyLossPercentText.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        let parsedDailyLoss = Double(cleanDaily) ?? 3.0
        
        let cleanRR = targetRiskRewardRatioText.replacingOccurrences(of: "1:", with: "").trimmingCharacters(in: .whitespaces)
        let parsedRR = Double(cleanRR) ?? 2.0
        
        conf.traderProfile = TraderProfileConfig(
            tradingStyle: tradingStyle.trimmingCharacters(in: .whitespaces),
            accountObjective: accountObjective.trimmingCharacters(in: .whitespaces),
            primaryPlaybooks: primaryPlaybooks.trimmingCharacters(in: .whitespaces),
            maxRiskPerTrade: maxRiskPerTrade.trimmingCharacters(in: .whitespaces),
            maxDailyLossPercent: parsedDailyLoss,
            targetRiskRewardRatio: parsedRR,
            knownPsychologicalLeaks: knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces),
            customMemoryNotes: customMemoryNotes.trimmingCharacters(in: .whitespaces)
        )
        dataStore.aiSettings = conf
        dataStore.saveToDisk()
        
        NativeHaptics.success()
        
        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSavedToast = false
            dismiss()
        }
    }
}
