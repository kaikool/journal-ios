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
    
    private let availableCurrencies = ["USD", "VND"]
    
    public init() {}
    
    public var body: some View {
        SettingsCard(title: "Currency conversion", footer: "Set reporting currency and exchange rates for combined analytics.") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Convert dashboard and calendar to reporting currency", isOn: $enabled)
                    .font(AppTypography.bodyBold)
                
                Divider()
                    .background(AppColors.border.opacity(0.4))
                
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
                }
                
                Divider()
                    .background(AppColors.border.opacity(0.4))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exchange rates")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
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
                            .frame(maxWidth: 140)
                            
                            Text(reportingCurrency)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
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
        
        // Trade P&L depends on the conversion rates, so the round trips have to be rebuilt.
        dataStore.applyCurrencyConversion(
            CurrencyConversion(
                enabled: enabled,
                reportingCurrency: reportingCurrency,
                rates: parsed
            )
        )
        statusMessage = "Conversion settings saved. Dashboard, calendar and trade figures now use these settings."
    }
}
