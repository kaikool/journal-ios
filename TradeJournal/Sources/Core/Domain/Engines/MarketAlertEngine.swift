import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Market Alert Event Type
public enum MarketAlertEventType: String, Codable, Equatable, Sendable {
    case touch = "TOUCH"
    case bounceBullish = "BOUNCE_BULLISH"
    case bounceBearish = "BOUNCE_BEARISH"
    case crossAbove = "CROSS_ABOVE"
    case crossBelow = "CROSS_BELOW"
    
    public var label: String {
        switch self {
        case .touch: return "Touch"
        case .bounceBullish: return "Bullish Bounce"
        case .bounceBearish: return "Bearish Bounce"
        case .crossAbove: return "Cross Above"
        case .crossBelow: return "Cross Below"
        }
    }
}

// MARK: - Market Alert Record
public struct MarketAlertRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let timeframe: String
    public let levelName: String
    public let eventType: MarketAlertEventType
    public let barTimestamp: Int64
    public let barClose: Decimal
    public let barLow: Decimal
    public let barHigh: Decimal
    public let levelValue: Decimal
    public let message: String
    public let triggeredAt: Date
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        timeframe: String,
        levelName: String,
        eventType: MarketAlertEventType,
        barTimestamp: Int64,
        barClose: Decimal,
        barLow: Decimal,
        barHigh: Decimal,
        levelValue: Decimal,
        message: String,
        triggeredAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.timeframe = timeframe
        self.levelName = levelName
        self.eventType = eventType
        self.barTimestamp = barTimestamp
        self.barClose = barClose
        self.barLow = barLow
        self.barHigh = barHigh
        self.levelValue = levelValue
        self.message = message
        self.triggeredAt = triggeredAt
    }
}

// MARK: - Market Alert Engine (Key Level & Market Structure Precision Service)
/// Background candle-close evaluation engine.
/// Evaluates price touches/rejections and structural breakouts against Key Structural Levels
/// (Swing High, Swing Low, PDH, PDL) exactly at bar close boundaries (:01 seconds after bar close),
/// eliminating 24/7 continuous tick streaming and conserving quota.
public final class MarketAlertEngine: ObservableObject, @unchecked Sendable {
    public static let shared = MarketAlertEngine()
    
    private let lock = NSLock()
    private var schedulerTask: Task<Void, Never>?
    private var firedAlertSignatures: Set<String> = []
    
