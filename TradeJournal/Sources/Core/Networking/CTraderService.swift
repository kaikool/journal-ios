import Foundation
import Combine

/// Represents an authorized cTrader trading account retrieved from the cTrader Open API.
public struct CTraderAccount: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let ctidTraderAccountId: Int64
    public var id: Int64 { ctidTraderAccountId }
    public let traderLogin: Int64
    public let isLive: Bool
    public let brokerTitleShort: String
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
        
        let clientMsgId = json["clientMsgId"] as? String ?? ""
        let payloadType = json["payloadType"] as? Int ?? 0
        let payload = json["payload"] as? [String: Any] ?? [:]
        
        // Handle error responses (2142: ProtoOAErrorRes)
        if payloadType == 2142 {
            let errorCode = payload["errorCode"] as? String ?? "UNKNOWN_ERROR"
            let desc = payload["description"] as? String ?? "An error occurred with cTrader Open API."
            let error = NSError(domain: "cTrader", code: payloadType, userInfo: [NSLocalizedDescriptionKey: "\(errorCode): \(desc)"])
            
            if let cont = pendingContinuations.removeValue(forKey: clientMsgId) {
                cont.resume(throwing: error)
            }
            return
        }
        
        if let cont = pendingContinuations.removeValue(forKey: clientMsgId) {
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
        _ = try await sendRequest(
            payloadType: 2100,
            payload: [
                "clientId": cleanId,
                "clientSecret": cleanSecret
            ]
        )
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
        
        guard let rawAccounts = res["ctidTraderAccount"] as? [[String: Any]] else {
            self.discoveredAccounts = []
            return []
        }
        
        var accounts: [CTraderAccount] = []
        for raw in rawAccounts {
            let accId = (raw["ctidTraderAccountId"] as? NSNumber)?.int64Value ?? 0
            guard accId > 0 else { continue }
            let login = (raw["traderLogin"] as? NSNumber)?.int64Value ?? accId
            let isLive = raw["isLive"] as? Bool ?? true
            let broker = raw["brokerTitleShort"] as? String ?? (isLive ? "cTrader Live" : "cTrader Demo")
            
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
                
                if let trader = traderRes["trader"] as? [String: Any] {
                    let balanceRaw = (trader["balance"] as? NSNumber)?.int64Value ?? 0
                    let moneyDigits = trader["moneyDigits"] as? Int ?? 2
                    let divisor = pow(10.0, Double(moneyDigits))
                    let balDecimal = Decimal(Double(balanceRaw) / divisor)
                    let leverage = (trader["leverageInCents"] as? Int).map { $0 / 100 } ?? 100
                    
                    accounts[idx].balance = balDecimal
                    accounts[idx].leverage = leverage
                    
                    // Lookup deposit currency from asset list
                    if let assetListRes = try? await sendRequest(payloadType: 2112, payload: ["ctidTraderAccountId": accId]),
                       let assets = assetListRes["asset"] as? [[String: Any]],
                       let depId = (trader["depositAssetId"] as? NSNumber)?.int64Value,
                       let matched = assets.first(where: { ((($0["assetId"] as? NSNumber)?.int64Value) ?? 0) == depId }),
                       let ccy = matched["name"] as? String {
                        accounts[idx].currency = ccy
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
            let accountName = "cTrader \(account.traderLogin) (\(safeBroker))"
            
            if let existingIdx = dataStore.accounts.firstIndex(where: {
                $0.id == journalAccId ||
                $0.id.isEquivalentAccountId(to: journalAccId) ||
                $0.id.cleanAccountId == String(account.ctidTraderAccountId) ||
                $0.id.cleanAccountId == String(account.traderLogin) ||
                $0.name.contains("\(account.traderLogin)")
            }) {
                var acc = dataStore.accounts[existingIdx]
                acc.currency = account.currency
                acc.kind = .sync
                acc.broker = safeBroker
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
            _ = try await sendRequest(
                payloadType: 2102,
                payload: ["ctidTraderAccountId": accId, "accessToken": cleanToken]
            )
            
            // 2. Fetch Symbol Dictionary
            var symbolMap: [Int64: String] = [:]
            if let symbolsRes = try? await sendRequest(payloadType: 2114, payload: ["ctidTraderAccountId": accId, "includeArchivedSymbols": false]),
               let symbolArray = symbolsRes["symbol"] as? [[String: Any]] {
                for s in symbolArray {
                    if let sId = (s["symbolId"] as? NSNumber)?.int64Value,
                       let sName = s["symbolName"] as? String {
                        symbolMap[sId] = sName
                    }
                }
            }
            
            // 3. Fetch Historical Deals (Completed executions)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let dealsFrom = fromTimestamp ?? 0
            let dealsTo = toTimestamp ?? nowMs
            let dealsRes = try await sendRequest(
                payloadType: 2133,
                payload: [
                    "ctidTraderAccountId": accId,
                    "fromTimestamp": dealsFrom,
                    "toTimestamp": dealsTo,
                    "maxRows": 2000
                ]
            )
            
            let rawDeals = dealsRes["deal"] as? [[String: Any]] ?? []
            
            // 4. Ensure Journal Account exists
            let journalAccId = "ctrader_\(accId)"
            if let existingIdx = dataStore.accounts.firstIndex(where: { $0.id == journalAccId || $0.name.contains("\(account.traderLogin)") }) {
                var acc = dataStore.accounts[existingIdx]
                acc.currency = account.currency
                acc.kind = .sync
                acc.autoSync = true
                dataStore.accounts[existingIdx] = acc
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: "cTrader \(account.traderLogin) (\(account.brokerTitleShort))",
                    broker: "cTrader",
                    kind: .sync,
                    currency: account.currency,
                    initialBalance: account.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true
                )
                dataStore.accounts.append(newAcc)
                dataStore.saveToDisk()
            }
            
            // 5. Convert Deals to Atomic Executions
            var newExecutions: [Execution] = []
            for raw in rawDeals {
                guard let dealId = (raw["dealId"] as? NSNumber)?.int64Value,
                      let symbolId = (raw["symbolId"] as? NSNumber)?.int64Value,
                      let filledVolume = (raw["filledVolume"] as? NSNumber)?.int64Value,
                      let executionPrice = raw["executionPrice"] as? Double,
                      let execTimestamp = (raw["executionTimestamp"] as? NSNumber)?.int64Value else {
                    continue
                }
                
                let symbolName = symbolMap[symbolId] ?? "Symbol_\(symbolId)"
                let sideStr = String(describing: raw["tradeSide"] ?? "BUY").uppercased()
                let side: ExecutionSide = (sideStr == "SELL" || sideStr == "2") ? .sell : .buy
                
                // Volume conversion: Standard forex lots (10,000,000 cents = 1.0 lot) or contracts
                let isForexOrMetals = symbolName.count == 6 || symbolName.contains("XAU") || symbolName.contains("XAG")
                let lotDivisor: Decimal = isForexOrMetals ? 10_000_000 : 100
                let quantity = max(Decimal(0.01), Decimal(filledVolume) / lotDivisor)
                
                let moneyDigits = raw["moneyDigits"] as? Int ?? 2
                let moneyDivisor = pow(10.0, Double(moneyDigits))
                let commRaw = (raw["commission"] as? NSNumber)?.doubleValue ?? 0
                let fee = Decimal(abs(commRaw) / moneyDivisor)
                
                let execDate = Date(timeIntervalSince1970: Double(execTimestamp) / 1000.0)
                let fillId = "ctrader_deal_\(dealId)"
                let hash = "\(journalAccId)|\(symbolName)|\(side.rawValue)|\(quantity)|\(executionPrice)|\(execTimestamp)"
                
                let exec = Execution(
                    id: fillId,
                    accountId: journalAccId,
                    symbol: symbolName,
                    side: side,
                    quantity: quantity,
                    price: Decimal(executionPrice),
                    fee: fee,
                    executedAt: execDate,
                    assetClass: isForexOrMetals ? "forex" : "cfd",
                    source: "sync",
                    contentHash: hash
                )
                newExecutions.append(exec)
            }
            
            // 6. Ingest executions and rebuild round trips
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
                totalDeals += newExecutions.count
            }
            
            // 7. Check for open positions via Reconcile
            if let reconcileRes = try? await sendRequest(payloadType: 2124, payload: ["ctidTraderAccountId": accId]),
               let positions = reconcileRes["position"] as? [[String: Any]] {
                for pos in positions {
                    guard let posId = (pos["positionId"] as? NSNumber)?.int64Value,
                          let tradeData = pos["tradeData"] as? [String: Any],
                          let sId = (tradeData["symbolId"] as? NSNumber)?.int64Value,
                          let vol = (tradeData["volume"] as? NSNumber)?.int64Value,
                          let price = pos["price"] as? Double else {
                        continue
                    }
                    
                    let sName = symbolMap[sId] ?? "Symbol_\(sId)"
                    let sideStr = String(describing: tradeData["tradeSide"] ?? "BUY").uppercased()
                    let dir: TradeDirection = (sideStr == "SELL" || sideStr == "2") ? .short : .long
                    let openTs = (tradeData["openTimestamp"] as? NSNumber)?.int64Value ?? nowMs
                    let openDate = Date(timeIntervalSince1970: Double(openTs) / 1000.0)
                    
                    let isForexOrMetals = sName.count == 6 || sName.contains("XAU") || sName.contains("XAG")
                    let lotDivisor: Decimal = isForexOrMetals ? 10_000_000 : 100
                    let qty = max(Decimal(0.01), Decimal(vol) / lotDivisor)
                    
                    let openTradeKey = "ctrader_open_\(posId)"
                    if let existingIdx = dataStore.trades.firstIndex(where: { $0.key == openTradeKey }) {
                        var existing = dataStore.trades[existingIdx]
                        existing.openQuantity = qty
                        existing.avgEntry = Decimal(price)
                        dataStore.trades[existingIdx] = existing
                    } else {
                        let openTrade = Trade(
                            key: openTradeKey,
                            accountId: journalAccId,
                            symbol: sName,
                            assetClass: isForexOrMetals ? "forex" : "cfd",
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
                            tags: ["ctrader", "open"]
                        )
                        dataStore.trades.append(openTrade)
                    }
                }
            }
            
            totalRebuiltTrades += dataStore.trades.filter { $0.accountId == journalAccId }.count
        }
        
        dataStore.deduplicateAndCleanAccounts()
        dataStore.saveToDisk(immediate: true)
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
}
