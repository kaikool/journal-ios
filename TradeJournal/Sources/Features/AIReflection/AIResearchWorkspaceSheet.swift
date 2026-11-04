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

