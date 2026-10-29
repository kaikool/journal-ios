import Foundation

// MARK: - Supabase Two-Way Sync for Trade Lesson Evaluations (trade_lesson_evaluations)
extension SupabaseService {
    
    /// Fetches all trade lesson evaluations belonging to the authenticated user
    public func fetchTradeLessonEvaluations() async throws -> [TradeLessonEvaluation] {
        guard isConfigured else { return [] }
        let endpoint = "trade_lesson_evaluations?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseTradeLessonEvaluationRecord.self, from: data)
        return records.map { $0.toEvaluation() }
    }
    
    /// Upserts a batch of trade lesson evaluations into Supabase PostgREST
    public func upsertTradeLessonEvaluations(_ items: [TradeLessonEvaluation]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseTradeLessonEvaluationRecord(evaluation: $0) }
        try await upsertBatches(endpoint: "trade_lesson_evaluations", items: dtos)
    }
    
    /// Deletes a trade lesson evaluation by ID on Supabase
    public func deleteTradeLessonEvaluation(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "trade_lesson_evaluations?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
