import SwiftUI

/// Notebook view adhering 1:1 with `source-repo/apps/web/src/app/notebook/page.tsx`:
/// - FilterBar with title "Notebook" and "New note" button
/// - Folder selector bar (All notes, folders, New folder)
/// - Search notes input
/// - Notes list with title, preview, and update date
/// - Full-featured Note Editor with edit/preview toggle, format actions, autosave, delete, and attachments
public struct NotebookView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var env = AppEnvironment.shared
    
    @State private var selectedFolderId: String = NotebookEngine.systemFolderAll
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
        let (notes, _) = dataStore.filteredNotes(
            folderId: selectedFolderId,
            searchQuery: searchQuery,
            sort: .updated
        )
        return notes
    }
    
    private var currentFolderName: String {
        activeFolders.first(where: { $0.id == selectedFolderId })?.name ?? "Notes"
    }
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Folder selector bar
            folderChipsBar
                .padding(.vertical, 8)
                .background(AppColors.cardBackground)
            
            Divider().background(AppColors.border.opacity(0.5))
            
            // Search field
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.background)
            
            Divider().background(AppColors.border.opacity(0.5))
            
            // Notes Content List
            if filteredNotes.isEmpty {
                emptyNotesState
            } else {
                notesScrollView
            }
        }
        .background(AppColors.background)
        .sheet(item: $editingNote) { note in
            NotebookEditorSheet(
                noteId: note.id,
                initialTitle: note.title,
                initialContent: note.content,
                initialFolderId: note.folderId,
                activeFolders: activeFolders
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
        .alert("Delete “\(folderToDelete?.name ?? "")”?", isPresented: $showDeleteFolderAlert) {
            Button("Cancel", role: .cancel) { folderToDelete = nil }
            Button("Delete folder", role: .destructive) {
                if let folder = folderToDelete {
                    try? dataStore.deleteFolder(id: folder.id)
                    if selectedFolderId == folder.id {
                        selectedFolderId = NotebookEngine.systemFolderMyNotes
                    }
                    folderToDelete = nil
                }
            }
        } message: {
            Text("The folder will be removed. Its notes will be kept in My notes.")
        }
        .alert("Delete this note?", isPresented: $showDeleteNoteAlert) {
            Button("Cancel", role: .cancel) { noteToDelete = nil }
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    dataStore.deleteNote(id: note.id)
                    noteToDelete = nil
                }
            }
        } message: {
            Text("This note will be permanently removed.")
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.system(size: 13))
                
                TextField("Search notes", text: $searchQuery)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                            .font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                createNewNote()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    // MARK: - Folder Chips Horizontal Bar
    
    private var folderChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeFolders) { folder in
                    let isSelected = selectedFolderId == folder.id
                    let count = dataStore.notebookNotes.filter {
                        folder.id == NotebookEngine.systemFolderAll ? true : $0.folderId == folder.id
                    }.count
                    
                    Button {
                        if selectedFolderId != folder.id {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                selectedFolderId = folder.id
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: folderIcon(for: folder))
                                .font(.system(size: 12))
                            Text(folder.name)
                                .font(AppTypography.captionBold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 160)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.22) : AppColors.secondaryText.opacity(0.12))
                                .clipShape(Capsule())
                            
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? AppColors.brand : AppColors.secondaryBackground)
                        .foregroundColor(isSelected ? AppColors.brandTextOnDark : AppColors.primaryText)
                        .clipShape(Capsule())
                        .shadow(color: isSelected ? AppColors.brand.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 1.5)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .contextMenu {
                        if folder.id != NotebookEngine.systemFolderAll && folder.id != NotebookEngine.systemFolderMyNotes {
                            Button {
                                folderToRename = folder
                                renameFolderName = folder.name
                                folderError = nil
                                showRenameFolderSheet = true
                            } label: {
                                Label("Rename Folder", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                folderToDelete = folder
                                showDeleteFolderAlert = true
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                    }
                }
                
                // Add new folder button
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    newFolderName = ""
                    folderError = nil
                    showNewFolderSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New folder")
                            .font(AppTypography.captionBold)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.secondaryBackground)
                    .foregroundColor(AppColors.brand)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppColors.brand.opacity(0.4), lineWidth: 0.8)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Notes Scroll View
    
    private var notesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredNotes) { note in
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
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
                                        Text(folder.name)
                                            .font(.system(size: 10, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: 100)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(AppColors.secondaryBackground)
                                            .foregroundColor(AppColors.secondaryText)
                                            .clipShape(Capsule())
                                    }
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
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                    Spacer()
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        #endif
                                        noteToDelete = note
                                        showDeleteNoteAlert = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.loss.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 88)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyNotesState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundColor(AppColors.secondaryText.opacity(0.5))
            Text("No notes here yet.")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
            Text("Create your first note in this folder to begin.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                createNewNote()
            } label: {
                Text("New note")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brandTextOnDark)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                    TextField("Folder name", text: $newFolderName)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewFolderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create folder") {
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
                    TextField("Folder name", text: $renameFolderName)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameFolderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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

