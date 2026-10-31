import SwiftUI

// MARK: - AI Memory Management Sheet (Apple HIG & Trading Terminal Standard)
/// Enables traders to view, filter, search, create, edit, verify, and delete
/// persistent AI memories across the 5 Module A knowledge categories.
/// Designed with 100% fidelity to the sleek, restrained dark theme of AIReflectionView.
public struct AIMemoryManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var memories: [AIMemoryRecord] = []
    @State private var selectedCategory: AIMemoryCategory? = nil
    @State private var selectedStatus: AIMemoryStatus? = nil
    @State private var searchQuery: String = ""
    @State private var isSyncing: Bool = false
    
    // Editor and action states
    @State private var editingMemory: AIMemoryRecord? = nil
    @State private var isCreatingMemory: Bool = false
    @State private var memoryToDelete: AIMemoryRecord? = nil
    @State private var showDeleteConfirmation: Bool = false
    
    public init() {}
    
    // MARK: - Filtered Memories
    private var filteredMemories: [AIMemoryRecord] {
        memories.filter { mem in
            // Category filter
            if let cat = selectedCategory, mem.category != cat {
                return false
            }
            // Status filter
            if let st = selectedStatus, mem.status != st {
                return false
            }
            // Search query
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let titleMatch = mem.title.lowercased().contains(q)
                let contentMatch = mem.content.lowercased().contains(q)
                let symbolMatch = mem.symbol?.lowercased().contains(q) ?? false
                if !titleMatch && !contentMatch && !symbolMatch {
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
                    
                    // 2. Search Bar (Matching AIReflectionCustomInquiryCard style)
                    searchBarSection
                    
                    // 3. Category Filter Chips (Matching AIReflectionCategoryChips)
                    categoryFilterSection
                    
                    // 4. Status Filter Chips (Subtle Secondary Filter)
                    statusFilterSection
                    
                    // 5. Memory Cards or Empty State
                    if filteredMemories.isEmpty {
                        emptyStateView
                    } else {
                        memoryCardsListView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("AI Long-Term Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    ModalPrimaryButton("Add Rule", icon: "plus") {
                        isCreatingMemory = true
                    }
                }
            }
            .onAppear(perform: reloadMemories)
            .sheet(item: $editingMemory) { mem in
                AIMemoryEditorSheet(memory: mem, onSave: { updated in
                    AIAdvisorMemoryEngine.shared.saveMemory(updated)
                    reloadMemories()
                })
            }
            .sheet(isPresented: $isCreatingMemory) {
                AIMemoryEditorSheet(memory: nil, onSave: { newRecord in
                    AIAdvisorMemoryEngine.shared.saveMemory(newRecord)
                    reloadMemories()
                })
            }
            .alert("Delete Memory Permanently?", isPresented: $showDeleteConfirmation, presenting: memoryToDelete) { mem in
                Button("Delete", role: .destructive) {
                    AIAdvisorMemoryEngine.shared.deleteMemory(id: mem.id)
                    reloadMemories()
                }
                Button("Cancel", role: .cancel) {}
            } message: { mem in
                Text("Memory '\(mem.title)' will be deleted locally and from cloud storage.")
            }
        }
    }
    
    // MARK: - 1. Scope Header Bar
    private var scopeHeaderBar: some View {
        HStack {
            let verifiedCount = memories.filter { $0.status == .verified }.count
            Text("AI Memory Hub • \(memories.count) Rules • \(verifiedCount) Verified")
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
        AppSearchBar("Search title, content, instrument...", text: $searchQuery)
    }
    
    // MARK: - 3. Category Filter Chips (Standardized with AIReflectionCategoryChips)
    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AppFilterChip(
                    "All",
                    isSelected: selectedCategory == nil,
                    count: memories.count
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = nil }
                }
                
                ForEach(AIMemoryCategory.allCases, id: \.rawValue) { cat in
                    let isSelected = selectedCategory == cat
                    let count = memories.filter { $0.category == cat }.count
                    AppFilterChip(
                        cat.localizedTitle,
                        isSelected: isSelected,
                        icon: iconForCategory(cat),
                        count: count
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = isSelected ? nil : cat
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    // MARK: - 4. Status Filter Chips
    private var statusFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                statusFilterChip(title: "All Statuses", status: nil)
                statusFilterChip(title: "Active", status: .active)
                statusFilterChip(title: "Verified", status: .verified)
                statusFilterChip(title: "Deprecated", status: .deprecated)
                statusFilterChip(title: "Refuted", status: .refuted)
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func statusFilterChip(title: String, status: AIMemoryStatus?) -> some View {
        AppFilterChip(title, isSelected: selectedStatus == status, height: 28) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedStatus = status
            }
        }
    }
    
    // MARK: - 5. Memory Cards List
    private var memoryCardsListView: some View {
        VStack(spacing: 10) {
            ForEach(filteredMemories) { mem in
                AIMemoryCard(
                    memory: mem,
                    onEdit: { editingMemory = mem },
                    onToggleVerified: {
                        let newStatus: AIMemoryStatus = (mem.status == .verified) ? .active : .verified
                        AIAdvisorMemoryEngine.shared.updateMemoryStatus(id: mem.id, status: newStatus)
                        reloadMemories()
                    },
                    onToggleDeprecated: {
                        let newStatus: AIMemoryStatus = (mem.status == .deprecated) ? .active : .deprecated
                        AIAdvisorMemoryEngine.shared.updateMemoryStatus(id: mem.id, status: newStatus)
                        reloadMemories()
                    },
                    onDelete: {
                        memoryToDelete = mem
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
                icon: "brain.head.profile",
                title: "No Memories Found",
                message: memories.isEmpty ? "AI automatically retains your trading habits, loss forensics, and commitments after review sessions." : "No memories match the current filter or search criteria.",
                iconColor: AppColors.brand,
                actionTitle: "Add Rule Manually",
                actionIcon: "plus",
                isInCard: true
            ) {
                isCreatingMemory = true
            }
        }
    }
    
    // MARK: - Reload & Sync
    private func reloadMemories() {
        self.memories = AIAdvisorMemoryEngine.shared.allMemories
    }
    
    private func performSync() {
        isSyncing = true
        Task {
            await AIAdvisorMemoryEngine.shared.syncWithRemote()
            await MainActor.run {
                reloadMemories()
                isSyncing = false
            }
        }
    }
    
    private func iconForCategory(_ cat: AIMemoryCategory) -> String {
        switch cat {
        case .preference: return "bookmark"
        case .decision:   return "arrow.triangle.turn.up.right.diamond"
        case .research:   return "atom"
        case .failure:    return "exclamationmark.triangle"
        case .context:    return "folder"
        }
    }
}

// MARK: - Memory Card (Clean, Restrained, Parity with AIReflectionQuestionsCatalog)
private struct AIMemoryCard: View {
    let memory: AIMemoryRecord
    let onEdit: () -> Void
    let onToggleVerified: () -> Void
    let onToggleDeprecated: () -> Void
    let onDelete: () -> Void
    
    @State private var isExpanded: Bool = false
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Category, Symbol, Status, Menu
                HStack(spacing: 6) {
                    // Category Badge (Subtle brand tint matching PreTradeBanner)
                    AppBadge(memory.category.localizedTitle.uppercased(), variant: .brand)
                    
                    // Symbol Badge (if present)
                    if let sym = memory.symbol, !sym.isEmpty {
                        AppBadge(sym, variant: .secondary)
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadgeView(memory.status)
                    
                    // Menu Ellipsis
                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(action: onToggleVerified) {
                            Label(memory.status == .verified ? "Unmark Verified" : "Mark as Verified", systemImage: "checkmark.seal")
                        }
                        
                        Button(action: onToggleDeprecated) {
                            Label(memory.status == .deprecated ? "Reactivate" : "Mark as Deprecated", systemImage: "archivebox")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(4)
                    }
                }
                
                // Title
                Text(memory.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                
                // Content
                Text(memory.content)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(isExpanded ? nil : 3)
                
                // Footer
                HStack {
                    Text("\(sourceLabel(memory.sourceType)) • \(formatDate(memory.createdAt))")
                        .font(AppTypography.microCaption)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    
                    Spacer()
                    
                    if memory.content.count > 100 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Text(isExpanded ? "Show Less" : "Read More")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        }
    }
    
    @ViewBuilder
    private func statusBadgeView(_ status: AIMemoryStatus) -> some View {
        switch status {
        case .active:
            AppBadge("Active", variant: .secondary)
        case .verified:
            AppBadge("Verified", variant: .profit)
        case .deprecated:
            AppBadge("Deprecated", variant: .secondary)
        case .refuted:
            AppBadge("Refuted", variant: .loss)
        }
    }
    
    private func sourceLabel(_ s: AIMemorySourceType) -> String {
        switch s {
        case .preTrade:   return "Pre-Trade"
        case .tradeAudit: return "Trade Audit"
        case .chat:       return "AI Chat"
        case .research:   return "Research"
        case .manual:     return "Manual"
        }
    }
    
    private func formatDate(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM dd, yyyy"
        return fmt.string(from: d)
    }
}

// MARK: - Memory Editor Sheet (Clean Dark Terminal Styling)
private struct AIMemoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let memory: AIMemoryRecord?
    let onSave: (AIMemoryRecord) -> Void
    
    @State private var category: AIMemoryCategory = .preference
    @State private var symbol: String = ""
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var status: AIMemoryStatus = .active
    @State private var confidence: Double = 1.0
    
    public init(memory: AIMemoryRecord?, onSave: @escaping (AIMemoryRecord) -> Void) {
        self.memory = memory
        self.onSave = onSave
        _category = State(initialValue: memory?.category ?? .preference)
        _symbol = State(initialValue: memory?.symbol ?? "")
        _title = State(initialValue: memory?.title ?? "")
        _content = State(initialValue: memory?.content ?? "")
        _status = State(initialValue: memory?.status ?? .active)
        _confidence = State(initialValue: memory?.confidence ?? 1.0)
    }
    
    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Classification Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("Classification & instrument")
                            
                            AppDropdownField(
                                label: "Category",
                                selection: $category,
                                options: AIMemoryCategory.allCases,
                                titleFor: { $0.localizedTitle }
                            )
                            
                            AppFormField(
                                "Symbol (Optional)",
                                text: $symbol,
                                placeholder: "e.g. XAUUSD (leave blank for general rule)",
                                height: 42
                            )
                        }
                    }
                    
                    // Content Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("Title & rule content")
                            
                            AppFormField(
                                "Rule Title",
                                text: $title,
                                placeholder: "e.g. Wait for 15m MSS before entry",
                                height: 42
                            )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rule / Lesson Description")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                TextEditor(text: $content)
                                    .font(AppTypography.inputText)
                                    .frame(minHeight: 100)
                                    .padding(8)
                                    .background(AppColors.secondaryBackground.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                                    )
                            }
                        }
                    }
                    
                    // Status & Confidence Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("Status & confidence")
                            
                            AppSegmentedBar(
                                selection: $status,
                                items: [AIMemoryStatus.active, AIMemoryStatus.verified, AIMemoryStatus.deprecated, AIMemoryStatus.refuted],
                                titleFor: { $0.rawValue.capitalized },
                                height: 34
                            )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Confidence Level")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text("\(Int(confidence * 100))%")
                                        .font(AppTypography.numberSmall)
                                        .foregroundColor(AppColors.brand)
                                }
                                Slider(value: $confidence, in: 0.1...1.0, step: 0.05)
                                    .tint(AppColors.brand)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle(memory == nil ? "New Memory Record" : "Edit Memory Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save", isEnabled: isFormValid) {
                        let cleanSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        let symOrNil = cleanSym.isEmpty ? nil : cleanSym
                        
                        let record = AIMemoryRecord(
                            id: memory?.id ?? JournalIds.newId(),
                            category: category,
                            symbol: symOrNil,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            confidence: confidence,
                            status: status,
                            supersededBy: memory?.supersededBy,
                            sourceType: memory?.sourceType ?? .manual,
                            sourceId: memory?.sourceId,
                            metadataJson: memory?.metadataJson ?? "{}",
                            createdAt: memory?.createdAt ?? Date(),
                            updatedAt: Date()
                        )
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }
}
