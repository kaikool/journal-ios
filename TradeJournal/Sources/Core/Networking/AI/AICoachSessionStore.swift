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
    private let diskUrl: URL = JSONDiskStore.appSupportFileURL(filename: "ai_coach_sessions.json")
    
    private init() {
        if let decoded = JSONDiskStore.load([String: AICoachSessionData].self, from: diskUrl) {
            self.cache = decoded
        }
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
        
        JSONDiskStore.saveAsync(snapshot, to: diskUrl)
    }
    
    public func clear(key: String) {
        lock.lock()
        cache.removeValue(forKey: key)
        let snapshot = cache
        lock.unlock()
        
        JSONDiskStore.saveAsync(snapshot, to: diskUrl)
    }
    
    public func clearAll() {
        lock.lock()
        cache.removeAll()
        let snapshot = cache
        lock.unlock()
        
        JSONDiskStore.saveAsync(snapshot, to: diskUrl)
    }
}
