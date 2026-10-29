import SwiftUI

// MARK: - New Prop Account Sheet

public struct NewPropAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultCurrency: String
    var initialFirm: String = "Topstep"
    var initialProgram: PropProgram = .evaluation
    var initialSizeText: String = ""
    var parentId: String? = nil
    
    @State private var firm: String
    @State private var name: String = ""
    @State private var program: PropProgram
    @State private var sizeText: String
    @State private var notes: String = ""
    
    var onSave: (PropAccountItem) -> Void
    
    public init(
        defaultCurrency: String,
        initialFirm: String = "Topstep",
        initialProgram: PropProgram = .evaluation,
        initialSizeText: String = "",
        parentId: String? = nil,
        onSave: @escaping (PropAccountItem) -> Void
    ) {
        self.defaultCurrency = defaultCurrency
        self.initialFirm = initialFirm
        self.initialProgram = initialProgram
        self.initialSizeText = initialSizeText
        self.parentId = parentId
        self.onSave = onSave
        _firm = State(initialValue: initialFirm)
        _program = State(initialValue: initialProgram)
        _sizeText = State(initialValue: initialSizeText)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                if let pId = parentId {
                    Section("Lineage Link") {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(AppColors.accent)
                            Text("Next phase (Parent: \(pId))")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
                
                Section("Firm & Account Name") {
                    TextField("Firm name (Topstep, FTMO, Apex...)", text: $firm)
                    TextField("Account name", text: $name)
                }
                
                Section("Program Type & Size") {
                    AppDropdownField(
                        label: "Stage",
                        selection: $program,
                        options: PropProgram.allCases,
                        titleFor: { $0.label }
                    )
                    TextField("Account size (\(defaultCurrency))", text: $sizeText)
                        .keyboardType(.numberPad)
                }
                
                Section("Notes") {
                    TextField("Drawdown rules, profit targets...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle(parentId == nil ? "Track account" : "Next stage / Phase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let sizeMinor = (Int64(sizeText) ?? 0) * 100
                        
                        let acc = PropAccountItem(
                            firm: firm,
                            name: name.isEmpty ? "\(firm) Account" : name,
                            program: program,
                            status: .active,
                            currency: defaultCurrency,
                            sizeMinor: sizeMinor,
                            parentId: parentId,
                            openedOn: today,
                            notes: notes
                        )
                        onSave(acc)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit Prop Account Sheet

public struct EditPropAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: PropAccountItem
    var onSave: (PropAccountItem) -> Void
    
    @State private var name: String
    @State private var status: PropStatus
    @State private var notes: String
    @State private var renewalDateText: String
    @State private var renewalAmountText: String
    @State private var closedDateText: String
    @State private var showDeleteConfirm: Bool = false
    
    public init(account: PropAccountItem, onSave: @escaping (PropAccountItem) -> Void) {
        self.account = account
        self.onSave = onSave
        _name = State(initialValue: account.name)
        _status = State(initialValue: account.status)
        _notes = State(initialValue: account.notes)
        _renewalDateText = State(initialValue: account.renewalOn ?? "")
        _renewalAmountText = State(initialValue: account.renewalMinor.map { String($0 / 100) } ?? "")
        _closedDateText = State(initialValue: account.closedOn ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Firm & Account Name") {
                    Text("Firm: \(account.firm)")
                        .foregroundColor(AppColors.secondaryText)
                    TextField("Account name", text: $name)
                }
                
                Section("Status") {
                    AppDropdownField(
                        label: "Account Status",
                        selection: $status,
                        options: PropStatus.allCases,
                        titleFor: { $0.label }
                    )
                    if status == .passed || status == .breached || status == .closed {
                        TextField("Closed date (YYYY-MM-DD)", text: $closedDateText)
                    }
                }
                
                Section("Renewal Reminder") {
                    TextField("Next renewal date (YYYY-MM-DD)", text: $renewalDateText)
                    TextField("Renewal fee (\(account.currency))", text: $renewalAmountText)
                        .keyboardType(.numberPad)
                }
                
                Section("Notes") {
                    TextField("Account notes...", text: $notes)
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Prop Account")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.loss)
                            Spacer()
                        }
                    }
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = account
                        let cleanName = name.trimmingCharacters(in: .whitespaces)
                        updated.name = cleanName.isEmpty ? account.name : cleanName
                        updated.status = status
                        updated.notes = notes
                        let cleanClosed = closedDateText.trimmingCharacters(in: .whitespaces)
                        updated.closedOn = cleanClosed.isEmpty ? nil : cleanClosed
                        let cleanRenewal = renewalDateText.trimmingCharacters(in: .whitespaces)
                        updated.renewalOn = cleanRenewal.isEmpty ? nil : cleanRenewal
                        if let rAmt = Int64(renewalAmountText.trimmingCharacters(in: .whitespaces)) {
                            updated.renewalMinor = rAmt * 100
                        } else {
                            updated.renewalMinor = nil
                        }
                        updated.revision += 1
                        updated.updatedAt = JournalIds.nowIso()
                        onSave(updated)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete “\(account.name)”? ", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete permanently", role: .destructive) {
                    TradeDataStore.shared.deletePropAccount(id: account.id)
                    dismiss()
                }
            } message: {
                Text("This will permanently remove this prop account and all its transactions from your device and Supabase.")
            }
        }
    }
}

