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
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Build a repeatable trading day.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    showAddRoutineSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New Routine")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppColors.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.clear)
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
        .alert("Archive Routine", isPresented: $showArchiveAlert, presenting: ruleToArchive) { rule in
            Button("Archive") {
                dataStore.archiveProgressRule(id: rule.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text("“\(rule.title)” will be hidden from daily checklists starting today. Past days' completion records are preserved.")
        }
        .alert("Delete Routine Permanently?", isPresented: $showDeleteAlert, presenting: ruleToDelete) { rule in
            Button("Delete Permanently", role: .destructive) {
                dataStore.deleteProgressRule(id: rule.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text("“\(rule.title)” will be completely removed from your device and cloud sync. All logs will be deleted and it will never appear again.")
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
                            .font(.system(size: 26, weight: .bold))
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
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.brand)
                            Text(activeDate == todayKey ? "Today" : activeDate)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.secondaryBackground)
                        .clipShape(Capsule())
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
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("\(rulesForStage.filter { isRuleChecked($0.id) }.count)/\(rulesForStage.count)")
                        .font(AppTypography.captionBold)
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
                                Button {
                                    dataStore.toggleProgressCheck(ruleId: rule.id, date: activeDate)
                                } label: {
                                    Image(systemName: isRuleChecked(rule.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 17))
                                        .foregroundColor(isRuleChecked(rule.id) ? AppColors.brand : AppColors.secondaryText)
                                }
                                .buttonStyle(.plain)
                                
                                Text(rule.title)
                                    .font(AppTypography.subheadline)
                                    .foregroundColor(isRuleChecked(rule.id) ? AppColors.secondaryText : AppColors.primaryText)
                                    .strikethrough(isRuleChecked(rule.id))
                                
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
                                        .font(.system(size: 14, weight: .bold))
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
                        Button {
                            selectedDate = item.date
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(percent: item.percent, total: item.total))
                                .aspectRatio(1.0, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(activeDate == item.date ? AppColors.primaryText : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
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
                    Button {
                        showArchivedSheet = true
                    } label: {
                        Text("Manage")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.brand)
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

/// Sheet to add or edit a daily disciplined routine with Apple HIG dark luxury cards
public struct AddProgressRoutineSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    public var routineToEdit: ProgressRule?
    
    @State private var title: String
    @State private var stage: String
    @State private var selectedDays: Set<Int>
    
    private let weekdayNames = [
        (0, "Sun"),
        (1, "Mon"),
        (2, "Tue"),
        (3, "Wed"),
        (4, "Thu"),
        (5, "Fri"),
        (6, "Sat")
    ]
    
    private static let quickSuggestions = [
        "Review ForexFactory Calendar",
        "Mark HTF Key Levels & Liquidity",
        "Enforce Max 1R Risk Per Trade",
        "Capture Entry & Exit Screenshot",
        "Perform Daily Post-Mortem Review"
    ]
    
    private static let stageMetadata: [(id: String, icon: String, subtitle: String)] = [
        ("Before trading", "sunrise.fill", "Pre-session preparation"),
        ("During trading", "chart.line.uptrend.xyaxis", "Active market execution"),
        ("After trading", "moon.stars.fill", "Post-market audit & review")
    ]
    
    public init(routineToEdit: ProgressRule? = nil) {
        self.routineToEdit = routineToEdit
        _title = State(initialValue: routineToEdit?.title ?? "")
        _stage = State(initialValue: routineToEdit?.stage ?? ProgressRoutinesView.stages[0])
        if let existing = routineToEdit {
            _selectedDays = State(initialValue: existing.activeWeekdays)
        } else {
            _selectedDays = State(initialValue: [1, 2, 3, 4, 5])
        }
    }
    
    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedDays.isEmpty
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Bar
                headerBar
                
                Divider()
                    .background(AppColors.border.opacity(0.5))
                
                ScrollView {
                    VStack(spacing: 14) {
                        // Card 1: Routine Title & Suggestions
                        routineTitleCard
                        
                        // Card 2: Execution Stage Selector
                        stageSelectionCard
                        
                        // Card 3: Scheduled Days
                        scheduledDaysCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppColors.background)
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center) {
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dismiss()
            } label: {
                Text("Cancel")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            Text(routineToEdit == nil ? "NEW ROUTINE" : "EDIT ROUTINE")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .tracking(0.5)
            
            Spacer()
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                saveRoutine()
            } label: {
                Text(routineToEdit == nil ? "Add" : "Save")
                    .font(AppTypography.headline)
                    .foregroundColor(isFormValid ? AppColors.brand : AppColors.secondaryText.opacity(0.5))
            }
            .disabled(!isFormValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground)
    }
    
    // MARK: - Card 1: Routine Title Card
    private var routineTitleCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("ROUTINE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text("Define a specific, measurable trading habit.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.brand)
                    
                    TextField("e.g. Check ForexFactory Calendar", text: $title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                    
                    if !title.isEmpty {
                        Button {
                            title = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.secondaryText)
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.8), lineWidth: 0.5)
                )
                
                // Quick suggestions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .textCase(.uppercase)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.quickSuggestions, id: \.self) { suggestion in
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    title = suggestion
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(suggestion)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(title == suggestion ? AppColors.brand : AppColors.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(title == suggestion ? AppColors.brand.opacity(0.12) : AppColors.secondaryBackground)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(title == suggestion ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: 0.6)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Card 2: Stage Selection Card
    private var stageSelectionCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHEN")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text("Choose the phase in your daily execution workflow.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(spacing: 8) {
                    ForEach(Self.stageMetadata, id: \.id) { meta in
                        let isSelected = stage == meta.id
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            stage = meta.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: meta.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meta.id)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                        .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                                    
                                    Text(meta.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isSelected ? AppColors.brand : AppColors.border)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(isSelected ? AppColors.brand.opacity(0.12) : AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.5), lineWidth: isSelected ? 1.0 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Card 3: Scheduled Days Card
    private var scheduledDaysCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SCHEDULED DAYS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Quick Presets
                    HStack(spacing: 6) {
                        Button("Mon-Fri") {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedDays = [1, 2, 3, 4, 5]
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selectedDays == [1, 2, 3, 4, 5] ? AppColors.brand : AppColors.secondaryText)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.border)
                        
                        Button("All Days") {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            selectedDays = [0, 1, 2, 3, 4, 5, 6]
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selectedDays.count == 7 ? AppColors.brand : AppColors.secondaryText)
                    }
                }
                
                HStack(spacing: 6) {
                    ForEach(weekdayNames, id: \.0) { day in
                        let isSelected = selectedDays.contains(day.0)
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            if isSelected {
                                if selectedDays.count > 1 {
                                    selectedDays.remove(day.0)
                                }
                            } else {
                                selectedDays.insert(day.0)
                            }
                        } label: {
                            Text(day.1)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? AppColors.brand : AppColors.secondaryBackground)
                                .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.secondaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelected ? AppColors.brand : AppColors.border.opacity(0.6), lineWidth: 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    private func saveRoutine() {
        let daysArr = Array(selectedDays).sorted()
        let jsonStr = "[\(daysArr.map(String.init).joined(separator: ","))]"
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = ProgressRule(
            id: routineToEdit?.id ?? JournalIds.newId(),
            title: cleanTitle,
            stage: stage,
            weekdaysJson: jsonStr,
            createdAt: routineToEdit?.createdAt ?? JournalIds.nowIso(),
            archivedAt: routineToEdit?.archivedAt
        )
        dataStore.saveProgressRule(rule)
        dismiss()
    }
}

/// Sheet displaying all archived routines with options to restore or delete permanently.
public struct ArchivedProgressRoutinesSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var ruleToDelete: ProgressRule? = nil
    @State private var showDeleteAlert: Bool = false
    
    private var archivedRules: [ProgressRule] {
        dataStore.progressRules.filter { !dataStore.deletedProgressRuleIds.contains($0.id) && $0.isArchived }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("ARCHIVED ROUTINES")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .tracking(0.5)
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.brand)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppColors.cardBackground)
                
                Divider()
                    .background(AppColors.border.opacity(0.5))
                
                if archivedRules.isEmpty {
                    emptyArchivedView
                } else {
                    archivedListView
                }
            }
            .background(AppColors.background)
            .alert("Delete Routine Permanently?", isPresented: $showDeleteAlert, presenting: ruleToDelete) { rule in
                Button("Delete Permanently", role: .destructive) {
                    dataStore.deleteProgressRule(id: rule.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { rule in
                Text("“\(rule.title)” will be completely removed from your device and cloud sync. All logs will be deleted and it will never appear again.")
            }
        }
    }
    
    private var emptyArchivedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 40))
                .foregroundColor(AppColors.secondaryText.opacity(0.4))
            Text("No archived routines")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var archivedListView: some View {
        List {
            ForEach(archivedRules) { rule in
                archivedRow(rule)
            }
        }
        .listStyle(.plain)
        .background(AppColors.background)
    }
    
    private func archivedRow(_ rule: ProgressRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.primaryText)
                Text(rule.stage)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            Button {
                dataStore.unarchiveProgressRule(id: rule.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.bin")
                    Text("Restore")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.brand.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Button {
                ruleToDelete = rule
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.loss.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(AppColors.secondaryBackground)
    }
}
