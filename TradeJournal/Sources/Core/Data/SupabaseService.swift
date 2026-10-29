import Foundation

/// Detailed error from Supabase PostgREST API for precise diagnostics
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
            return "Supabase Project URL and Anon Key are not configured."
        case .invalidUrl:
            return "Invalid Supabase Project URL format."
        case .tableNotFound(let table, let msg):
            return "Table '\(table)' does not exist on Supabase PostgreSQL (\(msg)). Run the migration DDL SQL in the Supabase SQL Editor."
        case .unauthorized(let msg):
            return "Authentication error (HTTP 401): \(msg). Please verify your Anon Key or JWT Access Token."
        case .rlsBlocked(let table, let msg):
            return "Blocked by Row Level Security (RLS) on table '\(table)' (HTTP 403: \(msg)). Add an RLS policy or use the Service Role Key."
        case .postgrestError(let code, let pgCode, let msg, let hint):
            var res = "Supabase HTTP error \(code)"
            if let p = pgCode, !p.isEmpty { res += " (Code: \(p))" }
            res += ": \(msg)"
            if let h = hint, !h.isEmpty { res += " • Hint: \(h)" }
            return res
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .decodingError(let msg):
            return "Data decoding error from Supabase: \(msg)"
        }
    }
}

/// Standard error response payload from Supabase PostgREST
internal struct PostgrestErrorPayload: Decodable {
    let code: String?
    let details: String?
    let hint: String?
    let message: String?
}

/// Service connecting directly to Supabase PostgreSQL via PostgREST API.
/// Supports Auth, Multi-tenancy RLS, and bi-directional synchronization.
/// Acts as Facade coordinating TradeSync, PropFirmSync, JournalSync, StorageService, and MigrationHelper.
public final class SupabaseService {
    public static let shared = SupabaseService()
    
    // Dynamic Supabase configuration loaded securely from Keychain, Environment, or Info.plist
    public static var defaultSupabaseUrl: String {
        if let envUrl = ProcessInfo.processInfo.environment["SUPABASE_URL"], !envUrl.isEmpty {
            return envUrl
        }
        if let bundleUrl = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String, !bundleUrl.isEmpty {
            return bundleUrl
        }
        return ""
    }
    
    public static var defaultSupabaseAnonKey: String {
        if let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let bundleKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !bundleKey.isEmpty {
            return bundleKey
        }
        return ""
    }
    
    public var supabaseUrl: String = ""
    public var supabaseAnonKey: String = ""
    public var accessToken: String? = nil
    
    internal let session = URLSession.shared
    
