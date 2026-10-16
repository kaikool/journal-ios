import Foundation

public enum NoteSortOrder: String, CaseIterable, Sendable {
    case updated
    case created
    case title
}

public struct JournalChronologyDay: Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String
    public let stats: DayStats?
    public let hasNote: Bool
    public let notePreview: String
    
    public init(date: String, stats: DayStats?, hasNote: Bool, notePreview: String) {
        self.date = date
        self.stats = stats
        self.hasNote = hasNote
        self.notePreview = notePreview
    }
}

public struct JournalDayDetail: Equatable, Sendable {
    public let date: String
    public let metrics: TradeMetrics
    public let trades: [Trade]
    public let intraday: [IntradayPoint]
    public let note: String
    
    public init(date: String, metrics: TradeMetrics, trades: [Trade], intraday: [IntradayPoint], note: String) {
        self.date = date
        self.metrics = metrics
        self.trades = trades
        self.intraday = intraday
        self.note = note
    }
}

public enum NotebookError: LocalizedError, Equatable {
    case folderNotFound
    case cannotDeleteSystemFolder
    case invalidFolderName(String)
    case noteNotFound
    case invalidFolderForNote
    
    public var errorDescription: String? {
        switch self {
        case .folderNotFound:
            return "Folder not found"
        case .cannotDeleteSystemFolder:
            return "This folder cannot be deleted."
        case .invalidFolderName(let reason):
            return reason
        case .noteNotFound:
            return "Note not found"
        case .invalidFolderForNote:
            return "Folder not found"
        }
    }
}

/// 1:1 port từ các handler:
/// - `source-repo/apps/web/src/app/api/folders/route.ts`
/// - `source-repo/apps/web/src/app/api/folders/[id]/route.ts`
/// - `source-repo/apps/web/src/app/api/notes/route.ts`
/// - `source-repo/apps/web/src/app/api/notes/[id]/route.ts`
/// - `source-repo/apps/web/src/app/api/journal/route.ts`
/// - `source-repo/apps/web/src/app/api/journal/[date]/route.ts`
public enum NotebookEngine {
    
    public static let systemFolderAll = "all"
    public static let systemFolderTradeNotes = "trade-notes"
    public static let systemFolderMyNotes = "my-notes"
    
    /// 3 thư mục hệ thống mặc định được khởi tạo theo `notebook-postgres.test.ts` & `notebook-folder-delete.test.ts`
    public static var defaultSystemFolders: [NotebookFolder] {
        [
            NotebookFolder(id: systemFolderAll, name: "All notes", kind: "system", createdAt: "2026-01-01T00:00:00.000Z"),
            NotebookFolder(id: systemFolderTradeNotes, name: "Trade notes", kind: "system", createdAt: "2026-01-01T00:00:00.500Z"),
            NotebookFolder(id: systemFolderMyNotes, name: "My notes", kind: "system", createdAt: "2026-01-01T00:00:01.000Z")
        ]
    }
    
    /// Tạo thư mục mới (`POST /api/folders`)
    public static func createFolder(
        name: String,
        existingFolders: [NotebookFolder]
    ) throws -> (folder: NotebookFolder, folders: [NotebookFolder]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NotebookError.invalidFolderName("Enter a folder name.")
        }
        if trimmed.count > 100 {
            throw NotebookError.invalidFolderName("Folder names must be 100 characters or fewer.")
        }
        
        let newFolder = NotebookFolder(
            id: JournalIds.newId(),
            name: trimmed,
            kind: "user",
            createdAt: JournalIds.nowIso()
        )
        
