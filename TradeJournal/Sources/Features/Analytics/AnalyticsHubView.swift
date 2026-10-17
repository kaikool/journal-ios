import SwiftUI

public enum AnalyticsSubTab: String, CaseIterable, Identifiable {
    case reports = "Reports"
    case playbooks = "Playbooks"
    case propFirms = "Prop firms"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .reports: return "chart.bar.xaxis"
        case .playbooks: return "book.pages"
        case .propFirms: return "building.columns"
        }
    }
}

/// Analytics Hub coordinating:
/// - Reports & deep performance metrics
/// - Trading Playbooks & strategy adherence
/// - Prop Firm accounts, challenges & payout ledger
public struct AnalyticsHubView: View {
    @State private var selectedSubTab: AnalyticsSubTab = .reports
    @Namespace private var analyticsTabNamespace
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG Sliding Pill Segmented Bar
            HStack(spacing: 4) {
                ForEach(AnalyticsSubTab.allCases) { tab in
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
                                    .matchedGeometryEffect(id: "AnalyticsSubTabPill", in: analyticsTabNamespace)
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
            case .reports:
                ReportsView()
            case .playbooks:
                PlaybooksView()
            case .propFirms:
                PropFirmTrackerView()
            }
        }
        .background(AppColors.background)
    }
}
