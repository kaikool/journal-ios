import SwiftUI
import UIKit

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
    @State private var selectedTemplate: AIReflectionTemplate = AIReflectionTemplates.defaultTemplate
    @State private var reflectionResult: String = ""
    @State private var isLoading: Bool = false
    @State private var showTraderProfileSheet: Bool = false
    @State private var showPreTradeSheet: Bool = false
    @State private var showMemoryManagementSheet: Bool = false
    @State private var showResearchWorkspaceSheet: Bool = false
    @State private var selectedChartImage: UIImage? = nil
    @State private var showPhotoPicker: Bool = false
    
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
                    AIReflectionScopeHeader(activeAccountName: activeAccountName, metrics: metrics)
                    
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
                        // 2B. AI Intelligence Hub (Long-term Memory & Research Lab)
                        AIReflectionIntelligenceCards(
                            memoryCount: AIAdvisorMemoryEngine.shared.allMemories.count,
                            projectCount: AIResearchWorkspaceEngine.shared.getActiveProjects().count,
                            onOpenMemory: { showMemoryManagementSheet = true },
                            onOpenResearch: { showResearchWorkspaceSheet = true }
                        )
                        
                        // 2C. Pre-Trade Forward-Looking Bias Card
                        AIReflectionPreTradeBanner(onOpenPreTrade: { showPreTradeSheet = true })
                        
                        // 3. Custom Inquiry Input Bar (Always available to type questions + optional chart image)
                        AIReflectionCustomInquiryCard(
                            userPrompt: $userPrompt,
                            selectedChartImage: $selectedChartImage,
                            isLoading: isLoading,
                            onOpenTraderProfile: { showTraderProfileSheet = true },
                            onAttachPhoto: { showPhotoPicker = true },
                            onSubmit: { query in
                                executeCustomPrompt(query)
                            }
                        )
                        
                        // 4. Category Filter Chips
                        AIReflectionCategoryChips(selectedCategory: $selectedCategory)
                        
                        // 5. List of Pre-configured Questions
                        AIReflectionQuestionsCatalog(templates: filteredTemplates) { t in
                            selectedTemplate = t
                            executeTemplate(t)
                        }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(AppColors.secondaryBackground.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showTraderProfileSheet) {
                TraderProfileSheet()
            }
            .sheet(isPresented: $showPreTradeSheet) {
                PreTradeAnalysisSheet()
            }
            .sheet(isPresented: $showMemoryManagementSheet) {
                AIMemoryManagementSheet()
            }
            .sheet(isPresented: $showResearchWorkspaceSheet) {
                AIResearchWorkspaceSheet()
            }
            .sheet(isPresented: $showPhotoPicker) {
                UIKitImagePicker(isPresented: $showPhotoPicker) { data, _ in
                    if let img = UIImage(data: data) {
                        self.selectedChartImage = img
                    }
                }
            }
        }
        .tradeJournalLoading(isLoading, size: 64)
    }
    
    // MARK: - Back to Questions Bar
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
    
    // MARK: - Template Filtering
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
    
    // MARK: - Execution Handlers
    private func executeTemplate(_ t: AIReflectionTemplate) {
        if t.id == "pre_trade_market_bias" {
            self.showPreTradeSheet = true
            return
        }
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
                    self.reflectionResult = "⚠️ [Risk AI Notice: \(error.localizedDescription)]"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func executeCustomPrompt(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        let currentTimeStr = df.string(from: Date())
        
        let recentSummary = AIReflectionTemplates.buildRecentTradesSnippet(trades: accountTrades, limit: 12)
        let chartNote = selectedChartImage != nil ? "\nNOTE: Trader has attached a chart screenshot for this question. Analyze the candlestick structure, liquidity, support/resistance, and patterns in the image to answer accurately." : ""
        let fullCustomPrompt = """
        ACTIVE ACCOUNT: \(activeAccountName)
        CURRENT SYSTEM TIME: \(currentTimeStr)
        
        USER CUSTOM INQUIRY:
        "\(query)"\(chartNote)
        
        RECENT TRADES IN ACTIVE ACCOUNT:
        \(recentSummary)
        
        TASK:
        Answer the trader's specific question directly with critical objectivity as Risk AI. Format your answer with clean sections using '### 1. ...', '### 2. ...' with NO emoji spam. Validate market structure, liquidity pools, S/R, and their declared Trader Profile. Cite specific symbols, prices, and outcomes.
        """
        
        let chartBase64 = selectedChartImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        
        Task {
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: fullCustomPrompt,
                    metrics: metrics,
                    edgeScore: edgeScore,
                    language: dataStore.aiSettings.language,
                    chartImageBase64: chartBase64
                )
                await MainActor.run {
                    self.reflectionResult = response
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.reflectionResult = "⚠️ [Risk AI Notice: \(error.localizedDescription)]"
                    self.isLoading = false
                }
            }
        }
    }
}
