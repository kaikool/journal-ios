import Foundation

// MARK: - Standard 27: Unified Alerting & Notification Models

/// Categories defined by Standard 27 (Single Source of Truth for Alert Dispatching)
public enum NotificationCategory: String, Codable, CaseIterable, Sendable {
    case economicNews = "ECONOMIC_NEWS"
    case disciplineTilt = "DISCIPLINE_TILT"
    case preSessionRoutine = "PRE_SESSION_ROUTINE"
    case dailyJournalReview = "DAILY_JOURNAL_REVIEW"
    case marketStructure = "MARKET_STRUCTURE"
    
    public var label: String {
        switch self {
        case .economicNews: return "Economic News"
        case .disciplineTilt: return "Discipline Warning"
        case .preSessionRoutine: return "Session Routine"
        case .dailyJournalReview: return "Journal Review"
        case .marketStructure: return "Market Structure"
        }
    }
}

/// Represents an in-app persistent notification record for the Notification Center
public struct NotificationItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let category: NotificationCategory
    public let title: String
    public let subtitle: String?
    public let body: String
    public let timestamp: Date
    public var isRead: Bool
    public let userInfo: [String: String]
    
    public init(
        id: String = JournalIds.newId(),
        category: NotificationCategory,
        title: String,
        subtitle: String? = nil,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        userInfo: [String: String] = [:]
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.userInfo = userInfo
    }
}
