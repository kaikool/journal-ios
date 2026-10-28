import Foundation

/// Conversion context describing how monetary amounts are translated into the reporting currency.
///
/// - `rates[currency]` expresses **1 unit of `currency` in units of the reporting currency**.
/// - Optional pair keys (e.g. `"USDJPY"`) are supported as a precision fallback when a currency
///   rate is not configured: `1 USDJPY` is then used to derive `JPY -> reporting`.
public struct CurrencyContext: Sendable, Equatable {
    public let reportingCurrency: String
    public let rates: [String: Decimal]
    /// Mirrors the "convert balances" toggle. Monetary conversions inside the financial engines
    /// always apply when a rate is known, because a P&L mixed across currencies is meaningless.
    public let isEnabled: Bool

    public init(reportingCurrency: String = "USD", rates: [String: Decimal] = [:], isEnabled: Bool = true) {
        self.reportingCurrency = reportingCurrency.uppercased()
        self.rates = rates.reduce(into: [String: Decimal]()) { acc, item in
            acc[item.key.uppercased()] = item.value
        }
        self.isEnabled = isEnabled
    }

    public static let `default` = CurrencyContext(
        reportingCurrency: "USD",
        rates: CurrencyConversion.default.rates,
        isEnabled: true
    )

    /// Rate converting 1 unit of `currency` into the reporting currency.
    /// Returns `nil` when no usable rate is configured.
    public func rateToReporting(currency: String) -> Decimal? {
        let code = currency.uppercased()
        guard code != reportingCurrency else { return 1 }
        if let rate = rates[code], rate > 0 { return rate }
        // Pair fallback: rates["USDJPY"] = 157.5 means 1 USD = 157.5 JPY => 1 JPY = 1/157.5 reporting
        if let pair = rates[reportingCurrency + code], pair > 0 { return 1 / pair }
        return nil
    }

    /// Rate converting 1 unit of `currency` into `target`.
    public func rate(from currency: String, to target: String) -> Decimal? {
        let from = currency.uppercased()
        let to = target.uppercased()
        if from == to { return 1 }
        guard let forward = rateToReporting(currency: from),
              let backward = rateToReporting(currency: to), backward > 0 else { return nil }
        return forward / backward
    }

    /// Converts an amount between two currencies. Returns `nil` when no rate is available.
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        guard let rate = rate(from: from, to: to) else { return nil }
        return amount * rate
    }
}
