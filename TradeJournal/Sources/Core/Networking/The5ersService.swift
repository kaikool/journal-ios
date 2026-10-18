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
    
    /// Internal domain documentation
    public func ensureInitialized() async throws {
        guard !isSessionInitialized else { return }
        guard isConfigured else { return }
        
        // Internal implementation note
        _ = try await sendRawMcpRpc(method: "initialize", params: [
            "protocolVersion": Self.protocolVersion,
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "trade-journal",
                "version": "1.0"
            ]
        ])
        
        // Internal implementation note
        try await sendMcpNotification(method: "notifications/initialized")
        self.isSessionInitialized = true
    }
    
    /// Internal domain documentation
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
    
    /// Internal domain documentation
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
        // Internal implementation note
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
        
        // Internal implementation note
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
    
    /// Internal domain documentation
    public func sendMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
        if method != "initialize" {
            try await ensureInitialized()
        }
        return try await sendRawMcpRpc(method: method, params: params)
    }
    
    /// Internal domain documentation
    public func callMcpTool(name: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        return try await sendMcpRpc(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
    }
    
    /// Internal domain documentation
    public func pingMcpConnection() async throws -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "The5ers MCP is not connected. Click 'Log in to The5ers Hub (OAuth)'.")
        }
        
        do {
            let res = try await sendMcpRpc(method: "tools/list", params: [:])
            self.isConnected = true
            let tools = res["tools"] as? [[String: Any]] ?? []
            return (true, "Connected to The5ers MCP Server! Protocol 2025-03-26 active (\(tools.count) tools ready).")
        } catch {
            return (false, "The5ers MCP connection error: \(error.localizedDescription)")
        }
    }
    
    // Internal implementation note
    
    /// Internal domain documentation
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
    
    /// Internal domain documentation
    private func extractMcpCollection(_ unwrapped: Any?, collectionKey: String) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        
        if let dict = unwrapped as? [String: Any] {
            // Internal implementation note
            if let dataDict = dict["data"] as? [String: Any] {
                if let items = (dataDict[collectionKey] ?? dataDict["items"] ?? dataDict["rows"] ?? dataDict["trades"]) as? [[String: Any]] {
                    return items
                }
            }
            // Internal implementation note
            if let dataArray = dict["data"] as? [[String: Any]] {
                return dataArray
            }
            // Internal implementation note
            if let resDict = dict["result"] as? [String: Any] {
                return extractMcpCollection(resDict, collectionKey: collectionKey)
            }
            // Internal implementation note
            if let items = (dict[collectionKey] ?? dict["items"] ?? dict["rows"] ?? dict["trades"]) as? [[String: Any]] {
                return items
            }
        } else if let arr = unwrapped as? [[String: Any]] {
            return arr
        }
        return []
    }
    
    // Internal implementation note
    
    @MainActor
    public func syncWithTradeStore(dataStore: TradeDataStore) async throws -> Int {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bearer Session Token not configured"])
        }
        
        isSyncing = true
        lastStatus = "Connecting to The5ers MCP Hub (Protocol 2025-03-26)..."
        defer { isSyncing = false }
        
        do {
            // Internal implementation note
            try await ensureInitialized()
            
            // Internal implementation note
            var rawAccountsList: [[String: Any]] = []
            var seenAccountRefs = Set<String>()
            
            for page in 1...20 {
                lastStatus = "Loading The5ers accounts (Page \(page))..."
                let accountToolArgs: [String: Any] = [
                    "operation": "list",
                    "page": page,
                    "limit": 50,
                    "contract_version": "1.0",
                    "request_context": ["timezone": "UTC", "locale": "en"]
                ]
                
                let accountResult: [String: Any]
                if page == 1 {
                    accountResult = try await callMcpTool(name: "the5ers_account", arguments: accountToolArgs)
                } else {
                    guard let res = try? await callMcpTool(name: "the5ers_account", arguments: accountToolArgs) else { break }
                    accountResult = res
                }
                
                if let isErr = accountResult["isError"] as? Bool, isErr {
                    let errMsg = (accountResult["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ") ?? "The5ers MCP returned an error"
                    if page == 1 {
                        throw NSError(domain: "The5ersMCP", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg])
                    } else {
                        break
                    }
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
                
                // Internal implementation note
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
            
            // Internal implementation note
            if accountsList.isEmpty {
                lastStatus = "The5ers MCP responded successfully but no trading accounts were found."
                return 0
            }
            
            // Internal implementation note
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
                
                if let accIdx = dataStore.accounts.firstIndex(where: { $0.id == journalAccId || $0.id == acc.id }) {
                    let old = dataStore.accounts[accIdx]
                    dataStore.accounts[accIdx] = Account(
                        id: journalAccId,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? acc.balance,
                        profitCalcMethod: old.profitCalcMethod,
                        autoSync: true,
                        lastSyncAt: Date(),
                        archivedAt: old.archivedAt,
                        visibleInJournal: old.visibleInJournal,
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
                        autoSync: true,
                        visibleInJournal: true
                    )
                    dataStore.accounts.append(newAcc)
                }
            }
            
            // Target all available accounts from The5ers
            var targetAccounts: [The5ersMcpAccount] = []
            var seenTargetIds = Set<String>()
            
            for acc in accountsList {
                if !seenTargetIds.contains(acc.id) {
                    seenTargetIds.insert(acc.id)
                    targetAccounts.append(acc)
                }
            }
            
            var importedPositionsCount = 0
            for (idx, acc) in targetAccounts.enumerated() {
                lastStatus = "Syncing trades (\(idx + 1)/\(targetAccounts.count)): \(acc.label)..."
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
                        AppLogger.error("The5ers MCP reported error for account \(acc.label) (\(acc.id)): \(posResult)")
                        continue
                    }
                    let unwrappedPos = unwrapMcpToolResult(posResult)
                    let rawPositions = extractMcpCollection(unwrappedPos, collectionKey: "positions")
                    mergePositions(rawPositions, for: acc, into: dataStore, count: &importedPositionsCount)
                    
                    // Internal implementation note
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
                    AppLogger.error("Error syncing trades for account \(acc.label) (\(acc.id)): \(error.localizedDescription)")
                }
            }
            
            // 4. Sync purchases / challenges & evaluation fees
            lastStatus = "Loading purchases and evaluation fees from the5ers_purchase..."
            let purchaseArgs: [String: Any] = [
                "operation": "list",
                "contract_version": "1.0",
                "request_context": ["timezone": "UTC", "locale": "en"]
            ]
            if let purchaseResult = try? await callMcpTool(name: "the5ers_purchase", arguments: purchaseArgs) {
                let unwrappedPurchases = unwrapMcpToolResult(purchaseResult)
                let rawPurchases = extractMcpCollection(unwrappedPurchases, collectionKey: "purchases")
                mergePurchases(rawPurchases, into: dataStore, targetAccounts: accountsList)
            }
            
            // 5. Sync payouts & withdrawal settlements
            lastStatus = "Loading withdrawal history from the5ers_payout..."
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
                    guard amtMinor > 0 else { continue }
                    
                    let rawDate = String(describing: pay["paidAt"] ?? pay["date"] ?? pay["createdAt"] ?? "")
                    let dateStr = rawDate.prefix(10).isEmpty ? String(JournalIds.nowIso().prefix(10)) : String(rawDate.prefix(10))
                    let payoutEntryId = "the5ers_payout_\(id)"
                    let rcptId = "the5ers_rcpt_\(id)"
                    let shortRef = "Payout #\(id.prefix(8))"
                    
                    let payAccRef = String(describing: pay["account_ref"] ?? pay["account_id"] ?? pay["accountId"] ?? pay["ref"] ?? "")
                    let matchedAcc = targetAccounts.first(where: { $0.id == payAccRef || $0.ref == payAccRef || "the5ers_\($0.id)" == payAccRef })
                    let primaryAccId: String = {
                        if let m = matchedAcc {
                            return m.id.hasPrefix("the5ers_") ? m.id : "the5ers_\(m.id)"
                        }
                        if let f = targetAccounts.first {
                            return f.id.hasPrefix("the5ers_") ? f.id : "the5ers_\(f.id)"
                        }
                        return "the5ers_payout_account"
                    }()
                    let primaryCurrency = matchedAcc?.currency ?? targetAccounts.first?.currency ?? "USD"
                    
                    if !dataStore.propEntries.contains(where: { $0.id == payoutEntryId }) {
                        let payoutEntry = PropEntryItem(
                            id: payoutEntryId,
                            accountId: primaryAccId,
                            firm: "The5ers",
                            kind: "payout",
                            category: "payout",
                            currency: primaryCurrency,
                            amountMinor: amtMinor,
                            splitBps: 8000,
                            occurredOn: dateStr,
                            status: .completed,
                            reference: shortRef,
                            notes: "The5ers Funded Payout"
                        )
                        dataStore.propEntries.append(payoutEntry)
                    }
                    
                    if !dataStore.propReceipts.contains(where: { $0.id == rcptId }) {
                        let rcpt = PropReceiptItem(
                            id: rcptId,
                            payoutId: payoutEntryId,
                            kind: "receipt",
                            amountMinor: amtMinor,
                            occurredOn: dateStr,
                            reference: "Receipt #\(id.prefix(8))",
                            notes: "The5ers Official Withdrawal Receipt"
                        )
                        dataStore.propReceipts.append(rcpt)
                    }
                }
            }
            
            lastSyncTime = Date()
            dataStore.rebuildAllAccounts()
            
            // Internal implementation note
            if dataStore.filteredTrades.isEmpty, let firstWithTrade = dataStore.accounts.first(where: { acc in dataStore.trades.contains(where: { $0.accountId == acc.id }) }) {
                dataStore.selectedAccountId = firstWithTrade.id
            }
            
            dataStore.saveToDisk()
            let activeCount = accountsList.filter { $0.status.lowercased() == "active" || $0.status.lowercased() == "available" }.count
            lastStatus = "Successfully synced \(accountsList.count) accounts (\(activeCount) active) and \(importedPositionsCount) positions from The5ers MCP."
            
            return accountsList.count
        } catch {
            lastStatus = "The5ers MCP sync error: \(error.localizedDescription)"
            throw error
        }
    }
    
    // Internal implementation note
    
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
    
    /// Internal domain documentation
