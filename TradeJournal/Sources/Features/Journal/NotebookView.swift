import SwiftUI

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
        activeFolders.first(where: { $0.id == selectedFolderId })?.name ?? "Ghi chú"
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Folder Selector Bar
            folderChipsBar
                .padding(.vertical, 8)
                .background(AppColors.cardBackground.opacity(0.5))
            
            // MARK: - Search & Action Bar
            searchAndActionBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            // MARK: - Notes Content List
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
        }
        .sheet(isPresented: $showNewFolderSheet) {
            newFolderSheet
        }
        .alert("Xóa thư mục “\(folderToDelete?.name ?? "")”?", isPresented: $showDeleteFolderAlert) {
            Button("Hủy", role: .cancel) { folderToDelete = nil }
            Button("Xóa thư mục", role: .destructive) {
                if let folder = folderToDelete {
                    try? dataStore.deleteFolder(id: folder.id)
                    if selectedFolderId == folder.id {
                        selectedFolderId = NotebookEngine.systemFolderMyNotes
                    }
                    folderToDelete = nil
                }
            }
        } message: {
            Text("Thư mục sẽ bị xóa. Toàn bộ ghi chú bên trong sẽ được giữ lại an toàn trong “My notes”.")
        }
        .alert("Xóa ghi chú?", isPresented: $showDeleteNoteAlert) {
            Button("Hủy", role: .cancel) { noteToDelete = nil }
            Button("Xóa", role: .destructive) {
                if let note = noteToDelete {
                    dataStore.deleteNote(id: note.id)
                    noteToDelete = nil
                }
            }
        } message: {
            Text("Ghi chú này sẽ bị xóa khỏi sổ tay.")
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
                        selectedFolderId = folder.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: folderIcon(for: folder))
                                .font(.system(size: 13))
                            Text(folder.name)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : AppColors.cardBackground)
                                .clipShape(Capsule())
                            
                            // Nút xóa thư mục user
                            if folder.id != NotebookEngine.systemFolderAll && folder.id != NotebookEngine.systemFolderMyNotes && isSelected {
                                Button {
                                    folderToDelete = folder
                                    showDeleteFolderAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.red.opacity(0.9))
                                }
                                .padding(.leading, 2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? AppColors.accent : AppColors.surface)
                        .foregroundColor(isSelected ? .white : AppColors.primaryText)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
                
                // Nút thêm thư mục mới
                Button {
                    newFolderName = ""
                    folderError = nil
                    showNewFolderSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Thư mục")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppColors.surface)
                    .foregroundColor(AppColors.accent)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Search & Action Bar
    
    private var searchAndActionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.system(size: 14))
                TextField("Tìm kiếm ghi chú...", text: $searchQuery)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColors.surface)
            .cornerRadius(10)
            
            // Nút Tạo Ghi Chú Mới
            Button {
                createNewNote()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Viết")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Notes Scroll View
    
    private var notesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredNotes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ghi chú không tên" : note.title)
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    if let folder = activeFolders.first(where: { $0.id == note.folderId }) {
                                        Text(folder.name)
                                            .font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.surface)
                                            .foregroundColor(AppColors.secondaryText)
                                            .cornerRadius(4)
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
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                    Spacer()
                                    Button {
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyNotesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            Text("Chưa có ghi chú nào trong mục này")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.secondaryText)
            Button {
                createNewNote()
            } label: {
                Text("Tạo ghi chú mới ngay")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.surface)
                    .cornerRadius(8)
            }
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
                    TextField("Tên thư mục", text: $newFolderName)
                    if let err = folderError {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                } header: {
                    Text("Thông tin thư mục")
                } footer: {
                    Text("Tối đa 100 ký tự. Các khoảng trắng thừa sẽ tự động được cắt bỏ.")
                }
            }
            .navigationTitle("Tạo thư mục mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showNewFolderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") {
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
}

// MARK: - Notebook Note Editor Sheet (Crash-proof & Native)

public struct NotebookEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let noteId: String
    let activeFolders: [NotebookFolder]
    
    @State private var title: String
    @State private var content: String
    @State private var selectedFolderId: String
    @State private var isPreviewMode: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
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
                    TextField("Tiêu đề ghi chú...", text: $title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .onChange(of: title) { _ in autoSave() }
                    
                    HStack {
                        // Thư mục selector
                        Picker("Thư mục", selection: $selectedFolderId) {
                            ForEach(activeFolders.filter { $0.id != NotebookEngine.systemFolderAll }) { folder in
                                Text(folder.name).tag(folder.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                        .onChange(of: selectedFolderId) { _ in autoSave() }
                        
                        Spacer()
                        
                        // Mode toggle: Soạn thảo / Xem trước
                        Picker("Chế độ", selection: $isPreviewMode) {
                            Text("Soạn thảo").tag(false)
                            Text("Xem trước").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }
                    .padding(.horizontal)
                    
                    Divider().background(AppColors.border)
                    
                    // Formatting Toolbar (Bold, Italic, Bullet, Quote)
                    if !isPreviewMode {
                        HStack(spacing: 12) {
                            Button {
                                applyFormat(marker: "**")
                            } label: {
                                Text("B")
                                    .font(.system(size: 15, weight: .black))
                                    .frame(width: 32, height: 28)
                                    .background(AppColors.surface)
                                    .foregroundColor(AppColors.primaryText)
                                    .cornerRadius(6)
                            }
                            
                            Button {
                                applyFormat(marker: "*")
                            } label: {
                                Text("I")
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                    .italic()
                                    .frame(width: 32, height: 28)
                                    .background(AppColors.surface)
                                    .foregroundColor(AppColors.primaryText)
                                    .cornerRadius(6)
                            }
                            
                            Button {
                                insertBullet()
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 32, height: 28)
                                    .background(AppColors.surface)
                                    .foregroundColor(AppColors.primaryText)
                                    .cornerRadius(6)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }
                }
                .background(AppColors.cardBackground)
                
                // Content View
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if isPreviewMode {
                            VStack(alignment: .leading, spacing: 8) {
                                if title.isEmpty && content.isEmpty {
                                    Text("*(Ghi chú trống)*")
                                        .foregroundColor(AppColors.secondaryText)
                                        .font(AppTypography.body)
                                } else {
                                    if !title.isEmpty {
                                        Text(title)
                                            .font(AppTypography.title)
                                            .foregroundColor(AppColors.primaryText)
                                            .padding(.bottom, 4)
                                    }
                                    Text(content)
                                        .font(AppTypography.body)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextEditor(text: $content)
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.primaryText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 180)
                                .onChange(of: content) { _ in autoSave() }
                        }
                        
                        Divider().background(AppColors.border)
                        
                        AttachmentsSectionView(
                            ownerType: "note",
                            ownerId: noteId,
                            title: "Hình ảnh & Tệp đính kèm ghi chú"
                        )
                    }
                    .padding()
                }
                .background(AppColors.background)
            }
            .navigationTitle("Ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(AppColors.loss)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        autoSave()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                }
            }
            .alert("Xóa ghi chú này?", isPresented: $showDeleteConfirmation) {
                Button("Hủy", role: .cancel) {}
                Button("Xóa", role: .destructive) {
                    dataStore.deleteNote(id: noteId)
                    dismiss()
                }
            } message: {
                Text("Ghi chú này sẽ bị xóa hoàn toàn khỏi sổ tay.")
            }
        }
    }
    
    private func autoSave() {
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
        autoSave()
    }
    
    private func insertBullet() {
        if content.isEmpty || content.hasSuffix("\n") {
            content += "- "
        } else {
            content += "\n- "
        }
        autoSave()
    }
}
