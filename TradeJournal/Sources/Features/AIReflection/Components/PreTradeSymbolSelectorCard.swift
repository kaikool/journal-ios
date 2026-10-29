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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Text(selectedSymbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                }
                
                // Popular Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(popularSymbols, id: \.self) { sym in
                            let isSel = selectedSymbol == sym
                            Button(action: {
                                selectedSymbol = sym
                                onSelectSymbol(sym)
                            }) {
                                Text(sym)
                                    .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSel ? AppColors.brand.opacity(0.15) : AppColors.secondaryBackground)
                                    .foregroundColor(isSel ? AppColors.brand : AppColors.primaryText)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(isSel ? AppColors.brand.opacity(0.5) : AppColors.border.opacity(0.5), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Custom Symbol Input Field
                HStack(spacing: 8) {
                    TextField("Enter symbol (e.g. USDCAD, NVDA, SOLUSDT)...", text: $customSymbolText)
                        .font(AppTypography.inputText)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                        )
                        .onSubmit {
                            onSubmitCustom()
                        }
                    
                    Button(action: onSubmitCustom) {
                        Text("Analyze")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(customSymbolText.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
                            .cornerRadius(8)
                    }
                    .disabled(customSymbolText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
