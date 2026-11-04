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
    @Published public internal(set) var isCancelledByUser: Bool = false
    @Published public var lastSyncTime: Date? = nil
    @Published public var lastStatus: String = ""
    @Published public var isConnected: Bool = false
    
    internal let session = URLSession.shared
    internal var rpcIdCounter: Int = 0
    internal var mcpSessionId: String? = nil
    internal var isSessionInitialized: Bool = false
    internal var cachedToolSchemas: [String: [String: Any]] = [:]
    internal var discoveredToolNames: Set<String> = []
    
    public var isConfigured: Bool {
        if !mcpToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let stored = KeychainManager.get(forKey: "the5ers_mcp_token") ?? UserDefaults.standard.string(forKey: "the5ers_mcp_token"),
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
        let kcToken = KeychainManager.get(forKey: "the5ers_mcp_token") ?? ""
        let udToken = UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? ""
        let resolved = kcToken.isEmpty ? udToken : kcToken
        if !udToken.isEmpty && kcToken.isEmpty {
            KeychainManager.set(udToken, forKey: "the5ers_mcp_token")
            UserDefaults.standard.removeObject(forKey: "the5ers_mcp_token")
        }
        self.mcpToken = resolved
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
        KeychainManager.set(self.mcpToken, forKey: "the5ers_mcp_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_token")
    }
    
    public func disconnect() {
        self.mcpToken = ""
        self.isConnected = false
        self.mcpSessionId = nil
        self.isSessionInitialized = false
        self.cachedToolSchemas.removeAll()
        self.discoveredToolNames.removeAll()
        KeychainManager.delete(forKey: "the5ers_mcp_token")
        KeychainManager.delete(forKey: "the5ers_mcp_refresh_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_refresh_token")
        UserDefaults.standard.removeObject(forKey: "the5ers_mcp_client_id")
    }
    
    // MARK: - 1. OAuth 2.0 PKCE Flow (Official The5ers Hub OAuth)
    
    /// Dynamic client registration RFC 7591 with The5ers Descope Hub server
    internal func getOrRegisterClientId(redirectUri: String) async throws -> String {
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
    
    internal func exchangeCodeForToken(code: String, verifier: String, clientId: String, redirectUri: String) async throws -> String {
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
        request.timeoutInterval = 45
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
    internal func sendRawMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
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
        request.timeoutInterval = 45
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
            if http.statusCode == 401 {
                self.isSessionInitialized = false
                self.mcpSessionId = nil
            } else if http.statusCode == 404 {
                let bodyText = (String(data: data, encoding: .utf8) ?? "").lowercased()
                if bodyText.contains("session") || bodyText.contains("mcp-session-id") {
                    self.isSessionInitialized = false
                    self.mcpSessionId = nil
                }
            }
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
            let lowerErr = errorMsg.lowercased()
            if lowerErr.contains("mcp-session-id") || lowerErr.contains("session not found") || lowerErr.contains("session expired") || lowerErr.contains("not initialized") || lowerErr.contains("unauthenticated") {
                self.isSessionInitialized = false
                self.mcpSessionId = nil
            }
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
    internal func filterArgsForTool(_ args: [String: Any], toolName: String) -> [String: Any] {
        guard let schema = cachedToolSchemas[toolName],
              let props = schema["properties"] as? [String: Any],
              !props.isEmpty else {
            return args
        }
        return args.filter { props.keys.contains($0.key) }
    }
    
    /// Builds resilient per-account arguments matching the exact parameter name expected by the tool
    internal func buildAccountArgs(toolName: String, accountRef: String, op: String? = nil) -> [String: Any] {
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
    internal func extractJsonFromText(_ text: String) -> Any? {
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
    internal func unwrapMcpToolResult(_ result: [String: Any]) -> Any? {
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
    internal func extractMcpCollection(_ unwrapped: Any?, collectionKey: String) -> [[String: Any]] {
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
}