// MARK: - Prop Audit Trail Sheet

public struct PropAuditTrailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: TradeDataStore
    let audits: [PropAuditItem]
    
    public init(audits: [PropAuditItem]) {
        self.audits = audits
    }
    
    public var body: some View {
        NavigationStack {
            List {
                if audits.isEmpty {
                    Text("No audit history recorded.")
                        .foregroundColor(AppColors.secondaryText)
                } else {
                    ForEach(audits.reversed()) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(a.entityType.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                                Spacer()
                                Text(a.createdAt.prefix(19))
                                    .font(.system(size: 10))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Text(a.reason)
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            let entityName: String = {
                                if let acc = dataStore.propAccounts.first(where: { $0.id == a.entityId }) {
                                    return Formatters.cleanAccountName(acc.name)
                                }
                                if let acc = dataStore.accounts.first(where: { $0.id == a.entityId }) {
                                    return Formatters.cleanAccountName(acc.name)
                                }
                                return Formatters.formatEntityId(a.entityId)
                            }()
                            Text("Target: \(entityName)")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Prop Audit Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - New Prop Entry Sheet

public struct NewPropEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [PropAccountItem]
    let defaultCurrency: String
    
    @State private var selectedAccountId: String = ""
    @State private var firm: String = "Topstep"
    @State private var kind: String = "expense"
    @State private var category: PropExpenseCategory = .evaluation
    @State private var amountText: String = ""
    @State private var splitText: String = "90"
    @State private var feeText: String = "0"
    @State private var notes: String = ""
    
    var onSave: (PropEntryItem) -> Void
    
    public init(accounts: [PropAccountItem], defaultCurrency: String, onSave: @escaping (PropEntryItem) -> Void) {
        self.accounts = accounts
        self.defaultCurrency = defaultCurrency
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Linked Account") {
                    let accountOptions = [""] + accounts.map { $0.id }
                    AppDropdownField(
                        label: "Account",
                        selection: $selectedAccountId,
                        options: accountOptions,
                        titleFor: { id in
                            if id.isEmpty { return "Shared firm cost" }
                            if let a = accounts.first(where: { $0.id == id }) {
                                return "\(a.firm) - \(a.name)"
                            }
                            return id
                        }
                    )
                }
                
                Section("Classification") {
                    AppDropdownField(
                        label: "Transaction Type",
                        selection: $kind,
                        options: ["expense", "payout"],
                        titleFor: { $0 == "expense" ? "Expense (Fee, reset...)" : "Payout request" }
                    )
                    
                    if kind == "expense" {
                        AppDropdownField(
                            label: "Expense Category",
                            selection: $category,
                            options: PropExpenseCategory.allCases,
                            titleFor: { $0.label }
                        )
                    }
                }
                
                Section("Amount") {
                    TextField("Amount (\(defaultCurrency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    
                    if kind == "payout" {
                        TextField("Trader split (%) (e.g. 90)", text: $splitText)
                            .keyboardType(.numberPad)
                        TextField("Transfer fee (\(defaultCurrency))", text: $feeText)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Notes") {
                    TextField("Invoice number, context...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle("Record expense / Payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: defaultCurrency)) ?? 0
                        let feeMinor = (try? PropFirmEngine.toMinor(value: feeText, currency: defaultCurrency)) ?? 0
                        let splitBps = ((Int(splitText) ?? 100) * 100)
                        
                        let linkedAcc = accounts.first(where: { $0.id == selectedAccountId })
                        let firmName = linkedAcc?.firm ?? firm
                        
                        let entry = PropEntryItem(
                            accountId: selectedAccountId.isEmpty ? nil : selectedAccountId,
                            firm: firmName,
                            kind: kind,
                            category: kind == "payout" ? "payout" : category.rawValue,
                            currency: defaultCurrency,
                            amountMinor: minor,
                            splitBps: splitBps,
                            feeMinor: feeMinor,
                            occurredOn: today,
                            status: kind == "payout" ? .requested : .completed,
                            notes: notes
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Receipt Sheet

public struct AddReceiptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payout: PropEntryItem
    
    @State private var amountText: String = ""
    @State private var isReversal: Bool = false
    @State private var reference: String = ""
    @State private var notes: String = ""
    
    var onAdd: (PropReceiptItem) -> Void
    
    public init(payout: PropEntryItem, onAdd: @escaping (PropReceiptItem) -> Void) {
        self.payout = payout
        self.onAdd = onAdd
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Payout Details") {
                    Text("Firm: \(payout.firm)")
                    Text("Expected payout: \(Formatters.formatCurrency(Decimal(PropFirmEngine.expectedPayout(entry: payout)) / 100, currency: payout.currency))")
                }
                
                Section("Cash Settlement") {
                    Toggle("Reversal / Return?", isOn: $isReversal)
                    TextField("Actual amount received (\(payout.currency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Bank reference (Deel, Wise...)", text: $reference)
                }
                
                Section("Notes") {
                    TextField("Additional notes...", text: $notes)
                }
            }
            .navigationTitle("Record payout receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: payout.currency)) ?? 0
                        
                        let rcpt = PropReceiptItem(
                            payoutId: payout.id,
                            kind: isReversal ? "reversal" : "receipt",
                            amountMinor: minor,
                            occurredOn: today,
                            reference: reference,
                            notes: notes
                        )
                        onAdd(rcpt)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Refund Sheet

public struct AddRefundSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expense: PropEntryItem
    
    @State private var amountText: String = ""
    @State private var notes: String = "Evaluation fee refund after passing"
    
    var onRefund: (PropEntryItem) -> Void
    
    public init(expense: PropEntryItem, onRefund: @escaping (PropEntryItem) -> Void) {
        self.expense = expense
        self.onRefund = onRefund
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("In prop trading, evaluation or challenge fees are often reimbursed by the firm upon passing and reaching the first payout. Recording a fee refund reduces your net spend.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                } header: {
                    Text("Fee reimbursement")
                }
                
                Section("Original Expense") {
                    Text("Firm: \(expense.firm)")
                    Text("Amount spent: \(Formatters.formatCurrency(Decimal(expense.amountMinor) / 100, currency: expense.currency))")
                }
                
                Section("Refund Details") {
                    TextField("Refunded amount (\(expense.currency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Notes...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle("Record fee refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: expense.currency)) ?? 0
                        
                        let refundEntry = PropEntryItem(
                            accountId: expense.accountId,
                            firm: expense.firm,
                            kind: "refund",
                            category: "refund",
                            currency: expense.currency,
                            amountMinor: minor,
                            occurredOn: today,
                            status: .completed,
                            parentId: expense.id,
                            notes: notes
                        )
                        onRefund(refundEntry)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Prop CSV Import Sheet

public struct PropCsvImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var csvContent: String = ""
    @State private var importResult: PropCsvImportResult? = nil
    @State private var errorMessage: String? = nil
    @State private var isImporting: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Standard CSV Template (/prop-cash-template.csv)") {
                    Text("id,kind,firm,account_id,currency,date,amount,category,expense_id,reference,notes")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Section("CSV Content") {
                    TextEditor(text: $csvContent)
                        .frame(minHeight: 160)
                        .font(.system(size: 12, design: .monospaced))
                    
                    if let err = errorMessage {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                }
                
                if let res = importResult {
                    Section("Import Preview") {
                        Text("Valid rows to import: \(res.imported)")
                            .foregroundColor(AppColors.profit)
                        Text("Duplicate rows skipped: \(res.skipped)")
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .navigationTitle("Import Prop CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if importResult == nil {
                        Button("Preview") {
                            do {
                                errorMessage = nil
                                let res = try dataStore.importPropCsvData(csvText: csvContent, preview: true)
                                importResult = res
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Import now") {
                            do {
                                errorMessage = nil
                                _ = try dataStore.importPropCsvData(csvText: csvContent, preview: false)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }
}
