import SwiftUI
import UniformTypeIdentifiers

public struct ImportStatementView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var isFileImporterPresented = false
    @State private var importedFileName: String? = nil
    @State private var csvContent: String = ""
    @State private var previewResult: ImportPreview? = nil
    @State private var isImportSuccess = false
    @State private var successCount = 0
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Account Selector
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tài khoản đích")
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Chọn tài khoản", selection: $dataStore.selectedAccountId) {
                                ForEach(dataStore.accounts) { acc in
                                    Text("\(acc.name) (\(acc.currency))").tag(acc.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Upload / Select Box
                    AppCard {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(AppColors.accent)
                            
                            if let fileName = importedFileName {
                                Text("Tệp đã chọn: \(fileName)")
                                    .font(AppTypography.headline)
                                    .foregroundColor(.primary)
                            } else {
                                Text("Chọn tệp sao kê giao dịch (.csv)")
                                    .font(AppTypography.headline)
                                Text("Hỗ trợ các cột chuẩn: Symbol, Side (Buy/Sell), Quantity, Price, Fee, Date")
                                    .font(AppTypography.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            HStack(spacing: 12) {
                                AppButton("Chọn File CSV", icon: "folder", style: .primary) {
                                    isFileImporterPresented = true
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    
                    // Success Banner
                    if isImportSuccess {
                        AppCard {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppColors.profit)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nạp sao kê thành công!")
                                        .font(AppTypography.headline)
                                    Text("Đã thêm \(successCount) lần khớp lệnh và cập nhật danh sách trades.")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    // Preview Result
                    if let preview = previewResult {
                        VStack(spacing: 16) {
                            // Summary Grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                AppCard {
                                    Text("Lệnh hợp lệ")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(preview.usableExecutions.count)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(AppColors.profit)
                                }
                                
                                AppCard {
                                    Text("Lệnh bị trùng")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(preview.duplicateCount)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(AppColors.warning)
                                }
                                
                                AppCard {
                                    Text("Dòng bị lỗi")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(preview.problems.count)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(preview.problems.isEmpty ? .secondary : AppColors.loss)
                                }
                                
                                AppCard {
                                    Text("Tổng dòng trong file")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(preview.totalRows)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                }
                            }
                            
                            // Error / Problem details
                            if !preview.problems.isEmpty {
                                AppCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Cảnh báo & Lỗi dòng (\(preview.problems.count))", systemImage: "exclamationmark.triangle.fill")
                                            .font(AppTypography.headline)
                                            .foregroundColor(AppColors.loss)
                                        
                                        ForEach(preview.problems.prefix(5)) { p in
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("Dòng \(p.lineNumber):")
                                                    .font(AppTypography.caption.bold())
                                                    .foregroundColor(.secondary)
                                                Text(p.reason)
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                        
                                        if preview.problems.count > 5 {
                                            Text("+ còn \(preview.problems.count - 5) lỗi khác...")
                                                .font(AppTypography.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            // Sample Preview Rows
                            if !preview.usableExecutions.isEmpty {
                                AppCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Xem trước dữ liệu (\(min(3, preview.usableExecutions.count))/\(preview.usableExecutions.count))")
                                            .font(AppTypography.headline)
                                        
                                        ForEach(preview.usableExecutions.prefix(3)) { fill in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(fill.symbol).font(AppTypography.headline)
                                                        AppBadge(
                                                            fill.side.rawValue.uppercased(),
                                                            color: fill.side == .buy ? AppColors.accent : AppColors.warning
                                                        )
                                                    }
                                                    Text("KL: \(fill.quantity) @ \(Formatters.price(fill.price))")
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Phí: \(Formatters.currency(fill.fee, isPrivate: false))")
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(.secondary)
                                                    Text(Formatters.dateOnly(fill.executedAt, timeZone: env.currentTimeZone))
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Divider()
                                        }
                                    }
                                }
                                
                                // Confirm Button
                                AppButton(
                                    "Xác Nhận Nạp \(preview.usableExecutions.count) Lệnh",
                                    icon: "arrow.up.circle.fill",
                                    style: .primary
                                ) {
                                    commitImport(preview.usableExecutions)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Nhập Sao Kê")
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadFile(at: url)
                case .failure(let error):
                    AppLogger.error("Failed to pick file", error: error)
                }
            }
        }
    }
    
    private func loadFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            importedFileName = url.lastPathComponent
            csvContent = content
            generatePreview(content)
        } catch {
            AppLogger.error("Failed to read file", error: error)
        }
    }
    
    
    private func generatePreview(_ content: String) {
        isImportSuccess = false
        previewResult = StandardCSVImporter.preview(
            csvText: content,
            accountId: dataStore.selectedAccountId,
            existingHashes: dataStore.existingHashesForSelectedAccount,
            timeZone: env.currentTimeZone
        )
    }
    
    private func commitImport(_ usable: [Execution]) {
        dataStore.importExecutions(accountId: dataStore.selectedAccountId, newExecutions: usable)
        successCount = usable.count
        isImportSuccess = true
        previewResult = nil
        importedFileName = nil
    }
}
