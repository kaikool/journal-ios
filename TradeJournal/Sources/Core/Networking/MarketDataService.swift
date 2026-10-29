import Foundation

/// Market data service providing historical candlestick data for Trade Replay and MAE/MFE excursions.
/// Domain specification matching core web repository
public final class MarketDataService: Sendable {
    public static let shared = MarketDataService()
    
    private let binanceBaseUrls = [
        "https://data-api.binance.vision",
        "https://api.binance.com",
        "https://api1.binance.com",
        "https://api3.binance.com"
    ]
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - 1. Symbol Normalization (Ported 1:1 from `market-normalize.ts`)
    
    public func normalizeMarketSymbol(symbol: String, provider: String) -> String {
        guard !symbol.isEmpty else { return "" }
        var clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Strip common MT4/MT5/cTrader prefixes and suffixes using AssetContractEngine canonicalization
        clean = clean.replacingOccurrences(of: "^#", with: "", options: .regularExpression)
        let canonical = AssetContractEngine.canonicalSymbol(clean)
        if !canonical.isEmpty {
            clean = canonical
        }
        clean = clean.replacingOccurrences(
            of: "(\\.[a-z0-9]+|\\+|#|_sb|_i|_pro|-m)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        if provider == "oanda" {
            // Preserve standard BASE_QUOTE format (e.g. XAU_USD, EUR_USD, US30_USD)
            if clean.contains("_") { return clean }
            
            let aliases: [String: String] = [
                "GOLD": "XAU_USD",
                "SILVER": "XAG_USD",
                "OIL": "WTICO_USD",
                "WTI": "WTICO_USD",
                "USOIL": "WTICO_USD",
                "BRENT": "BCO_USD",
                "UKOIL": "BCO_USD",
                "US30": "US30_USD",
                "DJ30": "US30_USD",
                "DJI": "US30_USD",
                "NAS100": "NAS100_USD",
                "USTEC": "NAS100_USD",
                "NDX": "NAS100_USD",
                "SPX500": "SPX500_USD",
                "US500": "SPX500_USD",
                "SP500": "SPX500_USD",
                "GER30": "DE30_EUR",
                "GER40": "DE30_EUR",
                "DAX": "DE30_EUR"
            ]
            if let alias = aliases[clean] { return alias }
            
            clean = clean.replacingOccurrences(of: "[/\\-\\.]", with: "", options: .regularExpression)
            
            // 6-character Forex/Metal pairs: XAUUSD -> XAU_USD, EURUSD -> EUR_USD
            if clean.count == 6 {
                let base = String(clean.prefix(3))
                let quote = String(clean.suffix(3))
                return "\(base)_\(quote)"
            }
            
            if clean.hasSuffix("USD") && clean.count > 3 {
                let base = String(clean.dropLast(3))
                return "\(base)_USD"
            }
            return clean
        }
        
        if provider == "binance" {
            clean = clean.replacingOccurrences(of: "[/\\-_\\.]", with: "", options: .regularExpression)
            
            // Handle XBT alias for BTC (used by Kraken / BitMEX / certain prop firms)
            if clean.hasPrefix("XBT") {
                clean = "BTC" + clean.dropFirst(3)
            }
            
            let singleCrypto = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "NEAR", "LTC"]
            if singleCrypto.contains(clean) {
                return "\(clean)USDT"
            }
            
            // Map broker USD crypto pairs (e.g. BTCUSD, ETHUSD, SOLUSD, XRPUSD) to liquid Binance USDT spot pairs
            if clean.hasSuffix("USD") && !clean.hasSuffix("USDT") {
                let base = String(clean.dropLast(3))
                return "\(base)USDT"
            }
            
            return clean
        }
        
