import SwiftUI

/// Notebook view adhering 1:1 with `source-repo/apps/web/src/app/notebook/page.tsx`:
/// - FilterBar with title "Notebook" and "New note" button
/// - Folder selector bar (All notes, folders, New folder)
/// - Search notes input
/// - Notes list with title, preview, and update date
/// - Full-featured Note Editor with edit/preview toggle, format actions, autosave, delete, and attachments
public struct NotebookView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    private var selectedFolderId: String {
        get { env.notebookFolderId ?? NotebookEngine.systemFolderAll }
        nonmutating set { env.notebookFolderId = (newValue == NotebookEngine.systemFolderAll) ? nil : newValue }
    }
    @State private var searchQuery: String = ""
    @State private var editingNote: NotebookNote? = nil
    
    @State private var showNewFolderSheet: Bool = false
    @State private var newFolderName: String = ""
    @State private var folderError: String? = nil
    
    @State private var folderToDelete: NotebookFolder? = nil
    @State private var showDeleteFolderAlert: Bool = false
    
    @State private var folderToRename: NotebookFolder? = nil
    @State private var renameFolderName: String = ""
    @State private var showRenameFolderSheet: Bool = false
    
    @State private var noteToDelete: NotebookNote? = nil
    @State private var showDeleteNoteAlert: Bool = false
    
    public init() {}
    
    private var activeFolders: [NotebookFolder] {
        dataStore.folders.filter { $0.deletedAt == nil }
    }
    
    private var filteredNotes: [NotebookNote] {
        let q = env.isSearchActive ? env.searchQuery : searchQuery
        let (notes, _) = dataStore.filteredNotes(
            folderId: selectedFolderId,
            searchQuery: q,
            sort: .updated
        )
        return notes
    }
    
    private var currentFolderName: String {
        activeFolders.first(where: { $0.id == selectedFolderId })?.name ?? "Notes"
    }
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().appCardStyle(cornerRadius: 16)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if filteredNotes.isEmpty {
                    emptyNotesState
                } else {
                    notesListView
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
        .onReceive(env.$requestNewNote) { requested in
            if requested {
                env.requestNewNote = false
                createNewNote()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .sheet(item: $editingNote) { note in
            NotebookEditorSheet(
                noteId: note.id,
                initialTitle: note.title,
                initialContent: note.content,
                initialFolderId: note.folderId,
                initialTradeKey: note.tradeKey,
                activeFolders: activeFolders,
                initialPreviewMode: !note.content.isEmpty
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showNewFolderSheet) {
            newFolderSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showRenameFolderSheet) {
            renameFolderSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .appConfirmationAlert(
            isPresented: $showDeleteFolderAlert,
            title: "Delete “\(folderToDelete?.name ?? "")”?",
            message: "The folder will be removed. Its notes will be kept in My notes.",
            confirmTitle: "Delete folder"
        ) {
            if let folder = folderToDelete {
                try? dataStore.deleteFolder(id: folder.id)
                if selectedFolderId == folder.id {
                    selectedFolderId = NotebookEngine.systemFolderMyNotes
                }
                folderToDelete = nil
            }
        }
        .appConfirmationAlert(
            isPresented: $showDeleteNoteAlert,
            title: "Delete this note?",
            message: "This note will be permanently removed."
        ) {
            if let note = noteToDelete {
                dataStore.deleteNote(id: note.id)
                noteToDelete = nil
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            AppSearchBar("Search notes", text: $searchQuery)
            
            AppPrimaryButton("New", icon: "plus", height: 34) {
                NativeHaptics.mediumImpact()
                createNewNote()
            }
        }
    }
    
    // MARK: - Folder Chips Horizontal Bar
    
    private var selectedFolderBinding: Binding<NotebookFolder> {
        Binding(
            get: {
                activeFolders.first(where: { $0.id == selectedFolderId }) ?? activeFolders.first ?? NotebookFolder(id: NotebookEngine.systemFolderAll, name: "All notes")
            },
            set: { newFolder in
                selectedFolderId = newFolder.id
            }
        )
    }
    
    private var folderChipsBar: some View {
        HStack(spacing: 8) {
            AppleSlidingSegmentedBar(
                selection: selectedFolderBinding,
                items: activeFolders,
                titleFor: { $0.name },
                iconFor: { folderIcon(for: $0) },
                badgeCountFor: { folder in
                    dataStore.notebookNotes.filter {
                        folder.id == NotebookEngine.systemFolderAll ? true : $0.folderId == folder.id
                    }.count
                },
                isScrollable: true
            )
            
            AppIconPodButton(icon: "folder.badge.plus", color: AppColors.brand, size: 32, label: "New folder") {
                newFolderName = ""
                folderError = nil
                showNewFolderSheet = true
            }
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Notes List View
    
    private var notesListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredNotes) { note in
                    Button {
                        NativeHaptics.lightImpact()
                        editingNote = note
                    } label: {
                        cardContainer {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Text(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : note.title)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    if let folder = activeFolders.first(where: { $0.id == note.folderId }) {
                                        AppBadge(folder.name, variant: .secondary)
                                            .frame(maxWidth: 100)
                                    }
                                }
                                
                                // Linked Trade Info (Minimalist Single Line, No Raw IDs)
                                if let key = note.tradeKey, !key.isEmpty,
                                   let trade = dataStore.trades.first(where: { $0.key == key || $0.executionIds.contains(key) || $0.id == key }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "link")
                                            .font(AppTypography.captionMicro)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text("\(trade.symbol) \(trade.direction == .short ? "SELL" : "BUY")")
                                            .font(AppTypography.captionMicro)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text(Formatters.currency(trade.netPnl))
                                            .font(AppTypography.numberMicro)
                                            .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    }
                                    .lineLimit(1)
                                }
                                
                                if !note.content.isEmpty {
                                    Text(note.content)
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                HStack {
                                    Text(String(note.updatedAt.prefix(10)))
                                        .font(AppTypography.captionMicro)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                    Spacer()
                                    ModalDeleteButton {
                                        noteToDelete = note
                                        showDeleteNoteAlert = true
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
        }
    
    // MARK: - Empty State
    
    private var emptyNotesState: some View {
        AppEmptyState(
            icon: "note.text",
            title: "No notes here yet",
            message: "Create your first note in this folder to begin.",
            iconColor: AppColors.secondaryText,
            actionTitle: "New Note",
            actionIcon: "plus"
        ) {
            createNewNote()
        }
    }
    
    private func folderIcon(for folder: NotebookFolder) -> String {
        if folder.id == NotebookEngine.systemFolderAll { return "tray.full" }
        if folder.id == NotebookEngine.systemFolderTradeNotes { return "chart.bar.doc.horizontal" }
        if folder.id == NotebookEngine.systemFolderMyNotes { return "person.crop.square" }
        return "folder"
    }
    
    private func createNewNote() {
        let targetFolder = selectedFolderId == NotebookEngine.systemFolderAll
            ? NotebookEngine.systemFolderMyNotes
            : selectedFolderId
        if let newNote = try? dataStore.createNote(folderId: targetFolder, title: "", content: "") {
            editingNote = newNote
        }
    }
    
    // MARK: - New Folder Sheet
    
    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                Section {
                    AppTextField("Folder name", text: $newFolderName)
                    if let err = folderError {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                } header: {
                    Text("Folder details")
                } footer: {
                    Text("Organize your notes in a named folder. Up to 100 characters.")
                }
            }
            .navigationTitle("New folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { showNewFolderSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Create") {
                        do {
                            let folder = try dataStore.createFolder(name: newFolderName)
                            selectedFolderId = folder.id
                            showNewFolderSheet = false
                        } catch {
                            folderError = error.localizedDescription
                        }
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Rename Folder Sheet
    
    private var renameFolderSheet: some View {
        NavigationStack {
            Form {
                Section {
                    AppTextField("Folder name", text: $renameFolderName)
                    if let err = folderError {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                } header: {
                    Text("Folder details")
                }
            }
            .navigationTitle("Rename folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { showRenameFolderSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Save") {
                        if let folder = folderToRename {
                            do {
                                try dataStore.renameFolder(id: folder.id, name: renameFolderName)
                                showRenameFolderSheet = false
                            } catch {
                                folderError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
