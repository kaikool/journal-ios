import SwiftUI

public enum JournalSubTab: String, CaseIterable, Identifiable {
    case daily = "Nhật Ký Ngày"
    case calendar = "Lịch P&L"
    case notebook = "Sổ Tay"
    case routines = "Thói Quen"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .daily: return "calendar.day.timeline.left"
        case .calendar: return "calendar"
        case .notebook: return "book.closed"
        case .routines: return "checklist"
        }
    }
}

/// Trung tâm điều phối tính năng Nhật ký giao dịch
/// Kết hợp 4 màn hình: Nhật ký ngày, Lịch P&L tháng, Sổ tay ghi chép, Thói quen kỷ luật
public struct JournalHubView: View {
    @State private var selectedSubTab: JournalSubTab = .daily
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Navigation Header theo chuẩn Apple HIG
            Picker("Phần nhật ký", selection: $selectedSubTab) {
                ForEach(JournalSubTab.allCases) { tab in
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
            case .daily:
                DailyJournalListView()
            case .calendar:
                JournalCalendarView()
            case .notebook:
                NotebookView()
            case .routines:
                ProgressRoutinesView()
            }
        }
        .background(AppColors.background)
    }
}
