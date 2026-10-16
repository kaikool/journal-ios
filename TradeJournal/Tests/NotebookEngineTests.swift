import XCTest
@testable import TradeJournal

final class NotebookEngineTests: XCTestCase {
    
    // MARK: - Note Formatting Tests (1:1 port từ source-repo note-formatting.test.ts)
    
    func testKeepsSelectionWhitespaceOutsideBoldAndItalicMarkers() {
        let markers = ["*", "**"]
        for marker in markers {
            let next = NoteFormattingEngine.formatInlineSelection(
                value: "A new notes test",
                start: 2,
                end: 6,
                marker: marker
            )
            XCTAssertEqual(next.value, "A \(marker)new\(marker) notes test")
            
            let nsStr = next.value as NSString
            let selectedSubstring = nsStr.substring(with: NSRange(location: next.selectionStart, length: next.selectionEnd - next.selectionStart))
            XCTAssertEqual(selectedSubstring, "new")
        }
    }
    
    func testInsertsPlaceholderTextWhenFormattingWithoutSelection() {
        // Bold placeholder
        let boldRes = NoteFormattingEngine.formatInlineSelection(
            value: "Test ",
            start: 5,
            end: 5,
            marker: "**"
        )
        XCTAssertEqual(boldRes.value, "Test **bold text**")
        let nsBold = boldRes.value as NSString
        let boldSub = nsBold.substring(with: NSRange(location: boldRes.selectionStart, length: boldRes.selectionEnd - boldRes.selectionStart))
        XCTAssertEqual(boldSub, "bold text")
        
        // Italic placeholder
        let italicRes = NoteFormattingEngine.formatInlineSelection(
            value: "Test ",
            start: 5,
            end: 5,
            marker: "*"
        )
        XCTAssertEqual(italicRes.value, "Test *italic text*")
        let nsItalic = italicRes.value as NSString
        let italicSub = nsItalic.substring(with: NSRange(location: italicRes.selectionStart, length: italicRes.selectionEnd - italicRes.selectionStart))
        XCTAssertEqual(italicSub, "italic text")
    }
    
    // MARK: - Notebook Postgres Tests (1:1 port từ source-repo notebook-postgres.test.ts)
    
    func testCreatesFiltersUpdatesAndDeletesNotesAsynchronously() throws {
        var folders = [
            NotebookFolder(id: "all", name: "All notes", kind: "system", createdAt: "2026-01-01T00:00:00.000Z"),
            NotebookFolder(id: "my-notes", name: "My notes", kind: "system", createdAt: "2026-01-01T00:00:01.000Z")
        ]
        var notes: [NotebookNote] = []
        
        // 1. Tạo folder với khoảng trắng cần trim
        let (createdFolder, updatedFolders) = try NotebookEngine.createFolder(
            name: " Setups ",
            existingFolders: folders
        )
        XCTAssertEqual(createdFolder.name, "Setups")
        folders = updatedFolders
        
        // 2. Tạo note trong folder mới
        let (createdNote, updatedNotes) = try NotebookEngine.createNote(
            folderId: createdFolder.id,
            title: "Breakout plan",
            content: "Wait for retest",
            tags: ["plan"],
            folders: folders,
            existingNotes: notes
        )
        XCTAssertEqual(createdNote.title, "Breakout plan")
        XCTAssertEqual(createdNote.content, "Wait for retest")
        notes = updatedNotes
        
        // 3. Lọc note với folder=all&q=breakout&tag=plan&sort=title
        let (filteredNotes, activeFolders) = NotebookEngine.filterNotes(
            notes: notes,
            folders: folders,
            folderId: "all",
            searchQuery: "breakout",
            tag: "plan",
            sort: .title
        )
        XCTAssertEqual(filteredNotes.map { $0.id }, [createdNote.id])
        XCTAssertEqual(activeFolders.count, 3)
        
        // 4. Patch note (đổi title và chuyển sang "my-notes")
        let (patchedNote, patchedNotes) = try NotebookEngine.patchNote(
            id: createdNote.id,
            title: "Updated",
            folderId: "my-notes",
            folders: folders,
            notes: notes
        )
        XCTAssertEqual(patchedNote.title, "Updated")
        XCTAssertEqual(patchedNote.content, "Wait for retest")
        XCTAssertEqual(patchedNote.folderId, "my-notes")
        notes = patchedNotes
        
        // 5. Xoá note
        notes = NotebookEngine.deleteNote(id: createdNote.id, notes: notes)
        XCTAssertEqual(notes.count, 0)
    }
    
