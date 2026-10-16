import Foundation

/// Lỗi chi tiết từ Supabase PostgREST API giúp người dùng chẩn đoán chính xác nguyên nhân
public enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidUrl
    case tableNotFound(table: String, message: String)
    case unauthorized(message: String)
    case rlsBlocked(table: String, message: String)
    case postgrestError(statusCode: Int, code: String?, message: String, hint: String?)
    case networkError(String)
    case decodingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Chưa cấu hình Supabase Project URL và Anon Key."
        case .invalidUrl:
            return "Supabase Project URL không đúng định dạng."
        case .tableNotFound(let table, let msg):
            return "Bảng '\(table)' chưa tồn tại trên Supabase PostgreSQL (\(msg)). Hãy bấm 'Sao Chép SQL Khởi Tạo' và chạy trên Supabase SQL Editor để tạo bảng."
        case .unauthorized(let msg):
            return "Lỗi xác thực (HTTP 401): \(msg). Vui lòng kiểm tra lại Anon Key hoặc JWT Access Token."
        case .rlsBlocked(let table, let msg):
            return "Bị chặn bởi Row Level Security (RLS) trên bảng '\(table)' (HTTP 403: \(msg)). Cần thêm Policy cho phép quyền thao tác hoặc dùng Service Role Key."
        case .postgrestError(let code, let pgCode, let msg, let hint):
            var res = "Supabase lỗi HTTP \(code)"
            if let p = pgCode, !p.isEmpty { res += " (Mã: \(p))" }
            res += ": \(msg)"
            if let h = hint, !h.isEmpty { res += " • Gợi ý: \(h)" }
            return res
        case .networkError(let msg):
            return "Lỗi kết nối mạng: \(msg)"
        case .decodingError(let msg):
            return "Lỗi phân tích dữ liệu từ Supabase: \(msg)"
        }
    }
}

