import Foundation

/// 1:1 port from table `progress_rules` in `schema.pg.ts`
public struct ProgressRule: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var stage: String
    public var weekdaysJson: String // JSON array e.g. "[1,2,3,4,5]"
    public let createdAt: String
    public var archivedAt: String?
    
    public init(
        id: String = JournalIds.newId(),
        title: String,
        stage: String,
        weekdaysJson: String = "[1,2,3,4,5]",
        createdAt: String = JournalIds.nowIso(),
        archivedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.stage = stage
        self.weekdaysJson = weekdaysJson
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

extension ProgressRule {
    public var isArchived: Bool {
        archivedAt != nil
    }
    
    /// Returns the parsed weekdays (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
    public var activeWeekdays: Set<Int> {
        guard let data = weekdaysJson.data(using: .utf8),
              let list = try? JSONDecoder().decode([Int].self, from: data) else {
            return [1, 2, 3, 4, 5]
        }
        return Set(list)
    }
    
    /// Checks if this routine was active on a given date string (yyyy-MM-dd).
    /// If never archived, returns true.
    /// If archived, it remains active for dates strictly before the day it was archived.
    public func isActive(on dateString: String) -> Bool {
        guard let arch = archivedAt else { return true }
        let archDate = String(arch.prefix(10))
        return dateString < archDate
    }
    
    /// Checks if this routine is scheduled on a given date string (yyyy-MM-dd) based on weekdays.
    public func isScheduled(on dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = formatter.date(from: dateString) else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let weekday = cal.component(.weekday, from: d) // 1 = Sunday, 2 = Monday, ... 7 = Saturday
        let idx = weekday - 1 // 0 = Sun, 1 = Mon, ..., 6 = Sat
        return activeWeekdays.contains(idx)
    }
}

/// 1:1 port from table `progress_checks` in `schema.pg.ts`
public struct ProgressCheck: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let ruleId: String
    public let date: String // YYYY-MM-DD
    public var done: Bool
    
    public init(
        id: String = JournalIds.newId(),
        ruleId: String,
        date: String,
        done: Bool
    ) {
        self.id = id
        self.ruleId = ruleId
        self.date = date
        self.done = done
    }
}
