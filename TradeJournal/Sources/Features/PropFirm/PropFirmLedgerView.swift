import SwiftUI

public enum PropLedgerTab: String, CaseIterable, Identifiable {
    case accounts = "Tài khoản"
    case cashFlow = "Dòng tiền"
    case payouts = "Payouts"
    
    public var id: String { rawValue }
}

public struct PropFirmLedgerView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedTab: PropLedgerTab = .accounts
    @State private var accounts: [PropAccountItem] = [
        PropAccountItem(
            id: "prop-1",
            firm: "Topstep",
            name: "Topstep 50K Express Funded",
            program: .funded,
            status: .active,
            currency: "USD",
            sizeMinor: 50_000_00,
            openedOn: "2026-09-01",
            notes: "Tài khoản live Funded, quy tắc daily loss 1,000 USD."
        ),
        PropAccountItem(
            id: "prop-2",
            firm: "FTMO",
            name: "FTMO 100K Normal Challenge",
            program: .evaluation,
            status: .passed,
            currency: "USD",
            sizeMinor: 100_000_00,
            openedOn: "2026-08-15",
            notes: "Đã qua vòng 1 với lợi nhuận 10.2%."
        )
    ]
    
    @State private var entries: [PropEntryItem] = [
        PropEntryItem(
            id: "entry-1",
            accountId: "prop-1",
            firm: "Topstep",
            kind: "expense",
            category: "activation",
            currency: "USD",
            amountMinor: 149_00,
            occurredOn: "2026-09-01",
            notes: "Phí kích hoạt tài khoản Express Funded"
        ),
        PropEntryItem(
            id: "entry-2",
            accountId: "prop-2",
            firm: "FTMO",
            kind: "expense",
            category: "evaluation",
            currency: "USD",
            amountMinor: 540_00,
            occurredOn: "2026-08-15",
            notes: "Phí thi gói 100k"
        ),
        PropEntryItem(
            id: "entry-3",
            accountId: "prop-1",
            firm: "Topstep",
            kind: "payout",
            category: "payout",
            currency: "USD",
            amountMinor: 2_500_00,
            splitBps: 9000, // 90%
            feeMinor: 25_00,
            occurredOn: "2026-10-01",
            status: .completed,
            notes: "Payout kỳ đầu tiên"
        )
    ]
    
    @State private var receipts: [PropReceiptItem] = [
        PropReceiptItem(
            id: "rcpt-1",
            payoutId: "entry-3",
            kind: "receipt",
            amountMinor: 2_225_00, // 2500 * 90% - 25 = 2225
            occurredOn: "2026-10-03",
            notes: "Đã nhận tiền qua Deel"
        )
    ]
    
    @State private var showNewAccountSheet: Bool = false
    @State private var showNewEntrySheet: Bool = false
    
    public init() {}
    
    private var movements: [CashMovementItem] {
        PropFirmEngine.cashMovements(entries: entries, receipts: receipts)
    }
    
    private var summary: CashSummaryResult {
        PropFirmEngine.cashSummary(rows: movements)
    }
    
    private var payoutItems: [PayoutProgressResult] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return PropFirmEngine.payoutProgress(entries: entries, receipts: receipts, today: today)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Cash Ledger Summary Card
                    AppCard {
                        VStack(spacing: 12) {
                            HStack {
                                Text("TỔNG QUAN TIỀN MẶT QUỸ (CASH LEDGER)")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                if let roi = summary.roi {
                                    AppBadge(
                                        text: String(format: "ROI: %+.1f%%", roi * 100),
                                        color: roi >= 0 ? AppColors.profit : AppColors.loss
                                    )
                                }
                            }
                            
                            HStack(alignment: .firstTextBaseline) {
                                let netDecimal = Decimal(summary.netMinor) / 100
                                Text(Formatters.formatPnL(netDecimal, currency: env.currentCurrency))
                                    .font(AppTypography.financialNumber(size: 30, weight: .bold))
                                    .foregroundColor(Formatters.pnlColor(netDecimal))
                                
                                Spacer()
                                
                                Text("Lợi nhuận ròng quỹ")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Divider().background(AppColors.border)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tổng chi (Thi + Phí)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(summary.netSpendMinor) / 100, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.loss)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Đã nhận (Payout)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(summary.receivedMinor) / 100, currency: env.currentCurrency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.profit)
                                }
                            }
                        }
                    }
                    
                    // Segmented Tab Picker
                    Picker("Mục quỹ", selection: $selectedTab) {
                        ForEach(PropLedgerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Content by Tab
                    switch selectedTab {
                    case .accounts:
                        accountsListView
                    case .cashFlow:
                        cashFlowListView
                    case .payouts:
                        payoutsProgressView
                    }
                }
                .padding()
            }
            .navigationTitle("Prop Firms")
            .background(AppColors.background)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showNewAccountSheet = true }) {
                            Label("Thêm tài khoản quỹ", systemImage: "plus.circle")
                        }
                        Button(action: { showNewEntrySheet = true }) {
                            Label("Thêm chi phí / Payout", systemImage: "dollarsign.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewAccountSheet) {
                NewPropAccountSheet { newAcc in
                    accounts.append(newAcc)
                }
            }
            .sheet(isPresented: $showNewEntrySheet) {
                NewPropEntrySheet(accounts: accounts) { newEntry in
                    entries.append(newEntry)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var accountsListView: some View {
        VStack(spacing: 12) {
            if accounts.isEmpty {
                EmptyStateView(
                    icon: "building.columns",
                    title: "Chưa có tài khoản quỹ",
                    message: "Thêm tài khoản Topstep, FTMO, The5ers... để quản lý chi phí thi và trạng thái."
                )
            } else {
                ForEach(accounts) { acc in
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(acc.firm)
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.accent)
                                Spacer()
                                AppBadge(
                                    text: acc.status.label,
                                    color: acc.status == .active || acc.status == .passed ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Text(acc.name)
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                if let size = acc.sizeMinor {
                                    Text("Size: \(Formatters.formatCurrency(Decimal(size) / 100, currency: acc.currency))")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                Text(acc.program.label)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var cashFlowListView: some View {
        VStack(spacing: 12) {
            if movements.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right",
                    title: "Chưa có dòng tiền",
                    message: "Các khoản phí thi, reset, hoàn tiền và payout nhận về sẽ hiển thị tại đây."
                )
            } else {
                ForEach(movements) { m in
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(m.firm)
                                        .font(AppTypography.subheadlineBold)
                                    AppBadge(
                                        text: m.category.capitalized,
                                        color: m.kind == "payout" || m.kind == "receipt" ? AppColors.profit : AppColors.secondaryText
                                    )
                                }
                                Text(m.date ?? "Không rõ ngày")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            let isIncoming = m.kind == "receipt" || m.kind == "refund"
                            let amountDecimal = Decimal(m.amountMinor) / 100
                            Text("\(isIncoming ? "+" : "-")\(Formatters.formatCurrency(amountDecimal, currency: m.currency))")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(isIncoming ? AppColors.profit : AppColors.loss)
                        }
                    }
                }
            }
        }
    }
    
    private var payoutsProgressView: some View {
        VStack(spacing: 12) {
            if payoutItems.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "Chưa có yêu cầu Payout",
                    message: "Theo dõi trạng thái duyệt, giải ngân và chênh lệch phí chuyển tiền của từng đợt rút quỹ."
                )
            } else {
                ForEach(payoutItems) { p in
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(p.entry.firm) Payout")
                                    .font(AppTypography.subheadlineBold)
                                Spacer()
                                AppBadge(
                                    text: p.entry.status.rawValue.capitalized,
                                    color: p.entry.status == .completed ? AppColors.profit : AppColors.accent
                                )
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dự kiến nhận:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.expectedMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Thực tế đã nhận:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.actualMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.profit)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - New Prop Account Sheet

public struct NewPropAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var firm: String = "Topstep"
    @State private var name: String = ""
    @State private var program: PropProgram = .evaluation
    @State private var sizeText: String = "50000"
    @State private var notes: String = ""
    
    var onSave: (PropAccountItem) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Quỹ & Tên tài khoản") {
                    TextField("Tên Quỹ (Topstep, FTMO, Apex...)", text: $firm)
                    TextField("Tên tài khoản gợi nhớ", text: $name)
                }
                
                Section("Loại chương trình & Quy mô") {
                    Picker("Giai đoạn", selection: $program) {
                        ForEach(PropProgram.allCases, id: \.self) { prog in
                            Text(prog.label).tag(prog)
                        }
                    }
                    TextField("Quy mô tài khoản USD", text: $sizeText)
                        .keyboardType(.numberPad)
                }
                
                Section("Ghi chú") {
                    TextField("Quy tắc drawdown, mục tiêu lãi...", text: $notes)
                }
            }
            .navigationTitle("Thêm tài khoản quỹ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let sizeMinor = (Int64(sizeText) ?? 0) * 100
                        
                        let acc = PropAccountItem(
                            firm: firm,
                            name: name.isEmpty ? "\(firm) Account" : name,
                            program: program,
                            status: .active,
                            sizeMinor: sizeMinor,
                            openedOn: today,
                            notes: notes
                        )
                        onSave(acc)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - New Prop Entry Sheet

public struct NewPropEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [PropAccountItem]
    
    @State private var selectedAccountId: String = ""
    @State private var kind: String = "expense"
    @State private var category: PropExpenseCategory = .evaluation
    @State private var amountText: String = ""
    @State private var notes: String = ""
    
    var onSave: (PropEntryItem) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Phân loại") {
                    Picker("Loại giao dịch", selection: $kind) {
                        Text("Chi phí (Phí thi, reset...)").tag("expense")
                        Text("Payout nhận về").tag("payout")
                        Text("Hoàn tiền (Refund)").tag("refund")
                    }
                    
                    if kind == "expense" {
                        Picker("Hạng mục chi phí", selection: $category) {
                            ForEach(PropExpenseCategory.allCases, id: \.self) { cat in
                                Text(cat.label).tag(cat)
                            }
                        }
                    }
                }
                
                Section("Số tiền") {
                    TextField("Số tiền (VD: 149.00)", text: $amountText)
                        .keyboardType(.decimalPad)
                }
                
                Section("Ghi chú") {
                    TextField("Ghi chú đợt thanh toán", text: $notes)
                }
            }
            .navigationTitle("Ghi nhận chi phí / Payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText)) ?? 0
                        
                        let entry = PropEntryItem(
                            firm: "Prop Firm",
                            kind: kind,
                            category: category.rawValue,
                            amountMinor: minor,
                            occurredOn: today,
                            notes: notes
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
            }
        }
    }
}