/// Cấu trúc phản hồi lỗi chuẩn từ Supabase PostgREST
private struct PostgrestErrorPayload: Decodable {
    let code: String?
    let details: String?
    let hint: String?
    let message: String?
}

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
        self.supabaseUrl = UserDefaults.standard.string(forKey: "supabase_url") ?? ""
        self.supabaseAnonKey = UserDefaults.standard.string(forKey: "supabase_anon_key") ?? ""
        self.accessToken = UserDefaults.standard.string(forKey: "supabase_access_token")
    }
    
    public func configure(url: String, anonKey: String, token: String? = nil) {
        var cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/\"'"))
        if !cleanUrl.isEmpty && !cleanUrl.hasPrefix("http://") && !cleanUrl.hasPrefix("https://") {
            cleanUrl = "https://" + cleanUrl
        }
        let cleanKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'\r\n "))
        
        self.supabaseUrl = cleanUrl
        self.supabaseAnonKey = cleanKey
        self.accessToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        UserDefaults.standard.set(self.supabaseUrl, forKey: "supabase_url")
        UserDefaults.standard.set(self.supabaseAnonKey, forKey: "supabase_anon_key")
        if let t = self.accessToken, !t.isEmpty {
            UserDefaults.standard.set(t, forKey: "supabase_access_token")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        }
    }
    
    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil, preferMerge: Bool = false) throws -> URLRequest {
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(endpoint)") else {
            throw SupabaseError.invalidUrl
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
    
    /// Kiểm tra phản hồi HTTP và ném lỗi có mô tả cụ thể thay vì lỗi -1011
    private func validateResponse(_ response: URLResponse, data: Data, endpoint: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.networkError("Không nhận được phản hồi HTTP từ Supabase.")
        }
        
        if (200...299).contains(http.statusCode) {
            return
        }
        
        let tableName = endpoint.components(separatedBy: "?").first ?? endpoint
        let errPayload = try? JSONDecoder().decode(PostgrestErrorPayload.self, from: data)
        let msg = errPayload?.message ?? (String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        let code = errPayload?.code
        let hint = errPayload?.hint
        
        if http.statusCode == 404 || code == "42P01" || msg.contains("does not exist") {
            throw SupabaseError.tableNotFound(table: tableName, message: msg)
        } else if http.statusCode == 401 || code == "PGRST301" {
            throw SupabaseError.unauthorized(message: msg)
        } else if http.statusCode == 403 || msg.contains("row-level security") {
            throw SupabaseError.rlsBlocked(table: tableName, message: msg)
        } else {
            throw SupabaseError.postgrestError(statusCode: http.statusCode, code: code, message: msg, hint: hint)
        }
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
    
    // MARK: - Chẩn Đoán Kết Nối Chính Xác (Accurate Connection Diagnostics)
    
    public func pingConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Vui lòng nhập đầy đủ Supabase Project URL và Anon Key.")
        }
        
        // 1. Kiểm tra URL Auth Settings để xác thực Anon Key (Endpoint chuẩn của Supabase)
        guard let authSettingsUrl = URL(string: "\(supabaseUrl)/auth/v1/settings") else {
            return (false, "Project URL không đúng định dạng: \(supabaseUrl)")
        }
        
        var authReq = URLRequest(url: authSettingsUrl)
        authReq.httpMethod = "GET"
        authReq.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (authData, authResp) = try await session.data(for: authReq)
            guard let authHttp = authResp as? HTTPURLResponse else {
                return (false, "Không nhận được phản hồi mạng từ Supabase.")
            }
            
            if authHttp.statusCode == 401 {
                return (false, "Lỗi 401: Anon Key không khớp với Project URL này. Vui lòng vào Supabase Dashboard -> Project Settings -> API và copy đúng 'anon public' key.")
            }
            
            if !(200...299).contains(authHttp.statusCode) {
                let errStr = String(data: authData, encoding: .utf8) ?? ""
                return (false, "Supabase phản hồi mã HTTP \(authHttp.statusCode): \(errStr)")
            }
        } catch {
            return (false, "Không thể kết nối tới Project URL: \(error.localizedDescription). Vui lòng kiểm tra lại kết nối mạng hoặc URL.")
        }
        
        // 2. Xác thực PostgREST Database Tables
        guard let restUrl = URL(string: "\(supabaseUrl)/rest/v1/accounts?select=id&limit=1") else {
            return (false, "URL PostgREST không đúng định dạng.")
        }
        
        var restReq = URLRequest(url: restUrl)
        restReq.httpMethod = "GET"
        restReq.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        restReq.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (restData, restResp) = try await session.data(for: restReq)
            guard let restHttp = restResp as? HTTPURLResponse else {
                return (false, "Không có phản hồi từ máy chủ PostgREST.")
            }
            
            if (200...299).contains(restHttp.statusCode) {
                return (true, "Kết nối Supabase thành công 100%! Bảng 'accounts' và dữ liệu đã sẵn sàng đồng bộ.")
            } else if restHttp.statusCode == 404 {
                let err = try? JSONDecoder().decode(PostgrestErrorPayload.self, from: restData)
                if err?.code == "42P01" || (err?.message?.contains("does not exist") ?? true) {
                    return (true, "Xác thực URL và Anon Key thành công! Tuy nhiên database chưa có bảng 'accounts' (Mã 42P01). Hãy bấm 'Sao Chép SQL Khởi Tạo' và chạy trong Supabase SQL Editor.")
                }
                return (false, "Bảng accounts không tìm thấy: \(err?.message ?? "HTTP 404")")
            } else if restHttp.statusCode == 403 {
                return (true, "Xác thực URL và Anon Key thành công! Tuy nhiên bảng đang bật Row Level Security (RLS). Hãy tạo policy cho phép thao tác.")
            } else {
                let bodyStr = String(data: restData, encoding: .utf8) ?? ""
                return (false, "PostgREST phản hồi HTTP \(restHttp.statusCode): \(bodyStr)")
            }
        } catch {
            return (false, "Lỗi kiểm tra PostgREST: \(error.localizedDescription)")
        }
    }
    
    /// Kiểm tra trạng thái tồn tại của các bảng cốt lõi
    public func checkDatabaseTables() async -> (allExist: Bool, missing: [String]) {
        let tables = ["accounts", "trades", "executions", "playbooks", "prop_accounts"]
        var missing: [String] = []
        
        for table in tables {
            do {
                let req = try makeRequest(endpoint: "\(table)?limit=1")
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    missing.append(table)
                } else if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    let err = try? JSONDecoder().decode(PostgrestErrorPayload.self, from: data)
                    if err?.code == "42P01" || (err?.message?.contains("does not exist") ?? false) {
                        missing.append(table)
                    }
                }
            } catch {
                missing.append(table)
            }
        }
        
        return (missing.isEmpty, missing)
    }
    
    // MARK: - Email & Password Authentication (Native Không Cần Trình Duyệt Web)
    
    public func loginWithEmail(email: String, password: String) async throws -> String {
        guard isConfigured else { throw SupabaseError.notConfigured }
        guard let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=password") else {
            throw SupabaseError.invalidUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let payload = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.networkError("Không nhận được phản hồi từ Supabase.")
        }
        
        guard (200...299).contains(http.statusCode) else {
            let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = errJson?["error_description"] as? String ?? errJson?["msg"] as? String ?? "Đăng nhập thất bại (HTTP \(http.statusCode))"
            throw SupabaseError.unauthorized(message: errMsg)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw SupabaseError.unauthorized(message: "Không tìm thấy access token trong phản hồi.")
        }
        
        self.accessToken = token
        UserDefaults.standard.set(token, forKey: "supabase_access_token")
        return token
    }
    
    public func logout() {
        self.accessToken = nil
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
    }
    
    // MARK: - Web OAuth Login Helper
    
    /// Đăng nhập qua trình duyệt web an toàn (Google, GitHub, Apple) để lấy Session Token
    @MainActor
    public func startWebOAuthLogin(provider: String = "google") async throws -> String {
        guard !supabaseUrl.isEmpty else { throw SupabaseError.notConfigured }
        let callbackScheme = "tradejournal"
        let authUrlStr = "\(supabaseUrl)/auth/v1/authorize?provider=\(provider)&redirect_to=\(callbackScheme)://auth-callback"
        guard let authUrl = URL(string: authUrlStr) else { throw SupabaseError.invalidUrl }
        
        let callbackUrl = try await WebAuthHelper.shared.startSession(url: authUrl, callbackScheme: callbackScheme)
        
        // Trích xuất access_token từ URL hash (VD: tradejournal://auth-callback#access_token=...&refresh_token=...)
        guard let fragment = callbackUrl.fragment, !fragment.isEmpty else {
            throw SupabaseError.unauthorized(message: "Không tìm thấy token trong phản hồi xác thực.")
        }
        
        var params: [String: String] = [:]
        for item in fragment.components(separatedBy: "&") {
            let pair = item.components(separatedBy: "=")
            if pair.count == 2 {
                params[pair[0]] = pair[1].removingPercentEncoding ?? pair[1]
            }
        }
        
        guard let token = params["access_token"], !token.isEmpty else {
            throw SupabaseError.unauthorized(message: "Access token không có trong callback URL.")
        }
        
        self.accessToken = token
        UserDefaults.standard.set(token, forKey: "supabase_access_token")
        return token
    }
    
    // MARK: - SQL Migration Script Generator
    
    /// Tạo mã SQL hoàn chỉnh 1:1 từ `schema.pg.ts` và `0000_ancient_starjammers.sql`
    /// để người dùng có thể dán trực tiếp vào Supabase SQL Editor và chạy khởi tạo
    public func generateDatabaseInitSql() -> String {
        return """
        -- ========================================================
        -- Trade Journal: Supabase PostgreSQL DDL Initialization
        -- Port 1:1 từ schema.pg.ts và drizzle migrations
        -- ========================================================

        CREATE TABLE IF NOT EXISTS "accounts" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "broker" text DEFAULT '' NOT NULL,
            "kind" text DEFAULT 'trading' NOT NULL,
            "currency" text DEFAULT 'USD' NOT NULL,
            "initial_balance" double precision DEFAULT 0 NOT NULL,
            "profit_calc_method" text DEFAULT 'fifo' NOT NULL,
            "credentials_enc" text,
            "auto_sync" boolean DEFAULT false NOT NULL,
            "last_sync_at" text,
            "ibkr_sync_time_zone" text,
            "snapshot_json" text,
            "archived_at" text,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "executions" (
            "id" text PRIMARY KEY NOT NULL,
            "account_id" text NOT NULL,
            "symbol" text NOT NULL,
            "side" text NOT NULL,
            "quantity" double precision NOT NULL,
            "price" double precision NOT NULL,
            "fee" double precision DEFAULT 0 NOT NULL,
            "executed_at" text NOT NULL,
            "asset_class" text,
            "source" text NOT NULL,
            "import_metadata_json" text,
            "content_hash" text NOT NULL,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "trades" (
            "key" text PRIMARY KEY NOT NULL,
            "account_id" text NOT NULL,
            "symbol" text NOT NULL,
            "asset_class" text,
            "direction" text NOT NULL,
            "status" text NOT NULL,
            "opened_at" text NOT NULL,
            "closed_at" text,
            "quantity" double precision NOT NULL,
            "open_quantity" double precision DEFAULT 0 NOT NULL,
            "avg_entry" double precision NOT NULL,
            "avg_exit" double precision,
            "gross_pnl" double precision DEFAULT 0 NOT NULL,
            "fees" double precision DEFAULT 0 NOT NULL,
            "net_pnl" double precision DEFAULT 0 NOT NULL,
            "execution_count" integer DEFAULT 0 NOT NULL,
            "execution_ids_json" text NOT NULL,
            "exits_json" text NOT NULL,
            "duration_ms" bigint,
            "notes" text,
            "tags_json" text,
            "mistakes_json" text,
            "playbook_id" text,
            "rating" integer,
            "stop_loss" double precision,
            "profit_target" double precision,
            "reviewed_at" text
        );

        CREATE TABLE IF NOT EXISTS "folders" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "kind" text DEFAULT 'user' NOT NULL,
            "created_at" text NOT NULL,
            "deleted_at" text
        );

        CREATE TABLE IF NOT EXISTS "notes" (
            "id" text PRIMARY KEY NOT NULL,
            "folder_id" text NOT NULL,
            "title" text NOT NULL,
            "content" text NOT NULL,
            "tags_json" text,
            "pinned" boolean DEFAULT false NOT NULL,
            "archived" boolean DEFAULT false NOT NULL,
            "created_at" text NOT NULL,
            "updated_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "playbooks" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "description" text NOT NULL,
            "rules_json" text NOT NULL,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "prop_accounts" (
            "id" text PRIMARY KEY NOT NULL,
            "firm" text NOT NULL,
            "name" text NOT NULL,
            "program" text NOT NULL,
            "status" text NOT NULL,
            "currency" text NOT NULL,
            "size_minor" bigint NOT NULL,
            "opened_on" text NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "archived" boolean DEFAULT false NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "prop_entries" (
            "id" text PRIMARY KEY NOT NULL,
            "firm" text NOT NULL,
            "account_id" text,
            "kind" text NOT NULL,
            "amount_minor" bigint NOT NULL,
            "currency" text NOT NULL,
            "incurred_on" text NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "receipt_id" text
        );

        CREATE TABLE IF NOT EXISTS "prop_receipts" (
            "id" text PRIMARY KEY NOT NULL,
            "firm" text NOT NULL,
            "account_id" text,
            "net_amount_minor" bigint NOT NULL,
            "currency" text NOT NULL,
            "received_on" text NOT NULL,
            "notes" text DEFAULT '' NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "settings" (
            "key" text PRIMARY KEY NOT NULL,
            "value" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "journal_days" (
            "date" text PRIMARY KEY NOT NULL,
            "note" text DEFAULT '' NOT NULL,
            "updated_at" text NOT NULL
        );

        -- Bật RLS và cấp quyền cho anon & authenticated
        ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE executions ENABLE ROW LEVEL SECURITY;
        ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
        ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
        ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
        ALTER TABLE playbooks ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_entries ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_receipts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
        ALTER TABLE journal_days ENABLE ROW LEVEL SECURITY;

        CREATE POLICY "Allow All For Anon" ON accounts FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON executions FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON trades FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON folders FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON notes FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON playbooks FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON prop_accounts FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON prop_entries FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON prop_receipts FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON settings FOR ALL USING (true);
        CREATE POLICY "Allow All For Anon" ON journal_days FOR ALL USING (true);
        """
    }
    
    // MARK: - API Operations
    
    public func fetchAccounts() async throws -> [Account] {
        guard isConfigured else { return [] }
        let endpoint = "accounts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([Account].self, from: data)
    }
    
    public func fetchExecutions(accountId: String? = nil) async throws -> [Execution] {
        guard isConfigured else { return [] }
        let endpoint: String
        if let acc = accountId, !acc.isEmpty {
            endpoint = "executions?account_id=eq.\(acc)&select=*"
        } else {
            endpoint = "executions?select=*"
        }
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = try jsonDecoder.decode([SupabaseExecutionRecord].self, from: data)
        return records.map { $0.toExecution() }
    }
    
    public func upsertExecutions(_ items: [Execution]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseExecutionRecord(execution: $0) }
        let body = try jsonEncoder.encode(dtos)
        let endpoint = "executions"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchTrades(accountId: String? = nil) async throws -> [Trade] {
        guard isConfigured else { return [] }
        let endpoint: String
        if let acc = accountId, !acc.isEmpty {
            endpoint = "trades?account_id=eq.\(acc)&select=*"
        } else {
            endpoint = "trades?select=*"
        }
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = try jsonDecoder.decode([SupabaseTradeRecord].self, from: data)
        return records.map { $0.toTrade() }
    }

    public func upsertTrades(_ items: [Trade]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseTradeRecord(trade: $0) }
        let body = try jsonEncoder.encode(dtos)
        let endpoint = "trades"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }

    public func fetchPlaybooks() async throws -> [Playbook] {
        guard isConfigured else { return [] }
        let endpoint = "playbooks?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        let records = try jsonDecoder.decode([SupabasePlaybookRecord].self, from: data)
        return records.map { $0.toPlaybook() }
    }

    public func upsertPlaybooks(_ items: [Playbook]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePlaybookRecord(playbook: $0) }
        let body = try jsonEncoder.encode(dtos)
        let endpoint = "playbooks"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchSettings() async throws -> [JournalSettingRecord] {
        guard isConfigured else { return [] }
        let endpoint = "settings?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([JournalSettingRecord].self, from: data)
    }
    
    public func upsertSettings(_ items: [JournalSettingRecord]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "settings"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    // MARK: - Prop Firms Sync
    
    public func fetchPropAccounts() async throws -> [PropAccountItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_accounts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([PropAccountItem].self, from: data)
    }
    
    public func upsertPropAccounts(_ items: [PropAccountItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "prop_accounts"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchPropEntries() async throws -> [PropEntryItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_entries?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([PropEntryItem].self, from: data)
    }
    
    public func upsertPropEntries(_ items: [PropEntryItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "prop_entries"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchPropReceipts() async throws -> [PropReceiptItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_receipts?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([PropReceiptItem].self, from: data)
    }
    
    public func upsertPropReceipts(_ items: [PropReceiptItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "prop_receipts"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func fetchPropAudits() async throws -> [PropAuditItem] {
        guard isConfigured else { return [] }
        let endpoint = "prop_audit?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([PropAuditItem].self, from: data)
    }
    
    public func upsertPropAudits(_ items: [PropAuditItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "prop_audit"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    // MARK: - Attachments & Storage
    
    public func fetchAttachments() async throws -> [Attachment] {
        guard isConfigured else { return [] }
        let endpoint = "attachments?select=*"
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
        return try jsonDecoder.decode([Attachment].self, from: data)
    }
    
    public func upsertAttachments(_ items: [Attachment]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let body = try jsonEncoder.encode(items)
        let endpoint = "attachments"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
    }
    
    public func uploadAttachmentFile(storagePath: String, data: Data, mime: String) async throws {
        guard isConfigured else { return }
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/journal-attachments/\(storagePath)") else {
            throw SupabaseError.invalidUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        
        let (respData, response) = try await session.data(for: request)
        try validateResponse(response, data: respData, endpoint: "storage/upload")
    }
    
    public func deleteAttachmentFile(storagePath: String) async throws {
        guard isConfigured else { return }
        guard let url = URL(string: "\(supabaseUrl)/storage/v1/object/journal-attachments/\(storagePath)") else {
            throw SupabaseError.invalidUrl
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (respData, response) = try await session.data(for: request)
        try validateResponse(response, data: respData, endpoint: "storage/delete")
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
