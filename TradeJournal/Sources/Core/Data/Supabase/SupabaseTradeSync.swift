import Foundation

// MARK: - Supabase Trade, Execution, Account & Playbook Sync
extension SupabaseService {
    
    public func fetchAccounts() async throws -> [Account] {
        guard isConfigured else { return [] }
        let endpoint = "accounts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabaseAccountRecord.self, from: data)
        return records.map { $0.toAccount() }
    }
    
    public func upsertAccounts(_ items: [Account]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseAccountRecord(account: $0) }
        try await upsertBatches(endpoint: "accounts", items: dtos)
    }

    public func deleteAccount(id: String) async throws {
        guard isConfigured else { return }
        _ = try? await session.data(for: try makeRequest(endpoint: "prop_entries?account_id=eq.\(id)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "prop_accounts?journal_account_id=eq.\(id)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "trade_rule_checks?account_id=eq.\(id)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "trade_excursions?account_id=eq.\(id)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "trades?account_id=eq.\(id)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "executions?account_id=eq.\(id)", method: "DELETE"))
        
        let endpoint = "accounts?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchExecutions(accountId: String? = nil) async throws -> [Execution] {
        guard isConfigured else { return [] }
        var allExecs: [Execution] = []
        let batchSize = 1000
        var offset = 0
        
        while true {
            let base = (accountId != nil && !accountId!.isEmpty) ? "executions?account_id=eq.\(accountId!)&select=*" : "executions?select=*"
            let endpoint = "\(base)&limit=\(batchSize)&offset=\(offset)&order=executed_at.asc"
            let request = try makeRequest(endpoint: endpoint)
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data, endpoint: endpoint)
            let records = decodeArray(SupabaseExecutionRecord.self, from: data)
            if records.isEmpty { break }
            allExecs.append(contentsOf: records.map { $0.toExecution() })
            if records.count < batchSize { break }
            offset += records.count
        }
        return allExecs
    }
    
    public func upsertExecutions(_ items: [Execution]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseExecutionRecord(execution: $0) }
        try await upsertBatches(endpoint: "executions", items: dtos)
    }
    
    public func fetchTrades(accountId: String? = nil) async throws -> [Trade] {
        guard isConfigured else { return [] }
        var allTrades: [Trade] = []
        let batchSize = 1000
        var offset = 0
        
        while true {
            let base = (accountId != nil && !accountId!.isEmpty) ? "trades?account_id=eq.\(accountId!)&select=*" : "trades?select=*"
            let endpoint = "\(base)&limit=\(batchSize)&offset=\(offset)&order=opened_at.asc"
            let request = try makeRequest(endpoint: endpoint)
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data, endpoint: endpoint)
            let records = decodeArray(SupabaseTradeRecord.self, from: data)
            if records.isEmpty { break }
            allTrades.append(contentsOf: records.map { $0.toTrade() })
            if records.count < batchSize { break }
            offset += records.count
        }
        return allTrades
    }

    public func upsertTrades(_ items: [Trade]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseTradeRecord(trade: $0) }
        try await upsertBatches(endpoint: "trades", items: dtos)
    }

    public func deleteTrade(key: String) async throws {
        guard isConfigured else { return }
        _ = try? await session.data(for: try makeRequest(endpoint: "trade_rule_checks?trade_key=eq.\(key)", method: "DELETE"))
        _ = try? await session.data(for: try makeRequest(endpoint: "trade_excursions?trade_key=eq.\(key)", method: "DELETE"))
        let endpoint = "trades?key=eq.\(key)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }

    public func fetchPlaybooks() async throws -> [Playbook] {
        guard isConfigured else { return [] }
        let endpoint = "playbooks?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = decodeArray(SupabasePlaybookRecord.self, from: data)
        return records.map { $0.toPlaybook() }
    }

    public func upsertPlaybooks(_ items: [Playbook]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePlaybookRecord(playbook: $0) }
        try await upsertBatches(endpoint: "playbooks", items: dtos)
    }

    public func deletePlaybook(id: String) async throws {
        guard isConfigured else { return }
        // 1. Delete associated trade rule checks first to prevent foreign key errors
        let rkEndpoint = "trade_rule_checks?playbook_id=eq.\(id)"
        if let req = try? makeRequest(endpoint: rkEndpoint, method: "DELETE") {
            _ = try? await session.data(for: req)
        }
        // 2. Clear playbook_id in trades so foreign key constraint is satisfied
        let trEndpoint = "trades?playbook_id=eq.\(id)"
        let patchData = "{\"playbook_id\":null}".data(using: .utf8)
        if let req = try? makeRequest(endpoint: trEndpoint, method: "PATCH", body: patchData) {
            _ = try? await session.data(for: req)
        }
        // 3. Delete playbook record
        let endpoint = "playbooks?id=eq.\(id)"
        let request = try makeRequest(endpoint: endpoint, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
}