    public var isConfigured: Bool {
        !supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
        !supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private init() {
        // Load credentials with preference for hardware-encrypted Keychain
        let kcUrl = KeychainManager.get(forKey: "supabase_url") ?? ""
        let kcKey = KeychainManager.get(forKey: "supabase_anon_key") ?? ""
        let kcToken = KeychainManager.get(forKey: "supabase_access_token")
        
        let savedUrl = kcUrl.isEmpty ? (UserDefaults.standard.string(forKey: "supabase_url") ?? "") : kcUrl
        let savedKey = kcKey.isEmpty ? (UserDefaults.standard.string(forKey: "supabase_anon_key") ?? "") : kcKey
        let savedToken = kcToken ?? UserDefaults.standard.string(forKey: "supabase_access_token")
        
        // Migrate legacy plain text to Keychain and remove from unencrypted UserDefaults
        if !savedUrl.isEmpty && kcUrl.isEmpty {
            KeychainManager.set(savedUrl, forKey: "supabase_url")
            UserDefaults.standard.removeObject(forKey: "supabase_url")
        }
        if !savedKey.isEmpty && kcKey.isEmpty {
            KeychainManager.set(savedKey, forKey: "supabase_anon_key")
            UserDefaults.standard.removeObject(forKey: "supabase_anon_key")
        }
        if let t = savedToken, kcToken == nil {
            KeychainManager.set(t, forKey: "supabase_access_token")
            UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        }
        
        self.supabaseUrl = savedUrl.isEmpty ? Self.defaultSupabaseUrl : savedUrl
        self.supabaseAnonKey = savedKey.isEmpty ? Self.defaultSupabaseAnonKey : savedKey
        self.accessToken = savedToken
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
        
        // Save securely to Keychain
        if !cleanUrl.isEmpty {
            KeychainManager.set(cleanUrl, forKey: "supabase_url")
        } else {
            KeychainManager.delete(forKey: "supabase_url")
        }
        
        if !cleanKey.isEmpty {
            KeychainManager.set(cleanKey, forKey: "supabase_anon_key")
        } else {
            KeychainManager.delete(forKey: "supabase_anon_key")
        }
        
        if let t = self.accessToken, !t.isEmpty {
            KeychainManager.set(t, forKey: "supabase_access_token")
        } else {
            KeychainManager.delete(forKey: "supabase_access_token")
        }
        
        // Remove from unencrypted UserDefaults
        UserDefaults.standard.removeObject(forKey: "supabase_url")
        UserDefaults.standard.removeObject(forKey: "supabase_anon_key")
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
    }
    
    internal func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil, preferMerge: Bool = false) throws -> URLRequest {
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
    
    /// Validates HTTP status and parses PostgREST error messages
    internal func validateResponse(_ response: URLResponse, data: Data, endpoint: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.networkError("No HTTP response received from Supabase.")
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
    
    internal var jsonDecoder: JSONDecoder {
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
    
    internal var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    /// Resilient array decoding supporting both arrays and single JSON objects
    public func decodeArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        if data.isEmpty { return [] }
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str == "null" || str == "[]" || str.isEmpty {
            return []
        }
        
        // Try standard array decoding
        if let decoded = try? jsonDecoder.decode([T].self, from: data) {
            return decoded
        }
        
        // Try single object decoding wrapped into array
        if let singleItem = try? jsonDecoder.decode(T.self, from: data) {
            return [singleItem]
        }
        
        // Fallback to row-by-row parsing skipping malformed records
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
                AppLogger.warning("SupabaseService: Skipped 1 invalid row of \(T.self): \(error.localizedDescription)")
            }
        }
        return results
    }
    
    // MARK: - PostgREST Batching & Dynamic Schema Resilience
    
    /// Tracks missing columns reported by PostgREST schema cache to strip them automatically in fallback retries
    private var missingColumnsByEndpoint: [String: Set<String>] = [:]
    
    internal func extractMissingColumn(from message: String) -> String? {
        // e.g. "Could not find the 'swap' column of 'trades' in the schema cache"
        let pattern = #"Could not find the '([^']+)' column"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return String(message[range])
    }
    
    /// Normalizes a JSON dictionary array so that every object has the exact same set of keys (with NSNull for nil values)
    internal func normalizeJsonArrayForPostgrest(_ jsonArray: [[String: Any]]) throws -> Data {
        guard !jsonArray.isEmpty else { return Data("[]".utf8) }
        
        var allKeys = Set<String>()
        for dict in jsonArray {
            for key in dict.keys {
                allKeys.insert(key)
            }
        }
        
        var normalizedArray: [[String: Any]] = []
        normalizedArray.reserveCapacity(jsonArray.count)
        for var dict in jsonArray {
            for key in allKeys {
                if dict[key] == nil {
                    dict[key] = NSNull()
                }
            }
            normalizedArray.append(dict)
        }
        
        return try JSONSerialization.data(withJSONObject: normalizedArray, options: [])
    }
    
