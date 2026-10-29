import Foundation

// MARK: - Supabase Two-Way Sync for AI Research Projects (ai_research_projects)
extension SupabaseService {
    
    /// Fetches all AI research projects belonging to the authenticated user
    public func fetchAIResearchProjects() async throws -> [AIResearchProject] {
        guard isConfigured else { return [] }
        let endpoint = "ai_research_projects?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseAIResearchProjectRecord.self, from: data)
        return records.map { $0.toProject() }
    }
    
    /// Upserts a batch of AI research projects into Supabase PostgREST
    public func upsertAIResearchProjects(_ items: [AIResearchProject]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseAIResearchProjectRecord(project: $0) }
        try await upsertBatches(endpoint: "ai_research_projects", items: dtos)
    }
    
    /// Deletes an AI research project by ID on Supabase
    public func deleteAIResearchProject(id: String) async throws {
        guard isConfigured else { return }
        let endpoint = "ai_research_projects?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
