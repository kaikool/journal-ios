import SwiftUI

// MARK: - 6. AI Settings View
// Clean Apple HIG settings view supporting Groq, OpenRouter, Google Gemini, OpenAI, and Custom endpoints
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "groq"
    @State private var model: String = "openai/gpt-oss-120b"
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    @State private var isSaved: Bool = false
    
    public init() {}
    
    private var providerDisplayName: String {
        switch provider {
        case "groq": return "Groq (Free & Ultra Fast)"
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
            return ["openrouter/free", "deepseek/deepseek-r1:free", "meta-llama/llama-3.2-3b-instruct:free"]
        case "gemini":
            return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case "openai":
            return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        default:
            return []
        }
    }
    
    private var keyFieldLabel: String {
        switch provider {
        case "groq": return "Groq API key"
        case "openrouter": return "OpenRouter API key"
        case "gemini": return "Google Gemini API key"
        case "openai": return "OpenAI API key"
        case "custom": return "API key / Bearer token"
        default: return "API key"
        }
    }
    
    private var keyFieldPlaceholder: String {
        switch provider {
        case "groq": return "gsk_..."
        case "openrouter": return "sk-or-v1-..."
        case "gemini": return "AIzaSy..."
        case "openai": return "sk-..."
        case "custom": return "API key or token..."
        default: return "Paste key..."
        }
    }
    
    private var keyFieldHint: String {
        switch provider {
        case "groq":
            return "Free API key from console.groq.com. Uses active models like llama-3.1-8b-instant."
        case "openrouter":
            return "Free API key from openrouter.ai/keys. Supports openrouter/free and :free models."
        case "gemini":
            return "Free tier from aistudio.google.com (15 RPM / 1,500 RPD, no credit card required)."
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
                        Button("Groq (Free & Fast)") { selectProvider("groq") }
                        Button("OpenRouter (Free Models)") { selectProvider("openrouter") }
                        Button("Google Gemini") { selectProvider("gemini") }
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
        syncDraftToMemory()
        
        provider = newProvider
        isSaved = false
        statusMessage = ""
        isError = false
        
        let conf = dataStore.aiSettings
        switch newProvider {
        case "groq":
            apiKey = conf.groqKey
            if model.isEmpty || !providerModels.contains(model) { model = "openai/gpt-oss-120b" }
        case "openrouter":
            apiKey = conf.openrouterKey
            if model.isEmpty || !providerModels.contains(model) { model = "openrouter/free" }
        case "gemini":
            apiKey = conf.geminiKey
            if model.isEmpty || !providerModels.contains(model) { model = "gemini-2.0-flash" }
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
        provider = conf.provider.isEmpty ? "groq" : conf.provider
        model = conf.model.isEmpty ? "openai/gpt-oss-120b" : conf.model
        customEndpoint = conf.customEndpoint
        
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
    
    private func syncDraftToMemory() {
        var conf = dataStore.aiSettings
        switch provider {
        case "groq": conf.groqKey = apiKey
        case "openrouter": conf.openrouterKey = apiKey
        case "gemini": conf.geminiKey = apiKey
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
