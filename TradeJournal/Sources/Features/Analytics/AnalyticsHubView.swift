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
            // Segmented Navigation Header adhering to Apple HIG
            Picker("Analytics Section", selection: $selectedSubTab) {
                ForEach(AnalyticsSubTab.allCases) { tab in
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
