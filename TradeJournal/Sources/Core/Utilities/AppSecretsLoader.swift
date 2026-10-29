import Foundation

/// Unified Secrets Resolver supporting Local Developer Plist, Info.plist, Environment, and Apple Keychain.
/// Allows private developers to build out-of-the-box zero-config builds while keeping Git repositories 100% secret-free.
public enum AppSecretsLoader {
    
    /// Resolves a secret value from:
    /// 1. Hardware-backed Keychain (or synced via iCloud Keychain)
    /// 2. Optional uncommitted local `AppSecrets.plist` in main bundle
    /// 3. Xcode `Info.plist` / Build Configurations
    /// 4. Process environment variables (`ProcessInfo.processInfo.environment`)
    public static func loadSecret(named key: String, keychainKey: String? = nil) -> String? {
        // 1. Check Hardware Keychain
        if let kcKey = keychainKey, let val = KeychainManager.get(forKey: kcKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val
        }
        
        // 2. Check local AppSecrets.plist (if added locally by the owner, ignored by Git)
        if let path = Bundle.main.path(forResource: "AppSecrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let val = dict[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 3. Check Bundle Info.plist
        if let val = Bundle.main.infoDictionary?[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 4. Check ProcessInfo Environment
        if let env = ProcessInfo.processInfo.environment[key], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Automatically bootstraps bundled local secrets into Apple Keychain on first app launch
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
