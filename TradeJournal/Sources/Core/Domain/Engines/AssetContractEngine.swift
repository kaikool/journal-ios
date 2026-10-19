import Foundation

/// Unified asset contract specification and P&L engine.
/// Standardizes contract sizes, pip values, price decimals, and P&L calculations
/// across Gold/Metals, Forex currency pairs, Crypto, Commodities, and Indices.
public enum AssetContractEngine {
    
    public enum AssetCategory: String, Sendable, Equatable {
        case goldAndMetals
        case forexMajor
        case forexJpy
        case forexCross
        case crypto
        case index
        case commodityOil
        case equity
        case custom
    }
    
    public struct SymbolSpec: Sendable, Equatable {
        public let symbol: String
        public let cleanSymbol: String
        public let baseCurrency: String
        public let quoteCurrency: String
        public let assetCategory: AssetCategory
        public let contractSize: Decimal        // e.g. 100 for Gold, 100,000 for Forex, 1 for Crypto/Index
        public let pipSize: Decimal             // 0.1 for Gold, 0.0001 for Forex, 0.01 for JPY
        public let defaultDecimals: Int         // 2 for Gold, 5 for Forex, 3 for JPY
        public let unitLabel: String            // "oz", "units", "barrels", "coins", "shares"
        public let pricePlaceholder: String     // "2650.00", "1.08500", "155.250"
        public let lotDescription: String       // e.g. "1 Lot = 100 oz", "1 Lot = 100,000 units"
        
        public init(
            symbol: String,
            cleanSymbol: String,
            baseCurrency: String,
            quoteCurrency: String,
            assetCategory: AssetCategory,
            contractSize: Decimal,
            pipSize: Decimal,
            defaultDecimals: Int,
            unitLabel: String,
            pricePlaceholder: String,
            lotDescription: String
        ) {
            self.symbol = symbol
            self.cleanSymbol = cleanSymbol
            self.baseCurrency = baseCurrency
            self.quoteCurrency = quoteCurrency
            self.assetCategory = assetCategory
            self.contractSize = contractSize
            self.pipSize = pipSize
            self.defaultDecimals = defaultDecimals
            self.unitLabel = unitLabel
            self.pricePlaceholder = pricePlaceholder
            self.lotDescription = lotDescription
        }
    }
    
    // MARK: - Symbol Specification Lookup
    
    public static func spec(for rawSymbol: String) -> SymbolSpec {
        let clean = rawSymbol
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[/\\-\\._]", with: "", options: .regularExpression)
        
        // 1. Gold & Precious Metals
        if clean.hasPrefix("XAU") || clean == "GOLD" || clean.contains("XAU") {
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: "XAUUSD",
                baseCurrency: "XAU",
                quoteCurrency: "USD",
                assetCategory: .goldAndMetals,
                contractSize: 100, // 1 standard lot = 100 troy oz
                pipSize: 0.1,      // 0.1 USD = 1 pip (1 giá = 1.00 USD = 10 pips)
                defaultDecimals: 2,
                unitLabel: "oz",
                pricePlaceholder: "2650.00",
                lotDescription: "1 Lot = 100 oz · 4 giá / 0.25 lot = $100"
            )
        }
        