        var updated = existingFolders
        updated.append(newFolder)
        return (newFolder, updated)
    }
    
    /// Xóa thư mục (`DELETE /api/folders/[id]`):
    /// BẢO TOÀN DỮ LIỆU: Toàn bộ ghi chú trong thư mục bị xoá sẽ được chuyển về "my-notes".
    /// Không cho phép xoá thư mục "all" hoặc "my-notes".
    public static func deleteFolder(
        id: String,
        folders: [NotebookFolder],
        notes: [NotebookNote]
    ) throws -> (folders: [NotebookFolder], notes: [NotebookNote]) {
        if id == systemFolderAll || id == systemFolderMyNotes {
            throw NotebookError.cannotDeleteSystemFolder
        }
        
        guard let index = folders.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw NotebookError.folderNotFound
        }
        
        var updatedFolders = folders
        var targetFolder = updatedFolders[index]
        targetFolder.deletedAt = JournalIds.nowIso()
        updatedFolders[index] = targetFolder
        
        // Di chuyển toàn bộ ghi chú của thư mục này sang "my-notes"
        let updatedNotes = notes.map { note -> NotebookNote in
            if note.folderId == id {
                var modified = note
                modified.folderId = systemFolderMyNotes
                modified.updatedAt = JournalIds.nowIso()
                return modified
            }
            return note
        }
        
        return (updatedFolders, updatedNotes)
    }
    
    /// Tạo ghi chú mới (`POST /api/notes`)
    public static func createNote(
        folderId: String? = nil,
        title: String = "",
        content: String = "",
        tags: [String] = [],
        tradeKey: String? = nil,
        dayDate: String? = nil,
        folders: [NotebookFolder],
        existingNotes: [NotebookNote]
    ) throws -> (note: NotebookNote, notes: [NotebookNote]) {
        let targetFolderId = folderId ?? systemFolderMyNotes
        if targetFolderId == systemFolderAll {
            throw NotebookError.invalidFolderForNote
        }
        
        let activeFolders = folders.filter { $0.deletedAt == nil }
        guard activeFolders.contains(where: { $0.id == targetFolderId }) else {
            throw NotebookError.folderNotFound
        }
        
        let now = JournalIds.nowIso()
        var tagsJson: String? = nil
        if !tags.isEmpty {
            if let data = try? JSONEncoder().encode(tags), let str = String(data: data, encoding: .utf8) {
                tagsJson = str
            }
        }
        
        let newNote = NotebookNote(
            id: JournalIds.newId(),
            folderId: targetFolderId,
            title: title,
            content: content,
            tagsJson: tagsJson,
            tradeKey: tradeKey,
            dayDate: dayDate,
            createdAt: now,
            updatedAt: now
        )
        
        var updated = existingNotes
        updated.append(newNote)
        return (newNote, updated)
    }
    
    /// Cập nhật ghi chú (`PATCH /api/notes/[id]`)
    public static func patchNote(
        id: String,
        title: String? = nil,
        content: String? = nil,
        tags: [String]? = nil,
        folderId: String? = nil,
        folders: [NotebookFolder],
        notes: [NotebookNote]
    ) throws -> (note: NotebookNote, notes: [NotebookNote]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.noteNotFound
        }
        
        if let targetFolderId = folderId {
            if targetFolderId == systemFolderAll {
                throw NotebookError.invalidFolderForNote
            }
            let activeFolders = folders.filter { $0.deletedAt == nil }
            guard activeFolders.contains(where: { $0.id == targetFolderId }) else {
                throw NotebookError.folderNotFound
            }
        }
        
        var target = notes[index]
        if let newTitle = title { target.title = newTitle }
        if let newContent = content { target.content = newContent }
        if let newFolderId = folderId { target.folderId = newFolderId }
        if let newTags = tags {
            if let data = try? JSONEncoder().encode(newTags), let str = String(data: data, encoding: .utf8) {
                target.tagsJson = str
            }
        }
        target.updatedAt = JournalIds.nowIso()
        
        var updated = notes
        updated[index] = target
        return (target, updated)
    }
    
    /// Xóa ghi chú (`DELETE /api/notes/[id]`)
    public static func deleteNote(
        id: String,
        notes: [NotebookNote]
    ) -> [NotebookNote] {
        notes.filter { $0.id != id }
    }
    
    /// Lọc và tìm kiếm danh sách ghi chú (`GET /api/notes`)
    public static func filterNotes(
        notes: [NotebookNote],
        folders: [NotebookFolder],
        folderId: String? = nil,
        searchQuery: String? = nil,
        tag: String? = nil,
        sort: NoteSortOrder = .updated
    ) -> (notes: [NotebookNote], folders: [NotebookFolder]) {
        let activeFolders = folders.filter { $0.deletedAt == nil }
        let activeFolderIds = Set(activeFolders.map { $0.id })
        
        // Chỉ lấy ghi chú thuộc các thư mục đang hoạt động
        var result = notes.filter { activeFolderIds.contains($0.folderId) }
        
        if let targetFolder = folderId, targetFolder != systemFolderAll {
            result = result.filter { $0.folderId == targetFolder }
        }
        
        if let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty {
            result = result.filter { note in
                note.title.lowercased().contains(query) || note.content.lowercased().contains(query)
            }
        }
        
        if let targetTag = tag, !targetTag.isEmpty {
            result = result.filter { note in
                guard let json = note.tagsJson,
                      let data = json.data(using: .utf8),
                      let tags = try? JSONDecoder().decode([String].self, from: data) else {
                    return false
                }
                return tags.contains(targetTag)
            }
        }
        
        // Sắp xếp
        result.sort { a, b in
            switch sort {
            case .created:
                return a.createdAt > b.createdAt
            case .title:
                return a.title.localizedCompare(b.title) == .orderedAscending
            case .updated:
                return a.updatedAt > b.updatedAt
            }
        }
        
        let sortedFolders = activeFolders.sorted { $0.createdAt < $1.createdAt }
        return (result, sortedFolders)
    }
    
    /// Lấy dòng thời gian lịch sử nhật ký (`GET /api/journal`)
    /// Trả về tất cả các ngày có giao dịch HOẶC có ghi chú ngày, xếp mới nhất lên đầu.
    public static func journalChronology(
        trades: [Trade],
        journalDays: [String: String], // date -> note
        fromDate: String? = nil,
        toDate: String? = nil,
        timeZone: String = "UTC"
    ) -> [JournalChronologyDay] {
        let tz = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC") ?? .current
        let dailyStatsList = FinancialMetricsEngine.dailyStats(trades: trades, timeZone: tz)
        var tradeDaysMap: [String: DayStats] = [:]
        for stat in dailyStatsList {
            tradeDaysMap[stat.date] = stat
        }
        
        let allDatesSet = Set(tradeDaysMap.keys).union(journalDays.keys)
        var filteredDates = Array(allDatesSet)
        
        if let from = fromDate, !from.isEmpty {
            filteredDates = filteredDates.filter { $0 >= from }
        }
        if let to = toDate, !to.isEmpty {
            filteredDates = filteredDates.filter { $0 <= to }
        }
        
        filteredDates.sort(by: >)
        
        return filteredDates.map { date in
            let stats = tradeDaysMap[date]
            let noteText = journalDays[date] ?? ""
            let hasNote = !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let preview = String(noteText.prefix(200))
            return JournalChronologyDay(
                date: date,
                stats: stats,
                hasNote: hasNote,
                notePreview: preview
            )
        }
    }
    
    /// Chi tiết một ngày nhật ký (`GET /api/journal/[date]`)
    public static func journalDayDetail(
        date: String,
        trades: [Trade],
        executions: [Execution],
        journalDayNote: String?,
        timeZone: String = "UTC"
    ) -> JournalDayDetail {
        let tz = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC") ?? .current
        
        // Lọc các trade đóng trong ngày này
        let dayTrades = trades.filter { trade in
            guard let closed = trade.closedAt else { return false }
            return AggregateEngine.dayKeyOf(date: closed, timeZone: tz) == date
        }
        
        let metrics = FinancialMetricsEngine.computeMetrics(trades: dayTrades)
        var execTimes: [String: Date] = [:]
        for exec in executions {
            execTimes[exec.id] = exec.executedAt
        }
        let intraday = FinancialMetricsEngine.intradayCurve(
            trades: dayTrades,
            executionTimes: execTimes,
            date: date,
            timeZone: tz
        )
        
        return JournalDayDetail(
            date: date,
            metrics: metrics,
            trades: dayTrades,
            intraday: intraday,
            note: journalDayNote ?? ""
        )
    }
}
