import Foundation
import Combine

/// Dedicated ViewModel for AddTradeSheet.
/// Encapsulates trade form state, input parsing, live P&L computation, and validation.
/// Part of Item 3: MVVM ViewModel Architecture.
@MainActor
public final class AddTradeViewModel: ObservableObject {
    @Published public var accountId: String = ""
    @Published public var symbol: String = ""
    @Published public var direction: TradeDirection = .long
    @Published public var isClosed: Bool = true
    @Published public var quantityText: String = "1"
    @Published public var entryPriceText: String = ""
    @Published public var exitPriceText: String = ""
    @Published public var openedAt: Date
    @Published public var closedAt: Date
    @Published public var feeText: String = "0"
    @Published public var stopLossText: String = ""
    @Published public var profitTargetText: String = ""
    @Published public var selectedPlaybookId: String = ""
    @Published public var ruleAssessments: [String: Bool] = [:]
    @Published public var rating: Int = 0
    @Published public var notes: String = ""
    @Published public var tags: [String] = []
    @Published public var mistakes: [String] = []
    @Published public var showCryptoSymbols: Bool = false
    @Published public var errorMessage: String? = nil

    public init(initialDate: Date = Date()) {
        self.openedAt = initialDate
        self.closedAt = initialDate
    }

    public var quantity: Decimal {
        Decimal(string: quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    public var entryPrice: Decimal {
        Decimal(string: entryPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    public var exitPrice: Decimal? {
        guard isClosed, !exitPriceText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: exitPriceText.replacingOccurrences(of: ",", with: "."))
    }

    public var fee: Decimal {
        Decimal(string: feeText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    public var stopLoss: Decimal? {
        guard !stopLossText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: stopLossText.replacingOccurrences(of: ",", with: "."))
    }

    public var profitTarget: Decimal? {
        guard !profitTargetText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Decimal(string: profitTargetText.replacingOccurrences(of: ",", with: "."))
    }

    public var symbolSpec: AssetContractEngine.SymbolSpec {
        AssetContractEngine.spec(for: symbol)
    }

    public func estimatedPnl(dataStore: TradeDataStore) -> Decimal? {
        guard let exit = exitPrice, entryPrice > 0, quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: exit,
            customMultiplier: AssetContractEngine.customMultiplier(for: symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: dataStore.currencyConversion.reportingCurrency
        )
        return gross - fee
    }

    public var estimatedDeltaText: String? {
        guard let exit = exitPrice, entryPrice > 0 else { return nil }
        return AssetContractEngine.formatDeltaText(
            symbol: symbol,
            entryPrice: entryPrice,
            exitPrice: exit,
            direction: direction
        )
    }

    public var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        quantity > 0 &&
        entryPrice > 0 &&
        (!isClosed || (exitPrice.map { $0 > 0 } ?? false))
    }

    public func saveTrade(dataStore: TradeDataStore, onSuccess: () -> Void) {
        guard isValid else {
            errorMessage = "Please enter valid symbol, quantity, and price."
            return
        }

        let targetAccId = accountId.isEmpty ? dataStore.selectedAccountId : accountId

        dataStore.addManualTrade(
            accountId: targetAccId,
            symbol: symbol,
            direction: direction,
            quantity: quantity,
            entryPrice: entryPrice,
            exitPrice: isClosed ? exitPrice : nil,
            openedAt: openedAt,
            closedAt: isClosed ? closedAt : nil,
            fee: fee,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            tags: tags,
            mistakes: mistakes,
            rating: rating > 0 ? rating : nil,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            ruleAssessments: ruleAssessments
        )

        onSuccess()
    }
}
