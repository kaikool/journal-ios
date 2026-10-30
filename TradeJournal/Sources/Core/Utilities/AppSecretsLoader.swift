import Foundation

/// Unified Secrets Resolver supporting Local Developer Plist, Info.plist, Environment, and Apple Keychain.
/// Allows private developers to build out-of-the-box zero-config builds while keeping Git repositories 100% secret-free.
public enum AppSecretsLoader {
    
    private static let defaultKeychainMappings: [String: String] = [
        "GEMINI_API_KEY": "gemini_api_key",
        "GROQ_API_KEY": "groq_api_key",
        "GROQ_BACKUP_KEY": "groq_backup_key",
        "OPENROUTER_API_KEY": "openrouter_api_key",
        "OANDA_API_KEY": "oanda_api_key",
        "EXNESS_API_KEY": "exness_api_key_public",
        "EXNESS_PRIVATE_KEY": "exness_private_key_ed25519",
        "SUPABASE_URL": "supabase_url",
        "SUPABASE_ANON_KEY": "supabase_anon_key"
    ]
    
    /// Resolves a secret value from:
    /// 1. Hardware-backed Keychain (or synced via iCloud Keychain)
    /// 2. Sandboxed UserDefaults persistence fallback (for sideloaded/resigned apps without Keychain entitlements)
    /// 3. Optional uncommitted local `AppSecrets.plist` in main bundle
    /// 4. Xcode `Info.plist` / Build Configurations
    /// 5. Process environment variables (`ProcessInfo.processInfo.environment`)
    public static func loadSecret(named key: String, keychainKey: String? = nil) -> String? {
        let kcKey = keychainKey ?? defaultKeychainMappings[key]
        
        // 1. Check Hardware Keychain
        if let targetKcKey = kcKey,
           let val = KeychainManager.get(forKey: targetKcKey),
           !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Check Sandboxed UserDefaults fallback (critical for sideloaded IPAs via eSign)
        if let targetKcKey = kcKey,
           let val = UserDefaults.standard.string(forKey: "bootstrapped_\(targetKcKey)"),
           !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 3. Check local AppSecrets.plist in main bundle (checks both Bundle.main.path and bundleURL)
        let possiblePaths = [
            Bundle.main.path(forResource: "AppSecrets", ofType: "plist"),
            Bundle.main.bundleURL.appendingPathComponent("AppSecrets.plist").path
        ].compactMap { $0 }
        
        for path in possiblePaths {
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let val = dict[key] as? String,
               !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 4. Check Bundle Info.plist
        if let val = Bundle.main.infoDictionary?[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 5. Check ProcessInfo Environment
        if let env = ProcessInfo.processInfo.environment[key], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Automatically bootstraps bundled local secrets into Apple Keychain & UserDefaults on app launch
    /// so the user doesn't have to manually enter anything in the UI.
    public static func bootstrapLocalSecretsToKeychain() {
        let mappings: [(envKey: String, kcKey: String)] = [
            ("SUPABASE_URL", "supabase_url"),
            ("SUPABASE_ANON_KEY", "supabase_anon_key"),
            ("GEMINI_API_KEY", "gemini_api_key"),
            ("GROQ_API_KEY", "groq_api_key"),
            ("GROQ_BACKUP_KEY", "groq_backup_key"),
            ("OPENROUTER_API_KEY", "openrouter_api_key"),
            ("OANDA_API_KEY", "oanda_api_key"),
            ("EXNESS_API_KEY", "exness_api_key_public"),
            ("EXNESS_PRIVATE_KEY", "exness_private_key_ed25519")
        ]
        
        for item in mappings {
            if let localSecret = loadSecret(named: item.envKey, keychainKey: nil), !localSecret.isEmpty {
                // Sideloaded-safe storage: Always update UserDefaults fallback
                UserDefaults.standard.set(localSecret, forKey: "bootstrapped_\(item.kcKey)")
                
                let existingInKeychain = KeychainManager.get(forKey: item.kcKey)
                if existingInKeychain != localSecret {
                    KeychainManager.set(localSecret, forKey: item.kcKey, syncAcrossDevices: true)
                    AppLogger.info("Bootstrap: Synced updated secret for '\(item.kcKey)' to Apple Keychain.")
                }
            }
        }
        
        // Bootstrap non-secret identifiers
        if let oandaAcc = loadSecret(named: "OANDA_ACCOUNT_ID"), !oandaAcc.isEmpty {
            UserDefaults.standard.set(oandaAcc, forKey: "oanda_account_id")
        }
        if let exnAcc = loadSecret(named: "EXNESS_ACCOUNT_ID"), !exnAcc.isEmpty {
            UserDefaults.standard.set(exnAcc, forKey: "exness_account_id")
        }
        if let exnHost = loadSecret(named: "EXNESS_HOST"), !exnHost.isEmpty {
            UserDefaults.standard.set(exnHost, forKey: "exness_api_host")
        } else {
            let current = UserDefaults.standard.string(forKey: "exness_api_host")
            if current == nil || current == "https://api.exness.com" {
                UserDefaults.standard.set("https://api.exness-api.com", forKey: "exness_api_host")
            }
        }
        
        ExnessService.shared.loadSettings()
    }
}
