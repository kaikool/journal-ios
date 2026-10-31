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
    @State private var knownPsychologicalLeaks: String = ""
    @State private var customMemoryNotes: String = ""
    
    @State private var showSavedToast: Bool = false
    
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
        }
    }
    
    // MARK: - 1. Header Guidance Card
    private var headerGuidanceCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trader Profile & Discipline Rules")
                        .font(.system(size: 13, weight: .bold))
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
                sectionHeader(title: "METHODOLOGY & PLAYBOOKS", icon: "chart.line.uptrend.xyaxis")
                
                // Trading Style
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trading Style & Timeframe")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. Day Trader / Scalper (M5, M15, H1)", text: $tradingStyle)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                    
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Primary Playbooks & Technical Setups")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. Price Action, Support & Resistance, Liquidity Sweeps, FVG", text: $primaryPlaybooks)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 3. Risk & Objectives Card
    private var riskAndObjectivesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "RISK BUDGET & ACCOUNT TARGETS", icon: "shield")
                
                // Max Risk per Trade
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maximum Risk Per Trade")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. 0.5% - 1.0% per trade (Strict Stop Loss)", text: $maxRiskPerTrade)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                    
                    // Quick Risk Chips
                    HStack(spacing: 6) {
                        presetRiskChip("0.5% / trade")
                        presetRiskChip("1.0% / trade")
                        presetRiskChip("1.5% / trade")
                    }
                    .padding(.top, 2)
                }
                
                // Account Objective
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account Objective & Max Drawdown")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. The5ers 100K High Stakes (Max 5% Daily Loss)", text: $accountObjective)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 4. Psychology & Rules Card
    private var psychologyAndRulesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "PSYCHOLOGICAL LEAKS & NON-NEGOTIABLES", icon: "exclamationmark.triangle")
                
                // Known Psychological Leaks
                VStack(alignment: .leading, spacing: 6) {
                    Text("Known Behavioral Leaks & Biases")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. Widening Stop Loss, Premature Profit Taking, FOMO re-entry", text: $knownPsychologicalLeaks)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                }
                
                // Custom Memory Directives
                VStack(alignment: .leading, spacing: 6) {
                    Text("Non-Negotiable Operational Rules")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    TextField("e.g. Minimum 2:1 R:R. Stop trading after 2 consecutive losses.", text: $customMemoryNotes, axis: .vertical)
                        .lineLimit(3...5)
                        .font(AppTypography.inputText)
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 5. Save Button Section
    private var saveButtonSection: some View {
        VStack(spacing: 8) {
            Button(action: saveProfile) {
                HStack(spacing: 6) {
                    Image(systemName: showSavedToast ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                    Text(showSavedToast ? "Profile Saved" : "Save Profile")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(showSavedToast ? AppColors.profit : AppColors.brand)
                .cornerRadius(10)
            }
            .disabled(showSavedToast)
        }
    }
    
    // MARK: - Helper UI Builders
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.brand)
            
            Text(title)
                .font(AppTypography.cardHeader)
                .foregroundColor(AppColors.secondaryText)
            
            Spacer()
        }
    }
    
    private func presetStyleChip(_ style: String) -> some View {
        Button(action: {
            tradingStyle = style
        }) {
            Text(style)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.secondaryBackground)
                .foregroundColor(tradingStyle == style ? AppColors.brand : AppColors.secondaryText)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(tradingStyle == style ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.4), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
    
    private func presetRiskChip(_ risk: String) -> some View {
        Button(action: {
            maxRiskPerTrade = risk
        }) {
            Text(risk)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.secondaryBackground)
                .foregroundColor(maxRiskPerTrade == risk ? AppColors.brand : AppColors.secondaryText)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(maxRiskPerTrade == risk ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.4), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Data Handlers
    private func loadProfile() {
        let prof = dataStore.aiSettings.traderProfile
        tradingStyle = prof.tradingStyle
        accountObjective = prof.accountObjective
        primaryPlaybooks = prof.primaryPlaybooks
        maxRiskPerTrade = prof.maxRiskPerTrade
        knownPsychologicalLeaks = prof.knownPsychologicalLeaks
        customMemoryNotes = prof.customMemoryNotes
    }
    
    private func saveProfile() {
        var conf = dataStore.aiSettings
        conf.traderProfile = TraderProfileConfig(
            tradingStyle: tradingStyle.trimmingCharacters(in: .whitespaces),
            accountObjective: accountObjective.trimmingCharacters(in: .whitespaces),
            primaryPlaybooks: primaryPlaybooks.trimmingCharacters(in: .whitespaces),
            maxRiskPerTrade: maxRiskPerTrade.trimmingCharacters(in: .whitespaces),
            knownPsychologicalLeaks: knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces),
            customMemoryNotes: customMemoryNotes.trimmingCharacters(in: .whitespaces)
        )
        dataStore.aiSettings = conf
        dataStore.saveToDisk()
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        
        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSavedToast = false
            dismiss()
        }
    }
}
