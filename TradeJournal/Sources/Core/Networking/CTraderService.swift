import Foundation
import Combine

/// Represents an authorized cTrader trading account retrieved from the cTrader Open API.
public struct CTraderAccount: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let ctidTraderAccountId: Int64
    public var id: Int64 { ctidTraderAccountId }
    public let traderLogin: Int64
    public let isLive: Bool
    public var brokerTitleShort: String
    public var balance: Decimal
    public var currency: String
    public var leverage: Int
    public var isSelected: Bool
    
    public init(
        ctidTraderAccountId: Int64,
        traderLogin: Int64,
        isLive: Bool,
        brokerTitleShort: String,
        balance: Decimal = 0,
        currency: String = "USD",
        leverage: Int = 100,
        isSelected: Bool = true
    ) {
        self.ctidTraderAccountId = ctidTraderAccountId
        self.traderLogin = traderLogin
        self.isLive = isLive
        self.brokerTitleShort = brokerTitleShort
        self.balance = balance
        self.currency = currency
        self.leverage = leverage
        self.isSelected = isSelected
    }
}

/// Represents an execution deal retrieved from the cTrader Open API.
public struct CTraderDeal: Identifiable, Codable, Sendable {
    public let dealId: Int64
    public var id: Int64 { dealId }
    public let orderId: Int64
    public let positionId: Int64
    public let volume: Int64
    public let filledVolume: Int64
    public let symbolId: Int64
    public var symbolName: String
    public let executionPrice: Double
    public let tradeSide: String
    public let executionTimestamp: Int64
    public let commission: Int64
    public let closePositionDetail: CTraderCloseDetail?
    public let moneyDigits: Int?
}

/// Closing position detail for deals that offset or close an open position.
public struct CTraderCloseDetail: Codable, Sendable {
    public let entryPrice: Double
    public let grossProfit: Int64
    public let swap: Int64
    public let commission: Int64
    public let balance: Int64
    public let closedVolume: Int64
    public let moneyDigits: Int?
}

/// Open position retrieved from cTrader reconcile endpoint.
public struct CTraderPosition: Identifiable, Codable, Sendable {
    public let positionId: Int64
    public var id: Int64 { positionId }
    public let symbolId: Int64
    public var symbolName: String
    public let volume: Int64
    public let tradeSide: String
    public let price: Double
    public let stopLoss: Double?
    public let takeProfit: Double?
    public let openTimestamp: Int64?
    public let swap: Int64
    public let commission: Int64
}

/// Summary report of a cTrader synchronization run.
public struct CTraderSyncSummary: Equatable, Sendable {
    public let accountsSynced: Int
    public let dealsImported: Int
    public let tradesRebuilt: Int
    public let message: String
}

/// Central networking service communicating with cTrader Open API via JSON WebSocket on port 5036.
@MainActor
public final class CTraderService: ObservableObject {
    public static let shared = CTraderService()
    
    // MARK: - Server Endpoints
    public static let liveEndpoint = "wss://live.ctraderapi.com:5036"
    public static let demoEndpoint = "wss://demo.ctraderapi.com:5036"
    
    // MARK: - Storage Keys
    private static let keyAccessToken = "cTrader_accessToken"
    private static let keyClientId = "cTrader_clientId"
    private static let keyClientSecret = "cTrader_clientSecret"
    private static let keyIsLive = "cTrader_isLive"
    private static let keySelectedAccounts = "cTrader_selectedAccountIds"
    private static let keyLastSyncDate = "cTrader_lastSyncDate"
    private static let keyDiscoveredAccounts = "cTrader_discoveredAccounts"
    
