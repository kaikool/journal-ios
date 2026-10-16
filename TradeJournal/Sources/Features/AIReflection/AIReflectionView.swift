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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(AppColors.accent)
                                Text("AI Trader Reflection")
                                    .font(AppTypography.headline)
                            }
                            Text("Phân tích khách quan dựa trên 100% dữ liệu nhật ký giao dịch thực tế của bạn. Không suy đoán, không sáo rỗng.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 8) {
                        actionButton(title: "Tổng kết Recap", icon: "doc.text.magnifyingglass", action: .recap)
                        actionButton(title: "Nhận xét Critique", icon: "brain.head.profile", action: .critique)
                        actionButton(title: "Hỏi đáp Ask", icon: "questionmark.bubble", action: .ask)
                    }
                    
                    // Input if Ask is selected
                    if selectedAction == .ask {
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Đặt câu hỏi cho AI")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                HStack {
                                    TextField("VD: Lỗi nào khiến tôi thua lỗ nhiều nhất?", text: $userPrompt)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button("Gửi") {
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
                                Text("Đang phân tích dữ liệu hiệu suất...")
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
                                        .foregroundColor(AppColors.accent)
                                    Text("Phản hồi từ Huấn luyện viên")
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
                .padding()
            }
            .navigationTitle("AI Reflection")
            .background(AppColors.background)
            .onAppear {
                if reflectionResult.isEmpty {
                    executeReflection()
                }
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
            .background(selectedAction == action ? AppColors.accent : AppColors.secondaryBackground)
            .foregroundColor(selectedAction == action ? .white : AppColors.primaryText)
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
                    self.reflectionResult = "Lỗi khi tạo phản hồi AI: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
