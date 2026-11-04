import Foundation

// MARK: - Session Footprint & Key Levels Coordinator
/// High-level orchestration pipeline coordinating:
/// 1. 0ms instant loading from Local Disk Cache (MarketDataCacheStore)
/// 2. Remote synchronization with Supabase (session_footprint_profiles)
/// 3. Minimal fallback OANDA API requests for computing missing historical profiles
/// 4. Realtime developing POC and Price Action Candlestick Pattern detection
public final class SessionFootprintCoordinator: Sendable {
    public static let shared = SessionFootprintCoordinator()
    
    private init() {}
    
    // MARK: - 1. Load Institutional Key Levels
    /// Loads historical session profiles and live developing levels with zero redundant OANDA quota usage.
    public func loadKeyLevels(
        for symbol: String,
        recentBars: [MarketBar] = []
    ) async -> (levels: [KeyLevel], profiles: [SessionProfileSnapshot], developing: DevelopingProfile?) {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return ([], [], nil) }
        
        // Step 1: Check Local Disk & Memory Cache
        var cachedProfiles = MarketDataCacheStore.shared.getSessionProfiles(symbol: clean) ?? []
        
        // Step 2: If local cache is empty, query Supabase
        if cachedProfiles.isEmpty {
            if let remote = try? await SupabaseService.shared.fetchSessionProfiles(symbol: clean, limit: 30), !remote.isEmpty {
                cachedProfiles = remote
                MarketDataCacheStore.shared.saveSessionProfiles(remote, symbol: clean)
            }
        }
        
        // Step 3: If still empty and recent bars are available, bootstrap profiles from bars
        if cachedProfiles.isEmpty && !recentBars.isEmpty {
            let bootstrapped = bootstrapProfiles(from: recentBars, symbol: clean)
            if !bootstrapped.isEmpty {
                cachedProfiles = bootstrapped
                MarketDataCacheStore.shared.saveSessionProfiles(bootstrapped, symbol: clean)
                
                // Persist to Supabase in background
                Task {
                    try? await SupabaseService.shared.upsertSessionProfiles(bootstrapped)
                }
            }
        }
        
        // Step 4: Update mitigation status against recent bars
        if !recentBars.isEmpty && !cachedProfiles.isEmpty {
            SessionFootprintEngine.updateMitigations(snapshots: &cachedProfiles, subsequentBars: recentBars)
        }
        
        // Step 5: Compute Developing (Live) Profile from current ongoing session
        let (devProfile, devPoc, devType) = computeCurrentDeveloping(from: recentBars, symbol: clean)
        
        // Step 6: Extract previous day High / Low for pure price action reference
        let (pdh, pdl) = extractPreviousDayLevels(from: recentBars)
        
        let levels = SessionFootprintEngine.extractKeyLevels(
            snapshots: cachedProfiles,
            developingPoc: devPoc,
            developingSession: devType,
            previousDayHigh: pdh,
            previousDayLow: pdl
        )
        
