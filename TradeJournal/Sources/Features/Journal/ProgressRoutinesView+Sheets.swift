import SwiftUI

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
        "Mark HTF Key Levels & Range",
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
        _stage = State(initialValue: routineToEdit?.stage ?? ProgressRoutinesView.stages.first ?? "Before trading")
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
            ScrollView {
                VStack(spacing: 14) {
                    routineTitleCard
                    stageSelectionCard
                    scheduledDaysCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.background)
            .navigationTitle(routineToEdit == nil ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton(routineToEdit == nil ? "Add" : "Save", isEnabled: isFormValid) {
                        saveRoutine()
                    }
                }
            }
        }
    }
    
    // MARK: - Card 1: Routine Title Card
    private var routineTitleCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("ROUTINE")
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text("Define a specific, measurable trading habit.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                AppTextField(
                    "e.g. Check ForexFactory Calendar",
                    text: $title,
                    icon: "checklist",
                    showClearButton: true
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .textCase(.uppercase)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.quickSuggestions, id: \.self) { suggestion in
                                AppFilterChip(suggestion, isSelected: title == suggestion, icon: "plus", height: 26) {
                                    title = suggestion
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
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text("Choose the phase in your daily execution workflow.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(spacing: 8) {
                    ForEach(Self.stageMetadata, id: \.id) { meta in
                        let isSelected = stage == meta.id
                        HStack(spacing: 12) {
                            Image(systemName: meta.icon)
                                .font(AppTypography.cardHeader)
                                .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meta.id)
                                    .font(isSelected ? AppTypography.rowPrimary : AppTypography.rowTitle)
                                    .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                                
                                Text(meta.subtitle)
                                    .font(AppTypography.captionMicro)
                                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                            }
                            
                            Spacer()
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(AppTypography.rowPrimary)
                                .foregroundColor(isSelected ? AppColors.brand : AppColors.border)
                        }
                        .appSubCardStyle(cornerRadius: 10, padding: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.5), lineWidth: isSelected ? 1.0 : 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NativeHaptics.lightImpact()
                            stage = meta.id
                        }
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
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        AppFilterChip("Mon-Fri", isSelected: selectedDays == [1, 2, 3, 4, 5], height: 24) {
                            NativeHaptics.lightImpact()
                            selectedDays = [1, 2, 3, 4, 5]
                        }
                        
                        AppFilterChip("All Days", isSelected: selectedDays.count == 7, height: 24) {
                            NativeHaptics.lightImpact()
                            selectedDays = [0, 1, 2, 3, 4, 5, 6]
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    ForEach(weekdayNames, id: \.0) { day in
                        let isSelected = selectedDays.contains(day.0)
                        AppFilterChip(day.1, isSelected: isSelected) {
                            if isSelected {
                                if selectedDays.count > 1 {
                                    selectedDays.remove(day.0)
                                }
                            } else {
                                selectedDays.insert(day.0)
                            }
                        }
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
            Group {
                if archivedRules.isEmpty {
                    emptyArchivedView
                } else {
                    archivedListView
                }
            }
            .background(AppColors.background)
            .navigationTitle("Archived Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Done") {
                        dismiss()
                    }
                }
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
    }
    
    private var emptyArchivedView: some View {
        AppEmptyState(
            icon: "archivebox",
            title: "No archived routines",
            message: "Routines you archive will be stored here for future reactivation.",
            iconColor: AppColors.secondaryText
        )
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
            
            AppSecondaryButton("Restore", icon: "arrow.up.bin", height: 28) {
                dataStore.unarchiveProgressRule(id: rule.id)
            }
            
            ModalDeleteButton {
                ruleToDelete = rule
                showDeleteAlert = true
            }
        }
        .listRowBackground(AppColors.secondaryBackground)
    }
}
