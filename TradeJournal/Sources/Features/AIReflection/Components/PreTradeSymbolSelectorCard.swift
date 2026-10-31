import SwiftUI

// MARK: - Pre-Trade Symbol Selector Card
// Displays target asset header, quick-access symbol chips, and custom symbol text field
public struct PreTradeSymbolSelectorCard: View {
    @Binding public var selectedSymbol: String
    @Binding public var customSymbolText: String
    public let popularSymbols: [String]
    public let onSelectSymbol: (String) -> Void
    public let onSubmitCustom: () -> Void
    
    public init(
        selectedSymbol: Binding<String>,
        customSymbolText: Binding<String>,
        popularSymbols: [String] = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "BTCUSDT", "ETHUSDT", "US30", "NAS100"],
        onSelectSymbol: @escaping (String) -> Void,
        onSubmitCustom: @escaping () -> Void
    ) {
        self._selectedSymbol = selectedSymbol
        self._customSymbolText = customSymbolText
        self.popularSymbols = popularSymbols
        self.onSelectSymbol = onSelectSymbol
        self.onSubmitCustom = onSubmitCustom
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TARGET ASSET")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Text(selectedSymbol)
                        .font(AppTypography.rowPrimary)
                        .foregroundColor(AppColors.primaryText)
                }
                
                // Popular Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(popularSymbols, id: \.self) { sym in
                            let isSel = selectedSymbol == sym
                            AppFilterChip(sym, isSelected: isSel, height: 28) {
                                selectedSymbol = sym
                                onSelectSymbol(sym)
                            }
                        }
                    }
                }
                
                // Custom Symbol Input Field
                HStack(spacing: 8) {
                    AppFormField(
                        text: $customSymbolText,
                        placeholder: "Enter symbol (e.g. USDCAD, NVDA, SOLUSDT)...",
                        icon: "magnifyingglass",
                        height: 34
                    )
                    .onSubmit {
                        onSubmitCustom()
                    }
                    
                    AppPrimaryButton(
                        "Analyze",
                        isEnabled: !customSymbolText.trimmingCharacters(in: .whitespaces).isEmpty,
                        height: 32,
                        action: onSubmitCustom
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}
