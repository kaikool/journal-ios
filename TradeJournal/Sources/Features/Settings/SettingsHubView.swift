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
    @Namespace private var settingsHubNamespace
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG Sliding Pill Segmented Bar
            HStack(spacing: 4) {
                ForEach(SettingsSubTab.allCases) { tab in
                    let isSelected = selectedSubTab == tab
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                            selectedSubTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(AppTypography.captionBold)
                        }
                        .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppColors.cardBackground)
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
                                    .matchedGeometryEffect(id: "SettingsHubPill", in: settingsHubNamespace)
                            }
                        }
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(4)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
