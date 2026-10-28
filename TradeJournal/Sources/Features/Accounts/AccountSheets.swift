import SwiftUI

/// Sheet to create a new trading account
public struct CreateAccountSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var broker: String = "IC Markets"
    @State private var currency: String = "USD"
    @State private var initialBalanceText: String = ""
    @State private var calcMethod: ProfitCalcMethod = .fifo
    
    private let commonBrokers = ["IC Markets", "Pepperstone", "The5ers", "FTMO", "FxPro", "FundingPips", "Topstep", "Oanda", "Binance", "Manual"]
    private let commonCurrencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account & Broker")) {
                    TextField("Account name (e.g. IC Markets Live #5123981)", text: $name)
                    
                    AppDropdownField(
                        label: "Broker",
                        selection: $broker,
                        options: commonBrokers,
                        titleFor: { $0 }
                    )
                }
                
                Section(header: Text("Financials & Calculation Method")) {
                    AppDropdownField(
                        label: "Currency",
                        selection: $currency,
                        options: commonCurrencies,
                        titleFor: { $0 }
                    )
                    
                    TextField("Initial balance (e.g. 10000)", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    
                    AppDropdownField(
                        label: "P&L Method",
                        selection: $calcMethod,
                        options: [ProfitCalcMethod.fifo, ProfitCalcMethod.lifo, ProfitCalcMethod.wavg],
                        titleFor: { method in
                            switch method {
                            case .fifo: return "FIFO (First In First Out)"
                            case .lifo: return "LIFO (Last In First Out)"
                            case .wavg: return "Weighted Average"
                            }
                        }
                    )
                }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let bal = Decimal(string: initialBalanceText) ?? 0
                        dataStore.addAccount(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            broker: broker,
                            currency: currency,
                            initialBalance: bal,
                            profitCalcMethod: calcMethod
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .font(AppTypography.headline)
                }
            }
        }
    }
}

/// Sheet to edit an existing trading account
public struct EditAccountSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    let account: Account
    
    @State private var name: String
    @State private var broker: String
    @State private var currency: String
    @State private var initialBalanceText: String
    @State private var kind: AccountKind
    
    private let commonBrokers = ["IC Markets", "Pepperstone", "The5ers", "FTMO", "FxPro", "FundingPips", "Topstep", "Oanda", "Binance", "Manual"]
    private let commonCurrencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD"]
    
    public init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _broker = State(initialValue: account.broker)
        _currency = State(initialValue: account.currency)
        _initialBalanceText = State(initialValue: "\(account.initialBalance)")
        _kind = State(initialValue: account.kind)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account & Broker")) {
                    TextField("Account name", text: $name)
                    
                    AppDropdownField(
                        label: "Broker",
                        selection: $broker,
                        options: commonBrokers,
                        titleFor: { $0 }
                    )
                }
                
                Section(header: Text("Financials")) {
                    AppDropdownField(
                        label: "Currency",
                        selection: $currency,
                        options: commonCurrencies,
                        titleFor: { $0 }
                    )
                    
                    TextField("Initial balance (e.g. 10000)", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }
            }
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let bal = Decimal(string: initialBalanceText) ?? account.initialBalance
                        dataStore.updateAccount(
                            id: account.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            broker: broker,
                            kind: kind,
                            currency: currency,
                            initialBalance: bal
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .font(AppTypography.headline)
                }
            }
        }
    }
}
