import Foundation
import SwiftUI

// MARK: - Notebook, Calendar Notes & Attachments Extension
extension TradeDataStore {
    
    // MARK: - Notebook & Folders
    
    public func createFolder(name: String) throws -> NotebookFolder {
        let (folder, updated) = try NotebookEngine.createFolder(name: name, existingFolders: folders)
        self.folders = updated
        saveToDisk()
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertFolders([folder])
            }
        }
        return folder
    }

    public func renameFolder(id: String, name: String) throws {
        let updated = try NotebookEngine.renameFolder(id: id, name: name, existingFolders: folders)
        self.folders = updated
        saveToDisk()
        if let f = folders.first(where: { $0.id == id }) {
            Task {
                if SupabaseService.shared.isConfigured {
                    try? await SupabaseService.shared.upsertFolders([f])
                }
            }
        }
    }
    
    public func deleteFolder(id: String) throws {
        let (updatedFolders, updatedNotes) = try NotebookEngine.deleteFolder(id: id, folders: folders, notes: notebookNotes)
        self.folders = updatedFolders
        self.notebookNotes = updatedNotes
        saveToDisk(immediate: true)
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.deleteFolder(id: id)
            }
        }
    }
    
    public func createNote(
        folderId: String? = nil,
        title: String = "",
        content: String = "",
        tags: [String] = [],
        tradeKey: String? = nil,
        dayDate: String? = nil
    ) throws -> NotebookNote {
        let (note, updated) = try NotebookEngine.createNote(
            folderId: folderId,
            title: title,
            content: content,
            tags: tags,
            tradeKey: tradeKey,
            dayDate: dayDate,
            folders: folders,
            existingNotes: notebookNotes
        )
        self.notebookNotes = updated
        saveToDisk()
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertNotes([note])
            }
        }
        return note
    }
    
    public func patchNote(
        id: String,
        title: String? = nil,
        content: String? = nil,
        tags: [String]? = nil,
        folderId: String? = nil,
        tradeKey: String?? = nil
    ) throws -> NotebookNote {
        let (note, updated) = try NotebookEngine.patchNote(
            id: id,
            title: title,
            content: content,
            tags: tags,
            folderId: folderId,
            tradeKey: tradeKey,
            folders: folders,
            notes: notebookNotes
        )
        self.notebookNotes = updated
        saveToDisk()
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertNotes([note])
            }
        }
        return note
    }
    
    public func deleteNote(id: String) {
        self.notebookNotes = NotebookEngine.deleteNote(id: id, notes: notebookNotes)
        saveToDisk(immediate: true)
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.deleteNote(id: id)
            }
        }
    }
    
    public func saveJournalDayNote(date: String, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteCalendarNote(for: date)
            return
        }
        self.journalDays[date] = note
        let jNote = JournalNote(date: date, content: note, updatedAt: Date())
        self.calendarNotes[date] = jNote
        saveToDisk()
        Task {
            try? await SupabaseService.shared.upsertJournalDay(jNote)
        }
    }
    
    public func getJournalDayNote(date: String) -> String {
        self.journalDays[date] ?? ""
    }
    
    public func filteredNotes(
        folderId: String? = nil,
        searchQuery: String? = nil,
        tag: String? = nil,
        sort: NoteSortOrder = .updated
    ) -> (notes: [NotebookNote], folders: [NotebookFolder]) {
        NotebookEngine.filterNotes(
            notes: notebookNotes,
            folders: folders,
            folderId: folderId,
            searchQuery: searchQuery,
            tag: tag,
            sort: sort
        )
    }
    
    // MARK: - Calendar Notes
    
    public func saveCalendarNote(_ note: JournalNote) {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && (note.rating == nil || note.rating == 0) {
            deleteCalendarNote(for: note.date)
            return
        }
        calendarNotes[note.date] = note
        journalDays[note.date] = note.content
        saveToDisk()
        Task {
            try? await SupabaseService.shared.upsertJournalDay(note)
        }
    }
    
    public func deleteCalendarNote(for date: String) {
        calendarNotes.removeValue(forKey: date)
        journalDays.removeValue(forKey: date)
        saveToDisk(immediate: true)
        Task {
            try? await SupabaseService.shared.deleteJournalDay(date: date)
        }
    }
    
    // MARK: - Attachments Management
    
    public var attachmentsBaseUrl: URL {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = baseDir.appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public func attachmentsFor(ownerType: String, ownerId: String) -> [Attachment] {
        attachments.filter { $0.ownerType == ownerType && $0.ownerId == ownerId }
    }
    
    public func addAttachment(
        ownerType: String,
        ownerId: String,
        name: String,
        data: Data
    ) throws -> Attachment {
        let validation = try AttachmentEngine.validateAttachment(data: data, declaredName: name)
        let attId = JournalIds.newId()
        let relativePath = AttachmentEngine.storagePath(
            ownerType: ownerType,
            ownerId: ownerId,
            id: attId,
            name: validation.cleanName
        )
        
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileUrl, options: .atomic)
        
        let attachment = Attachment(
            id: attId,
            ownerType: ownerType,
            ownerId: ownerId,
            name: validation.cleanName,
            mime: validation.mime,
            size: data.count,
            storagePath: relativePath,
            status: "ready"
        )
        
        attachments.append(attachment)
        saveToDisk(immediate: true)
        
        if SupabaseService.shared.isConfigured {
            Task {
                try? await SupabaseService.shared.uploadAttachmentFile(
                    storagePath: relativePath,
                    data: data,
                    mime: validation.mime
                )
                try? await SupabaseService.shared.upsertAttachments([attachment])
            }
        }
        
        return attachment
    }
    
    public func saveChartScreenshot(
        tradeKey: String,
        symbol: String,
        dataUrl: String
    ) throws -> Attachment {
        let data = try AttachmentEngine.validateChartScreenshotPng(dataUrl: dataUrl)
        let safeSymbol = symbol
            .replacingOccurrences(of: #"[^a-zA-Z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = "chart-\(safeSymbol.isEmpty ? "trade" : safeSymbol).png"
        return try addAttachment(
            ownerType: "trade",
            ownerId: tradeKey,
            name: filename,
            data: data
        )
    }
    
    public func deleteAttachment(id: String) throws {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let att = attachments[index]
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(att.storagePath)
        try? FileManager.default.removeItem(at: fileUrl)
        attachments.remove(at: index)
        saveToDisk(immediate: true)
        
        if SupabaseService.shared.isConfigured {
            Task {
                try? await SupabaseService.shared.deleteAttachmentFile(storagePath: att.storagePath)
            }
        }
    }
    
    public func attachmentFileData(storagePath: String) -> Data? {
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(storagePath)
        return try? Data(contentsOf: fileUrl)
    }
}
