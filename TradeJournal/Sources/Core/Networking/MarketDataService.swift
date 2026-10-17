import Foundation

/// Market data service providing historical candlestick data for Trade Replay and MAE/MFE excursions.
/// Domain specification matching core web repository
public final class MarketDataService: Sendable {
    public static let shared = MarketDataService()
    
    private let binanceBaseUrl = "https://data-api.binance.vision"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - 1. Symbol Normalization (Ported 1:1 from `market-normalize.ts`)
    
    public func normalizeMarketSymbol(symbol: String, provider: String) -> String {
        guard !symbol.isEmpty else { return "" }
        var clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Strip common MT4/MT5/cTrader prefixes and suffixes
        // VD: XAUUSD.m, XAUUSDpro, XAUUSDraw, EURUSD+, #EURUSD, EURUSD_i, EURUSD_sb
        clean = clean.replacingOccurrences(of: "^#", with: "", options: .regularExpression)
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
            let singleCrypto = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "NEAR", "LTC"]
            if singleCrypto.contains(clean) {
                return "\(clean)USDT"
            }
            return clean
        }
        
        return clean
    }
    
    public func detectProviderForSymbol(symbol: String, assetClass: String? = nil) -> String {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cryptoTokens = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "NEAR", "LTC", "USDT"]
        
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
    
    /// Fetches historical candlesticks from Binance Public API
    public func fetchBinanceBars(
        symbol: String,
        interval: String = "15m",
        startTimeMs: Int64? = nil,
        endTimeMs: Int64? = nil,
        limit: Int = 1000
    ) async throws -> [MarketBar] {
        let normalized = normalizeMarketSymbol(symbol: symbol, provider: "binance")
        guard var components = URLComponents(string: "\(binanceBaseUrl)/api/v3/klines") else {
            throw URLError(.badURL)
        }
        
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
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "BinanceAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Binance error: \(errorText)"])
        }
        
        // Parsing Binance raw kline array:
        // [ [ 0: openTime, 1: open, 2: high, 3: low, 4: close, 5: volume, ... ], ... ]
        guard let rawArray = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw NSError(domain: "BinanceAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid klines array from Binance"])
        }
        
        var bars: [MarketBar] = []
        for item in rawArray {
            guard item.count >= 6,
                  let timeNum = item[0] as? NSNumber,
                  let openStr = item[1] as? String,
                  let highStr = item[2] as? String,
                  let lowStr = item[3] as? String,
                  let closeStr = item[4] as? String,
                  let volStr = item[5] as? String,
                  let o = Decimal(string: openStr),
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
        
        return validateBars(bars)
    }
    
    // MARK: - 3. OANDA v20 Midpoint Candlesticks
    
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
            "1m": "M1", "5m": "M5", "15m": "M15", "1h": "H1", "1d": "D"
        ]
        let granularity = granularityMap[resolution] ?? "M15"
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fromStr = isoFormatter.string(from: from)
        let toStr = isoFormatter.string(from: to)
        
        let urlStr = "\(base)/v3/accounts/\(accountId)/instruments/\(normalized)/candles?from=\(fromStr)&to=\(toStr)&granularity=\(granularity)&price=M&smooth=false&includeFirst=true"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        
        let (data, response) = try await session.data(for: request)
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
                  let date = isoFormatter.date(from: timeStr) ?? ISO8601DateFormatter().date(from: timeStr),
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
    
    // MARK: - 3b. Diagnostic Connection Tests
    
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
        let urlStr = "\(base)/v3/accounts/\(cleanAcc)/instruments/EUR_USD/candles?count=1&granularity=M1&price=M"
        guard let url = URL(string: urlStr) else {
            return (false, "Invalid OANDA URL.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "No response received from OANDA server.")
            }
            if (200...299).contains(http.statusCode) {
                return (true, "OANDA v20 connection successful! Account \(cleanAcc) (\(environment)) is ready for candle data.")
            } else if http.statusCode == 401 {
                return (false, "Error 401: Invalid or expired OANDA Access Token.")
            } else if http.statusCode == 404 {
                return (false, "Error 404: Account ID '\(cleanAcc)' not found in \(environment). environment.")
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
    
    /// Internal domain documentation
    public func validateBars(_ bars: [MarketBar]) -> [MarketBar] {
        var unique: [Int64: MarketBar] = [:]
        for bar in bars {
            unique[bar.timestamp] = bar
        }
        return unique.values.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - 5. Unified Trade Candles Fetcher
    
    /// Internal domain documentation
    public func fetchBarsForTrade(
        trade: Trade,
        config: MarketConnectionConfig,
        resolution: String = "15m"
    ) async throws -> (provider: String, bars: [MarketBar]) {
        let provider = detectProviderForSymbol(symbol: trade.symbol)
        
        let resMs = MarketResolution(rawValue: resolution)?.durationMs ?? 900_000
        let beforePadding = Double(max(3_600_000, resMs * 4)) / 1000.0
        let afterPadding = Double(max(1_800_000, resMs * 2)) / 1000.0
        
        let openTime = trade.openedAt.addingTimeInterval(-beforePadding)
        let closeTime = (trade.closedAt ?? Date()).addingTimeInterval(afterPadding)
        
        if provider == "binance" {
            let startMs = Int64(openTime.timeIntervalSince1970 * 1000)
            let endMs = Int64(closeTime.timeIntervalSince1970 * 1000)
            let bars = try await fetchBinanceBars(
                symbol: trade.symbol,
                interval: resolution,
                startTimeMs: startMs,
                endTimeMs: endMs
            )
            return ("Binance Spot (Public)", validateBars(bars))
        } else if !config.oandaApiKey.isEmpty && !config.oandaAccountId.isEmpty {
            let bars = try await fetchOandaBars(
                symbol: trade.symbol,
                apiKey: config.oandaApiKey,
                accountId: config.oandaAccountId,
                environment: config.oandaEnvironment,
                from: openTime,
                to: closeTime,
                resolution: resolution
            )
            return ("OANDA v20", validateBars(bars))
        } else {
            // Internal implementation note
            let binanceBars = try? await fetchBinanceBars(
                symbol: "\(trade.symbol)USDT",
                interval: resolution,
                startTimeMs: Int64(openTime.timeIntervalSince1970 * 1000),
                endTimeMs: Int64(closeTime.timeIntervalSince1970 * 1000)
            )
            if let bb = binanceBars, !bb.isEmpty {
                return ("Binance Spot (USDT)", validateBars(bb))
            }
            
            throw NSError(
                domain: "MarketDataService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Instrument \(trade.symbol) is a Forex/CFD symbol. Please configure your OANDA Access Token in Settings → Market Data to stream historical candles."]
            )
        }
    }
}
