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
    public let emaPeriod: Int
    public let eventType: MarketAlertEventType
    public let barTimestamp: Int64
    public let barClose: Decimal
    public let barLow: Decimal
    public let barHigh: Decimal
    public let emaValue: Decimal
    public let message: String
    public let triggeredAt: Date
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        timeframe: String,
        emaPeriod: Int,
        eventType: MarketAlertEventType,
        barTimestamp: Int64,
        barClose: Decimal,
        barLow: Decimal,
        barHigh: Decimal,
        emaValue: Decimal,
        message: String,
        triggeredAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.timeframe = timeframe
        self.emaPeriod = emaPeriod
        self.eventType = eventType
        self.barTimestamp = barTimestamp
        self.barClose = barClose
        self.barLow = barLow
        self.barHigh = barHigh
        self.emaValue = emaValue
        self.message = message
        self.triggeredAt = triggeredAt
    }
}

// MARK: - Market Alert Engine (EMA 21/50 Candle Close Precision Service)
/// Background candle-close evaluation engine.
/// Evaluates price touches/rejections against EMA 21 and EMA 50 exactly at bar close boundaries
/// (:01 seconds after bar close), eliminating 24/7 continuous tick streaming and conserving quota.
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
    
    @Published public var enabledEMAPeriods: [Int] = [21, 50]
    
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
        
        let savedSymbols = UserDefaults.standard.stringArray(forKey: "market_alert_symbols")
        self.monitoredSymbols = (savedSymbols != nil && !savedSymbols!.isEmpty) ? savedSymbols! : ["XAUUSD", "EURUSD", "BTCUSD", "US30"]
        
        let savedTfs = UserDefaults.standard.stringArray(forKey: "market_alert_timeframes")
        self.monitoredTimeframes = (savedTfs != nil && !savedTfs!.isEmpty) ? savedTfs! : ["15m", "1h"]
        
        if isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - 1. Monitoring Lifecycle
    
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        
        guard schedulerTask == nil else { return }
        isMonitoring = true
        
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                let nextWakeDate = self.calculateNextNearestCandleClose()
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
    
    // MARK: - 3. Pure Candle Evaluation Engine
    
    /// Pure, causal evaluation of candles against EMA 21 and EMA 50.
    /// Determines whether the last closed candle touched, bounced, or crossed the moving average.
    public func evaluateCandles(
        symbol: String,
        timeframe: String,
        bars: [MarketBar],
        referenceDate: Date = Date()
    ) -> [MarketAlertRecord] {
        guard bars.count >= 52 else { return [] }
        
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
        
        var generatedRecords: [MarketAlertRecord] = []
        
        for period in enabledEMAPeriods {
            let emaSeries = MovingAverageEngine.calculateEMA(period: period, bars: bars)
            guard emaSeries.count > closedIndex else { continue }
            
            let curEMA = emaSeries[closedIndex]
            let prevEMA = emaSeries[closedIndex - 1]
            
            // Check touch condition: candle wick or body spans across EMA
            let touched = (targetBar.low <= curEMA && curEMA <= targetBar.high)
            
            if touched {
                // Determine specific reaction
                let eventType: MarketAlertEventType
                if targetBar.close > curEMA && targetBar.low <= curEMA {
                    eventType = .bounceBullish
                } else if targetBar.close < curEMA && targetBar.high >= curEMA {
                    eventType = .bounceBearish
                } else if prevBar.close <= prevEMA && targetBar.close > curEMA {
                    eventType = .crossAbove
                } else if prevBar.close >= prevEMA && targetBar.close < curEMA {
                    eventType = .crossBelow
                } else {
                    eventType = .touch
                }
                
                let signature = "\(symbol)_\(timeframe)_\(targetBar.timestamp)_ema\(period)_\(eventType.rawValue)"
                
                lock.lock()
                let alreadyFired = firedAlertSignatures.contains(signature)
                if !alreadyFired {
                    firedAlertSignatures.insert(signature)
                }
                lock.unlock()
                
                if !alreadyFired {
                    let formattedEma = Formatters.price(curEMA, symbol: symbol)
                    let formattedClose = Formatters.price(targetBar.close, symbol: symbol)
                    let formattedLow = Formatters.price(targetBar.low, symbol: symbol)
                    let formattedHigh = Formatters.price(targetBar.high, symbol: symbol)
                    
                    let msg = "Price reached EMA \(period) (\(formattedEma)). Closed at \(formattedClose) (Range: \(formattedLow) - \(formattedHigh))."
                    
                    let record = MarketAlertRecord(
                        symbol: symbol,
                        timeframe: timeframe,
                        emaPeriod: period,
                        eventType: eventType,
                        barTimestamp: targetBar.timestamp,
                        barClose: targetBar.close,
                        barLow: targetBar.low,
                        barHigh: targetBar.high,
                        emaValue: curEMA,
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
                    // Leverages Unified Candle Hub with sub-slice cache reuse & coalescing
                    let (_, bars) = try await MarketDataService.shared.fetchBarsForSymbol(
                        symbol: symbol,
                        config: config,
                        resolution: tf,
                        count: 60,
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
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "[Trade Alert] \(record.symbol) (\(record.timeframe.uppercased()))"
        content.subtitle = "Price \(record.eventType.label) EMA \(record.emaPeriod)"
        content.body = record.message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "market_alert_\(record.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let err = error {
                AppLogger.warning("Failed to dispatch alert notification: \(err.localizedDescription)")
            }
        }
        #endif
    }
    
    public func requestNotificationPermission() async -> Bool {
        #if canImport(UserNotifications)
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
    
    public func clearActiveAlerts() {
        lock.lock()
        firedAlertSignatures.removeAll()
        lock.unlock()
        
        activeAlerts.removeAll()
    }
}
