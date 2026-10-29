import Foundation

// MARK: - Local Persistent & Memory Cache for Trade Replay Candlesticks
// Stores fetched historical MarketBar arrays locally by trade id and resolution,
// eliminating loading spinners on subsequent reviews while preventing timeframe mismatch.
public final class TradeReplayCacheStore: @unchecked Sendable {
    public static let shared = TradeReplayCacheStore()
    
    private let lock = NSLock()
    private var memoryCache: [String: [MarketBar]] = [:]
    
    private let fileManager = FileManager.default
    private let cacheDirectoryUrl: URL
    
    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.cacheDirectoryUrl = base.appendingPathComponent("TradeReplayCandles_v4", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectoryUrl, withIntermediateDirectories: true)
    }
    
    private func cacheKey(tradeId: String, resolution: String) -> String {
        "\(tradeId)_\(resolution)"
    }
    
    public func getBars(for tradeId: String, resolution: String) -> [MarketBar]? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = cacheKey(tradeId: tradeId, resolution: resolution)
        
        // 1. Check memory cache (instant 0ms)
        if let mem = memoryCache[key], !mem.isEmpty {
            return mem
        }
        
        // 2. Check resolution-scoped disk cache
        let fileUrl = cacheDirectoryUrl.appendingPathComponent("\(key).json")
        if fileManager.fileExists(atPath: fileUrl.path),
           let data = try? Data(contentsOf: fileUrl),
           let decoded = try? JSONDecoder().decode([MarketBar].self, from: data),
           !decoded.isEmpty {
            memoryCache[key] = decoded
            return decoded
        }
        
        return nil
    }
    
    public func saveBars(_ bars: [MarketBar], for tradeId: String, resolution: String) {
        guard !bars.isEmpty else { return }
        
        let key = cacheKey(tradeId: tradeId, resolution: resolution)
        lock.lock()
        memoryCache[key] = bars
        lock.unlock()
        
        // Save to disk asynchronously so we never block the UI thread
        let dir = self.cacheDirectoryUrl
        DispatchQueue.global(qos: .utility).async {
            let fileUrl = dir.appendingPathComponent("\(key).json")
            if let data = try? JSONEncoder().encode(bars) {
                try? data.write(to: fileUrl, options: [.atomic])
            }
        }
    }
    
    /// Backward-compatible resolution-agnostic lookup with priority probing
    public func getBars(for tradeId: String) -> [MarketBar]? {
        for res in ["5m", "1m", "15m", "1h", "4h", "1d"] {
            if let b = getBars(for: tradeId, resolution: res), !b.isEmpty {
                return b
            }
        }
        
        lock.lock()
        defer { lock.unlock() }
        let legacyFileUrl = cacheDirectoryUrl.appendingPathComponent("\(tradeId).json")
        if fileManager.fileExists(atPath: legacyFileUrl.path),
           let data = try? Data(contentsOf: legacyFileUrl),
           let decoded = try? JSONDecoder().decode([MarketBar].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return nil
    }
    
    /// Backward-compatible resolution-agnostic save (defaults to 5m)
    public func saveBars(_ bars: [MarketBar], for tradeId: String) {
        saveBars(bars, for: tradeId, resolution: "5m")
    }
    
    public func clearAll() {
        lock.lock()
        memoryCache.removeAll()
        lock.unlock()
        try? fileManager.removeItem(at: cacheDirectoryUrl)
        try? fileManager.createDirectory(at: cacheDirectoryUrl, withIntermediateDirectories: true)
    }
}
