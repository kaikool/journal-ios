import SwiftUI
import Combine

/// Manages application-wide environment state and theme configuration.
public enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case system = "System"
    
    public var id: String { rawValue }
}

public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()
    
    @Published public var selectedTab: AppTab = .dashboard
    @Published public var isPrivacyModeEnabled: Bool = false
    @Published public var isDrawerOpen: Bool = false
    @Published public var currentCurrency: String = "USD"
    @Published public var currentTimeZone: TimeZone = .current
    @Published public var showSyncCenter: Bool = false
    @Published public var appTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: "journal_theme_preference")
        }
    }
    
    // Bypass authentication per local developer requirements
    @Published public var isAuthenticated: Bool = true
    @Published public var currentUserId: String = "local-developer-user"
    
    public var colorScheme: ColorScheme? {
        switch appTheme {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
    
    public init() {
        let savedTheme = UserDefaults.standard.string(forKey: "journal_theme_preference")
        self.appTheme = savedTheme.flatMap(AppTheme.init(rawValue:)) ?? .dark
        
        // Auto-bootstrap any uncommitted local secrets from AppSecrets.plist to Apple Keychain
        AppSecretsLoader.bootstrapLocalSecretsToKeychain()
        
        AppLogger.info("AppEnvironment initialized. PrivacyMode: \(isPrivacyModeEnabled), Currency: \(currentCurrency), Theme: \(appTheme.rawValue)")
    }
    
    public func togglePrivacyMode() {
        isPrivacyModeEnabled.toggle()
        AppLogger.debug("Privacy mode toggled to: \(isPrivacyModeEnabled)")
    }
    
    /// Keeps the display currency aligned with the reporting currency all monetary values are
    /// expressed in (trade P&L, balances and aggregated metrics).
    public func applyReportingCurrency(_ currency: String) {
        let code = currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != currentCurrency else { return }
        currentCurrency = code
    }
    
    public func toggleTheme() {
        appTheme = (appTheme == .dark) ? .light : .dark
        AppLogger.debug("Theme toggled to: \(appTheme.rawValue)")
    }
    
    // MARK: - Gesture-based Tab Navigation
    public func navigateToNextTab() {
        if let next = selectedTab.nextPrimaryTab {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            selectedTab = next
        }
    }
    
    public func navigateToPreviousTab() {
        if let prev = selectedTab.previousPrimaryTab {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            selectedTab = prev
        }
    }
}

/// 13 navigation sections mapped 1:1 from `source-repo/apps/web/src/components/shell.tsx`
public enum AppTab: String, CaseIterable, Identifiable {
    // Primary trading navigation group (NAV)
    case dashboard = "Dashboard"
    case calendar = "Calendar"
    case journal = "Daily journal"
    case trades = "Trades"
    case reports = "Reports"
    case propFirms = "Prop firms"
    case notebook = "Notebook"
    case playbooks = "Playbooks"
    case progress = "Progress"
    case missed = "Missed trades"
    
    // Configuration & setup group (NAV_SETUP)
    case importTrades = "Import"
    case accounts = "Accounts"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .journal: return "book.closed"
        case .trades: return "list.bullet.rectangle"
        case .reports: return "chart.bar.xaxis"
        case .propFirms: return "building.columns"
        case .notebook: return "note.text"
        case .playbooks: return "book"
        case .progress: return "checklist"
        case .missed: return "bookmark"
        case .importTrades: return "square.and.arrow.down"
        case .accounts: return "creditcard"
        case .settings: return "gearshape"
        }
    }
    
    public var selectedIconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .calendar: return "calendar.badge.clock"
        case .journal: return "book.closed.fill"
        case .trades: return "list.bullet.rectangle.fill"
        case .reports: return "chart.bar.xaxis"
        case .propFirms: return "building.columns.fill"
        case .notebook: return "note.text"
        case .playbooks: return "book.fill"
        case .progress: return "checklist.checked"
        case .missed: return "bookmark.fill"
        case .importTrades: return "square.and.arrow.down.fill"
        case .accounts: return "creditcard.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    public var isSetupSection: Bool {
        switch self {
        case .importTrades, .accounts, .settings: return true
        default: return false
        }
    }
    
    // Backward compatibility alias
    public static var analytics: AppTab { .reports }
    
    // MARK: - Gesture Navigation Order
    public static let primaryTabs: [AppTab] = [.dashboard, .calendar, .journal, .trades, .reports]
    
    public var isPrimaryTab: Bool {
        Self.primaryTabs.contains(self)
    }
    
    public var nextPrimaryTab: AppTab? {
        guard let idx = Self.primaryTabs.firstIndex(of: self), idx < Self.primaryTabs.count - 1 else { return nil }
        return Self.primaryTabs[idx + 1]
    }
    
    public var previousPrimaryTab: AppTab? {
        guard let idx = Self.primaryTabs.firstIndex(of: self), idx > 0 else { return nil }
        return Self.primaryTabs[idx - 1]
    }
}

extension Notification.Name {
    public static let appScrollToTop = Notification.Name("AppScrollToTopNotification")
}

