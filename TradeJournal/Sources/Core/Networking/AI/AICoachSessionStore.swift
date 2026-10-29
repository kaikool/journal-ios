import Foundation

// MARK: - Persistent Session Record for AI Discussions
public struct AICoachSessionData: Codable, Sendable {
    public let result: String
    public let followUps: [AICoachMessage]
    public let updatedAt: Date
    
    public init(result: String, followUps: [AICoachMessage], updatedAt: Date = Date()) {
        self.result = result
        self.followUps = followUps
        self.updatedAt = updatedAt
    }
}

// MARK: - Thread-Safe Persistent Session Cache for Multi-Turn AI Discussions
/// Preserves active conversations, pre-trade discussions, and trade audit inquiries across sheet dismissals and app restarts.
public final class AICoachSessionStore: @unchecked Sendable {
    public static let shared = AICoachSessionStore()
    
    private var cache: [String: AICoachSessionData] = [:]
    private let lock = NSLock()
    private let diskUrl: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("TradeJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai_coach_sessions.json")
    }()
    
    private init() {
        loadFromDisk()
    }
    
    public func get(key: String) -> (result: String, followUps: [AICoachMessage])? {
        lock.lock()
        defer { lock.unlock() }
        guard let session = cache[key] else { return nil }
        return (session.result, session.followUps)
    }
    
    public func save(key: String, result: String, followUps: [AICoachMessage]) {
        lock.lock()
        cache[key] = AICoachSessionData(result: result, followUps: followUps, updatedAt: Date())
        
        // Prune older sessions if count exceeds 60 to prevent unbounded local file growth
        if cache.count > 60 {
            let sortedKeys = cache.sorted { $0.value.updatedAt < $1.value.updatedAt }.map { $0.key }
            for k in sortedKeys.prefix(cache.count - 60) {
                cache.removeValue(forKey: k)
            }
        }
        
        let snapshot = cache
        lock.unlock()
        
        saveToDiskAsync(snapshot: snapshot)
    }
    
    public func clear(key: String) {
        lock.lock()
        cache.removeValue(forKey: key)
        let snapshot = cache
        lock.unlock()
        
        saveToDiskAsync(snapshot: snapshot)
    }
    
    public func clearAll() {
        lock.lock()
        cache.removeAll()
        let snapshot = cache
        lock.unlock()
        
        saveToDiskAsync(snapshot: snapshot)
    }
    
    // MARK: - Disk Persistence
    
    private func saveToDiskAsync(snapshot: [String: AICoachSessionData]) {
        guard let url = diskUrl else { return }
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
    
    private func loadFromDisk() {
        guard let url = diskUrl, FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: AICoachSessionData].self, from: data) else {
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        self.cache = decoded
    }
}
