import Foundation

/// Unified asset contract specification and gross P&L engine.
///
/// The engine is responsible for three things:
/// 1. Classifying a broker symbol into an asset category (FX, metals, crypto, index, oil, equity).
/// 2. Deriving the contract size used to convert a price move into money.
/// 3. Converting the resulting quote-currency P&L into the reporting currency.
///
/// Symbol handling is deliberately tolerant of broker suffixes (`EURUSDm`, `EURUSD.m`, `EURUSD.pro`,
/// `EURUSD_i`, ...) because those spellings are extremely common on MT4/MT5 and would otherwise be
/// classified as equities and priced with a contract size of 1 (a 100,000x P&L error).
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
        public let assetCategory: AssetCategory
        public let baseCurrency: String
        public let quoteCurrency: String
        public let contractSize: Decimal
        public let pipSize: Decimal
        public let defaultDecimals: Int         // 2 for Gold, 5 for Forex, 3 for JPY
        public let cleanSymbol: String
        public let pricePlaceholder: String
        public let lotDescription: String
        
        public init(
            assetCategory: AssetCategory,
            baseCurrency: String,
            quoteCurrency: String,
            contractSize: Decimal,
            pipSize: Decimal,
            defaultDecimals: Int,
            cleanSymbol: String,
            pricePlaceholder: String,
            lotDescription: String
        ) {
            self.assetCategory = assetCategory
            self.baseCurrency = baseCurrency
            self.quoteCurrency = quoteCurrency
            self.contractSize = contractSize
            self.pipSize = pipSize
            self.defaultDecimals = defaultDecimals
            self.cleanSymbol = cleanSymbol
            self.pricePlaceholder = pricePlaceholder
            self.lotDescription = lotDescription
        }
        
        /// True when the instrument is a spot FX pair (contract size 100,000 quote units per lot).
        public var isForex: Bool {
            switch assetCategory {
            case .forexMajor, .forexJpy, .forexCross:
                return true
            default:
                return false
            }
        }
    }
    
    /// Result of a gross P&L computation, including the currency the amount is denominated in.
    public struct GrossPnlResult: Sendable, Equatable {
        /// P&L expressed in the reporting currency (equal to `quoteAmount` when the conversion was impossible).
        public let amount: Decimal
        /// Raw P&L denominated in the instrument's quote currency.
        public let quoteAmount: Decimal
        public let quoteCurrency: String
        public let reportingCurrency: String
        /// False when no exchange rate was available and the raw quote amount had to be used as-is.
        public let isConverted: Bool
    }
    
    // MARK: - Currency Recognition
    
    /// Currency codes used to recognise FX pairs inside broker symbol names.
    /// Only codes that can realistically start or end a traded FX pair are listed.
    /// Major currency codes used to recognise FX pairs (EUR, GBP, JPY, AUD, NZD, CAD, CHF, USD) and local VND.
    public static let currencyCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF", "VND"
    ]
    
    /// Only BTC for crypto
    public static let cryptoCodes: Set<String> = [
        "BTC"
    ]
    
    private static let indexCodes: [String] = [
        "US30", "DJ30", "DJI", "NAS100", "USTEC", "NDX", "NQ", "SPX500", "US500",
        "SP500", "GER", "DAX", "ES"
    ]
    
    private static let oilCodes: [String] = ["OIL", "WTI", "BRENT", "WTICO", "BCO", "XTI"]
    
    // MARK: - Symbol Normalisation
    
    /// Uppercases the symbol and removes the separators brokers use (`/`, `-`, `.`, `_`, `:`, spaces).
    public static func cleanSymbol(_ rawSymbol: String) -> String {
        let upper = rawSymbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return upper.replacingOccurrences(of: "[/\\-\\._: ]", with: "", options: .regularExpression)
    }
    
    /// Detects an FX pair inside a cleaned symbol, tolerating broker prefixes/suffixes.
    /// Returns the first `(base, quote)` window where both halves are recognised currency codes.
    public static func detectCurrencyPair(in clean: String) -> (base: String, quote: String)? {
        let chars = Array(clean)
        guard chars.count >= 6 else { return nil }
        for index in 0...(chars.count - 6) {
            let base = String(chars[index..<(index + 3)])
            let quote = String(chars[(index + 3)..<(index + 6)])
            if currencyCodes.contains(base) && currencyCodes.contains(quote) {
                return (base, quote)
            }
        }
        return nil
    }
    
    /// Canonical instrument identifier used for lookups (multipliers, hashes, grouping).
    /// `EURUSDm` and `EURUSD.pro` both resolve to `EURUSD`.
    public static func canonicalSymbol(_ rawSymbol: String) -> String {
        spec(for: rawSymbol).cleanSymbol
    }
    
    /// Normalised key used to look up user-configured contract multipliers.
    public static func multiplierKey(for rawSymbol: String) -> String {
        canonicalSymbol(rawSymbol)
    }
    
    /// Asset class tag derived from the symbol (used when the broker does not provide one).
    public static func assetClass(for rawSymbol: String) -> String {
        switch spec(for: rawSymbol).assetCategory {
        case .forexMajor, .forexJpy, .forexCross:
            return "forex"
        case .crypto:
            return "crypto"
        case .goldAndMetals, .commodityOil, .index:
            return "cfd"
        case .equity, .custom:
            return "equity"
        }
    }
    
    // MARK: - Specification
    
    public static func spec(for rawSymbol: String) -> SymbolSpec {
        let clean = cleanSymbol(rawSymbol)
        
        // Metals: XAU / XAG with an optional quote currency and any broker suffix.
        if clean.contains("XAU") || clean.hasPrefix("GOLD") {
            return metalSpec(prefix: "XAU", clean: clean, contractSize: 100, pipSize: Decimal(string: "0.1")!, decimals: 2, placeholder: "2000.00", lot: "contract size 100 oz per lot")
        }
        if clean.contains("XAG") || clean.hasPrefix("SILVER") {
            return metalSpec(prefix: "XAG", clean: clean, contractSize: 5000, pipSize: Decimal(string: "0.001")!, decimals: 3, placeholder: "25.000", lot: "contract size 5,000 oz per lot")
        }
        
        // Spot FX: detected through currency codes so that broker suffixes stay harmless.
        if let pair = detectCurrencyPair(in: clean) {
            let canonical = pair.base + pair.quote
            if pair.quote == "JPY" {
                return SymbolSpec(
                    assetCategory: .forexJpy,
                    baseCurrency: pair.base,
                    quoteCurrency: pair.quote,
                    contractSize: 100_000,
                    pipSize: Decimal(string: "0.01")!,
                    defaultDecimals: 3,
                    cleanSymbol: canonical,
                    pricePlaceholder: "155.250",
                    lotDescription: "contract size 100,000 \(pair.quote) per lot"
                )
            }
            return SymbolSpec(
                assetCategory: pair.quote == "USD" ? .forexMajor : .forexCross,
                baseCurrency: pair.base,
                quoteCurrency: pair.quote,
                contractSize: 100_000,
                pipSize: Decimal(string: "0.0001")!,
                defaultDecimals: 5,
                cleanSymbol: canonical,
                pricePlaceholder: "1.08000",
                lotDescription: "contract size 100,000 \(pair.quote) per lot"
            )
        }
        
        // Oil.
        if oilCodes.contains(where: { clean.contains($0) }) {
            return SymbolSpec(
                assetCategory: .commodityOil,
                baseCurrency: "OIL",
                quoteCurrency: "USD",
                contractSize: 100,
                pipSize: Decimal(string: "0.01")!,
                defaultDecimals: 2,
                cleanSymbol: clean,
                pricePlaceholder: "70.00",
                lotDescription: "contract size 100 barrels per lot"
            )
        }
        
        // Indices: prefix matching avoids classifying equities such as AES or WES as indices.
        if indexCodes.contains(where: { clean.hasPrefix($0) }) {
            return SymbolSpec(
                assetCategory: .index,
                baseCurrency: "INDEX",
                quoteCurrency: "USD",
                contractSize: 1,
                pipSize: 1,
                defaultDecimals: 2,
                cleanSymbol: clean,
                pricePlaceholder: "35000.00",
                lotDescription: "1 contract = 1 USD per point"
            )
        }
        
        // Crypto.
        if let crypto = cryptoSpec(for: clean) {
            return crypto
        }
        
        // Equity / anything else.
        return SymbolSpec(
            assetCategory: .equity,
            baseCurrency: String(clean.prefix(3)),
            quoteCurrency: "USD",
            contractSize: 1,
            pipSize: Decimal(string: "0.01")!,
            defaultDecimals: 2,
            cleanSymbol: clean,
            pricePlaceholder: "100.00",
            lotDescription: "1 share per unit"
        )
    }
    
    private static func metalSpec(prefix: String, clean: String, contractSize: Decimal, pipSize: Decimal, decimals: Int, placeholder: String, lot: String) -> SymbolSpec {
        var quote = "USD"
        let chars = Array(clean)
        if let start = chars.firstIndex(of: Array(prefix)[0]),
           start + 3 <= chars.count {
            // Look for a currency code right after the metal code (XAUUSD, XAUUSDm, XAUEUR...).
            let tail = String(chars[(start + 3)...])
            if tail.count >= 3 {
                let candidate = String(tail.prefix(3))
                if currencyCodes.contains(candidate) {
                    quote = candidate
                }
            }
        }
        return SymbolSpec(
            assetCategory: .goldAndMetals,
            baseCurrency: prefix,
            quoteCurrency: quote,
            contractSize: contractSize,
            pipSize: pipSize,
            defaultDecimals: decimals,
            cleanSymbol: prefix + quote,
            pricePlaceholder: placeholder,
            lotDescription: lot
        )
    }
    
    private static func cryptoSpec(for clean: String) -> SymbolSpec? {
        let chars = Array(clean)
        // BTC, ETH or other standard crypto
        if chars.count >= 3 {
            let base = String(chars.prefix(3))
            if cryptoCodes.contains(base) {
                let quote = chars.count >= 6 ? String(chars[3..<6]) : "USD"
                return SymbolSpec(
                    assetCategory: .crypto,
                    baseCurrency: base,
                    quoteCurrency: quote,
                    contractSize: 1,
                    pipSize: Decimal(string: "0.01")!,
                    defaultDecimals: 2,
                    cleanSymbol: clean,
                    pricePlaceholder: "65000.00",
                    lotDescription: "1 coin per unit"
                )
            }
        }
        if clean.hasSuffix("USDT") {
            return SymbolSpec(
                assetCategory: .crypto,
                baseCurrency: String(clean.prefix(clean.count - 4)),
                quoteCurrency: "USDT",
                contractSize: 1,
                pipSize: Decimal(string: "0.01")!,
                defaultDecimals: 2,
                cleanSymbol: clean,
                pricePlaceholder: "65000.00",
                lotDescription: "1 coin per unit"
            )
        }
        return nil
    }
    
    // MARK: - Contract Multiplier
    
    /// Contract multiplier for a symbol, honouring user-configured overrides.
    public static func contractMultiplier(for symbol: String, customMultipliers: [String: Decimal] = [:]) -> Decimal {
        if let custom = customMultiplier(for: symbol, multipliers: customMultipliers) {
            return custom
        }
        return spec(for: symbol).contractSize
    }
    
    /// User-configured contract multiplier for a symbol, or `nil` when the default applies.
    /// Lookups use the canonical symbol so that `EURUSD` also matches `EURUSDm`.
    public static func customMultiplier(for symbol: String, multipliers: [String: Decimal]) -> Decimal? {
        guard !multipliers.isEmpty else { return nil }
        let key = multiplierKey(for: symbol)
        if let custom = multipliers[key], custom > 0 {
            return custom
        }
        // Backwards compatibility with multipliers stored under the raw symbol spelling.
        let rawKey = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom = multipliers[rawKey], custom > 0 {
            return custom
        }
        return nil
    }
    
    // MARK: - Gross P&L
    
    /// Computes the gross P&L of a position and converts it into the reporting currency.
    ///
    /// - Parameter entryNotional: When the entry side was matched across several lots, pass the
    ///   matched entry notional (price x matched quantity) instead of an averaged entry price.
    ///   The P&L is then computed as `exit * qty - entryNotional`, which avoids the rounding
    ///   artefacts of an averaged entry price and keeps the result exact.
    public static func calculateGrossPnlDetailed(
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal,
        customMultiplier: Decimal? = nil,
        context: CurrencyContext = .default,
        entryNotional: Decimal? = nil
    ) -> GrossPnlResult {
        let spec = spec(for: symbol)
        let reporting = context.reportingCurrency
        let quote = spec.quoteCurrency
        
        guard quantity > 0, exitPrice > 0 else {
            return GrossPnlResult(amount: 0, quoteAmount: 0, quoteCurrency: quote, reportingCurrency: reporting, isConverted: false)
        }
        if entryNotional == nil && entryPrice <= 0 {
            return GrossPnlResult(amount: 0, quoteAmount: 0, quoteCurrency: quote, reportingCurrency: reporting, isConverted: false)
        }
        
        let multiplier = (customMultiplier != nil && customMultiplier! > 0) ? customMultiplier! : spec.contractSize
        let quoteAmount: Decimal
        if let notional = entryNotional {
            let signed = direction == .long ? (exitPrice * quantity - notional) : (notional - exitPrice * quantity)
            quoteAmount = signed * multiplier
        } else {
            let priceDelta: Decimal = direction == .long ? (exitPrice - entryPrice) : (entryPrice - exitPrice)
            quoteAmount = priceDelta * quantity * multiplier
        }
        
        // 1. Quoted in the reporting currency already.
        if quote == reporting {
            return GrossPnlResult(amount: quoteAmount, quoteAmount: quoteAmount, quoteCurrency: quote, reportingCurrency: reporting, isConverted: true)
        }
        
        // 1b. USDT is treated as a USD stablecoin (1:1) so stablecoin pairs keep their P&L.
        if quote == "USDT" && reporting == "USD" {
            return GrossPnlResult(amount: quoteAmount, quoteAmount: quoteAmount, quoteCurrency: quote, reportingCurrency: reporting, isConverted: true)
        }
        
        // 2. FX pair whose base currency is the reporting currency: the trade price is an exact rate.
        if spec.isForex && spec.baseCurrency == reporting && exitPrice > 0 {
            let amount = quoteAmount / exitPrice
            return GrossPnlResult(amount: amount, quoteAmount: quoteAmount, quoteCurrency: quote, reportingCurrency: reporting, isConverted: true)
        }
        
        // 3. Configured rate table.
        if let rate = context.rateToReporting(currency: quote) {
            let amount = quoteAmount * rate
            return GrossPnlResult(amount: amount, quoteAmount: quoteAmount, quoteCurrency: quote, reportingCurrency: reporting, isConverted: true)
        }
        
        // 4. No rate available: keep the raw quote amount and flag it instead of silently mislabelling it.
        AppLogger.warning("No \(quote)->\(reporting) rate configured; \(symbol) P&L of \(quoteAmount) could not be converted.")
        return GrossPnlResult(amount: quoteAmount, quoteAmount: quoteAmount, quoteCurrency: quote, reportingCurrency: reporting, isConverted: false)
    }
    
    /// Convenience wrapper returning only the converted amount.
    public static func calculateGrossPnl(
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal,
        customMultiplier: Decimal? = nil,
        conversionRates: [String: Decimal] = [:],
        reportingCurrency: String = "USD"
    ) -> Decimal {
        let context = CurrencyContext(reportingCurrency: reportingCurrency, rates: conversionRates, isEnabled: true)
        return calculateGrossPnlDetailed(
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            customMultiplier: customMultiplier,
            context: context
        ).amount
    }
    
    /// Convenience wrapper using an explicit conversion context.
    public static func calculateGrossPnl(
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal,
        customMultiplier: Decimal? = nil,
        context: CurrencyContext
    ) -> Decimal {
        calculateGrossPnlDetailed(
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            customMultiplier: customMultiplier,
            context: context
        ).amount
    }
    
    // MARK: - Pips & Points Decomposition
    
    /// Computes point and pip movement between entry and exit prices.
    /// `points` is the raw price difference, `pips` expresses it in instrument pips.
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
    
    /// Formats human-readable pip and point movement string (e.g. "+4.00 giá (+40.0 pips)").
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
