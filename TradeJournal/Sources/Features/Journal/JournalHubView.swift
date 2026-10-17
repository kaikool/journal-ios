import SwiftUI

public enum JournalSubTab: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case calendar = "Calendar"
    case notebook = "Notebook"
    case routines = "Routines"
    
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

/// Journal hub navigation view providing access to:
/// - Daily journal logs
/// - Monthly P&L calendar
/// - Trading notebook & folders
/// - Discipline routines & progress checklist
public struct JournalHubView: View {
    @State private var selectedSubTab: JournalSubTab = .daily
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Navigation Header adhering to Apple HIG
            Picker("Journal Section", selection: $selectedSubTab) {
                ForEach(JournalSubTab.allCases) { tab in
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
