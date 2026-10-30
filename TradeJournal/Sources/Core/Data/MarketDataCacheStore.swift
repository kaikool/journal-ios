import Foundation

// MARK: - Market Data Cache Store (Memory & Persistent Disk 2-Tier Caching)
// Drastically minimizes OANDA and Binance API requests, eliminates redundant network traffic,
// prevents HTTP 429 rate-limiting, and ensures 0ms instant UI rendering on subsequent reviews.
//
// Key Optimizations:
// 1. Permanent Caching for Closed Historical Trades:
//    Candles between openedAt and closedAt never change in the past. Once fetched, they are cached indefinitely.
// 2. Adaptive Timeframe-Based TTL for Pre-Trade Forward Analysis:
//    • Daily (D1): 15 minutes (900s) — daily candles only mutate at session close
//    • 4-Hour (H4): 5 minutes (300s)
//    • 1-Hour (H1): 2 minutes (120s)
//    • 15-Min (M15): 60 seconds
//    • 5-Min (M5): 20 seconds
// 3. In-Flight Request Coalescing (De-duplication):
//    If multiple UI components or tasks request the same symbol/resolution concurrently,
//    only ONE network call executes; all other callers await the exact same task.
// 4. Offline Fallback:
//    Cached bars persist across app restarts in the local Caches directory.
public final class MarketDataCacheStore: @unchecked Sendable {
    public static let shared = MarketDataCacheStore()
    
    public struct CacheEntry: Codable, Sendable {
        public let bars: [MarketBar]
        public let cachedAtTimestamp: Int64
        public let ttlSeconds: Double
        public let isPermanent: Bool
        
        public var isExpired: Bool {
            if isPermanent { return false }
            let age = (Date().timeIntervalSince1970 * 1000.0 - Double(cachedAtTimestamp)) / 1000.0
            return age > ttlSeconds
        }
        
        public init(
            bars: [MarketBar],
            cachedAt: Date = Date(),
            ttlSeconds: Double,
            isPermanent: Bool = false
        ) {
            self.bars = bars
            self.cachedAtTimestamp = Int64(cachedAt.timeIntervalSince1970 * 1000)
            self.ttlSeconds = ttlSeconds
            self.isPermanent = isPermanent
        }
    }
    
