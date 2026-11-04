import Foundation
import Combine

/// Standard 27: Unified Alerting & Notification Architecture Coordinator
/// Single source of truth for scheduling, evaluating, and managing all institutional notifications.
/// Strictly enforces: Zero Icons, 100% Institutional Professional English, Centralized Deep Linking.
@MainActor
public final class AppNotificationCoordinator: ObservableObject {
    public static let shared = AppNotificationCoordinator()
    
    // MARK: - Published State
    
    @Published public private(set) var recentNotifications: [NotificationItem] = []
    @Published public private(set) var unreadCount: Int = 0
    
    // MARK: - Internal Storage & Cooldown Tracking
    
    private let kNotificationHistoryKey = "app_notification_history_v1"
    private var lastTiltAlertTime: Date? = nil
    private var lastMarketAlertTimes: [String: Date] = [:]
    private var scheduledEventKeys: Set<String> = []
    
    private init() {
        loadHistory()
    }
    
    // MARK: - 1. Pillar 3: Economic News Radar (Forex Factory)
    
    /// Evaluates upcoming high-impact economic news and schedules 15-minute and 5-minute pre-release alerts.
    /// Strictly filters by currencies involved in active open trades or user watchlist.
    public func evaluateNewsRadar(
        events: [ForexFactoryEvent],
        activeTrades: [Trade],
        watchlist: [String],
        timeZone: TimeZone
    ) {
        guard AppSettingsStore.shared.notifyHighImpactNews else { return }
        
        // 1. Resolve currencies from open positions and watchlist
        var monitoredCurrencies = Set<String>()
        if AppSettingsStore.shared.notifyNewsOnlyOpenTrades {
            for t in activeTrades where t.status == .open {
                monitoredCurrencies.formUnion(Self.relatedCurrencies(for: t.symbol))
            }
            if monitoredCurrencies.isEmpty {
                for s in watchlist {
                    monitoredCurrencies.formUnion(Self.relatedCurrencies(for: s))
                }
            }
        } else {
            for t in activeTrades where t.status == .open {
                monitoredCurrencies.formUnion(Self.relatedCurrencies(for: t.symbol))
            }
            for s in watchlist {
                monitoredCurrencies.formUnion(Self.relatedCurrencies(for: s))
            }
        }
        
        if monitoredCurrencies.isEmpty {
            monitoredCurrencies.insert("USD")
        }
        
        let now = Date()
        
        // 2. Filter for high-impact events matching monitored currencies
        let highImpactEvents = events.filter { event in
            guard event.impact == .high else { return false }
            let countryUpper = event.country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard monitoredCurrencies.contains(countryUpper) else { return false }
            guard let eventDate = event.date, eventDate > now else { return false }
            return true
        }
        
        var formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        
        for event in highImpactEvents {
            guard let eventDate = event.date else { continue }
            let country = event.country.uppercased()
            let timeStr = formatter.string(from: eventDate)
            
            // 15-Minute Alert
            if AppSettingsStore.shared.notifyNews15m {
                let alert15Date = eventDate.addingTimeInterval(-15 * 60)
                let key15 = "news_15m_\(event.id)"
                if alert15Date > now && !scheduledEventKeys.contains(key15) {
                    scheduledEventKeys.insert(key15)
                    let title = "[HIGH IMPACT EVENT - \(country)]"
                    let subtitle = "Scheduled at \(timeStr)"
                    let body = "\(event.title) release in 15 minutes (\(timeStr)). Assess open exposure, trailing stop losses, or reduce position sizing."
                    
                    AppNotificationManager.shared.scheduleNotification(
                        id: key15,
                        title: title,
                        subtitle: subtitle,
                        body: body,
                        categoryIdentifier: NotificationCategory.economicNews.rawValue,
                        date: alert15Date,
                        userInfo: ["country": country, "eventTitle": event.title]
                    )
                }
            }
            
            // 5-Minute Alert
            if AppSettingsStore.shared.notifyNews5m {
                let alert5Date = eventDate.addingTimeInterval(-5 * 60)
                let key5 = "news_5m_\(event.id)"
                if alert5Date > now && !scheduledEventKeys.contains(key5) {
                    scheduledEventKeys.insert(key5)
                    let title = "[IMMINENT VOLATILITY - \(country)]"
                    let subtitle = "Scheduled in 5 Minutes"
                    let body = "\(event.title) release in 5 minutes. Expect severe slippage and spread expansion. Protect capital."
                    
                    AppNotificationManager.shared.scheduleNotification(
                        id: key5,
                        title: title,
                        subtitle: subtitle,
                        body: body,
                        categoryIdentifier: NotificationCategory.economicNews.rawValue,
                        date: alert5Date,
                        userInfo: ["country": country, "eventTitle": event.title]
                    )
                }
            }
        }
    }
    
