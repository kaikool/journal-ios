import SwiftUI

// MARK: - 2. Trading Settings View
// Ported 1:1 from `ContractMultiplierSettings` and `JournalDefaultSettings`
public struct TradingSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var multipliersText: String = ""
    @State private var multiplierStatus: String = ""
    @State private var multiplierError: String = ""
    
    // Defaults Draft State
    @State private var breakevenText: String = "0"
    @State private var breakevenMode: String = "money"
    @State private var feeRules: [FeeRule] = []
    @State private var riskRules: [RiskRule] = []
    @State private var defaultsStatus: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Contract Multipliers
            SettingsCard(title: "Contract multipliers") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Futures/options — one per line, SYMBOL=multiplier")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextEditor(text: $multipliersText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 90)
                        .padding(8)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                        )
                    
                    Text("Use the exact symbol shown on your imported trades, including the contract month when present.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("Saving multipliers recalculates existing trade P&L from fills and preserves annotations.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 12) {
                        AppButton("Save multipliers", icon: "checkmark", style: .primary, size: .compact) {
                            saveMultipliers()
                        }
                        
                        if !multiplierStatus.isEmpty {
                            Text(multiplierStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.profit)
                        }
                        if !multiplierError.isEmpty {
                            Text(multiplierError)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.loss)
                        }
                    }
                }
            }
            
            // Card 2: Breakeven, fees and risk defaults
            SettingsCard(title: "Breakeven, fees and risk defaults") {
                VStack(alignment: .leading, spacing: 16) {
                    // Breakeven Range
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Breakeven range (±)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("0", text: $breakevenText)
                            .font(AppTypography.inputText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Range unit", selection: $breakevenMode) {
                            Text("Account currency").tag("money")
                            Text("% of entry notional").tag("percent")
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Closed trades within this net P&L range count as breakeven. Actual P&L is unchanged. Percentage mode uses entry price × total entry quantity × contract multiplier; configure multipliers for derivatives first.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Divider()
                    
                    // Default Fees
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default fees")
                            .font(AppTypography.headline)
                        Text("Applied to new fills with a zero fee, including explicit zeroes. Nonzero imported fees and existing fills are kept. The first matching rule wins.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        ForEach(Array(feeRules.enumerated()), id: \.element.id) { index, rule in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Rule #\(index + 1)")
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    Button(role: .destructive) {
                                        feeRules.remove(at: index)
                                    } label: {
                                        Text("Remove fee rule")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.loss)
                                    }
                                }
                                
                                HStack {
                                    Picker("Account", selection: $feeRules[index].accountId) {
                                        Text("All accounts").tag("")
                                        ForEach(dataStore.accounts) { acc in
                                            Text(acc.name).tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    TextField("Symbol (e.g. ES)", text: $feeRules[index].symbol)
                                        .font(AppTypography.inputText)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack {
                                    TextField("Amount", value: $feeRules[index].amount, format: .number)
                                        .font(AppTypography.inputText)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 100)
                                    
                                    Picker("Mode", selection: $feeRules[index].mode) {
                                        Text("Execution").tag("execution")
                                        Text("Unit / contract").tag("unit")
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        AppButton("Add fee rule", icon: "plus", style: .outline, size: .compact) {
                            feeRules.append(FeeRule(accountId: "", symbol: "", amount: 0, mode: "execution"))
                        }
                    }
                    
                    Divider()
                    
                    // Stop & Target Defaults
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stop and target defaults")
                            .font(AppTypography.headline)
                        Text("Distances from weighted entry, adjusted for long or short direction. Applied only when a new trade is first created. The first matching rule wins.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        ForEach(Array(riskRules.enumerated()), id: \.element.id) { index, rule in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Rule #\(index + 1)")
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    Button(role: .destructive) {
                                        riskRules.remove(at: index)
                                    } label: {
                                        Text("Remove risk rule")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.loss)
                                    }
                                }
                                
                                HStack {
                                    Picker("Account", selection: $riskRules[index].accountId) {
                                        Text("All accounts").tag("")
                                        ForEach(dataStore.accounts) { acc in
                                            Text(acc.name).tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    TextField("Symbol (e.g. NQ)", text: $riskRules[index].symbol)
                                        .font(AppTypography.inputText)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Stop").font(AppTypography.caption)
                                        TextField("Stop", value: $riskRules[index].stop, format: .number)
                                            .font(AppTypography.inputText)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Target").font(AppTypography.caption)
                                        TextField("Target", value: $riskRules[index].target, format: .number)
                                            .font(AppTypography.inputText)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unit").font(AppTypography.caption)
                                        Picker("Mode", selection: $riskRules[index].mode) {
                                            Text("Price pts").tag("price")
                                            Text("% entry").tag("percent")
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        AppButton("Add risk rule", icon: "plus", style: .outline, size: .compact) {
                            riskRules.append(RiskRule(accountId: "", symbol: "", stop: 1, target: 2, mode: "price"))
                        }
                    }
                    
                    HStack(spacing: 12) {
                        AppButton("Save defaults", icon: "checkmark", style: .primary, size: .compact) {
                            let be = Decimal(string: breakevenText) ?? 0
                            dataStore.defaults = JournalDefaults(
                                breakeven: be,
                                breakevenMode: breakevenMode,
                                feeRules: feeRules,
                                riskRules: riskRules
                            )
                            dataStore.saveToDisk()
                            defaultsStatus = "Defaults saved."
                        }
                        
                        if !defaultsStatus.isEmpty {
                            Text(defaultsStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                }
            }
        }
        .onAppear {
            multipliersText = dataStore.multipliers
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "\n")
            
            breakevenText = "\(dataStore.defaults.breakeven)"
            breakevenMode = dataStore.defaults.breakevenMode
            feeRules = dataStore.defaults.feeRules
            riskRules = dataStore.defaults.riskRules
        }
    }
    
    private func saveMultipliers() {
        multiplierError = ""
        multiplierStatus = ""
        var parsed: [String: Decimal] = [:]
        let lines = multipliersText.split(separator: "\n")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  let val = Decimal(string: parts[1]),
                  val > 0 else {
                multiplierError = "Check line \(index + 1): enter a unique symbol and a positive multiplier, such as ESU6=50."
                return
            }
            parsed[parts[0].uppercased()] = val
        }
        
        dataStore.multipliers = parsed
        dataStore.rebuildAllAccounts(forceRebuildTrades: true)
        dataStore.saveToDisk()
        multiplierStatus = "Contract multipliers saved."
    }
}
