import Foundation

/// Capabilities that a sync provider can support
public enum SyncCapability: String, Codable, Hashable, CaseIterable {
    case dateRangeFilter
    case accountSelection
    case openPositions
    case historicalExecutions
    case payoutsAndChallenges
    case cloudBackup
    
    public var label: String {
        switch self {
        case .dateRangeFilter: return "Date Range Filter"
        case .accountSelection: return "Account Filter"
        case .openPositions: return "Open Positions"
        case .historicalExecutions: return "Historical Deals"
        case .payoutsAndChallenges: return "Payouts & Challenges"
        case .cloudBackup: return "Cloud Backup"
        }
    }
}

/// Date range modes for synchronization
public enum SyncDateRangeMode: String, Codable, CaseIterable, Identifiable {
    case last7Days = "7d"
    case last30Days = "30d"
    case last90Days = "90d"
    case allTime = "all"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .allTime: return "All Time"
        case .custom: return "Custom Range"
        }
    }
    
    public func dateInterval(customStart: Date? = nil, customEnd: Date? = nil) -> (start: Date?, end: Date?) {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -7, to: now)
            return (start, now)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -30, to: now)
            return (start, now)
        case .last90Days:
            let start = cal.date(byAdding: .day, value: -90, to: now)
            return (start, now)
        case .allTime:
            return (nil, nil)
        case .custom:
            return (customStart, customEnd ?? now)
        }
    }
}

/// Unified options passed to providers during a sync run
public struct SyncOptions: Codable, Equatable {
    public var enabledProviderIds: Set<String>
    public var dateRangeMode: SyncDateRangeMode
    public var customStartDate: Date?
    public var customEndDate: Date?
    public var selectedAccountIds: Set<String>?
    public var includeOpenPositions: Bool
    public var includeHistoricalDeals: Bool
    public var backupToCloud: Bool
    
    public init(
        enabledProviderIds: Set<String> = ["ctrader", "the5ers"],
        dateRangeMode: SyncDateRangeMode = .last30Days,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil,
        selectedAccountIds: Set<String>? = nil,
        includeOpenPositions: Bool = true,
        includeHistoricalDeals: Bool = true,
        backupToCloud: Bool = false
    ) {
        self.enabledProviderIds = enabledProviderIds
        self.dateRangeMode = dateRangeMode
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
        self.selectedAccountIds = selectedAccountIds
        self.includeOpenPositions = includeOpenPositions
        self.includeHistoricalDeals = includeHistoricalDeals
        self.backupToCloud = backupToCloud
    }
    
    public static var `default`: SyncOptions {
        SyncOptions(
            enabledProviderIds: ["ctrader", "the5ers"],
            dateRangeMode: .last30Days,
            includeOpenPositions: true,
            includeHistoricalDeals: true,
            backupToCloud: false
        )
    }
}

/// Real-time progress update emitted during a sync execution
public struct SyncProgressUpdate: Equatable {
    public let providerId: String
    public let providerName: String
    public let message: String
    public let isCompleted: Bool
    
    public init(providerId: String, providerName: String, message: String, isCompleted: Bool = false) {
        self.providerId = providerId
        self.providerName = providerName
        self.message = message
        self.isCompleted = isCompleted
    }
}

/// Final outcome returned by a provider after synchronization
public struct SyncResult: Identifiable, Codable, Equatable {
    public var id: String { "\(providerId)_\(timestamp.timeIntervalSince1970)" }
    public let providerId: String
    public let providerName: String
    public let success: Bool
    public let importedExecutionsCount: Int
    public let updatedPositionsCount: Int
    public let updatedAccountsCount: Int
    public let message: String
    public let error: String?
    public let timestamp: Date
    
    public init(
        providerId: String,
        providerName: String,
        success: Bool,
        importedExecutionsCount: Int = 0,
        updatedPositionsCount: Int = 0,
        updatedAccountsCount: Int = 0,
        message: String,
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.success = success
        self.importedExecutionsCount = importedExecutionsCount
        self.updatedPositionsCount = updatedPositionsCount
        self.updatedAccountsCount = updatedAccountsCount
        self.message = message
        self.error = error
        self.timestamp = timestamp
    }
}

/// Protocol that every broker, exchange, or cloud service must implement
@MainActor
public protocol SyncProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    var isConfigured: Bool { get }
    var capabilities: Set<SyncCapability> { get }
    
    func performSync(
        options: SyncOptions,
        progressHandler: @escaping (SyncProgressUpdate) -> Void
    ) async throws -> SyncResult
}
