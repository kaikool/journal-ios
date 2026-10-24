import SwiftUI

// MARK: - AI Trader Reflection View (Apple HIG Standard)
// Questions-first coaching workflow: Displays structured inquiry categories first.
// Only queries the live AI when the user selects a question or submits a custom prompt.
// Strictly scopes analysis to the currently active account.
public struct AIReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedCategory: String = "All"
    @State private var userPrompt: String = ""
    @State private var selectedTemplate: AIReflectionTemplate = AIReflectionTemplates.all[0]
    @State private var reflectionResult: String = ""
    @State private var isLoading: Bool = false
    @State private var showSettingsSheet: Bool = false
    
    public init() {}
    
    // Strictly scoped to trades of the currently selected active account
    private var accountTrades: [Trade] {
        dataStore.filteredTrades
    }
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: accountTrades)
    }
    
    private var edgeScore: Double? {
        EdgeScoreEngine.computeEdgeScore(metrics: metrics).score
    }
    
    private var activeAccountName: String {
        dataStore.selectedAccount?.name ?? "Current Account"
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    
                    // 1. Data Scope Header Badge (Strictly Active Account)
                    scopeHeaderBadge
                    
                    if !reflectionResult.isEmpty {
                        // 2A. Back button to return to Question Catalog
                        backToQuestionsBar
                        
                        // 2B. Unified Result Document Card
                        AIReflectionResultView(
                            resultText: reflectionResult,
                            template: selectedTemplate,
                            metrics: metrics,
                            edgeScore: edgeScore,
                            language: dataStore.aiSettings.language,
                            onRegenerate: {
                                if !userPrompt.isEmpty {
                                    executeCustomPrompt(userPrompt)
                                } else {
                                    executeTemplate(selectedTemplate)
                                }
                            }
                        )
                    } else {
                        // 3. Custom Inquiry Input Bar (Always available to type questions)
                        customInquiryCard
                        
                        // 4. Category Filter Chips
                        categoryChipsSelector
                        
                        // 5. List of Pre-configured Questions
                        questionsCatalogList
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
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.primaryText)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                NavigationStack {
                    AiSettingsView()
                        .navigationTitle("AI Assistant Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettingsSheet = false }
                                    .font(AppTypography.captionBold)
                            }
                        }
                }
            }
        }
        .tradeJournalLoading(isLoading, size: 64)
    }
    
    // MARK: - 1. Active Account Scope Header
    private var scopeHeaderBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "wallet.pass")
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
        return "\(activeAccountName) • \(count) Trades • WR: \(wr) • P&L: \(pnlStr)"
    }
    
    // MARK: - 2A. Back to Questions Bar
    private var backToQuestionsBar: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                reflectionResult = ""
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back to Question List")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(AppColors.secondaryText)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 3. Custom Inquiry Card
    private var customInquiryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(AppColors.brand)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ask Custom Question")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    Button(action: { showSettingsSheet = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.crop.circle.badge.gearshape")
                                .font(.system(size: 11))
                            Text("Trader Profile")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("Enter question or instruction for AI...", text: $userPrompt)
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
                    
                    Button(action: {
                        executeCustomPrompt(userPrompt)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
                    }
                    .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal, 10)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 4. Category Filter Chips
    private var categories: [String] {
        ["All", "Session", "Trade Audit", "Leaks", "Prop Risk", "Sizing"]
    }
    
    private var categoryChipsSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button(action: {
                        selectedCategory = cat
                    }) {
                        Text(cat)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? AppColors.secondaryBackground : Color.clear)
                            .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? AppColors.border : AppColors.border.opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    // MARK: - 5. Questions Catalog List
    private var filteredTemplates: [AIReflectionTemplate] {
        switch selectedCategory {
        case "Session":
            return AIReflectionTemplates.all.filter { $0.category == .cadence }
        case "Trade Audit":
            return AIReflectionTemplates.all.filter { $0.category == .execution }
        case "Leaks":
            return AIReflectionTemplates.all.filter { $0.category == .psychology }
        case "Prop Risk", "Sizing":
            return AIReflectionTemplates.all.filter { $0.category == .risk }
        default:
            return AIReflectionTemplates.all
        }
    }
    
    private var questionsCatalogList: some View {
        VStack(spacing: 10) {
            ForEach(filteredTemplates) { t in
                questionCard(for: t)
            }
        }
    }
    
    private func questionCard(for t: AIReflectionTemplate) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: t.icon)
                        .foregroundColor(AppColors.primaryText)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text(t.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    Button(action: {
                        selectedTemplate = t
                        executeTemplate(t)
                    }) {
                        HStack(spacing: 4) {
                            Text("Analyze")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Text(t.subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTemplate = t
            executeTemplate(t)
        }
    }
    
    // MARK: - Execution Handlers
    private func executeTemplate(_ t: AIReflectionTemplate) {
        isLoading = true
        let prompt = AIReflectionTemplates.buildTemplatePrompt(
            template: t,
            metrics: metrics,
            edgeScore: edgeScore,
            trades: accountTrades,
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
    
    private func executeCustomPrompt(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        
        let recentSummary = AIReflectionTemplates.buildRecentTradesSnippet(trades: accountTrades, limit: 12)
        let fullCustomPrompt = """
        ACTIVE ACCOUNT: \(activeAccountName)
        
        USER CUSTOM INQUIRY:
        "\(query)"
        
        RECENT TRADES IN ACTIVE ACCOUNT:
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