    // MARK: - Published Properties
    @Published public var accessToken: String {
        didSet { UserDefaults.standard.set(accessToken, forKey: Self.keyAccessToken) }
    }
    @Published public var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: Self.keyClientId) }
    }
    @Published public var clientSecret: String {
        didSet { UserDefaults.standard.set(clientSecret, forKey: Self.keyClientSecret) }
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
    
    @Published public private(set) var discoveredAccounts: [CTraderAccount] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(discoveredAccounts) {
                UserDefaults.standard.set(data, forKey: Self.keyDiscoveredAccounts)
            }
        }
    }
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastStatus: String = ""
    @Published public private(set) var lastError: String? = nil
    
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
        self.accessToken = UserDefaults.standard.string(forKey: Self.keyAccessToken) ?? ""
        self.clientId = UserDefaults.standard.string(forKey: Self.keyClientId) ?? ""
        self.clientSecret = UserDefaults.standard.string(forKey: Self.keyClientSecret) ?? ""
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
            
            // "ALREADY_LOGGED_IN" or "Trading account is already authorized" is a normal/expected idempotent response
            // when an account or application was authorized previously on the same WebSocket session.
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
    private func sendRequest(payloadType: Int, payload: [String: Any], timeoutSeconds: Double = 20) async throws -> [String: Any] {
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
            // If user left app credentials empty, inform them clearly
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
        var assetCache: [Int64: String] = [:]
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
                    let moneyDigits = (safeInt64(trader["moneyDigits"]) != nil) ? Int(safeInt64(trader["moneyDigits"])!) : 2
                    let divisor = pow(10.0, Double(moneyDigits))
                    let balDecimal = Decimal(Double(balanceRaw) / divisor)
                    let leverage = (safeInt64(trader["leverageInCents"]) != nil) ? Int(safeInt64(trader["leverageInCents"])! / 100) : 100
                    
                    accounts[idx].balance = balDecimal
                    accounts[idx].leverage = leverage
                    
                    // Lookup deposit currency from asset cache or asset list
                    if let depId = safeInt64(trader["depositAssetId"]) {
                        if let cached = assetCache[depId] {
                            accounts[idx].currency = cached
                        } else if let assetListRes = try? await sendRequest(payloadType: 2112, payload: ["ctidTraderAccountId": accId]),
                                  let assets = (assetListRes["asset"] as? [[String: Any]]) ?? (assetListRes["assets"] as? [[String: Any]]) {
                            for a in assets {
                                if let aId = safeInt64(a["assetId"]), let aName = a["name"] as? String {
                                    assetCache[aId] = aName
                                }
                            }
                            if let matched = assetCache[depId] {
                                accounts[idx].currency = matched
                            }
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
    
    // MARK: - Auto-Registration into TradeDataStore
    
    /// Registers discovered cTrader accounts directly into TradeDataStore so they immediately appear
    /// in the ShellHeaderView account dropdown, AccountsManagerView, and all journal filtering views.
    @discardableResult
    public func registerDiscoveredAccounts(into dataStore: TradeDataStore) -> [Account] {
        guard !discoveredAccounts.isEmpty else { return [] }
        
        var registered: [Account] = []
        var hasChanges = false
        
        for account in discoveredAccounts {
            let journalAccId = "ctrader_\(account.ctidTraderAccountId)"
            let brokerName = account.brokerTitleShort.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeBroker = brokerName.isEmpty ? "cTrader" : brokerName
            let envLabel = account.isLive ? "Live" : "Demo"
            let accountName = "\(safeBroker) #\(account.traderLogin) (\(envLabel))"
            
            if let existingIdx = dataStore.accounts.firstIndex(where: {
                $0.id == journalAccId ||
                $0.id.isEquivalentAccountId(to: journalAccId) ||
                $0.id.cleanAccountId == String(account.ctidTraderAccountId) ||
                $0.id.cleanAccountId == String(account.traderLogin) ||
                $0.name.contains("\(account.traderLogin)")
            }) {
                var acc = dataStore.accounts[existingIdx]
                acc.name = accountName
                acc.broker = safeBroker
                acc.currency = account.currency
                acc.kind = .sync
                acc.autoSync = true
                if acc.initialBalance == 0 && account.balance > 0 {
                    acc.initialBalance = account.balance
                }
                dataStore.accounts[existingIdx] = acc
                registered.append(acc)
                hasChanges = true
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: accountName,
                    broker: safeBroker,
                    kind: .sync,
                    currency: account.currency,
                    initialBalance: account.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true,
                    visibleInJournal: true
                )
                dataStore.accounts.append(newAcc)
                registered.append(newAcc)
                hasChanges = true
            }
        }
        
        // Remove default placeholder account if real accounts are registered
        if dataStore.accounts.contains(where: { $0.id.hasPrefix("ctrader_") || $0.id.hasPrefix("the5ers_") }) {
            dataStore.accounts.removeAll(where: { $0.id == "default-acc" && dataStore.accounts.count > 1 })
        }
        
        // Auto-select this cTrader account if current selection is default-acc
        if dataStore.selectedAccountId == "default-acc", let firstRegistered = registered.first {
            dataStore.selectedAccountId = firstRegistered.id
        }
        
        if hasChanges {
            dataStore.deduplicateAndCleanAccounts()
            dataStore.saveToDisk(immediate: true)
            dataStore.objectWillChange.send()
        }
        
        return registered
    }
    
    /// Tests connection and retrieves linked accounts without modifying journal data.
    public func testConnection() async throws -> (success: Bool, message: String, accounts: [CTraderAccount]) {
        self.isSyncing = true
        self.lastError = nil
        defer {
            self.isSyncing = false
            disconnect()
        }
        
        do {
            let accs = try await fetchAccounts()
            let registered = registerDiscoveredAccounts(into: TradeDataStore.shared)
            return (true, "cTrader connection verified! \(accs.count) account(s) registered in Journal.", accs)
        } catch {
            self.lastError = error.localizedDescription
            return (false, "Connection error: \(error.localizedDescription)", [])
        }
    }
    
    // MARK: - Full Synchronization with TradeDataStore
    
    /// Fully synchronizes selected cTrader accounts and their deal histories into TradeDataStore.
    public func syncWithTradeStore(
        dataStore: TradeDataStore,
        fromTimestamp: Int64? = nil,
        toTimestamp: Int64? = nil,
        targetAccountIds: Set<Int64>? = nil
    ) async throws -> CTraderSyncSummary {
        guard isConfigured else {
            throw NSError(domain: "cTrader", code: 401, userInfo: [NSLocalizedDescriptionKey: "cTrader Access Token is not configured."])
        }
        
        self.isSyncing = true
        self.lastStatus = "Connecting to cTrader Open API..."
        self.lastError = nil
        defer {
            self.isSyncing = false
            disconnect()
        }
        
        let allAccounts = try await fetchAccounts()
        let activeAccounts = allAccounts.filter { acc in
            if let targets = targetAccountIds, !targets.isEmpty {
                return targets.contains(acc.ctidTraderAccountId)
            }
            return selectedAccountIds.isEmpty || selectedAccountIds.contains(acc.ctidTraderAccountId)
        }
        
        guard !activeAccounts.isEmpty else {
            let msg = "No cTrader accounts selected for synchronization."
            self.lastStatus = msg
            return CTraderSyncSummary(accountsSynced: 0, dealsImported: 0, tradesRebuilt: 0, message: msg)
        }
        
        var totalDeals = 0
        var totalRebuiltTrades = 0
        let cleanToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        for account in activeAccounts {
            let accId = account.ctidTraderAccountId
            self.lastStatus = "Syncing account \(account.traderLogin) (\(account.brokerTitleShort))..."
            
            // 1. Authorize specific account session
            do {
                _ = try await sendRequest(
                    payloadType: 2102,
                    payload: ["ctidTraderAccountId": accId, "accessToken": cleanToken]
                )
            } catch {
                let msg = error.localizedDescription.lowercased()
                if msg.contains("already_logged_in") || msg.contains("already authorized") || msg.contains("already logged in") {
                    AppLogger.info("cTrader account \(accId) is already authorized on this session.")
                } else {
                    AppLogger.warn("cTrader account authorization notice for \(accId): \(error.localizedDescription)")
                }
            }
            
            // 2. Fetch Symbol Dictionary (including archived symbols to handle closed trades on delisted/renamed symbols)
            var symbolMap: [Int64: String] = [:]
            if let symbolsRes = try? await sendRequest(payloadType: 2114, payload: ["ctidTraderAccountId": accId, "includeArchivedSymbols": true]) {
                let symbolArray = (symbolsRes["symbol"] as? [[String: Any]]) ?? (symbolsRes["symbols"] as? [[String: Any]]) ?? []
                for s in symbolArray {
                    if let sId = safeInt64(s["symbolId"]),
                       let sName = (s["symbolName"] as? String) ?? (s["name"] as? String) {
                        symbolMap[sId] = sName
                    }
                }
                let archivedArray = (symbolsRes["archivedSymbol"] as? [[String: Any]]) ?? (symbolsRes["archivedSymbols"] as? [[String: Any]]) ?? []
                for s in archivedArray {
                    if let sId = safeInt64(s["symbolId"]),
                       let sName = (s["symbolName"] as? String) ?? (s["name"] as? String) {
                        if symbolMap[sId] == nil {
                            symbolMap[sId] = sName
                        }
                    }
                }
            }
            
            // 3. Ensure Journal Account exists
            let journalAccId = "ctrader_\(accId)"
            let brokerName = account.brokerTitleShort.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeBroker = brokerName.isEmpty ? "cTrader" : brokerName
            let envLabel = account.isLive ? "Live" : "Demo"
            let accountName = "\(safeBroker) #\(account.traderLogin) (\(envLabel))"
            
            if let existingIdx = dataStore.accounts.firstIndex(where: {
                $0.id == journalAccId ||
                $0.id.isEquivalentAccountId(to: journalAccId) ||
                $0.id.cleanAccountId == String(account.ctidTraderAccountId) ||
                $0.id.cleanAccountId == String(account.traderLogin) ||
                $0.name.contains("\(account.traderLogin)")
            }) {
                var acc = dataStore.accounts[existingIdx]
                acc.name = accountName
                acc.broker = safeBroker
                acc.currency = account.currency
                acc.kind = .sync
                acc.autoSync = true
                acc.visibleInJournal = true
                if acc.initialBalance == 0 && account.balance > 0 {
                    acc.initialBalance = account.balance
                }
                dataStore.accounts[existingIdx] = acc
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: accountName,
                    broker: safeBroker,
                    kind: .sync,
                    currency: account.currency,
                    initialBalance: account.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true,
                    visibleInJournal: true
                )
                dataStore.accounts.append(newAcc)
                dataStore.saveToDisk()
            }
            
            // 4. Fetch Historical Deals in 6-day chunks
            // cTrader Open API enforces a strict maximum 7-day window (604,800,000 ms) and maxRows <= 1000 per ProtoOADealListReq.
            // Sending larger intervals or maxRows > 1000 triggers ProtoOAErrorRes (2142) INCORRECT_BOUNDS.
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let maxChunkMs: Int64 = 6 * 24 * 60 * 60 * 1000 // 518,400,000 ms (6 days safe margin)
            let dealsTo = toTimestamp ?? nowMs
            
            let defaultLookbackDays: Int64 = 180 // Fast lookback window (6 months) for responsive account loading
            let fallbackStart = max(nowMs - (defaultLookbackDays * 86_400 * 1000), 0)
            
            let existingAccountExecs = dataStore.executions.filter { $0.accountId == journalAccId }
            let dealsFrom: Int64
            if let fromTimestamp = fromTimestamp, fromTimestamp > 0 {
                dealsFrom = fromTimestamp
            } else if let latestDate = existingAccountExecs.map({ $0.executedAt }).max() {
                // Incremental sync: rewind 2 days before latest known fill to catch any delayed fills or fee reconciliations
                let latestMs = Int64(latestDate.timeIntervalSince1970 * 1000)
                dealsFrom = max(latestMs - (2 * 86_400 * 1000), 0)
            } else {
                dealsFrom = fallbackStart
            }
            
            var rawDeals: [[String: Any]] = []
            var seenDealIds = Set<Int64>()
            let totalSpanMs = max(dealsTo - dealsFrom, 1)
            let estimatedChunks = max(1, Int((totalSpanMs + maxChunkMs - 1) / maxChunkMs))
            var chunkIndex = 0
            var consecutiveEmptyChunks = 0
            
            // Query backwards from dealsTo -> dealsFrom (Recent -> Past)
            // Ensures latest trades are fetched immediately on the very first chunk
            var currentChunkEnd = dealsTo
            while currentChunkEnd > dealsFrom {
                chunkIndex += 1
                let currentChunkStart = max(currentChunkEnd - maxChunkMs, dealsFrom)
                guard currentChunkEnd > currentChunkStart else { break }
                
                self.lastStatus = "Fetching cTrader deals (\(chunkIndex)/\(estimatedChunks))..."
                
                var dealsFoundInChunk = 0
                var chunkFrom = currentChunkStart
                while chunkFrom < currentChunkEnd {
                    let payload: [String: Any] = [
                        "ctidTraderAccountId": accId,
                        "fromTimestamp": chunkFrom,
                        "toTimestamp": currentChunkEnd,
                        "maxRows": 1000
                    ]
                    
                    do {
                        let dealsRes = try await sendRequest(payloadType: 2133, payload: payload)
                        let dealsList = (dealsRes["deal"] as? [[String: Any]]) ?? (dealsRes["deals"] as? [[String: Any]]) ?? (dealsRes["items"] as? [[String: Any]]) ?? []
                        var latestDealTs: Int64 = 0
                        for d in dealsList {
                            if let dealId = safeInt64(d["dealId"]) ?? safeInt64(d["id"]) {
                                if seenDealIds.insert(dealId).inserted {
                                    rawDeals.append(d)
                                    dealsFoundInChunk += 1
                                }
                            }
                            if let ts = safeInt64(d["executionTimestamp"]) ?? safeInt64(d["createTimestamp"]) ?? safeInt64(d["timestamp"]) {
                                latestDealTs = max(latestDealTs, ts)
                            }
                        }
                        
                        let hasMore = (dealsRes["hasMore"] as? Bool) ?? false
                        if hasMore && latestDealTs > chunkFrom && latestDealTs < currentChunkEnd {
                            chunkFrom = latestDealTs + 1
                        } else {
                            break
                        }
                    } catch {
                        AppLogger.warn("cTrader deal chunk [\(chunkFrom)-\(currentChunkEnd)] returned error: \(error.localizedDescription)")
                        break
                    }
                }
                
                if dealsFoundInChunk == 0 && !rawDeals.isEmpty {
                    consecutiveEmptyChunks += 1
                    if consecutiveEmptyChunks >= 4 {
                        // Encountered 24 consecutive days without activity prior to known trades
                        break
                    }
                } else if dealsFoundInChunk > 0 {
                    consecutiveEmptyChunks = 0
                }
                
                currentChunkEnd = currentChunkStart
                if currentChunkEnd > dealsFrom {
                    try? await Task.sleep(nanoseconds: 30_000_000) // 30ms throttle between chunk requests
                }
            }
            
            // 5. Convert Deals to Atomic Executions
            var newExecutions: [Execution] = []
            for raw in rawDeals {
                guard let dealId = safeInt64(raw["dealId"]) ?? safeInt64(raw["id"]),
                      let symbolId = safeInt64(raw["symbolId"]),
                      let execTimestamp = safeInt64(raw["executionTimestamp"]) ?? safeInt64(raw["createTimestamp"]) ?? safeInt64(raw["timestamp"]) else {
                    continue
                }
                
                // Validate deal status if present (FILLED = 1, PARTIALLY_FILLED = 2)
                if let statusVal = safeInt64(raw["dealStatus"]) {
                    if statusVal >= 3 { continue } // Skip 3: REJECTED, 4: INTERNALLY_REJECTED, 5: ERROR, 6: MISSED
                } else if let statusStr = raw["dealStatus"] as? String {
                    let upper = statusStr.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if upper == "REJECTED" || upper == "INTERNALLY_REJECTED" || upper == "ERROR" || upper == "MISSED" || upper == "CANCELLED" {
                        continue
                    }
                }
                
                let volRaw = safeInt64(raw["filledVolume"]) ?? safeInt64(raw["volume"]) ?? 0
                guard volRaw > 0 else { continue }
                
                let priceRaw = safeDouble(raw["executionPrice"]) ?? safeDouble(raw["rate"]) ?? safeDouble(raw["price"]) ?? safeDouble(raw["closePrice"]) ?? safeDouble(raw["bid"]) ?? safeDouble(raw["ask"]) ?? 0.0
                guard priceRaw > 0 else { continue }
                
                let symbolName = symbolMap[symbolId] ?? (raw["symbolName"] as? String) ?? (raw["symbol"] as? String) ?? "Symbol_\(symbolId)"
                let sideStr = String(describing: raw["tradeSide"] ?? "BUY").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let side: ExecutionSide = (sideStr == "SELL" || sideStr == "2") ? .sell : .buy
                
                // Volume conversion:
                // In cTrader Open API, volume is represented in cents.
                // Forex: 1 lot = 100,000 units = 10,000,000 cents.
                // Metals (Gold/Silver): 1 lot = 100 oz = 1,000,000 cents.
                // Indices / CFDs / Crypto: 1 contract = 1 unit = 100 cents.
                // Symbol classification goes through AssetContractEngine so that broker suffixes
                // (EURUSDm, EURUSD.pro, ...) do not turn a FX pair into a "1 unit per contract" CFD.
                let spec = AssetContractEngine.spec(for: symbolName)
                let isMetals = spec.assetCategory == .goldAndMetals
                let isForex = spec.isForex
                let isCrypto = spec.assetCategory == .crypto
                
                let lotDivisor: Decimal
                if isMetals {
                    lotDivisor = 1_000_000
                } else if isForex {
                    lotDivisor = 10_000_000
                } else {
                    lotDivisor = 100
                }
                let quantity = max(Decimal(0.01), Decimal(volRaw) / lotDivisor)
                
                let moneyDigits = (safeInt64(raw["moneyDigits"]) != nil) ? Int(safeInt64(raw["moneyDigits"])!) : 2
                let moneyDivisor = pow(10.0, Double(moneyDigits))
                let commRaw = safeDouble(raw["commission"]) ?? 0.0
                let fee = Decimal(abs(commRaw) / moneyDivisor)
                
                // Swap / overnight interest: negative = cost charged, positive = credit received.
                // cTrader reports it on the closing deal (closePositionDetail) and on the position.
                let closeDetail = raw["closePositionDetail"] as? [String: Any]
                let swapRaw = safeDouble(closeDetail?["swap"]) ?? safeDouble(raw["swap"]) ?? 0.0
                let swap: Decimal? = swapRaw != 0 ? Decimal(swapRaw / moneyDivisor) : nil
                
                let execDate = Date(timeIntervalSince1970: Double(execTimestamp) / 1000.0)
                let fillId = "ctrader_deal_\(dealId)"
                let hash = "\(journalAccId)|\(spec.cleanSymbol)|\(side.rawValue)|\(quantity)|\(priceRaw)|\(execTimestamp)"
                
                let assetClass = isForex ? "forex" : (isMetals ? "commodity" : (isCrypto ? "crypto" : "index"))
                
                let exec = Execution(
                    id: fillId,
                    accountId: journalAccId,
                    symbol: symbolName,
                    side: side,
                    quantity: quantity,
                    price: Decimal(priceRaw),
                    fee: fee,
                    swap: swap,
                    executedAt: execDate,
                    assetClass: assetClass,
                    source: "ctrader",
                    contentHash: hash
                )
                newExecutions.append(exec)
            }
            
            // 6. Ingest executions and rebuild round trips
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
                totalDeals += newExecutions.count
            } else if dataStore.trades.filter({ $0.accountId == journalAccId }).isEmpty && !dataStore.executions.filter({ $0.accountId == journalAccId }).isEmpty {
                dataStore.rebuildAccount(accountId: journalAccId)
            }
            
            // 7. Check for open positions via Reconcile (payloadType 2124)
            if let reconcileRes = try? await sendRequest(payloadType: 2124, payload: ["ctidTraderAccountId": accId]),
               let positions = (reconcileRes["position"] as? [[String: Any]]) ?? (reconcileRes["positions"] as? [[String: Any]]) {
                
                var activePosKeys = Set<String>()
                
                for pos in positions {
                    let tradeData = (pos["tradeData"] as? [String: Any]) ?? pos
                    guard let posId = safeInt64(pos["positionId"]) ?? safeInt64(tradeData["positionId"]),
                          let sId = safeInt64(tradeData["symbolId"]) ?? safeInt64(pos["symbolId"]),
                          let vol = safeInt64(tradeData["volume"]) ?? safeInt64(pos["volume"]),
                          let price = safeDouble(pos["price"]) ?? safeDouble(tradeData["price"]) else {
                        continue
                    }
                    
                    let openTradeKey = "ctrader_open_\(posId)"
                    activePosKeys.insert(openTradeKey)
                    
                    let sName = symbolMap[sId] ?? "Symbol_\(sId)"
                    let sideStr = String(describing: tradeData["tradeSide"] ?? pos["tradeSide"] ?? "BUY").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let dir: TradeDirection = (sideStr == "SELL" || sideStr == "2") ? .short : .long
                    let openTs = safeInt64(tradeData["openTimestamp"]) ?? safeInt64(pos["openTimestamp"]) ?? nowMs
                    let openDate = Date(timeIntervalSince1970: Double(openTs) / 1000.0)
                    
                    let isMetals = sName.contains("XAU") || sName.contains("XAG")
                    let isForex = sName.count == 6 && !sName.contains("BTC") && !sName.contains("ETH")
                    let lotDivisor: Decimal = isMetals ? 1_000_000 : (isForex ? 10_000_000 : 100)
                    let qty = max(Decimal(0.01), Decimal(vol) / lotDivisor)
                    
                    let stopLossVal = safeDouble(pos["stopLoss"]) ?? safeDouble(tradeData["stopLoss"])
                    let takeProfitVal = safeDouble(pos["takeProfit"]) ?? safeDouble(tradeData["takeProfit"])
                    
                    if let existingIdx = dataStore.trades.firstIndex(where: { $0.key == openTradeKey }) {
                        var existing = dataStore.trades[existingIdx]
                        existing.openQuantity = qty
                        existing.quantity = qty
                        existing.avgEntry = Decimal(price)
                        if let sl = stopLossVal { existing.stopLoss = Decimal(sl) }
                        if let tp = takeProfitVal { existing.profitTarget = Decimal(tp) }
                        dataStore.trades[existingIdx] = existing
                    } else {
                        // Check if TradeReconstructionEngine already has an open trade for this position
                        let alreadyHasOpenTrade = dataStore.trades.contains { t in
                            t.accountId == journalAccId &&
                            t.status == .open &&
                            t.symbol == sName &&
                            t.direction == dir &&
                            abs(t.openQuantity - qty) < Decimal(0.01)
                        }
                        
                        if !alreadyHasOpenTrade {
                            let openTrade = Trade(
                                key: openTradeKey,
                                accountId: journalAccId,
                                symbol: sName,
                                assetClass: isForex ? "forex" : (isMetals ? "commodity" : "cfd"),
                                direction: dir,
                                status: .open,
                                openedAt: openDate,
                                closedAt: nil,
                                quantity: qty,
                                openQuantity: qty,
                                avgEntry: Decimal(price),
                                avgExit: nil,
                                grossPnl: 0,
                                fees: 0,
                                netPnl: 0,
                                executionCount: 1,
                                executionIds: [],
                                notes: "Open position synced from cTrader (Position #\(posId))",
                                tags: ["ctrader", "open"],
                                stopLoss: stopLossVal.map { Decimal($0) },
                                profitTarget: takeProfitVal.map { Decimal($0) }
                            )
                            dataStore.trades.append(openTrade)
                        }
                    }
                }
                
                // Clean up closed positions that were previously tracked under ctrader_open_*
                dataStore.trades.removeAll { trade in
                    trade.accountId == journalAccId &&
                    trade.key.hasPrefix("ctrader_open_") &&
                    !activePosKeys.contains(trade.key)
                }
            }
            
            dataStore.rebuildAccount(accountId: journalAccId)
            totalRebuiltTrades += dataStore.trades.filter { $0.accountId == journalAccId }.count
            
            if dataStore.selectedAccountId == "default-acc" || dataStore.selectedAccountId.isEmpty {
                dataStore.selectedAccountId = journalAccId
            }
        }
        
        dataStore.deduplicateAndCleanAccounts()
        dataStore.rebuildAllAccounts()
        dataStore.saveToDisk(immediate: true)
        dataStore.invalidatePerformanceCaches()
        dataStore.objectWillChange.send()
        
        let now = Date()
        self.lastSyncDate = now
        let summaryMsg = "cTrader synchronized: \(activeAccounts.count) account(s), \(totalDeals) executions imported, \(totalRebuiltTrades) trades updated."
        self.lastStatus = summaryMsg
        
        // Background push to Supabase if Supabase is configured
        if SupabaseService.shared.isConfigured {
            Task {
                await dataStore.syncWithSupabase(isBackground: true)
            }
        }
        
        return CTraderSyncSummary(
            accountsSynced: activeAccounts.count,
            dealsImported: totalDeals,
            tradesRebuilt: totalRebuiltTrades,
            message: summaryMsg
        )
    }
    
    // MARK: - Safe Parsing Helpers
    
    private func safeInt64(_ val: Any?) -> Int64? {
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
    
    private func safeDouble(_ val: Any?) -> Double? {
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
