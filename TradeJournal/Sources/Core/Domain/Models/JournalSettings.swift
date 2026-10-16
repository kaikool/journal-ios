import Foundation

/// 1:1 port từ bảng `settings` trong `schema.pg.ts`
public struct JournalSettingRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public var value: String
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
