import SwiftUI

public struct NotebookView: View {
    @EnvironmentObject private var dataStore: TradeDataStore
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedFolderId: String = NotebookEngine.systemFolderAll
    @State private var searchQuery: String = ""
    @State private var selectedNoteId: String? = nil
    
    @State private var showNewFolderSheet: Bool = false
    @State private var newFolderName: String = ""
    @State private var folderError: String? = nil
    
    @State private var folderToDelete: NotebookFolder? = nil
    @State private var showDeleteFolderAlert: Bool = false
    
    public init() {}
    
    private var filteredNotes: [NotebookNote] {
        let (notes, _) = dataStore.filteredNotes(
            folderId: selectedFolderId,
            searchQuery: searchQuery,
            sort: .updated
        )
        return notes
    }
    
    private var activeFolders: [NotebookFolder] {
        dataStore.folders.filter { $0.deletedAt == nil }
    }
    
    public var body: some View {
        NavigationSplitView {
            folderSidebar
                .navigationTitle("Sổ tay (Notebook)")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            createNewNote()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
        } content: {
            notesList
                .navigationTitle(currentFolderName)
        } detail: {
            if let noteId = selectedNoteId,
               let note = dataStore.notebookNotes.first(where: { $0.id == noteId }) {
                NotebookEditorView(note: note)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.secondaryText)
                    Text("Chọn hoặc tạo ghi chú mới")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
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
    }
    
    // MARK: - Folders Sidebar
    
    private var folderSidebar: some View {
        List {
            Section("Thư mục") {
                ForEach(activeFolders) { folder in
                    HStack {
                        Button {
                            selectedFolderId = folder.id
                        } label: {
                            HStack {
                                Image(systemName: folderIcon(for: folder))
                                    .foregroundColor(selectedFolderId == folder.id ? AppColors.accent : AppColors.secondaryText)
                                Text(folder.name)
                                    .foregroundColor(AppColors.primaryText)
                                    .fontWeight(selectedFolderId == folder.id ? .semibold : .regular)
                                Spacer()
                                let count = dataStore.notebookNotes.filter {
                                    folder.id == NotebookEngine.systemFolderAll ? true : $0.folderId == folder.id
                                }.count
                                Text("\(count)")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        
                        if folder.id != NotebookEngine.systemFolderAll && folder.id != NotebookEngine.systemFolderMyNotes {
                            Button {
                                folderToDelete = folder
                                showDeleteFolderAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(AppColors.loss.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            
            Section {
                Button {
                    newFolderName = ""
                    folderError = nil
                    showNewFolderSheet = true
                } label: {
                    Label("Thư mục mới", systemImage: "folder.badge.plus")
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Notes List
    
    private var notesList: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                TextField("Tìm kiếm ghi chú...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
            }
            .padding(10)
            .background(AppColors.surface)
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if filteredNotes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(AppColors.secondaryText)
                    Text("Chưa có ghi chú nào")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                    Button("Tạo ghi chú đầu tiên") {
                        createNewNote()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.accent)
                    .padding(.top, 4)
                    Spacer()
                }
            } else {
                List(filteredNotes) { note in
                    Button {
                        selectedNoteId = note.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            HStack {
                                Text(String(note.updatedAt.prefix(10)))
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("•")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(note.content.isEmpty ? "Trống" : note.content)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var currentFolderName: String {
        activeFolders.first(where: { $0.id == selectedFolderId })?.name ?? "Ghi chú"
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
        if let newNote = try? dataStore.createNote(folderId: targetFolder, title: "Untitled", content: "") {
            selectedNoteId = newNote.id
        }
    }
    
    private var newFolderSheet: some View {
        NavigationView {
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

// MARK: - Notebook Note Editor

public struct NotebookEditorView: View {
    @EnvironmentObject private var dataStore: TradeDataStore
    let note: NotebookNote
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var selectedFolderId: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var isPreviewMode: Bool = false
    
    public init(note: NotebookNote) {
        self.note = note
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header inputs
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Tiêu đề ghi chú", text: $title)
                        .font(AppTypography.title)
                        .foregroundColor(AppColors.primaryText)
                        .onChange(of: title) { _ in autoSave() }
                    
                    HStack {
                        // Thư mục
                        Picker("Thư mục", selection: $selectedFolderId) {
                            ForEach(dataStore.folders.filter { $0.deletedAt == nil && $0.id != NotebookEngine.systemFolderAll }) { folder in
                                Text(folder.name).tag(folder.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedFolderId) { _ in autoSave() }
                        
                        Spacer()
                        
                        // Chế độ Edit / Preview
                        Button {
                            isPreviewMode.toggle()
                        } label: {
                            Label(isPreviewMode ? "Soạn thảo" : "Xem trước", systemImage: isPreviewMode ? "pencil" : "eye")
                                .font(AppTypography.captionBold)
                        }
                        
                        // Nút Xóa Note
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.loss)
                        }
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Toolbar formatting: Bold, Italic
                if !isPreviewMode {
                    HStack(spacing: 12) {
                        Button {
                            applyFormat(marker: "**")
                        } label: {
                            Text("B")
                                .font(.system(size: 15, weight: .black))
                                .frame(width: 32, height: 28)
                                .background(AppColors.surface)
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
                                .cornerRadius(6)
                        }
                        
                        Spacer()
                    }
                }
                
                // Content area
                if isPreviewMode {
                    Text(content.isEmpty ? "*(Chưa có nội dung)*" : content)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(10)
                } else {
                    TextEditor(text: $content)
                        .font(AppTypography.body)
                        .frame(minHeight: 300)
                        .scrollContentBackground(.hidden)
                        .background(AppColors.cardBackground)
                        .cornerRadius(10)
                        .padding(4)
                        .onChange(of: content) { _ in autoSave() }
                }
            }
            .padding()
        }
        .onAppear {
            title = note.title
            content = note.content
            selectedFolderId = note.folderId
        }
        .alert("Xóa ghi chú này?", isPresented: $showDeleteConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa", role: .destructive) {
                dataStore.deleteNote(id: note.id)
            }
        }
    }
    
    private func autoSave() {
        try? dataStore.patchNote(
            id: note.id,
            title: title,
            content: content,
            folderId: selectedFolderId
        )
    }
    
    private func applyFormat(marker: String) {
        // Áp dụng định dạng inline formatting từ NoteFormattingEngine
        let res = NoteFormattingEngine.formatInlineSelection(
            value: content,
            start: (content as NSString).length,
            end: (content as NSString).length,
            marker: marker
        )
        content = res.value
        autoSave()
    }
}
