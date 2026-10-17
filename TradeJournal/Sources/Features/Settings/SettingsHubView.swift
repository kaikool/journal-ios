import SwiftUI

public enum SettingsSubTab: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case importFile = "Import"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .accounts: return "creditcard"
        case .importFile: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

/// Settings Hub coordinating Accounts Management, Statement Import, and Application Settings
public struct SettingsHubView: View {
    @State private var selectedSubTab: SettingsSubTab = .accounts
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG iOS 27 Sliding Segmented Bar
            AppleSlidingSegmentedBar(
                selection: $selectedSubTab,
                items: SettingsSubTab.allCases,
                titleFor: { $0.rawValue },
                iconFor: { $0.iconName }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
            
            Divider().background(AppColors.border.opacity(0.5))
            
            // Sub-view presentation
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
