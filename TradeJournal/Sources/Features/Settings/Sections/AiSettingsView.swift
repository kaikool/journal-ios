import SwiftUI

// MARK: - 6. AI Settings View
// Clean Apple HIG settings view matching GeneralSettingsView and TradingSettingsView
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "github"
    @State private var model: String = "gpt-4o"
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    @State private var isSaved: Bool = false
    
    public init() {}
    
    private var providerDisplayName: String {
        switch provider {
        case "github": return "GitHub Models"
        case "gemini": return "Google Gemini"
        case "groq": return "Groq"
        case "openai": return "OpenAI"
        case "custom": return "Custom / Azure"
        default: return provider.capitalized
        }
    }
    
    private var providerModels: [String] {
        switch provider {
        case "github":
            return ["gpt-4o", "gpt-4o-mini", "o3-mini", "Meta-Llama-3.1-70B-Instruct", "Phi-4"]
        case "gemini":
            return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case "groq":
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "deepseek-r1-distill-llama-70b"]
        case "openai":
            return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        default:
            return []
        }
    }
    
    private var keyFieldLabel: String {
        switch provider {
        case "github": return "GitHub personal access token (PAT)"
        case "gemini": return "Google Gemini API key"
        case "groq": return "Groq API key"
        case "openai": return "OpenAI API key"
        case "custom": return "API key / Bearer token"
        default: return "API key"
        }
    }
    
    private var keyFieldPlaceholder: String {
        switch provider {
        case "github": return "ghp_... or github_pat_..."
        case "gemini": return "AIzaSy..."
        case "groq": return "gsk_..."
        case "openai": return "sk-..."
        case "custom": return "API key or token..."
        default: return "Paste key..."
        }
    }
    
    private var keyFieldHint: String {
        switch provider {
        case "github":
            return "From github.com/settings/tokens (classic token with repo or fine-grained with models:read)."
        case "gemini":
            return "Free tier from aistudio.google.com (15 RPM / 1,500 RPD, no credit card required)."
        case "groq":
            return "Free tier from console.groq.com. Active model: llama-3.3-70b-versatile."
        case "openai":
            return "Requires an OpenAI platform account with billing balance."
        case "custom":
            return "OpenAI-compatible /chat/completions endpoint (e.g. Azure AI Foundry, self-hosted proxy)."
        default:
            return ""
        }
    }
    
    public var body: some View {
        SettingsCard(title: "AI reflection") {
            VStack(alignment: .leading, spacing: 16) {
                // Provider Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Provider")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    AppleMenuChip(title: "Provider", selectionText: providerDisplayName, icon: "cpu") {
                        Button("GitHub Models") { selectProvider("github") }
                        Button("Google Gemini") { selectProvider("gemini") }
                        Button("Groq") { selectProvider("groq") }
                        Button("OpenAI") { selectProvider("openai") }
                        Button("Custom / Azure") { selectProvider("custom") }
                    }
                    
                    Text("Automated trade reviews, daily recaps, and journaling coach grounded in your trade data.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Divider()
                
                // API Key / Token Field
                VStack(alignment: .leading, spacing: 6) {
                    Text(keyFieldLabel)
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    SecureField(keyFieldPlaceholder, text: $apiKey)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: apiKey) {
                            isSaved = false
                            statusMessage = ""
                        }
                    
                    Text(keyFieldHint)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                // Custom Endpoint Field (if custom selected)
                if provider == "custom" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom endpoint URL")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("https://your-endpoint.com/v1/chat/completions", text: $customEndpoint)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .onChange(of: customEndpoint) {
                                isSaved = false
                                statusMessage = ""
                            }
                    }
                }
                
                // Model ID Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if !providerModels.isEmpty {
                        AppleMenuChip(title: "Preset", selectionText: model, icon: "sparkles") {
                            ForEach(providerModels, id: \.self) { m in
                                Button(m) {
                                    model = m
                                    isSaved = false
                                    statusMessage = ""
                                }
                            }
                        }
                    }
                    
                    TextField("Model ID", text: $model)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: model) {
                            isSaved = false
                            statusMessage = ""
                        }
                }
                
                Divider()
                
                // Action Buttons
                HStack(spacing: 12) {
                    AppButton("Save settings", icon: "checkmark", style: .primary, size: .compact) {
                        saveSettings()
                    }
                    
                    AppButton("Test connection", icon: "network", style: .secondary, size: .compact, isLoading: isTesting) {
                        testConnection()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
                    
                    if isSaved && !statusMessage.isEmpty && !isError {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.profit)
                    }
                }
                
                if isError && !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.loss)
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Actions
    
    private func selectProvider(_ newProvider: String) {
        // Persist current key into memory before switching
        syncDraftToMemory()
        
        provider = newProvider
        isSaved = false
        statusMessage = ""
        isError = false
        
        // Load saved key for newly selected provider
        let conf = dataStore.aiSettings
        switch newProvider {
        case "github":
            apiKey = conf.githubKey
            if model.isEmpty || !providerModels.contains(model) { model = "gpt-4o" }
        case "gemini":
            apiKey = conf.geminiKey
            if model.isEmpty || !providerModels.contains(model) { model = "gemini-2.0-flash" }
        case "groq":
            apiKey = conf.groqKey
            if model.isEmpty || !providerModels.contains(model) { model = "llama-3.3-70b-versatile" }
        case "openai":
            apiKey = conf.openaiKey
            if model.isEmpty || !providerModels.contains(model) { model = "gpt-4o-mini" }
        case "custom":
            apiKey = conf.customKey
            customEndpoint = conf.customEndpoint
        default:
            break
        }
    }
    
    private func loadCurrentSettings() {
        let conf = dataStore.aiSettings
        provider = conf.provider.isEmpty ? "github" : conf.provider
        model = conf.model.isEmpty ? "gpt-4o" : conf.model
        customEndpoint = conf.customEndpoint
        
        switch provider {
        case "github": apiKey = conf.githubKey
        case "gemini": apiKey = conf.geminiKey
        case "groq": apiKey = conf.groqKey
        case "openai": apiKey = conf.openaiKey
        case "custom": apiKey = conf.customKey
        default: apiKey = ""
        }
        
        isSaved = false
        statusMessage = ""
        isError = false
    }
    
    private func syncDraftToMemory() {
        var conf = dataStore.aiSettings
        switch provider {
        case "github": conf.githubKey = apiKey
        case "gemini": conf.geminiKey = apiKey
        case "groq": conf.groqKey = apiKey
        case "openai": conf.openaiKey = apiKey
        case "custom":
            conf.customKey = apiKey
            conf.customEndpoint = customEndpoint
        default: break
        }
        conf.provider = provider
        conf.model = model
        dataStore.aiSettings = conf
    }
    
    private func saveSettings() {
        var conf = dataStore.aiSettings
        conf.provider = provider
        conf.model = model.trimmingCharacters(in: .whitespaces)
        
        switch provider {
        case "github":
            conf.githubKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "gemini":
            conf.geminiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "groq":
            conf.groqKey = apiKey.trimmingCharacters(in: .whitespaces)
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
        statusMessage = "AI settings saved."
    }
    
    private func testConnection() {
        isTesting = true
        statusMessage = "Testing connection..."
        isError = false
        
        var draft = dataStore.aiSettings
        draft.provider = provider
        draft.model = model.trimmingCharacters(in: .whitespaces)
        
        switch provider {
        case "github":
            draft.githubKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "gemini":
            draft.geminiKey = apiKey.trimmingCharacters(in: .whitespaces)
        case "groq":
            draft.groqKey = apiKey.trimmingCharacters(in: .whitespaces)
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
                let response = try await AIReflectionService.shared.testConnection(config: draft)
                await MainActor.run {
                    isTesting = false
                    isError = false
                    isSaved = true
                    statusMessage = "Connected: \(response.prefix(80))"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    isError = true
                    statusMessage = error.localizedDescription
                }
            }
        }
    }
}
