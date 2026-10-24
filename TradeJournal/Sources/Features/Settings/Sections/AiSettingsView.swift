import SwiftUI

// MARK: - 6. AI Settings View (Apple Human Interface Guidelines Compliant)
// Multi-provider AI reflection layer supporting free tier models (Google Gemini, Groq, OpenRouter) and BYOK (OpenAI, Anthropic)
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "gemini"
    @State private var model: String = "gemini-2.0-flash"
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    @State private var isSecureKey: Bool = true
    @State private var showCustomModelField: Bool = false
    
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isTesting: Bool = false
    
    @Environment(\.openURL) private var openURL
    
    // Curated top models per provider
    private let curatedModels: [String: [(id: String, name: String, tag: String)]] = [
        "gemini": [
            ("gemini-2.0-flash", "Gemini 2.0 Flash", "Recommended · Free"),
            ("gemini-1.5-flash", "Gemini 1.5 Flash", "Fast · Free"),
            ("gemini-1.5-pro", "Gemini 1.5 Pro", "Deep Analysis · Free")
        ],
        "groq": [
            ("llama-3.3-70b-versatile", "Llama 3.3 70B", "Recommended · Free"),
            ("llama-3.1-8b-instant", "Llama 3.1 8B", "Ultra-fast · Free"),
            ("deepseek-r1-distill-llama-70b", "DeepSeek R1 Distill", "Reasoning · Free"),
            ("mixtral-8x7b-32768", "Mixtral 8x7B", "Free")
        ],
        "openrouter": [
            ("deepseek/deepseek-r1:free", "DeepSeek R1", "Top Reasoning · Free"),
            ("deepseek/deepseek-chat:free", "DeepSeek V3", "Free"),
            ("meta-llama/llama-3.3-70b-instruct:free", "Llama 3.3 70B", "Free"),
            ("google/gemini-2.0-flash-exp:free", "Gemini 2.0 Flash Exp", "Free"),
            ("qwen/qwen-2.5-72b-instruct:free", "Qwen 2.5 72B", "Free")
        ],
        "openai": [
            ("gpt-4o", "GPT-4o", "Flagship · BYOK"),
            ("gpt-4o-mini", "GPT-4o Mini", "Efficient · BYOK"),
            ("o3-mini", "o3-mini", "Reasoning · BYOK")
        ],
        "anthropic": [
            ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet", "Recommended · BYOK"),
            ("claude-3-5-haiku-20241022", "Claude 3.5 Haiku", "Fast · BYOK")
        ]
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Card 1: Status & Overview
            SettingsCard(title: "AI Trader Coach") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automated Daily Reflection & Q&A")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Grounds 100% in your executions, P&L, and tilt behaviors.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        // Status Badge
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isKeyConfigured ? AppColors.profit : AppColors.warning)
                                .frame(width: 8, height: 8)
                            Text(isKeyConfigured ? "Active" : "Unconfigured")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(isKeyConfigured ? AppColors.profit : AppColors.warning)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isKeyConfigured ? AppColors.profitFill : AppColors.warning.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
            
            // Card 2: Provider Selection
            SettingsCard(title: "AI Provider") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Provider", selection: $provider) {
                        Text("Google Gemini").tag("gemini")
                        Text("Groq").tag("groq")
                        Text("OpenRouter").tag("openrouter")
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: provider) {
                        onProviderChanged()
                    }
                    
                    // Provider Benefit Pill
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: providerIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.brand)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(providerFeatureTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            Text(providerFeatureDescription)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        if let url = providerPortalUrl {
                            Button {
                                openURL(url)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Get Key")
                                    Image(systemName: "arrow.up.forward.app")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.brand.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            
            // Card 3: Model Selection
            SettingsCard(title: "Model Selection") {
                VStack(alignment: .leading, spacing: 12) {
                    if let models = curatedModels[provider], !models.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(models, id: \.id) { item in
                                Button {
                                    model = item.id
                                    showCustomModelField = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(model == item.id ? AppColors.primaryText : AppColors.secondaryText)
                                            Text(item.id)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                        }
                                        
                                        Spacer()
                                        
                                        Text(item.tag)
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(item.tag.contains("Free") ? AppColors.profitFill : AppColors.brand.opacity(0.12))
                                            .foregroundColor(item.tag.contains("Free") ? AppColors.profit : AppColors.brand)
                                            .clipShape(Capsule())
                                        
                                        if model == item.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppColors.brand)
                                                .font(.system(size: 16))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(model == item.id ? AppColors.secondaryBackground : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Divider().padding(.vertical, 2)
                    }
                    
                    // Custom model ID toggle
                    DisclosureGroup("Custom Model ID", isExpanded: $showCustomModelField) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("e.g. \(defaultModelForProvider)", text: $model)
                                .font(.system(size: 13, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            
                            Text("Enter any valid model identifier supported by \(providerDisplayName).")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.top, 4)
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Card 4: Credentials & API Key
            SettingsCard(title: "Authentication") {
                VStack(alignment: .leading, spacing: 12) {
                    if provider == "custom" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Endpoint Base URL").font(AppTypography.captionBold)
                            TextField("https://api.your-server.com/v1/chat/completions", text: $customEndpoint)
                                .font(AppTypography.inputText)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(providerDisplayName) API Key")
                                .font(AppTypography.captionBold)
                            Spacer()
                            if isKeyConfigured {
                                Text("Key Saved")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                        
                        HStack {
                            if isSecureKey {
                                SecureField(keyPlaceholder, text: $apiKey)
                                    .font(AppTypography.inputText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                TextField(keyPlaceholder, text: $apiKey)
                                    .font(.system(size: 13, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Button {
                                isSecureKey.toggle()
                            } label: {
                                Image(systemName: isSecureKey ? "eye" : "eye.slash")
                                    .foregroundColor(AppColors.secondaryText)
                                    .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            
                            if !apiKey.isEmpty {
                                Button {
                                    apiKey = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        Text(keyHelpText)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    // Buttons
                    HStack(spacing: 10) {
                        AppButton("Save", icon: "checkmark", style: .primary, size: .compact) {
                            saveAiSettings()
                        }
                        
                        AppButton(isTesting ? "Testing…" : "Test Connection", icon: "network", style: .secondary, size: .compact) {
                            testAiConnection()
                        }
                        .disabled(isTesting || (!isKeyConfigured && apiKey.trimmingCharacters(in: .whitespaces).isEmpty))
                        
                        if isKeyConfigured {
                            AppButton("Remove", icon: "trash", style: .destructive, size: .compact) {
                                removeKey()
                            }
                        }
                    }
                    
                    // Live Feedback
                    if !statusMessage.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                .foregroundColor(isError ? AppColors.loss : AppColors.profit)
                                .font(.system(size: 14))
                                .padding(.top, 2)
                            
                            Text(statusMessage)
                                .font(AppTypography.caption)
                                .foregroundColor(isError ? AppColors.loss : AppColors.primaryText)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isError ? AppColors.lossFill : AppColors.profitFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            
            // Privacy Footnote (Apple HIG standard)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.system(size: 12))
                Text("Your API key is securely encrypted on this device. AI prompts travel directly to the provider over TLS.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - State & Helpers
    
    private func loadCurrentSettings() {
        provider = dataStore.aiSettings.provider.isEmpty ? "gemini" : dataStore.aiSettings.provider
        model = dataStore.aiSettings.model.isEmpty ? defaultModelForProvider : dataStore.aiSettings.model
        customEndpoint = dataStore.aiSettings.customEndpoint
    }
    
    private var isKeyConfigured: Bool {
        switch provider {
        case "gemini": return !dataStore.aiSettings.geminiKey.isEmpty
        case "groq": return !dataStore.aiSettings.groqKey.isEmpty
        case "openrouter": return !dataStore.aiSettings.openrouterKey.isEmpty
        case "openai": return !dataStore.aiSettings.openaiKey.isEmpty
        case "anthropic": return !dataStore.aiSettings.anthropicKey.isEmpty
        case "custom": return !dataStore.aiSettings.customKey.isEmpty
        default: return false
        }
    }
    
    private var providerDisplayName: String {
        switch provider {
        case "gemini": return "Google Gemini"
        case "groq": return "Groq"
        case "openrouter": return "OpenRouter"
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "custom": return "Custom Server"
        default: return provider.capitalized
        }
    }
    
    private var defaultModelForProvider: String {
        switch provider {
        case "gemini": return "gemini-2.0-flash"
        case "groq": return "llama-3.3-70b-versatile"
        case "openrouter": return "deepseek/deepseek-r1:free"
        case "openai": return "gpt-4o-mini"
        case "anthropic": return "claude-3-5-sonnet-20241022"
        default: return "default"
        }
    }
    
    private var providerIcon: String {
        switch provider {
        case "gemini": return "sparkles"
        case "groq": return "bolt.fill"
        case "openrouter": return "arrow.triangle.branch"
        case "openai": return "brain"
        case "anthropic": return "bubble.left.and.bubble.right"
        default: return "server.rack"
        }
    }
    
    private var providerFeatureTitle: String {
        switch provider {
        case "gemini": return "Free 1,500 req/day · 1M Context Window"
        case "groq": return "Free · Ultra-Fast LPU Inference"
        case "openrouter": return "Free DeepSeek R1 & Top Open Models"
        case "openai": return "Official OpenAI Platform (BYOK)"
        case "anthropic": return "Official Anthropic Claude (BYOK)"
        default: return "Self-Hosted or Local Proxy"
        }
    }
    
    private var providerFeatureDescription: String {
        switch provider {
        case "gemini": return "Excellent at reasoning, chart explanations, and Vietnamese. Completely free via Google AI Studio."
        case "groq": return "Near-instant response times (~500 tokens/s) with Meta's Llama 3.3 70B model."
        case "openrouter": return "Access top reasoning models with free router endpoints (:free tag)."
        case "openai": return "Pay-as-you-go GPT-4o and reasoning models via your personal OpenAI key."
        case "anthropic": return "Industry-leading reasoning with Claude 3.5 Sonnet via Anthropic Console key."
        default: return "Connect any OpenAI-compatible backend, Ollama, or private LLM gateway."
        }
    }
    
    private var providerPortalUrl: URL? {
        switch provider {
        case "gemini": return URL(string: "https://aistudio.google.com/app/apikey")
        case "groq": return URL(string: "https://console.groq.com/keys")
        case "openrouter": return URL(string: "https://openrouter.ai/keys")
        case "openai": return URL(string: "https://platform.openai.com/api-keys")
        case "anthropic": return URL(string: "https://console.anthropic.com/settings/keys")
        default: return nil
        }
    }
    
    private var keyPlaceholder: String {
        if isKeyConfigured {
            return "Key saved · Leave blank to keep"
        }
        switch provider {
        case "gemini": return "AIzaSy… (API Key from Google AI Studio)"
        case "groq": return "gsk_… (API Key from Groq Cloud)"
        case "openrouter": return "sk-or-v1-… (API Key from OpenRouter)"
        case "openai": return "sk-proj-… (OpenAI Key)"
        case "anthropic": return "sk-ant-… (Anthropic Key)"
        default: return "Enter API Key"
        }
    }
    
    private var keyHelpText: String {
        if isKeyConfigured {
            return "Leave blank to keep your active key, or enter a new key to replace it."
        }
        switch provider {
        case "gemini": return "Get your free API key at aistudio.google.com (No credit card required)."
        case "groq": return "Get your free API key at console.groq.com/keys (Instant creation)."
        case "openrouter": return "Get your free key at openrouter.ai/keys to use free models."
        default: return "Requires a valid API key with available credits."
        }
    }
    
    private func onProviderChanged() {
        model = defaultModelForProvider
        apiKey = ""
        statusMessage = ""
        isError = false
        showCustomModelField = false
    }
    
    private func saveAiSettings() {
        dataStore.aiSettings.provider = provider
        dataStore.aiSettings.model = model.trimmingCharacters(in: .whitespaces)
        dataStore.aiSettings.customEndpoint = customEndpoint.trimmingCharacters(in: .whitespaces)
        
        let cleanKey = apiKey.trimmingCharacters(in: .whitespaces)
        if !cleanKey.isEmpty {
            switch provider {
            case "gemini": dataStore.aiSettings.geminiKey = cleanKey
            case "groq": dataStore.aiSettings.groqKey = cleanKey
            case "openrouter": dataStore.aiSettings.openrouterKey = cleanKey
            case "openai": dataStore.aiSettings.openaiKey = cleanKey
            case "anthropic": dataStore.aiSettings.anthropicKey = cleanKey
            case "custom": dataStore.aiSettings.customKey = cleanKey
            default: break
            }
        }
        
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerDisplayName) settings saved successfully."
        apiKey = ""
    }
    
    private func removeKey() {
        switch provider {
        case "gemini": dataStore.aiSettings.geminiKey = ""
        case "groq": dataStore.aiSettings.groqKey = ""
        case "openrouter": dataStore.aiSettings.openrouterKey = ""
        case "openai": dataStore.aiSettings.openaiKey = ""
        case "anthropic": dataStore.aiSettings.anthropicKey = ""
        case "custom": dataStore.aiSettings.customKey = ""
        default: break
        }
        
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerDisplayName) key removed from device."
        apiKey = ""
    }
    
    private func testAiConnection() {
        isTesting = true
        isError = false
        statusMessage = "Testing connection to \(providerDisplayName) (\(model))..."
        
        let testConfig = AiSettingsConfig(
            provider: provider,
            model: model.trimmingCharacters(in: .whitespaces),
            geminiKey: provider == "gemini" ? (apiKey.isEmpty ? dataStore.aiSettings.geminiKey : apiKey) : "",
            groqKey: provider == "groq" ? (apiKey.isEmpty ? dataStore.aiSettings.groqKey : apiKey) : "",
            openrouterKey: provider == "openrouter" ? (apiKey.isEmpty ? dataStore.aiSettings.openrouterKey : apiKey) : "",
            openaiKey: provider == "openai" ? (apiKey.isEmpty ? dataStore.aiSettings.openaiKey : apiKey) : "",
            anthropicKey: provider == "anthropic" ? (apiKey.isEmpty ? dataStore.aiSettings.anthropicKey : apiKey) : "",
            customEndpoint: customEndpoint.trimmingCharacters(in: .whitespaces),
            customKey: provider == "custom" ? (apiKey.isEmpty ? dataStore.aiSettings.customKey : apiKey) : ""
        )
        
        Task {
            do {
                let response = try await AIReflectionService.shared.testConnection(config: testConfig)
                await MainActor.run {
                    self.isTesting = false
                    self.isError = false
                    self.statusMessage = "Connected successfully!\n\n\"\(response)\""
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isError = true
                    self.statusMessage = "\(error.localizedDescription)"
                }
            }
        }
    }
}
