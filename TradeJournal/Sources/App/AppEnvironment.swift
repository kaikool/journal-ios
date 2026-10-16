import SwiftUI
import Combine

/// Quản lý trạng thái môi trường và cấu hình toàn ứng dụng.
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()
    
    @Published public var selectedTab: AppTab = .dashboard
    @Published public var isPrivacyModeEnabled: Bool = false
    @Published public var currentCurrency: String = "USD"
    @Published public var currentTimeZone: TimeZone = .current
    
    // Tạm thời bỏ qua đăng nhập theo yêu cầu người dùng
    @Published public var isAuthenticated: Bool = true
    @Published public var currentUserId: String = "local-developer-user"
    
    public init() {
        AppLogger.info("AppEnvironment initialized. PrivacyMode: \(isPrivacyModeEnabled), Currency: \(currentCurrency)")
    }
    
    public func togglePrivacyMode() {
        isPrivacyModeEnabled.toggle()
        AppLogger.debug("Privacy mode toggled to: \(isPrivacyModeEnabled)")
    }
}

public enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case trades = "Trades"
    case importStatement = "Import"
    case journal = "Journal"
    case propFirm = "Prop Firms"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .trades: return "list.bullet.rectangle"
        case .importStatement: return "square.and.arrow.down"
        case .journal: return "calendar"
        case .propFirm: return "building.columns"
        case .settings: return "gearshape"
        }
    }
}
