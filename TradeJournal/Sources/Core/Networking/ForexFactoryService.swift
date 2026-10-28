import Foundation
import SwiftUI
import Combine

// MARK: - Forex Factory News Impact
public enum ForexFactoryImpact: String, Codable, Sendable, CaseIterable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case holiday = "Holiday"
    case nonEconomic = "Non-Economic"
    case unknown = "Unknown"
    
    public var id: String { rawValue }
    
    public init(fromRaw: String) {
        let clean = fromRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.caseInsensitiveCompare("High") == .orderedSame { self = .high }
        else if clean.caseInsensitiveCompare("Medium") == .orderedSame { self = .medium }
        else if clean.caseInsensitiveCompare("Low") == .orderedSame { self = .low }
        else if clean.caseInsensitiveCompare("Holiday") == .orderedSame { self = .holiday }
        else { self = .unknown }
    }
    
    public var shortLabel: String {
        switch self {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        case .holiday: return "HOLIDAY"
        default: return "INFO"
        }
    }
}

// MARK: - Forex Factory Economic Event
public struct ForexFactoryEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(dateStr)_\(title)_\(country)" }
    public let title: String
    public let country: String
    public let dateStr: String // Raw ISO string: "2026-10-27T08:30:00-04:00"
    public let impactRaw: String
    public let forecast: String
    public let previous: String
    
    // Cached parsed values (computed once at initialization/decoding for 0ms access)
    public let date: Date?
    public let dateKey: String
    
    public var impact: ForexFactoryImpact {
        ForexFactoryImpact(fromRaw: impactRaw)
    }
    
    public func matches(dateKey: String, timeZone: TimeZone) -> Bool {
        if dateKey == self.dateKey { return true }
        if let d = self.date {
            ForexFactoryEvent.fastUtcFormatter.timeZone = timeZone
            let match = ForexFactoryEvent.fastUtcFormatter.string(from: d) == dateKey
            ForexFactoryEvent.fastUtcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            return match
        }
        return dateStr.hasPrefix(dateKey)
    }
    
    enum CodingKeys: String, CodingKey {
        case title
        case country
        case dateStr = "date"
        case impactRaw = "impact"
        case forecast
        case previous
    }
    
    private static let fastIsoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let fastIsoFormatterStd: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    public static let fastUtcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
    
    public static func parseDateFast(_ str: String) -> Date? {
        if let d = fastIsoFormatter.date(from: str) { return d }
        if let d = fastIsoFormatterStd.date(from: str) { return d }
        return FlexibleDateParser.parse(str)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.country = try container.decode(String.self, forKey: .country)
        let rawDate = try container.decode(String.self, forKey: .dateStr)
        self.dateStr = rawDate
        self.impactRaw = (try? container.decode(String.self, forKey: .impactRaw)) ?? ""
        self.forecast = (try? container.decode(String.self, forKey: .forecast)) ?? ""
        self.previous = (try? container.decode(String.self, forKey: .previous)) ?? ""
        
        let parsed = Self.parseDateFast(rawDate)
        self.date = parsed
        if let d = parsed {
            self.dateKey = Self.fastUtcFormatter.string(from: d)
        } else if rawDate.count >= 10 {
            self.dateKey = String(rawDate.prefix(10))
        } else {
            self.dateKey = ""
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(country, forKey: .country)
        try container.encode(dateStr, forKey: .dateStr)
        try container.encode(impactRaw, forKey: .impactRaw)
        try container.encode(forecast, forKey: .forecast)
        try container.encode(previous, forKey: .previous)
    }
    
    public init(
        title: String,
        country: String,
        dateStr: String,
        impactRaw: String,
        forecast: String = "",
        previous: String = ""
    ) {
        self.title = title
        self.country = country
        self.dateStr = dateStr
        self.impactRaw = impactRaw
        self.forecast = forecast
        self.previous = previous
        
        let parsed = Self.parseDateFast(dateStr)
        self.date = parsed
        if let d = parsed {
            self.dateKey = Self.fastUtcFormatter.string(from: d)
        } else if dateStr.count >= 10 {
            self.dateKey = String(dateStr.prefix(10))
        } else {
            self.dateKey = ""
        }
    }
}

// MARK: - Forex Factory Service (USD Focused)
@MainActor
public final class ForexFactoryService: ObservableObject {
    public static let shared = ForexFactoryService()
    
    public static let endpointUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.json?version=ae6353e5365cb1dd2a94f2299433e6bb"
    public static let fallbackEndpointUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
    
    private let cacheKey = "forex_factory_usd_events_v2"
    private let lastFetchedKey = "forex_factory_last_fetched_v2"
    private let cacheTTL: TimeInterval = 4 * 3600 // 4 hours
    
    @Published public private(set) var usdEvents: [ForexFactoryEvent] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastUpdated: Date? = nil
    @Published public private(set) var errorMessage: String? = nil
    
    private init() {
        loadFromCache()
    }
    