    // MARK: - 2. Pillar 4: Psychology (Tilt & Revenge Trading Detection)
    
    /// Evaluates recently closed trades for 3 consecutive losses within a 60-minute window.
    /// Implements a 60-minute cooldown lock to prevent spamming during tilt episodes.
    public func evaluateTiltAndRevengeTrading(trades: [Trade]) {
        guard AppSettingsStore.shared.notifyDisciplineTilt else { return }
        
        let now = Date()
        if let last = lastTiltAlertTime, now.timeIntervalSince(last) < 3600 {
            return
        }
        
        let closedTrades = trades
            .filter { $0.status.isClosed }
            .sorted { ($0.closedAt ?? $0.openedAt) > ($1.closedAt ?? $1.openedAt) }
        
        guard closedTrades.count >= 3 else { return }
        let recent3 = Array(closedTrades.prefix(3))
        let allLoss = recent3.allSatisfy { $0.status == .loss }
        guard allLoss else { return }
        
        let t1Date = recent3[0].closedAt ?? recent3[0].openedAt
        let t3Date = recent3[2].closedAt ?? recent3[2].openedAt
        let span = abs(t1Date.timeIntervalSince(t3Date))
        
        guard span <= 3600 else { return }
        
        lastTiltAlertTime = now
        let minutes = max(1, Int(span / 60))
        let totalLoss = abs(recent3.reduce(Decimal(0)) { $0 + $1.netPnl })
        let lossFormatted = Formatters.formatCurrency(totalLoss, currency: "USD")
        
        let title = "[DISCIPLINE BREACH WARNING]"
        let subtitle = "3 Consecutive Losses Detected"
        let body = "3 consecutive losses recorded within the last \(minutes) minutes (Net: -\(lossFormatted)). Execution quality is degrading. Mandatory cool-down: step away from the trading desk for 30 minutes."
        
        dispatchNotificationNow(
            id: "tilt_\(Int(now.timeIntervalSince1970))",
            category: .disciplineTilt,
            title: title,
            subtitle: subtitle,
            body: body,
            userInfo: ["type": "tilt_detection"]
        )
    }
    
    // MARK: - 3. Pillar 4: Routines (Pre-Session & Daily Journal Review)
    
    /// Schedules routine reminders for morning preparation, London session, and New York session.
    public func schedulePreSessionRoutines(timeZone: TimeZone) {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        
        // Morning Routine Checklist (08:00)
        if AppSettingsStore.shared.notifyMorningRoutine {
            scheduleDailyRoutine(
                id: "morning_routine_check",
                hour: 8,
                minute: 0,
                title: "[MORNING ROUTINE CHECKLIST]",
                subtitle: "Daily Trading Preparation",
                body: "Review daily economic calendar, account risk limits, and define key technical watchlist zones before session opening.",
                category: .preSessionRoutine,
                cal: cal,
                now: now,
                userInfo: ["type": "morning_routine"]
            )
        }
        
        // London Session Reminder (13:45 VN / 15m before 14:00)
        if AppSettingsStore.shared.notifyPreSessionLondon {
            scheduleDailyRoutine(
                id: "pre_session_london",
                hour: 13,
                minute: 45,
                title: "[LONDON SESSION OPEN]",
                subtitle: "Opening in 15 Minutes",
                body: "London session opens in 15 minutes. Review key footprint POC levels, macroeconomic calendar, and pre-trade rules before placing opening orders.",
                category: .preSessionRoutine,
                cal: cal,
                now: now,
                userInfo: ["type": "pre_session_london"]
            )
        }
        
        // New York Session Reminder (19:15 VN / 15m before 19:30)
        if AppSettingsStore.shared.notifyPreSessionNewYork {
            scheduleDailyRoutine(
                id: "pre_session_newyork",
                hour: 19,
                minute: 15,
                title: "[NEW YORK SESSION OPEN]",
                subtitle: "Opening in 15 Minutes",
                body: "New York session opens in 15 minutes. Review key footprint POC levels, macroeconomic calendar, and pre-trade rules before placing opening orders.",
                category: .preSessionRoutine,
                cal: cal,
                now: now,
                userInfo: ["type": "pre_session_newyork"]
            )
        }
    }
    
