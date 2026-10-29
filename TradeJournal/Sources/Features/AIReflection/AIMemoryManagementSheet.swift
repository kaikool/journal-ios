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
                    Button("Close") {
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.primaryText)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isCreatingMemory = true }) {
                        Text("Add Rule")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.secondaryText)
                .font(.system(size: 13, weight: .medium))
            
            TextField("Search title, content, instrument...", text: $searchQuery)
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
    
    // MARK: - 3. Category Filter Chips (Standardized with AIReflectionCategoryChips)
    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Chip
                let isAllSelected = selectedCategory == nil
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = nil }
                }) {
                    Text("All (\(memories.count))")
                        .font(.system(size: 12, weight: isAllSelected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isAllSelected ? AppColors.secondaryBackground : Color.clear)
                        .foregroundColor(isAllSelected ? AppColors.primaryText : AppColors.secondaryText)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isAllSelected ? AppColors.border : AppColors.border.opacity(0.4), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                
                // Specific Categories
                ForEach(AIMemoryCategory.allCases, id: \.rawValue) { cat in
                    let isSelected = selectedCategory == cat
                    let count = memories.filter { $0.category == cat }.count
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = isSelected ? nil : cat
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: iconForCategory(cat))
                                .font(.system(size: 10))
                            Text("\(cat.localizedTitle) (\(count))")
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
        let isSelected = selectedStatus == status
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedStatus = status
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? AppColors.secondaryBackground : Color.clear)
                .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppColors.border : AppColors.border.opacity(0.3), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    .padding(.top, 8)
                
                Text("No Memories Found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                
                Text(memories.isEmpty ? "AI automatically retains your trading habits, loss forensics, and commitments after review sessions." : "No memories match the current filter or search criteria.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Button(action: { isCreatingMemory = true }) {
                    Text("+ Add Rule Manually")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
                    Text(memory.category.localizedTitle.uppercased())
                        .font(AppTypography.badgeMicro)
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(AppColors.brand.opacity(0.12))
                        .cornerRadius(4)
                    
                    // Symbol Badge (if present)
                    if let sym = memory.symbol, !sym.isEmpty {
                        Text(sym)
                            .font(AppTypography.badgeMicro)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(4)
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
    
    private func statusBadgeView(_ status: AIMemoryStatus) -> some View {
        switch status {
        case .active:
            return Text("Active")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.secondaryBackground)
                .cornerRadius(4)
        case .verified:
            return Text("Verified")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.profit)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.profitFill)
                .cornerRadius(4)
        case .deprecated:
            return Text("Deprecated")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.secondaryBackground)
                .cornerRadius(4)
        case .refuted:
            return Text("Refuted")
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.loss)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.lossFill)
                .cornerRadius(4)
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CLASSIFICATION & INSTRUMENT")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Category")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Picker("Category", selection: $category) {
                                    ForEach(AIMemoryCategory.allCases, id: \.rawValue) { cat in
                                        Text(cat.localizedTitle).tag(cat)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Symbol (Optional)")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextField("e.g. XAUUSD (leave blank for general rule)", text: $symbol)
                                    .font(AppTypography.inputText)
                                    .padding(10)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                            }
                        }
                    }
                    
                    // Content Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TITLE & RULE CONTENT")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rule Title")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextField("e.g. Wait for 15m MSS before entry", text: $title)
                                    .font(AppTypography.inputText)
                                    .padding(10)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rule / Lesson Description")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                TextEditor(text: $content)
                                    .font(AppTypography.inputText)
                                    .frame(minHeight: 100)
                                    .padding(8)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                            }
                        }
                    }
                    
                    // Status & Confidence Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("STATUS & CONFIDENCE")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Picker("Status", selection: $status) {
                                Text("Active").tag(AIMemoryStatus.active)
                                Text("Verified").tag(AIMemoryStatus.verified)
                                Text("Deprecated").tag(AIMemoryStatus.deprecated)
                                Text("Refuted").tag(AIMemoryStatus.refuted)
                            }
                            .pickerStyle(.segmented)
                            
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
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brand)
                    .disabled(!isFormValid)
                }
            }
        }
    }
}
