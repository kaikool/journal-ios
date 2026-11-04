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
    ) async -> (levels: [KeyLevel], profiles: [SessionProfileSnapshot], developing: DevelopingProfile?, developingProfiles: [DevelopingProfile]) {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return ([], [], nil, []) }

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
        let (devProfile, devPoc, devType, devList) = computeCurrentDeveloping(from: recentBars, symbol: clean)

        // Step 6: Extract previous day High / Low for pure price action reference
        let (pdh, pdl) = extractPreviousDayLevels(from: recentBars)

        let levels = SessionFootprintEngine.extractKeyLevels(
            snapshots: cachedProfiles,
            developingPoc: devPoc,
            developingSession: devType,
            previousDayHigh: pdh,
            previousDayLow: pdl
        )

        return (levels, cachedProfiles, devProfile, devList)
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

    // MARK: - Synchronous Footprint Computation Helpers

    public static func bootstrapProfiles(from bars: [MarketBar], symbol: String) -> [SessionProfileSnapshot] {
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

            // New York Profile
            if let ny = SessionFootprintEngine.sessionInterval(for: .newYork, on: firstDate) {
                let nyBars = dayBars.filter { $0.date >= ny.start && $0.date <= ny.end }
                if !nyBars.isEmpty, let snap = SessionFootprintEngine.computeProfile(
                    bars: nyBars,
                    symbol: symbol,
                    sessionType: .newYork,
                    sessionDate: dateStr,
                    startTime: ny.start,
                    endTime: ny.end
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

        // Group bars by Weekly Profile in GMT+7
        let weekGroups = Dictionary(grouping: bars) { bar -> String in
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: bar.date)
            return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
        }
        for (_, wBars) in weekGroups {
            guard let firstDate = wBars.first?.date,
                  let wInterval = SessionFootprintEngine.sessionInterval(for: .weekly, on: firstDate) else { continue }
            let weekDateStr = SessionFootprintEngine.sessionDateString(for: wInterval.start)
            if let snap = SessionFootprintEngine.computeProfile(
                bars: wBars,
                symbol: symbol,
                sessionType: .weekly,
                sessionDate: weekDateStr,
                startTime: wInterval.start,
                endTime: wInterval.end
            ) {
                result.append(snap)
            }
        }

        // Group bars by Monthly Profile in GMT+7
        let monthGroups = Dictionary(grouping: bars) { bar -> String in
            let c = cal.dateComponents([.year, .month], from: bar.date)
            return "\(c.year ?? 0)-M\(c.month ?? 0)"
        }
        for (_, mBars) in monthGroups {
            guard let firstDate = mBars.first?.date,
                  let mInterval = SessionFootprintEngine.sessionInterval(for: .monthly, on: firstDate) else { continue }
            let monthDateStr = SessionFootprintEngine.sessionDateString(for: mInterval.start)
            if let snap = SessionFootprintEngine.computeProfile(
                bars: mBars,
                symbol: symbol,
                sessionType: .monthly,
                sessionDate: monthDateStr,
                startTime: mInterval.start,
                endTime: mInterval.end
            ) {
                result.append(snap)
            }
        }

        return result.sorted(by: { $0.endTime < $1.endTime })
    }

    public static func computeCurrentDeveloping(
        from bars: [MarketBar],
        symbol: String
    ) -> (profile: DevelopingProfile?, poc: Decimal?, session: FootprintSessionType?, list: [DevelopingProfile]) {
        guard let lastBar = bars.last else { return (nil, nil, nil, []) }
        let now = lastBar.date

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone

        var list: [DevelopingProfile] = []

        // 1. Developing Weekly (Monday 00:00 to now)
        if let wInterval = SessionFootprintEngine.sessionInterval(for: .weekly, on: now) {
            let wBars = bars.filter { $0.date >= wInterval.start && $0.date <= now }
            if !wBars.isEmpty, let snap = SessionFootprintEngine.computeProfile(
                bars: wBars,
                symbol: symbol,
                sessionType: .weekly,
                sessionDate: SessionFootprintEngine.sessionDateString(for: wInterval.start),
                startTime: wInterval.start,
                endTime: wInterval.end
            ) {
                list.append(DevelopingProfile(
                    sessionType: .weekly,
                    startTime: wInterval.start,
                    currentPoc: snap.pocPrice,
                    currentVah: snap.vahPrice,
                    currentVal: snap.valPrice,
                    profileHigh: snap.profileHigh,
                    profileLow: snap.profileLow,
                    totalVolume: snap.totalVolume
                ))
            }
        }

        // 2. Developing Daily (Today 00:00 to now)
        if let dInterval = SessionFootprintEngine.sessionInterval(for: .daily, on: now) {
            let dBars = bars.filter { $0.date >= dInterval.start && $0.date <= now }
            if !dBars.isEmpty, let snap = SessionFootprintEngine.computeProfile(
                bars: dBars,
                symbol: symbol,
                sessionType: .daily,
                sessionDate: SessionFootprintEngine.sessionDateString(for: dInterval.start),
                startTime: dInterval.start,
                endTime: dInterval.end
            ) {
                list.append(DevelopingProfile(
                    sessionType: .daily,
                    startTime: dInterval.start,
                    currentPoc: snap.pocPrice,
                    currentVah: snap.vahPrice,
                    currentVal: snap.valPrice,
                    profileHigh: snap.profileHigh,
                    profileLow: snap.profileLow,
                    totalVolume: snap.totalVolume
                ))
            }
        }

        // 3. Developing Session (Tokyo / London / NY)
        let hour = cal.component(.hour, from: now)
        let activeSession: FootprintSessionType? = {
            if hour >= 7 && hour < 16 {
                return .tokyo
            } else if hour >= 14 && hour < 23 {
                return .london
            } else if hour >= 19 || hour < 4 {
                return .newYork
            } else {
                return nil
            }
        }()

        if let sess = activeSession,
           let interval = SessionFootprintEngine.sessionInterval(for: sess, on: now) {
            let sessionBars = bars.filter { $0.date >= interval.start && $0.date <= now }
            if !sessionBars.isEmpty, let snap = SessionFootprintEngine.computeProfile(
                bars: sessionBars,
                symbol: symbol,
                sessionType: sess,
                sessionDate: SessionFootprintEngine.sessionDateString(for: now),
                startTime: interval.start,
                endTime: interval.end
            ) {
                list.append(DevelopingProfile(
                    sessionType: sess,
                    startTime: interval.start,
                    currentPoc: snap.pocPrice,
                    currentVah: snap.vahPrice,
                    currentVal: snap.valPrice,
                    profileHigh: snap.profileHigh,
                    profileLow: snap.profileLow,
                    totalVolume: snap.totalVolume
                ))
            }
        }

        let primaryDev = list.first(where: { $0.sessionType == activeSession }) ?? list.first(where: { $0.sessionType == .daily }) ?? list.first
        return (primaryDev, primaryDev?.currentPoc, primaryDev?.sessionType, list)
    }

    public static func extractPreviousDayLevels(from bars: [MarketBar]) -> (pdh: Decimal?, pdl: Decimal?) {
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
