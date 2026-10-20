import SwiftUI

// MARK: - 3. Currency Conversion Settings View
// Ported 1:1 from `CurrencySettings` in `currency-settings.tsx`
public struct CurrencyConversionSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var enabled: Bool = false
    @State private var reportingCurrency: String = "USD"
    @State private var rates: [String: String] = [:]
    @State private var statusMessage: String = ""
    @State private var errorMessage: String = ""
    
    private let availableCurrencies = ["USD", "EUR", "GBP", "JPY", "VND", "AUD", "CAD", "CHF"]
    
    public init() {}
    
    public var body: some View {
        SettingsCard(title: "Currency conversion") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Combine accounts using your own saved exchange rates. Works entirely offline.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Toggle("Convert dashboard and calendar to the reporting currency", isOn: $enabled)
                    .font(AppTypography.subheadlineBold)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reporting currency")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    AppleMenuChip(title: "Reporting currency", selectionText: reportingCurrency, icon: "dollarsign.circle") {
                        ForEach(availableCurrencies, id: \.self) { c in
                            Button(c) {
                                reportingCurrency = c
                            }
                        }
                    }
                    
                    Text("Changing the reporting currency clears the draft rates. Enter new rates before saving.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Exchange rates")
                        .font(AppTypography.headline)
                    
                    ForEach(allCurrencies, id: \.self) { code in
                        HStack(spacing: 8) {
                            Text("1 \(code) =")
                                .font(AppTypography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            
                            TextField("Rate", text: Binding(
                                get: { code == reportingCurrency ? "1" : (rates[code] ?? "") },
                                set: { rates[code] = $0 }
                            ))
                            .font(AppTypography.inputText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .disabled(code == reportingCurrency)
                            .frame(maxWidth: 120)
                            
                            Text(reportingCurrency)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                Text("These are fixed baseline rates, not live market rates. Changing saved rates recalculates all dashboard and calendar history, including starting balances and drawdown. Original account records, trade details and reports keep their account currencies.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                HStack(spacing: 12) {
                    AppButton("Save rates", icon: "checkmark", style: .primary, size: .compact) {
                        saveConversion()
                    }
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.profit)
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
        }
        .onAppear {
            let config = dataStore.currencyConversion
            enabled = config.enabled
            reportingCurrency = config.reportingCurrency
            rates = config.rates.mapValues { Formatters.formatDecimalInput($0, maxDecimals: 5) }
        }
    }
    
    private var allCurrencies: [String] {
        var set = Set(availableCurrencies)
        set.insert(reportingCurrency)
        for acc in dataStore.accounts {
            set.insert(acc.currency)
        }
        return Array(set).sorted()
    }
    
    private func saveConversion() {
        errorMessage = ""
        statusMessage = ""
        var parsed: [String: Decimal] = [:]
        
        for code in allCurrencies {
            if code == reportingCurrency {
                parsed[code] = 1.0
                continue
            }
            if let str = rates[code], let val = Decimal(string: str), val > 0 {
                parsed[code] = val
            } else if enabled {
                errorMessage = "Enter a positive rate for \(code) before enabling conversion."
                return
            }
        }
        
        dataStore.currencyConversion = CurrencyConversion(
            enabled: enabled,
            reportingCurrency: reportingCurrency,
            rates: parsed
        )
        dataStore.saveToDisk()
        statusMessage = "Conversion settings saved. Dashboard and calendar figures now use these settings."
    }
}