    // MARK: - Cache Management
    private func loadFromCache() {
        if let last = UserDefaults.standard.object(forKey: lastFetchedKey) as? Date {
            self.lastUpdated = last
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([ForexFactoryEvent].self, from: data),
           !cached.isEmpty {
            self.usdEvents = cached
        }
    }
    
    // MARK: - Event Merging & Persistence
    public func mergeEvents(_ incoming: [ForexFactoryEvent]) {
        var map: [String: ForexFactoryEvent] = [:]
        for e in usdEvents {
            map[e.id] = e
        }
        for e in incoming {
            map[e.id] = e
        }
        self.usdEvents = map.values.sorted { (a, b) -> Bool in
            (a.date ?? Date.distantPast) < (b.date ?? Date.distantPast)
        }
    }
    
    private func saveToCache() {
        if let encoded = try? JSONEncoder().encode(usdEvents) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            let now = Date()
            UserDefaults.standard.set(now, forKey: lastFetchedKey)
            self.lastUpdated = now
        }
    }
    
    // MARK: - Public Fetch Methods
    public func fetchEventsIfNeeded(force: Bool = false) async {
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < cacheTTL, !usdEvents.isEmpty {
            return
        }
        await fetchEvents()
    }
    
    public func fetchEvents() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let freshEvents = try await downloadUsdEvents()
            self.mergeEvents(freshEvents)
            saveToCache()
            self.isLoading = false
            AppLogger.info("Forex Factory USD calendar refreshed: \(freshEvents.count) fresh events merged into archive (total: \(usdEvents.count)).")
            
            // Quietly back up updated calendar events to Supabase
            if SupabaseService.shared.isConfigured {
                Task {
                    await self.pushToSupabase()
                }
            }
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            AppLogger.warning("Forex Factory calendar fetch failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Supabase Cloud Synchronization
    public func syncWithSupabase() async {
        guard SupabaseService.shared.isConfigured else { return }
        await pullFromSupabase()
        await pushToSupabase()
    }
    
    public func pullFromSupabase() async {
        guard SupabaseService.shared.isConfigured else { return }
        do {
            let records = try await SupabaseService.shared.fetchSettings(prefix: "economic_calendar:")
            var remoteEvents: [ForexFactoryEvent] = []
            for record in records {
                if let data = record.value.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([ForexFactoryEvent].self, from: data) {
                    remoteEvents.append(contentsOf: decoded)
                }
            }
            if !remoteEvents.isEmpty {
                self.mergeEvents(remoteEvents)
                self.saveToCache()
                AppLogger.info("Pulled \(remoteEvents.count) historical economic events from Supabase.")
            }
        } catch {
            AppLogger.warning("Supabase economic calendar pull warning: \(error.localizedDescription)")
        }
    }
    
    public func pushToSupabase() async {
        guard SupabaseService.shared.isConfigured, !usdEvents.isEmpty else { return }
        
        var monthGroups: [String: [ForexFactoryEvent]] = [:]
        for event in usdEvents {
            let monthKey = String(event.dateStr.prefix(7))
            guard monthKey.count == 7 else { continue }
            monthGroups[monthKey, default: []].append(event)
        }
        
        var recordsToUpload: [JournalSettingRecord] = []
        for (monthKey, events) in monthGroups {
            if let data = try? JSONEncoder().encode(events),
               let jsonStr = String(data: data, encoding: .utf8) {
                recordsToUpload.append(JournalSettingRecord(key: "economic_calendar:\(monthKey)", value: jsonStr))
            }
        }
        
        if !recordsToUpload.isEmpty {
            do {
                try await SupabaseService.shared.upsertSettings(recordsToUpload)
                AppLogger.info("Pushed \(recordsToUpload.count) economic calendar month groups to Supabase.")
            } catch {
                AppLogger.warning("Supabase economic calendar push warning: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - HTTP Fetch with Real Mobile User-Agent
    private func downloadUsdEvents() async throws -> [ForexFactoryEvent] {
        let candidateUrls = [
            URL(string: Self.endpointUrl),
            URL(string: Self.fallbackEndpointUrl)
        ].compactMap { $0 }
        
        var lastError: Error = URLError(.badServerResponse)
        
        for url in candidateUrls {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    continue
                }
                
                if http.statusCode == 200 {
                    let decoded = try JSONDecoder().decode([ForexFactoryEvent].self, from: data)
                    // Strictly filter to USD events as requested
                    let filtered = decoded.filter { $0.country.uppercased() == "USD" }
                    return filtered.sorted { (a, b) -> Bool in
                        (a.date ?? Date.distantPast) < (b.date ?? Date.distantPast)
                    }
                } else if http.statusCode == 429 {
                    // Rate limited - gracefully fall back to cache
                    if !usdEvents.isEmpty {
                        return usdEvents
                    }
                    return []
                } else {
                    lastError = NSError(domain: "ForexFactory", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode)"])
                }
            } catch {
                lastError = error
            }
        }
        
        // If we have cached events, gracefully return them instead of failing completely
        if !usdEvents.isEmpty {
            return usdEvents
        }
        throw lastError
    }
}
