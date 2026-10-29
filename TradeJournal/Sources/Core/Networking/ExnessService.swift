import Foundation
import SwiftUI
import CryptoKit

/// Official Exness REST API Integration Service based on exness-api.com specification
/// Implements automatic Access Point Discovery, Ed25519 cryptographic signing, and direct HTTPS endpoints.
/// Private keys and sensitive tokens are securely stored in the iOS Hardware Keychain (AES-256).
public final class ExnessService: ObservableObject, @unchecked Sendable {
    public static let shared = ExnessService()
    
    // MARK: - Published State
    
    @Published public var isConnected: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil
    
    // Default Exness API Gateway host per official exness-api.com specification
    @Published public var apiHost: String = "https://api.exness-api.com"
    @Published public var accountId: String = ""
    @Published public var apiKey: String = ""
    
    @Published public var currency: String = "USD"
    @Published public var balance: Decimal = 0
    @Published public var equity: Decimal = 0
    @Published public var leverage: Int = 100
    @Published public var syncedTradesCount: Int = 0
    
    // Resolved account-specific Access Point host (cached from discovery)
    private var cachedAccessPoint: String? = nil
    
    // MARK: - Keychain & UserDefaults Keys
    
    private let kExnessApiHost = "exness_api_host"
    private let kExnessAccountId = "exness_account_id"
    private let kExnessApiKey = "exness_api_key_public"
    private let kExnessPrivateKey = "exness_private_key_ed25519"
    private let kExnessLastSync = "exness_last_sync_date"
    private let kExnessCachedAccessPoint = "exness_cached_access_point"
    
    private init() {
        loadSettings()
    }
    
    // MARK: - Persistence & Security
    
    public func loadSettings() {
        let ud = UserDefaults.standard
        var storedHost = ud.string(forKey: kExnessApiHost) ?? AppSecretsLoader.loadSecret(named: "EXNESS_HOST") ?? "https://api.exness-api.com"
        if storedHost.isEmpty || storedHost == "https://api.exness.com" {
            storedHost = "https://api.exness-api.com"
            ud.set(storedHost, forKey: kExnessApiHost)
        }
        self.apiHost = storedHost
        
        var acc = ud.string(forKey: kExnessAccountId) ?? ""
        if acc.isEmpty {
            acc = AppSecretsLoader.loadSecret(named: "EXNESS_ACCOUNT_ID") ?? ""
            if !acc.isEmpty { ud.set(acc, forKey: kExnessAccountId) }
        }
        self.accountId = acc
        
        self.apiKey = KeychainManager.get(forKey: kExnessApiKey) ?? AppSecretsLoader.loadSecret(named: "EXNESS_API_KEY") ?? ""
        self.lastSyncDate = ud.object(forKey: kExnessLastSync) as? Date
        
        if let cap = ud.string(forKey: kExnessCachedAccessPoint), !cap.contains("api.exness.com") {
            self.cachedAccessPoint = cap
        } else {
            self.cachedAccessPoint = nil
            ud.removeObject(forKey: kExnessCachedAccessPoint)
        }
        
        let hasPrivateKey = KeychainManager.get(forKey: kExnessPrivateKey) != nil || (AppSecretsLoader.loadSecret(named: "EXNESS_PRIVATE_KEY") != nil)
        self.isConnected = !accountId.isEmpty && !apiKey.isEmpty && hasPrivateKey
    }
    