    private let lock = NSLock()
    private var memoryCache: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<[MarketBar], Error>] = [:]
    
    private let fileManager = FileManager.default
    private let cacheDirectoryUrl: URL
    
    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.cacheDirectoryUrl = base.appendingPathComponent("MarketDataCache_v4", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectoryUrl, withIntermediateDirectories: true)
    }
    
    // MARK: - 1. Adaptive TTL Resolution Helper
    
    public static func defaultTTL(for resolution: String) -> Double {
        let clean = resolution.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "1d", "d", "daily", "d1":
            return 900 // 15 minutes
        case "4h", "h4":
            return 300 // 5 minutes
        case "1h", "h1":
            return 120 // 2 minutes
        case "30m", "m30":
            return 90  // 1.5 minutes
        case "15m", "m15":
            return 60  // 60 seconds
        case "5m", "m5":
            return 20  // 20 seconds
        case "1m", "m1":
            return 10  // 10 seconds
        default:
            return 60
        }
    }
    
    // MARK: - 2. Trade Bars Caching (Historical / Replay / AI Coach)
    
    public func getTradeBars(tradeId: String, resolution: String, isClosed: Bool) -> [MarketBar]? {
        let key = "trade_\(tradeId)_\(resolution)"
        if let bars = getBars(forKey: key, bypassExpiry: isClosed), !bars.isEmpty {
            return bars
        }
        // ONLY fallback to TradeReplayCacheStore for fully closed historical trades!
        // Open/running trades must never hit indefinite replay cache so fresh candles can be fetched.
        if isClosed {
            if let replayBars = TradeReplayCacheStore.shared.getBars(for: tradeId, resolution: resolution), !replayBars.isEmpty {
                return replayBars
            }
        }
        return nil
    }
    
    public func getStaleTradeBars(tradeId: String, resolution: String) -> [MarketBar]? {
        let key = "trade_\(tradeId)_\(resolution)"
        if let bars = getBars(forKey: key, bypassExpiry: true) {
            return bars
        }
        return TradeReplayCacheStore.shared.getBars(for: tradeId, resolution: resolution)
    }
    
    public func saveTradeBars(_ bars: [MarketBar], tradeId: String, resolution: String, isClosed: Bool) {
        guard !bars.isEmpty else { return }
        let key = "trade_\(tradeId)_\(resolution)"
        let ttl = isClosed ? 0.0 : 20.0 // 20s adaptive TTL if trade is still running, permanent if closed
        let entry = CacheEntry(bars: bars, ttlSeconds: ttl, isPermanent: isClosed)
        saveEntry(entry, forKey: key)
        if isClosed {
            TradeReplayCacheStore.shared.saveBars(bars, for: tradeId, resolution: resolution)
        }
    }
    
    public func invalidateTrade(tradeId: String) {
        lock.lock()
        for res in ["1m", "5m", "15m", "30m", "1h", "4h", "1d"] {
            let key = "trade_\(tradeId)_\(res)"
            memoryCache.removeValue(forKey: key)
            let sanitizedKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            let fileUrl = cacheDirectoryUrl.appendingPathComponent("\(sanitizedKey).json")
            try? fileManager.removeItem(at: fileUrl)
        }
        lock.unlock()
    }
    
    // MARK: - 3. Symbol Bars Caching (Pre-Trade Forward Analysis & Market Bias)
    
    public func getSymbolBars(symbol: String, resolution: String, count: Int) -> [MarketBar]? {
        let cleanSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let key = "sym_\(cleanSym)_\(resolution)_\(count)"
        return getBars(forKey: key, bypassExpiry: false)
    }
    
    public func getStaleSymbolBars(symbol: String, resolution: String, count: Int) -> [MarketBar]? {
        let cleanSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let key = "sym_\(cleanSym)_\(resolution)_\(count)"
        return getBars(forKey: key, bypassExpiry: true)
    }
    
    public func saveSymbolBars(_ bars: [MarketBar], symbol: String, resolution: String, count: Int) {
        guard !bars.isEmpty else { return }
        let cleanSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let key = "sym_\(cleanSym)_\(resolution)_\(count)"
        let ttl = Self.defaultTTL(for: resolution)
        let entry = CacheEntry(bars: bars, ttlSeconds: ttl, isPermanent: false)
        saveEntry(entry, forKey: key)
    }
    
    // MARK: - 4. In-Flight Request Coalescing (De-duplication)
    
    /// Ensures that duplicate concurrent requests for the exact same market resource await a single task.
    public func runCoalesced(
        key: String,
        operation: @escaping @Sendable () async throws -> [MarketBar]
    ) async throws -> [MarketBar] {
        lock.lock()
        if let existing = inFlightTasks[key] {
            lock.unlock()
            return try await existing.value
        }
        
        let task = Task<[MarketBar], Error> {
            defer {
                self.lock.lock()
                self.inFlightTasks.removeValue(forKey: key)
                self.lock.unlock()
            }
            return try await operation()
        }
        inFlightTasks[key] = task
        lock.unlock()
        
        return try await task.value
    }
    
    // MARK: - 5. Internal Cache Engine (Memory + Disk Fallback)
    
    private func getBars(forKey key: String, bypassExpiry: Bool) -> [MarketBar]? {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Check memory cache (instant 0ms)
        if let mem = memoryCache[key] {
            if bypassExpiry || !mem.isExpired {
                return mem.bars
            } else {
                memoryCache.removeValue(forKey: key)
            }
        }
        
        // 2. Check persistent disk cache
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let fileUrl = cacheDirectoryUrl.appendingPathComponent("\(sanitizedKey).json")
        guard fileManager.fileExists(atPath: fileUrl.path),
              let data = try? Data(contentsOf: fileUrl),
              let decoded = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        
        if bypassExpiry || !decoded.isExpired {
            memoryCache[key] = decoded
            return decoded.bars
        } else {
            // Expired on disk -> clean up
            try? fileManager.removeItem(at: fileUrl)
            return nil
        }
    }
    
    private func saveEntry(_ entry: CacheEntry, forKey key: String) {
        lock.lock()
        // Bounded memory cache: evict expired or older entries if count exceeds 100
        if memoryCache.count >= 100 {
            let expiredKeys = memoryCache.filter { $0.value.isExpired }.map(\.key)
            for k in expiredKeys {
                memoryCache.removeValue(forKey: k)
            }
            if memoryCache.count >= 100 {
                let overflowKeys = Array(memoryCache.keys.prefix(25))
                for k in overflowKeys {
                    memoryCache.removeValue(forKey: k)
                }
            }
        }
        memoryCache[key] = entry
        lock.unlock()
        
        // Asynchronously persist to disk to avoid blocking caller thread
        let dir = self.cacheDirectoryUrl
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        DispatchQueue.global(qos: .utility).async {
            let fileUrl = dir.appendingPathComponent("\(sanitizedKey).json")
            if let data = try? JSONEncoder().encode(entry) {
                try? data.write(to: fileUrl, options: [.atomic])
            }
        }
    }
    
    // MARK: - 6. Cache Eviction & Cleanup
    
    public func clearAll() {
        lock.lock()
        memoryCache.removeAll()
        inFlightTasks.removeAll()
        lock.unlock()
        
        try? fileManager.removeItem(at: cacheDirectoryUrl)
        try? fileManager.createDirectory(at: cacheDirectoryUrl, withIntermediateDirectories: true)
        
        TradeReplayCacheStore.shared.clearAll()
    }
}
