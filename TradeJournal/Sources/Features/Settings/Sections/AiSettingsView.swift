import SwiftUI

// MARK: - 6. AI Settings View
// Integrated with OpenCode Free Models (Inference API) & BYOK
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "opencode" // "opencode" | "openai" | "anthropic"
    @State private var model: String = "deepseek-v4.1-flash-free"
    @State private var apiKey: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    @State private var isFetchingModels: Bool = false
    @State private var freeModels: [String] = AIReflectionService.fallbackFreeModels
    
    private let defaultModels: [String: String] = [
        "opencode": "deepseek-v4.1-flash-free",
        "openai": "gpt-4o-mini",
        "anthropic": "claude-3-5-sonnet-20241022"
    ]
    
    public init() {}
    
    public var body: some View {
        SettingsCard(title: "AI (OpenCode Free Models & BYOK)") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Use OpenCode with free models (DeepSeek, Big Pickle, GLM, Nemotron) or bring your own OpenAI / Anthropic key for automated daily recaps, critiques, and “ask your journal”. AI requests go directly to your chosen provider.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Text("Active provider: \(providerName(provider)) · \(isKeyConfigured ? "Key configured" : "Not configured")")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                
                // Provider Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").font(AppTypography.captionBold)
                    Picker("Provider", selection: $provider) {
                        Text("OpenCode (Free)").tag("opencode")
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) {
                        model = defaultModels[provider] ?? ""
                        apiKey = ""
                        statusMessage = ""
                    }
                }
                
                // Model Selection
                if provider == "opencode" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Free Model from OpenCode Source")
                                .font(AppTypography.captionBold)
                            Spacer()
                            Button {
                                refreshOpenCodeModels()
                            } label: {
                                HStack(spacing: 4) {
                                    if isFetchingModels {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Refresh source")
                                }
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.brand)
                            }
                            .buttonStyle(.plain)
                            .disabled(isFetchingModels)
                        }
                        
                        Picker("Select Model", selection: $model) {
                            ForEach(freeModels, id: \.self) { m in
                                Text(displayName(for: m)).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                    }
                }
                
                // Model ID Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID").font(AppTypography.captionBold)
                    TextField(defaultModels[provider] ?? "", text: $model)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                    
                    if provider == "opencode" {
                        Text("Select a free model above or enter any custom model supported by OpenCode.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                // API Key Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(providerName(provider)) API key").font(AppTypography.captionBold)
                    SecureField(keyPlaceholder, text: $apiKey)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                    
                    Text(keyHelpText)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    AppButton("Save AI", icon: "checkmark", style: .primary, size: .compact) {
                        saveAiSettings()
                    }
                    
                    AppButton(isTesting ? "Testing…" : "Test Connection", icon: "network", style: .secondary, size: .compact) {
                        testAiConnection()
                    }
                    .disabled(isTesting || (!isKeyConfigured && apiKey.trimmingCharacters(in: .whitespaces).isEmpty))
                    
                    if isKeyConfigured {
                        AppButton("Remove key", icon: "trash", style: .destructive, size: .compact) {
                            removeKey()
                        }
                    }
                }
                
                // Status Feedback
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(isError ? AppColors.loss : AppColors.profit)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear {
            provider = dataStore.aiSettings.provider
            model = dataStore.aiSettings.model
            if provider == "opencode" {
                refreshOpenCodeModels()
            }
        }
    }
    
    private var isKeyConfigured: Bool {
        switch provider {
        case "opencode":
            return !dataStore.aiSettings.opencodeKey.isEmpty
        case "anthropic":
            return !dataStore.aiSettings.anthropicKey.isEmpty
        case "openai":
            return !dataStore.aiSettings.openaiKey.isEmpty
        default:
            return false
        }
    }
    
    private func providerName(_ id: String) -> String {
        switch id {
        case "opencode": return "OpenCode"
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        default: return id.capitalized
        }
    }
    
    private var keyPlaceholder: String {
        if isKeyConfigured {
            return "Key configured (leave blank to keep)"
        }
        switch provider {
        case "opencode":
            return "oc_sk_… (API key from opencode.ai)"
        case "anthropic":
            return "sk-ant-…"
        case "openai":
            return "sk-…"
        default:
            return "Enter API key"
        }
    }
    
    private var keyHelpText: String {
        if provider == "opencode" {
            return "Get your free API key at opencode.ai (Inference API). Free models (ending in -free and big-pickle) require no paid balance."
        } else {
            return "Leave blank to keep your saved key, or enter a replacement."
        }
    }
    
    private func displayName(for modelId: String) -> String {
        if modelId == "deepseek-v4.1-flash-free" {
            return "DeepSeek V4.1 Flash (Recommended · Free)"
        } else if modelId == "big-pickle" {
            return "Big Pickle (Reasoning & Coding · Free)"
        } else if modelId == "glm-5.3-flash-free" {
            return "GLM 5.3 Flash (Free)"
        } else if modelId == "mimo-v2.6-flash-free" {
            return "Mimo V2.6 Flash (Free)"
        } else if modelId == "nemotron-3.5-lightning-free" {
            return "Nemotron 3.5 Lightning (Free)"
        } else {
            return modelId
        }
    }
    
    private func refreshOpenCodeModels() {
        isFetchingModels = true
        Task {
            let fetched = await AIReflectionService.shared.fetchOpenCodeFreeModels()
            await MainActor.run {
                self.freeModels = fetched
                self.isFetchingModels = false
                if self.provider == "opencode" && (self.model.isEmpty || self.model.hasPrefix("claude-") || self.model.hasPrefix("gpt-")) {
                    self.model = fetched.first ?? "deepseek-v4.1-flash-free"
                }
            }
        }
    }
    
    private func saveAiSettings() {
        dataStore.aiSettings.provider = provider
        dataStore.aiSettings.model = model.trimmingCharacters(in: .whitespaces)
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            switch provider {
            case "opencode":
                dataStore.aiSettings.opencodeKey = key
            case "anthropic":
                dataStore.aiSettings.anthropicKey = key
            case "openai":
                dataStore.aiSettings.openaiKey = key
            default:
                break
            }
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) settings saved."
        apiKey = ""
    }
    
    private func removeKey() {
        switch provider {
        case "opencode":
            dataStore.aiSettings.opencodeKey = ""
        case "anthropic":
            dataStore.aiSettings.anthropicKey = ""
        case "openai":
            dataStore.aiSettings.openaiKey = ""
        default:
            break
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) key removed."
        apiKey = ""
    }
    
    private func testAiConnection() {
        isTesting = true
        isError = false
        statusMessage = "Testing connection to \(providerName(provider)) (\(model))..."
        
        let testConfig = AiSettingsConfig(
            provider: provider,
            model: model.trimmingCharacters(in: .whitespaces),
            opencodeKey: provider == "opencode" ? (apiKey.isEmpty ? dataStore.aiSettings.opencodeKey : apiKey) : "",
            anthropicKey: provider == "anthropic" ? (apiKey.isEmpty ? dataStore.aiSettings.anthropicKey : apiKey) : "",
            openaiKey: provider == "openai" ? (apiKey.isEmpty ? dataStore.aiSettings.openaiKey : apiKey) : ""
        )
        
        Task {
            do {
                let response = try await AIReflectionService.shared.testConnection(config: testConfig)
                await MainActor.run {
                    self.isTesting = false
                    self.isError = false
                    self.statusMessage = "✅ Connected successfully! Response:\n\"\(response)\""
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isError = true
                    self.statusMessage = "❌ Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
