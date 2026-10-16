import SwiftUI

public enum AnalyticsSubTab: String, CaseIterable, Identifiable {
    case reports = "Báo Cáo"
    case playbooks = "Chiến Lược"
    case propFirms = "Quỹ Prop"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .reports: return "chart.bar.xaxis"
        case .playbooks: return "book.pages"
        case .propFirms: return "building.columns"
        }
    }
}

/// Trung tâm điều phối tính năng Phân tích & Quản lý chiến lược
/// Kết hợp 3 màn hình: Báo cáo phân tích chuyên sâu, Sách chiến lược (Playbooks), Quỹ Prop Firms
public struct AnalyticsHubView: View {
    @State private var selectedSubTab: AnalyticsSubTab = .reports
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Navigation Header theo chuẩn Apple HIG
            Picker("Phần phân tích", selection: $selectedSubTab) {
                ForEach(AnalyticsSubTab.allCases) { tab in
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
