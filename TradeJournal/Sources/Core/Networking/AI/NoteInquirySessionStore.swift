import Foundation

/// Thread-safe in-memory and persistent disk session store for Note AI Inquiries.
/// Preserves multi-turn inquiries, reflections, and follow-ups per note across sheet dismissals and app restarts.
public final class NoteInquirySessionStore: @unchecked Sendable {
    public static let shared = NoteInquirySessionStore()
    
    private var memoryCache: [String: [AICoachMessage]] = [:]
    private let lock = NSLock()
    private let diskUrl: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let dir = appSupport.appendingPathComponent("NoteInquiries", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskUrl = dir.appendingPathComponent("sessions.json")
        loadFromDisk()
    }
    
    public func getMessages(noteId: String) -> [AICoachMessage] {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache[noteId] ?? []
    }
    
    public func saveMessages(noteId: String, messages: [AICoachMessage]) {
        lock.lock()
        memoryCache[noteId] = messages
        let snapshot = memoryCache
        lock.unlock()
        
        saveToDiskAsync(snapshot: snapshot)
    }
    
    public func clear(noteId: String) {
        lock.lock()
        memoryCache.removeValue(forKey: noteId)
        let snapshot = memoryCache
        lock.unlock()
        
        saveToDiskAsync(snapshot: snapshot)
    }
    
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: diskUrl),
              let decoded = try? JSONDecoder().decode([String: [AICoachMessage]].self, from: data) else {
            return
        }
        lock.lock()
        memoryCache = decoded
        lock.unlock()
    }
    
    private func saveToDiskAsync(snapshot: [String: [AICoachMessage]]) {
        Task.detached(priority: .background) { [diskUrl = self.diskUrl] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: diskUrl, options: .atomic)
        }
    }
}
