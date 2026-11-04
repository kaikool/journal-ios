import Foundation

// MARK: - Supabase Session Footprint & Key Levels Sync
/// Network sync service for storing and querying completed Session Footprint Profiles.
/// Enables 0ms retrieval of historical POC, VAH, VAL, and Naked POCs, drastically reducing OANDA API requests.
extension SupabaseService {
    
    public func fetchSessionProfiles(symbol: String, limit: Int = 30) async throws -> [SessionProfileSnapshot] {
        guard isConfigured else { return [] }
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let endpoint = "session_footprint_profiles?symbol=eq.\(clean)&order=session_date.desc&limit=\(limit)"
        
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseSessionProfileRecord.self, from: data)
        return records.map { $0.toSnapshot() }
    }
    
    public func fetchNakedProfiles(symbol: String) async throws -> [SessionProfileSnapshot] {
        guard isConfigured else { return [] }
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let endpoint = "session_footprint_profiles?symbol=eq.\(clean)&is_naked=eq.true&order=session_date.desc"
        
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseSessionProfileRecord.self, from: data)
        return records.map { $0.toSnapshot() }
    }
    
    public func upsertSessionProfiles(_ items: [SessionProfileSnapshot]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseSessionProfileRecord(snapshot: $0) }
        try await upsertBatches(endpoint: "session_footprint_profiles", items: dtos)
    }
    
    public func markProfileMitigated(id: String, mitigatedAt: Date) async throws {
        guard isConfigured else { return }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let mStr = isoFormatter.string(from: mitigatedAt)
        
        let payload: [String: Any] = [
            "is_naked": false,
            "mitigated_at": mStr
        ]
        
        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = try makeRequest(endpoint: "session_footprint_profiles?id=eq.\(id)", method: "PATCH")
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (resData, response) = try await session.data(for: request)
        try validateResponse(response, data: resData, endpoint: "session_footprint_profiles?id=eq.\(id)")
    }
}
