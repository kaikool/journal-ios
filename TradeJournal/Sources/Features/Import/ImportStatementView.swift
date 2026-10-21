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
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    // Target Account Selector
                    cardContainer {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "creditcard")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.brand)
                                Text("Target Account")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            let selectedAcc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId })
                            let label = selectedAcc.map { "\($0.name) (\($0.currency))" } ?? "Select account"
                            
                            AppleMenuChip(
                                selectionText: label,
                                icon: "creditcard"
                            ) {
                                ForEach(dataStore.accounts) { acc in
                                    Button("\(acc.name) (\(acc.currency))") {
                                        dataStore.selectedAccountId = acc.id
                                    }
                                }
                            }
                        }
                    }
                    
                    // Upload / Select Box (Apple HIG Drop Zone)
                    cardContainer {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.brand.opacity(0.12))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppColors.brand)
                            }
                            .padding(.top, 4)
                            
                            if let fileName = importedFileName {
                                VStack(spacing: 4) {
                                    Text("Selected File")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(fileName)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Text("Choose trade statement (.csv)")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("Standard columns: Symbol, Side (Buy/Sell), Quantity, Price, Fee, Date. MetaTrader 4/5 statements (Open Time, Volume, Commission, Swap) and cTrader / TradingView exports are detected automatically.")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 8)
                                }
                            }
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                isFileImporterPresented = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text("Choose CSV File")
                                }
                                .font(AppTypography.captionBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(AppColors.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(ApplePressableButtonStyle())
                            .padding(.bottom, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Success Banner
                    if isImportSuccess {
                        cardContainer {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppColors.profit)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Import completed successfully!")
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("Added \(successCount) executions and updated trades.")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    // Preview Result
                    if let preview = previewResult {
                        VStack(spacing: 14) {
                            // Summary Grid
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Usable fills")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text("\(preview.usableExecutions.count)")
                                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.profit)
                                    }
                                }
                                
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Duplicate fills")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text("\(preview.duplicateCount)")
                                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.warning)
                                    }
                                }
                                
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Problem rows")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text("\(preview.problems.count)")
                                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundColor(preview.problems.isEmpty ? AppColors.secondaryText : AppColors.loss)
                                    }
                                }
                                
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Total file rows")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                        Text("\(preview.totalRows)")
                                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.primaryText)
                                    }
                                }
                            }
                            
                            // Error / Problem details
                            if !preview.problems.isEmpty {
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(AppColors.loss)
                                            Text("Warnings & Problems (\(preview.problems.count))")
                                                .font(AppTypography.headline)
                                                .foregroundColor(AppColors.loss)
                                        }
                                        
                                        ForEach(preview.problems.prefix(5)) { p in
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("Line \(p.lineNumber):")
                                                    .font(AppTypography.caption.bold())
                                                    .monospacedDigit()
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
                                cardContainer {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "list.clipboard")
                                                .font(.system(size: 13))
                                                .foregroundColor(AppColors.brand)
                                            Text("Execution Preview (\(min(3, preview.usableExecutions.count))/\(preview.usableExecutions.count))")
                                                .font(AppTypography.headline)
                                                .foregroundColor(AppColors.primaryText)
                                        }
                                        
                                        ForEach(preview.usableExecutions.prefix(3)) { fill in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    HStack(spacing: 6) {
                                                        Text(fill.symbol)
                                                            .font(AppTypography.bodyBold)
                                                            .foregroundColor(AppColors.primaryText)
                                                        Text(fill.side.rawValue.uppercased())
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(fill.side == .buy ? AppColors.brand : AppColors.warning)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background((fill.side == .buy ? AppColors.brand : AppColors.warning).opacity(0.12))
                                                            .clipShape(Capsule())
                                                    }
                                                    Text("Qty: \(Formatters.formatNumber(fill.quantity)) @ \(Formatters.price(fill.price))")
                                                        .font(AppTypography.caption)
                                                        .monospacedDigit()
                                                        .foregroundColor(AppColors.secondaryText)
                                                }
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 3) {
                                                    Text("Fee: \(Formatters.currency(fill.fee, isPrivate: false))")
                                                        .font(AppTypography.caption)
                                                        .monospacedDigit()
                                                        .foregroundColor(AppColors.secondaryText)
                                                    Text(Formatters.dateOnly(fill.executedAt, timeZone: env.currentTimeZone))
                                                        .font(AppTypography.caption)
                                                        .monospacedDigit()
                                                        .foregroundColor(AppColors.secondaryText)
                                                }
                                            }
                                            .padding(.vertical, 2)
                                            
                                            if fill.id != preview.usableExecutions.prefix(3).last?.id {
                                                Divider().background(AppColors.border.opacity(0.3))
                                            }
                                        }
                                    }
                                }
                                
                                // Confirm Button
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    #endif
                                    commitImport(preview.usableExecutions)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.up.circle.fill")
                                        Text("Confirm Import \(preview.usableExecutions.count) Fills")
                                    }
                                    .font(AppTypography.subheadlineBold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppColors.brand)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: AppColors.brand.opacity(0.25), radius: 6, x: 0, y: 2)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                }
                .padding(16)
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
        // Timestamps without an explicit offset are interpreted in the configured import timezone so
        // that the content hash (and therefore the duplicate detection) does not depend on the device
        // timezone. The device timezone is still checked to catch statements imported by older builds.
        let importTimeZone = TimeZone(identifier: dataStore.generalSettings.defaultImportTimeZone)
            ?? env.currentTimeZone
        previewResult = StandardCSVImporter.preview(
            csvText: content,
            accountId: dataStore.selectedAccountId,
            existingHashes: dataStore.existingHashesForSelectedAccount,
            timeZone: importTimeZone,
            legacyTimeZone: env.currentTimeZone
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
