import SwiftUI

// MARK: - 6. AI Engine Settings View
// Clean Apple HIG settings view supporting Groq, OpenRouter, Google Gemini, OpenAI, and Custom endpoints.
// Persistent Trader Profile is accessed via dedicated TraderProfileSheet to keep concerns strictly separated.
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "groq"
    @State private var model: String = "qwen/qwen3.8-27b"
    @State private var language: String = "vi"
    @State private var apiKey: String = ""
    @State private var groqBackupKey: String = ""
    @State private var customEndpoint: String = ""
    
    @State private var showTraderProfileSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    @State private var isSaved: Bool = false
    
    public init() {}
    
    private var providerDisplayName: String {
        switch provider {
        case "groq": return "Groq (Free & Fast)"
        case "openrouter": return "OpenRouter (Free Models)"
        case "gemini": return "Google Gemini"
        case "openai": return "OpenAI"
        case "custom": return "Custom / Azure"
        default: return provider.capitalized
        }
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Card 1: AI Provider & Engine
            SettingsCard(title: "AI Engine Configuration") {
                VStack(alignment: .leading, spacing: 14) {
                    // Provider Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppleMenuChip(title: "Provider", selectionText: providerDisplayName, icon: "cpu") {
                            Button("Groq (Free & Fast)") { selectProvider("groq") }
                            Button("OpenRouter (Free Models)") { selectProvider("openrouter") }
                            Button("Google Gemini") { selectProvider("gemini") }
                            Button("OpenAI") { selectProvider("openai") }
                            Button("Custom / Azure") { selectProvider("custom") }
                        }
                    }
                    
                    // Response Language Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Response Language")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Language", selection: $language) {
                            Text("Vietnamese").tag("vi")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: language) {
                            isSaved = false
                            statusMessage = ""
                        }
                    }
                    
                    // Optional API Key
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key (Optional - Built-in key active)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        SecureField("Optional custom key...", text: $apiKey)
                            .font(AppTypography.inputText)
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: apiKey) {
                                isSaved = false
                                statusMessage = ""
                            }
                    }
                    
                    if provider == "groq" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Backup Groq API Key (Auto-Failover)")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            SecureField("Enter secondary Groq token (gsk_...)", text: $groqBackupKey)
                                .font(AppTypography.inputText)
                                .padding(10)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onChange(of: groqBackupKey) {
                                    isSaved = false
                                    statusMessage = ""
                                }
                            
                            Text("Automatically utilized if primary key encounters rate limits (HTTP 429) or expires.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        }
                    }
                    
                    if provider == "custom" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Endpoint URL")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            TextField("https://...", text: $customEndpoint)
                                .font(AppTypography.inputText)
                                .padding(10)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                    }
                }
            }
            
            // Card 2: Trader Profile & Memory Navigation
            SettingsCard(title: "Trader Profile & Context Memory") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Risk AI enforces your Trader Profile to evaluate thesis validity, risk budget compliance, and behavioral leaks.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineSpacing(2)
                    
                    Button(action: { showTraderProfileSheet = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Edit Trader Profile & Rules")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                let prof = dataStore.aiSettings.traderProfile
                                Text("\(prof.tradingStyle) • Max Risk \(prof.maxRiskPerTrade)")
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
            
            // Clean Bottom Action Row
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    AppButton("Save settings", icon: "checkmark", style: .primary, size: .compact) {
                        saveSettings()
                    }
                    
                    AppButton("Test connection", icon: "network", style: .secondary, size: .compact, isLoading: isTesting) {
                        testConnection()
                    }
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(isError ? AppColors.loss : AppColors.profit)
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
        isSaved = false
        statusMessage = ""
        isError = false
        
        let conf = dataStore.aiSettings
        switch newProvider {
        case "groq":
            apiKey = conf.groqKey
            model = "qwen/qwen3.8-27b"
        case "openrouter":
            apiKey = conf.openrouterKey
            model = "nvidia/nemotron-3.5-super-vl:free"
        case "gemini":
            apiKey = conf.geminiKey
            model = "gemini-3.5-flash-lite"
        case "openai":
            apiKey = conf.openaiKey
            model = "gpt-4o-mini"
        case "custom":
            apiKey = conf.customKey
            customEndpoint = conf.customEndpoint
        groqBackupKey = conf.groqBackupKey
        default:
            break
        }
    }
    
    private func loadCurrentSettings() {
        let conf = dataStore.aiSettings
        provider = conf.provider.isEmpty ? "groq" : conf.provider
        model = conf.model.isEmpty ? "qwen/qwen3.8-27b" : conf.model
        language = conf.language.isEmpty ? "vi" : conf.language
        customEndpoint = conf.customEndpoint
        groqBackupKey = conf.groqBackupKey
        
        switch provider {
        case "groq": apiKey = conf.groqKey
        case "openrouter": apiKey = conf.openrouterKey
        case "gemini": apiKey = conf.geminiKey
        case "openai": apiKey = conf.openaiKey
        case "custom": apiKey = conf.customKey
        default: apiKey = ""
        }
        
        isSaved = false
        statusMessage = ""
        isError = false
    }
    
    private func saveSettings() {
        var conf = dataStore.aiSettings
        conf.provider = provider
        conf.model = model.trimmingCharacters(in: .whitespaces)
        conf.language = language
        
        switch provider {
        case "groq":
            conf.groqKey = apiKey.trimmingCharacters(in: .whitespaces)
            conf.groqBackupKey = groqBackupKey.trimmingCharacters(in: .whitespaces)
        case "openrouter":
            conf.openrouterKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "gemini":
            conf.geminiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "openai":
            conf.openaiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "custom":
            conf.customKey = apiKey.trimmingCharacters(in: .whitespaces)
            conf.customEndpoint = customEndpoint.trimmingCharacters(in: .whitespaces)
        default:
            break
        }
        
        dataStore.aiSettings = conf
        dataStore.saveToDisk()
        
        isSaved = true
        isError = false
        statusMessage = "AI engine settings saved successfully."
    }
    
    private func testConnection() {
        isTesting = true
        statusMessage = "Testing connection..."
        isError = false
        
        var draft = dataStore.aiSettings
        draft.provider = provider
        draft.model = model.trimmingCharacters(in: .whitespaces)
        
        switch provider {
        case "groq":
            draft.groqKey = apiKey.trimmingCharacters(in: .whitespaces)
            draft.groqBackupKey = groqBackupKey.trimmingCharacters(in: .whitespaces)
        case "openrouter":
            draft.openrouterKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "gemini":
            draft.geminiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "openai":
            draft.openaiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "custom":
            draft.customKey = apiKey.trimmingCharacters(in: .whitespaces)
            draft.customEndpoint = customEndpoint.trimmingCharacters(in: .whitespaces)
        default:
            break
        }
        
        Task {
            do {
                let testOutput = try await AIReflectionService.shared.testConnection(config: draft)
                await MainActor.run {
                    self.isTesting = false
                    self.isError = false
                    self.statusMessage = "Connected: \(testOutput.prefix(80))"
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isError = true
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }
}