/// Ported 1:1 from `the5ers-normalize.ts` `sourceFields`
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
    
    /// Internal domain documentation
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
        let isClosed = sourceBoolean(closedFlag) ?? (row["closedate"] != nil || row["exit"] != nil || row["closetime"] != nil || row["closeprice"] != nil)
        
        let closeKeys = ["closedate", "closedat", "closetime", "close_date", "closedatetime", "exittime", "exitdate"]
        let closeVal = firstValue(in: row, keys: closeKeys)
        let closedAtTuple = isClosed ? sourceInstant(closeVal) : nil
        
        let exitKeys = ["exit", "closeprice", "exitprice", "close_price", "price"]
        let exitVal = firstValue(in: row, keys: exitKeys)
        let exit = isClosed ? sourceNumber(exitVal) : nil
        
        let pnlKeys = ["profitandloss", "profit", "netpnl", "pnl", "net_pnl", "gross"]
        let pnlVal = firstValue(in: row, keys: pnlKeys)
        let netPnl = isClosed ? (sourceNumber(pnlVal) ?? 0) : 0
        
        if isClosed && (closedAtTuple == nil || exit == nil) {
            return nil
        }
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
    
    /// Internal domain documentation
/// Ported 1:1 from `source-repo/apps/web/src/server/the5ers/journal.ts` (`saveJournalPositions` & `journalTradeRow`)
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
        
        // Internal implementation note
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
            // Internal implementation note
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
        
        // Internal implementation note
        for position in valid {
            let posIdentity = JournalIds.positionIdentity(
                symbol: position.symbol,
                direction: position.direction.rawValue,
                openedAt: position.openedAtIso,
                discriminator: position.identityDiscriminator
            )
            // Internal implementation note
            let tradeKey = JournalIds.the5ersTradeKey(sourceAccountId: acc.id, positionIdentity: posIdentity)
            
            let isClosed = position.closedAtDate != nil
            let status: TradeStatus = isClosed
                ? (position.netPnl > 0 ? .win : (position.netPnl < 0 ? .loss : .breakeven))
                : .open
            
            // Internal implementation note
            // Provider net already includes signed swap and commission. Reverse costs for gross only.
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
                // Internal implementation note
                existing.status = status
                existing.closedAt = position.closedAtDate
                existing.openQuantity = isClosed ? 0 : position.quantity
                existing.avgExit = position.exit
                existing.grossPnl = grossPnl
                existing.fees = fees
                existing.netPnl = netPnl
                existing.durationMs = durationMs
                // Internal implementation note
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
            
            // Maintain corresponding Execution records for executions table and trade reconstruction
            let entryExecId = "the5ers_exec_\(tradeKey)_entry"
            if !dataStore.executions.contains(where: { $0.id == entryExecId }) {
                dataStore.executions.append(Execution(
                    id: entryExecId,
                    accountId: journalAccId,
                    symbol: position.symbol,
                    side: position.direction == .long ? .buy : .sell,
                    quantity: position.quantity,
                    price: position.entry,
                    fee: 0,
                    executedAt: position.openedAtDate,
                    assetClass: "forex",
                    source: "the5ers"
                ))
            }
            
            if isClosed, let exitDate = position.closedAtDate, let exitPrice = position.exit {
                let exitExecId = "the5ers_exec_\(tradeKey)_exit"
                if !dataStore.executions.contains(where: { $0.id == exitExecId }) {
                    dataStore.executions.append(Execution(
                        id: exitExecId,
                        accountId: journalAccId,
                        symbol: position.symbol,
                        side: position.direction == .long ? .sell : .buy,
                        quantity: position.quantity,
                        price: exitPrice,
                        fee: position.fee ?? 0,
                        executedAt: exitDate,
                        assetClass: "forex",
                        source: "the5ers"
                    ))
                }
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
    
    @MainActor
    private func mergePurchases(
        _ rawPurchases: [[String: Any]],
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount]
    ) {
        for purchase in rawPurchases {
            var fields: [String: Any] = [:]
            for (k, v) in purchase {
                let clean = k.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .lowercased()
                fields[clean] = v
            }
            
            let status = String(describing: fields["status"] ?? "completed").lowercased()
            let isRefunded = (fields["refunded"] as? Bool) ?? (fields["isrefunded"] as? Bool) ?? false
            guard (status == "completed" || status == "paid" || status == "approved") && !isRefunded else { continue }
            
            let rawDate = String(describing: fields["placedat"] ?? fields["date"] ?? fields["createdat"] ?? "")
            guard let date = FlexibleDateParser.parse(rawDate) else { continue }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = fmt.string(from: date)
            
            let currency = String(describing: fields["currency"] ?? "USD").uppercased()
            
            var itemNames: [String] = []
            var productType = "challenge_fee"
            var itemsTotal: Double = 0
            if let items = fields["items"] as? [[String: Any]] {
                for it in items {
                    if let n = (it["name"] ?? it["productName"]) as? String, !n.isEmpty {
                        itemNames.append(n)
                    }
                    if let pt = (it["producttype"] ?? it["product_type"] ?? it["category"]) as? String, !pt.isEmpty {
                        productType = pt.lowercased()
                    }
                    if let np = it["netpaid"] as? NSNumber {
                        itemsTotal += np.doubleValue
                    } else if let np = it["netpaid"] as? String, let d = Double(np) {
                        itemsTotal += d
                    }
                }
            }
            
            let priceNum = Double(String(describing: fields["price"] ?? fields["amount"] ?? "\(itemsTotal)")) ?? itemsTotal
            guard priceNum > 0 else { continue }
            let amountMinor = Int64(round(priceNum * 100))
            
            let title = itemNames.isEmpty ? "The5ers Program Evaluation" : itemNames.joined(separator: ", ")
            let purchaseHash = JournalIds.sha256("\(dateStr)_\(currency)_\(amountMinor)_\(title)")
            let entryId = "the5ers_purchase_\(purchaseHash.prefix(16))"
            let shortRef = "Order #\(purchaseHash.prefix(8))"
            
            let matchingAccId = targetAccounts.first(where: {
                title.contains("\($0.startingBalance ?? 0)") || $0.currency == currency
            })?.id
            let journalAccId = matchingAccId.map { $0.hasPrefix("the5ers_") ? $0 : "the5ers_\($0)" }
            
            if !dataStore.propEntries.contains(where: { $0.id == entryId }) {
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
}
