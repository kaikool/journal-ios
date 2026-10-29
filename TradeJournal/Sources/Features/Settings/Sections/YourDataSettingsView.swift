import SwiftUI

// MARK: - 7. Your Data & Backups Settings View
// Clean Apple HIG settings view: Cloud Database sync, Export tools, and local data management.
public struct YourDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showExportSheet: Bool = false
    @State private var exportedFileUrl: URL? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var showWipeConfirmation: Bool = false
    @State private var isWipingSupabase: Bool = false
    @State private var supabaseSyncStatus: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Cloud Database
            SettingsCard(title: "Cloud Database") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Supabase Cloud")
                                .font(AppTypography.headline)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SupabaseService.shared.isConfigured ? AppColors.profit : AppColors.secondaryText)
                                    .frame(width: 8, height: 8)
                                Text(SupabaseService.shared.isConfigured ? "Đã kết nối" : "Chưa kết nối")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(SupabaseService.shared.isConfigured ? AppColors.profit : AppColors.secondaryText)
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            AppButton("Sync", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, isLoading: dataStore.isSyncing) {
                                syncSupabase()
                            }
                            .disabled(!SupabaseService.shared.isConfigured)
                            
                            AppButton("Wipe", icon: "trash", style: .destructive, size: .compact, isLoading: isWipingSupabase) {
                                showWipeConfirmation = true
                            }
                            .disabled(isWipingSupabase || dataStore.isSyncing || !SupabaseService.shared.isConfigured)
                        }
                    }
                    
                    if let status = supabaseSyncStatus {
                        Text(status)
                            .font(AppTypography.caption)
                            .foregroundColor(status.contains("Error") || status.contains("error") || status.contains("Lỗi") ? AppColors.loss : AppColors.profit)
                    }
                }
            }
            
            // Card 2: Export your data
            SettingsCard(title: "Export your data") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Save a full journal backup, or export your trades as a CSV.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 12) {
                        AppButton("Export JSON", icon: "square.and.arrow.up", style: .secondary, size: .compact) {
                            exportFullJsonBackup()
                        }
                        
                        AppButton("Export CSV", icon: "square.and.arrow.up", style: .secondary, size: .compact) {
                            exportTradesCsv()
                        }
                    }
                }
            }
            
            // Card 3: Local data
            SettingsCard(title: "Local data") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Manage on-device storage or reset your local database.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    AppButton("Reset and delete all local data", icon: "trash", style: .destructive, size: .compact) {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let fileUrl = exportedFileUrl {
                ShareFileSheet(fileUrl: fileUrl)
            }
        }
        .alert("Reset all local data?", isPresented: $showResetConfirmation) {
            Button("Delete all local data", role: .destructive) {
                dataStore.resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All trades, journal logs, and notes will be permanently erased from this device.")
        }
        .alert("Wipe all cloud data on Supabase?", isPresented: $showWipeConfirmation) {
            Button("Wipe cloud data", role: .destructive) {
                wipeSupabaseData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all records across all tables in your Supabase database. Use this to reset when developing or testing features.")
        }
    }
    
    // MARK: - Actions
    
    private func syncSupabase() {
        Task {
            supabaseSyncStatus = "Đang đồng bộ..."
            await dataStore.syncWithSupabase()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.supabaseSyncStatus = "Lỗi sync: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.supabaseSyncStatus = summary
                } else {
                    self.supabaseSyncStatus = "Đồng bộ thành công!"
                }
            }
        }
    }
    
    private func wipeSupabaseData() {
        isWipingSupabase = true
        supabaseSyncStatus = "Đang xóa dữ liệu đám mây..."
        Task {
            do {
                try await SupabaseService.shared.wipeAllRemoteData()
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Đã xóa toàn bộ dữ liệu đám mây."
                }
            } catch {
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Lỗi: \(error.localizedDescription)"
                }
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
            let generalSettings: GeneralSettingsConfig
            let defaults: JournalDefaults
            let currencyConversion: CurrencyConversion
            let marketConnections: MarketConnectionConfig
            let aiSettings: AiSettingsConfig
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
            attachments: dataStore.attachments,
            generalSettings: dataStore.generalSettings,
            defaults: dataStore.defaults,
            currencyConversion: dataStore.currencyConversion,
            marketConnections: dataStore.marketConnections,
            aiSettings: dataStore.aiSettings
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(backup)
            let tempDir = FileManager.default.temporaryDirectory
            let fileUrl = tempDir.appendingPathComponent("TradeJournal_Backup_\(Date().timeIntervalSince1970).json")
            try data.write(to: fileUrl)
            
            self.exportedFileUrl = fileUrl
            self.showExportSheet = true
        } catch {
            AppLogger.error("Failed to export full backup JSON: \(error.localizedDescription)")
        }
    }
    
    private func exportTradesCsv() {
        var csv = "Trade ID,Account,Symbol,Direction,Entry Date,Exit Date,Entry Price,Exit Price,Size,Net P&L,Status,Playbook\n"
        for trade in dataStore.trades {
            let line = "\(trade.id),\(trade.accountId),\(trade.symbol),\(trade.direction.rawValue),\(trade.entryDate?.description ?? ""),\(trade.exitDate?.description ?? ""),\(trade.entryPrice ?? 0),\(trade.exitPrice ?? 0),\(trade.size ?? 0),\(trade.netPnl ?? 0),\(trade.status.rawValue),\"\(trade.playbookTag ?? "")\"\n"
            csv += line
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileUrl = tempDir.appendingPathComponent("TradeJournal_Trades_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: fileUrl, atomically: true, encoding: .utf8)
            self.exportedFileUrl = fileUrl
            self.showExportSheet = true
        } catch {
            AppLogger.error("Failed to export trades CSV: \(error.localizedDescription)")
        }
    }
}
