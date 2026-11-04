import Foundation

/// Market data service providing historical candlestick data for Trade Replay and MAE/MFE excursions.
/// Domain specification matching core web repository
public final class MarketDataService: Sendable {
    public static let shared = MarketDataService()
    
    internal let binanceBaseUrls = [
        "https://data-api.binance.vision",
        "https://api.binance.com",
        "https://api1.binance.com",
        "https://api3.binance.com"
    ]
    internal let session = URLSession.shared
    
    private init() {}
    
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
        let isClosed = (trade.status != .open && trade.closedAt != nil)
        let effectiveForceRefresh = forceRefresh || !isClosed
        let provider = detectProviderForSymbol(symbol: trade.symbol)
        let providerTag = provider == "binance" ? "Binance Spot" : "OANDA v20"
        
        if !effectiveForceRefresh,
           let cached = MarketDataCacheStore.shared.getTradeBars(tradeId: trade.id, resolution: resolution, isClosed: isClosed),
           !cached.isEmpty {
            return (providerTag, cached)
        }
        
        let coalescingKey = "trade_\(trade.id)_\(resolution)"
        
        do {
            let fetchedBars = try await MarketDataCacheStore.shared.runCoalesced(key: coalescingKey) { [self] in
                if !effectiveForceRefresh,
                   let cached = MarketDataCacheStore.shared.getTradeBars(tradeId: trade.id, resolution: resolution, isClosed: isClosed),
                   !cached.isEmpty {
                    return cached
                }
                
                let resMs = MarketResolution(rawValue: resolution)?.durationMs ?? 900_000
                let preBuffer = Double(resMs * 120) / 1000.0
                let postBuffer = Double(resMs * 30) / 1000.0
                
                let openTime = trade.openedAt.addingTimeInterval(-preBuffer)
                let closeTime: Date = {
                    if trade.status == .open {
                        return Date()
                    } else if let closedAt = trade.closedAt {
                        return min(Date(), closedAt.addingTimeInterval(postBuffer))
                    } else {
                        return Date()
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
                } else if !config.oandaApiKey.isEmpty || KeychainManager.get(forKey: "oanda_api_key") != nil || AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") != nil {
                    let effectiveKey = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? config.oandaApiKey
                    let effectiveAcc = AppSettingsStore.shared.oandaAccountId ?? AppSecretsLoader.loadSecret(named: "OANDA_ACCOUNT_ID") ?? config.oandaAccountId
                    let bars = try await fetchOandaBars(
                        symbol: trade.symbol,
                        apiKey: effectiveKey,
                        accountId: effectiveAcc,
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
            
            return (effectiveForceRefresh ? "\(providerTag) Live" : providerTag, fetchedBars)
        } catch {
            if let stale = MarketDataCacheStore.shared.getStaleTradeBars(tradeId: trade.id, resolution: resolution), !stale.isEmpty {
                return (providerTag, stale)
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
        
        var bars: [MarketBar] = []
        for c in candles {
            guard let timeStr = c["time"] as? String,
                  let date = parseOandaDate(timeStr),
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
    
    // MARK: - 6. Symbol Candlesticks Fetcher (Unified Candle Hub with Sub-slice Reuse & Coalescing)
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
        
        if !forceRefresh,
           let cached = MarketDataCacheStore.shared.getSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count),
           !cached.isEmpty {
            return (providerTag, cached)
        }
        
        let canonicalFetchCount = max(count, 100)
        let coalescingKey = "sym_\(cleanSymbol)_\(resolution)"
        
        do {
            let fetchedBars = try await MarketDataCacheStore.shared.runCoalesced(key: coalescingKey) { [self] in
                if !forceRefresh,
                   let cached = MarketDataCacheStore.shared.getSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count),
                   !cached.isEmpty {
                    return cached
                }
                
                if provider == "binance" {
                    let normalized = normalizeMarketSymbol(symbol: cleanSymbol, provider: "binance")
                    var bars = (try? await fetchBinanceBars(symbol: normalized, interval: resolution, limit: canonicalFetchCount)) ?? []
                    if bars.isEmpty {
                        bars = (try? await fetchBinanceBars(symbol: cleanSymbol, interval: resolution, limit: canonicalFetchCount)) ?? []
                    }
                    if !bars.isEmpty {
                        let valid = validateBars(bars)
                        MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: canonicalFetchCount)
                        return valid
                    }
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No candlestick data available on Binance for \(cleanSymbol)."]
                    )
                } else if !config.oandaApiKey.isEmpty || KeychainManager.get(forKey: "oanda_api_key") != nil || AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") != nil {
                    let effectiveKey = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? config.oandaApiKey
                    let effectiveAcc = AppSettingsStore.shared.oandaAccountId ?? AppSecretsLoader.loadSecret(named: "OANDA_ACCOUNT_ID") ?? config.oandaAccountId
                    let bars = try await fetchRecentOandaBars(
                        symbol: cleanSymbol,
                        apiKey: effectiveKey,
                        accountId: effectiveAcc,
                        environment: config.oandaEnvironment,
                        resolution: resolution,
                        count: canonicalFetchCount
                    )
                    let valid = validateBars(bars)
                    MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: canonicalFetchCount)
                    return valid
                } else {
                    let binanceBars = try? await fetchBinanceBars(
                        symbol: "\(cleanSymbol)USDT",
                        interval: resolution,
                        limit: canonicalFetchCount
                    )
                    if let bb = binanceBars, !bb.isEmpty {
                        let valid = validateBars(bb)
                        MarketDataCacheStore.shared.saveSymbolBars(valid, symbol: cleanSymbol, resolution: resolution, count: canonicalFetchCount)
                        return valid
                    }
                    
                    throw NSError(
                        domain: "MarketDataService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Instrument \(cleanSymbol) is a Forex/CFD symbol. Please configure your OANDA Access Token in Settings → Market Data to stream live candles."]
                    )
                }
            }
            
            let sliced = fetchedBars.count >= count ? Array(fetchedBars.suffix(count)) : fetchedBars
            return (forceRefresh ? "\(providerTag) Live" : providerTag, sliced)
        } catch {
            if let stale = MarketDataCacheStore.shared.getStaleSymbolBars(symbol: cleanSymbol, resolution: resolution, count: count), !stale.isEmpty {
                return (providerTag, stale)
            }
            throw error
        }
    }
}
