import Foundation
import CryptoKit

/// Model dữ liệu trả về từ The5ers MCP Protocol (the5ers_account)
/// Model dữ liệu trả về từ The5ers MCP Protocol (the5ers_account)
public struct The5ersMcpAccount: Identifiable, Codable, Sendable {
    public let id: String
    public let ref: String
    public let label: String
    public let platform: String?
    public let balance: Decimal
    public let equity: Decimal?
    public let currency: String
    public let status: String // active, passed, breached, closed
    public let program: String // evaluation, verification, funded, instant_funded
    public let startingBalance: Decimal?
    public let createdAt: String?
    
    public init(
        id: String,
        ref: String? = nil,
        label: String,
        platform: String? = nil,
        balance: Decimal,
        equity: Decimal? = nil,
        currency: String = "USD",
        status: String = "active",
        program: String = "funded",
        startingBalance: Decimal? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.ref = ref ?? id
        self.label = label
        self.platform = platform
        self.balance = balance
        self.equity = equity
        self.currency = currency
        self.status = status
        self.program = program
        self.startingBalance = startingBalance
        self.createdAt = createdAt
    }
}

/// Trình kết nối chính thức với The5ers qua giao thức Model Context Protocol (MCP)
/// Port 1:1 từ `mcp.ts`, `contracts.ts`, và `oauth.ts` tại `source-repo/apps/web/src/server/the5ers/`
public final class The5ersService: ObservableObject {
    public static let shared = The5ersService()
    
    public static let mcpUrl = "https://mcp.the5ers.com/mcp"
    public static let authHost = "https://auth.hub.the5ers.com"
    public static let tenantPath = "P37sOCdLJjVCAuLgqv2zMvS61Xbo/RS3HzAPk1eHIYMvTuvNbOQUYZQOZo"
    public static let protocolVersion = "2025-03-26"
    
    @Published public var mcpToken: String = ""
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncTime: Date? = nil
    @Published public var lastStatus: String = ""
    @Published public var isConnected: Bool = false
    
    private let session = URLSession.shared
    private var rpcIdCounter: Int = 0
    private var mcpSessionId: String? = nil
    private var isSessionInitialized: Bool = false
    
    public var isConfigured: Bool {
        !mcpToken.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private init() {
        self.mcpToken = UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? ""
        self.isConnected = !mcpToken.isEmpty
    }
    
    public func configure(token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean != self.mcpToken {
            self.isSessionInitialized = false
            self.mcpSessionId = nil
        }
        self.mcpToken = clean
        self.isConnected = !self.mcpToken.isEmpty
        UserDefaults.standard.set(self.mcpToken, forKey: "the5ers_mcp_token")
    }
    
    public func disconnect() {
        self.mcpToken = ""
        self.isConnected = false
        self.mcpSessionId = nil
        self.isSessionInitialized = false
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_refresh_token")
    }
    
    // MARK: - 1. OAuth 2.0 PKCE Flow (Official The5ers Hub OAuth)
    
    /// Đăng ký dynamic client RFC 7591 với máy chủ The5ers Descope Hub
    private func getOrRegisterClientId(redirectUri: String) async throws -> String {
        let key = "the5ers_mcp_client_id"
        if let cached = UserDefaults.standard.string(forKey: key), !cached.isEmpty {
            return cached
        }
        
        guard let url = URL(string: "\(Self.authHost)/v1/mgmt/mcp/client/\(Self.tenantPath)/register") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let payload: [String: Any] = [
            "client_name": "Trade Journal iOS",
            "redirect_uris": [redirectUri],
            "response_types": ["code"],
            "grant_types": ["authorization_code", "refresh_token"],
            "token_endpoint_auth_method": "none"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi đăng ký dynamic client: \(err)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi đăng ký The5ers không chứa client_id."])
        }
        
        UserDefaults.standard.set(clientId, forKey: key)
        return clientId
    }
    
    @MainActor
    public func startOAuthLogin() async throws -> String {
        // Tạo PKCE Verifier và Challenge (S256)
        var verifierBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, verifierBytes.count, &verifierBytes)
        let verifier = Data(verifierBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        
        let challengeHash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(challengeHash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        
        let state = UUID().uuidString
        let callbackScheme = "tradejournal"
        let redirectUri = "\(callbackScheme)://the5ers-callback"
        
        let clientId = try await getOrRegisterClientId(redirectUri: redirectUri)
        
        let scopes = [
            "mcp:accounts.read",
            "mcp:balance.read",
            "mcp:performance.read",
            "mcp:positions.read",
            "mcp:programs.read",
            "mcp:consistency.read",
            "mcp:payouts.read",
            "mcp:purchases.read"
        ].joined(separator: " ")
        
        var comp = URLComponents(string: "\(Self.authHost)/oauth2/v1/apps/agentic/\(Self.tenantPath)/authorize")!
        comp.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "resource", value: Self.mcpUrl),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authorizeUrl = comp.url else {
            throw URLError(.badURL)
        }
        
        let callbackUrl = try await WebAuthHelper.shared.startSession(url: authorizeUrl, callbackScheme: callbackScheme)
        
        // Trích xuất mã authorization code từ callback URL
        guard let components = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL phản hồi từ The5ers Hub không hợp lệ."])
        }
        
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            let err = components.queryItems?.first(where: { $0.name == "error_description" || $0.name == "error" })?.value ?? "Không nhận được mã xác thực code từ The5ers Hub."
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
        // Trao đổi token bằng mã code và verifier PKCE
        let token = try await exchangeCodeForToken(code: code, verifier: verifier, clientId: clientId, redirectUri: redirectUri)
        configure(token: token)
        return token
    }
    
