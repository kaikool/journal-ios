import Foundation

// MARK: - Supabase Two-Way Sync for AI Long-term Memory (ai_memories)
extension SupabaseService {
    
    /// Fetches all AI memories belonging to the authenticated user (or anon)
    public func fetchAIMemories() async throws -> [AIMemoryRecord] {
        guard isConfigured else { return [] }
        let endpoint = "ai_memories?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseAIMemoryRecord.self, from: data)
        return records.map { $0.toRecord() }
    }
    
    /// Upserts a batch of AI memory records into Supabase PostgREST
    public func upsertAIMemories(_ items: [AIMemoryRecord]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseAIMemoryRecord(record: $0) }
        try await upsertBatches(endpoint: "ai_memories", items: dtos)
    }
    
    /// Deletes an AI memory by ID on Supabase
    public func deleteAIMemory(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "ai_memories?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