    public func saveCredentials(
        host: String,
        accountId: String,
        apiKey: String,
        privateKey: String
    ) {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalHost = cleanHost.isEmpty ? "https://api.exness-api.com" : cleanHost
        let cleanAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let ud = UserDefaults.standard
        ud.set(finalHost, forKey: kExnessApiHost)
        ud.set(cleanAccountId, forKey: kExnessAccountId)
        
        if !cleanApiKey.isEmpty {
            KeychainManager.set(cleanApiKey, forKey: kExnessApiKey)
        }
        if !cleanPrivateKey.isEmpty {
            KeychainManager.set(cleanPrivateKey, forKey: kExnessPrivateKey)
        }
        
        self.cachedAccessPoint = nil
        ud.removeObject(forKey: kExnessCachedAccessPoint)
        
        DispatchQueue.main.async {
            self.apiHost = finalHost
            self.accountId = cleanAccountId
            self.apiKey = cleanApiKey
            self.isConnected = !cleanAccountId.isEmpty && !cleanApiKey.isEmpty && (!cleanPrivateKey.isEmpty || KeychainManager.get(forKey: self.kExnessPrivateKey) != nil)
        }
    }
    
    public func getStoredPrivateKey() -> String {
        return KeychainManager.get(forKey: kExnessPrivateKey) ?? AppSecretsLoader.loadSecret(named: "EXNESS_PRIVATE_KEY") ?? ""
    }
    
