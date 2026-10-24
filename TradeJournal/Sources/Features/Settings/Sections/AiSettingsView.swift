import SwiftUI

// MARK: - 6. AI Settings View
// Clean Apple HIG settings view supporting Groq, OpenRouter, Google Gemini, OpenAI, and Trader Profile Context Memory
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "groq"
    @State private var model: String = "openai/gpt-oss-120b"
    @State private var language: String = "vi"
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    
    // Trader Profile & Memory
    @State private var tradingStyle: String = ""
    @State private var accountObjective: String = ""
    @State private var primaryPlaybooks: String = ""
    @State private var maxRiskPerTrade: String = ""
    @State private var knownPsychologicalLeaks: String = ""
    @State private var customMemoryNotes: String = ""
    
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
    
    private var providerModels: [String] {
        switch provider {
        case "groq":
            return ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
        case "openrouter":
            return ["openrouter/free", "meta-llama/llama-3.2-3b-instruct:free"]
        case "gemini":
            return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case "openai":
            return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        default:
            return []
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
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: apiKey) {
                                isSaved = false
                                statusMessage = ""
                            }
                    }
                    
                    if provider == "custom" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Endpoint URL")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            TextField("https://...", text: $customEndpoint)
                                .font(AppTypography.inputText)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                    }
                }
            }
            
            // Card 2: Persistent Trader Profile & AI Context Memory
            SettingsCard(title: "Trader Profile & Context Memory") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The AI coach uses this persistent context on every trade review and reflection to tailor psychological, tactical, and risk advice.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trading Style & Timeframe")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. Day Trader / Intraday Scalper (M5, M15)", text: $tradingStyle)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Objective / Prop Firm Target")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. The5ers 100K High Stakes (Max 5% Daily Loss)", text: $accountObjective)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Primary Playbooks & Setups")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. Liquidity Sweeps, Order Blocks, London Breakouts", text: $primaryPlaybooks)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max Risk Budget Per Trade")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. 0.5% - 1.0% ($500 - $1,000)", text: $maxRiskPerTrade)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Known Psychological Pitfalls & Leaks")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. Moving Stop Loss, Early Exit on Winners, FOMO re-entry", text: $knownPsychologicalLeaks)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Coaching Directives & Personal Notes")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("e.g. Strictly demand minimum 2:1 R:R. Stop trading after 2 losses.", text: $customMemoryNotes)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                    }
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
            model = "openai/gpt-oss-120b"
        case "openrouter":
            apiKey = conf.openrouterKey
            model = "openrouter/free"
        case "gemini":
            apiKey = conf.geminiKey
            model = "gemini-2.0-flash"
        case "openai":
            apiKey = conf.openaiKey
            model = "gpt-4o-mini"
        case "custom":
            apiKey = conf.customKey
            customEndpoint = conf.customEndpoint
        default:
            break
        }
    }
    
    private func loadCurrentSettings() {
        let conf = dataStore.aiSettings
        provider = conf.provider.isEmpty ? "groq" : conf.provider
        model = conf.model.isEmpty ? "openai/gpt-oss-120b" : conf.model
        language = conf.language.isEmpty ? "vi" : conf.language
        customEndpoint = conf.customEndpoint
        
        switch provider {
        case "groq": apiKey = conf.groqKey
        case "openrouter": apiKey = conf.openrouterKey
        case "gemini": apiKey = conf.geminiKey
        case "openai": apiKey = conf.openaiKey
        case "custom": apiKey = conf.customKey
        default: apiKey = ""
        }
        
        let prof = conf.traderProfile
        tradingStyle = prof.tradingStyle
        accountObjective = prof.accountObjective
        primaryPlaybooks = prof.primaryPlaybooks
        maxRiskPerTrade = prof.maxRiskPerTrade
        knownPsychologicalLeaks = prof.knownPsychologicalLeaks
        customMemoryNotes = prof.customMemoryNotes
        
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
        
        isSaved = true
        isError = false
        statusMessage = "AI settings and Trader Profile saved."
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