    /// Schedules the 22:30 Daily Journal Review reminder ONLY if trades were executed today.
    public func scheduleDailyJournalReview(trades: [Trade], timeZone: TimeZone) {
        guard AppSettingsStore.shared.notifyDailyJournalReview else {
            AppNotificationManager.shared.removeNotification(identifier: "daily_journal_review_today")
            return
        }
        
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        
        let todayTrades = trades.filter { t in
            guard let date = t.closedAt ?? (t.status.isClosed ? t.openedAt : nil) else { return false }
            return cal.isDateInToday(date)
        }
        
        if todayTrades.isEmpty {
            AppNotificationManager.shared.removeNotification(identifier: "daily_journal_review_today")
            return
        }
        
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 22
        comps.minute = 30
        comps.second = 0
        guard let targetDate = cal.date(from: comps), targetDate > now else { return }
        
        let winCount = todayTrades.filter { $0.status == .win }.count
        let winRate = (Double(winCount) / Double(todayTrades.count)) * 100.0
        let netPnl = todayTrades.reduce(Decimal(0)) { $0 + $1.netPnl }
        let netPnlStr = Formatters.formatPnL(netPnl, currency: "USD")
        
        let title = "[END OF DAY JOURNAL REVIEW]"
        let subtitle = "Daily Performance Summary"
        let body = "\(todayTrades.count) closed trades recorded today (Win Rate: \(Formatters.formatPercent(winRate)) • Net: \(netPnlStr)). Complete your post-market journal entry to document execution quality and lessons."
        
        AppNotificationManager.shared.scheduleNotification(
            id: "daily_journal_review_today",
            title: title,
            subtitle: subtitle,
            body: body,
            categoryIdentifier: NotificationCategory.dailyJournalReview.rawValue,
            date: targetDate,
            userInfo: ["type": "daily_journal_review"]
        )
    }
    
    // MARK: - 4. Pillar 5: Market Structure & Footprint POC Alerts
    
    /// Dispatches institutional Footprint POC reactions with 15-minute level debouncing.
    public func dispatchMarketStructureAlert(
        symbol: String,
        levelName: String,
        price: Decimal,
        timeframe: String
    ) {
        guard AppSettingsStore.shared.notifyMarketStructure else { return }
        
        let cleanSymbol = symbol.uppercased()
        let cleanTf = timeframe.uppercased()
        let debounceKey = "\(cleanSymbol)_\(levelName)_\(cleanTf)"
        let now = Date()
        
        if let last = lastMarketAlertTimes[debounceKey], now.timeIntervalSince(last) < 900 {
            return
        }
        lastMarketAlertTimes[debounceKey] = now
        
        let formattedPrice = Formatters.price(price, symbol: cleanSymbol)
        let title = "[MARKET STRUCTURE ALERT]"
        let subtitle = "\(cleanSymbol) (\(cleanTf))"
        let body = "\(cleanSymbol) touched \(levelName) at \(formattedPrice) on \(cleanTf) timeframe."
        
        dispatchNotificationNow(
            id: "market_poc_\(Int(now.timeIntervalSince1970))_\(cleanSymbol)",
            category: .marketStructure,
            title: title,
            subtitle: subtitle,
            body: body,
            userInfo: ["symbol": cleanSymbol, "level": levelName, "price": "\(price)"]
        )
    }
    
