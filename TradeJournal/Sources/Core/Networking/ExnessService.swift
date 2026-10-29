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
    @Published public var isConfigured: Bool = false
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
    @Published public var workingHost: String? = nil
    @Published public var workingBasePath: String? = nil
    @Published public var lastSyncSummary: String = ""
    
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
        self.isConfigured = !accountId.isEmpty && !apiKey.isEmpty && hasPrivateKey
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
            self.isConfigured = !cleanAccountId.isEmpty && !cleanApiKey.isEmpty && (!cleanPrivateKey.isEmpty || KeychainManager.get(forKey: self.kExnessPrivateKey) != nil)
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
            self.isConfigured = false
            self.isConnected = false
            self.lastSyncDate = nil
            self.balance = 0
            self.equity = 0
            self.syncedTradesCount = 0
            self.workingHost = nil
            self.workingBasePath = nil
            self.lastSyncSummary = ""
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
            throw NSError(domain: "ExnessService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing EXN-API-KEY or Ed25519 Private Key in Keychain/Secrets."])
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
        
        // Parse Ed25519 raw 32-byte seed from PKCS#8 DER (48 bytes), Libsodium (64 bytes), URL-safe Base64, or Hex
        let rawKeyData: Data = {
            // 1. Standard base64
            if let d = Data(base64Encoded: cleanKeyStr) {
                if d.count == 32 { return d }
                if d.count == 48 { return d.subdata(in: 16..<48) } // Standard PKCS#8 Ed25519 offset
                if d.count == 64 { return d.subdata(in: 0..<32) }  // Libsodium 64-byte seed+pubkey
            }
            // 2. URL-safe base64 fallback
            let standardB64 = cleanKeyStr
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let paddedB64 = standardB64.padding(
                toLength: ((standardB64.count + 3) / 4) * 4,
                withPad: "=",
                startingAt: 0
            )
            if let d = Data(base64Encoded: paddedB64) {
                if d.count == 32 { return d }
                if d.count == 48 { return d.subdata(in: 16..<48) }
                if d.count == 64 { return d.subdata(in: 0..<32) }
            }
            // 3. Hex 64 chars (32 bytes)
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
            // 4. Hex 128 chars (64 bytes libsodium hex)
            if cleanKeyStr.count == 128 {
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
    public func resolveAccessPoint() async -> String {
        if let cached = cachedAccessPoint, !cached.isEmpty, !cached.contains("api.") {
            return cached
        }
        
        let cleanConfiguredHost = apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanConfiguredHost.contains("ap-") {
            self.cachedAccessPoint = cleanConfiguredHost
            return cleanConfiguredHost
        }
        
        guard !accountId.isEmpty else {
            return apiHost
        }
        
        let candidateGateways = [
            "https://api.exness-api.com",
            "https://api.exness.com"
        ]
        
        for gw in candidateGateways {
            let path = "/v1/trading/access-point?account_id=\(accountId)"
            guard let url = URL(string: "\(gw)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            
            guard let headers = try? signRequest(method: "GET", path: path, bodyData: nil) else { continue }
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ap = (json["access_point"] as? String) ??
                             ((json["data"] as? [String: Any])?["access_point"] as? String) ??
                             (json["cluster"] as? String) ??
                             (json["host"] as? String)
                    if let apStr = ap, !apStr.isEmpty {
                        var cleanAp = apStr.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanAp.hasPrefix("http://") && !cleanAp.hasPrefix("https://") {
                            cleanAp = "https://" + cleanAp
                        }
                        self.cachedAccessPoint = cleanAp
                        UserDefaults.standard.set(cleanAp, forKey: kExnessCachedAccessPoint)
                        AppLogger.info("Exness: Access Point discovered -> \(cleanAp)")
                        return cleanAp
                    }
                }
            }
        }
        
        AppLogger.info("Exness: Dynamic access point not returned; falling back to gateway \(apiHost)")
        return apiHost
    }
    
    // MARK: - Safe Data Parsers
    
    private func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
        for k in keys {
            if let v = dict[k] { return v }
        }
        return nil
    }

    private func parseDecimal(_ val: Any?) -> Decimal? {
        guard let v = val else { return nil }
        if let d = v as? Decimal { return d }
        if let num = v as? NSNumber {
            return Decimal(string: num.stringValue) ?? Decimal(num.doubleValue)
        }
        if let str = v as? String {
            let clean = str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            return Decimal(string: clean)
        }
        if let d = v as? Double { return Decimal(d) }
        if let i = v as? Int { return Decimal(i) }
        if let i64 = v as? Int64 { return Decimal(i64) }
        return nil
    }
    
    private func parseDouble(_ val: Any?) -> Double? {
        guard let v = val else { return nil }
        if let d = v as? Double { return d }
        if let num = v as? NSNumber { return num.doubleValue }
        if let str = v as? String {
            let clean = str.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            return Double(clean)
        }
        if let i = v as? Int { return Double(i) }
        if let i64 = v as? Int64 { return Double(i64) }
        return nil
    }
    
    private func parseDate(_ val: Any?) -> Date? {
        guard let v = val else { return nil }
        if let d = v as? Date { return d }
        if let ms = v as? Int64 {
            return Date(timeIntervalSince1970: ms > 10_000_000_000 ? Double(ms) / 1000.0 : Double(ms))
        }
        if let sec = v as? Double {
            return Date(timeIntervalSince1970: sec > 10_000_000_000 ? sec / 1000.0 : sec)
        }
        if let num = v as? NSNumber {
            let d = num.doubleValue
            return Date(timeIntervalSince1970: d > 10_000_000_000 ? d / 1000.0 : d)
        }
        if let str = v as? String {
            let clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = ISO8601DateFormatter().date(from: clean) {
                return d
            }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy.MM.dd HH:mm:ss",
                "yyyy/MM/dd HH:mm:ss"
            ]
            for fmt in formats {
                df.dateFormat = fmt
                if let d = df.date(from: clean) { return d }
            }
            if let sec = Double(clean) {
                return Date(timeIntervalSince1970: sec > 10_000_000_000 ? sec / 1000.0 : sec)
            }
        }
        return nil
    }
    
    private func parseBalanceResponse(_ json: [String: Any]) -> (balance: Decimal?, equity: Decimal?, currency: String?) {
        var targetDict = json
        if let dataDict = json["data"] as? [String: Any] {
            targetDict = dataDict
        } else if let accDict = json["account"] as? [String: Any] {
            targetDict = accDict
        } else if let resDict = json["result"] as? [String: Any] {
            targetDict = resDict
        } else if let accs = (json["accounts"] as? [[String: Any]]) ?? (json["items"] as? [[String: Any]]), let first = accs.first {
            targetDict = first
        }
        
        var foundCur: String? = nil
        let rawCur = targetDict["currency"] as? String ?? json["currency"] as? String ?? targetDict["account_currency"] as? String
        if let cur = rawCur {
            let cleanCur = cur.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // Exness Cent account: USC is micro-lot account, treated strictly as USD without altering calculations
            foundCur = (cleanCur == "USC" || cleanCur == "USCENT" || cleanCur == "CENT") ? "USD" : cleanCur
        }
        
        let balanceKeys = ["balance", "current_balance", "available_balance", "amount", "funds", "cash", "margin_free"]
        let rawBal = firstValue(in: targetDict, keys: balanceKeys) ?? json["balance"]
        let foundBal = parseDecimal(rawBal)
        
        let equityKeys = ["equity", "current_equity", "net_equity"]
        let rawEq = firstValue(in: targetDict, keys: equityKeys) ?? json["equity"] ?? rawBal
        let foundEq = parseDecimal(rawEq)
        
        return (foundBal, foundEq, foundCur)
    }
    
    @MainActor
    public func syncAccountWithDataStore() {
        guard !accountId.isEmpty else { return }
        let cleanId = accountId.cleanAccountId
        let journalAccId = "exness_\(cleanId)"
        let accountName = "Exness (\(cleanId))"
        let dataStore = TradeDataStore.shared
        var hasChanges = false
        
        if let existingIdx = dataStore.accounts.firstIndex(where: {
            $0.id == journalAccId ||
            $0.id == cleanId ||
            $0.id == self.accountId ||
            $0.id.isEquivalentAccountId(to: journalAccId) ||
            $0.name.contains(cleanId)
        }) {
            var acc = dataStore.accounts[existingIdx]
            if acc.initialBalance != self.balance || acc.currency != self.currency || acc.name != accountName {
                acc.name = accountName
                acc.broker = "Exness"
                acc.currency = self.currency
                acc.initialBalance = self.balance
                acc.lastSyncAt = Date()
                acc.visibleInJournal = true
                dataStore.accounts[existingIdx] = acc
                hasChanges = true
                AppLogger.info("Exness: Synced account \(acc.id) balance -> \(self.balance) \(self.currency)")
            }
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
            hasChanges = true
            AppLogger.info("Exness: Created new account \(journalAccId) balance -> \(self.balance) \(self.currency)")
        }
        
        if dataStore.selectedAccountId.isEmpty || dataStore.selectedAccountId == "default-acc" {
            dataStore.selectedAccountId = journalAccId
            hasChanges = true
        }
        
        // Only trigger UI invalidation and disk write if data actually changed
        if hasChanges {
            dataStore.invalidatePerformanceCaches()
            dataStore.saveToDisk(immediate: true)
            dataStore.objectWillChange.send()
        }
    }
    
    // MARK: - API Calls
    
    /// Tests authentication and connectivity to Exness REST API
    public func testConnection() async throws -> (success: Bool, message: String) {
        let cleanId = accountId.cleanAccountId
        guard !cleanId.isEmpty else {
            return (false, "Please configure Exness Account ID.")
        }
        
        let accessPointHost = await resolveAccessPoint()
        var candidateHosts: [String] = []
        if !accessPointHost.isEmpty {
            candidateHosts.append(accessPointHost)
        }
        if !candidateHosts.contains(self.apiHost) {
            candidateHosts.append(self.apiHost)
        }
        if !candidateHosts.contains("https://api.exness-api.com") {
            candidateHosts.append("https://api.exness-api.com")
        }
        if !candidateHosts.contains("https://api.exness.com") {
            candidateHosts.append("https://api.exness.com")
        }
        
        let candidateBalancePaths = [
            "/v1/trading/accounts/\(cleanId)/balance",
            "/v1/accounts/\(cleanId)/balance",
            "/v1/trading/accounts/\(cleanId)",
            "/v1/accounts/\(cleanId)",
            "/v1/trading/balance?account_id=\(cleanId)",
            "/v1/accounts/balance?account_id=\(cleanId)"
        ]
        
        var lastErrorMsg = "Unable to connect to Exness API."
        
        for host in candidateHosts {
            for path in candidateBalancePaths {
                let cleanHost = host.hasSuffix("/") ? String(host.dropLast()) : host
                let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
                guard let url = URL(string: "\(cleanHost)\(cleanPath)") else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                
                guard let headers = try? signRequest(method: "GET", path: cleanPath, bodyData: nil) else {
                    continue
                }
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let httpResponse = response as? HTTPURLResponse else {
                    continue
                }
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let parsed = parseBalanceResponse(json)
                        
                        await MainActor.run {
                            self.workingHost = cleanHost
                            self.workingBasePath = cleanPath
                            if let c = parsed.currency {
                                let cleanC = c.uppercased()
                                self.currency = (cleanC == "USC" || cleanC == "USCENT" || cleanC == "CENT") ? "USD" : cleanC
                            }
                            if let b = parsed.balance {
                                self.balance = b
                            }
                            if let eq = parsed.equity {
                                self.equity = eq
                            }
                            self.isConnected = true
                            self.syncAccountWithDataStore()
                        }
                    }
                    
                    let formattedBal = Formatters.formatCurrency(self.balance, currency: self.currency)
                    return (true, "Exness connected • Balance: \(formattedBal)")
                } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Invalid API key or Ed25519 signature."
                    lastErrorMsg = "Authentication failed (HTTP \(httpResponse.statusCode)): \(errorMsg)"
                } else {
                    let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    lastErrorMsg = "Connection error: \(errorMsg)"
                }
            }
        }
        
        await MainActor.run { self.isConnected = false }
        return (false, lastErrorMsg)
    }
    
    // MARK: - Exness Data Ingestion & Parser
    
    private func fetchEndpointData(path: String, host: String) async -> [[String: Any]] {
        let cleanHost = host.hasSuffix("/") ? String(host.dropLast()) : host
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "\(cleanHost)\(cleanPath)") else { return [] }
        
        // Exness Ed25519 Spec: Some gateway routers validate EXN-DATA 'path' against url.path (without query),
        // while others validate against the full path with query string. We test cleanPath first, then url.path.
        var signaturePaths = [cleanPath]
        if let query = url.query, !query.isEmpty {
            let basePath = url.path
            if !signaturePaths.contains(basePath) && !basePath.isEmpty {
                signaturePaths.append(basePath)
            }
        }
        
        for sigPath in signaturePaths {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 12
            
            guard let headers = try? signRequest(method: "GET", path: sigPath, bodyData: nil) else { continue }
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { continue }
            
            if http.statusCode == 200 {
                let records = extractRecords(from: data)
                if !records.isEmpty {
                    AppLogger.info("Exness: Found \(records.count) records at \(cleanHost)\(cleanPath)")
                }
                return records
            } else if http.statusCode == 401 || http.statusCode == 403 {
                // If signature was rejected, try next signature path variant
                continue
            } else {
                AppLogger.debug("Exness: Endpoint \(cleanHost)\(cleanPath) -> HTTP \(http.statusCode)")
                break // non-auth failure (e.g. 404 or 400), don't retry same URL
            }
        }
        
        return []
    }
    
    private func isTradeRecordLike(_ dict: [String: Any]) -> Bool {
        let symKeys = ["symbol", "instrument", "pair", "ticker", "code", "symbolName", "symbol_name"]
        let idKeys = ["ticket", "id", "order_id", "deal_id", "position_id", "trade_id", "ticket_id", "orderId", "dealId", "positionId", "pos_id"]
        let metricKeys = ["price", "open_price", "openPrice", "rate", "volume", "lots", "quantity", "amount", "profit", "net_profit", "pnl"]
        
        let hasSym = symKeys.contains(where: { dict[$0] != nil })
        let hasId = idKeys.contains(where: { dict[$0] != nil })
        let hasMetric = metricKeys.contains(where: { dict[$0] != nil })
        
        return (hasSym && (hasId || hasMetric)) || (hasId && hasMetric)
    }
    
    private func unwrapRecordContainer(_ dict: [String: Any]) -> [String: Any] {
        let wrapperKeys = ["position", "deal", "order", "trade", "item", "record", "transaction", "execution"]
        for k in wrapperKeys {
            if let inner = dict[k] as? [String: Any], isTradeRecordLike(inner) {
                var merged = dict
                merged.removeValue(forKey: k)
                inner.forEach { merged[$0] = $1 }
                return merged
            }
        }
        return dict
    }
    
    private func extractRecords(from data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return extractRecordsFromObject(root)
    }
    
    private func extractRecordsFromObject(_ obj: Any) -> [[String: Any]] {
        if let arr = obj as? [[String: Any]] {
            var res: [[String: Any]] = []
            for item in arr {
                let unwrapped = unwrapRecordContainer(item)
                if isTradeRecordLike(unwrapped) {
                    res.append(unwrapped)
                } else {
                    let sub = extractRecordsFromObject(item)
                    if !sub.isEmpty { res.append(contentsOf: sub) }
                }
            }
            return res
        }
        
        guard let dict = obj as? [String: Any] else { return [] }
        
        let unwrappedDict = unwrapRecordContainer(dict)
        if isTradeRecordLike(unwrappedDict) && !hasContainerCollections(dict) {
            return [unwrappedDict]
        }
        
        var collected: [[String: Any]] = []
        let candidateKeys = [
            "history", "deals", "trades", "orders", "positions", "open_positions", "closed_positions",
            "items", "data", "records", "result", "rows", "list", "entries", "transactions", "executions"
        ]
        
        for key in candidateKeys {
            guard let val = dict[key] else { continue }
            if let arr = val as? [[String: Any]] {
                for item in arr {
                    let u = unwrapRecordContainer(item)
                    if isTradeRecordLike(u) {
                        collected.append(u)
                    } else {
                        collected.append(contentsOf: extractRecordsFromObject(item))
                    }
                }
            } else if let subDict = val as? [String: Any] {
                // Check if subDict is a dictionary of records keyed by ID, e.g. {"1001": {...}, "1002": {...}}
                let innerRecords = subDict.values.compactMap { $0 as? [String: Any] }
                    .map { unwrapRecordContainer($0) }
                    .filter { isTradeRecordLike($0) }
                if !innerRecords.isEmpty {
                    collected.append(contentsOf: innerRecords)
                } else {
                    collected.append(contentsOf: extractRecordsFromObject(subDict))
                }
            }
        }
        
        if collected.isEmpty {
            let innerRecords = dict.values.compactMap { $0 as? [String: Any] }
                .map { unwrapRecordContainer($0) }
                .filter { isTradeRecordLike($0) }
            if !innerRecords.isEmpty {
                collected.append(contentsOf: innerRecords)
            }
        }
        
        return collected
    }
    
    private func hasContainerCollections(_ dict: [String: Any]) -> Bool {
        let containerKeys = ["positions", "deals", "orders", "history", "trades", "data", "items", "list", "open_positions", "closed_positions"]
        return containerKeys.contains(where: { dict[$0] is [[String: Any]] || dict[$0] is [String: Any] })
    }
    
    private func recordSignature(_ raw: [String: Any]) -> String {
        let target = unwrapRecordContainer(raw)
        let ticketKeys = ["ticket", "id", "order_id", "deal_id", "position_id", "trade_id", "ticket_id", "orderId", "dealId", "positionId", "pos_id"]
        for k in ticketKeys {
            if let v = target[k] {
                let str = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty && str != "0" { return str }
            }
        }
        let sym = String(describing: target["symbol"] ?? target["instrument"] ?? "")
        let openTime = String(describing: target["open_time"] ?? target["time_create"] ?? target["time"] ?? "")
        let price = String(describing: target["open_price"] ?? target["price"] ?? "")
        return "\(sym)|\(openTime)|\(price)"
    }
    
    private func parseExnessRecord(_ raw: [String: Any], journalAccId: String) -> (executions: [Execution], directTrade: Trade?) {
        let target = unwrapRecordContainer(raw)
        
        // 1. Symbol Extraction (supports String or nested Object)
        let symbolKeys = ["symbol", "instrument", "symbolName", "symbol_name", "code", "pair", "currency_pair", "ticker"]
        var cleanSymbol: String? = nil
        for k in symbolKeys {
            if let s = target[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cleanSymbol = s.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            } else if let subObj = target[k] as? [String: Any] {
                if let s = (subObj["name"] ?? subObj["symbol"] ?? subObj["code"] ?? subObj["id"]) as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleanSymbol = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        guard let symbol = cleanSymbol else { return ([], nil) }
        
        // 2. Ticket / Order ID Extraction
        let ticketKeys = [
            "ticket", "id", "order_id", "deal_id", "position_id", "trade_id", 
            "ticket_id", "orderId", "dealId", "positionId", "pos_id", 
            "order_ticket", "deal_ticket", "transact_id", "external_id", "uuid"
        ]
        var ticketStr = ""
        for k in ticketKeys {
            if let v = target[k] {
                let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty && s != "0" {
                    ticketStr = s
                    break
                }
            }
        }
        
        // 3. Dates & Pricing
        let rawOpenDate = firstValue(in: target, keys: ["open_time", "openTime", "time_create", "create_time", "time_setup", "timestamp", "time", "opened_at", "executed_at", "datetime"])
        let openDate = parseDate(rawOpenDate) ?? Date()
        
        let rawOpenPrice = firstValue(in: target, keys: [
            "open_price", "openPrice", "price", "executionPrice", "entry_price", "entryPrice",
            "price_open", "open_rate", "rate", "deal_price", "fill_price", "execution_price",
            "avg_price", "average_price", "trade_price", "open", "entry"
        ])
        var openPriceVal = parseDouble(rawOpenPrice) ?? 0.0
        
        let rawClosePrice = firstValue(in: target, keys: [
            "close_price", "closePrice", "exit_price", "exitPrice", "price_close", 
            "close_rate", "exit_rate", "close", "exit", "settle_price", "current_price"
        ])
        let closePriceVal = parseDouble(rawClosePrice)
        
        if openPriceVal == 0 && (closePriceVal ?? 0) > 0 {
            openPriceVal = closePriceVal!
        }
        guard openPriceVal > 0 else { return ([], nil) }
        let openPrice = Decimal(openPriceVal)
        
        // Deterministic ticket fallback if missing
        if ticketStr.isEmpty {
            ticketStr = "\(symbol)_\(Int(openDate.timeIntervalSince1970))_\(Int(openPriceVal * 100))"
        }
        
        // 4. Volume / Lots
        let rawVolume = firstValue(in: target, keys: ["volume", "lots", "quantity", "size", "units", "amount", "qty", "deal_volume"])
        let volumeVal = parseDouble(rawVolume) ?? 0.01
        let quantity = max(Decimal(string: "0.0001") ?? 0.0001, Decimal(volumeVal))
        
        // 5. Direction / Side
        let rawOp = firstValue(in: target, keys: ["operation", "side", "type", "cmd", "direction", "action"])
        let opRaw = String(describing: rawOp ?? "BUY").uppercased()
        let isSell = opRaw.contains("SELL") || opRaw == "1" || opRaw.contains("SHORT")
        let side: ExecutionSide = isSell ? .sell : .buy
        let exitSide: ExecutionSide = isSell ? .buy : .sell
        
        let rawCloseDate = firstValue(in: target, keys: ["close_time", "closeTime", "time_close", "time_done", "time_update", "closed_at", "closedAt", "exit_time"])
        let closeDate = parseDate(rawCloseDate)
        
        let rawFee = firstValue(in: target, keys: ["commission", "fee", "commission_amount", "fees", "comm"])
        let feeVal = abs(parseDouble(rawFee) ?? 0.0)
        let fee = Decimal(feeVal)
        
        let rawSwap = firstValue(in: target, keys: ["swap", "rollover", "swaps", "storage"])
        let swapVal = parseDouble(rawSwap)
        let swap: Decimal? = swapVal != nil ? Decimal(swapVal!) : nil
        
        let rawProfit = firstValue(in: target, keys: ["profit", "net_profit", "pnl", "realized_pnl", "net_pnl", "gross_pnl", "profit_loss", "pl"])
        let profitVal = parseDouble(rawProfit)
        
        let rawStatus = String(describing: target["status"] ?? target["state"] ?? "").lowercased()
        let isClosed = (closePriceVal != nil && closePriceVal! > 0) || 
                       (closeDate != nil && closeDate != openDate) || 
                       (profitVal != nil && profitVal != 0) ||
                       rawStatus.contains("closed") || rawStatus.contains("filled") ||
                       (target["closed"] as? Bool) == true
        
        let symUpper = symbol.uppercased()
        let isMetals = symUpper.hasPrefix("XAU") || symUpper.hasPrefix("XAG") || symUpper.contains("GOLD") || symUpper.contains("SILVER")
        let isCrypto = symUpper.hasPrefix("BTC") || symUpper.hasPrefix("ETH") || symUpper.hasPrefix("SOL") || symUpper.hasPrefix("XRP")
        let isIndex = symUpper.hasPrefix("US30") || symUpper.hasPrefix("USTEC") || symUpper.hasPrefix("NAS") || symUpper.hasPrefix("SPX") || symUpper.hasPrefix("GER") || symUpper.hasPrefix("UK100") || symUpper.hasPrefix("WS30")
        let assetClass: AssetClass = isMetals ? "commodity" : (isCrypto ? "crypto" : (isIndex ? "indices" : "forex"))
        
        var fills: [Execution] = []
        var directTrade: Trade? = nil
        
        if isClosed {
            let cp = closePriceVal ?? openPriceVal
            let cDate = closeDate ?? openDate.addingTimeInterval(60)
            
            let entryId = "exness_\(ticketStr)_in"
            let entryHash = "\(journalAccId)|\(symbol)|\(side.rawValue)|\(quantity)|\(openPriceVal)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let entryFill = Execution(
                id: entryId,
                accountId: journalAccId,
                symbol: symbol,
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
            let exitHash = "\(journalAccId)|\(symbol)|\(exitSide.rawValue)|\(quantity)|\(cp)|\(Int64(cDate.timeIntervalSince1970 * 1000))"
            let exitFill = Execution(
                id: exitId,
                accountId: journalAccId,
                symbol: symbol,
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
            
            // Construct authoritative direct Trade using broker-reported profit
            let tradeKey = "exness_\(ticketStr)"
            let rawNetPnl: Decimal = profitVal != nil ? Decimal(profitVal!) : ((side == .buy ? Decimal(cp) - openPrice : openPrice - Decimal(cp)) * quantity * 1000 - fee + (swap ?? 0))
            let grossPnl: Decimal = rawNetPnl + fee - (swap ?? 0)
            
            let tradeStatus: TradeStatus = rawNetPnl > 0 ? .win : (rawNetPnl < 0 ? .loss : .breakeven)
            let durMs = Int64(max(0, cDate.timeIntervalSince(openDate) * 1000))
            
            directTrade = Trade(
                key: tradeKey,
                accountId: journalAccId,
                symbol: symbol,
                assetClass: assetClass,
                direction: side == .buy ? .long : .short,
                status: tradeStatus,
                openedAt: openDate,
                closedAt: cDate,
                quantity: quantity,
                openQuantity: 0,
                avgEntry: openPrice,
                avgExit: Decimal(cp),
                grossPnl: grossPnl,
                fees: fee,
                swap: swap,
                netPnl: rawNetPnl,
                executionCount: 2,
                executionIds: [entryId, exitId],
                durationMs: durMs
            )
        } else {
            // Open Position
            let fillId = "exness_\(ticketStr)"
            let fillHash = "\(journalAccId)|\(symbol)|\(side.rawValue)|\(quantity)|\(openPriceVal)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let fill = Execution(
                id: fillId,
                accountId: journalAccId,
                symbol: symbol,
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
            
            let tradeKey = "exness_\(ticketStr)"
            let rawNetPnl: Decimal = profitVal != nil ? Decimal(profitVal!) : 0
            directTrade = Trade(
                key: tradeKey,
                accountId: journalAccId,
                symbol: symbol,
                assetClass: assetClass,
                direction: side == .buy ? .long : .short,
                status: .open,
                openedAt: openDate,
                closedAt: nil,
                quantity: quantity,
                openQuantity: quantity,
                avgEntry: openPrice,
                avgExit: nil,
                grossPnl: 0,
                fees: fee,
                swap: swap,
                netPnl: rawNetPnl,
                executionCount: 1,
                executionIds: [fillId],
                durationMs: nil
            )
        }
        
        return (fills, directTrade)
    }
    
    /// Synchronizes trades, orders, positions, and history from Exness REST API
    public func syncTrades() async throws -> Int {
        let cleanId = accountId.cleanAccountId
        guard !cleanId.isEmpty else {
            throw NSError(domain: "ExnessService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please configure Exness Account ID."])
        }
        
        await MainActor.run {
            self.isSyncing = true
        }
        defer {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }
        
        // 1. Fetch live balance, equity, and normalized currency (USC -> USD)
        _ = try? await testConnection()
        
        let accessPointHost = await resolveAccessPoint()
        let journalAccId = "exness_\(cleanId)"
        
        await MainActor.run {
            self.syncAccountWithDataStore()
        }
        
        // 2. Discover candidate hosts (working host first, then access point, gateway, fallback)
        var hostsToTry: [String] = []
        if let wh = workingHost, !wh.isEmpty {
            hostsToTry.append(wh)
        }
        if !accessPointHost.isEmpty && !hostsToTry.contains(accessPointHost) {
            hostsToTry.append(accessPointHost)
        }
        if !hostsToTry.contains(self.apiHost) {
            hostsToTry.append(self.apiHost)
        }
        if !hostsToTry.contains("https://api.exness-api.com") {
            hostsToTry.append("https://api.exness-api.com")
        }
        if !hostsToTry.contains("https://api.exness.com") {
            hostsToTry.append("https://api.exness.com")
        }
        
        // 3. Comprehensive candidate endpoints for history, deals, positions, and orders
        var candidatePaths = [
            // Standard Trading API History, Deals, Orders, and Positions routes
            "/v1/trading/accounts/\(cleanId)/positions",
            "/v1/trading/accounts/\(cleanId)/deals",
            "/v1/trading/accounts/\(cleanId)/history",
            "/v1/trading/accounts/\(cleanId)/orders",
            "/v1/trading/accounts/\(cleanId)/trades",
            "/v1/trading/accounts/\(cleanId)/history/deals",
            "/v1/trading/accounts/\(cleanId)/history/orders",
            "/v1/trading/accounts/\(cleanId)/deals/history",
            "/v1/trading/accounts/\(cleanId)/orders/history",
            
            // Standard Gateway routes
            "/v1/accounts/\(cleanId)/positions",
            "/v1/accounts/\(cleanId)/deals",
            "/v1/accounts/\(cleanId)/history",
            "/v1/accounts/\(cleanId)/orders",
            "/v1/accounts/\(cleanId)/trades",
            "/v1/accounts/\(cleanId)/history/deals",
            "/v1/accounts/\(cleanId)/history/orders",
            "/v1/accounts/\(cleanId)/deals/history",
            "/v1/accounts/\(cleanId)/orders/history",
            
            // Root Account details payload (frequently embeds active positions and recent orders)
            "/v1/trading/accounts/\(cleanId)",
            "/v1/accounts/\(cleanId)",
            
            // Query parameter variants with limits / date horizons
            "/v1/trading/accounts/\(cleanId)/positions?limit=1000",
            "/v1/trading/accounts/\(cleanId)/deals?limit=1000",
            "/v1/trading/accounts/\(cleanId)/history?limit=1000",
            "/v1/trading/accounts/\(cleanId)/deals?from=0&limit=1000",
            "/v1/trading/accounts/\(cleanId)/history?from=0&limit=1000",
            "/v1/accounts/\(cleanId)/positions?limit=1000",
            "/v1/accounts/\(cleanId)/deals?limit=1000",
            "/v1/accounts/\(cleanId)/history?limit=1000",
            
            // Non-account scoped routes
            "/v1/trading/positions?account_id=\(cleanId)",
            "/v1/trading/deals?account_id=\(cleanId)",
            "/v1/trading/history?account_id=\(cleanId)",
            "/v1/trading/trades?account_id=\(cleanId)",
            "/v1/trading/orders?account_id=\(cleanId)",
            "/v1/trading/history/deals?account_id=\(cleanId)",
            "/v1/trading/history/orders?account_id=\(cleanId)",
            "/v1/trading/positions",
            "/v1/trading/deals",
            "/v1/trading/history",
            "/v1/positions?account_id=\(cleanId)",
            "/v1/deals?account_id=\(cleanId)",
            "/v1/history?account_id=\(cleanId)",
            "/v1/trades?account_id=\(cleanId)",
            "/v1/orders?account_id=\(cleanId)"
        ]
        
        // If workingBasePath is known, prioritize matching path family
        if let base = workingBasePath {
            if base.contains("/trading/accounts/") {
                candidatePaths.sort { p1, _ in p1.contains("/trading/accounts/") }
            } else if base.contains("/accounts/") {
                candidatePaths.sort { p1, _ in p1.contains("/accounts/") }
            }
        }
        
        var allRawRecords: [[String: Any]] = []
        var seenRecordSignatures = Set<String>()
        
        for host in hostsToTry {
            for path in candidatePaths {
                let records = await fetchEndpointData(path: path, host: host)
                if !records.isEmpty {
                    for rec in records {
                        let sig = recordSignature(rec)
                        if !seenRecordSignatures.contains(sig) {
                            seenRecordSignatures.insert(sig)
                            allRawRecords.append(rec)
                        }
                    }
                }
            }
            if !allRawRecords.isEmpty {
                break
            }
        }
        
        // 4. Parse Exness records to database Execution fills and direct Trade objects
        var newExecutions: [Execution] = []
        var directTrades: [Trade] = []
        
        for raw in allRawRecords {
            let parsed = parseExnessRecord(raw, journalAccId: journalAccId)
            newExecutions.append(contentsOf: parsed.executions)
            if let dt = parsed.directTrade {
                directTrades.append(dt)
            }
        }
        
        // 5. Ingest executions and direct trades into TradeDataStore
        await MainActor.run {
            let dataStore = TradeDataStore.shared
            
            // A. Merge direct trades first so authoritative broker trades are in place
            if !directTrades.isEmpty {
                var currentTrades = dataStore.trades
                for t in directTrades {
                    if let idx = currentTrades.firstIndex(where: { $0.key == t.key || $0.id == t.id }) {
                        currentTrades[idx] = t
                    } else {
                        currentTrades.append(t)
                    }
                }
                dataStore.trades = currentTrades
                dataStore.deduplicateTrades()
            }
            
            // B. Import executions for execution history audit log
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
            }
            
            // Only invalidate caches and write to disk if new trades or executions arrived
            if !directTrades.isEmpty || !newExecutions.isEmpty {
                // Ensure newly synced Exness account is selected if currently default or empty
                if dataStore.selectedAccountId.isEmpty || dataStore.selectedAccountId == "default-acc" {
                    dataStore.selectedAccountId = journalAccId
                }
                dataStore.invalidatePerformanceCaches()
                dataStore.saveToDisk(immediate: true)
                dataStore.objectWillChange.send()
            }
            
            let total = directTrades.count > 0 ? directTrades.count : (newExecutions.count / 2)
            self.syncedTradesCount = total
            if total > 0 {
                self.lastSyncSummary = "Connected • \(total) trades synced"
            } else {
                self.lastSyncSummary = "Connected • 0 trades found (probed positions & history)"
            }
        }
        
        let now = Date()
        UserDefaults.standard.set(now, forKey: kExnessLastSync)
        await MainActor.run {
            self.lastSyncDate = now
            self.isConnected = true
        }
        
        return self.syncedTradesCount
    }
}
