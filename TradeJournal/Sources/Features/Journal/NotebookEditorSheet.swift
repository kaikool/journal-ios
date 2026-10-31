import SwiftUI

// MARK: - Notebook Note Editor Sheet
// Dedicated modal sheet for rich text / Markdown note editing and preview with attachments,
// explicit Trade Order Ticket linking, and AI Inquiry directly inside the note.
public struct NotebookEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let dataStore = TradeDataStore.shared
    
    let noteId: String
    let activeFolders: [NotebookFolder]
    
    @State private var title: String
    @State private var content: String
    @State private var selectedFolderId: String
    @State private var tradeKey: String?
    @State private var isPreviewMode: Bool
    @State private var showDeleteConfirmation: Bool = false
    @State private var showLinkTradeSheet: Bool = false
    @State private var showInquirySheet: Bool = false
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var hasPendingChanges: Bool = false
    
    public init(
        noteId: String,
        initialTitle: String,
        initialContent: String,
        initialFolderId: String,
        initialTradeKey: String? = nil,
        activeFolders: [NotebookFolder],
        initialPreviewMode: Bool = true
    ) {
        self.noteId = noteId
        self.activeFolders = activeFolders
        self._title = State(initialValue: initialTitle)
        self._content = State(initialValue: initialContent)
        self._selectedFolderId = State(initialValue: initialFolderId)
        self._tradeKey = State(initialValue: initialTradeKey)
        let hasContent = !initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self._isPreviewMode = State(initialValue: initialPreviewMode && hasContent)
    }
    
    private var linkedTrade: Trade? {
        guard let key = tradeKey, !key.isEmpty else { return nil }
        return dataStore.trades.first(where: {
            $0.key == key || $0.executionIds.contains(key) || $0.id == key
        })
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header inputs
                VStack(spacing: 12) {
                    TextField("Title", text: $title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .onChange(of: title) { _ in scheduleAutoSave() }
                    
                    HStack(spacing: 8) {
                        // Folder selector matching segmented picker height (32pt)
                        let folderOptions = activeFolders.filter { $0.id != NotebookEngine.systemFolderAll }.map { $0.id }
                        Menu {
                            ForEach(folderOptions, id: \.self) { id in
                                Button {
                                    selectedFolderId = id
                                    hasPendingChanges = true
                                    flushSave()
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text(activeFolders.first(where: { $0.id == id })?.name ?? id)
                                        if selectedFolderId == id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(activeFolders.first(where: { $0.id == selectedFolderId })?.name ?? "Folder")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                            )
                        }
                        
                        Spacer()
                        
                        // Mode toggle: Preview prioritized over Edit
                        Picker("Mode", selection: $isPreviewMode) {
                            Text("Preview").tag(true)
                            Text("Edit").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .frame(height: 34)
                        .onChange(of: isPreviewMode) { _ in
                            flushSave()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .background(AppColors.cardBackground)
                
                // Linked Trade & AI Inquiry Bar
                linkedTradeBar
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Content View
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isPreviewMode {
                            VStack(alignment: .leading, spacing: 8) {
                                if title.isEmpty && content.isEmpty {
                                    Text("*(Empty note)*")
                                        .foregroundColor(AppColors.secondaryText)
                                        .font(AppTypography.body)
                                } else {
                                    if !title.isEmpty {
                                        Text(title)
                                            .font(AppTypography.pageTitle)
                                            .foregroundColor(AppColors.primaryText)
                                            .padding(.bottom, 4)
                                    }
                                    JournalNotesMarkdownView(text: content)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            RichNoteEditor(
                                text: $content,
                                placeholder: "Write note in Markdown or plain text...",
                                minHeight: 180,
                                allowPreviewToggle: false,
                                onSave: { scheduleAutoSave() }
                            )
                        }
                        
                        Divider().background(AppColors.border.opacity(0.5))
                        
                        AttachmentsSectionView(
                            ownerType: "note",
                            ownerId: noteId,
                            title: "Attachments & Screenshots"
                        )
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppColors.background)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        ModalDismissButton {
                            flushSave()
                            dismiss()
                        }
                        
                        ModalDeleteButton {
                            showDeleteConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Done") {
                        flushSave()
                        dismiss()
                    }
                }
            }
            .alert("Delete this note?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    dataStore.deleteNote(id: noteId)
                    dismiss()
                }
            } message: {
                Text("This note will be permanently removed.")
            }
            .sheet(isPresented: $showLinkTradeSheet) {
                LinkNoteToTradeSheet(
                    noteId: noteId,
                    noteTitle: title,
                    currentTradeKey: tradeKey,
                    onLinked: { trade, _ in
                        self.tradeKey = trade.key
                        self.hasPendingChanges = true
                        self.flushSave()
                    },
                    onUnlinked: {
                        self.tradeKey = nil
                        self.hasPendingChanges = true
                        self.flushSave()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showInquirySheet) {
                NoteAIInquirySheet(
                    noteId: noteId,
                    noteTitle: title,
                    noteContent: $content,
                    tradeKey: tradeKey,
                    onSave: {
                        self.hasPendingChanges = true
                        self.flushSave()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onDisappear {
                flushSave()
            }
        }
    }
    
    // MARK: - Linked Trade & AI Inquiry Subview (Minimalist Single-Line)
    
    private var linkedTradeBar: some View {
        HStack(spacing: 10) {
            if let trade = linkedTrade {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("\(trade.symbol) \(trade.direction == .short ? "SELL" : "BUY")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Text("Entry \(Formatters.price(trade.avgEntry))")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    
                    Text(Formatters.currency(trade.netPnl))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        .lineLimit(1)
                }
                .lineLimit(1)
                
                Spacer(minLength: 6)
                
                AppSecondaryButton("Inquiry", icon: "sparkles", height: 34) {
                    showInquirySheet = true
                }
                
                AppIconPodButton(icon: "pencil", size: 34, label: "Edit linked trade") {
                    showLinkTradeSheet = true
                }
            } else {
                AppSecondaryButton("Link Trade", icon: "link", height: 34) {
                    showLinkTradeSheet = true
                }
                
                Spacer(minLength: 6)
                
                Button {
                    showInquirySheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text("Inquiry")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.6)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
    }
    
    private func scheduleAutoSave() {
        hasPendingChanges = true
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }
    
    private func flushSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard hasPendingChanges else { return }
        hasPendingChanges = false
        try? dataStore.patchNote(
            id: noteId,
            title: title,
            content: content,
            folderId: selectedFolderId,
            tradeKey: .some(tradeKey)
        )
    }
}
