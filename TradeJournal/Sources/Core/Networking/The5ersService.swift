import Foundation
import CryptoKit

/// Model dữ liệu trả về từ The5ers MCP Protocol (the5ers_account)
public struct The5ersMcpAccount: Identifiable, Codable, Sendable {
    public let id: String
    public let label: String
    public let platform: String?
    public let balance: Decimal
    public let equity: Decimal?
    public let currency: String
    public let status: String // active, passed, breached, closed
    public let program: String // evaluation, verification, funded, instant_funded
    public let startingBalance: Decimal?
    public let createdAt: String?
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
    
    public var isConfigured: Bool {
        !mcpToken.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private init() {
        self.mcpToken = UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? ""
        self.isConnected = !mcpToken.isEmpty
    }
    
    public func configure(token: String) {
        self.mcpToken = token.trimmingCharacters(in: .whitespaces)
        self.isConnected = !self.mcpToken.isEmpty
        UserDefaults.standard.set(self.mcpToken, forKey: "the5ers_mcp_token")
    }
    
    public func disconnect() {
        self.mcpToken = ""
        self.isConnected = false
        self.mcpSessionId = nil
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
    
    /// Gửi một yêu cầu JSON-RPC 2.0 tới The5ers MCP server tuân thủ chuẩn Model Context Protocol
    public func sendMcpRpc(method: String, params: [String: Any]) async throws -> [String: Any] {
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
        
        // Trích xuất JSON từ định dạng Server-Sent Events (SSE) nếu cần
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
    
    // MARK: - 3. Đồng Bộ Dữ Liệu Thực Tế Qua MCP Tools
    
    @MainActor
    public func syncWithTradeStore(dataStore: TradeDataStore) async throws -> Int {
        guard isConfigured else {
            throw NSError(domain: "The5ersMCP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình Token The5ers MCP. Vui lòng bấm 'Đăng Nhập The5ers Hub (OAuth PKCE)'. "])
        }
        
        isSyncing = true
        lastStatus = "Đang kết nối The5ers MCP và gọi the5ers_account (list)..."
        defer { isSyncing = false }
        
        do {
            // 1. Gọi MCP tool the5ers_account
            let accountResult = try await callMcpTool(name: "the5ers_account", arguments: ["operation": "list"])
            var accountsList: [The5ersMcpAccount] = []
            
            func parseMcpTextPayload(_ dict: [String: Any]) -> Data? {
                if let content = dict["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    return text.data(using: .utf8)
                }
                return nil
            }
            
            if let data = parseMcpTextPayload(accountResult),
               let parsed = try? JSONDecoder().decode([The5ersMcpAccount].self, from: data) {
                accountsList = parsed
            } else if let directList = (accountResult["accounts"] ?? accountResult["items"]) as? [[String: Any]] {
                for item in directList {
                    let id = String(describing: item["id"] ?? item["account_id"] ?? UUID().uuidString)
                    let label = String(describing: item["label"] ?? item["name"] ?? "The5ers Account")
                    let bal = Decimal(string: String(describing: item["balance"] ?? "0")) ?? 0
                    let eq = Decimal(string: String(describing: item["equity"] ?? bal)) ?? bal
                    let curr = String(describing: item["currency"] ?? "USD")
                    let status = String(describing: item["status"] ?? "active")
                    let prog = String(describing: item["program"] ?? "funded")
                    let startBal = Decimal(string: String(describing: item["startingBalance"] ?? item["initial_balance"] ?? bal)) ?? bal
                    
                    accountsList.append(The5ersMcpAccount(
                        id: id,
                        label: label,
                        platform: String(describing: item["platform"] ?? "MT5"),
                        balance: bal,
                        equity: eq,
                        currency: curr,
                        status: status,
                        program: prog,
                        startingBalance: startBal,
                        createdAt: item["createdAt"] as? String
                    ))
                }
            }
            
            // Tuyệt đối không nạp dữ liệu giả/demo: nếu trống thì báo không có
            if accountsList.isEmpty {
                lastStatus = "Máy chủ The5ers MCP phản hồi thành công nhưng không tìm thấy tài khoản giao dịch nào."
                return 0
            }
            
            var importedPositionsCount = 0
            
            // 2. Đồng bộ từng tài khoản và lấy các vị thế thực tế qua the5ers_positions
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
                
                // Đồng bộ Quỹ (Prop Firm Subsystem)
                if let existingIndex = dataStore.propAccounts.firstIndex(where: { $0.id == acc.id || $0.name == acc.label }) {
                    var existing = dataStore.propAccounts[existingIndex]
                    existing.status = mappedStatus
                    existing.program = mappedProgram
                    dataStore.propAccounts[existingIndex] = existing
                } else {
                    let newPropAccount = PropAccountItem(
                        id: acc.id,
                        firm: "The5ers",
                        name: acc.label,
                        program: mappedProgram,
                        status: mappedStatus,
                        currency: acc.currency,
                        sizeMinor: startingMinor,
                        journalAccountId: acc.id,
                        openedOn: acc.createdAt ?? DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
                        notes: "Đồng bộ từ The5ers MCP Hub (Protocol 2025-03-26)",
                        archived: false
                    )
                    dataStore.propAccounts.append(newPropAccount)
                }
                
                // Đồng bộ Account chính trong dataStore
                if let accIdx = dataStore.accounts.firstIndex(where: { $0.id == acc.id }) {
                    dataStore.accounts[accIdx].broker = "The5ers"
                    dataStore.accounts[accIdx].name = acc.label
                    dataStore.accounts[accIdx].currency = acc.currency
                } else {
                    let newAcc = Account(
                        id: acc.id,
                        name: acc.label,
                        broker: "The5ers",
                        kind: .sync,
                        currency: acc.currency,
                        initialBalance: acc.startingBalance ?? acc.balance,
                        autoSync: true
                    )
                    dataStore.accounts.append(newAcc)
                }
                
                // 3. Gọi the5ers_positions để lấy các lệnh thực tế
                lastStatus = "Đang tải vị thế lệnh cho tài khoản \(acc.label)..."
                if let posResult = try? await callMcpTool(name: "the5ers_positions", arguments: ["operation": "list", "accountId": acc.id]) {
                    var rawPositions: [[String: Any]] = []
                    if let data = parseMcpTextPayload(posResult),
                       let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        rawPositions = jsonArray
                    } else if let direct = (posResult["positions"] ?? posResult["trades"] ?? posResult["items"]) as? [[String: Any]] {
                        rawPositions = direct
                    }
                    
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let isoFallback = ISO8601DateFormatter()
                    isoFallback.formatOptions = [.withInternetDateTime]
                    
                    for p in rawPositions {
                        let symbol = String(describing: p["symbol"] ?? "").trimmingCharacters(in: .whitespaces)
                        guard !symbol.isEmpty else { continue }
                        
                        let sideStr = String(describing: p["side"] ?? p["direction"] ?? "buy").lowercased()
                        let dir: TradeDirection = (sideStr.contains("sell") || sideStr.contains("short")) ? .short : .long
                        
                        let qty = Decimal(string: String(describing: p["quantity"] ?? p["lots"] ?? p["size"] ?? "0")) ?? 0
                        let entry = Decimal(string: String(describing: p["entry"] ?? p["openPrice"] ?? "0")) ?? 0
                        let exit = Decimal(string: String(describing: p["exit"] ?? p["closePrice"] ?? ""))
                        let netPnl = Decimal(string: String(describing: p["profitAndLoss"] ?? p["netPnl"] ?? p["pnl"] ?? "0")) ?? 0
                        let fee = Decimal(string: String(describing: p["fee"] ?? p["commission"] ?? "0")) ?? 0
                        let swap = Decimal(string: String(describing: p["swap"] ?? "0")) ?? 0
                        
                        let openStr = String(describing: p["openDate"] ?? p["openedAt"] ?? "")
                        let closeStr = String(describing: p["closeDate"] ?? p["closedAt"] ?? "")
                        
                        let openDate = iso.date(from: openStr) ?? isoFallback.date(from: openStr) ?? Date()
                        let closeDate = iso.date(from: closeStr) ?? isoFallback.date(from: closeStr)
                        let isClosed = (closeDate != nil) || (p["isClosed"] as? Bool == true)
                        
                        let pId = String(describing: p["id"] ?? p["ticket"] ?? p["providerId"] ?? UUID().uuidString)
                        let tradeKey = "the5ers_\(acc.id)_\(pId)"
                        
                        let status: TradeStatus = isClosed ? (netPnl > 0 ? .win : (netPnl < 0 ? .loss : .breakeven)) : .open
                        
                        let trade = Trade(
                            key: tradeKey,
                            accountId: acc.id,
                            symbol: symbol,
                            direction: dir,
                            status: status,
                            openedAt: openDate,
                            closedAt: isClosed ? (closeDate ?? openDate) : nil,
                            quantity: qty,
                            openQuantity: isClosed ? 0 : qty,
                            avgEntry: entry,
                            avgExit: exit,
                            grossPnl: netPnl + fee + swap,
                            fees: -(abs(fee) + abs(swap)),
                            netPnl: netPnl,
                            executionCount: 0,
                            executionIds: [],
                            notes: "Vị thế được đồng bộ từ The5ers Hub (Ticket: \(pId))",
                            tags: ["the5ers", acc.program.lowercased()]
                        )
                        
                        if let tIdx = dataStore.trades.firstIndex(where: { $0.key == tradeKey }) {
                            dataStore.trades[tIdx] = trade
                        } else {
                            dataStore.trades.append(trade)
                            importedPositionsCount += 1
                        }
                    }
                }
            }
            
            // 4. Đồng bộ the5ers_payout
            lastStatus = "Đang tải lịch sử rút tiền the5ers_payout..."
            if let payoutResult = try? await callMcpTool(name: "the5ers_payout", arguments: ["operation": "history"]) {
                var rawPayouts: [[String: Any]] = []
                if let data = parseMcpTextPayload(payoutResult),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    rawPayouts = arr
                } else if let direct = (payoutResult["payouts"] ?? payoutResult["withdrawals"] ?? payoutResult["items"]) as? [[String: Any]] {
                    rawPayouts = direct
                }
                
                for pay in rawPayouts {
                    let id = String(describing: pay["id"] ?? UUID().uuidString)
                    let amtMinor = Int64(Double(String(describing: pay["amount"] ?? "0")) ?? 0) * 100
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
            dataStore.saveToDisk()
            lastStatus = "Đã đồng bộ thành công \(accountsList.count) tài khoản và \(importedPositionsCount) vị thế thực tế từ The5ers MCP."
            return accountsList.count
        } catch {
            lastStatus = "Lỗi đồng bộ The5ers MCP: \(error.localizedDescription)"
            throw error
        }
    }
}
