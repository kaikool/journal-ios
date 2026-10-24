import SwiftUI

// MARK: - AI Trader Reflection View (100% English UI)
// Integrates 11 specialized templates, structured visual Markdown results, and 1-tap Notebook saving
public struct AIReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedCategory: AIReflectionCategory = .all
    @State private var selectedTemplate: AIReflectionTemplate = AIReflectionTemplates.all[0]
    @State private var userPrompt: String = ""
    @State private var reflectionResult: String = ""
    @State private var isLoading: Bool = false
    @State private var showCustomAsk: Bool = false
    
    public init() {}
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: dataStore.filteredTrades)
    }
    
    private var edgeScore: Double? {
        EdgeScoreEngine.computeEdgeScore(metrics: metrics).score
    }
    
    private var filteredTemplates: [AIReflectionTemplate] {
        if selectedCategory == .all {
            return AIReflectionTemplates.all
        }
        return AIReflectionTemplates.all.filter { $0.category == selectedCategory }
    }
    
    private var languageName: String {
        dataStore.aiSettings.language == "vi" ? "Vietnamese" : "English"
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. Header Information Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppColors.brand)
                                Text("AI Trader Reflection")
                                    .font(AppTypography.headline)
                                Spacer()
                                Text("\(dataStore.aiSettings.provider.uppercased()) • \(languageName)")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Text("Objective, data-grounded performance coaching tailored to your trading journal. Response delivered in \(languageName).")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    // 2. Category Selector Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AIReflectionCategory.allCases) { cat in
                                Button(action: {
                                    selectedCategory = cat
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon)
                                            .font(.caption2)
                                        Text(cat.rawValue)
                                            .font(AppTypography.captionBold)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == cat ? AppColors.brand : AppColors.surface)
                                    .foregroundColor(selectedCategory == cat ? AppColors.brandTextOnDark : AppColors.primaryText)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(selectedCategory == cat ? AppColors.brand : AppColors.border, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    
                    // 3. Template Cards Carousel / List
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Specialized Coaching Templates")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Button(action: {
                                showCustomAsk.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showCustomAsk ? "chevron.up" : "questionmark.bubble")
                                    Text(showCustomAsk ? "Hide Custom Ask" : "Ask Custom Question")
                                }
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.brand)
                            }
                        }
                        
                        // Custom Ask Section if toggled
                        if showCustomAsk {
                            AppCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Free-form Journal Inquiry")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    
                                    HStack {
                                        TextField("e.g. Which pair costs me the most on Thursdays?", text: $userPrompt)
                                            .font(AppTypography.inputText)
                                            .textFieldStyle(.roundedBorder)
                                        
                                        Button("Ask") {
                                            executeCustomPrompt()
                                        }
                                        .font(AppTypography.captionBold)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(AppColors.brand)
                                        .foregroundColor(AppColors.brandTextOnDark)
                                        .cornerRadius(8)
                                        .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                                    }
                                }
                            }
                        }
                        
                        // Templates Horizontal Scroll
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(filteredTemplates) { t in
                                    templateCard(t)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    
                    // 4. Loading State Card
                    if isLoading {
                        AppCard {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.brand))
                                Text("Analyzing trade metrics and generating structured reflection...")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        }
                    }
                    // 5. Rich Result Card
                    else if !reflectionResult.isEmpty {
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
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
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
        .onAppear {
            if reflectionResult.isEmpty {
                executeTemplate(selectedTemplate)
            }
        }
    }
    
    // MARK: - Template Chip Card
    private func templateCard(_ t: AIReflectionTemplate) -> some View {
        let isSelected = selectedTemplate.id == t.id
        return Button(action: {
            selectedTemplate = t
            executeTemplate(t)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: t.icon)
                        .font(.subheadline)
                        .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.brand)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.brandTextOnDark)
                    }
                }
                
                Text(t.title)
                    .font(AppTypography.bodyBold)
                    .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.primaryText)
                    .lineLimit(1)
                
                Text(t.subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(isSelected ? AppColors.brandTextOnDark.opacity(0.85) : AppColors.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 220, height: 105, alignment: .topLeading)
            .background(isSelected ? AppColors.brand : AppColors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppColors.brand : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        
        Task {
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: query,
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
