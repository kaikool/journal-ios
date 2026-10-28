import Foundation

public struct JournalDaySummary: Identifiable {
    public var id: String { date }
    public let date: String
    public let weekday: String
    public let tradesCount: Int
    public let winsCount: Int
    public let lossesCount: Int
    public let netPnl: Decimal
    public let winRate: Double?
    public let hasNote: Bool
    public let notePreview: String
    
    public init(
        date: String,
        weekday: String,
        tradesCount: Int,
        winsCount: Int,
        lossesCount: Int,
        netPnl: Decimal,
        winRate: Double?,
        hasNote: Bool,
        notePreview: String
    ) {
        self.date = date
        self.weekday = weekday
        self.tradesCount = tradesCount
        self.winsCount = winsCount
        self.lossesCount = lossesCount
        self.netPnl = netPnl
        self.winRate = winRate
        self.hasNote = hasNote
        self.notePreview = notePreview
    }
}

public struct IdentifiableDateItem: Identifiable {
    public var id: String { date }
    public let date: String
    
    public init(date: String) {
        self.date = date
    }
}
