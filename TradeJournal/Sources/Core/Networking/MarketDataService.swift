import Foundation

/// Dịch vụ cung cấp dữ liệu nến thị trường (Market Data) cho tính năng Trade Replay và MAE/MFE.
/// Port 1:1 từ `market-normalize.ts`, `public-crypto.ts`, và `oanda.ts` trong mã nguồn web gốc.
public final class MarketDataService: Sendable {
    public static let shared = MarketDataService()
    
    private let binanceBaseUrl = "https://data-api.binance.vision"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - 1. Symbol Normalization (Port 1:1 từ `market-normalize.ts`)
    
    public func normalizeMarketSymbol(symbol: String, provider: String) -> String {
        guard !symbol.isEmpty else { return "" }
        var clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Loại bỏ tiền tố và hậu tố thường gặp từ MT4/MT5/cTrader
        // VD: XAUUSD.m, XAUUSDpro, XAUUSDraw, EURUSD+, #EURUSD, EURUSD_i, EURUSD_sb
        clean = clean.replacingOccurrences(of: "^#", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(
            of: "(\\.[a-z0-9]+|\\+|#|_sb|_i|_pro|-m)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        if provider == "oanda" {
            // Nếu đã theo chuẩn BASE_QUOTE (như XAU_USD, EUR_USD, US30_USD), giữ nguyên
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
            
            // Cặp 6 ký tự Forex/Kim loại: XAUUSD -> XAU_USD, EURUSD -> EUR_USD
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
    
    // MARK: - 2. Binance Public Spot Candlesticks (Không Cần API Key)
    
    /// Tải nến lịch sử từ API công khai của Binance
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
        
        return bars
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
        
        return bars
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
            return (false, "Vui lòng nhập đầy đủ OANDA Access Token và v20 Account ID.")
        }
        
        let base = environment.lowercased() == "live" ? "https://api-fxtrade.oanda.com" : "https://api-fxpractice.oanda.com"
        let urlStr = "\(base)/v3/accounts/\(cleanAcc)/instruments/EUR_USD/candles?count=1&granularity=M1&price=M"
        guard let url = URL(string: urlStr) else {
            return (false, "URL OANDA không hợp lệ.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("RFC3339", forHTTPHeaderField: "Accept-Datetime-Format")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "Không nhận được phản hồi từ máy chủ OANDA.")
            }
            if (200...299).contains(http.statusCode) {
                return (true, "Kết nối OANDA v20 thành công! Tài khoản \(cleanAcc) (\(environment)) đã sẵn sàng tải nến.")
            } else if http.statusCode == 401 {
                return (false, "Lỗi 401: Access Token OANDA không hợp lệ hoặc đã hết hạn.")
            } else if http.statusCode == 404 {
                return (false, "Lỗi 404: Không tìm thấy v20 Account ID '\(cleanAcc)' trên môi trường \(environment).")
            } else {
                let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errMsg = errJson?["errorMessage"] as? String ?? (String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
                return (false, "OANDA phản hồi lỗi: \(errMsg)")
            }
        } catch {
            return (false, "Lỗi kết nối OANDA: \(error.localizedDescription)")
        }
    }
    
    public func testBinanceConnection() async -> (success: Bool, message: String) {
        do {
            let bars = try await fetchBinanceBars(symbol: "BTCUSDT", interval: "1m", limit: 1)
            if !bars.isEmpty {
                return (true, "Kết nối Binance Public Spot API thành công! Tải nến Crypto sẵn sàng.")
            } else {
                return (false, "Binance không trả về dữ liệu nến.")
            }
        } catch {
            return (false, "Lỗi kết nối Binance: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 4. Unified Trade Candles Fetcher
    
    /// Tự động phát hiện nhà cung cấp thích hợp và tải nến thật cho một Trade
    public func fetchBarsForTrade(
        trade: Trade,
        config: MarketConnectionConfig,
        resolution: String = "15m"
    ) async throws -> (provider: String, bars: [MarketBar]) {
        let provider = detectProviderForSymbol(symbol: trade.symbol)
        
        // Khoảng thời gian: từ 2 giờ trước khi vào lệnh tới 2 giờ sau khi đóng lệnh
        let openTime = trade.openedAt.addingTimeInterval(-7200)
        let closeTime = (trade.closedAt ?? trade.openedAt).addingTimeInterval(7200)
        
        if provider == "binance" {
            let startMs = Int64(openTime.timeIntervalSince1970 * 1000)
            let endMs = Int64(closeTime.timeIntervalSince1970 * 1000)
            let bars = try await fetchBinanceBars(
                symbol: trade.symbol,
                interval: resolution,
                startTimeMs: startMs,
                endTimeMs: endMs
            )
            return ("Binance Spot (Public)", bars)
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
            return ("OANDA v20", bars)
        } else {
            // Trường hợp Forex nhưng chưa có key OANDA: thử tìm cặp tương đương trên Binance hoặc thông báo
            let binanceBars = try? await fetchBinanceBars(
                symbol: "\(trade.symbol)USDT",
                interval: resolution,
                startTimeMs: Int64(openTime.timeIntervalSince1970 * 1000),
                endTimeMs: Int64(closeTime.timeIntervalSince1970 * 1000)
            )
            if let bb = binanceBars, !bb.isEmpty {
                return ("Binance Spot (USDT)", bb)
            }
            
            throw NSError(
                domain: "MarketDataService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Cặp \(trade.symbol) thuộc nhóm Forex/CFD. Cần cấu hình OANDA Access Token trong Cài Đặt → Market Data để tải nến thật."]
            )
        }
    }
}