        return (levels, cachedProfiles, devProfile)
    }

    // MARK: - 2. Scan Candlestick Patterns Confluent with Key Levels
    public func scanConfluentPatterns(
        bars: [MarketBar],
        keyLevels: [KeyLevel],
        atr: Decimal? = nil
    ) -> [DetectedCandlePattern] {
        CandlePatternEngine.scanPatternsWithKeyLevelConfluence(
            bars: bars,
            keyLevels: keyLevels,
            atr: atr,
            lookbackBars: 16
        )
    }

    // MARK: - Private Helpers
    
    private func bootstrapProfiles(from bars: [MarketBar], symbol: String) -> [SessionProfileSnapshot] {
        guard bars.count >= 20 else { return [] }
        var result: [SessionProfileSnapshot] = []
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        
        // Group bars by session day in GMT+7
        let dayGroups = Dictionary(grouping: bars) { bar -> String in
            SessionFootprintEngine.sessionDateString(for: bar.date)
        }
        
        for (dateStr, dayBars) in dayGroups {
            guard let firstDate = dayBars.first?.date else { continue }
            
            // Tokyo Profile
            if let tyo = SessionFootprintEngine.sessionInterval(for: .tokyo, on: firstDate) {
                let tyoBars = dayBars.filter { $0.date >= tyo.start && $0.date <= tyo.end }
                if let snap = SessionFootprintEngine.computeProfile(
                    bars: tyoBars,
                    symbol: symbol,
                    sessionType: .tokyo,
                    sessionDate: dateStr,
                    startTime: tyo.start,
                    endTime: tyo.end
                ) {
                    result.append(snap)
                }
            }
            
            // London Profile
            if let ldn = SessionFootprintEngine.sessionInterval(for: .london, on: firstDate) {
                let ldnBars = dayBars.filter { $0.date >= ldn.start && $0.date <= ldn.end }
                if let snap = SessionFootprintEngine.computeProfile(
                    bars: ldnBars,
                    symbol: symbol,
                    sessionType: .london,
                    sessionDate: dateStr,
                    startTime: ldn.start,
                    endTime: ldn.end
                ) {
                    result.append(snap)
                }
            }
            
            // Daily Profile
            if let d1 = SessionFootprintEngine.sessionInterval(for: .daily, on: firstDate) {
                if let snap = SessionFootprintEngine.computeProfile(
                    bars: dayBars,
                    symbol: symbol,
                    sessionType: .daily,
                    sessionDate: dateStr,
                    startTime: d1.start,
                    endTime: d1.end
                ) {
                    result.append(snap)
                }
            }
        }
        
        return result.sorted(by: { $0.endTime < $1.endTime })
    }

    private func computeCurrentDeveloping(
        from bars: [MarketBar],
        symbol: String
    ) -> (profile: DevelopingProfile?, poc: Decimal?, session: FootprintSessionType?) {
        guard let lastBar = bars.last else { return (nil, nil, nil) }
        let now = lastBar.date
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        
        // Determine which session is currently open in GMT+7
        let hour = cal.component(.hour, from: now)
        let activeSession: FootprintSessionType? = {
            if hour >= 7 && hour < 16 {
                return .tokyo
            } else if hour >= 14 && hour < 23 {
                return .london
            } else if hour >= 19 || hour < 4 {
                return .newYork
            } else {
                return .daily
            }
        }()
        
        guard let sess = activeSession,
              let interval = SessionFootprintEngine.sessionInterval(for: sess, on: now) else {
            return (nil, nil, nil)
        }
        
        let sessionBars = bars.filter { $0.date >= interval.start && $0.date <= now }
        guard !sessionBars.isEmpty,
              let snap = SessionFootprintEngine.computeProfile(
                bars: sessionBars,
                symbol: symbol,
                sessionType: sess,
                sessionDate: SessionFootprintEngine.sessionDateString(for: now),
                startTime: interval.start,
                endTime: interval.end
              ) else {
            return (nil, nil, sess)
        }
        
        let dev = DevelopingProfile(
            sessionType: sess,
            startTime: interval.start,
            currentPoc: snap.pocPrice,
            currentVah: snap.vahPrice,
            currentVal: snap.valPrice,
            profileHigh: snap.profileHigh,
            profileLow: snap.profileLow,
            totalVolume: snap.totalVolume
        )
        
        return (dev, snap.pocPrice, sess)
    }

    private func extractPreviousDayLevels(from bars: [MarketBar]) -> (pdh: Decimal?, pdl: Decimal?) {
        guard bars.count >= 24 else { return (nil, nil) }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        
        let todayStr = SessionFootprintEngine.sessionDateString(for: Date())
        let yesterdayBars = bars.filter {
            SessionFootprintEngine.sessionDateString(for: $0.date) != todayStr
        }
        
        guard !yesterdayBars.isEmpty else { return (nil, nil) }
        let high = yesterdayBars.suffix(96).map(\.high).max()
        let low = yesterdayBars.suffix(96).map(\.low).min()
        return (high, low)
    }
}