// MARK: - Notebook Note Editor Sheet

public struct NotebookEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let dataStore = TradeDataStore.shared
    
    let noteId: String
    let activeFolders: [NotebookFolder]
    
    @State private var title: String
    @State private var content: String
    @State private var selectedFolderId: String
    @State private var isPreviewMode: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var hasPendingChanges: Bool = false
    
    public init(
        noteId: String,
        initialTitle: String,
        initialContent: String,
        initialFolderId: String,
        activeFolders: [NotebookFolder]
    ) {
        self.noteId = noteId
        self.activeFolders = activeFolders
        _title = State(initialValue: initialTitle)
        _content = State(initialValue: initialContent)
        _selectedFolderId = State(initialValue: initialFolderId)
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
                    
                    HStack {
                        // Folder selector
                        let folderOptions = activeFolders.filter { $0.id != NotebookEngine.systemFolderAll }.map { $0.id }
                        AppDropdownField(
                            selection: $selectedFolderId,
                            options: folderOptions,
                            titleFor: { id in
                                activeFolders.first(where: { $0.id == id })?.name ?? id
                            },
                            iconFor: { _ in "folder" }
                        )
                        .onChange(of: selectedFolderId) { _ in
                            hasPendingChanges = true
                            flushSave()
                        }
                        
                        Spacer()
                        
                        // Mode toggle: Edit / Preview
                        Picker("Mode", selection: $isPreviewMode) {
                            Text("Edit").tag(false)
                            Text("Preview").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .onChange(of: isPreviewMode) { _ in
                            flushSave()
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Divider().background(AppColors.border.opacity(0.5))
                    
                    // Formatting Toolbar (Bold, Italic, Bullet)
                    if !isPreviewMode {
                        HStack(spacing: 12) {
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                applyFormat(marker: "**")
                            } label: {
                                Text("B")
                                    .font(.system(size: 14, weight: .black))
                                    .frame(width: 34, height: 30)
                                    .background(AppColors.secondaryBackground)
                                    .foregroundColor(AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(ApplePressableButtonStyle())
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                applyFormat(marker: "*")
                            } label: {
                                Text("I")
                                    .font(.system(size: 14, weight: .bold, design: .serif))
                                    .italic()
                                    .frame(width: 34, height: 30)
                                    .background(AppColors.secondaryBackground)
                                    .foregroundColor(AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(ApplePressableButtonStyle())
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                insertBullet()
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 34, height: 30)
                                    .background(AppColors.secondaryBackground)
                                    .foregroundColor(AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(ApplePressableButtonStyle())
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                insertNumberedList()
                            } label: {
                                Image(systemName: "list.number")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 34, height: 30)
                                    .background(AppColors.secondaryBackground)
                                    .foregroundColor(AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(ApplePressableButtonStyle())
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }
                .background(AppColors.cardBackground)
                
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
                                    Text(LocalizedStringKey(content))
                                        .font(AppTypography.body)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextEditor(text: $content)
                                .font(AppTypography.inputText)
                                .foregroundColor(AppColors.primaryText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 180)
                                .onChange(of: content) { _ in scheduleAutoSave() }
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
                .background(AppColors.background)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(AppColors.loss.opacity(0.85))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        flushSave()
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brand)
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
            .onDisappear {
                flushSave()
            }
        }
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
            folderId: selectedFolderId
        )
    }
    
    private func applyFormat(marker: String) {
        let res = NoteFormattingEngine.formatInlineSelection(
            value: content,
            start: (content as NSString).length,
            end: (content as NSString).length,
            marker: marker
        )
        content = res.value
        scheduleAutoSave()
    }
    
    private func insertBullet() {
        if content.isEmpty || content.hasSuffix("\n") {
            content += "- "
        } else {
            content += "\n- "
        }
        scheduleAutoSave()
    }
    
    private func insertNumberedList() {
        if content.isEmpty || content.hasSuffix("\n") {
            content += "1. "
        } else {
            content += "\n1. "
        }
        scheduleAutoSave()
    }
}
