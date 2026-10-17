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
            // Segmented Navigation Header adhering to Apple HIG
            Picker("Settings Section", selection: $selectedSubTab) {
                ForEach(SettingsSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
            
            Divider()
            
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
