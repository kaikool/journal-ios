import Foundation

/// Typed, injectable facade over `UserDefaults` for non-secret app preferences.
///
/// All preference keys live in `Key` so they are defined in one place. Secrets (API keys,
/// OAuth tokens) must never be stored here — use `KeychainManager` instead.
public final class AppSettingsStore: @unchecked Sendable {
    public static let shared = AppSettingsStore()

    /// Every preference key persisted by the app (single source of truth).
    public enum Key: String {
        case themePreference = "journal_theme_preference"
        case hapticsEnabled = "journal_haptics_enabled"
        case persistentUserId = "trade_journal_persistent_user_id"
        case marketAlertEnabled = "market_alert_enabled"
        case marketAlertSymbols = "market_alert_symbols"
        case marketAlertTimeframes = "market_alert_timeframes"
        case quickSyncOptions = "journal_quick_sync_options_v1"
        case oandaAccountId = "oanda_account_id"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Appearance & Interaction

    public var themePreference: String? {
        get { defaults.string(forKey: Key.themePreference.rawValue) }
        set { defaults.set(newValue, forKey: Key.themePreference.rawValue) }
    }

    /// Haptics are enabled unless the user explicitly turned them off.
    public var isHapticsEnabled: Bool {
        get { defaults.object(forKey: Key.hapticsEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled.rawValue) }
    }

    // MARK: - Identity

    /// Stable per-device identifier; generated and persisted on first access.
    public var persistentUserId: String {
        if let existing = defaults.string(forKey: Key.persistentUserId.rawValue), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: Key.persistentUserId.rawValue)
        return newId
    }

    // MARK: - Market Alerts

    public var marketAlertEnabled: Bool {
        get { defaults.bool(forKey: Key.marketAlertEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.marketAlertEnabled.rawValue) }
    }

    public var marketAlertSymbols: [String]? {
        get { defaults.stringArray(forKey: Key.marketAlertSymbols.rawValue) }
        set { defaults.set(newValue, forKey: Key.marketAlertSymbols.rawValue) }
    }

    public var marketAlertTimeframes: [String]? {
        get { defaults.stringArray(forKey: Key.marketAlertTimeframes.rawValue) }
        set { defaults.set(newValue, forKey: Key.marketAlertTimeframes.rawValue) }
    }

    // MARK: - Sync & Market Data

    public var quickSyncOptionsData: Data? {
        get { defaults.data(forKey: Key.quickSyncOptions.rawValue) }
        set { defaults.set(newValue, forKey: Key.quickSyncOptions.rawValue) }
    }

    public var oandaAccountId: String? {
        get { defaults.string(forKey: Key.oandaAccountId.rawValue) }
        set { defaults.set(newValue, forKey: Key.oandaAccountId.rawValue) }
    }
}