    func testSoftDeletesFoldersWhilePreservingNotesInMyNotes() throws {
        // Invariant R004: Xoá folder không bao giờ được làm mất note
        let folderA = NotebookFolder(
            id: "folder-a",
            name: "Archive",
            kind: "user",
            createdAt: "2026-01-01T00:00:02.000Z"
        )
        var folders = NotebookEngine.defaultSystemFolders + [folderA]
        
        let noteA = NotebookNote(
            id: "note-a",
            folderId: "folder-a",
            title: "Preserved",
            content: "Keep me",
            createdAt: "2026-01-01T00:00:03.000Z",
            updatedAt: "2026-01-01T00:00:03.000Z"
        )
        var notes = [noteA]
        
        // Xoá folder-a
        let (updatedFolders, updatedNotes) = try NotebookEngine.deleteFolder(
            id: "folder-a",
            folders: folders,
            notes: notes
        )
        folders = updatedFolders
        notes = updatedNotes
        
        // Kiểm tra folder-a bị soft delete (deletedAt != nil)
        let deletedFolder = folders.first(where: { $0.id == "folder-a" })
        XCTAssertNotNil(deletedFolder?.deletedAt)
        
        // Kiểm tra note-a được bảo toàn và chuyển sang "my-notes"
        let preservedNote = notes.first(where: { $0.id == "note-a" })
        XCTAssertEqual(preservedNote?.folderId, NotebookEngine.systemFolderMyNotes)
        XCTAssertEqual(preservedNote?.title, "Preserved")
        XCTAssertEqual(preservedNote?.content, "Keep me")
    }
    
    func testCannotDeleteSystemFoldersAllAndMyNotes() {
        let folders = NotebookEngine.defaultSystemFolders
        let notes: [NotebookNote] = []
        
        XCTAssertThrowsError(try NotebookEngine.deleteFolder(id: "all", folders: folders, notes: notes)) { error in
            XCTAssertEqual(error as? NotebookError, NotebookError.cannotDeleteSystemFolder)
        }
        
        XCTAssertThrowsError(try NotebookEngine.deleteFolder(id: "my-notes", folders: folders, notes: notes)) { error in
            XCTAssertEqual(error as? NotebookError, NotebookError.cannotDeleteSystemFolder)
        }
        
        // Nhưng trade-notes có thể xoá được
        XCTAssertNoThrow(try NotebookEngine.deleteFolder(id: "trade-notes", folders: folders, notes: notes))
    }
    
    // MARK: - Journal Chronology Tests (1:1 port từ source-repo journal/route.ts)
    
    func testJournalChronologyIncludesTradeDaysAndNoteOnlyDays() {
        let calendar = Calendar(identifier: .gregorian)
        var comp = DateComponents()
        comp.year = 2026; comp.month = 10; comp.day = 14; comp.hour = 14; comp.minute = 0
        let date14 = calendar.date(from: comp)!
        
        comp.day = 15
        let date15 = calendar.date(from: comp)!
        
        let trade1 = Trade(
            id: "t1", accountId: "acc-1", symbol: "AAPL", direction: .long, status: .closed,
            openedAt: date14, closedAt: date14, totalQuantity: 10, totalCost: 1500,
            avgEntryPrice: 150, avgExitPrice: 155, grossPnl: 50, netPnl: 48, totalFee: 2, fillsCount: 2
        )
        let trade2 = Trade(
            id: "t2", accountId: "acc-1", symbol: "NVDA", direction: .short, status: .closed,
            openedAt: date15, closedAt: date15, totalQuantity: 5, totalCost: 600,
            avgEntryPrice: 120, avgExitPrice: 110, grossPnl: 50, netPnl: 49, totalFee: 1, fillsCount: 2
        )
        
        // Ngày 2026-10-16 là ngày nghỉ (không có trade nào, chỉ có ghi chú lập kế hoạch)
        let journalDays = [
            "2026-10-14": "Traded AAPL according to plan",
            "2026-10-16": "Weekend review and next week watch list"
        ]
        
        let chronology = NotebookEngine.journalChronology(
            trades: [trade1, trade2],
            journalDays: journalDays,
            timeZone: "UTC"
        )
        
        // Kỳ vọng hiển thị cả 3 ngày xếp mới nhất lên đầu: 2026-10-16, 2026-10-15, 2026-10-14
        XCTAssertEqual(chronology.count, 3)
        XCTAssertEqual(chronology[0].date, "2026-10-16")
        XCTAssertNil(chronology[0].stats) // Không có trade
        XCTAssertTrue(chronology[0].hasNote)
        XCTAssertEqual(chronology[0].notePreview, "Weekend review and next week watch list")
        
        XCTAssertEqual(chronology[1].date, "2026-10-15")
        XCTAssertNotNil(chronology[1].stats)
        XCTAssertEqual(chronology[1].stats?.netPnl, 49)
        XCTAssertFalse(chronology[1].hasNote)
        
        XCTAssertEqual(chronology[2].date, "2026-10-14")
        XCTAssertNotNil(chronology[2].stats)
        XCTAssertEqual(chronology[2].stats?.netPnl, 48)
        XCTAssertTrue(chronology[2].hasNote)
    }
}
