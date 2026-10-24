import SwiftUI

// MARK: - AI Trader Reflection View (Apple HIG Standard)
// Clean, simple performance coaching interface with rich trade data injection and 1-tap Notebook saving
public struct AIReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedTemplate: AIReflectionTemplate = AIReflectionTemplates.all[0]
    @State private var userPrompt: String = ""
    @State private var reflectionResult: String = ""
    @State private var isLoading: Bool = false
    
    public init() {}
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: dataStore.filteredTrades)
    }
    
    private var edgeScore: Double? {
        EdgeScoreEngine.computeEdgeScore(metrics: metrics).score
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    
                    // 1. Data Scope Header Badge
                    scopeHeaderBadge
                    
                    // 2. Streamlined Topic Chips
                    topicChipsSelector
                    
                    // 3. Compact Inquiry Input Bar
                    customInquiryBar
                    
                    // 4. Unified Result Document Card or Placeholder
                    if !reflectionResult.isEmpty {
                        AIReflectionResultView(
                            resultText: reflectionResult,
                            template: selectedTemplate,
                            metrics: metrics,
                            edgeScore: edgeScore,
                            language: dataStore.aiSettings.language,
                            onRegenerate: {
                                executeTemplate(selectedTemplate)
                            }
                        )
                    } else if !isLoading {
                        emptyStateCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("AI Trader Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.bodyBold)
                    .foregroundColor(AppColors.brand)
                }
            }
        }
        .tradeJournalLoading(
            isLoading,
            message: "Analyzing trade metrics and generating reflection...",
            size: 64
        )
        .onAppear {
            if reflectionResult.isEmpty {
                executeTemplate(selectedTemplate)
            }
        }
    }
    
    // MARK: - 1. Data Scope Header Badge
    private var scopeHeaderBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(AppColors.brand)
                .font(.system(size: 13, weight: .semibold))
            
            Text(scopeSummaryText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
    }
    
    private var scopeSummaryText: String {
        let count = metrics.totalTrades
        let wr = String(format: "%.2f%%", (metrics.winRate ?? 0) * 100)
        let pnl = metrics.netPnl
        let pnlVal = NSDecimalNumber(decimal: pnl).doubleValue
        let pnlStr = (pnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
        return "\(count) Trades Analyzed • WR: \(wr) • P&L: \(pnlStr)"
    }
    
    // MARK: - 2. Streamlined Topic Chips
    private var topicChipsSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AIReflectionTemplates.all) { t in
                    let isSelected = selectedTemplate.id == t.id
                    Button(action: {
                        selectedTemplate = t
                        executeTemplate(t)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(t.title)
                                .font(AppTypography.captionBold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? AppColors.brand : AppColors.surface)
                        .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.primaryText)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isSelected ? AppColors.brand : AppColors.border, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    // MARK: - 3. Compact Inquiry Input Bar
    private var customInquiryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundColor(AppColors.secondaryText)
                .font(.system(size: 14))
                .padding(.leading, 10)
            
            TextField("Ask custom question about your trades...", text: $userPrompt)
                .font(AppTypography.inputText)
                .foregroundColor(AppColors.primaryText)
                .padding(.vertical, 8)
            
            if !userPrompt.isEmpty {
                Button(action: { userPrompt = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.system(size: 14))
                }
            }
            
            Button(action: executeCustomPrompt) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
            }
            .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 0.8)
        )
    }
    
    // MARK: - Empty State Placeholder
    private var emptyStateCard: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.brand)
                Text("Select a topic above or ask a question to generate an AI reflection.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }
    
    // MARK: - Execution Handlers
    private func executeTemplate(_ t: AIReflectionTemplate) {
        isLoading = true
        let prompt = AIReflectionTemplates.buildTemplatePrompt(
            template: t,
            metrics: metrics,
            edgeScore: edgeScore,
            trades: dataStore.filteredTrades,
            language: dataStore.aiSettings.language
        )
        
        Task {
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: t.action,
                    prompt: prompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: dataStore.aiSettings.language
                )
                await MainActor.run {
                    self.reflectionResult = response
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.reflectionResult = "⚠️ [AI Reflection Notice: \(error.localizedDescription)]"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func executeCustomPrompt() {
        guard !userPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        let query = userPrompt
        
        // Build rich trader trades context so custom inquiry can analyze specific symbols & trades
        let recentSummary = AIReflectionTemplates.buildRecentTradesSnippet(trades: dataStore.filteredTrades, limit: 12)
        let fullCustomPrompt = """
        USER CUSTOM INQUIRY:
        "\(query)"
        
        RECENT TRADES IN JOURNAL:
        \(recentSummary)
        
        TASK:
        Answer the trader's specific question directly using the actual performance figures and real trade details provided above. Cite specific symbols, prices, and outcomes.
        """
        
        Task {
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: fullCustomPrompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: dataStore.aiSettings.language
                )
                await MainActor.run {
                    self.reflectionResult = response
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.reflectionResult = "⚠️ [AI Reflection Notice: \(error.localizedDescription)]"
                    self.isLoading = false
                }
            }
        }
    }
}
