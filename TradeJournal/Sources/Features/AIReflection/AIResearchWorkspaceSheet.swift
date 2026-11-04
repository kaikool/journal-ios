import SwiftUI

// MARK: - AI Research Workspace Sheet (Module E - Research Lab)
/// Enables traders to formulate quantitative hypotheses, track empirical sample collection,
/// monitor win rate & profit factor progress, record checkpoints, and validate or refute trading ideas.
/// Designed with 100% fidelity to the sleek, restrained dark theme of AIReflectionView.
public struct AIResearchWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var projects: [AIResearchProject] = []
    @State private var selectedStatus: AIResearchProjectStatus? = .active
    @State private var searchQuery: String = ""
    @State private var isSyncing: Bool = false
    
    // Sheets & Dialogs
    @State private var isCreatingProject: Bool = false
    @State private var projectForCheckpoint: AIResearchProject? = nil
    @State private var projectForConclusion: AIResearchProject? = nil
    @State private var conclusionStatus: AIResearchProjectStatus = .validated
    @State private var projectToDelete: AIResearchProject? = nil
    @State private var showDeleteConfirmation: Bool = false
    
    public init() {}
    
    // MARK: - Filtered Projects
    private var filteredProjects: [AIResearchProject] {
        projects.filter { p in
            if let st = selectedStatus, p.status != st {
                return false
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let titleMatch = p.title.lowercased().contains(q)
                let hypMatch = p.hypothesis.lowercased().contains(q)
                let symMatch = p.criteria.symbols.contains { $0.lowercased().contains(q) }
                if !titleMatch && !hypMatch && !symMatch {
                    return false
                }
            }
            return true
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Scope Header Bar (Matching AIReflectionScopeHeader)
                    scopeHeaderBar
                    
                    // 2. Search Bar
                    searchBarSection
                    
                    // 3. Status Filter Chips (Matching AIReflectionCategoryChips)
                    statusFilterSection
                    
                    // 4. Project Cards or Empty State
                    if filteredProjects.isEmpty {
                        emptyStateView
                    } else {
                        projectCardsListView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("Research Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("New Project", icon: "plus") {
                        isCreatingProject = true
                    }
                }
            }
            .onAppear(perform: reloadProjects)
            .sheet(isPresented: $isCreatingProject) {
                NewResearchProjectSheet(onCreated: { _ in
                    reloadProjects()
                })
            }
            .sheet(item: $projectForCheckpoint) { proj in
                AddResearchCheckpointSheet(project: proj, onSaved: {
                    reloadProjects()
                })
            }
            .sheet(item: $projectForConclusion) { proj in
                ConcludeResearchProjectSheet(project: proj, targetStatus: conclusionStatus, onSaved: {
                    reloadProjects()
                })
            }
            .appConfirmationAlert(
                isPresented: $showDeleteConfirmation,
                presenting: projectToDelete,
                title: { _ in "Delete Research Project?" },
                message: { p in "Project '\(p.title)' and all its checkpoint history will be removed." }
            ) { p in
                AIResearchWorkspaceEngine.shared.deleteProject(projectId: p.id)
                reloadProjects()
            }
        }
    }
    
    // MARK: - 1. Scope Header Bar
    private var scopeHeaderBar: some View {
        HStack {
            let activeCount = projects.filter { $0.status == .active }.count
            Text("Research Lab • \(projects.count) Projects • \(activeCount) Active")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Spacer()
            
            if isSyncing {
                TradeJournalProLoader(size: 20)
            } else {
                AppActionPill("Sync", icon: "arrow.triangle.2.circlepath", action: performSync)
                .buttonStyle(.plain)
            }
        }
        .appCardStyle(cornerRadius: 10)
    }
    
    // MARK: - 2. Search Bar
    private var searchBarSection: some View {
        AppSearchBar("Search projects, hypotheses, instruments...", text: $searchQuery)
    }
    
    // MARK: - 3. Status Filter Chips (Standardized with AIReflectionCategoryChips)
    private var statusFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusFilterChip(title: "Active", status: .active)
                statusFilterChip(title: "All", status: nil)
                statusFilterChip(title: "Validated", status: .validated)
                statusFilterChip(title: "Invalidated", status: .invalidated)
                statusFilterChip(title: "Paused", status: .paused)
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func statusFilterChip(title: String, status: AIResearchProjectStatus?) -> some View {
        let isSelected = selectedStatus == status
        let count = projects.filter { status == nil ? true : $0.status == status }.count
        
        return AppFilterChip(title, isSelected: isSelected, count: count) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedStatus = status
            }
        }
    }
    
    // MARK: - 4. Project Cards List
    private var projectCardsListView: some View {
        VStack(spacing: 12) {
            ForEach(filteredProjects) { project in
                AIResearchProjectCard(
                    project: project,
                    onAddCheckpoint: {
                        projectForCheckpoint = project
                    },
                    onValidate: {
                        conclusionStatus = .validated
                        projectForConclusion = project
                    },
                    onInvalidate: {
                        conclusionStatus = .invalidated
                        projectForConclusion = project
                    },
                    onTogglePause: {
                        let next: AIResearchProjectStatus = (project.status == .paused) ? .active : .paused
                        AIResearchWorkspaceEngine.shared.updateStatus(projectId: project.id, status: next, conclusion: nil)
                        reloadProjects()
                    },
                    onDelete: {
                        projectToDelete = project
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        AppCard {
            AppEmptyState(
                icon: "flask.fill",
                title: "No Research Projects Found",
                message: projects.isEmpty ? "Track systematic hypotheses with live trade sample sizes before committing them to your playbook." : "No projects match the current filter or search criteria.",
                iconColor: AppColors.brand,
                actionTitle: "Create Project",
                actionIcon: "plus",
                isInCard: true
            ) {
                isCreatingProject = true
            }
        }
    }
    
    // MARK: - Reload & Sync
    private func reloadProjects() {
        self.projects = AIResearchWorkspaceEngine.shared.getAllProjects()
    }
    
    private func performSync() {
        isSyncing = true
        Task {
            await AIResearchWorkspaceEngine.shared.syncWithRemote()
            await MainActor.run {
                reloadProjects()
                isSyncing = false
            }
        }
    }
}

// MARK: - Research Project Card (Restrained, Apple HIG & Parity with AppCard)
private struct AIResearchProjectCard: View {
    let project: AIResearchProject
    let onAddCheckpoint: () -> Void
    let onValidate: () -> Void
    let onInvalidate: () -> Void
    let onTogglePause: () -> Void
    let onDelete: () -> Void
    
    @State private var showCheckpoints: Bool = false
    
    private var progressRatio: Double {
        let minSize = max(project.criteria.minSampleSize, 1)
        return min(1.0, Double(project.sampleCount) / Double(minSize))
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeaderView
                
                // Title
                Text(project.title)
                    .font(AppTypography.rowTitle)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                
                cardHypothesisView
                cardProgressView
                cardMetricsView
                cardConclusionView
                cardCheckpointsTimelineView
                cardBottomBarView
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Sub-Views for Fast Type-Checking
    
    private var cardHeaderView: some View {
        HStack(spacing: 6) {
            statusBadge(project.status)
            
            if !project.criteria.symbols.isEmpty {
                AppBadge(project.criteria.symbols.joined(separator: ", "), variant: .secondary)
            }
            
            if !project.criteria.timeframes.isEmpty {
                AppBadge(project.criteria.timeframes.joined(separator: "/"), variant: .secondary)
            }
            
            Spacer()
            
            Menu {
                Button(action: onAddCheckpoint) {
                    Label("Add Checkpoint", systemImage: "plus.circle")
                }
                
                if project.status == .active {
                    Button(action: onValidate) {
                        Label("Validate Hypothesis", systemImage: "checkmark.seal")
                    }
                    Button(action: onInvalidate) {
                        Label("Invalidate Hypothesis", systemImage: "xmark.seal")
                    }
                    Button(action: onTogglePause) {
                        Label("Pause Research", systemImage: "pause.circle")
                    }
                } else if project.status == .paused {
                    Button(action: onTogglePause) {
                        Label("Resume Research", systemImage: "play.circle")
                    }
                }
                
                Divider()
                
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Project", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppTypography.actionButtonCompact)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(4)
            }
        }
    }
    
    private var cardHypothesisView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            
            Text(project.hypothesis)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .italic()
        }
        .appSubCardStyle(cornerRadius: 8, padding: 9)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
        )
    }
    
    private var cardProgressView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Sample Progress:")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text("\(project.sampleCount) / \(project.criteria.minSampleSize) trades")
                    .font(AppTypography.numberCaption)
                    .foregroundColor(AppColors.primaryText)
                Text("(\(Int(progressRatio * 100))%)")
                    .font(AppTypography.microCaption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.input)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressRatio >= 1.0 ? AppColors.profit : AppColors.brand)
                        .frame(width: max(4, geo.size.width * CGFloat(progressRatio)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
    
    private var cardMetricsView: some View {
        HStack(spacing: 8) {
            AppMetricTile(
                "Win Rate",
                value: project.winRate.map { Formatters.formatPercent($0) } ?? "--",
                color: (project.winRate ?? 0) >= 50.0 ? AppColors.profit : AppColors.primaryText,
                trend: project.winRate.map { $0 >= 50.0 ? .up : .down }
            )
            AppMetricTile(
                "Profit Factor",
                value: project.profitFactor.map { Formatters.formatDecimal(Decimal($0), maxDecimals: 2) } ?? "--",
                color: (project.profitFactor ?? 0) >= 1.5 ? AppColors.profit : AppColors.primaryText
            )
            AppMetricTile(
                "Checkpoints",
                value: "\(project.checkpoints.count)",
                color: AppColors.primaryText
            )
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private var cardConclusionView: some View {
        if let conclusion = project.conclusion, !conclusion.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: project.status == .validated ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(AppTypography.badgeMicro)
                    Text(project.status == .validated ? "CONCLUSION: VALIDATED" : "CONCLUSION: INVALIDATED")
                        .font(AppTypography.badgeMicro)
                }
                .foregroundColor(project.status == .validated ? AppColors.profit : AppColors.loss)
                
                Text(conclusion)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .appSubCardStyle(cornerRadius: 8, padding: 9)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
            )
        }
    }
    
    @ViewBuilder
    private var cardCheckpointsTimelineView: some View {
        if !project.checkpoints.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: showCheckpoints ? "chevron.down" : "chevron.right")
                    .font(AppTypography.captionMicro)
                Text(showCheckpoints ? "Hide checkpoints (\(project.checkpoints.count))" : "View checkpoints (\(project.checkpoints.count))")
                    .font(AppTypography.captionMicro)
                Spacer()
            }
            .foregroundColor(AppColors.brand)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                NativeHaptics.lightImpact()
                withAnimation(AppAnimations.springQuick) {
                    showCheckpoints.toggle()
                }
            }
            
            if showCheckpoints {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(project.checkpoints.sorted(by: { $0.timestamp > $1.timestamp })) { chk in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Sample: \(chk.sampleCount) trades")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                if let wr = chk.winRate {
                                    Text("• WR: \(Formatters.formatPercent(wr))")
                                        .font(AppTypography.numberMicro)
                                        .foregroundColor(wr >= 50.0 ? AppColors.profit : AppColors.secondaryText)
                                }
                                if let pf = chk.profitFactor {
                                    Text("• PF: \(Formatters.formatDecimal(Decimal(pf), maxDecimals: 2))")
                                        .font(AppTypography.numberMicro)
                                        .foregroundColor(pf >= 1.5 ? AppColors.profit : AppColors.secondaryText)
                                }
                                Spacer()
                                Text(Formatters.shortMonthDayTime(chk.timestamp))
                                    .font(AppTypography.microCaption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            if !chk.notes.isEmpty {
                                Text(chk.notes)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        .appSubCardStyle(cornerRadius: 6, padding: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private var cardBottomBarView: some View {
        HStack {
            AppSecondaryButton("Record Checkpoint", icon: "plus", height: 32, action: onAddCheckpoint)
            Spacer()
        }
        .padding(.top, 2)
    }
    
    @ViewBuilder
    private func statusBadge(_ st: AIResearchProjectStatus) -> some View {
        switch st {
        case .active:
            AppBadge("Active", variant: .brand)
        case .validated:
            AppBadge("Validated", variant: .profit)
        case .invalidated:
            AppBadge("Invalidated", variant: .loss)
        case .paused:
            AppBadge("Paused", variant: .secondary)
        case .archived:
            AppBadge("Archived", variant: .secondary)
        }
    }
}

// MARK: - New Research Project Sheet (Clean Dark Terminal Styling)
private struct NewResearchProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onCreated: (AIResearchProject) -> Void
    
    @State private var title: String = ""
    @State private var hypothesis: String = ""
    @State private var symbols: String = "XAUUSD, EURUSD"
    @State private var timeframes: String = "15m, 4h"
    @State private var minSampleSize: Int = 30
    
    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Title & working hypothesis")
                            
                            AppFormField(
                                "Project Title",
                                text: $title,
                                placeholder: "e.g. H4 Breaker Block + M15 FVG",
                                height: 42
                            )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hypothesis Description")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                TextEditor(text: $hypothesis)
                                    .font(AppTypography.inputText)
                                    .frame(minHeight: 100)
                                    .appSubCardStyle(cornerRadius: 10, padding: 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                                    )
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Scope & sample criteria")
                            
                            AppFormField(
                                "Target Symbols",
                                text: $symbols,
                                placeholder: "e.g. XAUUSD, EURUSD",
                                height: 42
                            )
                            
                            AppFormField(
                                "Timeframes",
                                text: $timeframes,
                                placeholder: "e.g. 15m, 4h",
                                height: 42
                            )
                            
                            HStack {
                                Text("Minimum Sample Size:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("\(minSampleSize) trades")
                                    .font(AppTypography.numberSmall)
                                    .foregroundColor(AppColors.primaryText)
                                Stepper("", value: $minSampleSize, in: 10...200, step: 5)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle("New Research Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Create", isEnabled: isFormValid) {
                        let symArr = symbols.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                            .filter { !$0.isEmpty }
                        let tfArr = timeframes.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        let criteria = AIResearchSampleCriteria(
                            symbols: symArr,
                            timeframes: tfArr,
                            minSampleSize: minSampleSize
                        )
                        
                        let newProj = AIResearchWorkspaceEngine.shared.createProject(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            hypothesis: hypothesis.trimmingCharacters(in: .whitespacesAndNewlines),
                            criteria: criteria
                        )
                        onCreated(newProj)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add Research Checkpoint Sheet (Clean Dark Terminal Styling)
private struct AddResearchCheckpointSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let project: AIResearchProject
    let onSaved: () -> Void
    
    @State private var sampleCount: Int = 10
    @State private var winRateText: String = ""
    @State private var profitFactorText: String = ""
    @State private var notes: String = ""
    
    public init(project: AIResearchProject, onSaved: @escaping () -> Void) {
        self.project = project
        self.onSaved = onSaved
        _sampleCount = State(initialValue: max(project.sampleCount + 1, 1))
        _winRateText = State(initialValue: project.winRate.map { Formatters.formatDecimalInput(Decimal($0), maxDecimals: 1) } ?? "")
        _profitFactorText = State(initialValue: project.profitFactor.map { Formatters.formatDecimalInput(Decimal($0), maxDecimals: 2) } ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("Sample & performance metrics")
                            
                            HStack {
                                Text("Trades Sampled:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("\(sampleCount) trades")
                                    .font(AppTypography.numberSmall)
                                    .foregroundColor(AppColors.primaryText)
                                Stepper("", value: $sampleCount, in: 1...500)
                                    .labelsHidden()
                            }
                            
                            HStack(spacing: 10) {
                                AppNumericField(
                                    "Win Rate %",
                                    text: $winRateText,
                                    placeholder: "e.g. 62.5",
                                    unit: "%",
                                    height: 38
                                )
                                
                                AppNumericField(
                                    "Profit Factor",
                                    text: $profitFactorText,
                                    placeholder: "e.g. 1.85",
                                    height: 38
                                )
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Observations & qualitative notes")
                            
                            TextEditor(text: $notes)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 100)
                                .appSubCardStyle(cornerRadius: 10, padding: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle("Record Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Save") {
                        let wr = Double(winRateText.replacingOccurrences(of: ",", with: "."))
                        let pf = Double(profitFactorText.replacingOccurrences(of: ",", with: "."))
                        
                        let chk = AIResearchCheckpoint(
                            sampleCount: sampleCount,
                            winRate: wr,
                            profitFactor: pf,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        
                        AIResearchWorkspaceEngine.shared.addCheckpoint(projectId: project.id, checkpoint: chk)
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Conclude Research Project Sheet (Clean Dark Terminal Styling)
private struct ConcludeResearchProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let project: AIResearchProject
    let targetStatus: AIResearchProjectStatus
    let onSaved: () -> Void
    
    @State private var conclusionText: String = ""
    
    public init(project: AIResearchProject, targetStatus: AIResearchProjectStatus, onSaved: @escaping () -> Void) {
        self.project = project
        self.targetStatus = targetStatus
        self.onSaved = onSaved
        _conclusionText = State(initialValue: project.conclusion ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EMPIRICAL CONCLUSION")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            HStack(spacing: 6) {
                                Image(systemName: targetStatus == .validated ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(AppTypography.captionBold)
                                Text(targetStatus == .validated ? "Confirming hypothesis as validated rule" : "Refuting hypothesis due to adverse metrics")
                                    .font(AppTypography.captionBold)
                            }
                            .foregroundColor(targetStatus == .validated ? AppColors.profit : AppColors.loss)
                            
                            TextEditor(text: $conclusionText)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 120)
                                .appSubCardStyle(cornerRadius: 8, padding: 8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle(targetStatus == .validated ? "Validate Hypothesis" : "Invalidate Hypothesis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Save") {
                        AIResearchWorkspaceEngine.shared.updateStatus(
                            projectId: project.id,
                            status: targetStatus,
                            conclusion: conclusionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