    /// Encodes and normalizes a batch of records for PostgREST bulk upsert
    internal func encodeNormalizedBatch<T: Encodable>(_ items: [T]) throws -> Data {
        let rawData = try jsonEncoder.encode(items)
        guard let jsonArray = try JSONSerialization.jsonObject(with: rawData, options: []) as? [[String: Any]],
              !jsonArray.isEmpty else {
            return rawData
        }
        return try normalizeJsonArrayForPostgrest(jsonArray)
    }
    
    /// Executes bulk upsert in chunks of 200 items, with automatic schema-resilient column stripping
    /// when remote Supabase database is missing new schema columns (e.g. 'swap').
    internal func upsertBatches<T: Encodable>(endpoint: String, items: [T], batchSize: Int = 200) async throws {
        guard isConfigured, !items.isEmpty else { return }
        
        let endpointName = endpoint.components(separatedBy: "?").first ?? endpoint
        let chunks = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }
        
        for chunk in chunks {
            let rawData = try jsonEncoder.encode(chunk)
            guard var jsonArray = try JSONSerialization.jsonObject(with: rawData, options: []) as? [[String: Any]] else {
                continue
            }
            
            // 1. Strip known missing columns for this endpoint from previous schema cache misses
            if let knownMissing = missingColumnsByEndpoint[endpointName] {
                for i in jsonArray.indices {
                    for col in knownMissing {
                        jsonArray[i].removeValue(forKey: col)
                    }
                }
            }
            
            // 2. Post batch with dynamic fallback retry on column schema cache miss
            var retryCount = 0
            while retryCount < 5 {
                let body = try normalizeJsonArrayForPostgrest(jsonArray)
                let request = try makeRequest(endpoint: endpoint, method: "POST", body: body, preferMerge: true)
                let (data, response) = try await session.data(for: request)
                
                do {
                    try validateResponse(response, data: data, endpoint: endpoint)
                    break // Successfully synced batch
                } catch {
                    let errMsg = error.localizedDescription
                    if let missingCol = extractMissingColumn(from: errMsg) {
                        AppLogger.warning("Supabase: Remote table '\(endpointName)' is missing column '\(missingCol)'. Stripping from payload and retrying...")
                        if missingColumnsByEndpoint[endpointName] == nil {
                            missingColumnsByEndpoint[endpointName] = Set<String>()
                        }
                        missingColumnsByEndpoint[endpointName]?.insert(missingCol)
                        for i in jsonArray.indices {
                            jsonArray[i].removeValue(forKey: missingCol)
                        }
                        retryCount += 1
                        continue
                    } else if endpointName == "prop_audit" && (errMsg.contains("row-level security") || errMsg.contains("RLS") || errMsg.contains("403")) {
                        // Tolerate remote prop_audit RLS restriction without aborting the sync
                        AppLogger.warning("Supabase: prop_audit skipped due to remote RLS policy: \(errMsg)")
                        break
                    } else {
                        throw error
                    }
                }
            }
        }
    }
    
    // MARK: - Health Check & Diagnostics
    
    public func pingConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Please provide both Supabase Project URL and Anon Key.")
        }
        
        // Check Auth service health endpoint
        guard let authSettingsUrl = URL(string: "\(supabaseUrl)/auth/v1/settings") else {
            return (false, "Invalid Project URL format: \(supabaseUrl)")
        }
        
        var authReq = URLRequest(url: authSettingsUrl)
        authReq.httpMethod = "GET"
        authReq.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (authData, authResp) = try await session.data(for: authReq)
            guard let authHttp = authResp as? HTTPURLResponse else {
                return (false, "No network response received from Supabase.")
            }
            
            if authHttp.statusCode == 401 {
                return (false, "Error 401: Invalid Anon Key for this Project URL. Check Supabase Dashboard -> Project Settings -> API.")
            }
            
            if !(200...299).contains(authHttp.statusCode) {
                let errStr = String(data: authData, encoding: .utf8) ?? ""
                return (false, "Supabase HTTP error \(authHttp.statusCode): \(errStr)")
            }
        } catch {
            return (false, "Cannot connect to Project URL: \(error.localizedDescription). Please check your network connection or URL.")
        }
        
        // Check PostgREST API access and schema presence
        guard let restUrl = URL(string: "\(supabaseUrl)/rest/v1/accounts?select=id&limit=1") else {
            return (false, "PostgREST URL is not properly formatted.")
        }
        
        var restReq = URLRequest(url: restUrl)
        restReq.httpMethod = "GET"
        restReq.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        restReq.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (restData, restResp) = try await session.data(for: restReq)
            guard let restHttp = restResp as? HTTPURLResponse else {
                return (false, "No response received from PostgREST server.")
            }
            
            if (200...299).contains(restHttp.statusCode) {
                return (true, "Supabase connection verified successfully! 'accounts' table and schema are ready to sync.")
            } else if restHttp.statusCode == 404 {
                let err = try? JSONDecoder().decode(PostgrestErrorPayload.self, from: restData)
                if err?.code == "42P01" || (err?.message?.contains("does not exist") ?? true) {
                    return (true, "URL and Anon Key authenticated successfully! Database is missing 'accounts' table (Code 42P01). Click 'Copy Schema SQL' and execute in Supabase SQL Editor.")
                }
                return (false, "'accounts' table not found: \(err?.message ?? "HTTP 404")")
            } else if restHttp.statusCode == 403 {
                return (true, "URL and Anon Key authenticated successfully! Row Level Security (RLS) is active. Please add RLS policies to allow access.")
            } else {
                let bodyStr = String(data: restData, encoding: .utf8) ?? ""
                return (false, "PostgREST returned HTTP \(restHttp.statusCode): \(bodyStr)")
            }
        } catch {
            return (false, "PostgREST check error: \(error.localizedDescription)")
        }
    }
    
    /// Verifies whether core database tables exist in Supabase
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
    
    // MARK: - Auth Operations
    
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
            throw SupabaseError.networkError("No response received from Supabase.")
        }
        
        guard (200...299).contains(http.statusCode) else {
            let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = errJson?["error_description"] as? String ?? errJson?["msg"] as? String ?? "Login failed (HTTP \(http.statusCode))"
            throw SupabaseError.unauthorized(message: errMsg)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw SupabaseError.unauthorized(message: "Access token not found in response.")
        }
        
        self.accessToken = token
        KeychainManager.set(token, forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        return token
    }
    
    public func logout() {
        self.accessToken = nil
        KeychainManager.delete(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
    }
    
    // MARK: - Web OAuth Login Helper
    
    /// Initiates PKCE / OAuth web flow with external identity providers
    @MainActor
    public func startWebOAuthLogin(provider: String = "google") async throws -> String {
        guard !supabaseUrl.isEmpty else { throw SupabaseError.notConfigured }
        let callbackScheme = "tradejournal"
        let authUrlStr = "\(supabaseUrl)/auth/v1/authorize?provider=\(provider)&redirect_to=\(callbackScheme)://auth-callback"
        guard let authUrl = URL(string: authUrlStr) else { throw SupabaseError.invalidUrl }
        
        let callbackUrl = try await WebAuthHelper.shared.startSession(url: authUrl, callbackScheme: callbackScheme)
        
        // Extract access token from URL fragment
        guard let fragment = callbackUrl.fragment, !fragment.isEmpty else {
            throw SupabaseError.unauthorized(message: "Token not found in authentication response.")
        }
        
        var params: [String: String] = [:]
        for item in fragment.components(separatedBy: "&") {
            let pair = item.components(separatedBy: "=")
            if pair.count == 2 {
                params[pair[0]] = pair[1].removingPercentEncoding ?? pair[1]
            }
        }
        
        guard let token = params["access_token"], !token.isEmpty else {
            throw SupabaseError.unauthorized(message: "Access token not present in callback URL.")
        }
        
        self.accessToken = token
        KeychainManager.set(token, forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        return token
    }
}
