import Foundation

// MARK: - Supabase Journal Days (Calendar Notes) & Settings Sync
extension SupabaseService {
    
    public func fetchJournalDays() async throws -> [JournalNote] {
        guard isConfigured else { return [] }
        let endpoint = "journal_days?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseJournalDayRecord.self, from: data)
        return records.map { $0.toJournalNote() }
    }

    public func upsertJournalDays(_ items: [JournalNote]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseJournalDayRecord(journalNote: $0) }
        try await upsertBatches(endpoint: "journal_days", items: dtos)
    }

    public func upsertJournalDay(_ item: JournalNote) async throws {
        guard isConfigured else { return }
        let dto = SupabaseJournalDayRecord(journalNote: item)
        try await upsertBatches(endpoint: "journal_days", items: [dto])
    }

    public func deleteJournalDay(date: String) async throws {
        guard isConfigured else { return }
        let endpoint = "journal_days?date=eq.\(date)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchSettings() async throws -> [JournalSettingRecord] {
        guard isConfigured else { return [] }
        let endpoint = "settings?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return decodeArray(JournalSettingRecord.self, from: data)
    }
    
    public func fetchSettings(prefix: String) async throws -> [JournalSettingRecord] {
        guard isConfigured else { return [] }
        let endpoint = "settings?key=like.\(prefix)*&select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return decodeArray(JournalSettingRecord.self, from: data)
    }
    
    public func upsertSettings(_ items: [JournalSettingRecord]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        try await upsertBatches(endpoint: "settings", items: items)
    }
}