    private func exchangeCodeForToken(code: String, verifier: String, clientId: String, redirectUri: String) async throws -> String {
        guard let url = URL(string: "\(Self.authHost)/oauth2/v1/apps/agentic/\(Self.tenantPath)/token") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let bodyParams = [
            "grant_type=authorization_code",
            "client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId)",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri)",
            "code_verifier=\(verifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verifier)",
            "resource=\(Self.mcpUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.mcpUrl)"
        ].joined(separator: "&")
        request.httpBody = bodyParams.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lỗi trao đổi token: \(errStr)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy access_token trong phản hồi The5ers."])
        }
        
        if let refreshToken = json["refresh_token"] as? String {
            UserDefaults.standard.set(refreshToken, forKey: "the5ers_mcp_refresh_token")
        }
        
        return accessToken
    }
    
    // MARK: - 2. JSON-RPC 2.0 MCP Client (`https://mcp.the5ers.com/mcp`)
    
    /// Đảm bảo phiên làm việc MCP đã được bắt tay khởi tạo theo đúng giao thức 2025-03-26 (Port 1:1 từ `The5ersMcp.initialize()` trong `mcp.ts`)
    public func ensureInitialized() async throws {
        guard !isSessionInitialized else { return }
        guard isConfigured else { return }
        
        // Bước 1: Gửi RPC initialize kèm protocolVersion & clientInfo
        _ = try await sendRawMcpRpc(method: "initialize", params: [
            "protocolVersion": Self.protocolVersion,
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "trade-journal",
                "version": "1.0"
            ]
        ])
        
        // Bước 2: Gửi notification notifications/initialized xác nhận phiên
        try await sendMcpNotification(method: "notifications/initialized")
        self.isSessionInitialized = true
    }
    
    /// Gửi một thông báo JSON-RPC 2.0 (không cần chờ id phản hồi)
    public func sendMcpNotification(method: String, params: [String: Any]? = nil) async throws {
        guard let url = URL(string: Self.mcpUrl) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(mcpToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sId = mcpSessionId {
            request.setValue(sId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        var rpcPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let p = params {
            rpcPayload["params"] = p
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: rpcPayload)
        
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, let newSessionId = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            self.mcpSessionId = newSessionId
        }
    }
    
    /// Gửi RPC thô (không tự động lặp lại ensureInitialized để tránh đệ quy khi gọi initialize)
    private func sendRawMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối The5ers. Hãy bấm 'Đăng Nhập The5ers Hub (OAuth)' hoặc nhập Session Token."])
        }
        
        rpcIdCounter += 1
        let currentId = rpcIdCounter
        
        guard let url = URL(string: Self.mcpUrl) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Yêu cầu bắt buộc của The5ers MCP: chấp nhận cả application/json và text/event-stream
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(mcpToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sId = mcpSessionId {
            request.setValue(sId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        let rpcPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": currentId,
            "method": method,
            "params": params
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: rpcPayload)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if let newSessionId = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            self.mcpSessionId = newSessionId
        }
        
        guard (200...299).contains(http.statusCode) else {
            let msg: String = {
                switch http.statusCode {
                case 401: return "Phiên ủy quyền The5ers MCP đã hết hạn. Hãy kết nối lại."
                case 403: return "The5ers không cấp quyền truy cập tài nguyên này."
                case 429: return "The5ers MCP bị giới hạn tần suất yêu cầu (Rate Limit). Thử lại sau."
                default: return "The5ers MCP phản hồi mã lỗi HTTP \(http.statusCode)"
                }
            }()
            throw NSError(domain: "The5ersMCP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        // Trích xuất JSON từ định dạng Server-Sent Events (SSE) nếu máy chủ gửi qua SSE
        var jsonData = data
        if let text = String(data: data, encoding: .utf8), text.contains("data:") {
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("data:") {
                    let jsonSub = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let d = jsonSub.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: d)) != nil {
                        jsonData = d
                        break
                    }
                }
            }
        }
        
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi MCP JSON-RPC không đúng định dạng."])
        }
        
        if let rpcError = json["error"] as? [String: Any],
           let errorMsg = rpcError["message"] as? String {
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "The5ers MCP báo lỗi: \(errorMsg)"])
        }
        
        guard let result = json["result"] as? [String: Any] else {
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi MCP JSON-RPC thiếu trường result."])
        }
        
        return result
    }
    
    /// Gửi một yêu cầu JSON-RPC 2.0 tới The5ers MCP server, tự động bắt tay initialize nếu chưa
    public func sendMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        if method != "initialize" {
            try await ensureInitialized()
        }
        return try await sendRawMcpRpc(method: method, params: params)
    }
    
    /// Gửi một yêu cầu gọi MCP Tool tới The5ers MCP server
    public func callMcpTool(name: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        return try await sendMcpRpc(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
    }
    
    /// Kiểm tra kết nối The5ers MCP qua phương thức discovery `tools/list`
    public func pingMcpConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Chưa kết nối The5ers MCP. Hãy bấm 'Đăng Nhập The5ers Hub (OAuth)'.")
        }
        
        do {
            let res = try await sendMcpRpc(method: "tools/list", params: [:])
            self.isConnected = true
            let tools = res["tools"] as? [[String: Any]] ?? []
            return (true, "Kết nối The5ers MCP Server thành công! Giao thức 2025-03-26 hoạt động (\(tools.count) công cụ sẵn sàng).")
        } catch {
            return (false, "Lỗi kết nối The5ers MCP: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 3. Trích Xuất Payload Dữ Liệu MCP (Port 1:1 từ `mcp.ts` và `data.ts`)
    
    /// Trích xuất nội dung thực tế từ phản hồi MCP tools/call
    private func unwrapMcpToolResult(_ result: [String: Any]) -> Any? {
        if let structured = result["structuredContent"] {
            return structured
        }
        if let content = result["content"] as? [[String: Any]] {
            for block in content {
                if let type = block["type"] as? String, type == "text", let text = block["text"] as? String {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    var jsonStr = cleaned
                    if cleaned.hasPrefix("```json") {
                        jsonStr = cleaned.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if cleaned.hasPrefix("```") {
                        jsonStr = cleaned.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let d = jsonStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) {
                        return obj
                    }
                    return text
                }
            }
            if let first = content.first, let text = first["text"] as? String {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                var jsonStr = cleaned
                if cleaned.hasPrefix("```json") {
                    jsonStr = cleaned.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if cleaned.hasPrefix("```") {
                    jsonStr = cleaned.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let d = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) {
                    return obj
                }
            }
        }
        if let res = result["result"] as? [String: Any] {
            return unwrapMcpToolResult(res)
        }
        return result
    }
    
    /// Trích xuất danh sách hàng dữ liệu theo định dạng envelope The5ers
    private func extractMcpCollection(_ unwrapped: Any?, collectionKey: String) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        
        if let dict = unwrapped as? [String: Any] {
            // Envelope có data dạng Dictionary (VD: { data: { positions: [...] } })
            if let dataDict = dict["data"] as? [String: Any] {
                if let items = (dataDict[collectionKey] ?? dataDict["items"] ?? dataDict["rows"] ?? dataDict["trades"]) as? [[String: Any]] {
                    return items
                }
            }
            // Envelope có data dạng Array (VD: { data: [...] })
            if let dataArray = dict["data"] as? [[String: Any]] {
                return dataArray
            }
            // Envelope lồng trường result
            if let resDict = dict["result"] as? [String: Any] {
                return extractMcpCollection(resDict, collectionKey: collectionKey)
            }
            // Top-level dictionary chứa key (VD: { positions: [...] })
            if let items = (dict[collectionKey] ?? dict["items"] ?? dict["rows"] ?? dict["trades"]) as? [[String: Any]] {
                return items
            }
        } else if let arr = unwrapped as? [[String: Any]] {
            return arr
        }
        return []
    }
    
    // MARK: - 4. Đồng Bộ Dữ Liệu Thực Tế Qua MCP Tools
    
    @MainActor
    public func syncWithTradeStore(dataStore: TradeDataStore) async throws -> Int {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình Token The5ers MCP. Vui lòng bấm 'Đăng Nhập The5ers Hub (OAuth PKCE)'. "])
        }
        
        isSyncing = true
        lastStatus = "Đang kết nối The5ers MCP Hub (Protocol 2025-03-26)..."
        defer { isSyncing = false }
        
        do {
            // Đảm bảo handshake session trước khi thực thi tool
            try await ensureInitialized()
            
            // 1. Phân trang lấy 100% toàn bộ tài khoản The5ers (Pages 1...20)
            var rawAccountsList: [[String: Any]] = []
            var seenAccountRefs = Set<String>()
            
            for page in 1...20 {
                lastStatus = "Đang tải danh sách tài khoản The5ers (Trang \(page))..."
                let accountToolArgs: [String: Any] = [
                    "operation": "list",
                    "page": page,
                    "limit": 50,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                guard let accountResult = try? await callMcpTool(name: "the5ers_account", arguments: accountToolArgs) else {
                    break
                }
                let unwrappedAccounts = unwrapMcpToolResult(accountResult)
                let pageRows = extractMcpCollection(unwrappedAccounts, collectionKey: "accounts")
                if pageRows.isEmpty { break }
                
                var newCount = 0
                for item in pageRows {
                    let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? "")
                    if !ref.isEmpty && !seenAccountRefs.contains(ref) {
                        seenAccountRefs.insert(ref)
                        rawAccountsList.append(item)
                        newCount += 1
                    }
                }
                
                // Nếu trang hiện tại ít hơn limit 50 hoặc không có tài khoản mới nào, đã lấy hết toàn bộ
                if pageRows.count < 50 || newCount == 0 {
                    break
                }
            }
            
            var accountsList: [The5ersMcpAccount] = []
            for item in rawAccountsList {
                let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? UUID().uuidString)
                let label = String(describing: item["label"] ?? item["name"] ?? "The5ers Account")
                let bal = Decimal(string: String(describing: item["balance"] ?? item["effectiveBalance"] ?? "0")) ?? 0
                let eq = Decimal(string: String(describing: item["equity"] ?? bal)) ?? bal
                let curr = String(describing: item["currency"] ?? "USD")
                let status = String(describing: item["status"] ?? "active")
                let prog = String(describing: item["type"] ?? item["accountType"] ?? item["program"] ?? "funded")
                let startBal = Decimal(string: String(describing: item["startingBalance"] ?? item["initial_balance"] ?? bal)) ?? bal
                let platform = String(describing: item["tradingPlatform"] ?? item["platform"] ?? item["tradingSystem"] ?? "MT5")
                let createdAt = item["createdAt"] as? String ?? item["creationDate"] as? String ?? item["created_at"] as? String
                
                accountsList.append(The5ersMcpAccount(
                    id: ref,
                    ref: ref,
                    label: label,
                    platform: platform,
                    balance: bal,
                    equity: eq,
                    currency: curr,
                    status: status,
                    program: prog,
                    startingBalance: startBal,
                    createdAt: createdAt
                ))
            }
            
            // Tuyệt đối không nạp dữ liệu giả/demo: nếu trống thì thông báo rõ ràng
            if accountsList.isEmpty {
                lastStatus = "Máy chủ The5ers MCP phản hồi thành công nhưng không tìm thấy tài khoản giao dịch nào."
                return 0
            }
            
            // 2. Cập nhật danh mục tài khoản (Accounts & Prop Accounts) ngay lập tức
            for acc in accountsList {
                let mappedStatus: PropStatus = {
                    switch acc.status.lowercased() {
                    case "passed": return .passed
                    case "breached", "failed": return .breached
                    case "closed": return .closed
                    default: return .active
                    }
                }()
                
                let mappedProgram: PropProgram = {
                    switch acc.program.lowercased() {
                    case "verification", "step2": return .verification
                    case "funded", "live": return .funded
                    case "instant_funded", "instant": return .instantFunded
                    default: return .evaluation
                    }
                }()
                
                let startingMinor = NSDecimalNumber(decimal: (acc.startingBalance ?? acc.balance) * 100).int64Value
                let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
                
                if let existingIndex = dataStore.propAccounts.firstIndex(where: { $0.id == journalAccId || $0.id == acc.id || $0.name == acc.label }) {
                    var existing = dataStore.propAccounts[existingIndex]
                    existing.id = journalAccId
                    existing.journalAccountId = journalAccId
                    existing.status = mappedStatus
                    existing.program = mappedProgram
                    dataStore.propAccounts[existingIndex] = existing
                } else {
                    let newPropAccount = PropAccountItem(
                        id: journalAccId,
                        firm: "The5ers",
                        name: acc.label,
                        program: mappedProgram,
                        status: mappedStatus,
                        currency: acc.currency,
                        sizeMinor: startingMinor,
                        journalAccountId: journalAccId,
                        openedOn: acc.createdAt ?? DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
                        notes: "Đồng bộ từ The5ers MCP Hub (Protocol 2025-03-26)",
                        archived: false
                    )
                    dataStore.propAccounts.append(newPropAccount)
                }
                
                if let accIdx = dataStore.accounts.firstIndex(where: { $0.id == journalAccId || $0.id == acc.id }) {
                    dataStore.accounts[accIdx].id = journalAccId
                    dataStore.accounts[accIdx].broker = "The5ers"
                    dataStore.accounts[accIdx].name = acc.label
                    dataStore.accounts[accIdx].currency = acc.currency
                } else {
                    let newAcc = Account(
                        id: journalAccId,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? acc.balance,
                        autoSync: true
                    )
                    dataStore.accounts.append(newAcc)
                }
            }
            
            // 3. Smart Target Selection: Lọc tài khoản cần quét vị thế
            // Ưu tiên toàn bộ tài khoản active / available / passed + tối đa 5 tài khoản gần nhất
            var targetAccounts: [The5ersMcpAccount] = []
            var seenTargetIds = Set<String>()
            
            for acc in accountsList {
                let s = acc.status.lowercased()
                if (s == "active" || s == "available" || s == "passed") && !seenTargetIds.contains(acc.id) {
                    seenTargetIds.insert(acc.id)
                    targetAccounts.append(acc)
                }
            }
            
            for acc in accountsList.prefix(5) {
                if !seenTargetIds.contains(acc.id) {
                    seenTargetIds.insert(acc.id)
                    targetAccounts.append(acc)
                }
            }
            
            if targetAccounts.isEmpty {
                targetAccounts = Array(accountsList.prefix(5))
            }
            
            var importedPositionsCount = 0
            for (idx, acc) in targetAccounts.enumerated() {
                lastStatus = "Đang đồng bộ lệnh (\(idx + 1)/\(targetAccounts.count)): \(acc.label)..."
                await Task.yield()
                
                let posArgs: [String: Any] = [
                    "operation": "list",
                    "account_ref": acc.ref,
                    "view": "all",
                    "page": 1,
                    "limit": 50,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                
                do {
                    let posResult = try await callMcpTool(name: "the5ers_positions", arguments: posArgs)
                    if let isErr = posResult["isError"] as? Bool, isErr {
                        AppLogger.error("The5ers MCP báo lỗi cho tài khoản \(acc.label) (\(acc.id)): \(posResult)")
                        continue
                    }
                    let unwrappedPos = unwrapMcpToolResult(posResult)
                    let rawPositions = extractMcpCollection(unwrappedPos, collectionKey: "positions")
                    mergePositions(rawPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                    
                    // Nếu trang 1 có đủ 50 vị thế, tiếp tục phân trang các trang tiếp theo
                    if rawPositions.count >= 50 {
                        var page = 2
                        while page <= 10 {
                            var pArgs = posArgs
                            pArgs["page"] = page
                            guard let nextRes = try? await callMcpTool(name: "the5ers_positions", arguments: pArgs) else { break }
                            let nextUnwrapped = unwrapMcpToolResult(nextRes)
                            let nextPositions = extractMcpCollection(nextUnwrapped, collectionKey: "positions")
                            if nextPositions.isEmpty { break }
                            mergePositions(nextPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                            if nextPositions.count < 50 { break }
                            page += 1
                        }
                    }
                } catch {
                    AppLogger.error("Lỗi đồng bộ lệnh tài khoản \(acc.label) (\(acc.id)): \(error.localizedDescription)")
                }
            }
            
            // 4. Đồng bộ the5ers_payout
            lastStatus = "Đang tải lịch sử rút tiền the5ers_payout..."
            let payoutArgs: [String: Any] = [
                "operation": "history",
                "contract_version": "1.0",
                "request_context": ["timezone": "UTC", "locale": "en"]
            ]
            if let payoutResult = try? await callMcpTool(name: "the5ers_payout", arguments: payoutArgs) {
                let unwrappedPayout = unwrapMcpToolResult(payoutResult)
                let rawPayouts = extractMcpCollection(unwrappedPayout, collectionKey: "payouts")
                
                for pay in rawPayouts {
                    let id = String(describing: pay["id"] ?? pay["payout_id"] ?? UUID().uuidString)
                    let amtMinor = Int64(Double(String(describing: pay["amount"] ?? pay["net_amount"] ?? "0")) ?? 0) * 100
                    let dateStr = String(describing: pay["paidAt"] ?? pay["date"] ?? pay["createdAt"] ?? "")
                    let rcptId = "the5ers_rcpt_\(id)"
                    
                    if !dataStore.propReceipts.contains(where: { $0.id == rcptId }) {
                        let rcpt = PropReceiptItem(
                            id: rcptId,
                            payoutId: id,
                            kind: "receipt",
                            amountMinor: amtMinor,
                            occurredOn: dateStr,
                            reference: "THE5ERS-\(id)",
                            notes: "Biên nhận rút tiền The5ers MCP"
                        )
                        dataStore.propReceipts.append(rcpt)
                    }
                }
            }
            
            lastSyncTime = Date()
            dataStore.rebuildAllAccounts()
            
            // Đảm bảo selectedAccountId trỏ vào tài khoản có lệnh giao dịch nếu hiện tại đang rỗng
            if dataStore.filteredTrades.isEmpty, let firstWithTrade = dataStore.accounts.first(where: { acc in dataStore.trades.contains(where: { $0.accountId == acc.id }) }) {
                dataStore.selectedAccountId = firstWithTrade.id
            }
            
            dataStore.saveToDisk()
            let activeCount = accountsList.filter { $0.status.lowercased() == "active" || $0.status.lowercased() == "available" }.count
            lastStatus = "Đã đồng bộ thành công \(accountsList.count) tài khoản (\(activeCount) đang hoạt động) và \(importedPositionsCount) vị thế lệnh từ The5ers MCP."
            
            // 5. Tự động kích hoạt luồng đẩy lên Supabase Cloud (Auto-Pipeline: The5ers -> Local -> Supabase)
            if SupabaseService.shared.isConfigured {
                lastStatus = "The5ers hoàn tất (\(importedPositionsCount) lệnh). Đang tự động sao lưu lên đám mây Supabase..."
                await dataStore.syncWithSupabase()
                lastStatus = "Đã đồng bộ thành công \(accountsList.count) tài khoản (\(activeCount) đang hoạt động), \(importedPositionsCount) vị thế lệnh từ The5ers và tự động sao lưu lên Supabase."
            }
            
            return accountsList.count
        } catch {
            lastStatus = "Lỗi đồng bộ The5ers MCP: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - 5. Source Normalization & Grouping (Port 1:1 từ the5ers-normalize.ts và journal.ts)
    
    private struct SourcePosition {
        var identityDiscriminator: String?
        let providerId: String?
        let symbol: String
        let direction: TradeDirection
        let openedAtIso: String
        let openedAtDate: Date
        let closedAtIso: String?
        let closedAtDate: Date?
        let quantity: Decimal
        let entry: Decimal
        let exit: Decimal?
        let netPnl: Decimal
        let fee: Decimal?
        let swap: Decimal?
        let isValid: Bool?
    }
    
    /// Chuyển đổi nhãn thuộc tính provider (camelCase, snake_case, v.v.) về chuẩn không dấu cách/gạch dưới chữ thường
    /// Port 1:1 từ `the5ers-normalize.ts` `sourceFields`
    private func sourceFields(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in dict {
            let cleanKey = key.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            result[cleanKey] = val
        }
        return result
    }
    
    private func sourceNumber(_ val: Any?) -> Decimal? {
        guard let val = val else { return nil }
        if let num = val as? NSNumber {
            return Decimal(string: num.stringValue)
        }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces)
        return Decimal(string: str)
    }
    
    private func sourceBoolean(_ val: Any?) -> Bool? {
        guard let val = val else { return nil }
        if let b = val as? Bool { return b }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces).lowercased()
        if ["yes", "true", "1"].contains(str) { return true }
        if ["no", "false", "0"].contains(str) { return false }
        return nil
    }
    
    private func sourceInstant(_ val: Any?) -> (iso: String, date: Date)? {
        guard let val = val else { return nil }
        let str = String(describing: val).trimmingCharacters(in: .whitespaces)
        guard let date = FlexibleDateParser.parse(str) else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (fmt.string(from: date), date)
    }
    
    /// Chuẩn hóa vị thế The5ers (Port 1:1 từ `the5ers-normalize.ts` `normalizePosition`)
    private func normalizePosition(from raw: [String: Any]) -> SourcePosition? {
        let row = sourceFields(raw)
        
        let symbol = String(describing: row["symbol"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty && symbol.count <= 100 else { return nil }
        
        let sideStr = String(describing: row["side"] ?? row["direction"] ?? "").lowercased()
        let direction: TradeDirection? = {
            if sideStr.contains("buy") || sideStr == "long" { return .long }
            if sideStr.contains("sell") || sideStr == "short" { return .short }
            return nil
        }()
        guard let dir = direction else { return nil }
        
        guard let (openedAtIso, openedAtDate) = sourceInstant(row["opendate"] ?? row["openedat"] ?? row["opentime"] ?? row["open_date"] ?? row["opendatetime"]) else {
            return nil
        }
        guard let quantity = sourceNumber(row["quantity"] ?? row["lots"] ?? row["volume"] ?? row["size"]), quantity > 0 else {
            return nil
        }
        guard let entry = sourceNumber(row["entry"] ?? row["openprice"] ?? row["entryprice"] ?? row["open_price"]) else {
            return nil
        }
        
        let isClosed = sourceBoolean(row["isclosed"]) ?? (row["closedate"] != nil || row["exit"] != nil || row["closetime"] != nil)
        
        let closedAtTuple = isClosed ? sourceInstant(row["closedate"] ?? row["closedat"] ?? row["closetime"] ?? row["close_date"] ?? row["closedatetime"]) : nil
        let exit = isClosed ? sourceNumber(row["exit"] ?? row["closeprice"] ?? row["exitprice"] ?? row["close_price"]) : nil
        let netPnl = isClosed ? (sourceNumber(row["profitandloss"] ?? row["profit"] ?? row["netpnl"] ?? row["pnl"] ?? row["net_pnl"]) ?? 0) : 0
        
        if isClosed && (closedAtTuple == nil || exit == nil) {
            return nil
        }
        if let cl = closedAtTuple, cl.date < openedAtDate {
            return nil
        }
        
        let providerId: String? = {
            if let p = row["positionid"] ?? row["ticket"] ?? row["id"] ?? row["dealid"] ?? row["positionref"] {
                let s = String(describing: p).trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            return nil
        }()
        
        let fee = sourceNumber(row["fee"] ?? row["commission"])
        let swap = sourceNumber(row["swap"])
        let isValid = sourceBoolean(row["isvalid"])
        
        return SourcePosition(
            identityDiscriminator: nil,
            providerId: providerId,
            symbol: symbol,
            direction: dir,
            openedAtIso: openedAtIso,
            openedAtDate: openedAtDate,
            closedAtIso: closedAtTuple?.iso,
            closedAtDate: closedAtTuple?.date,
            quantity: quantity,
            entry: entry,
            exit: exit,
            netPnl: netPnl,
            fee: fee,
            swap: swap,
            isValid: isValid
        )
    }
    
    /// Hợp nhất các vị thế giao dịch thực tế vào TradeDataStore
    /// Port 1:1 từ `source-repo/apps/web/src/server/the5ers/journal.ts` (`saveJournalPositions` & `journalTradeRow`)
    @MainActor
    private func mergePositions(
        _ rawPositions: [[String: Any]],
        for acc: The5ersMcpAccount,
        into dataStore: TradeDataStore,
        count: inout Int
    ) {
        let parsed = rawPositions.compactMap { normalizePosition(from: $0) }
        guard !parsed.isEmpty else { return }
        
        let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
        
        // Nhóm các vị thế theo base identity = sha256([symbol, direction, openedAt])
        var groups: [String: [SourcePosition]] = [:]
        for p in parsed {
            let baseKey = JournalIds.positionIdentity(symbol: p.symbol, direction: p.direction.rawValue, openedAt: p.openedAtIso, discriminator: nil)
            groups[baseKey, default: []].append(p)
        }
        
        var valid: [SourcePosition] = []
        for (_, group) in groups {
            if group.count == 1 {
                valid.append(group[0])
                continue
            }
            // Trường hợp có nhiều vị thế trùng (symbol, direction, openedAt), phân biệt bằng providerId hoặc entry
            for p in group {
                var item = p
                let disc: String
                if let pid = p.providerId, !pid.isEmpty {
                    disc = "provider:\(pid)"
                } else {
                    disc = "entry:\(JournalIds.sha256Hex([p.quantity, p.entry]))"
                }
                item.identityDiscriminator = disc
                valid.append(item)
            }
        }
        
        // Chuyển đổi SourcePosition thành TradeRow chuẩn
        for position in valid {
            let posIdentity = JournalIds.positionIdentity(
                symbol: position.symbol,
                direction: position.direction.rawValue,
                openedAt: position.openedAtIso,
                discriminator: position.identityDiscriminator
            )
            // Khóa chuẩn: "the5ers_" + sha256([sourceAccountId, positionIdentity])
            let tradeKey = JournalIds.the5ersTradeKey(sourceAccountId: acc.id, positionIdentity: posIdentity)
            
            let isClosed = position.closedAtDate != nil
            let status: TradeStatus = isClosed
                ? (position.netPnl > 0 ? .win : (position.netPnl < 0 ? .loss : .breakeven))
                : .open
            
            // Công thức Gross P&L & Fees toán học port 1:1 từ `journal.ts` (lines 68-75):
            // Broker The5ers báo netPnl đã tính cả fee và swap (mang dấu âm).
            // Do đó costsReversed = -fee - swap (thành số dương).
            // grossPnl = netPnl + costsReversed
            // fees = costsReversed
            // netPnl = netPnl
            // Bất biến luôn thỏa mãn: grossPnl - fees == netPnl
            let fee = position.fee ?? 0
            let swap = position.swap ?? 0
            let hasCosts = (position.fee != nil && position.swap != nil)
            let costsReversed = hasCosts ? (-fee - swap) : 0
            let grossPnl = position.netPnl + costsReversed
            let fees = hasCosts ? costsReversed : 0
            let netPnl = position.netPnl
            
            let durationMs: Int64? = (isClosed && position.closedAtDate != nil)
                ? Int64(position.closedAtDate!.timeIntervalSince(position.openedAtDate) * 1000)
                : nil
            
            if let tIdx = dataStore.trades.firstIndex(where: { $0.key == tradeKey }) {
                var existing = dataStore.trades[tIdx]
                // Cập nhật các trường kinh tế sàn có thể cập nhật khi đóng vị thế
                existing.status = status
                existing.closedAt = position.closedAtDate
                existing.openQuantity = isClosed ? 0 : position.quantity
                existing.avgExit = position.exit
                existing.grossPnl = grossPnl
                existing.fees = fees
                existing.netPnl = netPnl
                existing.durationMs = durationMs
                // Bảo toàn 100% annotations cá nhân của trader (notes, tags, mistakes, playbook, rating,...)
                if existing.notes == nil || existing.notes?.isEmpty == true {
                    existing.notes = "Vị thế được đồng bộ từ The5ers Hub (Ticket: \(position.providerId ?? ""))"
                }
                dataStore.trades[tIdx] = existing
            } else {
                let trade = Trade(
                    key: tradeKey,
                    accountId: journalAccId,
                    symbol: position.symbol,
                    direction: position.direction,
                    status: status,
                    openedAt: position.openedAtDate,
                    closedAt: position.closedAtDate,
                    quantity: position.quantity,
                    openQuantity: isClosed ? 0 : position.quantity,
                    avgEntry: position.entry,
                    avgExit: position.exit,
                    grossPnl: grossPnl,
                    fees: fees,
                    netPnl: netPnl,
                    executionCount: 0,
                    executionIds: [],
                    durationMs: durationMs,
                    notes: "Vị thế được đồng bộ từ The5ers Hub (Ticket: \(position.providerId ?? ""))",
                    tags: ["the5ers", acc.program.lowercased()]
                )
                dataStore.trades.append(trade)
                count += 1
            }
        }
    }
}
