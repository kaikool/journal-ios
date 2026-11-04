import Foundation

// MARK: - Session Footprint & Volume Profile Engine
/// Mathematical engine for calculating session-sliced Footprint Volume Profiles,
/// Point of Control (POC), 70% Value Area (VAH / VAL), and Naked POC mitigation tracking.
/// Configured strictly to GMT+7 (Bangkok/Hanoi/Jakarta) aligned with Asian, European, and US market sessions.
public enum SessionFootprintEngine {
    
    // Timezone GMT+7 for institutional session alignment
    public static let sessionTimeZone: TimeZone = TimeZone(identifier: "Asia/Bangkok") ?? TimeZone(secondsFromGMT: 7 * 3600) ?? .current

    // MARK: - 1. Tick Row Size Calculation
    public static func defaultRowSize(for symbol: String) -> Decimal {
        let clean = symbol.uppercased()
        if clean.contains("XAU") || clean.contains("GOLD") {
            return Decimal(1.0) // 100 ticks of 0.01 = $1.00 per bin
        } else if clean.contains("XAG") || clean.contains("SILVER") {
            return Decimal(string: "0.05") ?? Decimal(0.05)
        } else if clean.contains("JPY") {
            return Decimal(string: "0.05") ?? Decimal(0.05) // 50 ticks of 0.001 = 0.05
        } else if clean.contains("US30") || clean.contains("DJ30") || clean.contains("DE30") || clean.contains("GER40") {
            return Decimal(10.0)
        } else if clean.contains("NAS100") || clean.contains("USTEC") || clean.contains("SPX500") {
            return Decimal(5.0)
        } else if clean.contains("BTC") {
            return Decimal(50.0)
        } else {
            // Standard 5-digit Forex (EUR/USD, GBP/USD)
            return Decimal(string: "0.0005") ?? Decimal(0.0005) // 50 ticks of 0.00001 = 5 pips
        }
    }

