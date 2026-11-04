import Foundation
import Combine

/// Central networking service communicating with cTrader Open API via JSON WebSocket on port 5036.
@MainActor
public final class CTraderService: ObservableObject {
    public static let shared = CTraderService()
    
    // MARK: - Server Endpoints
    public static let liveEndpoint = "wss://live.ctraderapi.com:5036"
    public static let demoEndpoint = "wss://demo.ctraderapi.com:5036"
    
    // MARK: - Storage Keys
    internal static let keyAccessToken = "cTrader_accessToken"
    internal static let keyClientId = "cTrader_clientId"
    internal static let keyClientSecret = "cTrader_clientSecret"
    internal static let keyIsLive = "cTrader_isLive"
    internal static let keySelectedAccounts = "cTrader_selectedAccountIds"
    internal static let keyLastSyncDate = "cTrader_lastSyncDate"
    internal static let keyDiscoveredAccounts = "cTrader_discoveredAccounts"
    
    // MARK: - Published Properties
    @Published public var accessToken: String {
        didSet {
            let clean = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                KeychainManager.set(clean, forKey: Self.keyAccessToken)
            } else {
                KeychainManager.delete(forKey: Self.keyAccessToken)
            }
            UserDefaults.standard.removeObject(forKey: Self.keyAccessToken)
        }
    }
    @Published public var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: Self.keyClientId) }
    }
    @Published public var clientSecret: String {
        didSet {
            let clean = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                KeychainManager.set(clean, forKey: Self.keyClientSecret)
            } else {
                KeychainManager.delete(forKey: Self.keyClientSecret)
            }
            UserDefaults.standard.removeObject(forKey: Self.keyClientSecret)
        }
    }
    @Published public var isLive: Bool {
        didSet { UserDefaults.standard.set(isLive, forKey: Self.keyIsLive) }
    }
    @Published public var selectedAccountIds: Set<Int64> {
        didSet {
            let array = Array(selectedAccountIds)
            if let data = try? JSONEncoder().encode(array) {
                UserDefaults.standard.set(data, forKey: Self.keySelectedAccounts)
            }
        }
    }
    @Published public var lastSyncDate: Date? {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: Self.keyLastSyncDate) }
    }
    
    @Published public internal(set) var discoveredAccounts: [CTraderAccount] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(discoveredAccounts) {
                UserDefaults.standard.set(data, forKey: Self.keyDiscoveredAccounts)
            }
        }
    }
    @Published public internal(set) var isConnected: Bool = false
    @Published public internal(set) var isSyncing: Bool = false
    @Published public internal(set) var lastStatus: String = ""
    @Published public internal(set) var lastError: String? = nil
    
    public var isConfigured: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - WebSocket Session
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pendingContinuations: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var receiveTask: Task<Void, Never>?
    
    // MARK: - Initialization
    public init() {
        let kcToken = KeychainManager.get(forKey: Self.keyAccessToken) ?? AppSecretsLoader.loadSecret(named: "CTRADER_TOKEN") ?? ""
        let kcSecret = KeychainManager.get(forKey: Self.keyClientSecret) ?? AppSecretsLoader.loadSecret(named: "CTRADER_CLIENT_SECRET") ?? ""
        
        let udToken = UserDefaults.standard.string(forKey: Self.keyAccessToken) ?? ""
        let udSecret = UserDefaults.standard.string(forKey: Self.keyClientSecret) ?? ""
        
        let resolvedToken = !kcToken.isEmpty ? kcToken : udToken
        let resolvedSecret = !kcSecret.isEmpty ? kcSecret : udSecret
        
        // Migrate legacy plain text to Keychain
        if !udToken.isEmpty && kcToken.isEmpty {
            KeychainManager.set(udToken, forKey: Self.keyAccessToken)
            UserDefaults.standard.removeObject(forKey: Self.keyAccessToken)
        }
        if !udSecret.isEmpty && kcSecret.isEmpty {
            KeychainManager.set(udSecret, forKey: Self.keyClientSecret)
            UserDefaults.standard.removeObject(forKey: Self.keyClientSecret)
        }
        
        self.accessToken = resolvedToken
        self.clientId = UserDefaults.standard.string(forKey: Self.keyClientId) ?? ""
        self.clientSecret = resolvedSecret
        self.isLive = UserDefaults.standard.object(forKey: Self.keyIsLive) as? Bool ?? true
        self.lastSyncDate = UserDefaults.standard.object(forKey: Self.keyLastSyncDate) as? Date
        
        if let data = UserDefaults.standard.data(forKey: Self.keySelectedAccounts),
           let array = try? JSONDecoder().decode([Int64].self, from: data) {
            self.selectedAccountIds = Set(array)
        } else {
            self.selectedAccountIds = []
        }
        
        if let data = UserDefaults.standard.data(forKey: Self.keyDiscoveredAccounts),
           let array = try? JSONDecoder().decode([CTraderAccount].self, from: data) {
            self.discoveredAccounts = array
        } else {
            self.discoveredAccounts = []
        }
    }
    
    // MARK: - Connection & Disconnection
    
    /// Connects to cTrader Open API JSON WebSocket endpoint.
    public func connect() async throws {
        disconnect()
        
        let endpointString = isLive ? Self.liveEndpoint : Self.demoEndpoint
        guard let url = URL(string: endpointString) else {
            throw URLError(.badURL)
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        self.urlSession = session
        
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        
        startListening()
        self.isConnected = true
        self.lastStatus = "Connected to \(isLive ? "Live" : "Demo") cTrader gateway."
    }
    
    /// Closes active socket and cleans up listeners.
    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: URLError(.cancelled))
        }
        pendingContinuations.removeAll()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
    }
    
    // MARK: - Message Loop & Request Sending
    
    private func startListening() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self.handleIncomingMessageText(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleIncomingMessageText(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run { [weak self] in
                            self?.handleSocketError(error)
                        }
                    }
                    break
                }
            }
        }
    }
    
    private func handleIncomingMessageText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        let clientMsgId: String = {
            if let s = json["clientMsgId"] as? String { return s }
            if let p = json["payload"] as? [String: Any], let s = p["clientMsgId"] as? String { return s }
            return ""
        }()
        let payloadType = json["payloadType"] as? Int ?? 0
        var payload = json["payload"] as? [String: Any] ?? [:]
        if payload.isEmpty {
            payload = json
        }
        
        // Handle error responses (2142: ProtoOAErrorRes)
        if payloadType == 2142 {
            let errorCode = payload["errorCode"] as? String ?? "UNKNOWN_ERROR"
            let desc = payload["description"] as? String ?? "An error occurred with cTrader Open API."
            
            let isAlreadyAuthorized = errorCode == "ALREADY_LOGGED_IN" ||
                                      desc.lowercased().contains("already authorized") ||
                                      desc.lowercased().contains("already logged in") ||
                                      desc.lowercased().contains("already authenticated")
            
            if isAlreadyAuthorized {
                AppLogger.info("cTrader session/account is already authorized (\(errorCode): \(desc)). Resuming with success.")
                if let cont = pendingContinuations.removeValue(forKey: clientMsgId) {
                    cont.resume(returning: payload)
                } else if pendingContinuations.count == 1, let firstKey = pendingContinuations.keys.first, let cont = pendingContinuations.removeValue(forKey: firstKey) {
                    cont.resume(returning: payload)
                }
                return
            }
            
            let error = NSError(domain: "cTrader", code: payloadType, userInfo: [NSLocalizedDescriptionKey: "\(errorCode): \(desc)"])
            
            if let cont = pendingContinuations.removeValue(forKey: clientMsgId) {
                cont.resume(throwing: error)
            } else if pendingContinuations.count == 1, let firstKey = pendingContinuations.keys.first, let cont = pendingContinuations.removeValue(forKey: firstKey) {
                cont.resume(throwing: error)
            }
            return
        }
        
        if let cont = pendingContinuations.removeValue(forKey: clientMsgId) {
            cont.resume(returning: payload)
        } else if pendingContinuations.count == 1, let firstKey = pendingContinuations.keys.first, let cont = pendingContinuations.removeValue(forKey: firstKey) {
            cont.resume(returning: payload)
        }
    }
    
    private func handleSocketError(_ error: Error) {
        self.isConnected = false
        self.lastError = error.localizedDescription
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: error)
        }
        pendingContinuations.removeAll()
    }
    
    /// Sends an envelope and waits asynchronously for response matching clientMsgId.
    internal func sendRequest(payloadType: Int, payload: [String: Any], timeoutSeconds: Double = 20) async throws -> [String: Any] {
        guard let task = webSocketTask, isConnected else {
            throw NSError(domain: "cTrader", code: 400, userInfo: [NSLocalizedDescriptionKey: "WebSocket connection not established."])
        }
        
        let clientMsgId = UUID().uuidString
        let envelope: [String: Any] = [
            "clientMsgId": clientMsgId,
            "payloadType": payloadType,
            "payload": payload
        ]
        
        let data = try JSONSerialization.data(withJSONObject: envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "cTrader", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON request."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuations[clientMsgId] = continuation
            
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    self.pendingContinuations.removeValue(forKey: clientMsgId)
                    continuation.resume(throwing: error)
                    return
                }
                
                // Timeout handler
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let pending = self.pendingContinuations.removeValue(forKey: clientMsgId) {
                    pending.resume(throwing: NSError(domain: "cTrader", code: 408, userInfo: [NSLocalizedDescriptionKey: "Request timed out waiting for cTrader Open API response."]))
                }
            }
        }
    }
    
    // MARK: - cTrader Open API Commands
    
    /// Authorizes application (ProtoOAApplicationAuthReq, 2100).
    public func authenticateApplication() async throws {
        let cleanId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanId.isEmpty && !cleanSecret.isEmpty else {
            throw NSError(domain: "cTrader", code: 401, userInfo: [NSLocalizedDescriptionKey: "Client ID and Client Secret are required for cTrader Open API. Obtain them from openapi.ctrader.com."])
        }
        
        self.lastStatus = "Authorizing application..."
        do {
            _ = try await sendRequest(
                payloadType: 2100,
                payload: [
                    "clientId": cleanId,
                    "clientSecret": cleanSecret
                ]
            )
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already_logged_in") || msg.contains("already authorized") || msg.contains("already authenticated") {
                AppLogger.info("cTrader application is already authorized.")
            } else {
                throw error
            }
        }
    }
    
    /// Fetches all trading accounts linked to the user's Access Token (ProtoOAGetAccountListByAccessTokenReq, 2149).
    public func fetchAccounts() async throws -> [CTraderAccount] {
        let cleanToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw NSError(domain: "cTrader", code: 401, userInfo: [NSLocalizedDescriptionKey: "cTrader Access Token is required."])
        }
        
        try await connect()
        try await authenticateApplication()
        
        self.lastStatus = "Fetching trading accounts..."
        let res = try await sendRequest(
            payloadType: 2149,
            payload: ["accessToken": cleanToken]
        )
        
        guard let rawAccounts = (res["ctidTraderAccount"] as? [[String: Any]]) ?? (res["ctidTraderAccounts"] as? [[String: Any]]) ?? (res["accounts"] as? [[String: Any]]) else {
            self.discoveredAccounts = []
            return []
        }
        
        var accounts: [CTraderAccount] = []
        for raw in rawAccounts {
            let accId = safeInt64(raw["ctidTraderAccountId"]) ?? 0
            guard accId > 0 else { continue }
            let login = safeInt64(raw["traderLogin"]) ?? accId
            let isLive = (raw["isLive"] as? Bool) ?? ((raw["isLive"] as? NSNumber)?.boolValue) ?? true
            let broker = (raw["brokerTitleShort"] as? String) ?? (raw["brokerName"] as? String) ?? (raw["broker"] as? String) ?? (isLive ? "cTrader Live" : "cTrader Demo")
            
            let isSelected = selectedAccountIds.isEmpty || selectedAccountIds.contains(accId)
            
            accounts.append(CTraderAccount(
                ctidTraderAccountId: accId,
                traderLogin: login,
                isLive: isLive,
                brokerTitleShort: broker,
                isSelected: isSelected
            ))
        }
        
        // Enrich accounts with balance and currency by authorizing and querying each account
        for idx in accounts.indices {
            let accId = accounts[idx].ctidTraderAccountId
            do {
                _ = try await sendRequest(payloadType: 2102, payload: ["ctidTraderAccountId": accId, "accessToken": cleanToken])
                let traderRes = try await sendRequest(payloadType: 2121, payload: ["ctidTraderAccountId": accId])
                
                if let trader = (traderRes["trader"] as? [String: Any]) ?? (traderRes["traderData"] as? [String: Any]) {
                    if let broker = trader["brokerName"] as? String, !broker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        accounts[idx].brokerTitleShort = broker.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    let balanceRaw = safeInt64(trader["balance"]) ?? 0
                    let moneyDigits = safeInt64(trader["moneyDigits"]).map(Int.init) ?? 2
                    let divisor = pow(10.0, Double(moneyDigits))
                    let balDecimal = Decimal(Double(balanceRaw) / divisor)
                    let leverage = safeInt64(trader["leverageInCents"]).map { Int($0 / 100) } ?? 100
                    
                    accounts[idx].balance = balDecimal
                    accounts[idx].leverage = leverage
                    
                    var accountAssetMap: [Int64: String] = [:]
                    if let depId = safeInt64(trader["depositAssetId"]) {
                        if let assetListRes = try? await sendRequest(payloadType: 2112, payload: ["ctidTraderAccountId": accId]),
                                  let assets = (assetListRes["asset"] as? [[String: Any]]) ?? (assetListRes["assets"] as? [[String: Any]]) {
                            for a in assets {
                                if let aId = safeInt64(a["assetId"]),
                                   let aName = (a["name"] as? String) ?? (a["displayName"] as? String) {
                                    accountAssetMap[aId] = aName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                }
                            }
                        }
                        if let matched = accountAssetMap[depId], !matched.isEmpty {
                            accounts[idx].currency = matched
                            AppLogger.info("cTrader account \(accId) deposit currency resolved to \(matched) (assetId: \(depId)).")
                        } else {
                            accounts[idx].currency = "USD"
                        }
                    }
                }
            } catch {
                AppLogger.warning("Failed to enrich cTrader account \(accId): \(error.localizedDescription)")
            }
        }
        
        self.discoveredAccounts = accounts
        self.lastStatus = "Found \(accounts.count) trading account(s)."
        registerDiscoveredAccounts(into: TradeDataStore.shared)
        return accounts
    }
    
    // MARK: - Safe Parsing Helpers
    
    internal func safeInt64(_ val: Any?) -> Int64? {
        guard let v = val else { return nil }
        if let n = v as? NSNumber { return n.int64Value }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let s = v as? String {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int64(clean) { return parsed }
            if let d = Double(clean) { return Int64(d) }
        }
        return nil
    }
    
    internal func safeDouble(_ val: Any?) -> Double? {
        guard let v = val else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let f = v as? Float { return Double(f) }
        if let i = v as? Int64 { return Double(i) }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String {
            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(clean)
        }
        return nil
    }
}
