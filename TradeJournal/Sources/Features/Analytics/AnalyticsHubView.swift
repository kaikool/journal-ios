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
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG iOS 27 Sliding Segmented Bar
            AppleSlidingSegmentedBar(
                selection: $selectedSubTab,
                items: AnalyticsSubTab.allCases,
                titleFor: { $0.rawValue },
                iconFor: { $0.iconName }
            )
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
