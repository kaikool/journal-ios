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
    
    // Authoritative Hub / Broker Metrics
    public let profitAndLoss: Decimal?
    public let dailyProfitAndLoss: Decimal?
    public let unrealized: Decimal?
    public let totalNetProfit: Decimal?
    public let totalFees: Decimal?
    public let totalTrades: Int?
    public let winRate: Double?
    public let profitFactor: Double?
    public let tradingBlocked: Bool?
    
    // Authoritative Program Objectives & Progress
    public let profitTarget: Decimal?
    public let maxLoss: Decimal?
    public let maxDailyLoss: Decimal?
    public let minTradingDays: Int?
    public let currentTradingDays: Int?
    public let winningDays: Int?
    public let currentStepName: String?
    
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
        createdAt: String? = nil,
        profitAndLoss: Decimal? = nil,
        dailyProfitAndLoss: Decimal? = nil,
        unrealized: Decimal? = nil,
        totalNetProfit: Decimal? = nil,
        totalFees: Decimal? = nil,
        totalTrades: Int? = nil,
        winRate: Double? = nil,
        profitFactor: Double? = nil,
        tradingBlocked: Bool? = nil,
        profitTarget: Decimal? = nil,
        maxLoss: Decimal? = nil,
        maxDailyLoss: Decimal? = nil,
        minTradingDays: Int? = nil,
        currentTradingDays: Int? = nil,
        winningDays: Int? = nil,
        currentStepName: String? = nil
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
        self.profitAndLoss = profitAndLoss
        self.dailyProfitAndLoss = dailyProfitAndLoss
        self.unrealized = unrealized
        self.totalNetProfit = totalNetProfit
        self.totalFees = totalFees
        self.totalTrades = totalTrades
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.tradingBlocked = tradingBlocked
        self.profitTarget = profitTarget
        self.maxLoss = maxLoss
        self.maxDailyLoss = maxDailyLoss
        self.minTradingDays = minTradingDays
        self.currentTradingDays = currentTradingDays
        self.winningDays = winningDays
        self.currentStepName = currentStepName
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
    @Published public private(set) var isCancelledByUser: Bool = false
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
        if !mcpToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let stored = UserDefaults.standard.string(forKey: "the5ers_mcp_token"),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
    
    @MainActor
    public func cancelSync() {
        isCancelledByUser = true
        isSyncing = false
        lastStatus = "Synchronization cancelled by user."
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
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_client_id")
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
    
    /// Refreshes the OAuth access token using saved refresh token
    public func refreshAccessTokenIfNeeded() async throws -> String? {
        guard let refreshToken = UserDefaults.standard.string(forKey: "the5ers_mcp_refresh_token"), !refreshToken.isEmpty else {
            return nil
        }
        guard let url = URL(string: "\(Self.authHost)/oauth2/v1/apps/agentic/\(Self.tenantPath)/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let callbackScheme = "tradejournal"
        let redirectUri = "\(callbackScheme)://the5ers-callback"
        guard let clientId = try? await getOrRegisterClientId(redirectUri: redirectUri) else { return nil }
        
        let bodyParams = [
            "grant_type=refresh_token",
            "client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId)",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "resource=\(Self.mcpUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.mcpUrl)"
        ].joined(separator: "&")
        request.httpBody = bodyParams.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let newAccessToken = json["access_token"] as? String {
            if let newRefresh = json["refresh_token"] as? String {
                UserDefaults.standard.set(newRefresh, forKey: "the5ers_mcp_refresh_token")
            }
            await MainActor.run {
                self.configure(token: newAccessToken)
            }
            return newAccessToken
        }
        return nil
    }
    
    // MARK: - 2. JSON-RPC 2.0 MCP Client (`https://mcp.the5ers.com/mcp`)
    
    /// Initializes JSON-RPC protocol handshake with The5ers MCP server
    public func ensureInitialized() async throws {
        guard !isSessionInitialized else { return }
        guard isConfigured else { return }
        
        self.mcpSessionId = nil
        
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
        let effectiveToken = mcpToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            : mcpToken
        request.setValue("Bearer \(effectiveToken)", forHTTPHeaderField: "Authorization")
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
        let effectiveToken: String = {
            let direct = mcpToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !direct.isEmpty { return direct }
            return (UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        
        guard !effectiveToken.isEmpty else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bearer Session Token not configured"])
        }
        
        if mcpToken != effectiveToken {
            Task { @MainActor in
                self.mcpToken = effectiveToken
                self.isConnected = true
            }
        }
        
        rpcIdCounter += 1
        let currentId = rpcIdCounter
        
        guard let url = URL(string: Self.mcpUrl) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(effectiveToken)", forHTTPHeaderField: "Authorization")
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
        
        var (data, response) = try await session.data(for: request)
        guard var http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Auto-refresh token if 401 Unauthorized
        if http.statusCode == 401 {
            if let refreshedToken = try? await refreshAccessTokenIfNeeded() {
                var retryReq = request
                retryReq.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                if let (retriedData, retriedResponse) = try? await session.data(for: retryReq),
                   let retriedHttp = retriedResponse as? HTTPURLResponse, (200...299).contains(retriedHttp.statusCode) {
                    data = retriedData
                    http = retriedHttp
                }
            }
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
        
        isCancelledByUser = false
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
                if Task.isCancelled || isCancelledByUser { throw CancellationError() }
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
                            "contract_version": "1.0",
                            "page": page,
                            "limit": 50
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
                if Task.isCancelled || isCancelledByUser { throw CancellationError() }
                // Ignore contest accounts which belong to a separate space and cannot be read by standard operations
                if item["contest_account_ref"] != nil && item["ref"] == nil {
                    continue
                }
                let ref = String(describing: item["ref"] ?? item["account_ref"] ?? item["id"] ?? UUID().uuidString)
                let label = String(describing: item["label"] ?? item["name"] ?? "The5ers Account")
                var bal = Decimal(string: String(describing: item["balance"] ?? item["effectiveBalance"] ?? "0")) ?? 0
                var eq = Decimal(string: String(describing: item["equity"] ?? bal)) ?? bal
                let curr = String(describing: item["currency"] ?? "USD")
                let status = String(describing: item["status"] ?? "active")
                let prog = String(describing: item["type"] ?? item["accountType"] ?? item["program"] ?? "funded")
                let platform = String(describing: item["tradingPlatform"] ?? item["platform"] ?? item["tradingSystem"] ?? "MT5")
                let createdAt = item["createdAt"] as? String ?? item["creationDate"] as? String ?? item["created_at"] as? String
                
                // Deterministic persistent account ID (source-repo/apps/web/src/server/the5ers/data.ts:173-175: sha256([label, platform, stamp]))
                // Ephemeral opaque refs expire after 10m and are never used as persistent journal identity (docs/the5ers.md:16)
                let stamp: String = {
                    if let raw = createdAt, let d = FlexibleDateParser.parse(raw) {
                        let iso = ISO8601DateFormatter()
                        iso.formatOptions = [.withInternetDateTime]
                        return iso.string(from: d)
                    }
                    return createdAt ?? ""
                }()
                let stableId: String = {
                    if !stamp.isEmpty {
                        return JournalIds.sha256Hex([label, platform, stamp])
                    } else {
                        return JournalIds.sha256Hex([label, platform])
                    }
                }()
                
                // Authoritative initial capital detection (docs/the5ers.md:12: Never substitute current balance for starting capital)
                var explicitStartBal: Decimal? = nil
                let startCandidates: [Any?] = [
                    item["startingBalance"],
                    item["initialBalance"],
                    item["initial_balance"],
                    item["starting_balance"],
                    item["accountSize"],
                    item["account_size"],
                    item["nominalBalance"]
                ]
                for cand in startCandidates {
                    if let num = cand as? NSNumber, num.doubleValue > 0 {
                        explicitStartBal = Decimal(string: num.stringValue); break
                    } else if let s = cand as? String, let dec = Decimal(string: s.trimmingCharacters(in: .whitespaces)), dec > 0 {
                        explicitStartBal = dec; break
                    }
                }
                
                // Concurrently query Authoritative Balance, Statistics, and Journey in parallel
                var accProfitAndLoss: Decimal? = nil
                var accDailyProfitAndLoss: Decimal? = nil
                var accUnrealized: Decimal? = nil
                var accTradingBlocked: Bool? = nil
                var accTotalTrades: Int? = nil
                var accWinRate: Double? = nil
                var accProfitFactor: Double? = nil
                var accTotalFees: Decimal? = nil
                var authoritativeWinningDays: Int? = nil
                var authoritativeTradingDays: Int? = nil
                var authoritativeProgramName: String? = nil
                var authoritativeStepName: String? = nil
                var authoritativeAccountType: String? = nil
                var authoritativeProfitTarget: Decimal? = nil
                var authoritativeMaxLoss: Decimal? = nil
                var authoritativeMaxDailyLoss: Decimal? = nil
                var authoritativeMinTradingDays: Int? = nil
                
                async let balTask: [String: Any]? = {
                    let balArgs: [String: Any] = [
                        "operation": "balance",
                        "account_ref": ref,
                        "contract_version": "1.0"
                    ]
                    return try? await self.callMcpTool(name: "the5ers_account", arguments: balArgs)
                }()
                
                async let statsTask: [String: Any]? = {
                    let statsArgs: [String: Any] = [
                        "operation": "statistics",
                        "account_ref": ref,
                        "contract_version": "1.0"
                    ]
                    return try? await self.callMcpTool(name: "the5ers_account", arguments: statsArgs)
                }()
                
                async let journeyTask: [String: Any]? = {
                    let journeyArgs: [String: Any] = [
                        "operation": "journey",
                        "account_ref": ref,
                        "contract_version": "1.0"
                    ]
                    return try? await self.callMcpTool(name: "the5ers_program", arguments: journeyArgs)
                }()
                
                let (bRes, sRes, jRes) = await (balTask, statsTask, journeyTask)
                
                // Parse Authoritative Balance
                if let bRes = bRes, !(bRes["isError"] as? Bool ?? false) {
                    let uBal = unwrapMcpToolResult(bRes)
                    if let bDict = (uBal as? [String: Any])?["data"] as? [String: Any] ?? uBal as? [String: Any] {
                        if let initB = sourceNumber(bDict["initialBalance"] ?? bDict["baseBalance"] ?? bDict["startingBalance"]), initB > 0 {
                            explicitStartBal = initB
                        }
                        if let cb = sourceNumber(bDict["balance"]), cb > 0 {
                            bal = cb
                        }
                        if let ce = sourceNumber(bDict["equity"]), ce > 0 {
                            eq = ce
                        }
                        accProfitAndLoss = sourceNumber(bDict["profitAndLoss"] ?? bDict["profit_and_loss"] ?? bDict["pnl"] ?? bDict["netProfit"])
                        accDailyProfitAndLoss = sourceNumber(bDict["dailyProfitAndLoss"] ?? bDict["daily_profit_and_loss"] ?? bDict["dailyPnl"])
                        accUnrealized = sourceNumber(bDict["unrealized"] ?? bDict["floatingProfit"] ?? bDict["unrealizedPnl"])
                        if let tb = bDict["tradingBlocked"] as? Bool ?? (bDict["trading_blocked"] as? Bool) {
                            accTradingBlocked = tb
                        }
                    }
                }
                
                // Parse Authoritative Statistics
                if let sRes = sRes, !(sRes["isError"] as? Bool ?? false) {
                    let uStats = unwrapMcpToolResult(sRes)
                    if let sDict = (uStats as? [String: Any])?["data"] as? [String: Any] ?? uStats as? [String: Any] {
                        if let tt = sDict["totalTrades"] as? Int ?? (sDict["tradesCount"] as? Int) ?? (sDict["total_trades"] as? Int) {
                            accTotalTrades = tt
                        } else if let num = sDict["totalTrades"] as? NSNumber {
                            accTotalTrades = num.intValue
                        }
                        if let wr = sDict["winRate"] as? Double ?? (sDict["win_rate"] as? Double) {
                            accWinRate = wr > 1.0 ? wr / 100.0 : wr
                        } else if let num = sDict["winRate"] as? NSNumber {
                            let d = num.doubleValue
                            accWinRate = d > 1.0 ? d / 100.0 : d
                        }
                        if let pf = sDict["profitFactor"] as? Double ?? (sDict["profit_factor"] as? Double) {
                            accProfitFactor = pf
                        } else if let num = sDict["profitFactor"] as? NSNumber {
                            accProfitFactor = num.doubleValue
                        }
                        accTotalFees = sourceNumber(sDict["totalFees"] ?? sDict["fees"] ?? sDict["total_fees"])
                        
                        if let wd = sDict["winningDays"] as? Int ?? (sDict["profitableDays"] as? Int) ?? (sDict["winning_days"] as? Int) {
                            authoritativeWinningDays = wd
                        } else if let num = sDict["winningDays"] as? NSNumber {
                            authoritativeWinningDays = num.intValue
                        }
                        if let td = sDict["tradingDays"] as? Int ?? (sDict["activeDays"] as? Int) ?? (sDict["trading_days"] as? Int) {
                            authoritativeTradingDays = td
                        } else if let num = sDict["tradingDays"] as? NSNumber {
                            authoritativeTradingDays = num.intValue
                        }
                    }
                }
                
                // Parse Authoritative Program & Objectives from Journey
                if let jRes = jRes, !(jRes["isError"] as? Bool ?? false) {
                    let uJourney = unwrapMcpToolResult(jRes)
                    if let jData = (uJourney as? [String: Any])?["data"] as? [String: Any] ?? uJourney as? [String: Any],
                       let auth = jData["authoritative"] as? [String: Any] {
                        if let pName = auth["programName"] as? String, !pName.trimmingCharacters(in: .whitespaces).isEmpty {
                            authoritativeProgramName = pName.trimmingCharacters(in: .whitespaces)
                        }
                        if let currStep = auth["currentStep"] as? [String: Any] {
                            if let sName = currStep["name"] as? String, !sName.trimmingCharacters(in: .whitespaces).isEmpty {
                                authoritativeStepName = sName.trimmingCharacters(in: .whitespaces)
                            }
                            if let ph = currStep["phase"] as? String, !ph.trimmingCharacters(in: .whitespaces).isEmpty {
                                authoritativeAccountType = ph.trimmingCharacters(in: .whitespaces)
                            }
                            authoritativeProfitTarget = sourceNumber(currStep["profitTarget"] ?? currStep["target"])
                        }
                        if let reqs = auth["requirements"] as? [String: Any] {
                            if authoritativeProfitTarget == nil {
                                authoritativeProfitTarget = sourceNumber(reqs["profitTarget"] ?? reqs["target"])
                            }
                            authoritativeMaxLoss = sourceNumber(reqs["maxLoss"] ?? reqs["maxTotalLoss"] ?? reqs["maximumLoss"] ?? reqs["lossLimit"])
                            authoritativeMaxDailyLoss = sourceNumber(reqs["maxDailyLoss"] ?? reqs["dailyLoss"] ?? reqs["dailyLossLimit"])
                            if let mtd = reqs["minTradingDays"] as? Int ?? (reqs["minimumTradingDays"] as? Int) {
                                authoritativeMinTradingDays = mtd
                            } else if let num = reqs["minTradingDays"] as? NSNumber {
                                authoritativeMinTradingDays = num.intValue
                            }
                        }
                    }
                }
                
                // Resolve standard prop tier from metadata (e.g. 50K evaluation account)
                let resolvedStartBal: Decimal? = {
                    if let ex = explicitStartBal, ex > 0 { return ex }
                    let combined = "\(label.lowercased()) \(prog.lowercased())"
                    if combined.contains("50k") || combined.contains("50,000") || combined.contains("50000") { return 50000 }
                    if combined.contains("100k") || combined.contains("100,000") || combined.contains("100000") { return 100000 }
                    if combined.contains("25k") || combined.contains("25,000") || combined.contains("25000") { return 25000 }
                    if combined.contains("10k") || combined.contains("10,000") || combined.contains("10000") { return 10000 }
                    if combined.contains("5k") || combined.contains("5,000") || combined.contains("5000") { return 5000 }
                    if combined.contains("60k") || combined.contains("60,000") || combined.contains("60000") { return 60000 }
                    if combined.contains("200k") || combined.contains("200,000") || combined.contains("200000") { return 200000 }
                    if combined.contains("20k") || combined.contains("20,000") || combined.contains("20000") { return 20000 }
                    if bal >= 40000 && bal <= 55000 { return 50000 }
                    if bal >= 80000 && bal <= 110000 { return 100000 }
                    return nil
                }()
                
                let defaultName = Self.the5ersDefaultName(
                    from: item,
                    fallbackLabel: label,
                    platform: platform,
                    startingBalance: resolvedStartBal,
                    balance: bal,
                    authoritativeProgramName: authoritativeProgramName,
                    authoritativeStepName: authoritativeStepName,
                    authoritativeAccountType: authoritativeAccountType
                )
                let cleanLabel = defaultName.isEmpty ? Formatters.cleanAccountName(label, balance: resolvedStartBal) : defaultName
                
                accountsList.append(The5ersMcpAccount(
                    id: stableId,
                    ref: ref,
                    label: cleanLabel,
                    platform: platform,
                    balance: bal,
                    equity: eq,
                    currency: curr,
                    status: status,
                    program: prog,
                    startingBalance: resolvedStartBal,
                    createdAt: createdAt,
                    profitAndLoss: accProfitAndLoss,
                    dailyProfitAndLoss: accDailyProfitAndLoss,
                    unrealized: accUnrealized,
                    totalNetProfit: accProfitAndLoss,
                    totalFees: accTotalFees,
                    totalTrades: accTotalTrades,
                    winRate: accWinRate,
                    profitFactor: accProfitFactor,
                    tradingBlocked: accTradingBlocked,
                    profitTarget: authoritativeProfitTarget,
                    maxLoss: authoritativeMaxLoss,
                    maxDailyLoss: authoritativeMaxDailyLoss,
                    minTradingDays: authoritativeMinTradingDays,
                    currentTradingDays: authoritativeTradingDays,
                    winningDays: authoritativeWinningDays,
                    currentStepName: authoritativeStepName
                ))
            }
            
            if accountsList.isEmpty {
                lastStatus = "The5ers MCP responded successfully but no trading accounts were found."
                return 0
            }
            
            // Sync accounts into local PropAccountItem and Account models
            for acc in accountsList {
                let rawStatus = acc.status.trimmingCharacters(in: .whitespaces).lowercased()
                let isBlocked = (acc.tradingBlocked == true)
                let mappedStatus: PropStatus = {
                    // 1. Terminated / Breached / Failed / Disqualified / Violated (Highest priority)
                    if rawStatus.contains("term") || rawStatus.contains("breach") || rawStatus.contains("fail") || rawStatus.contains("viola") || rawStatus.contains("disqual") {
                        return .breached
                    }
                    // 2. Passed / Qualified
                    if rawStatus.contains("pass") || rawStatus.contains("qualif") {
                        return .passed
                    }
                    // 3. Closed / Ended / Expired / Archived
                    if rawStatus.contains("close") || rawStatus.contains("ended") || rawStatus.contains("expir") || rawStatus.contains("arch") {
                        return .closed
                    }
                    // 4. Inactive / Disabled
                    if rawStatus.contains("inact") || rawStatus.contains("disab") {
                        return .inactive
                    }
                    // 5. If broker/Hub balance has tradingBlocked == true, account is terminated/halted
                    if isBlocked {
                        return .closed
                    }
                    // 6. Explicit Active only (exact tokens, never substring 'trad' that matched 'trading_blocked')
                    if rawStatus == "active" || rawStatus == "open" || rawStatus == "available" || rawStatus == "trading" {
                        return .active
                    }
                    return .closed
                }()
                
                let rawProg = acc.program.trimmingCharacters(in: .whitespaces).lowercased()
                let rawLabel = acc.label.trimmingCharacters(in: .whitespaces).lowercased()
                let mappedProgram: PropProgram = {
                    if rawProg.contains("instant") || rawLabel.contains("instant") { return .instantFunded }
                    if rawProg.contains("step2") || rawProg.contains("step 2") || rawProg.contains("phase2") || rawProg.contains("phase 2") || rawProg.contains("verification") || rawLabel.contains("phase 2") || rawLabel.contains("step 2") || rawLabel.contains("high stakes - 2") { return .verification }
                    if rawProg.contains("fund") || rawProg.contains("live") || rawProg.contains("master") || rawProg.contains("step 3") || rawProg.contains("phase 3") || rawLabel.contains("funded") || rawLabel.contains("live") || rawLabel.contains("step 3") || rawLabel.contains("phase 3") { return .funded }
                    return .evaluation
                }()
                
                let startingMinor = NSDecimalNumber(decimal: (acc.startingBalance ?? acc.balance) * 100).int64Value
                let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
                let isActive = (mappedStatus == .active)
                
                let pnlMinor: Int64? = {
                    if let pnl = acc.profitAndLoss ?? acc.totalNetProfit {
                        return NSDecimalNumber(decimal: pnl * 100).int64Value
                    }
                    return nil
                }()
                let balMinor: Int64 = NSDecimalNumber(decimal: acc.balance * 100).int64Value
                let eqMinor: Int64? = acc.equity.map { NSDecimalNumber(decimal: $0 * 100).int64Value }
                let feesMinor: Int64? = {
                    if let f = acc.totalFees {
                        return NSDecimalNumber(decimal: abs(f) * 100).int64Value
                    }
                    return nil
                }()
                
                // Extract account login/number to link with existing cTrader trading account
                let accountNumber: String? = {
                    let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: acc.label, range: NSRange(acc.label.startIndex..., in: acc.label)),
                       let range = Range(match.range(at: 1), in: acc.label) {
                        return String(acc.label[range])
                    }
                    return nil
                }()
                
                let existingLinkedAcc = dataStore.accounts.first(where: {
                    $0.id == journalAccId ||
                    $0.name == acc.label ||
                    (accountNumber != nil && ($0.id.cleanAccountId == accountNumber! || $0.name.contains(accountNumber!)))
                })
                let linkedAccountId = existingLinkedAcc?.id ?? journalAccId
                
                if let existingIndex = dataStore.propAccounts.firstIndex(where: {
                    TradeDataStore.isSameAccountId($0.id, journalAccId) ||
                    $0.name == acc.label ||
                    (accountNumber != nil && ($0.id.cleanAccountId == accountNumber! || $0.name.contains(accountNumber!)))
                }) {
                    let old = dataStore.propAccounts[existingIndex]
                    dataStore.propAccounts[existingIndex] = PropAccountItem(
                        id: old.id,
                        firm: "The5ers",
                        name: acc.label,
                        program: mappedProgram,
                        status: mappedStatus,
                        currency: acc.currency,
                        sizeMinor: startingMinor,
                        parentId: old.parentId,
                        journalAccountId: linkedAccountId,
                        openedOn: old.openedOn,
                        closedOn: old.closedOn,
                        renewalOn: old.renewalOn,
                        renewalMinor: old.renewalMinor,
                        notes: old.notes,
                        archived: old.archived,
                        revision: old.revision + 1,
                        createdAt: old.createdAt,
                        updatedAt: JournalIds.nowIso(),
                        balanceMinor: balMinor,
                        equityMinor: eqMinor,
                        netPnlMinor: pnlMinor,
                        totalFeesMinor: feesMinor,
                        totalTrades: acc.totalTrades,
                        winRate: acc.winRate,
                        profitFactor: acc.profitFactor,
                        profitTargetMinor: acc.profitTarget.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        maxLossMinor: acc.maxLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        maxDailyLossMinor: acc.maxDailyLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        minTradingDays: acc.minTradingDays,
                        currentTradingDays: acc.currentTradingDays,
                        winningDays: acc.winningDays,
                        currentStepName: acc.currentStepName
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
                        journalAccountId: linkedAccountId,
                        openedOn: acc.createdAt ?? DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
                        notes: "Synced from The5ers MCP Hub (Protocol 2025-03-26)",
                        archived: false,
                        balanceMinor: balMinor,
                        equityMinor: eqMinor,
                        netPnlMinor: pnlMinor,
                        totalFeesMinor: feesMinor,
                        totalTrades: acc.totalTrades,
                        winRate: acc.winRate,
                        profitFactor: acc.profitFactor,
                        profitTargetMinor: acc.profitTarget.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        maxLossMinor: acc.maxLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        maxDailyLossMinor: acc.maxDailyLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                        minTradingDays: acc.minTradingDays,
                        currentTradingDays: acc.currentTradingDays,
                        winningDays: acc.winningDays,
                        currentStepName: acc.currentStepName
                    )
                    dataStore.propAccounts.append(newPropAccount)
                }
                
                if let accIdx = dataStore.accounts.firstIndex(where: {
                    TradeDataStore.isSameAccountId($0.id, journalAccId) ||
                    $0.name == acc.label ||
                    (accountNumber != nil && ($0.id.cleanAccountId == accountNumber! || $0.name.contains(accountNumber!)))
                }) {
                    var old = dataStore.accounts[accIdx]
                    old.name = acc.label
                    old.broker = "The5ers"
                    old.currency = acc.currency
                    if let sb = acc.startingBalance, sb > 0 {
                        old.initialBalance = sb
                    }
                    old.autoSync = isActive
                    old.lastSyncAt = Date()
                    old.propProgram = mappedProgram.rawValue
                    dataStore.accounts[accIdx] = old
                } else {
                    let newAcc = Account(
                        id: journalAccId,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? (acc.balance > 0 ? acc.balance : 50000),
                        autoSync: isActive,
                        archivedAt: nil,
                        visibleInJournal: true,
                        propProgram: mappedProgram.rawValue
                    )
                    dataStore.accounts.append(newAcc)
                }
            }
            
            // Official MCP accounts with valid session-minted account_ref
            let allTargetAccounts: [The5ersMcpAccount] = accountsList
            
            // Prioritize active accounts to stream data to UI immediately
            let accountsToSyncPositions = allTargetAccounts.sorted { a, b in
                let aActive = a.status.lowercased() == "active" || a.status.lowercased() == "trading"
                let bActive = b.status.lowercased() == "active" || b.status.lowercased() == "trading"
                if aActive != bActive { return aActive && !bActive }
                return a.label < b.label
            }
            
            var importedPositionsCount = 0
            for (idx, acc) in accountsToSyncPositions.enumerated() {
                if Task.isCancelled || isCancelledByUser { break }
                lastStatus = "Syncing trades (\(idx + 1)/\(accountsToSyncPositions.count)): \(acc.label)..."
                await Task.yield()
                
                let posArgs: [String: Any] = [
                    "operation": "list",
                    "account_ref": acc.ref,
                    "view": "all",
                    "page": 1,
                    "limit": 100,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                
                do {
                    var posResult = try await callMcpTool(name: "the5ers_positions", arguments: posArgs)
                    if let isErr = posResult["isError"] as? Bool, isErr {
                        // Resilient retry without request_context
                        let fbArgs: [String: Any] = [
                            "operation": "list",
                            "account_ref": acc.ref,
                            "view": "all",
                            "contract_version": "1.0"
                        ]
                        if let fbRes = try? await callMcpTool(name: "the5ers_positions", arguments: fbArgs),
                           !(fbRes["isError"] as? Bool ?? false) {
                            posResult = fbRes
                        } else {
                            AppLogger.error("The5ers MCP reported error for account \(acc.label) (\(acc.id)): \(posResult)")
                            // Check embedded positions in raw account record
                            if let rawAcc = rawAccountsList.first(where: { ($0["ref"] as? String) == acc.ref || ($0["account_ref"] as? String) == acc.ref || ($0["id"] as? String) == acc.id }) {
                                let embeddedPos = extractMcpCollection(rawAcc, collectionKey: "positions")
                                if !embeddedPos.isEmpty {
                                    mergePositions(embeddedPos, for: acc, into: dataStore, count: &importedPositionsCount)
                                }
                            }
                            continue
                        }
                    }
                    let unwrappedPos = unwrapMcpToolResult(posResult)
                    var rawPositions = extractMcpCollection(unwrappedPos, collectionKey: "positions")
                    if rawPositions.isEmpty {
                        // Check embedded positions in raw account record
                        if let rawAcc = rawAccountsList.first(where: { ($0["ref"] as? String) == acc.ref || ($0["account_ref"] as? String) == acc.ref || ($0["id"] as? String) == acc.id }) {
                            let embeddedPos = extractMcpCollection(rawAcc, collectionKey: "positions")
                            if !embeddedPos.isEmpty {
                                rawPositions = embeddedPos
                            }
                        }
                    }
                    mergePositions(rawPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                    
                    // Paginate if full page returned or pagination indicates more
                    let posPagination = (unwrappedPos as? [String: Any])?["pagination"] as? [String: Any]
                    let initialHasMore = (posPagination?["has_more"] as? Bool) ?? (rawPositions.count >= 100)
                    
                    if initialHasMore {
                        var page = 2
                        while page <= 20 {
                            if Task.isCancelled || isCancelledByUser { break }
                            var pArgs = posArgs
                            pArgs["page"] = page
                            guard let nextRes = try? await callMcpTool(name: "the5ers_positions", arguments: pArgs) else { break }
                            let nextUnwrapped = unwrapMcpToolResult(nextRes)
                            let nextPositions = extractMcpCollection(nextUnwrapped, collectionKey: "positions")
                            if nextPositions.isEmpty { break }
                            mergePositions(nextPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                            let nextPag = (nextUnwrapped as? [String: Any])?["pagination"] as? [String: Any]
                            let hasMore = (nextPag?["has_more"] as? Bool) ?? (nextPositions.count >= 100)
                            if !hasMore { break }
                            page += 1
                        }
                    }
                } catch {
                    if Task.isCancelled || isCancelledByUser { break }
                    AppLogger.error("Error syncing trades for account \(acc.label) (\(acc.id)): \(error.localizedDescription)")
                }
            }
            
            if Task.isCancelled || isCancelledByUser { throw CancellationError() }
            
            // 4. Sync purchases / challenges & evaluation fees across official MCP tools
            await syncPurchases(into: dataStore, targetAccounts: allTargetAccounts, rawAccounts: rawAccountsList)
            
            if Task.isCancelled || isCancelledByUser { throw CancellationError() }
            
            // 5. Sync payouts & withdrawal settlements strictly for funded accounts
            await syncPayouts(into: dataStore, targetAccounts: allTargetAccounts, rawAccounts: rawAccountsList)
            
            lastSyncTime = Date()
            dataStore.rebuildAllAccounts()
            
            if dataStore.selectedAccountId == "default-acc" || dataStore.selectedAccountId.isEmpty {
                dataStore.selectAccount(id: "all")
            }
            
            dataStore.saveToDisk(immediate: true)
            dataStore.objectWillChange.send()
            let activeCount = accountsList.filter { $0.status.lowercased() == "active" || $0.status.lowercased() == "available" }.count
            lastStatus = "Successfully synced \(accountsList.count) accounts (\(activeCount) active) and \(importedPositionsCount) positions from The5ers MCP."
            
            return accountsList.count
        } catch {
            if Task.isCancelled || isCancelledByUser || error is CancellationError || (error as? URLError)?.code == .cancelled || error.localizedDescription.lowercased().contains("cancel") {
                isCancelledByUser = false
                lastStatus = "Synchronization cancelled by user."
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
        
        // Robust closed status: boolean flag, status token, or presence of close date/exit price/realized PnL
        let isClosed: Bool = {
            if let b = sourceBoolean(firstValue(in: row, keys: ["isclosed", "closed", "isclose"])) {
                return b
            }
            let st = String(describing: row["status"] ?? "").lowercased()
            if st.contains("close") || st == "filled" || st == "done" || st.contains("exit") || st.contains("history") { return true }
            if st.contains("open") { return false }
            
            // Check if any close date/time exists
            let hasCloseDate = firstValue(in: row, keys: [
                "closedate", "closedat", "closetime", "close_date", "close_time",
                "closedatetime", "exittime", "exit_time", "exitdate", "timeclose",
                "time_close", "outtime", "out_time"
            ]) != nil
            if hasCloseDate { return true }
            
            // Check if exit price is present
            let hasExitPrice = sourceNumber(firstValue(in: row, keys: [
                "exit", "closeprice", "exitprice", "close_price", "exit_price", "closedprice", "outprice", "out_price"
            ])) != nil
            if hasExitPrice { return true }
            
            // Check if non-zero or explicit profitAndLoss field is present
            let hasRealizedPnl = sourceNumber(firstValue(in: row, keys: [
                "profitandloss", "profit_and_loss", "netpnl", "net_pnl", "realizedpnl", "realized_pnl"
            ])) != nil
            if hasRealizedPnl { return true }
            
            return false
        }()
        
        let closedAtTuple: (iso: String, date: Date)?
        let exit: Decimal?
        let netPnl: Decimal
        
        if isClosed {
            let closeKeys = [
                "closedate", "closedat", "closetime", "close_date", "close_time",
                "closedatetime", "exittime", "exit_time", "exitdate", "timeclose",
                "time_close", "outtime", "out_time"
            ]
            let closeVal = firstValue(in: row, keys: closeKeys)
            if let cl = sourceInstant(closeVal) {
                closedAtTuple = cl.date >= openedAtDate ? cl : (openedAtIso, openedAtDate)
            } else {
                closedAtTuple = (openedAtIso, openedAtDate)
            }
            
            let exitKeys = [
                "exit", "closeprice", "exitprice", "close_price", "exit_price",
                "closedprice", "outprice", "out_price"
            ]
            let exitVal = firstValue(in: row, keys: exitKeys)
            exit = sourceNumber(exitVal) ?? entry
            
            let pnlKeys = [
                "profitandloss", "profit_and_loss", "netpnl", "net_pnl", "realizedpnl",
                "realized_pnl", "net", "profit", "pnl"
            ]
            let pnlVal = firstValue(in: row, keys: pnlKeys)
            netPnl = sourceNumber(pnlVal) ?? 0
        } else {
            closedAtTuple = nil
            exit = nil
            netPnl = 0
        }
        
        let provKeys = ["positionid", "ticket", "id", "dealid", "positionref", "position_ref", "orderid", "order_id"]
        let provVal = firstValue(in: row, keys: provKeys)
        let providerId: String? = {
            if let p = provVal {
                let s = String(describing: p).trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            return nil
        }()
        
        let feeVal = firstValue(in: row, keys: ["fee", "commission", "fees", "commissions", "totalfees", "brokerfee", "broker_fee", "orderfee", "order_fee", "cost", "costs", "comm"])
        let fee = sourceNumber(feeVal)
        let swapVal = firstValue(in: row, keys: ["swap", "swaps", "totalswap", "total_swap", "rollover", "financing", "interest", "overnight"])
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
        let targetAccId = dataStore.propAccounts.first(where: {
            TradeDataStore.isSameAccountId($0.id, journalAccId) ||
            $0.id == acc.id ||
            $0.name == acc.label
        })?.journalAccountId ?? journalAccId
        
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
            let rawFee = abs(position.fee ?? 0)
            let rawSwap = position.swap ?? 0
            
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
            let fees = isClosed ? toReporting(rawFee) : Decimal.zero
            let swap: Decimal? = position.swap != nil ? toReporting(rawSwap) : nil
            // Authoritative invariant from Execution.swift: netPnl == grossPnl - fees + swapAmount
            // Reverse costs for gross calculation: grossPnl = netPnl + fees - swapAmount
            let grossPnl = netPnl + fees - (swap ?? 0)
            
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
            
            let openSec = Int64(position.openedAtDate.timeIntervalSince1970)
            let existingIdx = dataStore.trades.firstIndex(where: {
                if $0.key == tradeKey { return true }
                // If this position has an authoritative provider ticket, match by ticket in notes
                if let pid = position.providerId, !pid.isEmpty {
                    if let notes = $0.notes, notes.contains("Ticket: \(pid)") {
                        return true
                    }
                    return false
                }
                // Fallback fuzzy match only when neither trade has a provider ticket
                return $0.symbol.uppercased() == position.symbol.uppercased() &&
                       $0.direction == position.direction &&
                       abs(Int64($0.openedAt.timeIntervalSince1970) - openSec) <= 1 &&
                       abs($0.quantity - position.quantity) < 0.001 &&
                       abs($0.avgEntry - position.entry) < 0.0001
            })
            
            if let tIdx = existingIdx {
                var existing = dataStore.trades[tIdx]
                existing.accountId = targetAccId
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
                    accountId: targetAccId,
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
        balance: Decimal? = nil,
        authoritativeProgramName: String? = nil,
        authoritativeStepName: String? = nil,
        authoritativeAccountType: String? = nil
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
            fields["program"]
        ]
        var packageName: String? = nil
        for cand in pkgCandidates {
            if let str = cand as? String, !str.trimmingCharacters(in: .whitespaces).isEmpty {
                let cleanStr = str.trimmingCharacters(in: .whitespaces)
                let l = cleanStr.lowercased()
                if !l.contains("standard") && l != "funded" && l != "active" && !l.contains("eval") {
                    packageName = cleanStr
                    break
                }
            }
        }
        
        var accountSize: Decimal? = (startingBalance != nil && startingBalance != balance) ? startingBalance : nil
        let sizeCandidates: [Any?] = [
            fields["accountsize"],
            fields["startingbalance"],
            fields["initialbalance"],
            fields["nominalbalance"],
            fields["size"]
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
            let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
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
        
        let rawCombined = "\(fallbackLabel) \(packageName ?? "") \(fields["type"] ?? "") \(fields["step"] ?? "") \(fields["phase"] ?? "") \(fields["stage"] ?? "")".lowercased()
        
        let pkg: String = {
            if let apn = authoritativeProgramName?.trimmingCharacters(in: .whitespaces), !apn.isEmpty {
                let l = apn.lowercased()
                if l.contains("high stakes") || l.contains("highstakes") || l.contains("high-stakes") { return "High Stakes" }
                if l.contains("hyper growth") || l.contains("hypergrowth") || l.contains("hyper-growth") { return "Hyper Growth" }
                if l.contains("bootcamp") || l.contains("boot camp") { return "Bootcamp" }
                if l.contains("instant") { return "Instant Funding" }
                if !l.contains("standard") && l != "funded" && l != "active" && !l.contains("eval") {
                    return apn
                }
            }
            if rawCombined.contains("high stakes") || rawCombined.contains("highstakes") || rawCombined.contains("high-stakes") {
                return "High Stakes"
            }
            if rawCombined.contains("hyper growth") || rawCombined.contains("hypergrowth") || rawCombined.contains("hyper-growth") {
                return "Hyper Growth"
            }
            if rawCombined.contains("bootcamp") || rawCombined.contains("boot camp") {
                return "Bootcamp"
            }
            if rawCombined.contains("instant") {
                return "Instant Funding"
            }
            if let p = packageName, !p.isEmpty, !p.lowercased().contains("eval") {
                return p
            }
            return "The5ers \(platformTag)"
        }()
        
        let phase: String = {
            if let asn = authoritativeStepName?.trimmingCharacters(in: .whitespaces), !asn.isEmpty {
                let l = asn.lowercased()
                if l.contains("step 1") || l.contains("phase 1") { return "Phase 1" }
                if l.contains("step 2") || l.contains("phase 2") || l.contains("verification") { return "Phase 2" }
                if l.contains("step 3") || l.contains("phase 3") { return "Phase 3" }
                if l.contains("fund") || l.contains("live") { return "Funded" }
                return asn
            }
            if let aat = authoritativeAccountType?.lowercased() {
                if aat == "funded" { return "Funded" }
            }
            if rawCombined.contains("step 2") || rawCombined.contains("step2") || rawCombined.contains("phase 2") || rawCombined.contains("phase2") || rawCombined.contains("verification") {
                return "Phase 2"
            }
            if rawCombined.contains("step 3") || rawCombined.contains("step3") || rawCombined.contains("phase 3") || rawCombined.contains("phase3") {
                return "Phase 3"
            }
            if rawCombined.contains("funded") || rawCombined.contains("live") || rawCombined.contains("master") {
                return "Funded"
            }
            if pkg == "Instant Funding" {
                return "Funded"
            }
            return "Phase 1"
        }()
        
        var nameComponents: [String] = [pkg]
        if !phase.isEmpty {
            nameComponents.append(phase)
        }
        
        if let sz = accountSize, sz > 0 {
            let szInt = NSDecimalNumber(decimal: sz).intValue
            if szInt >= 1000 && szInt % 1000 == 0 {
                nameComponents.append("$\(szInt / 1000)K")
            } else {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = "USD"
                formatter.maximumFractionDigits = 0
                if let formatted = formatter.string(from: sz as NSDecimalNumber) {
                    nameComponents.append(formatted)
                }
            }
        }
        
        if let s = suffix, !s.isEmpty {
            nameComponents.append("#\(s)")
        }
        
        return nameComponents.joined(separator: " - ")
    }
    
    private func isLikelyPurchaseDictionary(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        let hasCost = keys.contains("netpaid") || keys.contains("price") || keys.contains("priceusd") ||
                      keys.contains("cost") || keys.contains("fee") || keys.contains("amount") || keys.contains("total")
        let hasIdentity = keys.contains("id") || keys.contains("orderid") || keys.contains("purchaseid") ||
                          keys.contains("reference") || keys.contains("ref") || keys.contains("purchaseref") ||
                          keys.contains("items") || keys.contains("placedat")
        return (hasCost || keys.contains("items")) && (hasIdentity || keys.contains("status"))
    }
    
    private func extractAnyPurchaseCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPurchaseCollection(from: parsed)
            }
            return []
        }
        if let dict = unwrapped as? [String: Any] {
            if let data = dict["data"] as? [String: Any] {
                if let p = data["purchases"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["orders"] as? [[String: Any]], !p.isEmpty { return p }
            }
            if let p = dict["purchases"] as? [[String: Any]], !p.isEmpty { return p }
            if let p = dict["orders"] as? [[String: Any]], !p.isEmpty { return p }
            if isLikelyPurchaseDictionary(dict) {
                return [dict]
            }
            let possibleKeys = ["purchases", "orders", "transactions", "history", "data", "lineitems", "rows", "records", "challenges", "invoices"]
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
        if let arr = unwrapped as? [[String: Any]] {
            return arr.filter { isLikelyPurchaseDictionary($0) }
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
                let pId = String(describing: p["ref"] ?? p["id"] ?? p["orderid"] ?? p["order_id"] ?? p["purchaseid"] ?? UUID().uuidString)
                if !seenPurchaseIds.contains(pId) {
                    seenPurchaseIds.insert(pId)
                    allPurchases.append(p)
                }
            }
        }
        
        // 2. Fetch orders from official the5ers_purchase 'list'
        let pArgsList: [[String: Any]] = [
            ["operation": "list", "contract_version": "1.0", "limit": 50],
            ["operation": "list"]
        ]
        for pArgs in pArgsList {
            if Task.isCancelled || isCancelledByUser { break }
            if let res = try? await callMcpTool(name: "the5ers_purchase", arguments: pArgs),
               !(res["isError"] as? Bool ?? false) {
                let unwrapped = unwrapMcpToolResult(res)
                let rows = extractAnyPurchaseCollection(from: unwrapped)
                if !rows.isEmpty {
                    for r in rows {
                        let pId = String(describing: r["ref"] ?? r["id"] ?? r["orderid"] ?? r["order_id"] ?? r["purchaseid"] ?? UUID().uuidString)
                        if !seenPurchaseIds.contains(pId) {
                            seenPurchaseIds.insert(pId)
                            allPurchases.append(r)
                        }
                    }
                    break
                }
            }
        }
        
        // 3. Resiliently associate orders with accounts if account_ref is missing
        var unmappedLookupCount = 0
        for i in allPurchases.indices {
            if unmappedLookupCount >= 8 { break }
            let pRef = String(describing: allPurchases[i]["ref"] ?? allPurchases[i]["purchase_ref"] ?? allPurchases[i]["id"] ?? "")
            let existingAccRef = String(describing: allPurchases[i]["account_ref"] ?? "")
            if !pRef.isEmpty && existingAccRef.isEmpty {
                unmappedLookupCount += 1
                if let accRes = try? await self.callMcpTool(name: "the5ers_purchase", arguments: [
                    "operation": "accounts",
                    "purchase_ref": pRef,
                    "contract_version": "1.0"
                ]), !(accRes["isError"] as? Bool ?? false) {
                    let unwrappedAcc = self.unwrapMcpToolResult(accRes)
                    let accRows = self.extractMcpCollection(unwrappedAcc, collectionKey: "accounts")
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
            
            var currency = String(describing: fields["currency"] ?? "USD").uppercased()
            
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
            // Prioritize authoritative USD-denominated fields per MCP contract (Root Cause #4)
            for k in ["priceusd", "price_usd", "netpaid", "net_paid", "total", "amount", "price", "cost", "value"] {
                if let val = fields[k] {
                    if let n = val as? NSNumber, n.doubleValue > 0 {
                        priceNum = n.doubleValue
                        if k == "priceusd" || k == "price_usd" || k == "netpaid" || k == "net_paid" {
                            currency = "USD"
                        }
                        break
                    }
                    if let s = val as? String {
                        let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if let d = Double(clean), d > 0 {
                            priceNum = d
                            if k == "priceusd" || k == "price_usd" || k == "netpaid" || k == "net_paid" {
                                currency = "USD"
                            }
                            break
                        }
                    }
                }
            }
            if priceNum == 0 && itemsTotal > 0 {
                priceNum = itemsTotal
                currency = "USD"
            }
            guard priceNum > 0 else { continue }
            let amountMinor = Int64(round(priceNum * 100))
            
            let orderRef = String(describing: fields["ref"] ?? fields["id"] ?? fields["orderid"] ?? fields["order_id"] ?? fields["purchaseid"] ?? fields["purchase_id"] ?? "")
            let title = itemNames.isEmpty ? (fields["name"] as? String ?? "The5ers Program Evaluation") : itemNames.joined(separator: ", ")
            let purchaseHash = JournalIds.sha256Hex([rawDate, currency, title])
            let entryId = !orderRef.isEmpty ? "the5ers_purchase_\(orderRef)" : "the5ers_purchase_\(purchaseHash)"
            let shortRef = !orderRef.isEmpty && !orderRef.contains("opaque") ? "Order #\(orderRef.prefix(8))" : "Order #\(purchaseHash.prefix(8))"
            
            // Normalize category matching EXPENSE_CATEGORIES: "evaluation", "reset", "activation", etc.
            let normalizedCategory: String = {
                let validCategories: Set<String> = [
                    "evaluation", "reset", "activation", "subscription",
                    "platform", "market_data", "transfer", "other"
                ]
                let cleanType = productType.lowercased().trimmingCharacters(in: .whitespaces)
                if validCategories.contains(cleanType) {
                    return cleanType
                }
                if cleanType.contains("challenge") || cleanType.contains("eval") || cleanType.contains("bootcamp") || cleanType.contains("hyper") || cleanType.contains("high stakes") {
                    return "evaluation"
                }
                if cleanType.contains("reset") { return "reset" }
                if cleanType.contains("activat") { return "activation" }
                return "other"
            }()
            
            // Match account attribution:
            // 1. By exact account_ref / ID
            let candidateAccRef = String(describing: fields["accountref"] ?? fields["account_ref"] ?? fields["accountid"] ?? fields["account_id"] ?? "")
            var matchedAcc = targetAccounts.first(where: {
                (!candidateAccRef.isEmpty && ($0.ref == candidateAccRef || $0.id == candidateAccRef)) ||
                (!candidateAccRef.isEmpty && $0.label.contains(candidateAccRef))
            })
            // 2. If single target account, attribute to it directly
            if matchedAcc == nil && targetAccounts.count == 1 {
                matchedAcc = targetAccounts.first
            }
            // 3. Match by account size (e.g. "100k" in title)
            if matchedAcc == nil {
                for acc in targetAccounts {
                    let sz = NSDecimalNumber(decimal: acc.balance).intValue
                    if sz > 0 {
                        let kStr = "\(sz / 1000)k"
                        if title.lowercased().contains(kStr) {
                            matchedAcc = acc
                            break
                        }
                    }
                }
            }
            // 4. Fallback attribute to primary active The5ers account
            let journalAccId: String? = {
                if let m = matchedAcc {
                    return m.id.hasPrefix("the5ers_") ? m.id : "the5ers_\(m.id)"
                }
                if let first = targetAccounts.first {
                    return first.id.hasPrefix("the5ers_") ? first.id : "the5ers_\(first.id)"
                }
                return nil
            }()
            
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == entryId ||
                (!orderRef.isEmpty && !orderRef.contains("opaque") && ($0.id.contains(orderRef) || $0.reference.contains(orderRef))) ||
                ($0.firm == "The5ers" && $0.kind == "expense" && $0.occurredOn == dateStr && $0.amountMinor == amountMinor && $0.currency == currency)
            }) {
                var existing = dataStore.propEntries[existingIdx]
                existing.amountMinor = amountMinor
                existing.currency = currency
                existing.occurredOn = dateStr
                existing.category = normalizedCategory
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
                    category: normalizedCategory,
                    currency: currency,
                    amountMinor: amountMinor,
                    occurredOn: dateStr,
                    status: .completed,
                    reference: shortRef,
                    notes: "\(title) (The5ers official order placed \(rawDate))"
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
                        keys.contains("finalamount") || keys.contains("usershare")
        let hasIdentity = keys.contains("payoutid") || keys.contains("withdrawalid") || keys.contains("requestid") ||
                          keys.contains("id") || keys.contains("ref")
        let hasDate = keys.contains("requestedat") || keys.contains("completedat") || keys.contains("paymentdate") ||
                      keys.contains("settledat") || keys.contains("paidat") || keys.contains("date") || keys.contains("createdat")
        let hasStatus = keys.contains("status") || keys.contains("method")
        return hasAmount && (hasIdentity || hasDate || hasStatus)
    }
    
    private func extractAnyPayoutCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPayoutCollection(from: parsed)
            }
            return []
        }
        if let dict = unwrapped as? [String: Any] {
            if let data = dict["data"] as? [String: Any] {
                if let p = data["payouts"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["payout_history"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["history"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["requests"] as? [[String: Any]], !p.isEmpty { return p }
            }
            if let p = dict["payouts"] as? [[String: Any]], !p.isEmpty { return p }
            if let p = dict["payout_history"] as? [[String: Any]], !p.isEmpty { return p }
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
        if let arr = unwrapped as? [[String: Any]] {
            return arr.filter { isLikelyPayoutDictionary($0) }
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
        var accountSplitMap: [String: Double] = [:]
        
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
        
        // 2. Query official payouts across target accounts (eligibility / explain / history)
        let fundedAccounts = targetAccounts.filter { acc in
            let prog = acc.program.lowercased()
            let label = acc.label.lowercased()
            let stat = acc.status.lowercased()
            return prog.contains("fund") || prog.contains("live") || prog.contains("master") ||
                   label.contains("fund") || label.contains("live") || stat.contains("fund")
        }
        let candidateAccounts = fundedAccounts.isEmpty ? targetAccounts : fundedAccounts
        
        guard !candidateAccounts.isEmpty || !allRawPayouts.isEmpty else {
            return
        }
        
        for acc in candidateAccounts {
            if Task.isCancelled || isCancelledByUser { break }
            
            // Concurrently query eligibility, explain, and history in parallel
            async let eligTask: [String: Any]? = {
                let eligArgs: [String: Any] = [
                    "operation": "eligibility",
                    "account_ref": acc.ref,
                    "contract_version": "1.0"
                ]
                return try? await self.callMcpTool(name: "the5ers_payout", arguments: eligArgs)
            }()
            
            async let explainTask: [String: Any]? = {
                let explainArgs: [String: Any] = [
                    "operation": "explain",
                    "account_ref": acc.ref,
                    "contract_version": "1.0"
                ]
                return try? await self.callMcpTool(name: "the5ers_payout", arguments: explainArgs)
            }()
            
            async let histTask: [String: Any]? = {
                let histArgs: [String: Any] = [
                    "operation": "history",
                    "account_ref": acc.ref,
                    "contract_version": "1.0",
                    "limit": 50
                ]
                return try? await self.callMcpTool(name: "the5ers_payout", arguments: histArgs)
            }()
            
            let (eligRes, explainRes, histRes) = await (eligTask, explainTask, histTask)
            
            // A. Parse eligibility
            if let eligRes = eligRes, !(eligRes["isError"] as? Bool ?? false) {
                let unwrapped = unwrapMcpToolResult(eligRes)
                if let eDict = (unwrapped as? [String: Any])?["data"] as? [String: Any] ?? unwrapped as? [String: Any] {
                    if let split = eDict["userPayoutPercentage"] as? NSNumber {
                        accountSplitMap[acc.ref] = split.doubleValue
                    }
                }
            }
            
            // B. Parse explain
            var latestPayoutDict: [String: Any]? = nil
            if let explainRes = explainRes, !(explainRes["isError"] as? Bool ?? false) {
                let unwrappedExplain = unwrapMcpToolResult(explainRes)
                if let expDict = (unwrappedExplain as? [String: Any])?["data"] as? [String: Any] ?? unwrappedExplain as? [String: Any] {
                    if let avail = expDict["available"] as? [String: Any] {
                        if let split = avail["traderSplitPercent"] as? NSNumber ?? avail["userPayoutPercentage"] as? NSNumber {
                            accountSplitMap[acc.ref] = split.doubleValue
                        }
                    }
                    if let latest = expDict["latestPayout"] as? [String: Any] {
                        var p = latest
                        if p["account_ref"] == nil { p["account_ref"] = acc.ref }
                        if p["currency"] == nil { p["currency"] = acc.currency }
                        if let b = latest["breakdown"] as? [String: Any] {
                            for (k, v) in b { p[k] = v }
                        }
                        latestPayoutDict = p
                    }
                }
            }
            
            // C. Parse history payouts
            var historyPayouts: [[String: Any]] = []
            if let histRes = histRes, !(histRes["isError"] as? Bool ?? false) {
                let unwrappedHist = unwrapMcpToolResult(histRes)
                let rows = extractAnyPayoutCollection(from: unwrappedHist)
                for var r in rows {
                    if r["account_ref"] == nil { r["account_ref"] = acc.ref }
                    if r["currency"] == nil { r["currency"] = acc.currency }
                    if let s = accountSplitMap[acc.ref], r["split_percent"] == nil {
                        r["split_percent"] = s
                    }
                    // If this history payout matches latestPayout, enrich with detailed breakdown
                    if let latest = latestPayoutDict {
                        let histReq = String(describing: r["requestedAt"] ?? r["requested_at"] ?? "")
                        let latestReq = String(describing: latest["requestedAt"] ?? latest["requested_at"] ?? "")
                        let histAmt = String(describing: r["amount"] ?? "")
                        let latestAmt = String(describing: latest["amount"] ?? "")
                        if (!histReq.isEmpty && histReq == latestReq) || (!histAmt.isEmpty && histAmt == latestAmt) {
                            for (k, v) in latest {
                                if r[k] == nil { r[k] = v }
                            }
                        }
                    }
                    historyPayouts.append(r)
                }
            }
            
            if !historyPayouts.isEmpty {
                for p in historyPayouts {
                    let reqDate = String(describing: p["requestedAt"] ?? p["requested_at"] ?? "")
                    let amt = String(describing: p["amount"] ?? "")
                    let pId = String(describing: p["id"] ?? p["payout_id"] ?? p["withdrawalid"] ?? "\(acc.ref)_\(reqDate)_\(amt)")
                    if !seenPayoutIds.contains(pId) {
                        seenPayoutIds.insert(pId)
                        allRawPayouts.append(p)
                    }
                }
            } else if let latest = latestPayoutDict {
                let reqDate = String(describing: latest["requestedAt"] ?? latest["requested_at"] ?? "")
                let amt = String(describing: latest["amount"] ?? "")
                let pId = String(describing: latest["id"] ?? latest["payout_id"] ?? latest["withdrawalid"] ?? "\(acc.ref)_\(reqDate)_\(amt)")
                if !seenPayoutIds.contains(pId) {
                    seenPayoutIds.insert(pId)
                    allRawPayouts.append(latest)
                }
            }
        }
        
        for pay in allRawPayouts {
            let fields = sourceFields(pay)
            let rawId = String(describing: fields["id"] ?? fields["payoutid"] ?? fields["withdrawalid"] ?? fields["requestid"] ?? fields["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            let status = String(describing: fields["status"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            let isReversed = (fields["reversed"] as? Bool) == true
            guard !isReversed else { continue }
            
            let isCompleted = ["completed", "paid", "received", "settled", "approved", "processed", "success", "successful"].contains(status)
            let isRejected = ["rejected", "cancelled", "declined", "failed"].contains(status)
            let payoutStatus: PayoutStatus = isCompleted ? .completed : (isRejected ? .rejected : .requested)
            
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
                for k in ["availableprofit", "available_profit", "grossamount", "gross_amount", "grossprofit", "gross_profit", "tradingprofit", "trading_profit", "profit"] {
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
                for k in ["finalamount", "final_amount", "requestedamount", "requested_amount", "receivedamount", "received_amount", "netamount", "net_amount", "paidamount", "paid_amount", "netpaid", "traderprofit", "trader_profit", "tradershare", "trader_share", "payoutamount", "payout_amount", "withdrawalamount", "withdrawal_amount", "usershare", "user_share", "net"] {
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
                if let f = fields["fee"] ?? fields["fees"] ?? fields["transferfee"] ?? fields["transfer_fee"] ?? fields["commission"] {
                    if let n = f as? NSNumber { return n.doubleValue }
                    if let s = f as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
                }
                return 0
            }()
            let feeMinor = Int64(round(feeVal * 100))
            
            let effectiveSplit = splitPercentVal ?? 80.0
            let ratio = effectiveSplit > 1.0 ? (effectiveSplit / 100.0) : effectiveSplit
            let splitBps = Int(round(ratio * 10000.0))
            
            let netReceivedMinor: Int64
            let grossMinor: Int64
            
            if let en = explicitNet {
                netReceivedMinor = Int64(round(en * 100))
                if let eg = explicitGross, eg >= en {
                    grossMinor = Int64(round(eg * 100))
                } else {
                    grossMinor = Int64(round(Double(netReceivedMinor) / ratio))
                }
            } else if let eg = explicitGross {
                grossMinor = Int64(round(eg * 100))
                netReceivedMinor = max(0, Int64((Double(grossMinor) * Double(splitBps) + 5000) / 10000) - feeMinor)
            } else if let ga = genericAmount {
                // In The5ers history, 'amount' is the gross profit payout requested!
                grossMinor = Int64(round(ga * 100))
                netReceivedMinor = max(0, Int64((Double(grossMinor) * Double(splitBps) + 5000) / 10000) - feeMinor)
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
            
            let payAccRef = String(describing: fields["accountref"] ?? fields["accountid"] ?? fields["ref"] ?? "")
            let matchedAcc = candidateAccounts.first(where: {
                $0.id == payAccRef || $0.ref == payAccRef || "the5ers_\($0.id)" == payAccRef || $0.id.cleanAccountId == payAccRef.cleanAccountId || $0.ref.cleanAccountId == payAccRef.cleanAccountId
            })
            let primaryAccId: String? = {
                if let m = matchedAcc {
                    return m.id.hasPrefix("the5ers_") ? m.id : "the5ers_\(m.id)"
                }
                if !payAccRef.isEmpty && !payAccRef.contains("opaque") {
                    return payAccRef.hasPrefix("the5ers_") ? payAccRef : "the5ers_\(payAccRef)"
                }
                return candidateAccounts.first?.id
            }()
            let currency = String(describing: fields["currency"] ?? matchedAcc?.currency ?? "USD").uppercased()
            
            let cleanAcc = (primaryAccId ?? "the5ers").cleanAccountId
            
            // Stable deterministic key matching payouts.ts:21-36 payoutKey:
            // sha256([accountId, requestedAt ?? date, currency, grossMinor])
            let stablePayoutHash = JournalIds.sha256Hex([cleanAcc, dateStr, currency, grossMinor])
            let payoutEntryId = "the5ers_payout_\(stablePayoutHash)"
            let rcptId = "the5ers_rcpt_\(stablePayoutHash)"
            let canonicalId = PropFirmEngine.canonicalPayoutId(stablePayoutHash)
            let shortRef = !rawId.isEmpty && !rawId.contains("opaque") ? "Payout #\(rawId.prefix(8))" : "Payout #\(stablePayoutHash.prefix(8))"
            
            // Mark the corresponding prop account as funded program
            if let pAccIdx = dataStore.propAccounts.firstIndex(where: { $0.id == primaryAccId || TradeDataStore.isSameAccountId($0.id, primaryAccId ?? "") }) {
                if dataStore.propAccounts[pAccIdx].program == .evaluation {
                    dataStore.propAccounts[pAccIdx].program = .funded
                }
            }
            
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == payoutEntryId ||
                PropFirmEngine.canonicalPayoutId($0.id) == canonicalId ||
                (!rawId.isEmpty && !rawId.contains("opaque") && ($0.id.contains(rawId) || $0.reference.contains(rawId))) ||
                ($0.firm == "The5ers" && $0.kind == "payout" && $0.occurredOn == dateStr && ($0.amountMinor == grossMinor || $0.amountMinor == netReceivedMinor))
            }) {
                let existing = dataStore.propEntries[existingIdx]
                let updatedEntry = PropEntryItem(
                    id: payoutEntryId,
                    accountId: primaryAccId ?? existing.accountId,
                    firm: existing.firm,
                    kind: existing.kind,
                    category: existing.category,
                    currency: currency,
                    amountMinor: grossMinor,
                    splitBps: splitBps,
                    feeMinor: feeMinor,
                    occurredOn: dateStr,
                    dueOn: existing.dueOn,
                    status: payoutStatus,
                    parentId: existing.parentId,
                    reference: existing.reference.isEmpty ? shortRef : existing.reference,
                    notes: existing.notes.isEmpty ? "The5ers Official Withdrawal" : existing.notes,
                    voided: existing.voided,
                    revision: existing.revision + 1,
                    createdAt: existing.createdAt,
                    updatedAt: JournalIds.nowIso()
                )
                dataStore.propEntries[existingIdx] = updatedEntry
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
                    status: payoutStatus,
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
                    PropFirmEngine.canonicalPayoutId($0.id) == canonicalId ||
                    (!rawId.isEmpty && !rawId.contains("opaque") && ($0.id.contains(rawId) || $0.reference.contains(rawId))) ||
                    ($0.occurredOn == dateStr && $0.amountMinor == netReceivedMinor)
                }) {
                    let existingRcpt = dataStore.propReceipts[rIdx]
                    let updatedRcpt = PropReceiptItem(
                        id: rcptId,
                        payoutId: payoutEntryId,
                        kind: existingRcpt.kind,
                        amountMinor: netReceivedMinor,
                        occurredOn: dateStr,
                        reference: existingRcpt.reference.isEmpty ? "Receipt #\(stablePayoutHash.prefix(8))" : existingRcpt.reference,
                        notes: existingRcpt.notes.isEmpty ? "The5ers Settlement Receipt" : existingRcpt.notes,
                        voided: existingRcpt.voided,
                        createdAt: existingRcpt.createdAt
                    )
                    dataStore.propReceipts[rIdx] = updatedRcpt
                } else {
                    let rcpt = PropReceiptItem(
                        id: rcptId,
                        payoutId: payoutEntryId,
                        kind: "receipt",
                        amountMinor: netReceivedMinor,
                        occurredOn: dateStr,
                        reference: "Receipt #\(stablePayoutHash.prefix(8))",
                        notes: "The5ers Settlement Receipt"
                    )
                    dataStore.propReceipts.append(rcpt)
                }
            }
        }
        
        dataStore.deduplicatePropEntries()
        dataStore.deduplicatePropReceipts()
    }
}