        return clean
    }
    
    public func detectProviderForSymbol(symbol: String, assetClass: String? = nil) -> String {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cryptoTokens = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "NEAR", "LTC", "USDT", "XBT"]
        
        if let asset = assetClass?.lowercased(), asset.contains("crypto") {
            return "binance"
        }
        
        for token in cryptoTokens {
            if clean.contains(token) {
                return "binance"
            }
        }
        
        return "oanda"
    }
    
    // MARK: - 2. Binance Public Spot Candlesticks (No API Key Required)
    
    /// Fetches historical candlesticks from Binance Public API with resilient endpoint failover
    public func fetchBinanceBars(
        symbol: String,
        interval: String = "15m",
        startTimeMs: Int64? = nil,
        endTimeMs: Int64? = nil,
        limit: Int = 1000
    ) async throws -> [MarketBar] {
        let normalized = normalizeMarketSymbol(symbol: symbol, provider: "binance")
        
        var lastError: Error?
        for baseUrl in binanceBaseUrls {
            guard var components = URLComponents(string: "\(baseUrl)/api/v3/klines") else { continue }
            
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "symbol", value: normalized),
                URLQueryItem(name: "interval", value: interval),
                URLQueryItem(name: "limit", value: String(min(limit, 1000)))
            ]
            
            if let s = startTimeMs {
                queryItems.append(URLQueryItem(name: "startTime", value: String(s)))
            }
            if let e = endTimeMs {
                queryItems.append(URLQueryItem(name: "endTime", value: String(e)))
            }
            
            components.queryItems = queryItems
            guard let url = components.url else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 8
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }
                
                guard let rawArray = try JSONSerialization.jsonObject(with: data) as? [[Any]], !rawArray.isEmpty else {
                    continue
                }
                
                var bars: [MarketBar] = []
                for item in rawArray {
                    guard item.count >= 6,
                          let timeNum = item[0] as? NSNumber else {
                        continue
                    }
                    
                    let openStr = (item[1] as? String) ?? "\(item[1])"
                    let highStr = (item[2] as? String) ?? "\(item[2])"
                    let lowStr = (item[3] as? String) ?? "\(item[3])"
                    let closeStr = (item[4] as? String) ?? "\(item[4])"
                    let volStr = (item[5] as? String) ?? "\(item[5])"
                    
                    guard let o = Decimal(string: openStr),
                          let h = Decimal(string: highStr),
                          let l = Decimal(string: lowStr),
                          let c = Decimal(string: closeStr) else {
                        continue
                    }
                    
                    let v = Decimal(string: volStr) ?? 0
                    bars.append(MarketBar(
                        timestamp: timeNum.int64Value,
                        open: o,
                        high: h,
                        low: l,
                        close: c,
                        volume: v
                    ))
                }
                
                if !bars.isEmpty {
                    return validateBars(bars)
                }
            } catch {
                lastError = error
            }
        }
        
        if let err = lastError {
            throw err
        }
        return []
    }
    
    // MARK: - 3. OANDA v20 Midpoint Candlesticks (Optimized per OANDA v20 REST Specification)
    
    public func fetchOandaBars(
        symbol: String,
        apiKey: String,
        accountId: String,
        environment: String,
        from: Date,
        to: Date,
        resolution: String = "15m"
    ) async throws -> [MarketBar] {
        let normalized = normalizeMarketSymbol(symbol: symbol, provider: "oanda")
        let base = environment.lowercased() == "live" ? "https://api-fxtrade.oanda.com" : "https://api-fxpractice.oanda.com"
        
        let granularityMap: [String: String] = [
            "1m": "M1", "5m": "M5", "15m": "M15", "30m": "M30", "1h": "H1", "4h": "H4", "1d": "D", "d1": "D"
        ]
        let granularity = granularityMap[resolution] ?? "M15"
        
        // Granularity in seconds to guard against OANDA's hard limit of 5,000 candles per query
        let granSeconds: Double = {
            switch resolution.lowercased() {
            case "1m": return 60
            case "5m": return 300
            case "15m": return 900
            case "30m": return 1800
            case "1h": return 3600
            case "4h": return 14400
            case "1d", "d1": return 86400
            default: return 900
            }
        }()
        
        // Clamp timeframe so count never exceeds 4,000 candles (guaranteed safety margin below 5,000)
        let maxSpan = granSeconds * 4000.0
        let clampedFrom = (to.timeIntervalSince(from) > maxSpan) ? to.addingTimeInterval(-maxSpan) : from
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fromStr = isoFormatter.string(from: clampedFrom)
        let toStr = isoFormatter.string(from: to)
        
        // Canonical OANDA v20 endpoint: GET /v3/instruments/{instrument}/candles
        // This endpoint does not require account ID in the URL path, preventing 404 errors from account scope mismatches
        guard var components = URLComponents(string: "\(base)/v3/instruments/\(normalized)/candles") else {
            throw URLError(.badURL)
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "from", value: fromStr),
            URLQueryItem(name: "to", value: toStr),
            URLQueryItem(name: "granularity", value: granularity),
            // price=M requests Midpoint only, cutting response JSON payload by ~66% compared to MBA
            URLQueryItem(name: "price", value: "M"),
            // smooth=false preserves genuine wick highs/lows for precise SMC sweeps and FVGs
            URLQueryItem(name: "smooth", value: "false"),
            URLQueryItem(name: "includeFirst", value: "true")
        ]
        
        if granularity == "D" {
            // Standard Forex daily rollover: 17:00 New York (5 PM EST)
            queryItems.append(URLQueryItem(name: "dailyAlignment", value: "17"))
            queryItems.append(URLQueryItem(name: "alignmentTimezone", value: "America/New_York"))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 12
        
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            // OANDA rate limit: read Retry-After header or pause 1.2s exponential backoff and retry once
            let retrySec = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1.2
            try? await Task.sleep(nanoseconds: UInt64(retrySec * 1_000_000_000))
            (data, response) = try await session.data(for: request)
        }
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "OANDA error"
            throw NSError(domain: "OandaAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candles = json["candles"] as? [[String: Any]] else {
            throw NSError(domain: "OandaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid candles structure from OANDA"])
        }
        
        var bars: [MarketBar] = []
        for c in candles {
            guard let timeStr = c["time"] as? String,
                  let date = parseOandaDate(timeStr, isoFormatter: isoFormatter),
                  let mid = c["mid"] as? [String: Any],
                  let oStr = mid["o"] as? String,
                  let hStr = mid["h"] as? String,
                  let lStr = mid["l"] as? String,
                  let cStr = mid["c"] as? String,
                  let o = Decimal(string: oStr),
                  let h = Decimal(string: hStr),
                  let l = Decimal(string: lStr),
                  let close = Decimal(string: cStr) else {
                continue
            }
            
            let vol = (c["volume"] as? NSNumber)?.intValue ?? 0
            bars.append(MarketBar(
                timestamp: Int64(date.timeIntervalSince1970 * 1000),
                open: o,
                high: h,
                low: l,
                close: close,
                volume: Decimal(vol)
            ))
        }
        
        return validateBars(bars)
    }
    
    // MARK: - 3b. Robust OANDA Date Parser (Handles RFC3339 nanoseconds & UNIX epoch)
    private func parseOandaDate(_ str: String, isoFormatter: ISO8601DateFormatter) -> Date? {
        if let d = isoFormatter.date(from: str) { return d }
        if let d = ISO8601DateFormatter().date(from: str) { return d }
        if let dotIndex = str.firstIndex(of: ".") {
            let remaining = str[str.index(after: dotIndex)...]
            let endCharIndex = remaining.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) ?? remaining.endIndex
            let prefix = str[...dotIndex]
            let frac = remaining[..<endCharIndex]
            let suffix = remaining[endCharIndex...]
            let clampedFrac = frac.prefix(3)
            let normalized = "\(prefix)\(clampedFrac)\(suffix)"
            if let d = isoFormatter.date(from: normalized) { return d }
            if let d = ISO8601DateFormatter().date(from: normalized) { return d }
        }
        if let sec = Double(str) {
            return Date(timeIntervalSince1970: sec)
        }
        return nil
    }
    
    // MARK: - 3c. Diagnostic Connection Tests
    
    public func testOandaConnection(
        apiKey: String,
        accountId: String,
        environment: String
    ) async -> (success: Bool, message: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAcc = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanAcc.isEmpty else {
            return (false, "Please enter both OANDA Access Token and v20 Account ID.")
        }
        
        let base = environment.lowercased() == "live" ? "https://api-fxtrade.oanda.com" : "https://api-fxpractice.oanda.com"
        // Test account summary first per OANDA v20 REST specification
        let summaryUrlStr = "\(base)/v3/accounts/\(cleanAcc)/summary"
        guard let summaryUrl = URL(string: summaryUrlStr) else {
            return (false, "Invalid OANDA URL.")
        }
        
        var request = URLRequest(url: summaryUrl)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "No response received from OANDA server.")
            }
            if (200...299).contains(http.statusCode) {
                var currencyStr = ""
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let acc = json["account"] as? [String: Any],
                   let cur = acc["currency"] as? String {
                    currencyStr = " [\(cur)]"
                }
                return (true, "OANDA v20 connected! Account \(cleanAcc)\(currencyStr) (\(environment)) is verified.")
            } else if http.statusCode == 401 {
                return (false, "Error 401: Invalid or expired OANDA Access Token.")
            } else if http.statusCode == 404 {
                return (false, "Error 404: Account ID '\(cleanAcc)' not found in \(environment) environment.")
            } else {
                let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errMsg = errJson?["errorMessage"] as? String ?? (String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
                return (false, "OANDA returned error: \(errMsg)")
            }
        } catch {
            return (false, "OANDA connection error: \(error.localizedDescription)")
        }
    }
    
    public func testBinanceConnection() async -> (success: Bool, message: String) {
        do {
            let bars = try await fetchBinanceBars(symbol: "BTCUSDT", interval: "1m", limit: 1)
            if !bars.isEmpty {
                return (true, "Binance Public Spot API connected. Crypto candles ready.")
            } else {
                return (false, "Binance returned no candle data.")
            }
        } catch {
            return (false, "Binance connection error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 4. Validation & De-duplication
    
    /// Deduplicates and chronologically sorts market candle bars
    public func validateBars(_ bars: [MarketBar]) -> [MarketBar] {
        var unique: [Int64: MarketBar] = [:]
        for bar in bars {
            unique[bar.timestamp] = bar
        }
        return unique.values.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - 5. Unified Trade Candles Fetcher
    
    /// Fetches market candle bars matching the trade timeframe across active providers with multi-tier caching
    public func fetchBarsForTrade(
        trade: Trade,
        config: MarketConnectionConfig,
        resolution: String = "15m",
        forceRefresh: Bool = false
    ) async throws -> (provider: String, bars: [MarketBar]) {
        let isClosed = (trade.status != .open)
        let provider = detectProviderForSymbol(symbol: trade.symbol)
        let providerTag = provider == "binance" ? "Binance Spot" : "OANDA v20"
        
        // 1. Check multi-tier cache (instant 0ms lookup)
        if !forceRefresh,
           let cached = MarketDataCacheStore.shared.getTradeBars(tradeId: trade.id, resolution: resolution, isClosed: isClosed),
           !cached.isEmpty {
            let tag = isClosed ? "Historical Cache" : "Cache"
            return ("\(providerTag) (\(tag))", cached)
        }
        
        let coalescingKey = "trade_\(trade.id)_\(resolution)"
        
        do {
            let fetchedBars = try await MarketDataCacheStore.shared.runCoalesced(key: coalescingKey) { [self] in
                // Check cache again inside coalescing task
                if !forceRefresh,
                   let cached = MarketDataCacheStore.shared.getTradeBars(tradeId: trade.id, resolution: resolution, isClosed: isClosed),
                   !cached.isEmpty {
                    return cached
                }
                
                let resMs = MarketResolution(rawValue: resolution)?.durationMs ?? 900_000
                // Pre-buffer: 120 bars before entry (guarantees ample historical context for SMC swing points, liquidity pools, and RSI-14)
                let preBuffer = Double(resMs * 120) / 1000.0
                // Post-buffer: 30 bars after trade close to evaluate post-trade reaction and MFE
                let postBuffer = Double(resMs * 30) / 1000.0
                
                let openTime = trade.openedAt.addingTimeInterval(-preBuffer)
                let closeTime: Date = {
                    if trade.status == .open || trade.closedAt == nil {
                        return Date()
                    } else {
                        return min(Date(), trade.closedAt!.addingTimeInterval(postBuffer))
                    }
                }()
                
                if provider == "binance" {
                    let startMs = Int64(openTime.timeIntervalSince1970 * 1000)
                    let endMs = Int64(closeTime.timeIntervalSince1970 * 1000)
                    
                    var bars = (try? await fetchBinanceBars(
                        symbol: trade.symbol,
                        interval: resolution,
                        startTimeMs: startMs,
                        endTimeMs: endMs
                    )) ?? []
                    
                    if bars.isEmpty {
                        let cleanRaw = trade.symbol.replacingOccurrences(of: "[/\\-_\\.]", with: "", options: .regularExpression)
                        bars = (try? await fetchBinanceBars(
                            symbol: cleanRaw,
                            interval: resolution,
                            startTimeMs: startMs,
                            endTimeMs: endMs
                        )) ?? []
                    }
                    
                    if !bars.isEmpty {
                        let valid = validateBars(bars)
                        MarketDataCacheStore.shared.saveTradeBars(valid, tradeId: trade.id, resolution: resolution, isClosed: isClosed)
                        return valid
                    }
                    
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No candlestick data available on Binance for \(trade.symbol)."]
                    )
                } else if !config.oandaApiKey.isEmpty {
                    let bars = try await fetchOandaBars(
                        symbol: trade.symbol,
                        apiKey: config.oandaApiKey,
                        accountId: config.oandaAccountId,
                        environment: config.oandaEnvironment,
                        from: openTime,
                        to: closeTime,
                        resolution: resolution
                    )
                    let valid = validateBars(bars)
                    MarketDataCacheStore.shared.saveTradeBars(valid, tradeId: trade.id, resolution: resolution, isClosed: isClosed)
                    return valid
                } else {
                    let binanceBars = try? await fetchBinanceBars(
                        symbol: "\(trade.symbol)USDT",
                        interval: resolution,
                        startTimeMs: Int64(openTime.timeIntervalSince1970 * 1000),
                        endTimeMs: Int64(closeTime.timeIntervalSince1970 * 1000)
                    )
                    if let bb = binanceBars, !bb.isEmpty {
                        let valid = validateBars(bb)
                        MarketDataCacheStore.shared.saveTradeBars(valid, tradeId: trade.id, resolution: resolution, isClosed: isClosed)
                        return valid
                    }
                    
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Instrument \(trade.symbol) is a Forex/CFD symbol. Please configure your OANDA Access Token in Settings → Market Data to stream historical candles."]
                    )
                }
            }
            
            return (providerTag, fetchedBars)
        } catch {
            // Stale / Offline Cache Fallback
            if let stale = MarketDataCacheStore.shared.getStaleTradeBars(tradeId: trade.id, resolution: resolution), !stale.isEmpty {
                return ("\(providerTag) (Offline Cache)", stale)
            }
            throw error
        }
    }
    
    // MARK: - 5b. Recent OANDA Candlesticks by Count (Pre-Trade Forward Analysis)
    public func fetchRecentOandaBars(
        symbol: String,
        apiKey: String,
        accountId: String,
        environment: String,
        resolution: String = "15m",
        count: Int = 50
    ) async throws -> [MarketBar] {
        let normalized = normalizeMarketSymbol(symbol: symbol, provider: "oanda")
        let base = environment.lowercased() == "live" ? "https://api-fxtrade.oanda.com" : "https://api-fxpractice.oanda.com"
        
        let granularityMap: [String: String] = [
            "1m": "M1", "5m": "M5", "15m": "M15", "30m": "M30", "1h": "H1", "4h": "H4", "1d": "D", "d1": "D"
        ]
        let granularity = granularityMap[resolution] ?? "M15"
        let countClamped = max(1, min(500, count))
        
        guard var components = URLComponents(string: "\(base)/v3/instruments/\(normalized)/candles") else {
            throw URLError(.badURL)
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "count", value: String(countClamped)),
            URLQueryItem(name: "granularity", value: granularity),
            URLQueryItem(name: "price", value: "M"),
            URLQueryItem(name: "smooth", value: "false")
        ]
        
        if granularity == "D" {
            queryItems.append(URLQueryItem(name: "dailyAlignment", value: "17"))
            queryItems.append(URLQueryItem(name: "alignmentTimezone", value: "America/New_York"))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 10
        
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let retrySec = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1.2
            try? await Task.sleep(nanoseconds: UInt64(retrySec * 1_000_000_000))
            (data, response) = try await session.data(for: request)
        }
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "OANDA error"
            throw NSError(domain: "OandaAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candles = json["candles"] as? [[String: Any]] else {
            throw NSError(domain: "OandaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid candles structure from OANDA"])
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var bars: [MarketBar] = []
        for c in candles {
            guard let timeStr = c["time"] as? String,
                  let date = parseOandaDate(timeStr, isoFormatter: isoFormatter),
                  let mid = c["mid"] as? [String: Any],
                  let oStr = mid["o"] as? String,
                  let hStr = mid["h"] as? String,
                  let lStr = mid["l"] as? String,
                  let cStr = mid["c"] as? String,
                  let o = Decimal(string: oStr),
                  let h = Decimal(string: hStr),
                  let l = Decimal(string: lStr),
                  let close = Decimal(string: cStr) else {
                continue
            }
            
            let vol = (c["volume"] as? NSNumber)?.intValue ?? 0
            bars.append(MarketBar(
                timestamp: Int64(date.timeIntervalSince1970 * 1000),
                open: o,
                high: h,
                low: l,
                close: close,
                volume: Decimal(vol)
            ))
        }
        
        return validateBars(bars)
    }
    
    // MARK: - 6. Symbol Candlesticks Fetcher (Pre-Trade Forward Analysis with Adaptive TTL Caching)
    public func fetchBarsForSymbol(
        symbol: String,
        config: MarketConnectionConfig,
        resolution: String = "15m",
        count: Int = 50,
        forceRefresh: Bool = false
    ) async throws -> (provider: String, bars: [MarketBar]) {
        let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let provider = detectProviderForSymbol(symbol: cleanSymbol)
        let providerTag = provider == "binance" ? "Binance Spot" : "OANDA v20"
        
        // 1. Check adaptive TTL cache (0ms instant lookup)
        if !forceRefresh,
           let cached = MarketDataCacheStore.shared.getSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count),
           !cached.isEmpty {
            return ("\(providerTag) (Cached)", cached)
        }
        
        let coalescingKey = "sym_\(cleanSymbol)_\(resolution)_\(count)"
        
        do {
            let fetchedBars = try await MarketDataCacheStore.shared.runCoalesced(key: coalescingKey) { [self] in
                // Check cache again inside coalescing task
                if !forceRefresh,
                   let cached = MarketDataCacheStore.shared.getSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count),
                   !cached.isEmpty {
                    return cached
                }
                
                if provider == "binance" {
                    let normalized = normalizeMarketSymbol(symbol: cleanSymbol, provider: "binance")
                    var bars = (try? await fetchBinanceBars(symbol: normalized, interval: resolution, limit: count)) ?? []
                    if bars.isEmpty {
                        bars = (try? await fetchBinanceBars(symbol: cleanSymbol, interval: resolution, limit: count)) ?? []
                    }
                    if !bars.isEmpty {
                        let valid = validateBars(bars)
                        MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: count)
                        return valid
                    }
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No candlestick data available on Binance for \(cleanSymbol)."]
                    )
                } else if !config.oandaApiKey.isEmpty || KeychainManager.get(forKey: "oanda_api_key") != nil || AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") != nil {
                    let effectiveKey = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? config.oandaApiKey
                    let effectiveAcc = UserDefaults.standard.string(forKey: "oanda_account_id") ?? AppSecretsLoader.loadSecret(named: "OANDA_ACCOUNT_ID") ?? config.oandaAccountId
                    let bars = try await fetchRecentOandaBars(
                        symbol: cleanSymbol,
                        apiKey: effectiveKey,
                        accountId: effectiveAcc,
                        environment: config.oandaEnvironment,
                        resolution: resolution,
                        count: count
                    )
                    let valid = validateBars(bars)
                    MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: count)
                    return valid
                } else {
                    // Binance USDT Fallback
                    let binanceBars = try? await fetchBinanceBars(
                        symbol: "\(cleanSymbol)USDT",
                        interval: resolution,
                        limit: count
                    )
                    if let bb = binanceBars, !bb.isEmpty {
                        let valid = validateBars(bb)
                        MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: count)
                        return valid
                    }
                    
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Instrument \(cleanSymbol) is a Forex/CFD symbol. Please configure your OANDA Access Token in Settings → Market Data to stream live candles."]
                    )
                }
            }
            
            return (providerTag, fetchedBars)
        } catch {
            // Stale / Offline Cache Fallback
            if let stale = MarketDataCacheStore.shared.getStaleSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count), !stale.isEmpty {
                return ("\(providerTag) (Offline Cache)", stale)
            }
            throw error
        }
    }
}
