import SwiftUI

public enum SettingsSubTab: String, CaseIterable, Identifiable {
    case accounts = "Tài Khoản"
    case importFile = "Nhập File"
    case settings = "Cài Đặt"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .accounts: return "creditcard"
        case .importFile: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

/// Trung tâm điều phối Cài đặt & Quản lý hệ thống
/// Kết hợp 3 màn hình: Quản lý tài khoản, Nhập file statement/lệnh, Cài đặt hệ thống
public struct SettingsHubView: View {
    @State private var selectedSubTab: SettingsSubTab = .accounts
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Navigation Header theo chuẩn Apple HIG
            Picker("Phần cài đặt", selection: $selectedSubTab) {
                ForEach(SettingsSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
            
            Divider()
            
            // Nội dung tab con tương ứng
            switch selectedSubTab {
            case .accounts:
                AccountsManagerView()
            case .importFile:
                ImportStatementView()
            case .settings:
                SettingsView()
            }
        }
        .background(AppColors.background)
    }
}
