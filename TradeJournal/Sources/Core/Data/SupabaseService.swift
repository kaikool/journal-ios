import Foundation

/// Dịch vụ kết nối trực tiếp với Supabase PostgreSQL qua chuẩn PostgREST API.
/// Hỗ trợ Auth, Multi-tenancy RLS, và đồng bộ dữ liệu hai chiều.
public final class SupabaseService {
    public static let shared = SupabaseService()
    
    public var supabaseUrl: String = ""
    public var supabaseAnonKey: String = ""
    public var accessToken: String? = nil
    
    private let session = URLSession.shared
    
    public var isConfigured: Bool {
        !supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
        !supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private init() {
        // Load cấu hình lưu trong UserDefaults nếu có
        self.supabaseUrl = UserDefaults.standard.string(forKey: "supabase_url") ?? ""
        self.supabaseAnonKey = UserDefaults.standard.string(forKey: "supabase_anon_key") ?? ""
        self.accessToken = UserDefaults.standard.string(forKey: "supabase_access_token")
    }
    
    public func configure(url: String, anonKey: String, token: String? = nil) {
        self.supabaseUrl = url.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.supabaseAnonKey = anonKey.trimmingCharacters(in: .whitespaces)
        self.accessToken = token
        
        UserDefaults.standard.set(self.supabaseUrl, forKey: "supabase_url")
        UserDefaults.standard.set(self.supabaseAnonKey, forKey: "supabase_anon_key")
        UserDefaults.standard.set(self.accessToken, forKey: "supabase_access_token")
    }
    
    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil, preferMerge: Bool = false) throws -> URLRequest {
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(endpoint)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if preferMerge {
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        }
        
        request.httpBody = body
        return request
    }
    
    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    public func fetchAccounts() async throws -> [Account] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "accounts?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([Account].self, from: data)
    }
    
    public func pingConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Chưa cấu hình Supabase URL và Key.")
        }
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/") else {
            return (false, "URL Supabase không đúng định dạng.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if (200...299).contains(http.statusCode) {
                return (true, "Kết nối Supabase thành công! (HTTP \(http.statusCode))")
            } else if http.statusCode == 401 {
                return (false, "Lỗi 401: API Key hoặc Token không hợp lệ.")
            } else if http.statusCode == 403 {
                return (false, "Lỗi 403: Bị chặn bởi RLS. Hãy cấp quyền Policy hoặc dùng Service Role Key.")
            } else {
                return (false, "Supabase phản hồi mã HTTP \(http.statusCode)")
            }
        }
        return (false, "Không có phản hồi từ máy chủ.")
    }
    
    public func fetchExecutions(accountId: String) async throws -> [Execution] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "executions?account_id=eq.\(accountId)&select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let records = try jsonDecoder.decode([SupabaseExecutionRecord].self, from: data)
        return records.map { $0.toExecution() }
    }
    
    public func upsertExecutions(_ items: [Execution]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseExecutionRecord(execution: $0) }
        let body = try jsonEncoder.encode(dtos)
        let request = try makeRequest(endpoint: "executions", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func fetchTrades(accountId: String) async throws -> [Trade] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "trades?account_id=eq.\(accountId)&select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let records = try jsonDecoder.decode([SupabaseTradeRecord].self, from: data)
        return records.map { $0.toTrade() }
    }

    public func upsertTrades(_ items: [Trade]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseTradeRecord(trade: $0) }
        let body = try jsonEncoder.encode(dtos)
        let request = try makeRequest(endpoint: "trades", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func fetchPlaybooks() async throws -> [Playbook] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "playbooks?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let records = try jsonDecoder.decode([SupabasePlaybookRecord].self, from: data)
        return records.map { $0.toPlaybook() }
    }

    public func fetchJournalDays() async throws -> [JournalNote] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "journal_days?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([JournalNote].self, from: data)
    }

    public func fetchSettings() async throws -> [JournalSettingRecord] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "settings?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([JournalSettingRecord].self, from: data)
    }
    
    // MARK: - Prop Firm (Sổ cái Quỹ) PostgREST Sync
    
    public func fetchPropAccounts() async throws -> [PropAccountItem] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "prop_accounts?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([PropAccountItem].self, from: data)
    }
    
    public func upsertPropAccounts(_ items: [PropAccountItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let request = try makeRequest(endpoint: "prop_accounts", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func fetchPropEntries() async throws -> [PropEntryItem] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "prop_entries?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([PropEntryItem].self, from: data)
    }
    
    public func upsertPropEntries(_ items: [PropEntryItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let request = try makeRequest(endpoint: "prop_entries", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func fetchPropReceipts() async throws -> [PropReceiptItem] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "prop_receipts?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([PropReceiptItem].self, from: data)
    }
    
    public func upsertPropReceipts(_ items: [PropReceiptItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let request = try makeRequest(endpoint: "prop_receipts", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func fetchPropAudits() async throws -> [PropAuditItem] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "prop_audit?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([PropAuditItem].self, from: data)
    }
    
    public func upsertPropAudits(_ items: [PropAuditItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let request = try makeRequest(endpoint: "prop_audit", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    // MARK: - Attachments & Storage API
    
    public func fetchAttachments() async throws -> [Attachment] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "attachments?select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([Attachment].self, from: data)
    }
    
    public func upsertAttachments(_ items: [Attachment]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let request = try makeRequest(endpoint: "attachments", method: "POST", body: body, preferMerge: true)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func uploadAttachmentFile(storagePath: String, data: Data, mime: String) async throws {
        guard isConfigured else { return }
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/journal-attachments/\(storagePath)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    public func deleteAttachmentFile(storagePath: String) async throws {
        guard isConfigured else { return }
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/journal-attachments/\(storagePath)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - PostgREST 1:1 Schema DTOs (Mapped to schema.pg.ts)

public struct SupabaseTradeRecord: Codable {
    public let key: String
    public let accountId: String
    public let symbol: String
    public let assetClass: String?
    public let direction: String
    public let status: String
    public let openedAt: String
    public let closedAt: String?
    public let quantity: Double
    public let openQuantity: Double
    public let avgEntry: Double
    public let avgExit: Double?
    public let grossPnl: Double
    public let fees: Double
    public let netPnl: Double
    public let executionCount: Int
    public let executionIdsJson: String
    public let exitsJson: String
    public let durationMs: Int64?
    public let notes: String?
    public let tagsJson: String?
    public let mistakesJson: String?
    public let playbookId: String?
    public let rating: Int?
    public let stopLoss: Double?
    public let profitTarget: Double?
    public let reviewedAt: String?
    
    public init(trade: Trade) {
        let fmt = ISO8601DateFormatter()
        self.key = trade.key
        self.accountId = trade.accountId
        self.symbol = trade.symbol
        self.assetClass = trade.assetClass
        self.direction = trade.direction.rawValue
        self.status = trade.status.rawValue
        self.openedAt = fmt.string(from: trade.openedAt)
        self.closedAt = trade.closedAt.map { fmt.string(from: $0) }
        self.quantity = (trade.quantity as NSDecimalNumber).doubleValue
        self.openQuantity = (trade.openQuantity as NSDecimalNumber).doubleValue
        self.avgEntry = (trade.avgEntry as NSDecimalNumber).doubleValue
        self.avgExit = trade.avgExit.map { ($0 as NSDecimalNumber).doubleValue }
        self.grossPnl = (trade.grossPnl as NSDecimalNumber).doubleValue
        self.fees = (trade.fees as NSDecimalNumber).doubleValue
        self.netPnl = (trade.netPnl as NSDecimalNumber).doubleValue
        self.executionCount = trade.executionCount
        
        let enc = JSONEncoder()
        self.executionIdsJson = (try? String(data: enc.encode(trade.executionIds), encoding: .utf8)) ?? "[]"
        self.exitsJson = (try? String(data: enc.encode(trade.exits), encoding: .utf8)) ?? "[]"
        self.durationMs = trade.durationMs
        self.notes = trade.notes
        self.tagsJson = (try? String(data: enc.encode(trade.tags), encoding: .utf8)) ?? "[]"
        self.mistakesJson = (try? String(data: enc.encode(trade.mistakes), encoding: .utf8)) ?? "[]"
        self.playbookId = trade.playbookId
        self.rating = trade.rating
        self.stopLoss = trade.stopLoss.map { ($0 as NSDecimalNumber).doubleValue }
        self.profitTarget = trade.profitTarget.map { ($0 as NSDecimalNumber).doubleValue }
        self.reviewedAt = trade.reviewedAt.map { fmt.string(from: $0) }
    }
    
    public func toTrade() -> Trade {
        let fmt = ISO8601DateFormatter()
        let dec = JSONDecoder()
        let parsedOpenedAt = fmt.date(from: openedAt) ?? Date()
        let parsedClosedAt = closedAt.flatMap { fmt.date(from: $0) }
        let parsedReviewedAt = reviewedAt.flatMap { fmt.date(from: $0) }
        let parsedExecIds = (try? dec.decode([String].self, from: Data(executionIdsJson.utf8))) ?? []
        let parsedExits = (try? dec.decode([ExitAttribution].self, from: Data(exitsJson.utf8))) ?? []
        let parsedTags = tagsJson.flatMap { (try? dec.decode([String].self, from: Data($0.utf8))) } ?? []
        let parsedMistakes = mistakesJson.flatMap { (try? dec.decode([String].self, from: Data($0.utf8))) } ?? []
        
        return Trade(
            key: key,
            accountId: accountId,
            symbol: symbol,
            assetClass: assetClass,
            direction: TradeDirection(rawValue: direction) ?? .long,
            status: TradeStatus(rawValue: status) ?? .open,
            openedAt: parsedOpenedAt,
            closedAt: parsedClosedAt,
            quantity: Decimal(quantity),
            openQuantity: Decimal(openQuantity),
            avgEntry: Decimal(avgEntry),
            avgExit: avgExit.map { Decimal($0) },
            grossPnl: Decimal(grossPnl),
            fees: Decimal(fees),
            netPnl: Decimal(netPnl),
            executionCount: executionCount,
            executionIds: parsedExecIds,
            exits: parsedExits,
            durationMs: durationMs,
            notes: notes,
            tags: parsedTags,
            mistakes: parsedMistakes,
            playbookId: playbookId,
            rating: rating,
            stopLoss: stopLoss.map { Decimal($0) },
            profitTarget: profitTarget.map { Decimal($0) },
            reviewedAt: parsedReviewedAt
        )
    }
}

public struct SupabaseExecutionRecord: Codable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let side: String
    public let quantity: Double
    public let price: Double
    public let fee: Double
    public let executedAt: String
    public let assetClass: String?
    public let source: String
    public let importMetadataJson: String?
    public let contentHash: String
    public let createdAt: String
    
    public init(execution: Execution) {
        let fmt = ISO8601DateFormatter()
        self.id = execution.id
        self.accountId = execution.accountId
        self.symbol = execution.symbol
        self.side = execution.side.rawValue
        self.quantity = (execution.quantity as NSDecimalNumber).doubleValue
        self.price = (execution.price as NSDecimalNumber).doubleValue
        self.fee = (execution.fee as NSDecimalNumber).doubleValue
        self.executedAt = fmt.string(from: execution.executedAt)
        self.assetClass = execution.assetClass
        self.source = execution.source
        self.importMetadataJson = execution.importMetadataJson
        self.contentHash = execution.contentHash
        self.createdAt = fmt.string(from: execution.executedAt)
    }
    
    public func toExecution() -> Execution {
        let fmt = ISO8601DateFormatter()
        let parsedDate = fmt.date(from: executedAt) ?? Date()
        return Execution(
            id: id,
            accountId: accountId,
            symbol: symbol,
            side: ExecutionSide(rawValue: side) ?? .buy,
            quantity: Decimal(quantity),
            price: Decimal(price),
            fee: Decimal(fee),
            executedAt: parsedDate,
            assetClass: assetClass,
            source: source,
            contentHash: contentHash,
            importMetadataJson: importMetadataJson
        )
    }
}

public struct SupabasePlaybookRecord: Codable {
    public let id: String
    public let name: String
    public let description: String
    public let rulesJson: String
    public let createdAt: String
    
    public init(playbook: Playbook) {
        let fmt = ISO8601DateFormatter()
        self.id = playbook.id
        self.name = playbook.name
        self.description = playbook.description
        self.rulesJson = (try? String(data: JSONEncoder().encode(playbook.rules), encoding: .utf8)) ?? "[]"
        self.createdAt = fmt.string(from: playbook.createdAt)
    }
    
    public func toPlaybook() -> Playbook {
        let fmt = ISO8601DateFormatter()
        let parsedRules = (try? JSONDecoder().decode([String].self, from: Data(rulesJson.utf8))) ?? []
        return Playbook(
            id: id,
            name: name,
            description: description,
            rules: parsedRules,
            createdAt: fmt.date(from: createdAt) ?? Date()
        )
    }
}


