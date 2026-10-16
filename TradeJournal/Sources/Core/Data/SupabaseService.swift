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
    
    public func fetchExecutions(accountId: String) async throws -> [Execution] {
        guard isConfigured else { return [] }
        let request = try makeRequest(endpoint: "executions?account_id=eq.\(accountId)&select=*")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode([Execution].self, from: data)
    }
    
    public func upsertExecutions(_ items: [Execution]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
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
        return try jsonDecoder.decode([Trade].self, from: data)
    }

    public func upsertTrades(_ items: [Trade]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
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
        return try jsonDecoder.decode([Playbook].self, from: data)
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


