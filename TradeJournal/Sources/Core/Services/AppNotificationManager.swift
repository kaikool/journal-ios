import Foundation
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Unified Push & Local Notification Management Service (Standard 25)
/// Serves as the Single Source of Truth for all system notification dispatches,
/// permission request lifecycles, and foreground presentation behaviors.
public final class AppNotificationManager: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AppNotificationManager()
    
    @Published public private(set) var isAuthorized: Bool = false
    #if canImport(UserNotifications)
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    #endif
    
    private override init() {
        super.init()
    }
    
    /// Initializes and configures notification categories and delegates on application launch
    public func configure() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        Task {
            await refreshAuthorizationStatus()
        }
        #endif
    }
    
    // MARK: - Permission Lifecycle
    
    /// Requests notification permissions for alerts, sounds, and badges asynchronously
    @discardableResult
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = granted ? .authorized : .denied
            }
            return granted
        } catch {
            await MainActor.run {
                self.isAuthorized = false
                self.authorizationStatus = .denied
            }
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Queries the current authorization status without prompting the user
    public func refreshAuthorizationStatus() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
        #endif
    }
    
    // MARK: - Dispatching
    
    /// Dispatches a structured local notification with sound, badge, and optional payload
    public func dispatchNotification(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        body: String,
        categoryIdentifier: String? = nil,
        badge: NSNumber? = nil,
        userInfo: [AnyHashable: Any] = [:],
        timeInterval: TimeInterval? = nil
    ) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        if let sub = subtitle, !sub.isEmpty {
            content.subtitle = sub
        }
        content.body = body
        content.sound = .default
        if let b = badge {
            content.badge = b
        }
        content.userInfo = userInfo
        if let cat = categoryIdentifier {
            content.categoryIdentifier = cat
        }
        
        let trigger: UNNotificationTrigger? = {
            if let interval = timeInterval, interval > 0 {
                return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            }
            return nil
        }()
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let err = error {
                AppLogger.warning("Failed to schedule notification (\(id)): \(err.localizedDescription)")
            }
        }
        #endif
    }
    
    // MARK: - Maintenance & Badge Controls
    
    public func clearBadgeCount() {
        #if canImport(UserNotifications)
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
        #endif
    }
    
    public func removeNotification(identifier: String) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        #endif
    }
    
    public func removeAllNotifications() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        #endif
    }
    
    // MARK: - Categories
    
    private func registerNotificationCategories() {
        #if canImport(UserNotifications)
        let marketAlertCategory = UNNotificationCategory(
            identifier: "MARKET_ALERT",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let tradeAlertCategory = UNNotificationCategory(
            identifier: "TRADE_ALERT",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([marketAlertCategory, tradeAlertCategory])
        #endif
    }
}

// MARK: - UNUserNotificationCenterDelegate
#if canImport(UserNotifications)
extension AppNotificationManager: UNUserNotificationCenterDelegate {
    /// Allows foreground banner display when application is actively open
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
    
    /// Handles user interaction when tapping a banner or notification action
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let symbol = userInfo["symbol"] as? String {
            AppLogger.info("User tapped notification for \(symbol)")
        }
        completionHandler()
    }
}
#endif
