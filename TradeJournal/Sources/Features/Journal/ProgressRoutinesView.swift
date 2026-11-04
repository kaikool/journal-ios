import SwiftUI

/// Screen managing daily disciplined trading routines.
/// Ported 1:1 from `source-repo/apps/web/src/app/progress/page.tsx`:
/// - FilterBar with title "Progress" and "Add routine" button
/// - Subtitle: "Build a repeatable trading day. Routines are tracked independently of trade filters and profit."
/// - Daily completion score card with date picker & progress bar
/// - 3 stage checklist cards: "Before trading", "During trading", "After trading"
/// - 13-week streak heatmap (last 91 days)
public struct ProgressRoutinesView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedDate: String = ""
    @State private var showAddRoutineSheet: Bool = false
    @State private var ruleToEdit: ProgressRule? = nil
    @State private var ruleToArchive: ProgressRule? = nil
    @State private var showArchiveAlert: Bool = false
    @State private var ruleToDelete: ProgressRule? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var showArchivedSheet: Bool = false
    
    public static let stages = ["Before trading", "During trading", "After trading"]
    
    public init() {}
    
    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        return formatter.string(from: Date())
    }
    
    private var activeDate: String {
        selectedDate.isEmpty ? todayKey : selectedDate
    }
    
    private var score: (completed: Int, total: Int, percent: Double) {
        dataStore.progressScore(for: activeDate)
    }
    
    /// Last 91 days (13 weeks) for the routine heatmap
    private var past91Days: [(date: String, percent: Double, completed: Int, total: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<91).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dStr = formatter.string(from: d)
            let s = dataStore.progressScore(for: dStr)
            return (date: dStr, percent: s.percent, completed: s.completed, total: s.total)
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Card 1: Daily completion & Date selector
                completionScoreCard
                
                // Card 2: 3 Stages checklist (Before, During, After trading)
                stagesSection
                
                // Card 3: 13-week heatmap streak (Last 91 days)
                heatmapCard
                
                // Card 4: Archived routines (if any)
                if archivedRulesCount > 0 {
                    archivedSection
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 88)
        }
        .onReceive(env.$requestNewRoutine) { requested in
            if requested {
                env.requestNewRoutine = false
                showAddRoutineSheet = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .sheet(isPresented: $showAddRoutineSheet) {
            AddProgressRoutineSheet()
        }
        .sheet(item: $ruleToEdit) { rule in
            AddProgressRoutineSheet(routineToEdit: rule)
        }
        .sheet(isPresented: $showArchivedSheet) {
            ArchivedProgressRoutinesSheet()
        }
        .appConfirmationAlert(
            isPresented: $showArchiveAlert,
            presenting: ruleToArchive,
            title: { _ in "Archive Routine" },
            message: { rule in "“\(rule.title)” will be hidden from daily checklists starting today. Past days' completion records are preserved." },
            confirmTitle: "Archive",
            isDestructive: false
        ) { rule in
            dataStore.archiveProgressRule(id: rule.id)
        }
        .appConfirmationAlert(
            isPresented: $showDeleteAlert,
            presenting: ruleToDelete,
            title: { _ in "Delete Routine Permanently?" },
            message: { rule in "“\(rule.title)” will be completely removed from your device and cloud sync. All logs will be deleted and it will never appear again." },
            confirmTitle: "Delete Permanently"
        ) { rule in
            dataStore.deleteProgressRule(id: rule.id)
        }
    }
    
    // MARK: - Subviews
    
    private var completionScoreCard: some View {
        AppCard {
            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily completion")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("\(Int(score.percent * 100))%")
                            .font(AppTypography.displayHero)
                            .monospacedDigit()
                            .foregroundColor(score.percent >= 0.8 ? AppColors.profit : (score.percent >= 0.5 ? AppColors.brand : AppColors.secondaryText))
                        
                        Text("\(score.completed) of \(score.total) scheduled routines")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Review date selector
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Review date")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppBadge(activeDate == todayKey ? "Today" : activeDate, icon: "calendar", variant: .secondary)
                    }
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.secondaryBackground)
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(score.percent >= 0.8 ? AppColors.profit : AppColors.brand)
                            .frame(width: max(0, min(geo.size.width * CGFloat(score.percent), geo.size.width)), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var stagesSection: some View {
        VStack(spacing: 12) {
            ForEach(Self.stages, id: \.self) { stage in
                stageCard(stage)
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func stageCard(_ stage: String) -> some View {
        let rulesForStage = dataStore.progressRules.filter { r in
            guard !dataStore.deletedProgressRuleIds.contains(r.id) else { return false }
            guard r.isActive(on: activeDate) else { return false }
            guard r.isScheduled(on: activeDate) else { return false }
            if r.stage == stage { return true }
            if stage == "Before trading" && (r.stage.localizedCaseInsensitiveContains("before") || r.stage.localizedCaseInsensitiveContains("truoc")) { return true }
            if stage == "During trading" && (r.stage.localizedCaseInsensitiveContains("during") || r.stage.localizedCaseInsensitiveContains("trong")) { return true }
            if stage == "After trading" && (r.stage.localizedCaseInsensitiveContains("after") || r.stage.localizedCaseInsensitiveContains("sau")) { return true }
            return false
        }
        
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: stageIcon(stage))
                        .foregroundColor(AppColors.brand)
                    Text(stage)
                        .font(AppTypography.cardHeader)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("\(rulesForStage.filter { isRuleChecked($0.id) }.count)/\(rulesForStage.count)")
                        .font(AppTypography.badgeStandard)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Divider()
                
                if rulesForStage.isEmpty {
                    Text("No routines scheduled.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rulesForStage) { rule in
                            HStack(alignment: .center, spacing: 12) {
                                AppCheckboxRow(
                                    rule.title,
                                    isChecked: isRuleChecked(rule.id),
                                    isStrikethroughWhenChecked: true
                                ) {
                                    dataStore.toggleProgressCheck(ruleId: rule.id, date: activeDate)
                                }
                                
                                Spacer()
                                
                                Menu {
                                    Button {
                                        ruleToEdit = rule
                                    } label: {
                                        Label("Edit Routine", systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        ruleToArchive = rule
                                        showArchiveAlert = true
                                    } label: {
                                        Label("Archive Routine", systemImage: "archivebox")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        ruleToDelete = rule
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(AppTypography.cardHeader)
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .contextMenu {
                                Button {
                                    ruleToEdit = rule
                                } label: {
                                    Label("Edit Routine", systemImage: "pencil")
                                }
                                
                                Button {
                                    ruleToArchive = rule
                                    showArchiveAlert = true
                                } label: {
                                    Label("Archive Routine", systemImage: "archivebox")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    ruleToDelete = rule
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                }
                            }
                            
                            if rule.id != rulesForStage.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func isRuleChecked(_ ruleId: String) -> Bool {
        dataStore.progressChecks.contains { $0.ruleId == ruleId && $0.date == activeDate && $0.done }
    }
    
    private func stageIcon(_ stage: String) -> String {
        switch stage {
        case "Before trading": return "sunrise.fill"
        case "During trading": return "waveform.path.ecg"
        case "After trading": return "moon.stars.fill"
        default: return "checklist"
        }
    }
    
    private var heatmapCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last 13 weeks")
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                Text("Brighter squares mean a higher completion rate. Click a day to review it.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // 91-cell grid (13 columns x 7 rows)
                let columns = Array(repeating: GridItem(.flexible(minimum: 10, maximum: 24), spacing: 4), count: 13)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(past91Days, id: \.date) { item in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cellColor(percent: item.percent, total: item.total))
                            .aspectRatio(1.0, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(activeDate == item.date ? AppColors.primaryText : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                NativeHaptics.lightImpact()
                                selectedDate = item.date
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func cellColor(percent: Double, total: Int) -> Color {
        if total == 0 {
            return AppColors.secondaryBackground
        }
        if percent == 0 {
            return AppColors.secondaryBackground.opacity(0.8)
        }
        return AppColors.brand.opacity(0.2 + (percent * 0.8))
    }
    
    private var archivedRulesCount: Int {
        dataStore.progressRules.filter { !dataStore.deletedProgressRuleIds.contains($0.id) && $0.isArchived }.count
    }
    
    private var archivedSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(AppColors.secondaryText)
                    Text("Archived Routines (\(archivedRulesCount))")
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    AppActionPill("Manage", icon: "slider.horizontal.3") {
                        showArchivedSheet = true
                    }
                }
                
                Text("Archived routines are hidden from daily checklists. You can restore or permanently delete them at any time.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
    }
}