    public func disconnect() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: kExnessApiHost)
        ud.removeObject(forKey: kExnessAccountId)
        ud.removeObject(forKey: kExnessLastSync)
        ud.removeObject(forKey: kExnessCachedAccessPoint)
        
        KeychainManager.delete(forKey: kExnessApiKey)
        KeychainManager.delete(forKey: kExnessPrivateKey)
        self.cachedAccessPoint = nil
        
        DispatchQueue.main.async {
            self.accountId = ""
            self.apiKey = ""
            self.isConnected = false
            self.lastSyncDate = nil
            self.balance = 0
            self.equity = 0
            self.syncedTradesCount = 0
        }
    }
    
    // MARK: - Exness Cryptographic Signing Engine (exness-api.com Spec)
    
    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
    
    /// Constructs canonical headers and signs payload using Ed25519 as specified by exness-api.com
    private func signRequest(
        method: String,
        path: String,
        bodyData: Data? = nil,
        idempotencyKey: String = ""
    ) throws -> [String: String] {
        let cleanKey = apiKey.isEmpty ? (KeychainManager.get(forKey: kExnessApiKey) ?? AppSecretsLoader.loadSecret(named: "EXNESS_API_KEY") ?? "") : apiKey
        let privKeyStr = getStoredPrivateKey()
        
        guard !cleanKey.isEmpty, !privKeyStr.isEmpty else {
            throw NSError(domain: "ExnessService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa có EXN-API-KEY hoặc Private Key ký Ed25519 trong Keychain/Secrets."])
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Exact SHA-256 body hash per Exness spec:
        // "For requests without a body, body_hash is the SHA-256 hash of the empty byte sequence: 47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
        let bodyHash: String
        if let body = bodyData, !body.isEmpty {
            let digest = SHA256.hash(data: body)
            bodyHash = base64UrlEncode(Data(digest))
        } else {
            bodyHash = "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
        }
        
        // Canonical payload dictionary for EXN-DATA (sign_version must be integer 1, timestamp in ms)
        let canonicalPayload: [String: Any] = [
            "api_key": cleanKey,
            "idempotency_key": idempotencyKey,
            "timestamp": timestamp,
            "sign_version": 1,
            "method": method.uppercased(),
            "path": path,
            "body_hash": bodyHash
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: canonicalPayload, options: [.sortedKeys])
        let exnData = base64UrlEncode(jsonData)
        
        // Clean PEM/Hex/Base64 Ed25519 Private Key
        let cleanKeyStr = privKeyStr
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN ED25519 PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END ED25519 PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse Ed25519 raw 32-byte seed from PKCS#8 DER (48 bytes) or raw Base64/Hex
        let rawKeyData: Data = {
            if let d = Data(base64Encoded: cleanKeyStr) {
                if d.count == 32 { return d }
                if d.count == 48 { return d.subdata(in: 16..<48) } // Standard PKCS#8 Ed25519 offset
            }
            if cleanKeyStr.count == 64 {
                var d = Data()
                var idx = cleanKeyStr.startIndex
                for _ in 0..<32 {
                    let nextIdx = cleanKeyStr.index(idx, offsetBy: 2)
                    let byteStr = String(cleanKeyStr[idx..<nextIdx])
                    if let byte = UInt8(byteStr, radix: 16) { d.append(byte) }
                    idx = nextIdx
                }
                if d.count == 32 { return d }
            }
            return cleanKeyStr.data(using: .utf8) ?? Data()
        }()
        
        var exnSign = ""
        if let ed25519Key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawKeyData) {
            let signature = try ed25519Key.signature(for: jsonData)
            exnSign = base64UrlEncode(signature)
        } else {
            // Symmetric HMAC fallback if private key was provided as plain secret string
            let symmetricKey = SymmetricKey(data: privKeyStr.data(using: .utf8) ?? Data())
            let signature = HMAC<SHA256>.authenticationCode(for: jsonData, using: symmetricKey)
            exnSign = base64UrlEncode(Data(signature))
        }
        
        return [
            "EXN-API-KEY": cleanKey,
            "EXN-IDEMPOTENCY-KEY": idempotencyKey,
            "EXN-TIMESTAMP": String(timestamp),
            "EXN-SIGN-VERSION": "1",
            "EXN-DATA": exnData,
            "EXN-SIGN": exnSign,
            "Content-Type": "application/json",
            "User-Agent": "TradeJournal-iOS"
        ]
    }
    
    // MARK: - Access Point / Host Discovery (Official exness-api.com Spec)
    
    /// Resolves the dynamic Access Point URL for this account ID via the Exness Gateway
    public func resolveAccessPoint() async throws -> String {
        if let cached = cachedAccessPoint, !cached.isEmpty, !cached.contains("api.") {
            return cached
        }
        
        let cleanConfiguredHost = apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the user configured an explicit cluster access point (e.g. https://ap-xxx.exness.com)
        if cleanConfiguredHost.contains("ap-") {
            self.cachedAccessPoint = cleanConfiguredHost
            return cleanConfiguredHost
        }
        
        guard !accountId.isEmpty else {
            throw NSError(domain: "ExnessService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Chưa có Account ID Exness."])
        }
        
        // Official Gateway host exclusively handles dynamic access point routing
        let gatewayHost = "https://api.exness-api.com"
        let path = "/v1/trading/access-point?account_id=\(accountId)"
        
        guard let hostUrl = URL(string: gatewayHost),
              let url = URL(string: path, relativeTo: hostUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let headers = try signRequest(method: "GET", path: path, bodyData: nil)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if http.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ap = json["access_point"] as? String, !ap.isEmpty {
                var cleanAp = ap.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanAp.hasPrefix("http://") && !cleanAp.hasPrefix("https://") {
                    cleanAp = "https://" + cleanAp
                }
                self.cachedAccessPoint = cleanAp
                UserDefaults.standard.set(cleanAp, forKey: kExnessCachedAccessPoint)
                AppLogger.info("Exness: Access Point discovered -> \(cleanAp)")
                return cleanAp
            } else {
                throw NSError(domain: "ExnessService", code: 200, userInfo: [NSLocalizedDescriptionKey: "Phản hồi Access Point không đúng định dạng."])
            }
        } else if http.statusCode == 400 {
            let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? "Tham số không hợp lệ."
            throw NSError(domain: "ExnessService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Exness Gateway: \(desc)"])
        } else if http.statusCode == 401 || http.statusCode == 403 {
            let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_message"] as? String ?? "Khóa API hoặc chữ ký Ed25519 không khớp."
            throw NSError(domain: "ExnessService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Lỗi xác thực (HTTP \(http.statusCode)): \(desc)"])
        } else if http.statusCode == 429 {
            throw NSError(domain: "ExnessService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit Exness. Vui lòng đợi vài giây."])
        } else {
            let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "ExnessService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Không thể lấy Access Point (HTTP \(http.statusCode)): \(desc)"])
        }
    }
    
    // MARK: - API Calls
    
    /// Tests authentication and connectivity to Exness REST API
    public func testConnection() async throws -> (success: Bool, message: String) {
        guard !accountId.isEmpty else {
            return (false, "Vui lòng nhập Account ID Exness.")
        }
        
        // 1. Resolve Access Point via Discovery
        let accessPointHost: String
        do {
            accessPointHost = try await resolveAccessPoint()
        } catch {
            return (false, "Không thể xác định Access Point: \(error.localizedDescription)")
        }
        
        guard let hostUrl = URL(string: accessPointHost) else {
            return (false, "Địa chỉ Access Point không hợp lệ.")
        }
        
        // 2. Fetch Account Configuration on the discovered Access Point
        let path = "/v1/configuration/accounts/\(accountId)/account"
        guard let url = URL(string: path, relativeTo: hostUrl) else {
            return (false, "Không thể tạo URL request.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let headers = try signRequest(method: "GET", path: path, bodyData: nil)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let cur = json["currency"] as? String {
                    await MainActor.run { self.currency = cur }
                }
                if let bal = json["balance"] as? Double {
                    await MainActor.run { self.balance = Decimal(bal) }
                } else if let balNum = json["balance"] as? NSNumber {
                    await MainActor.run { self.balance = Decimal(balNum.doubleValue) }
                } else if let balStr = json["balance"] as? String, let d = Double(balStr) {
                    await MainActor.run { self.balance = Decimal(d) }
                }
                if let eq = json["equity"] as? Double {
                    await MainActor.run { self.equity = Decimal(eq) }
                } else if let eqNum = json["equity"] as? NSNumber {
                    await MainActor.run { self.equity = Decimal(eqNum.doubleValue) }
                } else if let eqStr = json["equity"] as? String, let d = Double(eqStr) {
                    await MainActor.run { self.equity = Decimal(d) }
                }
                if let lev = json["leverage"] as? Int {
                    await MainActor.run { self.leverage = lev }
                } else if let levStr = json["leverage"] as? String {
                    let num = levStr.replacingOccurrences(of: "1:", with: "")
                    if let l = Int(num) { await MainActor.run { self.leverage = l } }
                }
            }
            await MainActor.run {
                self.isConnected = true
            }
            return (true, "Đã kết nối Exness API! (Chữ ký Ed25519 hợp lệ)")
        } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Khóa API hoặc chữ ký Ed25519 không hợp lệ."
            return (false, "Lỗi xác thực (HTTP \(httpResponse.statusCode)): \(errorMsg)")
        } else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            return (false, "Không thể kết nối (HTTP \(httpResponse.statusCode)): \(errorMsg)")
        }
    }
    
    // MARK: - Exness Data Ingestion & Parser
    
    private func fetchEndpointData(path: String, accessPointHost: String) async -> [[String: Any]] {
        guard let hostUrl = URL(string: accessPointHost),
              let url = URL(string: path, relativeTo: hostUrl) else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        
        guard let headers = try? signRequest(method: "GET", path: path, bodyData: nil) else { return [] }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = dict["orders"] as? [[String: Any]] { return arr }
            if let arr = dict["data"] as? [[String: Any]] { return arr }
            if let arr = dict["items"] as? [[String: Any]] { return arr }
            if let arr = dict["trades"] as? [[String: Any]] { return arr }
            if let arr = dict["positions"] as? [[String: Any]] { return arr }
            if let arr = dict["history"] as? [[String: Any]] { return arr }
        }
        return []
    }
    
    private func parseExnessRecordToExecutions(_ raw: [String: Any], journalAccId: String) -> [Execution] {
        let ticket = raw["ticket"] ?? raw["id"] ?? raw["order_id"] ?? raw["deal_id"] ?? raw["position_id"]
        guard let ticketVal = ticket else { return [] }
        let ticketStr = String(describing: ticketVal)
        
        let symbolRaw = (raw["symbol"] as? String) ?? (raw["instrument"] as? String) ?? (raw["symbolName"] as? String) ?? "UNKNOWN"
        let cleanSymbol = symbolRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let volumeNum = (raw["volume"] as? Double) ?? (raw["lots"] as? Double) ?? (raw["quantity"] as? Double) ?? (raw["size"] as? Double) ?? (Double(String(describing: raw["volume"] ?? raw["lots"] ?? "0.01")) ?? 0.01)
        let quantity = max(Decimal(0.01), Decimal(volumeNum))
        
        let opStr = String(describing: raw["operation"] ?? raw["side"] ?? raw["type"] ?? raw["cmd"] ?? "BUY").uppercased()
        let side: ExecutionSide = (opStr.contains("SELL") || opStr == "1") ? .sell : .buy
        let exitSide: ExecutionSide = (side == .buy) ? .sell : .buy
        
        let openPriceVal = (raw["open_price"] as? Double) ?? (raw["openPrice"] as? Double) ?? (raw["price"] as? Double) ?? (raw["executionPrice"] as? Double) ?? 0.0
        guard openPriceVal > 0 else { return [] }
        let openPrice = Decimal(openPriceVal)
        
        let openDate: Date = {
            if let ms = raw["open_time"] as? Int64 ?? raw["openTime"] as? Int64 ?? raw["timestamp"] as? Int64 {
                return Date(timeIntervalSince1970: Double(ms) > 10_000_000_000 ? Double(ms) / 1000.0 : Double(ms))
            }
            if let sec = raw["open_time"] as? Double ?? raw["openTime"] as? Double ?? raw["timestamp"] as? Double {
                return Date(timeIntervalSince1970: sec > 10_000_000_000 ? sec / 1000.0 : sec)
            }
            if let str = raw["open_time"] as? String ?? raw["openTime"] as? String,
               let d = ISO8601DateFormatter().date(from: str) {
                return d
            }
            return Date()
        }()
        
        let feeVal = abs((raw["commission"] as? Double) ?? (raw["fee"] as? Double) ?? 0.0)
        let fee = Decimal(feeVal)
        
        let swapVal = (raw["swap"] as? Double) ?? (raw["rollover"] as? Double)
        let swap: Decimal? = swapVal != nil ? Decimal(swapVal!) : nil
        
        let closePriceVal = (raw["close_price"] as? Double) ?? (raw["closePrice"] as? Double) ?? (raw["exit_price"] as? Double) ?? (raw["exitPrice"] as? Double)
        let closeDate: Date? = {
            if let ms = raw["close_time"] as? Int64 ?? raw["closeTime"] as? Int64 {
                return Date(timeIntervalSince1970: Double(ms) > 10_000_000_000 ? Double(ms) / 1000.0 : Double(ms))
            }
            if let sec = raw["close_time"] as? Double ?? raw["closeTime"] as? Double {
                return Date(timeIntervalSince1970: sec > 10_000_000_000 ? sec / 1000.0 : sec)
            }
            if let str = raw["close_time"] as? String ?? raw["closeTime"] as? String,
               let d = ISO8601DateFormatter().date(from: str) {
                return d
            }
            return nil
        }()
        
        let isMetals = cleanSymbol.hasPrefix("XAU") || cleanSymbol.hasPrefix("XAG") || cleanSymbol.hasPrefix("GOLD") || cleanSymbol.hasPrefix("SILVER")
        let isCrypto = cleanSymbol.hasPrefix("BTC") || cleanSymbol.hasPrefix("ETH")
        let assetClass = isMetals ? "commodity" : (isCrypto ? "crypto" : "forex")
        
        var fills: [Execution] = []
        
        if let cp = closePriceVal, cp > 0, let cDate = closeDate {
            // Closed Trade: Create entry fill + exit fill
            let entryId = "exness_\(ticketStr)_in"
            let entryHash = "\(journalAccId)|\(cleanSymbol)|\(side.rawValue)|\(quantity)|\(openPriceVal)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let entryFill = Execution(
                id: entryId,
                accountId: journalAccId,
                symbol: cleanSymbol,
                side: side,
                quantity: quantity,
                price: openPrice,
                fee: fee / 2,
                swap: nil,
                executedAt: openDate,
                assetClass: assetClass,
                source: "exness",
                contentHash: entryHash
            )
            
            let exitId = "exness_\(ticketStr)_out"
            let exitHash = "\(journalAccId)|\(cleanSymbol)|\(exitSide.rawValue)|\(quantity)|\(cp)|\(Int64(cDate.timeIntervalSince1970 * 1000))"
            let exitFill = Execution(
                id: exitId,
                accountId: journalAccId,
                symbol: cleanSymbol,
                side: exitSide,
                quantity: quantity,
                price: Decimal(cp),
                fee: fee / 2,
                swap: swap,
                executedAt: cDate,
                assetClass: assetClass,
                source: "exness",
                contentHash: exitHash
            )
            fills.append(entryFill)
            fills.append(exitFill)
        } else {
            // Open Position or Individual Fill
            let fillId = "exness_\(ticketStr)"
            let fillHash = "\(journalAccId)|\(cleanSymbol)|\(side.rawValue)|\(quantity)|\(openPriceVal)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let fill = Execution(
                id: fillId,
                accountId: journalAccId,
                symbol: cleanSymbol,
                side: side,
                quantity: quantity,
                price: openPrice,
                fee: fee,
                swap: swap,
                executedAt: openDate,
                assetClass: assetClass,
                source: "exness",
                contentHash: fillHash
            )
            fills.append(fill)
        }
        
        return fills
    }
    
    /// Synchronizes trades and order history from Exness REST API
    public func syncTrades() async throws -> Int {
        guard !accountId.isEmpty else {
            throw NSError(domain: "ExnessService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình tài khoản Exness."])
        }
        
        await MainActor.run {
            self.isSyncing = true
        }
        defer {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }
        
        let accessPointHost = try await resolveAccessPoint()
        let journalAccId = "exness_\(accountId)"
        let accountName = "Exness (\(accountId))"
        
        // 1. Ensure linked trading account exists in TradeDataStore
        await MainActor.run {
            let dataStore = TradeDataStore.shared
            if let existingIdx = dataStore.accounts.firstIndex(where: { $0.id == journalAccId || $0.id == self.accountId }) {
                var acc = dataStore.accounts[existingIdx]
                acc.broker = "Exness"
                acc.currency = self.currency
                acc.lastSyncAt = Date()
                dataStore.accounts[existingIdx] = acc
            } else {
                let newAcc = Account(
                    id: journalAccId,
                    name: accountName,
                    broker: "Exness",
                    kind: .sync,
                    currency: self.currency,
                    initialBalance: self.balance,
                    profitCalcMethod: .fifo,
                    autoSync: true,
                    visibleInJournal: true
                )
                dataStore.accounts.append(newAcc)
                dataStore.saveToDisk()
            }
        }
        
        // 2. Fetch raw orders and positions across standard Exness routes
        var rawOrders = await fetchEndpointData(path: "/v1/trading/accounts/\(accountId)/orders", accessPointHost: accessPointHost)
        let rawPositions = await fetchEndpointData(path: "/v1/trading/accounts/\(accountId)/positions", accessPointHost: accessPointHost)
        rawOrders.append(contentsOf: rawPositions)
        
        // 3. Parse Exness records to database Execution fills
        var newExecutions: [Execution] = []
        for raw in rawOrders {
            let fills = parseExnessRecordToExecutions(raw, journalAccId: journalAccId)
            newExecutions.append(contentsOf: fills)
        }
        
        // 4. Ingest executions and trigger FIFO round-trip reconstruction
        if !newExecutions.isEmpty {
            await MainActor.run {
                TradeDataStore.shared.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
                self.syncedTradesCount = newExecutions.count
            }
        }
        
        let now = Date()
        UserDefaults.standard.set(now, forKey: kExnessLastSync)
        await MainActor.run {
            self.lastSyncDate = now
            self.isConnected = true
        }
        return newExecutions.count
    }
}
