import SwiftUI

// MARK: - 6. AI Engine Settings View
// Ultra-clean Apple HIG settings view: Status (Đã kết nối / Chưa kết nối), Ping button, Provider & Language pickers.
// All raw API keys are handled securely via GitHub Secrets / Hardware Keychain without cluttering UI.
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "gemini"
    @State private var model: String = "gemini-3.5-flash-lite"
    @State private var language: String = "vi"
    
    @State private var showTraderProfileSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    
    public init() {}
    
    private var isProviderConfigured: Bool {
        switch provider {
        case "gemini":
            return !(KeychainManager.get(forKey: "gemini_api_key") ?? AiSettingsConfig.defaultGeminiKey).isEmpty
        case "groq":
            return !(KeychainManager.get(forKey: "groq_api_key") ?? AiSettingsConfig.defaultGroqKey).isEmpty
        case "openrouter":
            return !(KeychainManager.get(forKey: "openrouter_api_key") ?? AiSettingsConfig.defaultOpenRouterKey).isEmpty
        default:
            return true
        }
    }
    
    private var providerDisplayName: String {
        switch provider {
        case "groq": return "Groq (Fast LPU)"
        case "openrouter": return "OpenRouter"
        case "gemini": return "Google Gemini"
        case "openai": return "OpenAI"
        default: return provider.capitalized
        }
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Card 1: AI Engine & Connection Status
            SettingsCard(title: "AI Engine") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isProviderConfigured ? AppColors.profit : AppColors.secondaryText)
                                .frame(width: 8, height: 8)
                            Text(isProviderConfigured ? "Đã kết nối" : "Chưa kết nối")
                                .font(AppTypography.headline)
                                .foregroundColor(isProviderConfigured ? AppColors.profit : AppColors.secondaryText)
                        }
                        Spacer()
                        AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTesting) {
                            testConnection()
                        }
                    }
                    
                    Divider()
                    
                    // Provider Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhà cung cấp")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppleMenuChip(title: "Provider", selectionText: providerDisplayName, icon: "cpu") {
                            Button("Google Gemini") { selectProvider("gemini") }
                            Button("Groq (Fast LPU)") { selectProvider("groq") }
                            Button("OpenRouter") { selectProvider("openrouter") }
                            Button("OpenAI") { selectProvider("openai") }
                        }
                    }
                    
                    // Response Language Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ngôn ngữ phản hồi")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Language", selection: $language) {
                            Text("Tiếng Việt").tag("vi")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: language) {
                            saveSettings()
                        }
                    }
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(isError ? AppColors.loss : AppColors.profit)
                    }
                }
            }
            
            // Card 2: Trader Profile
            SettingsCard(title: "Hồ sơ Trader") {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: { showTraderProfileSheet = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chỉnh sửa phong cách & Kế hoạch")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                let prof = dataStore.aiSettings.traderProfile
                                Text("\(prof.tradingStyle) • Rủi ro tối đa \(prof.maxRiskPerTrade)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(12)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.5), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showTraderProfileSheet) {
            TraderProfileSheet()
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Actions
    
    private func selectProvider(_ newProvider: String) {
        provider = newProvider
        statusMessage = ""
        isError = false
        
        switch newProvider {
        case "groq":
            model = "qwen/qwen3.8-27b"
        case "openrouter":
            model = "nvidia/nemotron-3.5-super-vl:free"
        case "gemini":
            model = "gemini-3.5-flash-lite"
        case "openai":
            model = "gpt-4o-mini"
        default:
            break
        }
        saveSettings()
    }
    
    private func loadCurrentSettings() {
        let conf = dataStore.aiSettings
        provider = conf.provider.isEmpty ? "gemini" : conf.provider
        model = conf.model.isEmpty ? "gemini-3.5-flash-lite" : conf.model
        language = conf.language.isEmpty ? "vi" : conf.language
        statusMessage = ""
        isError = false
    }
    
    private func saveSettings() {
        var conf = dataStore.aiSettings
        conf.provider = provider
        conf.model = model.trimmingCharacters(in: .whitespaces)
        conf.language = language
        dataStore.aiSettings = conf
        dataStore.saveToDisk()
    }
    
    private func testConnection() {
        isTesting = true
        statusMessage = "Đang ping..."
        isError = false
        
        var draft = dataStore.aiSettings
        draft.provider = provider
        draft.model = model.trimmingCharacters(in: .whitespaces)
        
        Task {
            do {
                let testOutput = try await AIReflectionService.shared.testConnection(config: draft)
                await MainActor.run {
                    self.isTesting = false
                    self.isError = false
                    self.statusMessage = "Đã kết nối: \(testOutput.prefix(60))"
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isError = true
                    self.statusMessage = "Lỗi: \(error.localizedDescription)"
                }
            }
        }
    }
}
