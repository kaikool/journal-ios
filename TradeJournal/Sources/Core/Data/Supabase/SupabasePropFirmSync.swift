import Foundation

// MARK: - Supabase Prop Firm Accounts, Movements, Receipts & Audits Sync
extension SupabaseService {
    
    public func fetchPropAccounts() async throws -> [PropAccountItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_accounts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabasePropAccountRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropAccounts(_ items: [PropAccountItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropAccountRecord(item: $0) }
        try await upsertBatches(endpoint: "prop_accounts", items: dtos)
    }

    public func deletePropAccount(id: String) async throws {
        guard isConfigured else { return }
        _ = try? await session.data(for: try makeRequest(endpoint: "prop_entries?account_id=eq.\(id)", method: "DELETE"))
        let endpoint = "prop_accounts?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchPropEntries() async throws -> [PropEntryItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_entries?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabasePropEntryRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropEntries(_ items: [PropEntryItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropEntryRecord(item: $0) }
        try await upsertBatches(endpoint: "prop_entries", items: dtos)
    }

    public func deletePropEntry(id: String) async throws {
        guard isConfigured else { return }
        _ = try? await session.data(for: try makeRequest(endpoint: "prop_receipts?payout_id=eq.\(id)", method: "DELETE"))
        let endpoint = "prop_entries?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchPropReceipts() async throws -> [PropReceiptItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_receipts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabasePropReceiptRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropReceipts(_ items: [PropReceiptItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropReceiptRecord(item: $0) }
        try await upsertBatches(endpoint: "prop_receipts", items: dtos)
    }
    
    public func fetchPropAudits() async throws -> [PropAuditItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_audit?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabasePropAuditRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropAudits(_ items: [PropAuditItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropAuditRecord(item: $0) }
        try await upsertBatches(endpoint: "prop_audit", items: dtos)
    }

    public func deleteProgressRule(id: String) async throws {
        guard isConfigured else { return }
        _ = try? await session.data(for: try makeRequest(endpoint: "progress_checks?rule_id=eq.\(id)", method: "DELETE"))
        let endpoint = "progress_rules?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