    // MARK: - 5. System Test Notification Dispatcher
    
    /// Dispatches a sample notification to verify permissions, sound, and banner presentation.
    public func sendTestNotification() {
        dispatchNotificationNow(
            id: "test_\(Int(Date().timeIntervalSince1970))",
            category: .marketStructure,
            title: "[SYSTEM NOTIFICATION TEST]",
            subtitle: "Alert Delivery Operational",
            body: "Standard 27 notification dispatch verified. Alerts, sound, and deep linking are functioning normally.",
            userInfo: ["type": "test_notification"]
        )
    }
    
    // MARK: - Helper Methods
    
    private func scheduleDailyRoutine(
        id: String,
        hour: Int,
        minute: Int,
        title: String,
        subtitle: String,
        body: String,
        category: NotificationCategory,
        cal: Calendar,
        now: Date,
        userInfo: [String: String] = [:]
    ) {
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let targetDate = cal.date(from: comps), targetDate > now else { return }
        
        AppNotificationManager.shared.scheduleNotification(
            id: id,
            title: title,
            subtitle: subtitle,
            body: body,
            categoryIdentifier: category.rawValue,
            date: targetDate,
            userInfo: userInfo
        )
    }
    
    private func dispatchNotificationNow(
        id: String,
        category: NotificationCategory,
        title: String,
        subtitle: String?,
        body: String,
        userInfo: [String: String]
    ) {
        AppNotificationManager.shared.dispatchNotification(
            id: id,
            title: title,
            subtitle: subtitle,
            body: body,
            categoryIdentifier: category.rawValue,
            userInfo: userInfo
        )
        
        let item = NotificationItem(
            id: id,
            category: category,
            title: title,
            subtitle: subtitle,
            body: body,
            timestamp: Date(),
            isRead: false,
            userInfo: userInfo
        )
        addNotificationToHistory(item)
    }
    
    // MARK: - In-App History & Feed Management
    
    private func addNotificationToHistory(_ item: NotificationItem) {
        recentNotifications.insert(item, at: 0)
        if recentNotifications.count > 50 {
            recentNotifications = Array(recentNotifications.prefix(50))
        }
        unreadCount = recentNotifications.filter { !$0.isRead }.count
        saveHistory()
    }
    
    public func markAllAsRead() {
        for idx in recentNotifications.indices {
            recentNotifications[idx].isRead = true
        }
        unreadCount = 0
        saveHistory()
    }
    
    public func clearAll() {
        recentNotifications.removeAll()
        unreadCount = 0
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: kNotificationHistoryKey),
              let list = try? JSONDecoder().decode([NotificationItem].self, from: data) else {
            return
        }
        self.recentNotifications = list
        self.unreadCount = list.filter { !$0.isRead }.count
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentNotifications) {
            UserDefaults.standard.set(data, forKey: kNotificationHistoryKey)
        }
    }
    
    // MARK: - Static Currency Mapping Helper
    
    public static func relatedCurrencies(for symbol: String) -> Set<String> {
        let sym = symbol.uppercased().replacingOccurrences(of: "[/_\\-\\.]", with: "", options: .regularExpression)
        var result = Set<String>()
        let major = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "NZD", "CHF"]
        for c in major {
            if sym.contains(c) {
                result.insert(c)
            }
        }
        if sym.contains("XAU") || sym.contains("GOLD") || sym.contains("OIL") ||
           sym.contains("US30") || sym.contains("NAS100") || sym.contains("SPX") ||
           sym.contains("BTC") || sym.contains("ETH") || sym.contains("SOL") {
            result.insert("USD")
        }
        if sym.contains("GER") || sym.contains("DAX") || sym.contains("DE30") || sym.contains("DE40") {
            result.insert("EUR")
        }
        if sym.contains("UK100") || sym.contains("FTSE") {
            result.insert("GBP")
        }
        if result.isEmpty {
            result.insert("USD")
        }
        return result
    }
}
