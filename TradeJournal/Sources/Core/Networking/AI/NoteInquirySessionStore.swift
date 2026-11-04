import Foundation

/// Thread-safe in-memory and persistent disk session store for Note AI Inquiries.
/// Preserves multi-turn inquiries, reflections, and follow-ups per note across sheet dismissals and app restarts.
public final class NoteInquirySessionStore: @unchecked Sendable {
    public static let shared = NoteInquirySessionStore()
    
    private var memoryCache: [String: [AICoachMessage]] = [:]
    private let lock = NSLock()
    private let diskUrl: URL = JSONDiskStore.appSupportFileURL(directory: "NoteInquiries", filename: "sessions.json")
    
    private init() {
        if let decoded = JSONDiskStore.load([String: [AICoachMessage]].self, from: diskUrl) {
            memoryCache = decoded
        }
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
        
        JSONDiskStore.saveAsync(snapshot, to: diskUrl, priority: .background)
    }
    
    public func clear(noteId: String) {
        lock.lock()
        memoryCache.removeValue(forKey: noteId)
        let snapshot = memoryCache
        lock.unlock()
        
        JSONDiskStore.saveAsync(snapshot, to: diskUrl, priority: .background)
    }
}
