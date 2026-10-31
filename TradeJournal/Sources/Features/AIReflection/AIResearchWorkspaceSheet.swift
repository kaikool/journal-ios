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
            .alert("Delete Research Project?", isPresented: $showDeleteConfirmation, presenting: projectToDelete) { p in
                Button("Delete", role: .destructive) {
                    AIResearchWorkspaceEngine.shared.deleteProject(projectId: p.id)
                    reloadProjects()
                }
                Button("Cancel", role: .cancel) {}
            } message: { p in
                Text("Project '\(p.title)' and all its checkpoint history will be removed.")
            }
        }
    }
    
    // MARK: - 1. Scope Header Bar
    private var scopeHeaderBar: some View {
        HStack {
            let activeCount = projects.filter { $0.status == .active }.count
            Text("Research Lab • \(projects.count) Projects • \(activeCount) Active")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Spacer()
            
            if isSyncing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.brand))
                    .scaleEffect(0.7)
            } else {
                Button(action: performSync) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .medium))
                        Text("Sync")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
    }
    
    // MARK: - 2. Search Bar
    private var searchBarSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.secondaryText)
                .font(.system(size: 13, weight: .medium))
            
            TextField("Search projects, hypotheses, instruments...", text: $searchQuery)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryText)
                .autocorrectionDisabled(true)
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.secondaryBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
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
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedStatus = status
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .opacity(0.7)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.secondaryBackground : Color.clear)
            .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? AppColors.border : AppColors.border.opacity(0.4), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 12) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    .padding(.top, 8)
                
                Text("No Research Projects Found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                
                Text(projects.isEmpty ? "Track systematic hypotheses with live trade sample sizes before committing them to your playbook." : "No projects match the current filter or search criteria.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                AppPrimaryButton("Create Project", icon: "plus", height: 36) {
                    isCreatingProject = true
                }
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
                    .font(.system(size: 13, weight: .semibold))
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
                Text(project.criteria.symbols.joined(separator: ", "))
                    .font(AppTypography.badgeMicro)
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(4)
            }
            
            if !project.criteria.timeframes.isEmpty {
                Text(project.criteria.timeframes.joined(separator: "/"))
                    .font(AppTypography.badgeMicro)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(4)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(4)
            }
        }
    }
    
    private var cardHypothesisView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            
            Text(project.hypothesis)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .italic()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
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
            metricCell(
                title: "WIN RATE",
                value: project.winRate.map { "\(String(format: "%.1f", $0))%" } ?? "--",
                color: (project.winRate ?? 0) >= 50.0 ? AppColors.profit : AppColors.primaryText
            )
            metricCell(
                title: "PROFIT FACTOR",
                value: project.profitFactor.map { String(format: "%.2f", $0) } ?? "--",
                color: (project.profitFactor ?? 0) >= 1.5 ? AppColors.profit : AppColors.primaryText
            )
            metricCell(
                title: "CHECKPOINTS",
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
                        .font(.system(size: 10))
                    Text(project.status == .validated ? "CONCLUSION: VALIDATED" : "CONCLUSION: INVALIDATED")
                        .font(AppTypography.badgeMicro)
                }
                .foregroundColor(project.status == .validated ? AppColors.profit : AppColors.loss)
                
                Text(conclusion)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
            )
        }
    }
    
    @ViewBuilder
    private var cardCheckpointsTimelineView: some View {
        if !project.checkpoints.isEmpty {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCheckpoints.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: showCheckpoints ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(showCheckpoints ? "Hide checkpoints (\(project.checkpoints.count))" : "View checkpoints (\(project.checkpoints.count))")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(AppColors.brand)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
            
            if showCheckpoints {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(project.checkpoints.sorted(by: { $0.timestamp > $1.timestamp })) { chk in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Sample: \(chk.sampleCount) trades")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                                
                                if let wr = chk.winRate {
                                    Text("• WR: \(String(format: "%.1f", wr))%")
                                        .font(AppTypography.numberMicro)
                                        .foregroundColor(wr >= 50.0 ? AppColors.profit : AppColors.secondaryText)
                                }
                                if let pf = chk.profitFactor {
                                    Text("• PF: \(String(format: "%.2f", pf))")
                                        .font(AppTypography.numberMicro)
                                        .foregroundColor(pf >= 1.5 ? AppColors.profit : AppColors.secondaryText)
                                }
                                Spacer()
                                Text(formatDate(chk.timestamp))
                                    .font(AppTypography.microCaption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            if !chk.notes.isEmpty {
                                Text(chk.notes)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
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
    
    private func metricCell(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(AppTypography.microCaption)
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(AppTypography.numberSmall)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(AppColors.secondaryBackground)
        .cornerRadius(6)
    }
    
    private func statusBadge(_ st: AIResearchProjectStatus) -> some View {
        switch st {
        case .active:
            return Text("Active")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.brand)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.brand.opacity(0.12))
                .cornerRadius(4)
        case .validated:
            return Text("Validated")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.profit)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.profitFill)
                .cornerRadius(4)
        case .invalidated:
            return Text("Invalidated")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.loss)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.lossFill)
                .cornerRadius(4)
        case .paused:
            return Text("Paused")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.secondaryBackground)
                .cornerRadius(4)
        case .archived:
            return Text("Archived")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.secondaryBackground)
                .cornerRadius(4)
        }
    }
    
    private func formatDate(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM dd, HH:mm"
        return fmt.string(from: d)
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
                            Text("TITLE & WORKING HYPOTHESIS")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Project Title")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextField("e.g. H4 Breaker Block + M15 FVG", text: $title)
                                    .font(AppTypography.inputText)
                                    .padding(10)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hypothesis Description")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextEditor(text: $hypothesis)
                                    .font(AppTypography.inputText)
                                    .frame(minHeight: 100)
                                    .padding(8)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SCOPE & SAMPLE CRITERIA")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target Symbols")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextField("e.g. XAUUSD, EURUSD", text: $symbols)
                                    .font(AppTypography.inputText)
                                    .padding(10)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Timeframes")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextField("e.g. 15m, 4h", text: $timeframes)
                                    .font(AppTypography.inputText)
                                    .padding(10)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                    .disableAutocorrection(true)
                            }
                            
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
        _winRateText = State(initialValue: project.winRate.map { String(format: "%.1f", $0) } ?? "")
        _profitFactorText = State(initialValue: project.profitFactor.map { String(format: "%.2f", $0) } ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SAMPLE & PERFORMANCE METRICS")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Win Rate %")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                    TextField("e.g. 62.5", text: $winRateText)
                                        .font(AppTypography.inputText)
                                        .keyboardType(.decimalPad)
                                        .padding(10)
                                        .background(AppColors.secondaryBackground)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Profit Factor")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                    TextField("e.g. 1.85", text: $profitFactorText)
                                        .font(AppTypography.inputText)
                                        .keyboardType(.decimalPad)
                                        .padding(10)
                                        .background(AppColors.secondaryBackground)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                }
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("OBSERVATIONS & QUALITATIVE NOTES")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            TextEditor(text: $notes)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
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
                                    .font(.system(size: 12))
                                Text(targetStatus == .validated ? "Confirming hypothesis as validated rule" : "Refuting hypothesis due to adverse metrics")
                                    .font(AppTypography.captionBold)
                            }
                            .foregroundColor(targetStatus == .validated ? AppColors.profit : AppColors.loss)
                            
                            TextEditor(text: $conclusionText)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
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
