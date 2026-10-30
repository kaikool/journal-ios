import SwiftUI

// MARK: - AI Settings View (Apple HIG Inset-Grouped Standard)
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "gemini"
    @State private var model: String = "gemini-3.5-flash-lite"
    @State private var language: String = "en"
    
    @State private var showTraderProfileSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    
    public init() {}
    
    private var isProviderConfigured: Bool {
        switch provider {
        case "gemini":
            return !AiSettingsConfig.defaultGeminiKey.isEmpty
        case "groq":
            return !AiSettingsConfig.defaultGroqKey.isEmpty
        case "openrouter":
            return !AiSettingsConfig.defaultOpenRouterKey.isEmpty
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
            // Card 1: AI Engine
            SettingsCard(title: "AI Engine", footer: "Powers automated trade journaling, reflection, and playbook audit.") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isProviderConfigured ? AppColors.profit : AppColors.secondaryText)
                                .frame(width: 7, height: 7)
                            Text(isProviderConfigured ? "Connected" : "Not configured")
                                .font(AppTypography.captionBold)
                                .foregroundColor(isProviderConfigured ? AppColors.profit : AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTesting) {
                            testConnection()
                        }
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // Provider Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
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
                        Text("Response Language")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Response Language", selection: $language) {
                            Text("English").tag("en")
                            Text("Vietnamese").tag("vi")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: language) { _ in
                            saveSettings()
                        }
                    }
                    
                    // Secret Resolution Status Indicator
                    HStack(spacing: 6) {
                        Image(systemName: isProviderConfigured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isProviderConfigured ? AppColors.profit : AppColors.loss)
                        Text(isProviderConfigured ? "API Key auto-configured from GitHub Secrets" : "API Key missing in secrets")
                            .font(AppTypography.caption)
                            .foregroundColor(isProviderConfigured ? AppColors.secondaryText : AppColors.loss)
                    }
                    .padding(.top, 2)
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(isError ? AppColors.loss : AppColors.profit)
                    }
                }
            }
            
            // Card 2: Trader Profile
            SettingsCard(title: "Trader Profile", footer: "Customize trading style, risk limits, and behavioral rules for AI audits.") {
                Button(action: { showTraderProfileSheet = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Style & Discipline Rules")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            let prof = dataStore.aiSettings.traderProfile
                            Text("\(prof.tradingStyle.isEmpty ? "Standard" : prof.tradingStyle) • Max risk \(prof.maxRiskPerTrade.isEmpty ? "1%" : prof.maxRiskPerTrade)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
        language = conf.language.isEmpty ? "en" : conf.language
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
        statusMessage = "Pinging AI Engine..."
        isError = false
        
        var draft = dataStore.aiSettings
        draft.provider = provider
        draft.model = model.trimmingCharacters(in: .whitespaces)
        if provider == "gemini" && draft.geminiKey.isEmpty {
            draft.geminiKey = AiSettingsConfig.defaultGeminiKey
        } else if provider == "groq" && draft.groqKey.isEmpty {
            draft.groqKey = AiSettingsConfig.defaultGroqKey
        } else if provider == "openrouter" && draft.openrouterKey.isEmpty {
            draft.openrouterKey = AiSettingsConfig.defaultOpenRouterKey
        }
        
        Task {
            do {
                let testOutput = try await AIReflectionService.shared.testConnection(config: draft)
                await MainActor.run {
                    self.isTesting = false
                    self.isError = false
                    self.statusMessage = "Connected: \(testOutput.prefix(60))"
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isError = true
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
