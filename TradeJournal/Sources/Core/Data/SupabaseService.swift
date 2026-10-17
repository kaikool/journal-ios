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
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let dateStr = try? container.decode(String.self) {
                if let d = FlexibleDateParser.parse(dateStr) {
                    return d
                }
                return Date()
            }
            if let timestamp = try? container.decode(Double.self) {
                if timestamp > 1_000_000_000_000 {
                    return Date(timeIntervalSince1970: timestamp / 1000.0)
                }
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date()
        }
        return decoder
    }
    
    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    /// Giải mã mảng dữ liệu PostgREST với khả năng phục hồi lỗi tối đa (Permissive Decoder)
    /// Đảm bảo không bao giờ ném DecodingError.keyNotFound hoặc valueNotFound làm sập luồng đồng bộ.
    public func decodeArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        if data.isEmpty { return [] }
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str == "null" || str == "[]" || str.isEmpty {
            return []
        }
        
        // Fast path: Thử parse toàn bộ mảng
        if let decoded = try? jsonDecoder.decode([T].self, from: data) {
            return decoded
        }
        
        // Nếu PostgREST trả về 1 object đơn lẻ thay vì mảng
        if let singleItem = try? jsonDecoder.decode(T.self, from: data) {
            return [singleItem]
        }
        
        // Lossy path: Parse từng bản ghi độc lập để 1 dòng lỗi không vứt bỏ toàn bộ hàng trăm bản ghi khác
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var results: [T] = []
        for itemDict in jsonArray {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: itemDict)
                let item = try jsonDecoder.decode(T.self, from: itemData)
                results.append(item)
            } catch {
                AppLogger.warning("SupabaseService: Bỏ qua 1 dòng không hợp lệ của \(T.self): \(error.localizedDescription)")
            }
        }
        return results
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
            "size_minor" bigint,
            "parent_id" text,
            "journal_account_id" text,
            "opened_on" text NOT NULL,
            "closed_on" text,
            "renewal_on" text,
            "renewal_minor" bigint,
            "notes" text DEFAULT '' NOT NULL,
            "archived" boolean DEFAULT false NOT NULL,
            "revision" integer DEFAULT 1 NOT NULL,
            "created_at" text,
            "updated_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_entries" (
            "id" text PRIMARY KEY NOT NULL,
            "account_id" text,
            "firm" text NOT NULL,
            "kind" text NOT NULL,
            "category" text DEFAULT '' NOT NULL,
            "currency" text NOT NULL,
            "amount_minor" bigint NOT NULL,
            "split_bps" integer DEFAULT 8000 NOT NULL,
            "fee_minor" bigint DEFAULT 0 NOT NULL,
            "occurred_on" text NOT NULL,
            "due_on" text,
            "status" text DEFAULT 'completed' NOT NULL,
            "parent_id" text,
            "reference" text DEFAULT '' NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "voided" boolean DEFAULT false NOT NULL,
            "revision" integer DEFAULT 1 NOT NULL,
            "created_at" text,
            "updated_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_receipts" (
            "id" text PRIMARY KEY NOT NULL,
            "payout_id" text DEFAULT '' NOT NULL,
            "kind" text DEFAULT 'payout' NOT NULL,
            "amount_minor" bigint DEFAULT 0 NOT NULL,
            "occurred_on" text NOT NULL,
            "reference" text DEFAULT '' NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "voided" boolean DEFAULT false NOT NULL,
            "created_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_audit" (
            "id" text PRIMARY KEY NOT NULL,
            "entity_type" text NOT NULL,
            "entity_id" text NOT NULL,
            "before_json" text,
            "after_json" text NOT NULL,
            "reason" text NOT NULL,
            "created_at" text
        );

        CREATE TABLE IF NOT EXISTS "attachments" (
            "id" text PRIMARY KEY NOT NULL,
            "owner_type" text NOT NULL,
            "owner_id" text NOT NULL,
            "name" text NOT NULL,
            "mime" text NOT NULL,
            "size" integer NOT NULL,
            "storage_path" text NOT NULL,
            "status" text DEFAULT 'ready' NOT NULL,
            "created_at" text
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

        -- Tự động vá bổ sung các cột nếu bảng đã được tạo trước đó
        DO $$
        BEGIN
            -- accounts
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS broker text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS kind text DEFAULT 'trading' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS currency text DEFAULT 'USD' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS initial_balance double precision DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS profit_calc_method text DEFAULT 'fifo' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS auto_sync boolean DEFAULT false NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS last_sync_at text;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS archived_at text;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS created_at text DEFAULT '';

            -- executions
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS asset_class text;
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS fee double precision DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS import_metadata_json text;

            -- trades
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS asset_class text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS duration_ms bigint;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS notes text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS tags_json text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS mistakes_json text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS playbook_id text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS rating integer;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS stop_loss double precision;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS profit_target double precision;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS reviewed_at text;

            -- prop_entries
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS category text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS split_bps integer DEFAULT 8000 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS fee_minor bigint DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS occurred_on text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS due_on text;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS status text DEFAULT 'completed' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS reference text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS voided boolean DEFAULT false NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS revision integer DEFAULT 1 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS created_at text;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS updated_at text;

            -- prop_receipts
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS payout_id text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS kind text DEFAULT 'payout' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS amount_minor bigint DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS occurred_on text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS reference text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS voided boolean DEFAULT false NOT NULL;
        END $$;

        -- Gỡ bỏ các chính sách RLS hạn chế cũ nếu có (từ schema user_id)
        DROP POLICY IF EXISTS "Users can only manage own accounts" ON accounts;
        DROP POLICY IF EXISTS "Users can only manage own executions" ON executions;
        DROP POLICY IF EXISTS "Users can only manage own trades" ON trades;
        DROP POLICY IF EXISTS "Users can only manage own folders" ON folders;
        DROP POLICY IF EXISTS "Users can only manage own notes" ON notes;
        DROP POLICY IF EXISTS "Users can only manage own playbooks" ON playbooks;
        DROP POLICY IF EXISTS "Users can only manage own prop_accounts" ON prop_accounts;
        DROP POLICY IF EXISTS "Users can only manage own journal days" ON journal_days;

        -- Bật RLS và cấp quyền cho anon, authenticated và service_role
        ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE executions ENABLE ROW LEVEL SECURITY;
        ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
        ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
        ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
        ALTER TABLE playbooks ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_entries ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_receipts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_audit ENABLE ROW LEVEL SECURITY;
        ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
        ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
        ALTER TABLE journal_days ENABLE ROW LEVEL SECURITY;

        DROP POLICY IF EXISTS "Allow All For Anon" ON accounts;
        CREATE POLICY "Allow All For Anon" ON accounts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON executions;
        CREATE POLICY "Allow All For Anon" ON executions FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON trades;
        CREATE POLICY "Allow All For Anon" ON trades FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON folders;
        CREATE POLICY "Allow All For Anon" ON folders FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON notes;
        CREATE POLICY "Allow All For Anon" ON notes FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON playbooks;
        CREATE POLICY "Allow All For Anon" ON playbooks FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_accounts;
        CREATE POLICY "Allow All For Anon" ON prop_accounts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_entries;
        CREATE POLICY "Allow All For Anon" ON prop_entries FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_receipts;
        CREATE POLICY "Allow All For Anon" ON prop_receipts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_audit;
        CREATE POLICY "Allow All For Anon" ON prop_audit FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON attachments;
        CREATE POLICY "Allow All For Anon" ON attachments FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON settings;
        CREATE POLICY "Allow All For Anon" ON settings FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON journal_days;
        CREATE POLICY "Allow All For Anon" ON journal_days FOR ALL USING (true) WITH CHECK (true);

        -- Cấp toàn quyền truy cập bảng cho anon và authenticated
        GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
        """
    }
    
    // MARK: - API Operations
    
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
        let body = try jsonEncoder.encode(dtos)
        let endpoint = "accounts"
        let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data, endpoint: endpoint)
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
        let records = decodeArray(SupabaseExecutionRecord.self, from: data)
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
        let records = decodeArray(SupabaseTradeRecord.self, from: data)
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
        let records = decodeArray(SupabasePlaybookRecord.self, from: data)
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
        return decodeArray(JournalSettingRecord.self, from: data)
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
        let records = decodeArray(SupabasePropAccountRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropAccounts(_ items: [PropAccountItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropAccountRecord(item: $0) }
        let body = try jsonEncoder.encode(dtos)
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
        let records = decodeArray(SupabasePropEntryRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropEntries(_ items: [PropEntryItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropEntryRecord(item: $0) }
        let body = try jsonEncoder.encode(dtos)
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
        let records = decodeArray(SupabasePropReceiptRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropReceipts(_ items: [PropReceiptItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropReceiptRecord(item: $0) }
        let body = try jsonEncoder.encode(dtos)
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
        let records = decodeArray(SupabasePropAuditRecord.self, from: data)
        return records.map { $0.toItem() }
    }
    
    public func upsertPropAudits(_ items: [PropAuditItem]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabasePropAuditRecord(item: $0) }
        let body = try jsonEncoder.encode(dtos)
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
        let records = decodeArray(SupabaseAttachmentRecord.self, from: data)
        return records.map { $0.toAttachment() }
    }
    
    public func upsertAttachments(_ items: [Attachment]) async throws {
        guard isConfigured, !items.isEmpty else { return }
        let dtos = items.map { SupabaseAttachmentRecord(attachment: $0) }
        let body = try jsonEncoder.encode(dtos)
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

public struct AnyCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeString(forKeys keys: [String]) -> String? {
        for key in keys {
            if let k = AnyCodingKey(stringValue: key), let val = try? decode(String.self, forKey: k) {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
    
    func decodeDouble(forKeys keys: [String]) -> Double? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Double.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Double(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    func decodeInt(forKeys keys: [String]) -> Int? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Int.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Int(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    func decodeInt64(forKeys keys: [String]) -> Int64? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Int64.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Int64(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    func decodeBool(forKeys keys: [String]) -> Bool? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Bool.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k) {
                let s = str.trimmingCharacters(in: .whitespaces).lowercased()
                if s == "true" || s == "1" || s == "yes" { return true }
                if s == "false" || s == "0" || s == "no" { return false }
            }
        }
        return nil
    }
}

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
    
    private enum CodingKeys: String, CodingKey {
        case key, symbol, direction, status, quantity, fees, notes, rating
        case accountId = "account_id"
        case assetClass = "asset_class"
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case openQuantity = "open_quantity"
        case avgEntry = "avg_entry"
        case avgExit = "avg_exit"
        case grossPnl = "gross_pnl"
        case netPnl = "net_pnl"
        case executionCount = "execution_count"
        case executionIdsJson = "execution_ids_json"
        case exitsJson = "exits_json"
        case durationMs = "duration_ms"
        case tagsJson = "tags_json"
        case mistakesJson = "mistakes_json"
        case playbookId = "playbook_id"
        case stopLoss = "stop_loss"
        case profitTarget = "profit_target"
        case reviewedAt = "reviewed_at"
    }
    
    public init(trade: Trade) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.key = c.decodeString(forKeys: ["key", "id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId", "account"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? "UNKNOWN"
        self.assetClass = c.decodeString(forKeys: ["asset_class", "assetClass"])
        self.direction = c.decodeString(forKeys: ["direction", "side"]) ?? "long"
        self.status = c.decodeString(forKeys: ["status"]) ?? "open"
        self.openedAt = c.decodeString(forKeys: ["opened_at", "openedAt", "open_date", "opendate", "open_time", "opentime"]) ?? JournalIds.nowIso()
        self.closedAt = c.decodeString(forKeys: ["closed_at", "closedAt", "close_date", "closedate", "close_time", "closetime"])
        self.quantity = c.decodeDouble(forKeys: ["quantity", "open_quantity", "size", "lots", "volume"]) ?? 0
        self.openQuantity = c.decodeDouble(forKeys: ["open_quantity", "openQuantity"]) ?? 0
        self.avgEntry = c.decodeDouble(forKeys: ["avg_entry", "avgEntry", "open_price", "entry_price", "entry"]) ?? 0
        self.avgExit = c.decodeDouble(forKeys: ["avg_exit", "avgExit", "close_price", "exit_price", "exit"])
        self.grossPnl = c.decodeDouble(forKeys: ["gross_pnl", "grossPnl", "gross"]) ?? 0
        self.fees = c.decodeDouble(forKeys: ["fees", "fee", "commission"]) ?? 0
        self.netPnl = c.decodeDouble(forKeys: ["net_pnl", "netPnl", "profit", "pnl"]) ?? 0
        self.executionCount = c.decodeInt(forKeys: ["execution_count", "executionCount"]) ?? 0
        
        // Hỗ trợ cả string và array cho executionIdsJson
        if let str = c.decodeString(forKeys: ["execution_ids_json", "executionIdsJson", "execution_ids"]) {
            self.executionIdsJson = str
        } else if let arr = (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "execution_ids_json")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "executionIdsJson")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "execution_ids")!)) {
            self.executionIdsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.executionIdsJson = "[]"
        }
        
        // Hỗ trợ cả string và array cho exitsJson
        if let str = c.decodeString(forKeys: ["exits_json", "exitsJson", "exits"]) {
            self.exitsJson = str
        } else if let arr = (try? c.decode([ExitAttribution].self, forKey: AnyCodingKey(stringValue: "exits_json")!)) ??
                            (try? c.decode([ExitAttribution].self, forKey: AnyCodingKey(stringValue: "exitsJson")!)) ??
                            (try? c.decode([ExitAttribution].self, forKey: AnyCodingKey(stringValue: "exits")!)) {
            self.exitsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.exitsJson = "[]"
        }
        
        self.durationMs = c.decodeInt64(forKeys: ["duration_ms", "durationMs"])
        self.notes = c.decodeString(forKeys: ["notes", "note"])
        
        if let str = c.decodeString(forKeys: ["tags_json", "tagsJson", "tags"]) {
            self.tagsJson = str
        } else if let arr = (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "tags_json")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "tagsJson")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "tags")!)) {
            self.tagsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.tagsJson = nil
        }
        
        if let str = c.decodeString(forKeys: ["mistakes_json", "mistakesJson", "mistakes"]) {
            self.mistakesJson = str
        } else if let arr = (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "mistakes_json")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "mistakesJson")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "mistakes")!)) {
            self.mistakesJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.mistakesJson = nil
        }
        
        self.playbookId = c.decodeString(forKeys: ["playbook_id", "playbookId"])
        self.rating = c.decodeInt(forKeys: ["rating"])
        self.stopLoss = c.decodeDouble(forKeys: ["stop_loss", "stopLoss"])
        self.profitTarget = c.decodeDouble(forKeys: ["profit_target", "profitTarget"])
        self.reviewedAt = c.decodeString(forKeys: ["reviewed_at", "reviewedAt"])
    }
    
    public func toTrade() -> Trade {
        let dec = JSONDecoder()
        let parsedOpenedAt = FlexibleDateParser.parse(openedAt) ?? Date()
        let parsedClosedAt = FlexibleDateParser.parse(closedAt)
        let parsedReviewedAt = FlexibleDateParser.parse(reviewedAt)
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
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, side, quantity, price, fee, source
        case accountId = "account_id"
        case executedAt = "executed_at"
        case assetClass = "asset_class"
        case importMetadataJson = "import_metadata_json"
        case contentHash = "content_hash"
        case createdAt = "created_at"
    }
    
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
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId", "account"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? "UNKNOWN"
        self.side = c.decodeString(forKeys: ["side", "direction"]) ?? "buy"
        self.quantity = c.decodeDouble(forKeys: ["quantity", "size", "lots", "volume"]) ?? 0
        self.price = c.decodeDouble(forKeys: ["price", "entry"]) ?? 0
        self.fee = c.decodeDouble(forKeys: ["fee", "commission", "fees"]) ?? 0
        self.executedAt = c.decodeString(forKeys: ["executed_at", "executedAt", "timestamp", "date"]) ?? JournalIds.nowIso()
        self.assetClass = c.decodeString(forKeys: ["asset_class", "assetClass"])
        self.source = c.decodeString(forKeys: ["source"]) ?? "manual"
        self.importMetadataJson = c.decodeString(forKeys: ["import_metadata_json", "importMetadataJson"])
        self.contentHash = c.decodeString(forKeys: ["content_hash", "contentHash"]) ?? UUID().uuidString
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toExecution() -> Execution {
        let parsedDate = FlexibleDateParser.parse(executedAt) ?? Date()
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
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case rulesJson = "rules_json"
        case createdAt = "created_at"
    }
    
    public init(playbook: Playbook) {
        let fmt = ISO8601DateFormatter()
        self.id = playbook.id
        self.name = playbook.name
        self.description = playbook.description
        self.rulesJson = (try? String(data: JSONEncoder().encode(playbook.rules), encoding: .utf8)) ?? "[]"
        self.createdAt = fmt.string(from: playbook.createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Playbook"
        self.description = c.decodeString(forKeys: ["description"]) ?? ""
        if let str = c.decodeString(forKeys: ["rules_json", "rulesJson", "rules"]) {
            self.rulesJson = str
        } else if let arr = (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "rules_json")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "rulesJson")!)) ??
                            (try? c.decode([String].self, forKey: AnyCodingKey(stringValue: "rules")!)) {
            self.rulesJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.rulesJson = "[]"
        }
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toPlaybook() -> Playbook {
        let parsedRules = (try? JSONDecoder().decode([String].self, from: Data(rulesJson.utf8))) ?? []
        return Playbook(
            id: id,
            name: name,
            description: description,
            rules: parsedRules,
            createdAt: FlexibleDateParser.parse(createdAt) ?? Date()
        )
    }
}

public struct SupabaseAccountRecord: Codable {
    public let id: String
    public let name: String
    public let broker: String
    public let kind: String
    public let currency: String
    public let initialBalance: Double
    public let profitCalcMethod: String
    public let autoSync: Bool
    public let lastSyncAt: String?
    public let archivedAt: String?
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, name, broker, kind, currency
        case initialBalance = "initial_balance"
        case profitCalcMethod = "profit_calc_method"
        case autoSync = "auto_sync"
        case lastSyncAt = "last_sync_at"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
    
    public init(account: Account) {
        let fmt = ISO8601DateFormatter()
        self.id = account.id
        self.name = account.name
        self.broker = account.broker
        self.kind = account.kind.rawValue
        self.currency = account.currency
        self.initialBalance = (account.initialBalance as NSDecimalNumber).doubleValue
        self.profitCalcMethod = account.profitCalcMethod.rawValue
        self.autoSync = account.autoSync
        self.lastSyncAt = account.lastSyncAt.map { fmt.string(from: $0) }
        self.archivedAt = account.archivedAt.map { fmt.string(from: $0) }
        self.createdAt = fmt.string(from: account.createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Account"
        self.broker = c.decodeString(forKeys: ["broker"]) ?? ""
        self.kind = c.decodeString(forKeys: ["kind", "type"]) ?? "trading"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.initialBalance = c.decodeDouble(forKeys: ["initial_balance", "initialBalance", "balance", "starting_balance", "startingBalance"]) ?? 0
        self.profitCalcMethod = c.decodeString(forKeys: ["profit_calc_method", "profitCalcMethod"]) ?? "fifo"
        self.autoSync = c.decodeBool(forKeys: ["auto_sync", "autoSync"]) ?? false
        self.lastSyncAt = c.decodeString(forKeys: ["last_sync_at", "lastSyncAt"])
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toAccount() -> Account {
        let parsedLastSync = FlexibleDateParser.parse(lastSyncAt)
        let parsedArchived = FlexibleDateParser.parse(archivedAt)
        let parsedCreated = FlexibleDateParser.parse(createdAt) ?? Date()
        
        return Account(
            id: id,
            name: name,
            broker: broker,
            kind: AccountKind(rawValue: kind) ?? .manual,
            currency: currency,
            initialBalance: Decimal(initialBalance),
            profitCalcMethod: ProfitCalcMethod(rawValue: profitCalcMethod) ?? .fifo,
            autoSync: autoSync,
            lastSyncAt: parsedLastSync,
            archivedAt: parsedArchived,
            createdAt: parsedCreated
        )
    }
}

public struct SupabasePropAccountRecord: Codable {
    public let id: String
    public let firm: String
    public let name: String
    public let program: String
    public let status: String
    public let currency: String
    public let sizeMinor: Int64?
    public let parentId: String?
    public let journalAccountId: String?
    public let openedOn: String
    public let closedOn: String?
    public let renewalOn: String?
    public let renewalMinor: Int64?
    public let notes: String
    public let archived: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, name, program, status, currency, notes, archived, revision
        case sizeMinor = "size_minor"
        case parentId = "parent_id"
        case journalAccountId = "journal_account_id"
        case openedOn = "opened_on"
        case closedOn = "closed_on"
        case renewalOn = "renewal_on"
        case renewalMinor = "renewal_minor"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropAccountItem) {
        self.id = item.id
        self.firm = item.firm
        self.name = item.name
        self.program = item.program.rawValue
        self.status = item.status.rawValue
        self.currency = item.currency
        self.sizeMinor = item.sizeMinor
        self.parentId = item.parentId
        self.journalAccountId = item.journalAccountId
        self.openedOn = item.openedOn
        self.closedOn = item.closedOn
        self.renewalOn = item.renewalOn
        self.renewalMinor = item.renewalMinor
        self.notes = item.notes
        self.archived = item.archived
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        self.name = c.decodeString(forKeys: ["name"]) ?? "Prop Account"
        self.program = c.decodeString(forKeys: ["program"]) ?? "evaluation"
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.sizeMinor = c.decodeInt64(forKeys: ["size_minor", "sizeMinor"])
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.journalAccountId = c.decodeString(forKeys: ["journal_account_id", "journalAccountId"])
        self.openedOn = c.decodeString(forKeys: ["opened_on", "openedOn", "created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.closedOn = c.decodeString(forKeys: ["closed_on", "closedOn"])
        self.renewalOn = c.decodeString(forKeys: ["renewal_on", "renewalOn"])
        self.renewalMinor = c.decodeInt64(forKeys: ["renewal_minor", "renewalMinor"])
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.archived = c.decodeBool(forKeys: ["archived"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func toItem() -> PropAccountItem {
        return PropAccountItem(
            id: id,
            firm: firm,
            name: name,
            program: PropProgram(rawValue: program) ?? .evaluation,
            status: PropStatus(rawValue: status) ?? .active,
            currency: currency,
            sizeMinor: sizeMinor,
            parentId: parentId,
            journalAccountId: journalAccountId,
            openedOn: openedOn,
            closedOn: closedOn,
            renewalOn: renewalOn,
            renewalMinor: renewalMinor,
            notes: notes,
            archived: archived,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropEntryRecord: Codable {
    public let id: String
    public let accountId: String?
    public let firm: String
    public let kind: String
    public let category: String
    public let currency: String
    public let amountMinor: Int64
    public let splitBps: Int
    public let feeMinor: Int64
    public let occurredOn: String
    public let dueOn: String?
    public let status: String
    public let parentId: String?
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, kind, category, currency, reference, notes, voided, revision
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case splitBps = "split_bps"
        case feeMinor = "fee_minor"
        case occurredOn = "occurred_on"
        case incurredOn = "incurred_on"
        case dueOn = "due_on"
        case status
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropEntryItem) {
        self.id = item.id
        self.accountId = item.accountId
        self.firm = item.firm
        self.kind = item.kind
        self.category = item.category
        self.currency = item.currency
        self.amountMinor = item.amountMinor
        self.splitBps = item.splitBps
        self.feeMinor = item.feeMinor
        self.occurredOn = item.occurredOn
        self.dueOn = item.dueOn
        self.status = item.status.rawValue
        self.parentId = item.parentId
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId"])
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        self.kind = c.decodeString(forKeys: ["kind"]) ?? "fee"
        self.category = c.decodeString(forKeys: ["category"]) ?? "eval_fee"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor"]) ?? 0
        self.splitBps = c.decodeInt(forKeys: ["split_bps", "splitBps"]) ?? 8000
        self.feeMinor = c.decodeInt64(forKeys: ["fee_minor", "feeMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "incurred_on", "incurredOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.dueOn = c.decodeString(forKeys: ["due_on", "dueOn"])
        self.status = c.decodeString(forKeys: ["status"]) ?? "completed"
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(accountId, forKey: .accountId)
        try c.encode(firm, forKey: .firm)
        try c.encode(kind, forKey: .kind)
        try c.encode(category, forKey: .category)
        try c.encode(currency, forKey: .currency)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(splitBps, forKey: .splitBps)
        try c.encode(feeMinor, forKey: .feeMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encodeIfPresent(dueOn, forKey: .dueOn)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toItem() -> PropEntryItem {
        return PropEntryItem(
            id: id,
            accountId: accountId,
            firm: firm,
            kind: kind,
            category: category,
            currency: currency,
            amountMinor: amountMinor,
            splitBps: splitBps,
            feeMinor: feeMinor,
            occurredOn: occurredOn,
            dueOn: dueOn,
            status: PayoutStatus(rawValue: status) ?? .completed,
            parentId: parentId,
            reference: reference,
            notes: notes,
            voided: voided,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropReceiptRecord: Codable {
    public let id: String
    public let payoutId: String
    public let kind: String
    public let amountMinor: Int64
    public let occurredOn: String
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, kind, reference, notes, voided
        case payoutId = "payout_id"
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case netAmountMinor = "net_amount_minor"
        case occurredOn = "occurred_on"
        case receivedOn = "received_on"
        case createdAt = "created_at"
    }
    
    public init(item: PropReceiptItem) {
        self.id = item.id
        self.payoutId = item.payoutId
        self.kind = item.kind
        self.amountMinor = item.amountMinor
        self.occurredOn = item.occurredOn
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.payoutId = c.decodeString(forKeys: ["payout_id", "payoutId", "account_id", "accountId"]) ?? ""
        self.kind = c.decodeString(forKeys: ["kind"]) ?? "payout"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor", "net_amount_minor", "netAmountMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "received_on", "receivedOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(payoutId, forKey: .payoutId)
        try c.encode(kind, forKey: .kind)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    public func toItem() -> PropReceiptItem {
        return PropReceiptItem(
            id: id,
            payoutId: payoutId,
            kind: kind,
            amountMinor: amountMinor,
            occurredOn: occurredOn,
            reference: reference,
            notes: notes,
            voided: voided,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropAuditRecord: Codable {
    public let id: String
    public let entityType: String
    public let entityId: String
    public let beforeJson: String?
    public let afterJson: String
    public let reason: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, reason
        case entityType = "entity_type"
        case entityId = "entity_id"
        case beforeJson = "before_json"
        case afterJson = "after_json"
        case createdAt = "created_at"
    }
    
    public init(item: PropAuditItem) {
        self.id = item.id
        self.entityType = item.entityType
        self.entityId = item.entityId
        self.beforeJson = item.beforeJson
        self.afterJson = item.afterJson
        self.reason = item.reason
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.entityType = c.decodeString(forKeys: ["entity_type", "entityType"]) ?? "entry"
        self.entityId = c.decodeString(forKeys: ["entity_id", "entityId"]) ?? ""
        self.beforeJson = c.decodeString(forKeys: ["before_json", "beforeJson"])
        self.afterJson = c.decodeString(forKeys: ["after_json", "afterJson"]) ?? "{}"
        self.reason = c.decodeString(forKeys: ["reason"]) ?? "sync"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toItem() -> PropAuditItem {
        return PropAuditItem(
            id: id,
            entityType: entityType,
            entityId: entityId,
            beforeJson: beforeJson,
            afterJson: afterJson,
            reason: reason,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabaseAttachmentRecord: Codable {
    public let id: String
    public let ownerType: String
    public let ownerId: String
    public let name: String
    public let mime: String
    public let size: Int
    public let storagePath: String
    public let status: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, mime, size, status
        case ownerType = "owner_type"
        case ownerId = "owner_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
    
    public init(attachment: Attachment) {
        self.id = attachment.id
        self.ownerType = attachment.ownerType
        self.ownerId = attachment.ownerId
        self.name = attachment.name
        self.mime = attachment.mime
        self.size = attachment.size
        self.storagePath = attachment.storagePath
        self.status = attachment.status
        self.createdAt = attachment.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.ownerType = c.decodeString(forKeys: ["owner_type", "ownerType"]) ?? "trade"
        self.ownerId = c.decodeString(forKeys: ["owner_id", "ownerId"]) ?? ""
        self.name = c.decodeString(forKeys: ["name"]) ?? "Attachment"
        self.mime = c.decodeString(forKeys: ["mime"]) ?? "image/png"
        self.size = c.decodeInt(forKeys: ["size"]) ?? 0
        self.storagePath = c.decodeString(forKeys: ["storage_path", "storagePath"]) ?? ""
        self.status = c.decodeString(forKeys: ["status"]) ?? "ready"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toAttachment() -> Attachment {
        return Attachment(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            name: name,
            mime: mime,
            size: size,
            storagePath: storagePath,
            status: status,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}
