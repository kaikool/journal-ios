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
            contractMultipliersCard
            breakevenFeeRiskCard
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
    
    // MARK: - Card 1: Contract Multipliers
    private var contractMultipliersCard: some View {
        SettingsCard(title: "Contract multipliers") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Futures/options — one per line, SYMBOL=multiplier")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                
                TextEditor(text: $multipliersText)
                    .font(AppTypography.codeBlock)
                    .frame(minHeight: 90)
                    .appSubCardStyle(cornerRadius: 10, padding: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
                
                Text("One entry per line (e.g. ESU6=50). Recalculates P&L on save.")
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
    }
    
    // MARK: - Card 2: Breakeven, fees and risk defaults
    private var breakevenFeeRiskCard: some View {
        SettingsCard(title: "Breakeven, fees and risk defaults") {
            VStack(alignment: .leading, spacing: 16) {
                breakevenSection
                Divider()
                feeRulesSection
                Divider()
                riskRulesSection
                saveDefaultsButtonRow
            }
        }
    }
    
    private var breakevenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakeven range (±)")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.secondaryText)
            
            AppNumericField(text: $breakevenText, placeholder: "0", height: 34)
            
            AppSegmentedBar(
                selection: $breakevenMode,
                items: ["money", "percent"],
                titleFor: { $0 == "money" ? "Account currency" : "% of notional" },
                height: 32
            )
        }
    }
    
    private var feeRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default fees")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.secondaryText)
            
            ForEach(Array(feeRules.enumerated()), id: \.element.id) { index, rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rule #\(index + 1)")
                            .font(AppTypography.captionBold)
                        Spacer()
                        ModalDeleteButton { feeRules.remove(at: index) }
                    }
                    
                    HStack {
                        let accIds = [""] + dataStore.accounts.map { $0.id }
                        AppCompactDropdown(
                            icon: "wallet.pass",
                            selection: $feeRules[index].accountId,
                            options: accIds,
                            titleFor: { id in
                                if id.isEmpty { return "All accounts" }
                                return dataStore.accounts.first(where: { $0.id == id })?.name ?? id
                            },
                            height: 32
                        )
                        
                        AppTextField("Symbol (e.g. ES)", text: $feeRules[index].symbol)
                            .textInputAutocapitalization(.characters)
                    }
                    
                    HStack {
                        AppDecimalField("Amount", value: $feeRules[index].amount, height: 34)
                            .frame(maxWidth: 100)
                        
                        AppSegmentedBar(
                            selection: $feeRules[index].mode,
                            items: ["execution", "unit"],
                            titleFor: { $0 == "execution" ? "Execution" : "Unit" },
                            height: 32
                        )
                    }
                }
                .appSubCardStyle(cornerRadius: 8, padding: 10)
            }
            
            AppButton("Add fee rule", icon: "plus", style: .outline, size: .compact) {
                feeRules.append(FeeRule(accountId: "", symbol: "", amount: 0, mode: "execution"))
            }
        }
    }
    
    private var riskRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stop and target defaults")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.secondaryText)
            
            ForEach(Array(riskRules.enumerated()), id: \.element.id) { index, rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rule #\(index + 1)")
                            .font(AppTypography.captionBold)
                        Spacer()
                        ModalDeleteButton { riskRules.remove(at: index) }
                    }
                    
                    HStack {
                        let accIds = [""] + dataStore.accounts.map { $0.id }
                        AppCompactDropdown(
                            icon: "wallet.pass",
                            selection: $riskRules[index].accountId,
                            options: accIds,
                            titleFor: { id in
                                if id.isEmpty { return "All accounts" }
                                return dataStore.accounts.first(where: { $0.id == id })?.name ?? id
                            },
                            height: 32
                        )
                        
                        AppTextField("Symbol (e.g. NQ)", text: $riskRules[index].symbol)
                            .textInputAutocapitalization(.characters)
                    }
                    
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stop").font(AppTypography.caption)
                            AppDecimalField("Stop", value: $riskRules[index].stop, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target").font(AppTypography.caption)
                            AppDecimalField("Target", value: $riskRules[index].target, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unit").font(AppTypography.caption)
                            AppCompactDropdown(
                                selection: $riskRules[index].mode,
                                options: ["price", "percent"],
                                titleFor: { $0 == "price" ? "Price pts" : "% entry" },
                                height: 32
                            )
                        }
                    }
                }
                .appSubCardStyle(cornerRadius: 8, padding: 10)
            }
            
            AppButton("Add risk rule", icon: "plus", style: .outline, size: .compact) {
                riskRules.append(RiskRule(accountId: "", symbol: "", stop: 1, target: 2, mode: "price"))
            }
        }
    }
    
    private var saveDefaultsButtonRow: some View {
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
            parsed[AssetContractEngine.multiplierKey(for: parts[0])] = val
        }
        
        dataStore.multipliers = parsed
        dataStore.rebuildAllAccounts(forceRebuildTrades: true)
        dataStore.saveToDisk()
        multiplierStatus = "Contract multipliers saved."
    }
}
