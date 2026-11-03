import Foundation
import SwiftUI
import CryptoKit

/// Official Exness REST API Integration Service based on exness-api.com specification
/// Implements automatic Access Point Discovery, Ed25519 cryptographic signing, server clock drift compensation,
/// live balance/equity snapshots, and full deals/executions/orders history synchronization.
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
    @Published public var accountName: String = ""
    
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
    
    // Server clock drift compensation (ms) to satisfy strict Exness timestamp window
    private var serverTimeOffsetMs: Int64 = 0
    
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
        
        let plistAcc = AppSecretsLoader.loadSecret(named: "EXNESS_ACCOUNT_ID")
        let acc = (plistAcc?.isEmpty == false) ? (plistAcc ?? "") : (ud.string(forKey: kExnessAccountId) ?? "")
        if !acc.isEmpty {
            ud.set(acc, forKey: kExnessAccountId)
        }
        self.accountId = acc
        
        let plistKey = AppSecretsLoader.loadSecret(named: "EXNESS_API_KEY")
        let key = (plistKey?.isEmpty == false) ? (plistKey ?? "") : (KeychainManager.get(forKey: kExnessApiKey) ?? "")
        if !key.isEmpty {
            KeychainManager.set(key, forKey: kExnessApiKey)
        }
        self.apiKey = key
        
        let plistPriv = AppSecretsLoader.loadSecret(named: "EXNESS_PRIVATE_KEY")
        let priv = (plistPriv?.isEmpty == false) ? (plistPriv ?? "") : (KeychainManager.get(forKey: kExnessPrivateKey) ?? "")
        if !priv.isEmpty {
            KeychainManager.set(priv, forKey: kExnessPrivateKey)
        }
        
        self.lastSyncDate = ud.object(forKey: kExnessLastSync) as? Date
        
        if let cap = ud.string(forKey: kExnessCachedAccessPoint), !cap.contains("api.exness.com") {
            self.cachedAccessPoint = cap
        } else {
            self.cachedAccessPoint = nil
            ud.removeObject(forKey: kExnessCachedAccessPoint)
        }
        
        let hasPrivateKey = !priv.isEmpty
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
        KeychainManager.get(forKey: kExnessPrivateKey) ?? AppSecretsLoader.loadSecret(named: "EXNESS_PRIVATE_KEY") ?? ""
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
    
    // MARK: - Server Time Synchronization
    
    /// Synchronizes client time offset against the Exness server Date header
    public func syncServerTimeIfNeeded() async {
        guard let url = URL(string: "https://api.exness-api.com/") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        let start = Date()
        if let (_, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse {
            recordServerTime(from: http, roundTripStart: start)
        }
    }
    
    private func recordServerTime(from response: HTTPURLResponse, roundTripStart: Date) {
        let rawDate = response.value(forHTTPHeaderField: "Date") ?? (response.allHeaderFields["Date"] as? String)
        guard let dateStr = rawDate else { return }
        
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        
        if let serverDate = df.date(from: dateStr) {
            let roundTrip = Date().timeIntervalSince(roundTripStart)
            let estimatedServerTime = serverDate.timeIntervalSince1970 + (roundTrip / 2.0)
            let offset = Int64((estimatedServerTime - Date().timeIntervalSince1970) * 1000)
            self.serverTimeOffsetMs = offset
            AppLogger.info("Exness: Synchronized server time offset: \(offset) ms")
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
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000) + serverTimeOffsetMs
        
        // Exact SHA-256 body hash per Exness spec:
        // "For requests without a body, body_hash is the SHA-256 hash of the empty byte sequence: 47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
        let bodyHash: String
        if let body = bodyData, !body.isEmpty {
            let digest = SHA256.hash(data: body)
            bodyHash = base64UrlEncode(Data(digest))
        } else {
            bodyHash = "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
        }
        
        // Canonical payload dictionary for EXN-DATA (sign_version must be integer 1, timestamp in integer ms)
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
        
        // Parse Ed25519 raw 32-byte seed from PKCS#8 DER (48 bytes), Libsodium (64 bytes), 128-char Hex, 64-char Hex, or Base64
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
            // 3. Hex 64 chars (32 bytes raw seed)
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
            // 4. Hex 128 chars (64 bytes: 32 bytes seed + 32 bytes public key)
            if cleanKeyStr.count == 128 {
                var d = Data()
                var idx = cleanKeyStr.startIndex
                for _ in 0..<32 { // extract first 32 bytes (64 hex characters)
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
        
        var headers: [String: String] = [
            "EXN-API-KEY": cleanKey,
            "EXN-IDEMPOTENCY-KEY": idempotencyKey,
            "EXN-TIMESTAMP": String(timestamp),
            "EXN-SIGN-VERSION": "1",
            "EXN-DATA": exnData,
            "EXN-SIGN": exnSign,
            "User-Agent": "TradeJournal-iOS/1.0"
        ]
        if bodyData != nil {
            headers["Content-Type"] = "application/json"
        }
        return headers
    }
    
    // MARK: - Access Point / Host Discovery (Official exness-api.com Spec)
    
    /// Resolves the dynamic Access Point URL for this account ID via the Exness Gateway
    public func resolveAccessPoint() async -> String {
        if let cached = cachedAccessPoint, !cached.isEmpty, cached.contains("ap-") {
            return cached
        }
        
        let cleanConfiguredHost = apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanConfiguredHost.contains("ap-") {
            self.cachedAccessPoint = cleanConfiguredHost
            return cleanConfiguredHost
        }
        
        let cleanId = accountId.cleanAccountId
        guard !cleanId.isEmpty else {
            return "https://api.exness-api.com"
        }
        
        if serverTimeOffsetMs == 0 {
            await syncServerTimeIfNeeded()
        }
        
        let candidateGateways = [
            "https://api.exness-api.com",
            "https://api.exness.com"
        ]
        
        for gw in candidateGateways {
            let path = "/v1/trading/access-point?account_id=\(cleanId)"
            guard let url = URL(string: "\(gw)\(path)") else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            
            guard let headers = try? signRequest(method: "GET", path: path, bodyData: nil) else { continue }
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            let reqStart = Date()
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse {
                recordServerTime(from: http, roundTripStart: reqStart)
                if http.statusCode == 200 {
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
        }
        
        AppLogger.info("Exness: Dynamic access point not returned; falling back to gateway https://api.exness-api.com")
        return "https://api.exness-api.com"
    }
    
    // MARK: - Safe Data Parsers
    
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
            
            let isoWithFractional = ISO8601DateFormatter()
            isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoWithFractional.date(from: clean) {
                return d
            }
            if let d = ISO8601DateFormatter().date(from: clean) {
                return d
            }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
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
    
    @MainActor
    public func syncAccountWithDataStore() {
        guard !accountId.isEmpty else { return }
        let cleanId = accountId.cleanAccountId
        let journalAccId = "exness_\(cleanId)"
        let resolvedAccountName = self.accountName.isEmpty ? "Exness (\(cleanId))" : "\(self.accountName) (\(cleanId))"
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
            if acc.initialBalance != self.balance || acc.currency != self.currency || acc.name != resolvedAccountName {
                acc.name = resolvedAccountName
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
                name: resolvedAccountName,
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
            
            Task {
                if SupabaseService.shared.isConfigured,
                   let acc = dataStore.accounts.first(where: { $0.id == journalAccId }) {
                    try? await SupabaseService.shared.upsertAccounts([acc])
                }
                await dataStore.syncWithSupabase(isBackground: true)
            }
        }
    }
    
    // MARK: - API Calls
    
    /// Tests authentication and connectivity to Exness REST API using official Discovery, Account Details, and Snapshot endpoints
    public func testConnection() async throws -> (success: Bool, message: String) {
        let cleanId = accountId.cleanAccountId
        guard !cleanId.isEmpty else {
            return (false, "Please configure Exness Account ID.")
        }
        
        await syncServerTimeIfNeeded()
        
        // 1. Discover cluster Access Point host
        let apHost = await resolveAccessPoint()
        guard !apHost.isEmpty else {
            return (false, "Could not discover Exness cluster access point.")
        }
        
        // 2. Fetch Account Configuration metadata (/v1/configuration/accounts/{account_id}/account)
        var discoveredName = ""
        var discoveredCurrency = "USD"
        var discoveredLeverage = 100
        
        let configPath = "/v1/configuration/accounts/\(cleanId)/account"
        if let configUrl = URL(string: "\(apHost)\(configPath)") {
            var cReq = URLRequest(url: configUrl)
            cReq.httpMethod = "GET"
            cReq.timeoutInterval = 8
            
            if let cHeaders = try? signRequest(method: "GET", path: configPath, bodyData: nil) {
                cHeaders.forEach { cReq.setValue($1, forHTTPHeaderField: $0) }
                let cStart = Date()
                if let (cData, cRes) = try? await URLSession.shared.data(for: cReq),
                   let cHttp = cRes as? HTTPURLResponse {
                    recordServerTime(from: cHttp, roundTripStart: cStart)
                    if cHttp.statusCode == 200,
                       let cJson = try? JSONSerialization.jsonObject(with: cData) as? [String: Any] {
                        if let n = cJson["account_name"] as? String, !n.isEmpty {
                            discoveredName = n
                        }
                        if let s = cJson["settings"] as? [String: Any] {
                            if let cur = s["currency"] as? String {
                                let cleanCur = cur.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                discoveredCurrency = (cleanCur == "USC" || cleanCur == "USCENT" || cleanCur == "CENT") ? "USD" : cleanCur
                            }
                            if let levStr = s["leverage"] as? String, let levInt = Int(levStr) {
                                discoveredLeverage = levInt
                            }
                        }
                    }
                }
            }
        }
        
        // 3. Fetch Trading State Snapshot (/v1/trading/accounts/{account_id}/snapshot)
        let snapshotPath = "/v1/trading/accounts/\(cleanId)/snapshot"
        guard let snapshotUrl = URL(string: "\(apHost)\(snapshotPath)") else {
            return (false, "Invalid Exness Snapshot URL.")
        }
        
        var sReq = URLRequest(url: snapshotUrl)
        sReq.httpMethod = "GET"
        sReq.timeoutInterval = 8
        
        guard let sHeaders = try? signRequest(method: "GET", path: snapshotPath, bodyData: nil) else {
            return (false, "Failed to sign Exness Snapshot request with Ed25519.")
        }
        sHeaders.forEach { sReq.setValue($1, forHTTPHeaderField: $0) }
        
        let sStart = Date()
        guard let (sData, sResponse) = try? await URLSession.shared.data(for: sReq),
              let sHttp = sResponse as? HTTPURLResponse else {
            await MainActor.run { self.isConnected = false }
            return (false, "Unable to reach Exness Trading Snapshot.")
        }
        recordServerTime(from: sHttp, roundTripStart: sStart)
        
        if sHttp.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
               let state = json["account_state"] as? [String: Any] {
                let bal = parseDecimal(state["balance"]) ?? 0
                let eq = parseDecimal(state["equity"]) ?? bal
                
                await MainActor.run {
                    self.workingHost = apHost
                    self.workingBasePath = snapshotPath
                    self.balance = bal
                    self.equity = eq
                    self.currency = discoveredCurrency
                    if !discoveredName.isEmpty {
                        self.accountName = discoveredName
                    }
                    self.leverage = discoveredLeverage
                    self.isConnected = true
                    self.syncAccountWithDataStore()
                }
                
                let formattedBal = Formatters.formatCurrency(bal, currency: discoveredCurrency)
                let accLabel = discoveredName.isEmpty ? "Account \(cleanId)" : "'\(discoveredName)'"
                return (true, "Exness \(accLabel) • Balance: \(formattedBal)")
            }
        } else if sHttp.statusCode == 401 || sHttp.statusCode == 403 {
            await MainActor.run { self.isConnected = false }
            return (false, "Exness authentication failed (HTTP \(sHttp.statusCode)). Please verify API key & secret.")
        }
        
        await MainActor.run { self.isConnected = false }
        return (false, "Exness Snapshot returned HTTP \(sHttp.statusCode).")
    }
    
    // MARK: - Exness Data Ingestion & Parser
    
    private func fetchEndpointData(path: String, host: String) async -> (json: [String: Any]?, statusCode: Int) {
        let cleanHost = host.hasSuffix("/") ? String(host.dropLast()) : host
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "\(cleanHost)\(cleanPath)") else { return (nil, 0) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        guard let headers = try? signRequest(method: "GET", path: cleanPath, bodyData: nil) else { return (nil, 0) }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let start = Date()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, 0) }
        
        recordServerTime(from: http, roundTripStart: start)
        
        if http.statusCode == 200 {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json, 200)
        } else {
            AppLogger.debug("Exness: Endpoint \(cleanHost)\(cleanPath) -> HTTP \(http.statusCode)")
            return (nil, http.statusCode)
        }
    }
    
    private func assetClassForSymbol(_ symbol: String) -> AssetClass {
        let symUpper = symbol.uppercased()
        if symUpper.hasPrefix("XAU") || symUpper.hasPrefix("XAG") || symUpper.contains("GOLD") || symUpper.contains("SILVER") {
            return "commodity"
        }
        if symUpper.hasPrefix("BTC") || symUpper.hasPrefix("ETH") || symUpper.hasPrefix("SOL") || symUpper.hasPrefix("XRP") {
            return "crypto"
        }
        if symUpper.hasPrefix("US30") || symUpper.hasPrefix("USTEC") || symUpper.hasPrefix("NAS") || symUpper.hasPrefix("SPX") || symUpper.hasPrefix("GER") || symUpper.hasPrefix("UK100") || symUpper.hasPrefix("WS30") {
            return "indices"
        }
        return "forex"
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
        
        // 1. Fetch live balance, equity, and normalized currency
        _ = try? await testConnection()
        
        let accessPointHost = await resolveAccessPoint()
        let clusterHost = accessPointHost.contains("ap-") ? accessPointHost : "https://api.exness-api.com"
        let journalAccId = "exness_\(cleanId)"
        
        await MainActor.run {
            self.syncAccountWithDataStore()
        }
        
        // 2. Fetch live snapshot positions and orders
        let snapshotResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/snapshot", host: clusterHost)
        var snapshotPositions: [[String: Any]] = []
        var allOrders: [[String: Any]] = []
        var seenOrderIds = Set<String>()
        
        if let sJson = snapshotResult.json {
            if let posArr = sJson["positions"] as? [[String: Any]] {
                snapshotPositions = posArr
            }
            if let ordArr = (sJson["orders"] as? [[String: Any]]) ?? (sJson["items"] as? [[String: Any]]) {
                for it in ordArr {
                    let order = (it["order"] as? [String: Any]) ?? it
                    if let oId = order["order_id"] as? String, !seenOrderIds.contains(oId) {
                        seenOrderIds.insert(oId)
                        allOrders.append(order)
                    }
                }
            }
        }
        
        // Fallback: dedicated active positions endpoint if snapshot returned empty positions
        if snapshotPositions.isEmpty {
            let posResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/positions", host: clusterHost)
            if let pJson = posResult.json, let posArr = (pJson["positions"] as? [[String: Any]]) ?? (pJson["items"] as? [[String: Any]]) {
                snapshotPositions = posArr
            }
        }
        
        // Also query active trading orders endpoint (contains active SL/TP orders on open positions)
        let activeOrdersResult = await fetchEndpointData(path: "/v1/trading/accounts/\(cleanId)/orders", host: clusterHost)
        if let aoJson = activeOrdersResult.json, let ordArr = (aoJson["orders"] as? [[String: Any]]) ?? (aoJson["items"] as? [[String: Any]]) {
            for it in ordArr {
                let order = (it["order"] as? [String: Any]) ?? it
                if let oId = order["order_id"] as? String, !seenOrderIds.contains(oId) {
                    seenOrderIds.insert(oId)
                    allOrders.append(order)
                }
            }
        }
        
        // 3. Query Deals and Orders History in safe 14-day chunks (Exness limit: max 30 days per request)
        // Backfill up to 84 days back (6 chunks of 14 days)
        let nowServer = Date().addingTimeInterval(Double(serverTimeOffsetMs) / 1000.0)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        var chunkWindows: [(from: Date, to: Date)] = []
        for i in 0..<6 {
            let chunkEnd = nowServer.addingTimeInterval(-Double(i * 14 * 24 * 3600))
            let chunkStart = nowServer.addingTimeInterval(-Double((i + 1) * 14 * 24 * 3600))
            chunkWindows.append((from: chunkStart, to: chunkEnd))
        }
        
        var allDeals: [[String: Any]] = []
        var seenDealIds = Set<String>()
        
        for w in chunkWindows {
            let fromStr = isoFormatter.string(from: w.from)
            let toStr = isoFormatter.string(from: w.to)
            
            // A. Fetch Deals
            let dealsPath = "/v1/history/accounts/\(cleanId)/deals?from=\(fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr)&to=\(toStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? toStr)"
            let dRes = await fetchEndpointData(path: dealsPath, host: clusterHost)
            if let dJson = dRes.json, let items = dJson["items"] as? [[String: Any]] {
                for it in items {
                    if let deal = it["deal"] as? [String: Any],
                       let dId = deal["deal_id"] as? String,
                       !seenDealIds.contains(dId) {
                        seenDealIds.insert(dId)
                        allDeals.append(deal)
                    }
                }
            }
            
            // B. Fetch Orders
            let ordersPath = "/v1/history/accounts/\(cleanId)/orders?from=\(fromStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromStr)&to=\(toStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? toStr)"
            let oRes = await fetchEndpointData(path: ordersPath, host: clusterHost)
            if let oJson = oRes.json, let items = oJson["items"] as? [[String: Any]] {
                for it in items {
                    if let order = it["order"] as? [String: Any],
                       let oId = order["order_id"] as? String,
                       !seenOrderIds.contains(oId) {
                        seenOrderIds.insert(oId)
                        allOrders.append(order)
                    }
                }
            }
        }
        
        // 4. Map Orders and Positions to SL / TP by position_id and order_id
        func extractSltp(from dict: [String: Any]) -> (sl: Decimal?, tp: Decimal?) {
            let sl = parseDecimal(dict["stop_loss_price"]) ??
                     parseDecimal(dict["stop_loss"]) ??
                     parseDecimal(dict["sl"]) ??
                     parseDecimal(dict["sl_price"])
            let tp = parseDecimal(dict["take_profit_price"]) ??
                     parseDecimal(dict["take_profit"]) ??
                     parseDecimal(dict["tp"]) ??
                     parseDecimal(dict["tp_price"])
            let validSl = (sl != nil && (sl ?? 0) > 0) ? sl : nil
            let validTp = (tp != nil && (tp ?? 0) > 0) ? tp : nil
            return (validSl, validTp)
        }
        
        var positionSltpMap: [String: (sl: Decimal?, tp: Decimal?)] = [:]
        
        // 4.1 Harvest from all Orders (historical + active snapshot)
        for o in allOrders {
            let (sl, tp) = extractSltp(from: o)
            guard sl != nil || tp != nil else { continue }
            if let posId = o["position_id"] as? String, !posId.isEmpty {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
            if let ordId = o["order_id"] as? String, !ordId.isEmpty {
                let existing = positionSltpMap[ordId] ?? (nil, nil)
                positionSltpMap[ordId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
        }
        
        // 4.2 Harvest from Snapshot Positions
        for p in snapshotPositions {
            let (sl, tp) = extractSltp(from: p)
            guard sl != nil || tp != nil else { continue }
            if let posId = p["position_id"] as? String, !posId.isEmpty {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (sl ?? existing.sl, tp ?? existing.tp)
            }
        }
        
        // 4.3 Harvest from Deal close reasons or comments (e.g. "[sl]", "[tp 2715.00]", "stop_loss")
        for d in allDeals {
            guard let posId = d["position_id"] as? String, !posId.isEmpty else { continue }
            let comment = (d["comment"] as? String ?? "").lowercased()
            let reason = (d["reason"] as? String ?? d["close_reason"] as? String ?? "").lowercased()
            let p = parseDecimal(d["price"])
            
            let isSl = comment.contains("[sl") || comment.contains("sl]") || reason.contains("stop_loss") || reason == "sl"
            let isTp = comment.contains("[tp") || comment.contains("tp]") || reason.contains("take_profit") || reason == "tp"
            
            if (isSl || isTp), let price = p, price > 0 {
                let existing = positionSltpMap[posId] ?? (nil, nil)
                positionSltpMap[posId] = (
                    isSl ? (existing.sl ?? price) : existing.sl,
                    isTp ? (existing.tp ?? price) : existing.tp
                )
            }
        }
        
        // 5. Group deals by position_id
        struct DealGroup {
            let positionId: String
            var symbol: String
            var openDeals: [[String: Any]]
            var closeDeals: [[String: Any]]
        }
        
        var groups: [String: DealGroup] = [:]
        for d in allDeals {
            let type = (d["type"] as? String) ?? ""
            if type == "balance" {
                // Deposit or withdrawal transaction
                continue
            }
            guard let posId = d["position_id"] as? String, !posId.isEmpty else { continue }
            let sym = (d["instrument"] as? String) ?? "UNKNOWN"
            
            if groups[posId] == nil {
                groups[posId] = DealGroup(positionId: posId, symbol: sym, openDeals: [], closeDeals: [])
            }
            if type == "open" {
                groups[posId]?.openDeals.append(d)
            } else if type == "close" {
                groups[posId]?.closeDeals.append(d)
            }
        }
        
        // 6. Build atomic Executions and authoritative Trades (with multi-deal and partial close support)
        var directTrades: [Trade] = []
        var newExecutions: [Execution] = []
        let defaultPlaybookId = await MainActor.run { TradeDataStore.shared.defaultPlaybook?.id }
        
        for (posId, g) in groups {
            let sym = g.symbol
            let assetClass = assetClassForSymbol(sym)
            let sltp = positionSltpMap[posId]
            var execIds: [String] = []
            
            // A. Open Deals & Entry (Support multiple open fills/scale-in)
            var totalOpenVolume: Decimal = 0
            var openWeightedSum: Decimal = 0
            var earliestOpenDate: Date = Date()
            var tradeDir: TradeDirection = .long
            
            for (idx, od) in g.openDeals.enumerated() {
                let v = parseDecimal(od["volume"]) ?? 0
                let p = parseDecimal(od["price"]) ?? 0
                let d = parseDate(od["create_time"]) ?? Date()
                let dirStr = (od["direction"] as? String ?? "buy").lowercased()
                let currentDir: TradeDirection = (dirStr == "sell") ? .short : .long
                
                if idx == 0 {
                    tradeDir = currentDir
                    earliestOpenDate = d
                } else if d < earliestOpenDate {
                    earliestOpenDate = d
                }
                
                totalOpenVolume += v
                openWeightedSum += (p * v)
                
                if let dId = od["deal_id"] as? String {
                    let execId = "exness_deal_\(dId)"
                    execIds.append(execId)
                    let fillHash = "\(journalAccId)|\(sym)|\(dirStr)|\(v)|\(p)|\(Int64(d.timeIntervalSince1970 * 1000))"
                    let openFill = Execution(
                        id: execId,
                        accountId: journalAccId,
                        symbol: sym,
                        side: currentDir == .short ? .sell : .buy,
                        quantity: v,
                        price: p,
                        fee: 0,
                        swap: nil,
                        executedAt: d,
                        assetClass: assetClass,
                        source: "exness",
                        contentHash: fillHash
                    )
                    newExecutions.append(openFill)
                }
            }
            
            let entryPrice = totalOpenVolume > 0 ? (openWeightedSum / totalOpenVolume) : (parseDecimal(g.openDeals.first?["price"]) ?? 0)
            let volume = totalOpenVolume > 0 ? totalOpenVolume : (parseDecimal(g.openDeals.first?["volume"]) ?? 0.01)
            
            // B. Close Deals & Exits (Support Partial Closes)
            var totalClosedVolume: Decimal = 0
            var closeWeightedSum: Decimal = 0
            var totalRealizedPnl: Decimal = 0
            var latestCloseDate: Date = earliestOpenDate
            var exits: [ExitAttribution] = []
            
            for cd in g.closeDeals {
                let v = parseDecimal(cd["volume"]) ?? 0
                let p = parseDecimal(cd["price"]) ?? entryPrice
                let d = parseDate(cd["create_time"]) ?? earliestOpenDate
                let exitDir = (cd["direction"] as? String ?? "sell").lowercased()
                
                var dealPnl: Decimal = 0
                if let pObj = cd["profit"] as? [String: Any] {
                    dealPnl = parseDecimal(pObj["amount"]) ?? 0
                }
                
                totalClosedVolume += v
                closeWeightedSum += (p * v)
                totalRealizedPnl += dealPnl
                if d > latestCloseDate {
                    latestCloseDate = d
                }
                
                if let cdId = cd["deal_id"] as? String {
                    let exitExecId = "exness_deal_\(cdId)"
                    execIds.append(exitExecId)
                    let exitHash = "\(journalAccId)|\(sym)|\(exitDir)|\(v)|\(p)|\(Int64(d.timeIntervalSince1970 * 1000))"
                    let exitFill = Execution(
                        id: exitExecId,
                        accountId: journalAccId,
                        symbol: sym,
                        side: tradeDir == .short ? .buy : .sell,
                        quantity: v,
                        price: p,
                        fee: 0,
                        swap: nil,
                        executedAt: d,
                        assetClass: assetClass,
                        source: "exness",
                        contentHash: exitHash
                    )
                    newExecutions.append(exitFill)
                    
                    exits.append(ExitAttribution(
                        executionId: exitExecId,
                        grossPnl: dealPnl,
                        quantity: v
                    ))
                }
            }
            
            let remainingOpenVolume = max(Decimal(0), volume - totalClosedVolume)
            let isFullyClosed = remainingOpenVolume <= Decimal(0.000001) && totalClosedVolume > 0
            let avgExit = totalClosedVolume > 0 ? (closeWeightedSum / totalClosedVolume) : nil
            let status: TradeStatus = isFullyClosed
                ? (totalRealizedPnl > 0 ? .win : (totalRealizedPnl < 0 ? .loss : .breakeven))
                : .open
            let durMs = isFullyClosed ? Int64(max(0, latestCloseDate.timeIntervalSince(earliestOpenDate) * 1000)) : nil
            let finalClosedAt = isFullyClosed ? latestCloseDate : nil
            
            let trade = Trade(
                key: "exness_\(posId)",
                accountId: journalAccId,
                symbol: sym,
                assetClass: assetClass,
                direction: tradeDir,
                status: status,
                openedAt: earliestOpenDate,
                closedAt: finalClosedAt,
                quantity: volume,
                openQuantity: isFullyClosed ? 0 : remainingOpenVolume,
                avgEntry: entryPrice,
                avgExit: avgExit,
                grossPnl: totalRealizedPnl,
                fees: 0,
                swap: nil,
                netPnl: totalRealizedPnl,
                executionCount: execIds.count,
                executionIds: execIds,
                exits: exits,
                durationMs: durMs,
                playbookId: defaultPlaybookId,
                stopLoss: sltp?.sl,
                profitTarget: sltp?.tp
            )
            directTrades.append(trade)
        }
        
        // 7. Parse active Snapshot positions (if not already covered in deals)
        for p in snapshotPositions {
            guard let posId = p["position_id"] as? String, !posId.isEmpty else { continue }
            let (slFromPos, tpFromPos) = extractSltp(from: p)
            let sltp = positionSltpMap[posId]
            let resolvedSl = slFromPos ?? sltp?.sl
            let resolvedTp = tpFromPos ?? sltp?.tp
            
            if let existingIdx = directTrades.firstIndex(where: { $0.key == "exness_\(posId)" }) {
                if let liveVol = parseDecimal(p["volume"]), liveVol > 0 {
                    directTrades[existingIdx].openQuantity = liveVol
                    directTrades[existingIdx].status = .open
                    directTrades[existingIdx].closedAt = nil
                }
                if let sl = resolvedSl, directTrades[existingIdx].stopLoss == nil {
                    directTrades[existingIdx].stopLoss = sl
                }
                if let tp = resolvedTp, directTrades[existingIdx].profitTarget == nil {
                    directTrades[existingIdx].profitTarget = tp
                }
                continue
            }
            
            let sym = (p["instrument"] as? String) ?? "UNKNOWN"
            let assetClass = assetClassForSymbol(sym)
            let dirStr = (p["direction"] as? String ?? "buy").lowercased()
            let tradeDir: TradeDirection = (dirStr == "sell") ? .short : .long
            let price = parseDecimal(p["open_price"]) ?? 0
            let volume = parseDecimal(p["volume"]) ?? 0.01
            let openDate = parseDate(p["create_time"]) ?? Date()
            
            let execId = "exness_pos_\(posId)"
            let fillHash = "\(journalAccId)|\(sym)|\(dirStr)|\(volume)|\(price)|\(Int64(openDate.timeIntervalSince1970 * 1000))"
            let fill = Execution(
                id: execId,
                accountId: journalAccId,
                symbol: sym,
                side: tradeDir == .short ? .sell : .buy,
                quantity: volume,
                price: price,
                fee: 0,
                swap: nil,
                executedAt: openDate,
                assetClass: assetClass,
                source: "exness",
                contentHash: fillHash
            )
            newExecutions.append(fill)
            
            let openTrade = Trade(
                key: "exness_\(posId)",
                accountId: journalAccId,
                symbol: sym,
                assetClass: assetClass,
                direction: tradeDir,
                status: .open,
                openedAt: openDate,
                closedAt: nil,
                quantity: volume,
                openQuantity: volume,
                avgEntry: price,
                avgExit: nil,
                grossPnl: 0,
                fees: 0,
                swap: nil,
                netPnl: 0,
                executionCount: 1,
                executionIds: [execId],
                exits: [],
                durationMs: nil,
                playbookId: defaultPlaybookId,
                stopLoss: resolvedSl,
                profitTarget: resolvedTp
            )
            directTrades.append(openTrade)
        }
        
        // 8. Ingest into TradeDataStore
        await MainActor.run {
            let dataStore = TradeDataStore.shared
            
            // A. Merge direct trades with broker-reported P&L
            if !directTrades.isEmpty {
                var currentTrades = dataStore.trades
                let defaultPbId = dataStore.defaultPlaybook?.id
                for t in directTrades {
                    var tradeToMerge = t
                    if let idx = currentTrades.firstIndex(where: { $0.key == tradeToMerge.key || $0.id == tradeToMerge.id }) {
                        let existing = currentTrades[idx]
                        
                        // 1. Playbook
                        if let existingPbId = existing.playbookId, !existingPbId.isEmpty {
                            tradeToMerge.playbookId = existingPbId
                        } else if tradeToMerge.playbookId == nil {
                            tradeToMerge.playbookId = defaultPbId
                        }
                        
                        // 2. User Annotations (Notes, Tags, Mistakes, Rating, ReviewedAt)
                        if let existingNotes = existing.notes, !existingNotes.isEmpty {
                            tradeToMerge.notes = existingNotes
                        }
                        if !existing.tags.isEmpty {
                            tradeToMerge.tags = Array(Set(existing.tags + tradeToMerge.tags))
                        }
                        if !existing.mistakes.isEmpty {
                            tradeToMerge.mistakes = existing.mistakes
                        }
                        if let r = existing.rating {
                            tradeToMerge.rating = r
                        }
                        if let rev = existing.reviewedAt {
                            tradeToMerge.reviewedAt = rev
                        }
                        
                        // 3. SL / TP Priority:
                        // Priority 1: Broker-reported SL/TP (tradeToMerge.stopLoss / profitTarget from Exness)
                        // Priority 2: User manually entered SL/TP (existing.stopLoss / existing.profitTarget)
                        if tradeToMerge.stopLoss == nil || (tradeToMerge.stopLoss ?? 0) <= 0 {
                            tradeToMerge.stopLoss = existing.stopLoss
                        }
                        if tradeToMerge.profitTarget == nil || (tradeToMerge.profitTarget ?? 0) <= 0 {
                            tradeToMerge.profitTarget = existing.profitTarget
                        }
                        
                        currentTrades[idx] = tradeToMerge
                    } else {
                        if tradeToMerge.playbookId == nil {
                            tradeToMerge.playbookId = defaultPbId
                        }
                        currentTrades.append(tradeToMerge)
                    }
                }
                dataStore.trades = currentTrades
                dataStore.deduplicateTrades()
            }
            
            // B. Import execution fills
            if !newExecutions.isEmpty {
                dataStore.importExecutions(accountId: journalAccId, newExecutions: newExecutions)
            }
            
            // C. Invalidate performance caches and persist
            if !directTrades.isEmpty || !newExecutions.isEmpty {
                if dataStore.selectedAccountId.isEmpty || dataStore.selectedAccountId == "default-acc" {
                    dataStore.selectedAccountId = journalAccId
                }
                dataStore.invalidatePerformanceCaches()
                dataStore.performSaveToDiskAsync()
                dataStore.objectWillChange.send()
            }
            
            let total = directTrades.count
            self.syncedTradesCount = total
            
            let formattedBal = Formatters.formatCurrency(self.balance, currency: self.currency)
            let accLabel = self.accountName.isEmpty ? cleanId : "'\(self.accountName)'"
            
            if total > 0 {
                self.lastSyncSummary = "Connected • Balance: \(formattedBal) • \(total) trades synced"
            } else {
                self.lastSyncSummary = "Connected • Balance: \(formattedBal) • Account \(accLabel) synced (no recent deals in 28-day window)"
            }
        }
        
        let now = Date()
        UserDefaults.standard.set(now, forKey: kExnessLastSync)
        await MainActor.run {
            self.lastSyncDate = now
            self.isConnected = true
        }
        
        // Asynchronously backup to Supabase Cloud in the background without blocking UI
        if SupabaseService.shared.isConfigured {
            Task.detached(priority: .background) {
                if !directTrades.isEmpty {
                    _ = try? await SupabaseService.shared.upsertTrades(directTrades)
                }
                if !newExecutions.isEmpty {
                    _ = try? await SupabaseService.shared.upsertExecutions(newExecutions)
                }
            }
        }
        
        return self.syncedTradesCount
    }
}
