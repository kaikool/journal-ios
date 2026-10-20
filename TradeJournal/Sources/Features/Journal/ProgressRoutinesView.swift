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
    @State private var ruleToArchive: ProgressRule? = nil
    @State private var showArchiveAlert: Bool = false
    
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
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
                                Text("Routine")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppColors.brandPrimary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    
                    // Card 1: Daily completion & Date selector
                    completionScoreCard
                    
                    // Card 2: 3 Stages checklist (Before, During, After trading)
                    stagesSection
                    
                    // Card 3: 13-week heatmap streak (Last 91 days)
                    heatmapCard
                }
                .padding(.bottom, 88)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showAddRoutineSheet) {
            AddProgressRoutineSheet()
        }
        .alert("Archive routine", isPresented: $showArchiveAlert, presenting: ruleToArchive) { rule in
            Button("Archive", role: .destructive) {
                dataStore.deleteProgressRule(id: rule.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text("Archive “\(rule.title)”? Previous days are preserved.")
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
                            .font(.system(size: 26, weight: .bold, design: .rounded))
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
            guard r.archivedAt == nil else { return false }
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
                                
                                Button {
                                    ruleToArchive = rule
                                    showArchiveAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                                }
                                .buttonStyle(.plain)
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
}

/// Sheet to add a new daily disciplined routine
public struct AddProgressRoutineSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var stage: String = ProgressRoutinesView.stages[0]
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5] // Monday - Friday default
    
    private let weekdayNames = [
        (0, "Sun"),
        (1, "Mon"),
        (2, "Tue"),
        (3, "Wed"),
        (4, "Thu"),
        (5, "Fri"),
        (6, "Sat")
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Routine")) {
                    TextField("e.g. Review the economic calendar", text: $title)
                        .font(AppTypography.body)
                }
                
                Section(header: Text("When")) {
                    AppDropdownField(
                        label: "Stage",
                        selection: $stage,
                        options: ProgressRoutinesView.stages,
                        titleFor: { $0 }
                    )
                }
                
                Section(header: Text("Scheduled days")) {
                    HStack {
                        ForEach(weekdayNames, id: \.0) { day in
                            let isSelected = selectedDays.contains(day.0)
                            Button {
                                if isSelected {
                                    selectedDays.remove(day.0)
                                } else {
                                    selectedDays.insert(day.0)
                                }
                            } label: {
                                Text(day.1)
                                    .font(AppTypography.captionBold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? AppColors.brand : AppColors.secondaryBackground)
                                    .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add a daily routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add routine") {
                        saveRoutine()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDays.isEmpty)
                    .font(AppTypography.headline)
                }
            }
        }
    }
    
    private func saveRoutine() {
        let daysArr = Array(selectedDays).sorted()
        let jsonStr = "[\(daysArr.map(String.init).joined(separator: ","))]"
        let rule = ProgressRule(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            stage: stage,
            weekdaysJson: jsonStr
        )
        dataStore.saveProgressRule(rule)
        dismiss()
    }
}
