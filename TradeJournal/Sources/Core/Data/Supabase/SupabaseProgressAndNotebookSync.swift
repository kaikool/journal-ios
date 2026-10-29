import Foundation

// MARK: - Supabase Two-Way Sync for Notebook (Folders & Notes), Progress Routines & Missed Trades
extension SupabaseService {
    
    // MARK: - Notebook Folders
    
    public func fetchFolders() async throws -> [NotebookFolder] {
        guard isConfigured else { return [] }
        let endpoint = "folders?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseFolderRecord.self, from: data)
        return records.map { $0.toFolder() }
    }
    
    public func upsertFolders(_ items: [NotebookFolder]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseFolderRecord(folder: $0) }
        try await upsertBatches(endpoint: "folders", items: dtos)
    }
    
    public func deleteFolder(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "folders?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    // MARK: - Notebook Notes
    
    public func fetchNotes() async throws -> [NotebookNote] {
        guard isConfigured else { return [] }
        let endpoint = "notes?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseNoteRecord.self, from: data)
        return records.map { $0.toNote() }
    }
    
    public func upsertNotes(_ items: [NotebookNote]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseNoteRecord(note: $0) }
        try await upsertBatches(endpoint: "notes", items: dtos)
    }
    
    public func deleteNote(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "notes?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    // MARK: - Progress Rules (Routines)
    
    public func fetchProgressRules() async throws -> [ProgressRule] {
        guard isConfigured else { return [] }
        let endpoint = "progress_rules?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseProgressRuleRecord.self, from: data)
        return records.map { $0.toRule() }
    }
    
    public func upsertProgressRules(_ items: [ProgressRule]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseProgressRuleRecord(rule: $0) }
        try await upsertBatches(endpoint: "progress_rules", items: dtos)
    }
    
    // MARK: - Progress Checks
    
    public func fetchProgressChecks() async throws -> [ProgressCheck] {
        guard isConfigured else { return [] }
        let endpoint = "progress_checks?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseProgressCheckRecord.self, from: data)
        return records.map { $0.toCheck() }
    }
    
    public func upsertProgressChecks(_ items: [ProgressCheck]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseProgressCheckRecord(check: $0) }
        try await upsertBatches(endpoint: "progress_checks", items: dtos)
    }
    
    public func deleteProgressCheck(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "progress_checks?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    // MARK: - Missed Trades
    
    public func fetchMissedTrades() async throws -> [MissedTrade] {
        guard isConfigured else { return [] }
        let endpoint = "missed_trades?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseMissedTradeRecord.self, from: data)
        return records.map { $0.toTrade() }
    }
    
    public func upsertMissedTrades(_ items: [MissedTrade]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseMissedTradeRecord(trade: $0) }
        try await upsertBatches(endpoint: "missed_trades", items: dtos)
    }
    
    public func deleteMissedTrade(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "missed_trades?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
