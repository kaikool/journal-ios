import SwiftUI

public enum AccountFilterTab: String, CaseIterable, Identifiable {
    case `default` = "Mặc định"
    case active = "Hoạt động"
    case visible = "Hiển thị"
    case all = "Tất cả"
    
    public var id: String { rawValue }
}

/// Màn hình quản lý các tài khoản giao dịch
/// Port 1:1 từ `source-repo/apps/web/src/app/accounts/page.tsx`
public struct AccountsManagerView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var filterTab: AccountFilterTab = .default
    @State private var searchText: String = ""
    @State private var showNewAccountSheet: Bool = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var syncingAccountId: String? = nil
    
    public init() {}
    
    private var accounts: [Account] {
        dataStore.accounts
    }
    
    private var defaultCount: Int {
        accounts.filter { $0.archivedAt == nil || ($0.visibleInJournal ?? true) }.count
    }
    
    private var activeCount: Int {
        accounts.filter { $0.archivedAt == nil }.count
    }
    
    private var visibleCount: Int {
        accounts.filter { $0.visibleInJournal ?? true }.count
    }
    
    private var filteredAccounts: [Account] {
        accounts.filter { acc in
            let isActive = acc.archivedAt == nil
            let isVisible = acc.visibleInJournal ?? true
            
            switch filterTab {
            case .default:
                if !isActive && !isVisible { return false }
            case .active:
                if !isActive { return false }
            case .visible:
                if !isVisible { return false }
            case .all:
                break
            }
            
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let matches = acc.name.lowercased().contains(q) ||
                              acc.broker.lowercased().contains(q) ||
                              acc.id.lowercased().contains(q) ||
                              (acc.propProgram?.lowercased().contains(q) ?? false)
                if !matches { return false }
            }
            return true
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tài Khoản")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)
                            Text("Quản lý các tài khoản giao dịch cá nhân và tài khoản quỹ")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button {
                            showNewAccountSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Tạo tài khoản")
                            }
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Filter & Search Controls (Port 1:1 từ thanh lọc Accounts)
                    filterAndSearchHeader
                    
                    // Bulk Visibility Actions
                    bulkVisibilityBar
                    
                    // Danh sách thẻ tài khoản
                    if filteredAccounts.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredAccounts) { acc in
                                accountCard(acc)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showNewAccountSheet) {
                CreateAccountSheet()
            }
            .alert("Xác nhận xoá tài khoản", isPresented: $showDeleteAlert, presenting: accountToDelete) { acc in
                Button("Xoá tài khoản", role: .destructive) {
                    dataStore.deleteAccount(id: acc.id)
                }
                Button("Huỷ", role: .cancel) {}
            } message: { acc in
                Text("Hành động này sẽ xoá tài khoản “\(acc.name)” và các lệnh liên quan khỏi máy của bạn.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var filterAndSearchHeader: some View {
        VStack(spacing: 10) {
            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton(title: "Mặc định (\(defaultCount))", tab: .default)
                    filterButton(title: "Hoạt động (\(activeCount))", tab: .active)
                    filterButton(title: "Hiển thị (\(visibleCount))", tab: .visible)
                    filterButton(title: "Tất cả (\(accounts.count))", tab: .all)
                }
                .padding(.horizontal, 16)
            }
            
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                TextField("Tìm theo tên, sàn, ID...", text: $searchText)
                    .font(AppTypography.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private func filterButton(title: String, tab: AccountFilterTab) -> some View {
        Button {
            filterTab = tab
        } label: {
            Text(title)
                .font(AppTypography.captionBold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filterTab == tab ? AppColors.accent : AppColors.secondaryBackground)
                .foregroundColor(filterTab == tab ? .white : AppColors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var bulkVisibilityBar: some View {
        HStack(spacing: 8) {
            Text("Hiển thị nhanh:")
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
            
            Button("Chỉ hiện Active") {
                dataStore.setBulkAccountVisibility(action: "select-active")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Button("Hiện tất cả") {
                dataStore.setBulkAccountVisibility(action: "select-all")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Button("Ẩn tất cả") {
                dataStore.setBulkAccountVisibility(action: "deselect-all")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 40))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            Text("Không tìm thấy tài khoản nào")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
            Text("Hãy tạo tài khoản mới hoặc kết nối The5ers trong phần Cài đặt.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    @ViewBuilder
    private func accountCard(_ acc: Account) -> some View {
        let isSelected = dataStore.selectedAccountId == acc.id
        let isArchived = acc.archivedAt != nil
        let tradeCount = dataStore.trades.filter { $0.accountId == acc.id }.count
        
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(acc.name)
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.profit)
                                    .font(.system(size: 14))
                            }
                        }
                        
                        Text("ID: \(acc.id)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Nút chọn làm tài khoản chính
                    if !isSelected {
                        Button("Chọn xem") {
                            dataStore.selectAccount(id: acc.id)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.12))
                        .foregroundColor(AppColors.accent)
                        .clipShape(Capsule())
                    } else {
                        Text("Đang xem")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.profit.opacity(0.15))
                            .foregroundColor(AppColors.profit)
                            .clipShape(Capsule())
                    }
                }
                
                // Huy hiệu trạng thái & sàn
                HStack(spacing: 6) {
                    if isArchived {
                        badgeView("Đã lưu trữ", color: AppColors.secondaryText)
                    } else {
                        badgeView("Active", color: AppColors.profit)
                    }
                    
                    if !acc.broker.isEmpty {
                        badgeView(acc.broker, color: AppColors.accent)
                    }
                    
                    badgeView(acc.kind.rawValue.uppercased(), color: AppColors.secondaryText)
                    badgeView(acc.profitCalcMethod.rawValue.uppercased(), color: AppColors.secondaryText)
                    
                    if acc.autoSync {
                        badgeView("Auto-sync", color: AppColors.profit)
                    }
                }
                
                Divider()
                
                // Thông tin số dư và lệnh
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Số dư khởi đầu")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatCurrency(acc.initialBalance, currency: acc.currency))
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Tổng lệnh")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(tradeCount) lệnh")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                Divider()
                
                // Thanh tác vụ bên dưới thẻ
                HStack(spacing: 12) {
                    // Auto sync toggle
                    Toggle("Tự động đồng bộ", isOn: Binding(
                        get: { acc.autoSync },
                        set: { _ in dataStore.toggleAccountAutoSync(id: acc.id) }
                    ))
                    .font(.system(size: 11))
                    .tint(AppColors.accent)
                    
                    Spacer()
                    
                    // Nút Lưu trữ / Khôi phục
                    Button {
                        dataStore.archiveAccount(id: acc.id, archived: !isArchived)
                    } label: {
                        Image(systemName: isArchived ? "tray.and.arrow.up" : "archivebox")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    // Nút Xoá
                    Button {
                        accountToDelete = acc
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.loss.opacity(0.8))
                    }
                }
            }
        }
        .opacity(isArchived ? 0.65 : 1.0)
    }
    
    @ViewBuilder
    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Sheet tạo tài khoản mới
public struct CreateAccountSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var broker: String = "The5ers"
    @State private var currency: String = "USD"
    @State private var initialBalanceText: String = "10000"
    @State private var calcMethod: ProfitCalcMethod = .fifo
    
    private let commonBrokers = ["The5ers", "FTMO", "Topstep", "Oanda", "MetaTrader 5", "Binance", "Thủ công"]
    private let commonCurrencies = ["USD", "EUR", "GBP", "JPY", "VND"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tên và sàn")) {
                    TextField("Tên tài khoản (VD: Quỹ 100K 5ers)", text: $name)
                    
                    Picker("Sàn giao dịch", selection: $broker) {
                        ForEach(commonBrokers, id: \.self) { b in
                            Text(b).tag(b)
                        }
                    }
                }
                
                Section(header: Text("Tài chính & Thuật toán tính lãi")) {
                    Picker("Đồng tiền", selection: $currency) {
                        ForEach(commonCurrencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    
                    TextField("Số dư ban đầu", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                    
                    Picker("Phương pháp tính P&L", selection: $calcMethod) {
                        Text("FIFO (First In First Out)").tag(ProfitCalcMethod.fifo)
                        Text("LIFO (Last In First Out)").tag(ProfitCalcMethod.lifo)
                        Text("Weighted Average (Bình quân gia quyền)").tag(ProfitCalcMethod.wavg)
                    }
                }
            }
            .navigationTitle("Tạo tài khoản mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") {
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