    @Published public private(set) var activeAlerts: [MarketAlertRecord] = []
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var lastEvaluatedAt: Date?
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "market_alert_enabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    @Published public var monitoredSymbols: [String] {
        didSet {
            UserDefaults.standard.set(monitoredSymbols, forKey: "market_alert_symbols")
        }
    }
    
    @Published public var monitoredTimeframes: [String] {
        didSet {
            UserDefaults.standard.set(monitoredTimeframes, forKey: "market_alert_timeframes")
        }
    }
    
    public func toggleSymbol(_ symbol: String) {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        if let idx = monitoredSymbols.firstIndex(of: clean) {
            if monitoredSymbols.count > 1 {
                monitoredSymbols.remove(at: idx)
            }
        } else {
            monitoredSymbols.append(clean)
        }
    }
    
    public func isSymbolMonitored(_ symbol: String) -> Bool {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return monitoredSymbols.contains(clean)
    }
    
    public func toggleTimeframe(_ tf: String) {
        let clean = tf.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }
        if let idx = monitoredTimeframes.firstIndex(of: clean) {
            if monitoredTimeframes.count > 1 {
                monitoredTimeframes.remove(at: idx)
            }
        } else {
            monitoredTimeframes.append(clean)
        }
    }
    
    public func isTimeframeMonitored(_ tf: String) -> Bool {
        let clean = tf.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return monitoredTimeframes.contains(clean)
    }
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "market_alert_enabled")
        
        let savedSymbols = UserDefaults.standard.stringArray(forKey: "market_alert_symbols") ?? ["XAUUSD", "EURUSD", "BTCUSD"]
        self.monitoredSymbols = savedSymbols
        
        let savedTfs = UserDefaults.standard.stringArray(forKey: "market_alert_timeframes") ?? ["15m", "1h"]
        self.monitoredTimeframes = savedTfs
        
        if self.isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - 1. Dynamic Scheduling Loop
    
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        
        guard schedulerTask == nil else { return }
        isMonitoring = true
        
        schedulerTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                let nextWakeDate = self.calculateNextNearestCandleClose(referenceDate: Date())
                let waitDuration = max(2.0, nextWakeDate.timeIntervalSince(Date()) + 1.5)
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(waitDuration * 1_000_000_000))
                } catch {
                    break // Task cancelled
                }
                
                if Task.isCancelled { break }
                _ = await self.evaluateAllMonitoredSymbols()
            }
            
            await MainActor.run { [weak self] in
                self?.isMonitoring = false
            }
        }
    }
    
    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        
        schedulerTask?.cancel()
        schedulerTask = nil
        isMonitoring = false
    }
    
    // MARK: - 2. Candle Close Timing Calculation
    
    public func calculateNextNearestCandleClose(referenceDate: Date = Date()) -> Date {
        let tfs = monitoredTimeframes.isEmpty ? ["15m"] : monitoredTimeframes
        var nextDates: [Date] = []
        
        for tf in tfs {
            nextDates.append(Self.nextCandleCloseDate(for: tf, referenceDate: referenceDate))
        }
        
        return nextDates.min() ?? referenceDate.addingTimeInterval(900)
    }
    
    public static func nextCandleCloseDate(for resolution: String, referenceDate: Date = Date()) -> Date {
        let clean = resolution.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let granSec: Double
        switch clean {
        case "1m", "m1": granSec = 60
        case "5m", "m5": granSec = 300
        case "15m", "m15": granSec = 900
        case "30m", "m30": granSec = 1800
        case "1h", "h1": granSec = 3600
        case "4h", "h4": granSec = 14400
        case "1d", "d", "daily", "d1": granSec = 86400
        default: granSec = 900
        }
        
        let epochSec = referenceDate.timeIntervalSince1970
        let elapsed = epochSec.truncatingRemainder(dividingBy: granSec)
        let remaining = granSec - elapsed
        return referenceDate.addingTimeInterval(remaining)
    }
    
    // MARK: - 3. Pure Candle Evaluation Against Key Structural Levels
    
    /// Pure, causal evaluation of candles against Key Price Action Levels (Swing Highs, Swing Lows).
    public func evaluateCandles(
        symbol: String,
        timeframe: String,
        bars: [MarketBar],
        referenceDate: Date = Date()
    ) -> [MarketAlertRecord] {
        guard bars.count >= 15 else { return [] }
        
        let durationMs = MarketResolution(rawValue: timeframe)?.durationMs ?? 900_000
        let nowMs = Int64(referenceDate.timeIntervalSince1970 * 1000)
        
        // Locate the latest closed candle
        var closedIndex = bars.count - 1
        if closedIndex >= 0 {
            let lastBar = bars[closedIndex]
            if (lastBar.timestamp + durationMs) > (nowMs + 5000) && closedIndex > 0 {
                // Last bar is still actively forming; evaluate the preceding sealed bar
                closedIndex -= 1
            }
        }
        
        guard closedIndex >= 1 else { return [] }
        
        let targetBar = bars[closedIndex]
        let prevBar = bars[closedIndex - 1]
        
        // Extract 20-bar lookback high/low levels preceding targetBar
        let lookback = Array(bars.prefix(closedIndex).suffix(20))
        var levelsToTest: [(name: String, price: Decimal)] = []
        if let h = lookback.map(\.high).max() {
            levelsToTest.append(("Range High", h))
        }
        if let l = lookback.map(\.low).min() {
            levelsToTest.append(("Range Low", l))
        }
        
        var generatedRecords: [MarketAlertRecord] = []
        
        for (levelName, levelPrice) in levelsToTest {
            let touched = (targetBar.low <= levelPrice && levelPrice <= targetBar.high)
            
            if touched {
                let eventType: MarketAlertEventType
                if targetBar.close > levelPrice && targetBar.low <= levelPrice {
                    eventType = .bounceBullish
                } else if targetBar.close < levelPrice && targetBar.high >= levelPrice {
                    eventType = .bounceBearish
                } else if prevBar.close <= levelPrice && targetBar.close > levelPrice {
                    eventType = .crossAbove
                } else if prevBar.close >= levelPrice && targetBar.close < levelPrice {
                    eventType = .crossBelow
                } else {
                    eventType = .touch
                }
                
                let signature = "\(symbol)_\(timeframe)_\(targetBar.timestamp)_\(levelName)_\(eventType.rawValue)"
                
                lock.lock()
                let alreadyFired = firedAlertSignatures.contains(signature)
                if !alreadyFired {
                    firedAlertSignatures.insert(signature)
                }
                lock.unlock()
                
                if !alreadyFired {
                    let formattedLevel = Formatters.price(levelPrice, symbol: symbol)
                    let formattedClose = Formatters.price(targetBar.close, symbol: symbol)
                    let formattedLow = Formatters.price(targetBar.low, symbol: symbol)
                    let formattedHigh = Formatters.price(targetBar.high, symbol: symbol)
                    
                    let msg = "Price reached \(levelName) (\(formattedLevel)). Closed at \(formattedClose) (Range: \(formattedLow) - \(formattedHigh))."
                    
                    let record = MarketAlertRecord(
                        symbol: symbol,
                        timeframe: timeframe,
                        levelName: levelName,
                        eventType: eventType,
                        barTimestamp: targetBar.timestamp,
                        barClose: targetBar.close,
                        barLow: targetBar.low,
                        barHigh: targetBar.high,
                        levelValue: levelPrice,
                        message: msg,
                        triggeredAt: referenceDate
                    )
                    generatedRecords.append(record)
                }
            }
        }
        
        return generatedRecords
    }
    
    // MARK: - 4. Batch Evaluation Across All Monitored Symbols
    
    @discardableResult
    public func evaluateAllMonitoredSymbols() async -> [MarketAlertRecord] {
        let symbols = monitoredSymbols
        let timeframes = monitoredTimeframes
        let config = await MainActor.run { TradeDataStore.shared.marketConnections }
        
        var allFired: [MarketAlertRecord] = []
        
        for symbol in symbols {
            for tf in timeframes {
                do {
                    let (_, bars) = try await MarketDataService.shared.fetchBarsForSymbol(
                        symbol: symbol,
                        config: config,
                        resolution: tf,
                        count: 40,
                        forceRefresh: false
                    )
                    
                    let records = evaluateCandles(symbol: symbol, timeframe: tf, bars: bars)
                    for rec in records {
                        dispatchNotification(for: rec)
                        allFired.append(rec)
                    }
                } catch {
                    AppLogger.warning("Alert evaluation failed for \(symbol) \(tf): \(error.localizedDescription)")
                }
            }
        }
        
        let fired = allFired
        await MainActor.run {
            self.lastEvaluatedAt = Date()
            if !fired.isEmpty {
                self.activeAlerts.insert(contentsOf: fired, at: 0)
                if self.activeAlerts.count > 50 {
                    self.activeAlerts = Array(self.activeAlerts.prefix(50))
                }
            }
        }
        
        return allFired
    }
    
    // MARK: - 5. System Notification Dispatcher
    
    public func dispatchNotification(for record: MarketAlertRecord) {
        AppNotificationManager.shared.dispatchNotification(
            id: "market_alert_\(record.id)",
            title: "[Trade Alert] \(record.symbol) (\(record.timeframe.uppercased()))",
            subtitle: "Price \(record.eventType.label) \(record.levelName)",
            body: record.message,
            categoryIdentifier: "MARKET_ALERT",
            userInfo: [
                "symbol": record.symbol,
                "timeframe": record.timeframe,
                "alertId": record.id
            ]
        )
    }
    
    public func requestNotificationPermission() async -> Bool {
        await AppNotificationManager.shared.requestAuthorization()
    }
    
    public func clearActiveAlerts() {
        lock.lock()
        firedAlertSignatures.removeAll()
        lock.unlock()
        
        activeAlerts.removeAll()
    }
}
