import SwiftUI
import UniformTypeIdentifiers

/// Trade statement import view supporting CSV file uploads, reconciliation, and preview.
/// Ported 1:1 from `source-repo/apps/web/src/app/import/page.tsx`
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
        VStack(spacing: 0) {
            FilterBarView(
                title: "Import trades",
                showFilters: false
            )
            
            ScrollView {
                VStack(spacing: 14) {
                    // Target Account Selector
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target account")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Picker("Select account", selection: $dataStore.selectedAccountId) {
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
                                .foregroundColor(AppColors.brand)
                            
                            if let fileName = importedFileName {
                                Text("Selected file: \(fileName)")
                                    .font(AppTypography.headline)
                                    .foregroundColor(AppColors.primaryText)
                            } else {
                                Text("Choose trade statement file (.csv)")
                                    .font(AppTypography.headline)
                                Text("Supports standard columns: Symbol, Side (Buy/Sell), Quantity, Price, Fee, Executed Date")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            
                            HStack(spacing: 12) {
                                AppButton("Choose CSV file", icon: "folder", style: .primary) {
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
                                    Text("Import completed successfully!")
                                        .font(AppTypography.headline)
                                    Text("Added \(successCount) executions and updated trades.")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
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
                                    Text("Usable fills")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(preview.usableExecutions.count)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(AppColors.profit)
                                }
                                
                                AppCard {
                                    Text("Duplicate fills")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(preview.duplicateCount)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(AppColors.warning)
                                }
                                
                                AppCard {
                                    Text("Problem rows")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(preview.problems.count)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                        .foregroundColor(preview.problems.isEmpty ? AppColors.secondaryText : AppColors.loss)
                                }
                                
                                AppCard {
                                    Text("Total file rows")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(preview.totalRows)")
                                        .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                }
                            }
                            
                            // Error / Problem details
                            if !preview.problems.isEmpty {
                                AppCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Warnings & Problems (\(preview.problems.count))", systemImage: "exclamationmark.triangle.fill")
                                            .font(AppTypography.headline)
                                            .foregroundColor(AppColors.loss)
                                        
                                        ForEach(preview.problems.prefix(5)) { p in
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("Line \(p.lineNumber):")
                                                    .font(AppTypography.caption.bold())
                                                    .foregroundColor(AppColors.secondaryText)
                                                Text(p.reason)
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(AppColors.primaryText)
                                            }
                                        }
                                        
                                        if preview.problems.count > 5 {
                                            Text("+ \(preview.problems.count - 5) more issues...")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                    }
                                }
                            }
                            
                            // Sample Preview Rows
                            if !preview.usableExecutions.isEmpty {
                                AppCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Execution Preview (\(min(3, preview.usableExecutions.count))/\(preview.usableExecutions.count))")
                                            .font(AppTypography.headline)
                                        
                                        ForEach(preview.usableExecutions.prefix(3)) { fill in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(fill.symbol).font(AppTypography.headline)
                                                        AppBadge(
                                                            fill.side.rawValue.uppercased(),
                                                            color: fill.side == .buy ? AppColors.brand : AppColors.warning
                                                        )
                                                    }
                                                    Text("Qty: \(fill.quantity) @ \(Formatters.price(fill.price))")
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(AppColors.secondaryText)
                                                }
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Fee: \(Formatters.currency(fill.fee, isPrivate: false))")
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(AppColors.secondaryText)
                                                    Text(Formatters.dateOnly(fill.executedAt, timeZone: env.currentTimeZone))
                                                        .font(AppTypography.caption)
                                                        .foregroundColor(AppColors.secondaryText)
                                                }
                                            }
                                            Divider()
                                        }
                                    }
                                }
                                
                                // Confirm Button
                                AppButton(
                                    "Confirm Import \(preview.usableExecutions.count) Fills",
                                    icon: "arrow.up.circle.fill",
                                    style: .primary
                                ) {
                                    commitImport(preview.usableExecutions)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
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
        .background(AppColors.background)
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
