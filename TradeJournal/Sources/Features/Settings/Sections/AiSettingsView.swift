import SwiftUI

// MARK: - 6. AI Settings View
// Ported 1:1 from `AiSettings` in `ai-settings.tsx` & `ai-settings.ts`
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "anthropic" // "anthropic" | "openai"
    @State private var model: String = "claude-opus-5"
    @State private var apiKey: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    
    private let defaultModels: [String: String] = [
        "anthropic": "claude-opus-5",
        "openai": "gpt-4.1-mini"
    ]
    
    public init() {}
    
    public var body: some View {
        SettingsCard(title: "AI (bring your own key)") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Use Anthropic or OpenAI for recaps, trade critiques, and “ask your journal”. Your key is encrypted at rest. AI requests go directly to the provider you select.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Text("Active provider: \(providerName(provider)) · \(isKeyConfigured ? "Key configured" : "Not configured")")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").font(AppTypography.captionBold)
                    Picker("Provider", selection: $provider) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) {
                        model = defaultModels[provider] ?? ""
                        apiKey = ""
                        statusMessage = ""
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID").font(AppTypography.captionBold)
                    TextField(defaultModels[provider] ?? "", text: $model)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(providerName(provider)) API key").font(AppTypography.captionBold)
                    SecureField(isKeyConfigured ? "Key configured (leave blank to keep)" : (provider == "anthropic" ? "sk-ant-…" : "sk-…"), text: $apiKey)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Leave blank to keep your saved key, or enter a replacement.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                HStack(spacing: 12) {
                    AppButton("Save AI", icon: "checkmark", style: .primary, size: .compact) {
                        saveAiSettings()
                    }
                    
                    if isKeyConfigured {
                        AppButton("Remove key", icon: "trash", style: .destructive, size: .compact) {
                            removeKey()
                        }
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
            provider = dataStore.aiSettings.provider
            model = dataStore.aiSettings.model
        }
    }
    
    private var isKeyConfigured: Bool {
        if provider == "anthropic" {
            return !dataStore.aiSettings.anthropicKey.isEmpty
        } else {
            return !dataStore.aiSettings.openaiKey.isEmpty
        }
    }
    
    private func providerName(_ id: String) -> String {
        id == "anthropic" ? "Anthropic" : "OpenAI"
    }
    
    private func saveAiSettings() {
        dataStore.aiSettings.provider = provider
        dataStore.aiSettings.model = model.trimmingCharacters(in: .whitespaces)
        if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            if provider == "anthropic" {
                dataStore.aiSettings.anthropicKey = apiKey.trimmingCharacters(in: .whitespaces)
            } else {
                dataStore.aiSettings.openaiKey = apiKey.trimmingCharacters(in: .whitespaces)
            }
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) settings saved."
        apiKey = ""
    }
    
    private func removeKey() {
        if provider == "anthropic" {
            dataStore.aiSettings.anthropicKey = ""
        } else {
            dataStore.aiSettings.openaiKey = ""
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) key removed."
        apiKey = ""
    }
}
