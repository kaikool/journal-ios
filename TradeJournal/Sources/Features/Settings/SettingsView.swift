import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showNewAccountSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportedJsonString: String = ""
    @State private var showResetConfirmation: Bool = false
    
    private let timeZones: [String] = [
        "UTC",
        "America/New_York",
        "America/Chicago",
        "Europe/London",
        "Europe/Berlin",
        "Asia/Dubai",
        "Asia/Bangkok",
        "Asia/Singapore",
        "Asia/Tokyo"
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section: Active Account
                Section("Tài Khoản Giao Dịch") {
                    if let selected = dataStore.selectedAccount {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.name)
                                    .font(AppTypography.subheadlineBold)
                                Text("Số dư gốc: \(Formatters.formatCurrency(selected.initialBalance, currency: selected.currency)) • \(selected.profitCalcMethod.rawValue.uppercased())")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.profit)
                        }
                    }
                    
                    Picker("Chọn tài khoản", selection: $dataStore.selectedAccountId) {
                        ForEach(dataStore.accounts) { acc in
                            Text(acc.name).tag(acc.id)
                        }
                    }
                    
                    Button(action: { showNewAccountSheet = true }) {
                        Label("Thêm tài khoản giao dịch mới", systemImage: "plus.circle")
                            .foregroundColor(AppColors.accent)
                    }
                }
                
                // Section: Display & Timezone
                Section("Tùy Chọn Hiển Thị & Múi Giờ") {
                    Toggle("Chế độ riêng tư (Ẩn số dư)", isOn: $env.isPrivacyModeEnabled)
                    
                    Picker("Đơn vị tiền tệ chính", selection: $env.currentCurrency) {
                        Text("USD ($)").tag("USD")
                        Text("EUR (€)").tag("EUR")
                        Text("GBP (£)").tag("GBP")
                        Text("JPY (¥)").tag("JPY")
                        Text("VND (₫)").tag("VND")
                    }
                    
                    Picker("Múi giờ phân tích", selection: Binding(
                        get: { env.currentTimeZone.identifier },
                        set: { newId in env.currentTimeZone = TimeZone(identifier: newId) ?? .current }
                    )) {
                        ForEach(timeZones, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                }
                
                // Section: Backup & Export
                Section("Sao Lưu Dữ Liệu & Xuất File") {
                    Button(action: { exportFullJsonBackup() }) {
                        Label("Xuất bản sao lưu JSON toàn bộ", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: { showResetConfirmation = true }) {
                        Label("Xóa sạch dữ liệu mẫu & nạp lại", systemImage: "trash")
                    }
                }
                
                // Section: Supabase & Auth
                Section("Hạ Tầng & Backend") {
                    HStack {
                        Text("Trạng thái phiên")
                        Spacer()
                        Text("Khách / Cục bộ (Chưa bắt buộc đăng nhập)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack {
                        Text("Nền tảng")
                        Spacer()
                        Text("iOS 17+ Native SwiftUI")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack {
                        Text("Backend")
                        Spacer()
                        Text("Supabase PostgreSQL + RLS")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                // Section: App Info
                Section("Thông Tin Ứng Dụng") {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0.0 (Master Release)")
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack {
                        Text("Kiến trúc")
                        Spacer()
                        Text("Clean MVVM • Swift Concurrency • Swift Charts")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .navigationTitle("Cài Đặt")
            .sheet(isPresented: $showNewAccountSheet) {
                NewTradingAccountSheet { newAcc in
                    dataStore.accounts.append(newAcc)
                    dataStore.selectAccount(id: newAcc.id)
                }
            }
            .sheet(isPresented: $showExportSheet) {
                JsonShareSheet(jsonText: exportedJsonString)
            }
            .alert("Xác nhận xóa dữ liệu?", isPresented: $showResetConfirmation) {
                Button("Xóa tất cả", role: .destructive) {
                    dataStore.executions.removeAll()
                    dataStore.trades.removeAll()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Hành động này sẽ xóa các lệnh hiện tại trong bộ nhớ. Bạn có thể import lại file CSV bất cứ lúc nào.")
            }
        }
    }
    
    private func exportFullJsonBackup() {
        struct FullBackup: Codable {
            let exportedAt: Date
            let accounts: [Account]
            let executions: [Execution]
            let trades: [Trade]
            let folders: [NotebookFolder]
            let notebookNotes: [NotebookNote]
            let propAccounts: [PropAccountItem]
            let propEntries: [PropEntryItem]
            let propReceipts: [PropReceiptItem]
            let propAudits: [PropAuditItem]
            let attachments: [Attachment]
        }
        
        let backup = FullBackup(
            exportedAt: Date(),
            accounts: dataStore.accounts,
            executions: dataStore.executions,
            trades: dataStore.trades,
            folders: dataStore.folders,
            notebookNotes: dataStore.notebookNotes,
            propAccounts: dataStore.propAccounts,
            propEntries: dataStore.propEntries,
            propReceipts: dataStore.propReceipts,
            propAudits: dataStore.propAudits,
            attachments: dataStore.attachments
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(backup), let str = String(data: data, encoding: .utf8) {
            self.exportedJsonString = str
            self.showExportSheet = true
        }
    }
}

// MARK: - New Trading Account Sheet

public struct NewTradingAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var initialBalanceText: String = "10000"
    @State private var currency: String = "USD"
    @State private var calcMethod: ProfitCalcMethod = .fifo
    
    var onSave: (Account) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Tên tài khoản") {
                    TextField("VD: Futures Live, Forex Demo...", text: $name)
                }
                
                Section("Số dư ban đầu & Tiền tệ") {
                    TextField("Số dư", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                    
                    Picker("Đơn vị tiền tệ", selection: $currency) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("VND").tag("VND")
                    }
                }
                
                Section("Phương pháp khớp lệnh đóng") {
                    Picker("Quy tắc", selection: $calcMethod) {
                        Text("FIFO (Nhập trước xuất trước)").tag(ProfitCalcMethod.fifo)
                        Text("LIFO (Nhập sau xuất trước)").tag(ProfitCalcMethod.lifo)
                        Text("WAVG (Bình quân gia quyền)").tag(ProfitCalcMethod.wavg)
                    }
                }
            }
            .navigationTitle("Tạo tài khoản mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let bal = Decimal(string: initialBalanceText) ?? 10000
                        let acc = Account(
                            name: name.isEmpty ? "New Account" : name,
                            currency: currency,
                            initialBalance: bal,
                            profitCalcMethod: calcMethod
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

// MARK: - JSON Share Sheet

public struct JsonShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jsonText: String
    
    public var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: .constant(jsonText))
                    .font(.system(size: 11, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Bản Sao Lưu JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: jsonText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
