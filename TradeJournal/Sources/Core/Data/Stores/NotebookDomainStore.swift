import Foundation
import Combine

/// Dedicated domain store managing notebook notes, folders, and calendar day reflections.
/// Part of Item 1: TradeDataStore God Object decomposition into domain stores.
@MainActor
public final class NotebookDomainStore: ObservableObject {
    @Published public var folders: [NotebookFolder] = []
    @Published public var notebookNotes: [NotebookNote] = []
    @Published public var journalDays: [String: String] = [:]
    @Published public var calendarNotes: [String: JournalNote] = [:]

    public init(
        folders: [NotebookFolder] = [],
        notebookNotes: [NotebookNote] = [],
        journalDays: [String: String] = [:],
        calendarNotes: [String: JournalNote] = [:]
    ) {
        self.folders = folders
        self.notebookNotes = notebookNotes
        self.journalDays = journalDays
        self.calendarNotes = calendarNotes
    }

    public func findNote(byId id: String) -> NotebookNote? {
        notebookNotes.first { $0.id == id }
    }
}