        if clean.hasPrefix("XAG") || clean == "SILVER" || clean.contains("XAG") {
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: "XAGUSD",
                baseCurrency: "XAG",
                quoteCurrency: "USD",
                assetCategory: .goldAndMetals,
                contractSize: 5000, // 1 standard lot = 5000 troy oz
                pipSize: 0.001,
                defaultDecimals: 3,
                unitLabel: "oz",
                pricePlaceholder: "31.500",
                lotDescription: "1 Lot = 5,000 oz"
            )
        }
        
        // 2. Oil / Energies
        if clean.contains("OIL") || clean.contains("WTI") || clean.contains("BRENT") || clean.contains("WTICO") || clean.contains("BCO") {
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: "USOIL",
                baseCurrency: "OIL",
                quoteCurrency: "USD",
                assetCategory: .commodityOil,
                contractSize: 100, // 1 standard CFD lot = 100 barrels
                pipSize: 0.01,
                defaultDecimals: 2,
                unitLabel: "barrels",
                pricePlaceholder: "72.50",
                lotDescription: "1 Lot = 100 barrels"
            )
        }
        
        // 3. Stock Indices (CFD)
        if clean.contains("US30") || clean.contains("DJ30") || clean.contains("DJI") ||
           clean.contains("NAS100") || clean.contains("USTEC") || clean.contains("NDX") || clean.contains("NQ") ||
           clean.contains("SPX500") || clean.contains("US500") || clean.contains("SP500") || clean.contains("ES") ||
           clean.contains("GER") || clean.contains("DAX") {
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: clean,
                baseCurrency: "INDEX",
                quoteCurrency: "USD",
                assetCategory: .index,
                contractSize: 1, // 1 point = $1 per 1 contract
                pipSize: 1.0,
                defaultDecimals: 1,
                unitLabel: "pts",
                pricePlaceholder: clean.contains("US30") ? "43500.0" : (clean.contains("NAS") || clean.contains("NQ") ? "20500.0" : "5800.0"),
                lotDescription: "1 Lot = 1 contract ($1/pt)"
            )
        }
        
        // 4. Crypto Tokens
        let cryptoPrefixes = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "NEAR", "LTC"]
        if cryptoPrefixes.contains(where: { clean.hasPrefix($0) }) || clean.hasSuffix("USDT") {
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: clean,
                baseCurrency: String(clean.prefix(3)),
                quoteCurrency: "USD",
                assetCategory: .crypto,
                contractSize: 1, // 1 lot = 1 coin
                pipSize: 0.01,
                defaultDecimals: 2,
                unitLabel: "coins",
                pricePlaceholder: clean.hasPrefix("BTC") ? "68500.00" : (clean.hasPrefix("ETH") ? "2650.00" : "150.00"),
                lotDescription: "1 Lot = 1 coin"
            )
        }
        
        // 5. Forex Currency Pairs (6 characters standard)
        if clean.count == 6 {
            let base = String(clean.prefix(3))
            let quote = String(clean.suffix(3))
            
            // JPY quote pairs: 2 or 3 decimals, 1 pip = 0.01
            if quote == "JPY" {
                return SymbolSpec(
                    symbol: rawSymbol,
                    cleanSymbol: "\(base)\(quote)",
                    baseCurrency: base,
                    quoteCurrency: quote,
                    assetCategory: .forexJpy,
                    contractSize: 100_000, // 1 standard lot = 100,000 units
                    pipSize: 0.01,         // 1 pip = 0.01 JPY
                    defaultDecimals: 3,    // 3 fractional digits (e.g. 155.250)
                    unitLabel: "units",
                    pricePlaceholder: "155.250",
                    lotDescription: "1 Lot = 100,000 \(base) · 1 pip = 0.01"
                )
            }
            
            // Major pairs quoting in USD (EURUSD, GBPUSD, AUDUSD, NZDUSD)
            if quote == "USD" {
                return SymbolSpec(
                    symbol: rawSymbol,
                    cleanSymbol: "\(base)\(quote)",
                    baseCurrency: base,
                    quoteCurrency: quote,
                    assetCategory: .forexMajor,
                    contractSize: 100_000, // 1 standard lot = 100,000 units
                    pipSize: 0.0001,       // 1 pip = 0.0001 USD ($10 / lot)
                    defaultDecimals: 5,    // 5 fractional digits (e.g. 1.08500)
                    unitLabel: "units",
                    pricePlaceholder: base == "EUR" ? "1.08500" : (base == "GBP" ? "1.29500" : "0.66500"),
                    lotDescription: "1 Lot = 100,000 \(base) · 1 pip = $10/lot"
                )
            }
            
            // Other Forex cross pairs (USDCAD, USDCHF, EURGBP, etc.)
            return SymbolSpec(
                symbol: rawSymbol,
                cleanSymbol: "\(base)\(quote)",
                baseCurrency: base,
                quoteCurrency: quote,
                assetCategory: .forexCross,
                contractSize: 100_000,
                pipSize: 0.0001,
                defaultDecimals: 5,
                unitLabel: "units",
                pricePlaceholder: "1.35000",
                lotDescription: "1 Lot = 100,000 \(base)"
            )
        }
        
        // 6. Equities / Stocks / Unknown Default
        return SymbolSpec(
            symbol: rawSymbol,
            cleanSymbol: clean,
            baseCurrency: clean,
            quoteCurrency: "USD",
            assetCategory: .equity,
            contractSize: 1, // 1 share
            pipSize: 0.01,
            defaultDecimals: 2,
            unitLabel: "shares",
            pricePlaceholder: "150.00",
            lotDescription: "1 Lot = 1 share"
        )
    }
    
    // MARK: - Multiplier Lookup
    
    /// Returns standard contract multiplier for an instrument, checking custom user overrides first.
    public static func contractMultiplier(for symbol: String, customMultipliers: [String: Decimal] = [:]) -> Decimal {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit = customMultipliers[clean], explicit > 0 {
            return explicit
        }
        return spec(for: symbol).contractSize
    }
    
    // MARK: - Accurate Gross P&L Calculation
    
    /// Computes realized gross P&L in reporting currency (default USD) using standard asset contract specifications.
    public static func calculateGrossPnl(
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal,
        customMultiplier: Decimal? = nil,
        conversionRates: [String: Decimal] = [:]
    ) -> Decimal {
        guard quantity > 0, entryPrice > 0, exitPrice > 0 else { return 0 }
        
        let priceDelta = (direction == .long) ? (exitPrice - entryPrice) : (entryPrice - exitPrice)
        let instrumentSpec = spec(for: symbol)
        let multiplier = (customMultiplier != nil && customMultiplier! > 0) ? customMultiplier! : instrumentSpec.contractSize
        
        // Base gross profit in quote currency
        let rawPnlInQuote = priceDelta * quantity * multiplier
        
        // Convert quote currency to USD where applicable
        switch instrumentSpec.assetCategory {
        case .forexJpy:
            // JPY quote currency:
            // For USD/JPY: profitInUSD = profitInJPY / exitPrice
            if instrumentSpec.baseCurrency == "USD" {
                return rawPnlInQuote / exitPrice
            } else {
                // Cross pair like EUR/JPY: use JPY conversion rate or 1 / USDJPY rate
                let jpyRate = conversionRates["JPY"] ?? (Decimal(1) / exitPrice)
                return rawPnlInQuote * jpyRate
            }
            
        case .forexCross:
            if instrumentSpec.baseCurrency == "USD" {
                // e.g. USD/CAD, USD/CHF: profitInUSD = profitInQuote / exitPrice
                return rawPnlInQuote / exitPrice
            } else if instrumentSpec.quoteCurrency == "USD" {
                // Already in USD
                return rawPnlInQuote
            } else {
                // Cross pair like EUR/GBP: convert GBP to USD using rate
                if let quoteRate = conversionRates[instrumentSpec.quoteCurrency] {
                    return rawPnlInQuote * quoteRate
                }
                return rawPnlInQuote
            }
            
        default:
            // Gold (XAUUSD), Majors (EURUSD), Crypto, Indices: already quoted in USD
            return rawPnlInQuote
        }
    }
    
    // MARK: - Pips & Points Decomposition
    
    /// Computes point and pip movement between entry and exit prices.
    public static func pipDelta(
        symbol: String,
        entryPrice: Decimal,
        exitPrice: Decimal,
        direction: TradeDirection
    ) -> (pips: Decimal, points: Decimal) {
        guard entryPrice > 0, exitPrice > 0 else { return (0, 0) }
        let instrumentSpec = spec(for: symbol)
        let rawDiff = (direction == .long) ? (exitPrice - entryPrice) : (entryPrice - exitPrice)
        let pips = instrumentSpec.pipSize > 0 ? (rawDiff / instrumentSpec.pipSize) : rawDiff
        return (pips: pips, points: rawDiff)
    }
    
    /// Formats human-readable pip and point movement string (e.g. "+4.00 giá (+40.0 pips)")
    public static func formatDeltaText(
        symbol: String,
        entryPrice: Decimal,
        exitPrice: Decimal,
        direction: TradeDirection
    ) -> String {
        let (pips, points) = pipDelta(symbol: symbol, entryPrice: entryPrice, exitPrice: exitPrice, direction: direction)
        let instrumentSpec = spec(for: symbol)
        
        let sign = points >= 0 ? "+" : ""
        let doublePoints = (points as NSDecimalNumber).doubleValue
        let doublePips = (pips as NSDecimalNumber).doubleValue
        
        switch instrumentSpec.assetCategory {
        case .goldAndMetals:
            return String(format: "%@%.2f giá (%@%.1f pips)", sign, doublePoints, sign, doublePips)
        case .forexMajor, .forexCross, .forexJpy:
            return String(format: "%@%.1f pips", sign, doublePips)
        case .index:
            return String(format: "%@%.1f pts", sign, doublePoints)
        case .crypto:
            return String(format: "%@$%.2f", sign, doublePoints)
        default:
            return String(format: "%@%.2f pts", sign, doublePoints)
        }
    }
}
