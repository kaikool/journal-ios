import Foundation
import CryptoKit

/// The5ers MCP Protocol model (`the5ers_account`)
/// The5ers MCP Protocol model (`the5ers_account`)
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

/// Official connector for The5ers via Model Context Protocol (MCP)
/// Domain specification matching core web repository
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
    private var cachedToolSchemas: [String: [String: Any]] = [:]
    private var discoveredToolNames: Set<String> = []
    
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
            self.cachedToolSchemas.removeAll()
            self.discoveredToolNames.removeAll()
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
        self.cachedToolSchemas.removeAll()
        self.discoveredToolNames.removeAll()
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_refresh_token")
    }
    
    // MARK: - 1. OAuth 2.0 PKCE Flow (Official The5ers Hub OAuth)
    
    /// Dynamic client registration RFC 7591 with The5ers Descope Hub server
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
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to register dynamic client: \(err)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response: The5ers registration did not return client_id."])
        }
        
        UserDefaults.standard.set(clientId, forKey: key)
        return clientId
    }
    
    @MainActor
    public func startOAuthLogin() async throws -> String {
        // Generate PKCE Verifier and Challenge (S256)
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
        
        guard var comp = URLComponents(string: "\(Self.authHost)/oauth2/v1/apps/agentic/\(Self.tenantPath)/authorize") else {
            throw URLError(.badURL)
        }
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
        
// Extract authorization code from callback URL
        guard let components = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL received from The5ers Hub."])
        }
        
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            let err = components.queryItems?.first(where: { $0.name == "error_description" || $0.name == "error" })?.value ?? "Failed to receive authorization code from The5ers Hub."
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        
// Exchange authorization code for token with PKCE verifier
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
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to exchange token: \(errStr)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "The5ersOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find valid session token"])
        }
        
        if let refreshToken = json["refresh_token"] as? String {
            UserDefaults.standard.set(refreshToken, forKey: "the5ers_mcp_refresh_token")
        }
        
        return accessToken
    }
    
    // MARK: - 2. JSON-RPC 2.0 MCP Client (`https://mcp.the5ers.com/mcp`)
    
    /// Initializes JSON-RPC protocol handshake with The5ers MCP server
    public func ensureInitialized() async throws {
        guard !isSessionInitialized else { return }
        guard isConfigured else { return }
        
        // Protocol initialization handshake
        _ = try await sendRawMcpRpc(method: "initialize", params: [
            "protocolVersion": Self.protocolVersion,
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "trade-journal",
                "version": "1.0"
            ]
        ])
        
        // Notify server that client initialization completed
        try await sendMcpNotification(method: "notifications/initialized")
        self.isSessionInitialized = true
    }
    
    /// Sends a one-way notification without expecting a response
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
    
    /// Dispatches a raw JSON-RPC 2.0 request to the MCP endpoint
    private func sendRawMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bearer Session Token not configured"])
        }
        
        rpcIdCounter += 1
        let currentId = rpcIdCounter
        
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
                case 401: return "The5ers MCP authorization session expired. Please reconnect."
                case 403: return "The5ers server denied access to this resource."
                case 429: return "The5ers MCP request rate limit exceeded. Please try again later."
                default: return "The5ers MCP returned HTTP error \(http.statusCode)"
                }
            }()
            throw NSError(domain: "The5ersMCP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        // Handle SSE (Server-Sent Events) formatting if streamed
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
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response: MCP JSON-RPC payload is malformed."])
        }
        
        if let rpcError = json["error"] as? [String: Any],
           let errorMsg = rpcError["message"] as? String {
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "The5ers MCP error: \(errorMsg)"])
        }
        
        guard let result = json["result"] as? [String: Any] else {
            throw NSError(domain: "The5ersMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response: MCP JSON-RPC missing result field."])
        }
        
        return result
    }
    
    /// Sends an authenticated JSON-RPC call ensuring initialized session
    public func sendMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        if method != "initialize" {
            try await ensureInitialized()
        }
        return try await sendRawMcpRpc(method: method, params: params)
    }
    
    /// Queries and caches available MCP tools and their input schemas
    public func refreshAvailableTools() async {
        guard let res = try? await sendMcpRpc(method: "tools/list", params: [:]) else { return }
        let toolsList: [[String: Any]] = {
            if let tools = res["tools"] as? [[String: Any]] { return tools }
            if let r = res["result"] as? [String: Any], let tools = r["tools"] as? [[String: Any]] { return tools }
            return []
        }()
        for t in toolsList {
            if let name = t["name"] as? String {
                discoveredToolNames.insert(name)
                if let schema = t["inputSchema"] as? [String: Any] {
                    cachedToolSchemas[name] = schema
                }
            }
        }
    }
    
    /// Filters arguments to conform strictly to the tool's published inputSchema properties
    private func filterArgsForTool(_ args: [String: Any], toolName: String) -> [String: Any] {
        guard let schema = cachedToolSchemas[toolName],
              let props = schema["properties"] as? [String: Any],
              !props.isEmpty else {
            return args
        }
        return args.filter { props.keys.contains($0.key) }
    }
    
    /// Builds resilient per-account arguments matching the exact parameter name expected by the tool
    private func buildAccountArgs(toolName: String, accountRef: String, op: String? = nil) -> [String: Any] {
        var base: [String: Any] = [
            "contract_version": "1.0"
        ]
        if let op = op {
            base["operation"] = op
        }
        
        if let schema = cachedToolSchemas[toolName],
           let props = schema["properties"] as? [String: Any],
           !props.isEmpty {
            if props.keys.contains("account_ref") {
                base["account_ref"] = accountRef
            } else if props.keys.contains("account_id") {
                base["account_id"] = accountRef
            } else if props.keys.contains("account") {
                base["account"] = accountRef
            } else if props.keys.contains("ref") {
                base["ref"] = accountRef
            } else if props.keys.contains("id") {
                base["id"] = accountRef
            } else {
                base["account_ref"] = accountRef
            }
            return filterArgsForTool(base, toolName: toolName)
        }
        
        base["account_ref"] = accountRef
        return base
    }
    
    /// Invokes an MCP tool by name with arguments, automatically filtered against tool schema
    public func callMcpTool(name: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        if cachedToolSchemas.isEmpty {
            await refreshAvailableTools()
        }
        let filtered = filterArgsForTool(arguments, toolName: name)
        return try await sendMcpRpc(method: "tools/call", params: [
            "name": name,
            "arguments": filtered
        ])
    }
    
    /// Pings the MCP connection by listing available tools
    public func pingMcpConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "The5ers MCP is not connected. Click 'Log in to The5ers Hub (OAuth)'.")
        }
        
        do {
            let res = try await sendMcpRpc(method: "tools/list", params: [:])
            self.isConnected = true
            let tools = res["tools"] as? [[String: Any]] ?? []
            for t in tools {
                if let name = t["name"] as? String {
                    discoveredToolNames.insert(name)
                    if let schema = t["inputSchema"] as? [String: Any] {
                        cachedToolSchemas[name] = schema
                    }
                }
            }
            return (true, "Connected to The5ers MCP Server! Protocol 2025-03-26 active (\(tools.count) tools ready).")
        } catch {
            return (false, "The5ers MCP connection error: \(error.localizedDescription)")
        }
    }
    
    /// Extracts JSON objects or arrays from arbitrary text, markdown fences, or bracket boundaries
    private func extractJsonFromText(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        // 1. Direct JSON parse
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return obj
        }
        
        // 2. Markdown fence ```json ... ``` or ``` ... ```
        if let startFence = trimmed.range(of: "```") {
            let afterFence = trimmed[startFence.upperBound...]
            let contentPart: Substring
            if afterFence.lowercased().hasPrefix("json") {
                contentPart = afterFence.dropFirst(4)
            } else {
                contentPart = afterFence
            }
            if let endFence = contentPart.range(of: "```") {
                let inside = contentPart[..<endFence.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = inside.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) {
                    return obj
                }
            }
        }
        
        // 3. Substring matching outermost [ ... ] or { ... }
        if let firstBracket = trimmed.firstIndex(of: "["),
           let lastBracket = trimmed.lastIndex(of: "]"),
           firstBracket < lastBracket {
            let sub = String(trimmed[firstBracket...lastBracket])
            if let data = sub.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
        }
        
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let sub = String(trimmed[firstBrace...lastBrace])
            if let data = sub.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
        }
        
        return nil
    }
    
    /// Unwraps JSON string, markdown fences, or structured dictionary from MCP tool responses
    private func unwrapMcpToolResult(_ result: [String: Any]) -> Any? {
        if let structured = result["structuredContent"] {
            return structured
        }
        if let content = result["content"] as? [[String: Any]] {
            // First pass: look for valid JSON in any block
            for block in content {
                if let text = block["text"] as? String,
                   let obj = extractJsonFromText(text) {
                    return obj
                }
            }
            // Second pass: return non-empty text if no JSON was found
            for block in content {
                if let text = block["text"] as? String {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        if let data = result["data"] {
            return data
        }
        if let res = result["result"] as? [String: Any] {
            return unwrapMcpToolResult(res)
        }
        return result
    }
    
    /// Traverses flexible JSON response envelopes to find an array of items
    private func extractMcpCollection(_ unwrapped: Any?, collectionKey: String) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        
        if let dict = unwrapped as? [String: Any] {
            if let dataDict = dict["data"] as? [String: Any] {
                if let items = (dataDict[collectionKey] ?? dataDict["items"] ?? dataDict["rows"] ?? dataDict["trades"]) as? [[String: Any]] {
                    return items
                }
            }
            if let dataArray = dict["data"] as? [[String: Any]] {
                return dataArray
            }
            if let resDict = dict["result"] as? [String: Any] {
                return extractMcpCollection(resDict, collectionKey: collectionKey)
            }
            if let items = (dict[collectionKey] ?? dict["items"] ?? dict["rows"] ?? dict["trades"]) as? [[String: Any]] {
                return items
            }
        } else if let arr = unwrapped as? [[String: Any]] {
            return arr
        }
        return []
    }
    
    @MainActor
    public func syncWithTradeStore(dataStore: TradeDataStore) async throws -> Int {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bearer Session Token not configured"])
        }
        
        isSyncing = true
        lastStatus = "Connecting to The5ers MCP Hub (Protocol 2025-03-26)..."
        defer { isSyncing = false }
        
        do {
            try await ensureInitialized()
            await refreshAvailableTools()
            
            var rawAccountsList: [[String: Any]] = []
            var seenAccountRefs = Set<String>()
            var successfulArgTemplate: [String: Any]? = nil
            
            for page in 1...20 {
                lastStatus = "Loading The5ers accounts (Page \(page))..."
                let candidateArgsList: [[String: Any]] = {
                    if let template = successfulArgTemplate {
                        var pArgs = template
                        pArgs["page"] = page
                        return [pArgs]
                    }
                    return [
                        [
                            "operation": "list",
                            "page": page,
                            "limit": 50,
                            "contract_version": "1.0",
                            "request_context": ["timezone": "UTC", "locale": "en"]
                        ],
                        [
                            "operation": "list",
                            "page": page,
                            "limit": 50
                        ],
                        ["operation": "list"],
                        [:]
                    ]
                }()
                
                var accountResult: [String: Any]? = nil
                var lastErr: String = ""
                
                for candidateArgs in candidateArgsList {
                    if let res = try? await callMcpTool(name: "the5ers_account", arguments: candidateArgs) {
                        let isErr = (res["isError"] as? Bool) ?? false
                        if !isErr {
                            accountResult = res
                            if successfulArgTemplate == nil {
                                successfulArgTemplate = candidateArgs
                            }
                            break
                        } else {
                            lastErr = (res["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ") ?? ""
                        }
                    }
                }
                
                guard let finalAccountResult = accountResult else {
                    if page == 1 {
                        let msg = lastErr.isEmpty ? "The5ers MCP returned an error when fetching accounts" : lastErr
                        throw NSError(domain: "The5ersMCP", code: 500, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                    break
                }
                
                let unwrappedAccounts = unwrapMcpToolResult(finalAccountResult)
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
                
                // Break pagination loop if end of stream reached, or candidateArgs didn't include pagination, or no new accounts
                if pageRows.count < 50 || newCount == 0 || (successfulArgTemplate?["page"] == nil && page == 1) {
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
                
                let defaultName = Self.the5ersDefaultName(
                    from: item,
                    fallbackLabel: label,
                    platform: platform,
                    startingBalance: startBal,
                    balance: bal
                )
                let cleanLabel = defaultName.isEmpty ? Formatters.cleanAccountName(label, balance: startBal) : defaultName
                
                accountsList.append(The5ersMcpAccount(
                    id: ref,
                    ref: ref,
                    label: cleanLabel,
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
            
            if accountsList.isEmpty {
                lastStatus = "The5ers MCP responded successfully but no trading accounts were found."
                return 0
            }
            
            // Sync accounts into local PropAccountItem and Account models
            for acc in accountsList {
                let rawStatus = acc.status.trimmingCharacters(in: .whitespaces).lowercased()
                let mappedStatus: PropStatus = {
                    if rawStatus == "passed" || rawStatus.contains("pass") || rawStatus.contains("qualif") { return .passed }
                    if rawStatus == "breached" || rawStatus == "failed" || rawStatus.contains("breach") || rawStatus.contains("fail") || rawStatus.contains("viola") { return .breached }
                    if rawStatus == "closed" || rawStatus.contains("term") || rawStatus.contains("ended") || rawStatus.contains("expir") { return .closed }
                    if rawStatus == "inactive" || rawStatus == "disabled" || rawStatus.contains("inact") { return .inactive }
                    if rawStatus == "active" || rawStatus == "available" || rawStatus.contains("trad") || rawStatus.contains("open") { return .active }
                    return .closed
                }()
                
                let rawProg = acc.program.trimmingCharacters(in: .whitespaces).lowercased()
                let rawLabel = acc.label.trimmingCharacters(in: .whitespaces).lowercased()
                let mappedProgram: PropProgram = {
                    if rawProg.contains("instant") || rawLabel.contains("instant") { return .instantFunded }
                    if rawProg.contains("step2") || rawProg.contains("step 2") || rawProg.contains("phase2") || rawProg.contains("phase 2") || rawProg.contains("verification") || rawLabel.contains("phase 2") || rawLabel.contains("step 2") || rawLabel.contains("high stakes - 2") { return .verification }
                    if rawProg.contains("fund") || rawProg.contains("live") || rawLabel.contains("funded") || rawLabel.contains("live") { return .funded }
                    return .evaluation
                }()
                
                let startingMinor = NSDecimalNumber(decimal: (acc.startingBalance ?? acc.balance) * 100).int64Value
                let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
                
                let isActive = (mappedStatus == .active)
                
                if let existingIndex = dataStore.propAccounts.firstIndex(where: { TradeDataStore.isSameAccountId($0.id, journalAccId) || $0.name == acc.label }) {
                    let old = dataStore.propAccounts[existingIndex]
                    dataStore.propAccounts[existingIndex] = PropAccountItem(
                        id: journalAccId,
                        firm: "The5ers",
                        name: acc.label,
                        program: mappedProgram,
                        status: mappedStatus,
                        currency: acc.currency,
                        sizeMinor: startingMinor,
                        parentId: old.parentId,
                        journalAccountId: journalAccId,
                        openedOn: old.openedOn,
                        closedOn: old.closedOn,
                        renewalOn: old.renewalOn,
                        renewalMinor: old.renewalMinor,
                        notes: old.notes,
                        archived: old.archived,
                        revision: old.revision + 1,
                        createdAt: old.createdAt,
                        updatedAt: JournalIds.nowIso()
                    )
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
                        notes: "Synced from The5ers MCP Hub (Protocol 2025-03-26)",
                        archived: false
                    )
                    dataStore.propAccounts.append(newPropAccount)
                }
                
                if let accIdx = dataStore.accounts.firstIndex(where: { TradeDataStore.isSameAccountId($0.id, journalAccId) || $0.name == acc.label }) {
                    let old = dataStore.accounts[accIdx]
                    dataStore.accounts[accIdx] = Account(
                        id: journalAccId,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? acc.balance,
                        profitCalcMethod: old.profitCalcMethod,
                        autoSync: isActive,
                        lastSyncAt: Date(),
                        archivedAt: old.archivedAt,
                        visibleInJournal: old.visibleInJournal ?? true,
                        createdAt: old.createdAt
                    )
                } else {
                    let newAcc = Account(
                        id: journalAccId,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? acc.balance,
                        autoSync: isActive,
                        archivedAt: nil,
                        visibleInJournal: true
                    )
                    dataStore.accounts.append(newAcc)
                }
            }
            
            // Target all available accounts from The5ers (both freshly discovered and existing historical accounts)
            var allTargetAccounts: [The5ersMcpAccount] = []
            var seenTargetRefs = Set<String>()
            
            for acc in accountsList {
                if !seenTargetRefs.contains(acc.ref) {
                    seenTargetRefs.insert(acc.ref)
                    allTargetAccounts.append(acc)
                }
            }
            
            for prop in dataStore.propAccounts where prop.firm.lowercased() == "the5ers" || prop.id.hasPrefix("the5ers_") {
                let ref = prop.id.cleanAccountId
                if !ref.isEmpty && !seenTargetRefs.contains(ref) {
                    seenTargetRefs.insert(ref)
                    allTargetAccounts.append(The5ersMcpAccount(
                        id: prop.id,
                        ref: ref,
                        label: prop.name,
                        platform: "cTrader",
                        balance: Decimal(prop.sizeMinor ?? 0) / 100,
                        equity: Decimal(prop.sizeMinor ?? 0) / 100,
                        currency: prop.currency,
                        status: prop.status.rawValue,
                        program: prop.program.rawValue,
                        startingBalance: Decimal(prop.sizeMinor ?? 0) / 100
                    ))
                }
            }
            
            for acc in dataStore.accounts where acc.broker.lowercased() == "the5ers" || acc.id.hasPrefix("the5ers_") {
                let ref = acc.id.cleanAccountId
                if !ref.isEmpty && !seenTargetRefs.contains(ref) {
                    seenTargetRefs.insert(ref)
                    allTargetAccounts.append(The5ersMcpAccount(
                        id: acc.id,
                        ref: ref,
                        label: acc.name,
                        platform: "cTrader",
                        balance: acc.initialBalance,
                        equity: acc.initialBalance,
                        currency: acc.currency,
                        status: "active",
                        program: "funded",
                        startingBalance: acc.initialBalance
                    ))
                }
            }
            
            // Incremental sync optimization: only query positions for active accounts or accounts with 0 trades
            let accountsToSyncPositions = allTargetAccounts.filter { acc in
                let isActive = (acc.status.lowercased() == "active" || acc.status.lowercased() == "available")
                let hasTrades = dataStore.trades.contains(where: { TradeDataStore.isSameAccountId($0.accountId, acc.id) })
                return isActive || !hasTrades
            }
            
            var importedPositionsCount = 0
            for (idx, acc) in accountsToSyncPositions.enumerated() {
                if Task.isCancelled { break }
                lastStatus = "Syncing trades (\(idx + 1)/\(accountsToSyncPositions.count)): \(acc.label)..."
                await Task.yield()
                
                let posArgs: [String: Any] = [
                    "operation": "list",
                    "account_ref": acc.ref,
                    "page": 1,
                    "limit": 50,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                
                do {
                    let posResult = try await callMcpTool(name: "the5ers_positions", arguments: posArgs)
                    if let isErr = posResult["isError"] as? Bool, isErr {
                        AppLogger.error("The5ers MCP reported error for account \(acc.label) (\(acc.id)): \(posResult)")
                        continue
                    }
                    let unwrappedPos = unwrapMcpToolResult(posResult)
                    let rawPositions = extractMcpCollection(unwrappedPos, collectionKey: "positions")
                    mergePositions(rawPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                    
                    // Paginate if full page returned
                    if rawPositions.count >= 50 {
                        var page = 2
                        while page <= 10 {
                            if Task.isCancelled { break }
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
                    if Task.isCancelled { break }
                    AppLogger.error("Error syncing trades for account \(acc.label) (\(acc.id)): \(error.localizedDescription)")
                }
            }
            
            // 4. Sync purchases / challenges & evaluation fees across all tools and accounts
            await syncPurchases(into: dataStore, targetAccounts: allTargetAccounts, rawAccounts: rawAccountsList)
            
            // 5. Sync payouts & withdrawal settlements across ALL accounts
            await syncPayouts(into: dataStore, targetAccounts: allTargetAccounts, rawAccounts: rawAccountsList)
            
            lastSyncTime = Date()
            dataStore.rebuildAllAccounts()
            
            if dataStore.selectedAccountId == "default-acc" || dataStore.selectedAccountId.isEmpty {
                if let activeAcc = dataStore.mostRecentActiveAccount {
                    dataStore.selectAccount(id: activeAcc.id)
                } else if let firstWithTrade = dataStore.accounts.first(where: { acc in dataStore.trades.contains(where: { $0.accountId == acc.id }) }) {
                    dataStore.selectAccount(id: firstWithTrade.id)
                } else {
                    dataStore.selectAccount(id: "all")
                }
            }
            
            dataStore.saveToDisk(immediate: true)
            dataStore.objectWillChange.send()
            let activeCount = accountsList.filter { $0.status.lowercased() == "active" || $0.status.lowercased() == "available" }.count
            lastStatus = "Successfully synced \(accountsList.count) accounts (\(activeCount) active) and \(importedPositionsCount) positions from The5ers MCP."
            
            return accountsList.count
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled || error.localizedDescription.lowercased().contains("cancel") {
                lastStatus = "Sync cancelled."
                throw CancellationError()
            }
            lastStatus = "The5ers MCP sync error: \(error.localizedDescription)"
            throw error
        }
    }
    
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
    
    /// Sanitizes dictionary keys by removing whitespaces, underscores, and hyphens
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
    
    private func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
        for k in keys {
            if let val = dict[k] {
                return val
            }
        }
        return nil
    }
    
    /// Normalizes raw position record into SourcePosition model
    private func normalizePosition(from raw: [String: Any]) -> SourcePosition? {
        let row = sourceFields(raw)
        
        let rawSymbol = row["symbol"]
        let symbol = String(describing: rawSymbol ?? "").trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty && symbol.count <= 100 else { return nil }
        
        let sideVal = row["side"] ?? row["direction"]
        let sideStr = String(describing: sideVal ?? "").lowercased()
        let direction: TradeDirection? = {
            if sideStr.contains("buy") || sideStr == "long" { return .long }
            if sideStr.contains("sell") || sideStr == "short" { return .short }
            return nil
        }()
        guard let dir = direction else { return nil }
        
        let openKeys = ["opendate", "openedat", "opentime", "open_date", "opendatetime", "time", "timestamp", "datetime"]
        let openVal = firstValue(in: row, keys: openKeys)
        guard let (openedAtIso, openedAtDate) = sourceInstant(openVal) else {
            return nil
        }
        
        let qtyKeys = ["quantity", "lots", "volume", "size", "units"]
        let qtyVal = firstValue(in: row, keys: qtyKeys)
        guard let quantity = sourceNumber(qtyVal), quantity > 0 else {
            return nil
        }
        
        let entryKeys = ["entry", "openprice", "entryprice", "open_price", "price"]
        let entryVal = firstValue(in: row, keys: entryKeys)
        guard let entry = sourceNumber(entryVal) else {
            return nil
        }
        
        let closedFlag = firstValue(in: row, keys: ["isclosed", "closed", "isclose"])
        let rawStatusField = String(describing: firstValue(in: row, keys: ["status", "state"]) ?? "").lowercased()
        let isClosedByStatus = rawStatusField == "closed" || rawStatusField == "win" || rawStatusField == "loss"
        let isClosed = sourceBoolean(closedFlag) ?? (isClosedByStatus || row["closedate"] != nil || row["exit"] != nil || row["closetime"] != nil || row["closeprice"] != nil)
        
        let closeKeys = ["closedate", "closedat", "closetime", "close_date", "closedatetime", "exittime", "exitdate", "timeclose", "time_close"]
        let closeVal = firstValue(in: row, keys: closeKeys)
        var closedAtTuple = isClosed ? sourceInstant(closeVal) : nil
        
        let exitKeys = ["exit", "closeprice", "exitprice", "close_price", "price", "closedprice", "outprice"]
        let exitVal = firstValue(in: row, keys: exitKeys)
        var exit = isClosed ? sourceNumber(exitVal) : nil
        
        if isClosed {
            if closedAtTuple == nil {
                closedAtTuple = (openedAtIso, openedAtDate)
            }
            if exit == nil {
                exit = entry
            }
        }
        
        let pnlKeys = ["profitandloss", "netpnl", "net_pnl", "realizedpnl", "net", "profit", "pnl", "gross"]
        let pnlVal = firstValue(in: row, keys: pnlKeys)
        let netPnl = isClosed ? (sourceNumber(pnlVal) ?? 0) : 0
        
        if let cl = closedAtTuple, cl.date < openedAtDate {
            return nil
        }
        
        let provKeys = ["positionid", "ticket", "id", "dealid", "positionref"]
        let provVal = firstValue(in: row, keys: provKeys)
        let providerId: String? = {
            if let p = provVal {
                let s = String(describing: p).trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            return nil
        }()
        
        let feeVal = firstValue(in: row, keys: ["fee", "commission", "fees"])
        let fee = sourceNumber(feeVal)
        let swapVal = firstValue(in: row, keys: ["swap", "swaps"])
        let swap = sourceNumber(swapVal)
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
    
    /// Reconciles and merges remote positions from The5ers into local TradeDataStore
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
        
        // Group duplicate positions to compute disambiguation discriminators
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
            // Assign deterministic discriminator to distinguish identical concurrent positions
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
        
        for position in valid {
            let posIdentity = JournalIds.positionIdentity(
                symbol: position.symbol,
                direction: position.direction.rawValue,
                openedAt: position.openedAtIso,
                discriminator: position.identityDiscriminator
            )
            let tradeKey = JournalIds.the5ersTradeKey(sourceAccountId: acc.id, positionIdentity: posIdentity)
            
            let isClosed = position.closedAtDate != nil
            let rawNetProfit = position.netPnl
            let rawFee = position.fee ?? 0
            let rawSwap = position.swap ?? 0
            let feeCost = abs(rawFee)
            let swapCost = rawSwap < 0 ? abs(rawSwap) : Decimal.zero
            let swapCredit = rawSwap > 0 ? rawSwap : Decimal.zero
            // Signed swap: negative = cost charged, positive = credit received.
            let signedSwap = swapCredit - swapCost
            
            // The5ers MCP reports netPnl which already includes signed swap and commission.
            // Reverse costs for gross only (1:1 with source-repo/apps/web/src/server/the5ers/journal.ts lines 67-75).
            // Invariant: grossPnl - fees + swap == netPnl
            let accountCurrency = acc.currency.uppercased()
            let reportingCurrency = dataStore.currencyConversion.reportingCurrency.uppercased()
            let toReporting: (Decimal) -> Decimal = { amount in
                if accountCurrency == reportingCurrency { return amount }
                guard let converted = dataStore.currencyConversion.context.convert(
                    amount,
                    from: accountCurrency,
                    to: reportingCurrency
                ) else {
                    AppLogger.warning("No \(accountCurrency)->\(reportingCurrency) rate configured; The5ers amount \(amount) kept in \(accountCurrency).")
                    return amount
                }
                return converted
            }
            let netPnl = isClosed ? toReporting(rawNetProfit) : Decimal.zero
            let fees = toReporting(feeCost)
            let swap = toReporting(signedSwap)
            let grossPnl = netPnl + fees - swap
            
            let breakevenBand = JournalDefaultsEngine.breakevenThreshold(
                defaults: dataStore.defaults,
                entryPrice: position.entry,
                quantity: position.quantity,
                multiplier: AssetContractEngine.contractMultiplier(
                    for: position.symbol,
                    customMultipliers: dataStore.multipliers
                )
            )
            let status: TradeStatus = {
                if !isClosed { return .open }
                if abs(netPnl) <= max(breakevenBand, TradeReconstructionEngine.flatEpsilon) { return .breakeven }
                return netPnl > 0 ? .win : .loss
            }()
            
            let durationMs: Int64? = {
                guard isClosed, let closedDate = position.closedAtDate else { return nil }
                return Int64(closedDate.timeIntervalSince(position.openedAtDate) * 1000)
            }()
            
            let cleanAcc = journalAccId.cleanAccountId
            let openSec = Int64(position.openedAtDate.timeIntervalSince1970)
            let existingIdx = dataStore.trades.firstIndex(where: {
                $0.key == tradeKey ||
                ($0.accountId.cleanAccountId == cleanAcc &&
                 $0.symbol.uppercased() == position.symbol.uppercased() &&
                 $0.direction == position.direction &&
                 abs(Int64($0.openedAt.timeIntervalSince1970) - openSec) <= 2 &&
                 abs($0.quantity - position.quantity) < 0.001)
            })
            
            if let tIdx = existingIdx {
                var existing = dataStore.trades[tIdx]
                existing.accountId = journalAccId
                existing.status = status
                existing.closedAt = position.closedAtDate
                existing.openQuantity = isClosed ? 0 : position.quantity
                existing.avgExit = position.exit
                existing.grossPnl = grossPnl
                existing.fees = fees
                existing.swap = swap
                existing.netPnl = netPnl
                existing.durationMs = durationMs
                if existing.notes == nil || existing.notes?.isEmpty == true {
                    existing.notes = "Position synced from The5ers Hub (Ticket: \(position.providerId ?? ""))"
                }
                dataStore.trades[tIdx] = existing
                count += 1
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
                    swap: swap,
                    netPnl: netPnl,
                    executionCount: 0,
                    executionIds: [],
                    durationMs: durationMs,
                    notes: "Position synced from The5ers Hub (Ticket: \(position.providerId ?? ""))",
                    tags: ["the5ers", acc.program.lowercased()]
                )
                dataStore.trades.append(trade)
                count += 1
            }
        }
    }
    
    // MARK: - Purchase & Account Normalization
    
    /// Derives a clean, professional display name for a The5ers account matching the web source specification.
    public static func the5ersDefaultName(
        from item: [String: Any],
        fallbackLabel: String,
        platform: String? = nil,
        startingBalance: Decimal? = nil,
        balance: Decimal? = nil
    ) -> String {
        var fields: [String: Any] = [:]
        for (k, v) in item {
            let clean = k.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            fields[clean] = v
        }
        
        let pkgCandidates: [Any?] = [
            fields["packagename"],
            fields["programname"],
            fields["productname"],
            fields["planname"],
            fields["program"],
            fields["type"],
            fields["accounttype"]
        ]
        var packageName: String? = nil
        for cand in pkgCandidates {
            if let str = cand as? String, !str.trimmingCharacters(in: .whitespaces).isEmpty {
                let cleanStr = str.trimmingCharacters(in: .whitespaces)
                let l = cleanStr.lowercased()
                if !l.contains("standard") && l != "funded" && l != "active" {
                    packageName = cleanStr
                    break
                }
            }
        }
        
        var accountSize: Decimal? = startingBalance ?? balance
        let sizeCandidates: [Any?] = [
            fields["accountsize"],
            fields["startingbalance"],
            fields["initialbalance"],
            fields["nominalbalance"],
            fields["size"],
            fields["balance"]
        ]
        for cand in sizeCandidates {
            if let num = cand as? NSNumber, num.doubleValue > 0 {
                accountSize = Decimal(string: num.stringValue)
                break
            } else if let str = cand as? String, let dec = Decimal(string: str.trimmingCharacters(in: .whitespaces)), dec > 0 {
                accountSize = dec
                break
            }
        }
        
        var accountNumber: String? = nil
        let accNumCandidates: [Any?] = [
            fields["accountnumber"],
            fields["tradingaccountnumber"],
            fields["login"],
            fields["accountlogin"]
        ]
        for cand in accNumCandidates {
            if let num = cand as? NSNumber, num.intValue > 0 {
                accountNumber = num.stringValue
                break
            } else if let str = cand as? String, !str.isEmpty {
                accountNumber = str.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        let suffix: String? = {
            if let acc = accountNumber { return acc }
            let pattern = #"(?:…|\.{3}|[-_·\s])?(\d{3,12})\s*$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: fallbackLabel, range: NSRange(fallbackLabel.startIndex..., in: fallbackLabel)),
               let range = Range(match.range(at: 1), in: fallbackLabel) {
                return String(fallbackLabel[range])
            }
            return nil
        }()
        
        let pLower = (platform ?? String(describing: fields["platform"] ?? fields["tradingplatform"] ?? "")).lowercased()
        let platformTag: String = {
            if pLower.contains("meta-trader-5") || pLower.contains("mt5") { return "MT5" }
            if pLower.contains("meta-trader-4") || pLower.contains("mt4") { return "MT4" }
            if pLower.contains("c-trader") || pLower.contains("ctrader") { return "cTrader" }
            return "MT5"
        }()
        
        let leadTitle = packageName ?? "The5ers \(platformTag)"
        var parts: [String] = [leadTitle]
        
        if let sz = accountSize, sz > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 0
            if let formatted = formatter.string(from: sz as NSDecimalNumber),
               !leadTitle.contains(formatted) && !leadTitle.contains("\(sz)") {
                parts.append(formatted)
            }
        }
        
        if let s = suffix, !leadTitle.contains(s) {
            parts.append("#\(s)")
        }
        
        return parts.joined(separator: " · ")
    }
    
    private func isLikelyPurchaseDictionary(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        let hasCost = keys.contains("netpaid") || keys.contains("price") || keys.contains("cost") ||
                      keys.contains("fee") || keys.contains("amount") || keys.contains("total")
        let hasIdentity = keys.contains("id") || keys.contains("orderid") || keys.contains("purchaseid") ||
                          keys.contains("reference") || keys.contains("items") || keys.contains("placedat")
        return hasCost && hasIdentity
    }
    
    private func extractAnyPurchaseCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPurchaseCollection(from: parsed)
            }
            return []
        }
        if let arr = unwrapped as? [[String: Any]] {
            var results: [[String: Any]] = []
            for item in arr {
                let sub = extractAnyPurchaseCollection(from: item)
                if !sub.isEmpty {
                    results.append(contentsOf: sub)
                } else if isLikelyPurchaseDictionary(item) {
                    results.append(item)
                }
            }
            if !results.isEmpty { return results }
            return arr.filter { isLikelyPurchaseDictionary($0) }
        }
        if let dict = unwrapped as? [String: Any] {
            if isLikelyPurchaseDictionary(dict) {
                return [dict]
            }
            let possibleKeys = ["purchases", "orders", "items", "transactions", "history", "data", "lineitems", "rows", "records", "challenges", "invoices"]
            for k in possibleKeys {
                if let arr = dict[k] as? [[String: Any]], !arr.isEmpty {
                    return arr
                }
                if let subDict = dict[k] as? [String: Any] {
                    let sub = extractAnyPurchaseCollection(from: subDict)
                    if !sub.isEmpty { return sub }
                }
            }
            if let res = dict["result"] {
                let sub = extractAnyPurchaseCollection(from: res)
                if !sub.isEmpty { return sub }
            }
        }
        return []
    }
    
    @MainActor
    private func syncPurchases(
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount],
        rawAccounts: [[String: Any]] = []
    ) async {
        lastStatus = "Loading purchases and evaluation fees from the5ers_purchase..."
        var allPurchases: [[String: Any]] = []
        var seenPurchaseIds = Set<String>()
        
        // 1. Extract any purchases embedded inside raw account records
        for rawAcc in rawAccounts {
            let accRef = String(describing: rawAcc["ref"] ?? rawAcc["account_ref"] ?? rawAcc["id"] ?? "")
            let embedded = extractAnyPurchaseCollection(from: rawAcc)
            for var p in embedded {
                if p["account_ref"] == nil && !accRef.isEmpty { p["account_ref"] = accRef }
                let pId = String(describing: p["id"] ?? p["orderid"] ?? p["order_id"] ?? p["purchaseid"] ?? p["ref"] ?? UUID().uuidString)
                if !seenPurchaseIds.contains(pId) {
                    seenPurchaseIds.insert(pId)
                    allPurchases.append(p)
                }
            }
        }
        
        // 2. Query official the5ers_purchase operation 'list'
        let purchaseArgsList: [[String: Any]] = [
            ["operation": "list", "contract_version": "1.0", "limit": 50],
            ["operation": "list"]
        ]
        
        for pArgs in purchaseArgsList {
            if Task.isCancelled { break }
            if let res = try? await callMcpTool(name: "the5ers_purchase", arguments: pArgs),
               !(res["isError"] as? Bool ?? false) {
                let unwrapped = unwrapMcpToolResult(res)
                let rows = extractAnyPurchaseCollection(from: unwrapped)
                if !rows.isEmpty {
                    for r in rows {
                        let pId = String(describing: r["id"] ?? r["orderid"] ?? r["order_id"] ?? r["purchaseid"] ?? r["ref"] ?? UUID().uuidString)
                        if !seenPurchaseIds.contains(pId) {
                            seenPurchaseIds.insert(pId)
                            allPurchases.append(r)
                        }
                    }
                    break
                }
            }
        }
        
        // 3. For orders that have a 'ref', query 'accounts' to map directly to created accounts
        for i in allPurchases.indices {
            if Task.isCancelled { break }
            let pRef = String(describing: allPurchases[i]["ref"] ?? allPurchases[i]["purchase_ref"] ?? allPurchases[i]["id"] ?? "")
            if !pRef.isEmpty && (allPurchases[i]["account_ref"] == nil || String(describing: allPurchases[i]["account_ref"] ?? "").isEmpty) {
                if let accRes = try? await callMcpTool(name: "the5ers_purchase", arguments: [
                    "operation": "accounts",
                    "purchase_ref": pRef,
                    "contract_version": "1.0"
                ]), !(accRes["isError"] as? Bool ?? false) {
                    let unwrappedAcc = unwrapMcpToolResult(accRes)
                    let accRows = extractMcpCollection(unwrappedAcc, collectionKey: "accounts")
                    if let firstAcc = accRows.first, let createdRef = firstAcc["account_ref"] ?? firstAcc["ref"] {
                        allPurchases[i]["account_ref"] = String(describing: createdRef)
                    }
                }
            }
        }
        
        if !allPurchases.isEmpty {
            mergePurchases(allPurchases, into: dataStore, targetAccounts: targetAccounts)
        }
    }
    
    @MainActor
    private func mergePurchases(
        _ rawPurchases: [[String: Any]],
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount]
    ) {
        for purchase in rawPurchases {
            var fields = sourceFields(purchase)
            
            let status = String(describing: fields["status"] ?? "completed").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isRefunded = (fields["refunded"] as? Bool) ?? (fields["isrefunded"] as? Bool) ?? false
            let validStatuses = ["completed", "paid", "approved", "success", "successful", "settled", "active", "done"]
            guard (validStatuses.contains(status) || status.isEmpty) && !isRefunded else { continue }
            
            let rawDate = String(describing: fields["placedat"] ?? fields["date"] ?? fields["createdat"] ?? fields["purchasedat"] ?? fields["timestamp"] ?? "")
            let date = FlexibleDateParser.parse(rawDate) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = fmt.string(from: date)
            
            let currency = String(describing: fields["currency"] ?? "USD").uppercased()
            
            var itemNames: [String] = []
            var productType = "challenge_fee"
            var itemsTotal: Double = 0
            if let items = (fields["items"] ?? fields["purchases"] ?? fields["lineitems"]) as? [[String: Any]] {
                for it in items {
                    if let n = (it["name"] ?? it["productName"] ?? it["title"] ?? it["description"]) as? String, !n.isEmpty {
                        itemNames.append(n)
                    }
                    if let pt = (it["producttype"] ?? it["product_type"] ?? it["category"] ?? it["type"]) as? String, !pt.isEmpty {
                        productType = pt.lowercased()
                    }
                    if let np = it["netpaid"] as? NSNumber {
                        itemsTotal += np.doubleValue
                    } else if let np = it["netpaid"] as? String, let d = Double(np) {
                        itemsTotal += d
                    }
                }
            }
            
            var priceNum: Double = 0
            for k in ["price", "amount", "total", "netpaid", "net_paid", "cost", "value"] {
                if let val = fields[k] {
                    if let n = val as? NSNumber, n.doubleValue > 0 { priceNum = n.doubleValue; break }
                    if let s = val as? String {
                        let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if let d = Double(clean), d > 0 { priceNum = d; break }
                    }
                }
            }
            if priceNum == 0 && itemsTotal > 0 {
                priceNum = itemsTotal
            }
            guard priceNum > 0 else { continue }
            let amountMinor = Int64(round(priceNum * 100))
            
            let orderId = String(describing: fields["id"] ?? fields["orderid"] ?? fields["order_id"] ?? fields["purchaseid"] ?? fields["purchase_id"] ?? fields["ref"] ?? "")
            let title = itemNames.isEmpty ? (fields["name"] as? String ?? "The5ers Program Evaluation") : itemNames.joined(separator: ", ")
            let entryId: String = {
                if !orderId.isEmpty {
                    return "the5ers_purchase_\(orderId)"
                }
                let purchaseHash = JournalIds.sha256("\(dateStr)_\(currency)_\(amountMinor)_\(title)")
                return "the5ers_purchase_\(purchaseHash.prefix(16))"
            }()
            let shortRef = !orderId.isEmpty ? "Order #\(orderId.prefix(8))" : "Order #\(entryId.suffix(8))"
            
            let matchingAccId = targetAccounts.first(where: {
                title.contains("\($0.startingBalance ?? 0)") || $0.currency == currency
            })?.id
            let journalAccId = matchingAccId.map { $0.hasPrefix("the5ers_") ? $0 : "the5ers_\($0)" }
            
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == entryId ||
                (!orderId.isEmpty && ($0.id.contains(orderId) || $0.reference.contains(orderId))) ||
                ($0.occurredOn == dateStr && $0.amountMinor == amountMinor && $0.currency == currency && $0.kind == "expense")
            }) {
                var existing = dataStore.propEntries[existingIdx]
                existing.amountMinor = amountMinor
                existing.currency = currency
                existing.occurredOn = dateStr
                if existing.accountId == nil || existing.accountId?.isEmpty == true {
                    existing.accountId = journalAccId
                }
                dataStore.propEntries[existingIdx] = existing
            } else {
                let entry = PropEntryItem(
                    id: entryId,
                    accountId: journalAccId,
                    firm: "The5ers",
                    kind: "expense",
                    category: productType,
                    currency: currency,
                    amountMinor: amountMinor,
                    occurredOn: dateStr,
                    status: .completed,
                    reference: shortRef,
                    notes: "\(title) (The5ers official order)"
                )
                dataStore.propEntries.append(entry)
            }
        }
    }
    
    // MARK: - Payouts & Settlement Receipts Synchronization
    
    private func isLikelyPayoutDictionary(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        let hasAmount = keys.contains("amount") || keys.contains("payoutamount") || keys.contains("netamount") ||
                        keys.contains("grossamount") || keys.contains("grossprofit") || keys.contains("receivedamount") ||
                        keys.contains("withdrawalamount") || keys.contains("paidamount") || keys.contains("netpaid") ||
                        keys.contains("tradershare") || keys.contains("profit") || keys.contains("split") ||
                        keys.contains("profitsplit") || keys.contains("tradersplit")
        let hasIdentity = keys.contains("id") || keys.contains("payoutid") || keys.contains("withdrawalid") ||
                          keys.contains("requestid") || keys.contains("reference") || keys.contains("ref") ||
                          keys.contains("status") || keys.contains("date") || keys.contains("createdat") ||
                          keys.contains("processedat") || keys.contains("placedat")
        return hasAmount && hasIdentity
    }
    
    private func extractAnyPayoutCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPayoutCollection(from: parsed)
            }
            return []
        }
        if let arr = unwrapped as? [[String: Any]] {
            var results: [[String: Any]] = []
            for item in arr {
                let sub = extractAnyPayoutCollection(from: item)
                if !sub.isEmpty {
                    results.append(contentsOf: sub)
                } else if isLikelyPayoutDictionary(item) {
                    results.append(item)
                }
            }
            if !results.isEmpty { return results }
            return arr.filter { isLikelyPayoutDictionary($0) }
        }
        if let dict = unwrapped as? [String: Any] {
            if isLikelyPayoutDictionary(dict) {
                return [dict]
            }
            let possibleKeys = [
                "payouts", "withdrawals", "items", "history", "notifications",
                "data", "rows", "records", "payout_history", "list", "results",
                "transfers", "payments", "transactions", "payoutRequests", "requests", "settlements"
            ]
            for k in possibleKeys {
                if let arr = dict[k] as? [[String: Any]], !arr.isEmpty {
                    return arr
                }
                if let subDict = dict[k] as? [String: Any] {
                    let sub = extractAnyPayoutCollection(from: subDict)
                    if !sub.isEmpty { return sub }
                }
            }
            if let res = dict["result"] {
                let sub = extractAnyPayoutCollection(from: res)
                if !sub.isEmpty { return sub }
            }
        }
        return []
    }
    
    @MainActor
    private func syncPayouts(
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount],
        rawAccounts: [[String: Any]] = []
    ) async {
        lastStatus = "Loading withdrawal and payout history from the5ers_payout..."
        
        var allRawPayouts: [[String: Any]] = []
        var seenPayoutIds = Set<String>()
        
        // 1. Extract any payouts embedded inside raw account objects
        for rawAcc in rawAccounts {
            let accRef = String(describing: rawAcc["ref"] ?? rawAcc["account_ref"] ?? rawAcc["id"] ?? "")
            let accCurr = String(describing: rawAcc["currency"] ?? "USD")
            let embedded = extractAnyPayoutCollection(from: rawAcc)
            for var p in embedded {
                if p["account_ref"] == nil && !accRef.isEmpty { p["account_ref"] = accRef }
                if p["currency"] == nil { p["currency"] = accCurr }
                let pId = String(describing: p["id"] ?? p["payout_id"] ?? p["withdrawalid"] ?? UUID().uuidString)
                if !seenPayoutIds.contains(pId) {
                    seenPayoutIds.insert(pId)
                    allRawPayouts.append(p)
                }
            }
        }
        
        // 2. Query official the5ers_payout operations for target accounts
        var accountSplitMap: [String: Double] = [:]
        
        for acc in targetAccounts {
            if Task.isCancelled { break }
            
            // A. Query 'explain' for exact recorded split breakdown and userPayoutPercentage
            let explainArgs: [String: Any] = [
                "operation": "explain",
                "account_ref": acc.ref,
                "contract_version": "1.0"
            ]
            if let explainRes = try? await callMcpTool(name: "the5ers_payout", arguments: explainArgs),
               !(explainRes["isError"] as? Bool ?? false) {
                let unwrappedExplain = unwrapMcpToolResult(explainRes)
                if let explainDict = unwrappedExplain as? [String: Any] {
                    if let avail = explainDict["available"] as? [String: Any],
                       let split = avail["userPayoutPercentage"] as? NSNumber {
                        accountSplitMap[acc.ref] = split.doubleValue
                    }
                    if let latest = explainDict["latestPayout"] as? [String: Any] {
                        var p = latest
                        if p["account_ref"] == nil { p["account_ref"] = acc.ref }
                        if p["currency"] == nil { p["currency"] = acc.currency }
                        if let b = latest["breakdown"] as? [String: Any] {
                            for (k, v) in b { p[k] = v }
                        }
                        let pId = String(describing: p["id"] ?? p["payout_id"] ?? p["withdrawalid"] ?? UUID().uuidString)
                        if !seenPayoutIds.contains(pId) {
                            seenPayoutIds.insert(pId)
                            allRawPayouts.append(p)
                        }
                    }
                }
            }
            
            // B. Query 'history' for past completed/processed payouts
            let histArgs: [String: Any] = [
                "operation": "history",
                "account_ref": acc.ref,
                "contract_version": "1.0"
            ]
            if let histRes = try? await callMcpTool(name: "the5ers_payout", arguments: histArgs),
               !(histRes["isError"] as? Bool ?? false) {
                let unwrappedHist = unwrapMcpToolResult(histRes)
                let rows = extractAnyPayoutCollection(from: unwrappedHist)
                for var r in rows {
                    if r["account_ref"] == nil { r["account_ref"] = acc.ref }
                    if r["currency"] == nil { r["currency"] = acc.currency }
                    if let s = accountSplitMap[acc.ref], r["split_percent"] == nil {
                        r["split_percent"] = s
                    }
                    let pId = String(describing: r["id"] ?? r["payout_id"] ?? r["withdrawalid"] ?? UUID().uuidString)
                    if !seenPayoutIds.contains(pId) {
                        seenPayoutIds.insert(pId)
                        allRawPayouts.append(r)
                    }
                }
            }
        }
        
        for pay in allRawPayouts {
            let fields = sourceFields(pay)
            let id = String(describing: fields["id"] ?? fields["payoutid"] ?? fields["withdrawalid"] ?? fields["requestid"] ?? UUID().uuidString)
            let canonicalId = PropFirmEngine.canonicalPayoutId(id)
            
            let status = String(describing: fields["status"] ?? "completed").lowercased().trimmingCharacters(in: .whitespaces)
            let isReversed = (fields["reversed"] as? Bool) == true
            let isCompleted = ["completed", "paid", "received", "settled", "approved", "processed", "successful", "done", "transferred"].contains(status) || status.isEmpty
            
            // 1. Extract Trader Split percentage/ratio
            let splitPercentVal: Double? = {
                for key in [
                    "splitpercent", "split_percent", "profitsplit", "profit_split",
                    "tradersplit", "trader_split", "profitshare", "profit_share",
                    "split", "splitrate", "split_rate", "percentage", "rate", "share"
                ] {
                    if let sp = fields[key] {
                        if let n = sp as? NSNumber { return n.doubleValue }
                        if let s = sp as? String {
                            let clean = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean) { return d }
                        }
                    }
                }
                let payAccRef = String(describing: fields["accountref"] ?? fields["accountid"] ?? fields["ref"] ?? "")
                if let known = accountSplitMap[payAccRef] ?? accountSplitMap[payAccRef.cleanAccountId] {
                    return known
                }
                return nil
            }()
            
            // 2. Extract Explicit Gross Amount
            let explicitGross: Double? = {
                for k in ["grossamount", "gross_amount", "grossprofit", "gross_profit", "tradingprofit", "trading_profit", "profit"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                return nil
            }()
            
            // 3. Extract Explicit Net Received Amount
            let explicitNet: Double? = {
                for k in ["receivedamount", "received_amount", "netamount", "net_amount", "paidamount", "paid_amount", "netpaid", "traderprofit", "trader_profit", "tradershare", "trader_share", "payoutamount", "payout_amount", "withdrawalamount", "withdrawal_amount", "usershare", "user_share", "net"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                return nil
            }()
            
            // 4. Extract Generic Amount (often payout amount requested)
            let genericAmount: Double? = {
                for k in ["amount", "total", "price", "value"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                return nil
            }()
            
            let feeVal: Double = {
                if let f = fields["fee"] ?? fields["fees"] ?? fields["transferfee"] ?? fields["transfer_fee"] {
                    if let n = f as? NSNumber { return n.doubleValue }
                    if let s = f as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
                }
                return 0
            }()
            let feeMinor = Int64(round(feeVal * 100))
            
            // Determine split basis points (bps)
            var splitBps: Int = {
                if let sp = splitPercentVal, sp > 0 {
                    return Int(round(sp > 1.0 ? sp * 100 : sp * 10000))
                }
                if let net = explicitNet, let gross = explicitGross, gross > 0, net < gross {
                    return Int(round((net / gross) * 10000))
                }
                return 8000 // Standard The5ers trader split (80%)
            }()
            
            // Determine grossMinor and netReceivedMinor
            let grossMinor: Int64
            let netReceivedMinor: Int64
            
            if let eg = explicitGross, let en = explicitNet {
                grossMinor = Int64(round(eg * 100))
                netReceivedMinor = Int64(round(en * 100))
                if splitPercentVal == nil && grossMinor > 0 {
                    splitBps = Int(round(Double(netReceivedMinor) * 10000.0 / Double(grossMinor)))
                }
            } else if let eg = explicitGross {
                grossMinor = Int64(round(eg * 100))
                if let ga = genericAmount, ga < eg {
                    netReceivedMinor = Int64(round(ga * 100))
                    if splitPercentVal == nil && grossMinor > 0 {
                        splitBps = Int(round(Double(netReceivedMinor) * 10000.0 / Double(grossMinor)))
                    }
                } else {
                    netReceivedMinor = max(0, Int64((Double(grossMinor) * Double(splitBps) + 5000) / 10000) - feeMinor)
                }
            } else if let en = explicitNet {
                netReceivedMinor = Int64(round(en * 100))
                if let ga = genericAmount, ga > en {
                    grossMinor = Int64(round(ga * 100))
                    if splitPercentVal == nil && grossMinor > 0 {
                        splitBps = Int(round(Double(netReceivedMinor) * 10000.0 / Double(grossMinor)))
                    }
                } else {
                    grossMinor = splitBps > 0 ? Int64(round(Double(netReceivedMinor + feeMinor) * 10000.0 / Double(splitBps))) : netReceivedMinor
                }
            } else if let ga = genericAmount {
                // In a withdrawal/payout record, generic amount is the cash payout received
                netReceivedMinor = Int64(round(ga * 100))
                grossMinor = splitBps > 0 ? Int64(round(Double(netReceivedMinor + feeMinor) * 10000.0 / Double(splitBps))) : netReceivedMinor
            } else {
                continue
            }
            
            let dateVal = fields["receivedat"] ?? fields["paidat"] ?? fields["settledat"] ?? fields["paymentdate"] ?? fields["completedat"] ?? fields["requestedat"] ?? fields["createdat"] ?? fields["date"]
            let rawDate = String(describing: dateVal ?? "")
            let parsedDate = FlexibleDateParser.parse(rawDate) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = fmt.string(from: parsedDate)
            
            let payoutEntryId = "the5ers_payout_\(id)"
            let rcptId = "the5ers_rcpt_\(id)"
            let shortRef = "Payout #\(id.prefix(8))"
            
            let payAccRef = String(describing: fields["accountref"] ?? fields["accountid"] ?? fields["ref"] ?? "")
            let matchedAcc = targetAccounts.first(where: {
                $0.id == payAccRef || $0.ref == payAccRef || "the5ers_\($0.id)" == payAccRef || $0.id.cleanAccountId == payAccRef.cleanAccountId || $0.ref.cleanAccountId == payAccRef.cleanAccountId
            })
            let primaryAccId: String? = {
                if let m = matchedAcc {
                    return m.id.hasPrefix("the5ers_") ? m.id : "the5ers_\(m.id)"
                }
                if !payAccRef.isEmpty {
                    return payAccRef.hasPrefix("the5ers_") ? payAccRef : "the5ers_\(payAccRef)"
                }
                return targetAccounts.first?.id
            }()
            let currency = String(describing: fields["currency"] ?? matchedAcc?.currency ?? "USD").uppercased()
            
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == payoutEntryId ||
                PropFirmEngine.canonicalPayoutId($0.id) == canonicalId ||
                (!id.isEmpty && ($0.id.contains(id) || $0.reference.contains(id))) ||
                ($0.occurredOn == dateStr && $0.kind == "payout" && ($0.amountMinor == grossMinor || $0.amountMinor == netReceivedMinor))
            }) {
                var existing = dataStore.propEntries[existingIdx]
                existing.amountMinor = grossMinor
                existing.splitBps = splitBps
                existing.feeMinor = feeMinor
                existing.status = isCompleted ? .completed : .requested
                existing.occurredOn = dateStr
                if existing.accountId == nil || existing.accountId?.isEmpty == true {
                    existing.accountId = primaryAccId
                }
                dataStore.propEntries[existingIdx] = existing
            } else {
                let payoutEntry = PropEntryItem(
                    id: payoutEntryId,
                    accountId: primaryAccId,
                    firm: "The5ers",
                    kind: "payout",
                    category: "payout",
                    currency: currency,
                    amountMinor: grossMinor,
                    splitBps: splitBps,
                    feeMinor: feeMinor,
                    occurredOn: dateStr,
                    status: isCompleted ? .completed : .requested,
                    reference: shortRef,
                    notes: "The5ers Official Withdrawal"
                )
                dataStore.propEntries.append(payoutEntry)
            }
            
            // Settlement receipt records actual cash in-pocket
            if isCompleted && !isReversed {
                if let rIdx = dataStore.propReceipts.firstIndex(where: {
                    $0.id == rcptId ||
                    $0.payoutId == payoutEntryId ||
                    PropFirmEngine.canonicalPayoutId($0.payoutId) == canonicalId ||
                    (!id.isEmpty && ($0.id.contains(id) || $0.reference.contains(id))) ||
                    ($0.occurredOn == dateStr && $0.amountMinor == netReceivedMinor)
                }) {
                    var existingRcpt = dataStore.propReceipts[rIdx]
                    existingRcpt.payoutId = payoutEntryId
                    existingRcpt.amountMinor = netReceivedMinor
                    existingRcpt.occurredOn = dateStr
                    dataStore.propReceipts[rIdx] = existingRcpt
                } else {
                    let rcpt = PropReceiptItem(
                        id: rcptId,
                        payoutId: payoutEntryId,
                        kind: "receipt",
                        amountMinor: netReceivedMinor,
                        occurredOn: dateStr,
                        reference: "Receipt #\(id.prefix(8))",
                        notes: "The5ers Settlement Receipt"
                    )
                    dataStore.propReceipts.append(rcpt)
                }
            }
        }
    }
}
