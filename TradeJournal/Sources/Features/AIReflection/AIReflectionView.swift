import SwiftUI

public struct AIReflectionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var userPrompt: String = ""
    @State private var reflectionResult: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedAction: AIReflectionAction = .recap
    
    public init() {}
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: dataStore.filteredTrades)
    }
    
    private var edgeScore: Double? {
        EdgeScoreEngine.computeEdgeScore(metrics: metrics).score
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "AI Trader Reflection",
                showFilters: false
            )
            
            ScrollView {
                VStack(spacing: 12) {
                    // Header Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppColors.brand)
                                Text("AI Trader Reflection")
                                    .font(AppTypography.headline)
                            }
                            Text("Objective feedback grounded 100% in your actual trading journal data. No speculation, no generic advice.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 8) {
                        actionButton(title: "Recap", icon: "doc.text.magnifyingglass", action: .recap)
                        actionButton(title: "Critique", icon: "brain.head.profile", action: .critique)
                        actionButton(title: "Ask Journal", icon: "questionmark.bubble", action: .ask)
                    }
                    
                    // Input if Ask is selected
                    if selectedAction == .ask {
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ask your journal")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                HStack {
                                    TextField("e.g. Which mistake costs me the most money?", text: $userPrompt)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button("Send") {
                                        executeReflection()
                                    }
                                    .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                                }
                            }
                        }
                    }
                    
                    // Reflection Result Card
                    if isLoading {
                        AppCard {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Analyzing trading performance data...")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else if !reflectionResult.isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "quote.opening")
                                        .foregroundColor(AppColors.brand)
                                    Text("Coach Feedback")
                                        .font(AppTypography.headline)
                                    Spacer()
                                }
                                
                                Text(reflectionResult)
                                    .font(AppTypography.body)
                                    .foregroundColor(AppColors.primaryText)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(14)
            }
            .background(AppColors.background)
        }
        .background(AppColors.background)
        .onAppear {
            if reflectionResult.isEmpty {
                executeReflection()
            }
        }
    }
    
    private func actionButton(title: String, icon: String, action: AIReflectionAction) -> some View {
        Button(action: {
            selectedAction = action
            if action != .ask {
                executeReflection()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(AppTypography.captionBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedAction == action ? AppColors.brand : AppColors.secondaryBackground)
            .foregroundColor(selectedAction == action ? AppColors.brandTextOnDark : AppColors.primaryText)
            .cornerRadius(8)
        }
    }
    
    private func executeReflection() {
        isLoading = true
        Task {
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: selectedAction,
                    prompt: userPrompt,
                    metrics: metrics,
                    edgeScore: edgeScore
                )
                await MainActor.run {
                    self.reflectionResult = response
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.reflectionResult = "AI reflection error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
