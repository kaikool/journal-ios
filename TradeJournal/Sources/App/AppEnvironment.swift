import SwiftUI
import Combine

/// Quản lý trạng thái môi trường và cấu hình toàn ứng dụng.
public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()
    
    @Published public var selectedTab: AppTab = .dashboard
    @Published public var isPrivacyModeEnabled: Bool = false
    @Published public var isDrawerOpen: Bool = false
    @Published public var currentCurrency: String = "USD"
    @Published public var currentTimeZone: TimeZone = .current
    
    // Bỏ qua đăng nhập theo yêu cầu người dùng
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

/// 13 phân hệ điều hướng chuẩn xác 1:1 từ `source-repo/apps/web/src/components/shell.tsx`
public enum AppTab: String, CaseIterable, Identifiable {
    // Nhóm tính năng giao dịch (NAV)
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
    
    // Nhóm cấu hình (NAV_SETUP)
    case importTrades = "Import"
    case accounts = "Accounts"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .journal: return "book.closed"
        case .trades: return "list.number"
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
    
    public var isSetupSection: Bool {
        switch self {
        case .importTrades, .accounts, .settings: return true
        default: return false
        }
    }
    
    // Alias tương thích ngược
    public static var analytics: AppTab { .reports }
}