    // MARK: - 2. Session Time Intervals in GMT+7
    /// Tokyo (Asia): 07:00 - 16:00 GMT+7
    /// London (Europe): 14:00 - 23:00 GMT+7
    /// New York (US): 19:00 - 04:00 GMT+7 (next day)
    public static func sessionInterval(
        for session: FootprintSessionType,
        on date: Date
    ) -> (start: Date, end: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = sessionTimeZone
        
        let startOfDay = cal.startOfDay(for: date)
        
        switch session {
        case .tokyo:
            guard let s = cal.date(byAdding: .hour, value: 7, to: startOfDay),
                  let e = cal.date(byAdding: .hour, value: 16, to: startOfDay) else { return nil }
            return (s, e)
            
        case .london:
            guard let s = cal.date(byAdding: .hour, value: 14, to: startOfDay),
                  let e = cal.date(byAdding: .hour, value: 23, to: startOfDay) else { return nil }
            return (s, e)
            
        case .newYork:
            guard let s = cal.date(byAdding: .hour, value: 19, to: startOfDay),
                  let nextDay = cal.date(byAdding: .day, value: 1, to: startOfDay),
                  let e = cal.date(byAdding: .hour, value: 4, to: nextDay) else { return nil }
            return (s, e)
            
        case .daily:
            guard let e = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
            return (startOfDay, e)
            
        case .weekly:
            let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            guard let startOfWeek = cal.date(from: comp),
                  let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfWeek) else { return nil }
            return (startOfWeek, endOfWeek)
            
        case .monthly:
            let comp = cal.dateComponents([.year, .month], from: date)
            guard let startOfMonth = cal.date(from: comp),
                  let endOfMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth) else { return nil }
            return (startOfMonth, endOfMonth)
        }
    }

    public static func sessionDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = sessionTimeZone
        return formatter.string(from: date)
    }

    // MARK: - 3. Volume Binning & Profile Calculation
    /// Accumulates tick volume into discrete price bins of size `rowSize`
    /// and extracts POC, VAH, and VAL at 70% value area threshold.
    public static func computeProfile(
        bars: [MarketBar],
        symbol: String,
        sessionType: FootprintSessionType,
        sessionDate: String,
        startTime: Date,
        endTime: Date,
        rowSize: Decimal? = nil
    ) -> SessionProfileSnapshot? {
        guard !bars.isEmpty else { return nil }
        
        let step = rowSize ?? defaultRowSize(for: symbol)
        let stepDouble = NSDecimalNumber(decimal: step).doubleValue
        guard stepDouble > 0 else { return nil }
        
        var binsMap: [Int: Decimal] = [:]
        var totalVolume: Decimal = .zero
        var minBarLow: Decimal = bars[0].low
        var maxBarHigh: Decimal = bars[0].high
        
        for bar in bars {
            minBarLow = min(minBarLow, bar.low)
            maxBarHigh = max(maxBarHigh, bar.high)
            totalVolume += bar.volume
            
            let lowD = NSDecimalNumber(decimal: bar.low).doubleValue
            let highD = NSDecimalNumber(decimal: bar.high).doubleValue
            
            let startKey = Int(floor(lowD / stepDouble))
            let endKey = max(startKey, Int(floor(highD / stepDouble)))
            let spanCount = endKey - startKey + 1
            
            let volPerBin = bar.volume / Decimal(max(1, spanCount))
            for k in startKey...endKey {
                binsMap[k, default: .zero] += volPerBin
            }
        }
        
        guard !binsMap.isEmpty, totalVolume > .zero else { return nil }
        
        let sortedKeys = binsMap.keys.sorted()
        guard let minKey = sortedKeys.first, let maxKey = sortedKeys.last else { return nil }
        let profileMidKey = Double(minKey + maxKey) / 2.0
        
        // Find Point of Control (POC) with maximum volume
        var maxV: Decimal = .zero
        var pocKey: Int = minKey
        var bestDist: Double = Double.greatestFiniteMagnitude
        
        for k in sortedKeys {
            let v = binsMap[k] ?? .zero
            if v > maxV {
                maxV = v
                pocKey = k
                bestDist = abs(Double(k) - profileMidKey)
            } else if v == maxV && v > .zero {
                let candidateDist = abs(Double(k) - profileMidKey)
                if candidateDist < bestDist || (candidateDist == bestDist && k > pocKey) {
                    pocKey = k
                    bestDist = candidateDist
                }
            }
        }
        
        // Value Area Expansion (70% Target)
        guard let pocIndex = sortedKeys.firstIndex(of: pocKey) else { return nil }
        let targetVolume = totalVolume * Decimal(0.70)
        var accumulatedVolume: Decimal = binsMap[pocKey] ?? .zero
        
        var valKey = pocKey
        var vahKey = pocKey
        var belowIdx = pocIndex - 1
        var aboveIdx = pocIndex + 1
        let n = sortedKeys.count
        
        while accumulatedVolume < targetVolume {
            let hasBelow = belowIdx >= 0
            let hasAbove = aboveIdx < n
            if !hasBelow && !hasAbove { break }
            
            let belowKey = hasBelow ? sortedKeys[belowIdx] : nil
            let aboveKey = hasAbove ? sortedKeys[aboveIdx] : nil
            let belowV = belowKey != nil ? (binsMap[belowKey!] ?? .zero) : Decimal(-1)
            let aboveV = aboveKey != nil ? (binsMap[aboveKey!] ?? .zero) : Decimal(-1)
            
            let chooseAbove: Bool
            if hasAbove && !hasBelow {
                chooseAbove = true
            } else if hasBelow && !hasAbove {
                chooseAbove = false
            } else if aboveV > belowV {
                chooseAbove = true
            } else if belowV > aboveV {
                chooseAbove = false
            } else {
                let aboveDist = abs((aboveKey ?? pocKey) - pocKey)
                let belowDist = abs(pocKey - (belowKey ?? pocKey))
                chooseAbove = aboveDist <= belowDist
            }
            
            let chosenIdx = chooseAbove ? aboveIdx : belowIdx
            guard chosenIdx >= 0 && chosenIdx < n else { break }
            let chosenKey = sortedKeys[chosenIdx]
            let chosenV = binsMap[chosenKey] ?? .zero
            
            accumulatedVolume += max(chosenV, .zero)
            if chooseAbove {
                vahKey = chosenKey
                aboveIdx += 1
            } else {
                valKey = chosenKey
                belowIdx -= 1
            }
        }
        
        let pocPrice = Decimal(pocKey) * step + (step / Decimal(2))
        let valPrice = Decimal(valKey) * step
        let vahPrice = Decimal(vahKey) * step + step
        let profileHigh = Decimal(maxKey) * step + step
        let profileLow = Decimal(minKey) * step
        
        return SessionProfileSnapshot(
            symbol: symbol,
            sessionType: sessionType,
            sessionDate: sessionDate,
            startTime: startTime,
            endTime: endTime,
            pocPrice: pocPrice,
            vahPrice: vahPrice,
            valPrice: valPrice,
            profileHigh: profileHigh,
            profileLow: profileLow,
            totalVolume: totalVolume,
            isNaked: true,
            mitigatedAt: nil
        )
    }

    // MARK: - 4. Naked POC Mitigation Tracking
    /// Checks past unmitigated snapshots against subsequent price action bars.
    /// If any subsequent bar's range [low, high] spans the snapshot POC, it is marked mitigated.
    public static func updateMitigations(
        snapshots: inout [SessionProfileSnapshot],
        subsequentBars: [MarketBar]
    ) {
        guard !snapshots.isEmpty && !subsequentBars.isEmpty else { return }
        
        for i in snapshots.indices {
            guard snapshots[i].isNaked else { continue }
            let snapPoc = snapshots[i].pocPrice
            let snapEndTimeMs = Int64(snapshots[i].endTime.timeIntervalSince1970 * 1000.0)
            
            for bar in subsequentBars where bar.timestamp >= snapEndTimeMs {
                if bar.high >= snapPoc && bar.low <= snapPoc {
                    snapshots[i].isNaked = false
                    snapshots[i].mitigatedAt = bar.date
                    break
                }
            }
        }
    }

    // MARK: - 5. Value Migration / Order Flow Direction
    /// Assesses whether value areas are shifting upward (Bullish), downward (Bearish), or compressing.
    public static func evaluateValueMigration(
        currentPoc: Decimal?,
        previousPoc: Decimal?,
        currentClose: Decimal?
    ) -> String {
        guard let curPoc = currentPoc, let prevPoc = previousPoc else { return "NEUTRAL" }
        if curPoc > prevPoc {
            if let close = currentClose, close > curPoc {
                return "BULLISH EXPANSION"
            }
            return "BULLISH BIAS"
        } else if curPoc < prevPoc {
            if let close = currentClose, close < curPoc {
                return "BEARISH EXPANSION"
            }
            return "BEARISH BIAS"
        } else {
            return "CONSOLIDATION / BALANCED"
        }
    }

    // MARK: - 6. Extract Unified Key Levels
    /// Produces a clean, sorted collection of KeyLevel items for UI rendering and AI prompt injection.
    public static func extractKeyLevels(
        snapshots: [SessionProfileSnapshot],
        developingPoc: Decimal? = nil,
        developingSession: FootprintSessionType? = nil,
        previousDayHigh: Decimal? = nil,
        previousDayLow: Decimal? = nil
    ) -> [KeyLevel] {
        var levels: [KeyLevel] = []
        
        // 1. Previous Day High & Low
        if let pdh = previousDayHigh, pdh > .zero {
            levels.append(KeyLevel(type: .pdh, price: pdh, label: "PDH"))
        }
        if let pdl = previousDayLow, pdl > .zero {
            levels.append(KeyLevel(type: .pdl, price: pdl, label: "PDL"))
        }
        
        // 2. Developing Live POC
        if let devPoc = developingPoc, let devSess = developingSession {
            levels.append(KeyLevel(
                type: .sessionPoc(devSess),
                price: devPoc,
                label: "Live \(devSess.shortCode) POC"
            ))
        }
        
        // 3. Completed Session Profiles (Recent POCs & Naked POCs)
        var ageMap: [FootprintSessionType: Int] = [:]
        for snap in snapshots.sorted(by: { $0.endTime > $1.endTime }) {
            let age = ageMap[snap.sessionType, default: 0] + 1
            ageMap[snap.sessionType] = age
            
            if snap.isNaked {
                levels.append(KeyLevel(
                    type: .nakedPoc(snap.sessionType, age: age),
                    price: snap.pocPrice,
                    label: "NPOC [\(snap.sessionType.shortCode)-\(age)]",
                    isNaked: true
                ))
            } else if age <= 2 {
                // Include recent tested POCs for immediate retest awareness
                levels.append(KeyLevel(
                    type: .sessionPoc(snap.sessionType),
                    price: snap.pocPrice,
                    label: "\(snap.sessionType.shortCode) POC"
                ))
            }
        }
        
        return levels
    }
}
