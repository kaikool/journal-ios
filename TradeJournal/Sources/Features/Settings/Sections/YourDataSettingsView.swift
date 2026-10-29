import SwiftUI

// MARK: - Your Data & Backups Settings View (Apple HIG Inset-Grouped Standard)
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
        VStack(spacing: 16) {
            // Card 1: Cloud Database
            SettingsCard(title: "Cloud Database", footer: "Multi-device synchronization and automatic cloud storage.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SupabaseService.shared.isConfigured ? AppColors.profit : AppColors.secondaryText)
                                .frame(width: 7, height: 7)
                            Text(SupabaseService.shared.isConfigured ? "Connected" : "Not configured")
                                .font(AppTypography.captionBold)
                                .foregroundColor(SupabaseService.shared.isConfigured ? AppColors.profit : AppColors.secondaryText)
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
                            .foregroundColor(status.contains("Error") || status.contains("error") || status.contains("Failed") ? AppColors.loss : AppColors.profit)
                    }
                }
            }
            
            // Card 2: Data Export
            SettingsCard(title: "Data Export", footer: "Export your complete trade journal or raw trade executions.") {
                HStack(spacing: 10) {
                    AppButton("Export JSON", icon: "square.and.arrow.up", style: .secondary, size: .compact, fullWidth: true) {
                        exportFullJsonBackup()
                    }
                    
                    AppButton("Export CSV", icon: "square.and.arrow.up", style: .secondary, size: .compact, fullWidth: true) {
                        exportTradesCsv()
                    }
                }
            }
            
            // Card 3: Local Storage
            SettingsCard(title: "Local Storage", footer: "On-device database storage. Resetting permanently deletes local records.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("\(dataStore.trades.count) trades • \(dataStore.executions.count) executions • \(dataStore.accounts.count) accounts")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Spacer()
                        
                        AppButton("Reset", icon: "trash", style: .destructive, size: .compact) {
                            showResetConfirmation = true
                        }
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
            Button("Delete All Data", role: .destructive) {
                dataStore.resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All trades, executions, journal logs, and notes will be permanently erased from this device.")
        }
        .alert("Wipe all cloud data?", isPresented: $showWipeConfirmation) {
            Button("Wipe Remote Data", role: .destructive) {
                wipeSupabaseData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all records across all tables in your cloud database.")
        }
    }
    
    // MARK: - Actions
    
    private func syncSupabase() {
        Task {
            supabaseSyncStatus = "Syncing..."
            await dataStore.syncWithSupabase()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.supabaseSyncStatus = "Sync error: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.supabaseSyncStatus = summary
                } else {
                    self.supabaseSyncStatus = "Synchronized successfully."
                }
            }
        }
    }
    
    private func wipeSupabaseData() {
        isWipingSupabase = true
        supabaseSyncStatus = "Wiping cloud database..."
        Task {
            do {
                try await SupabaseService.shared.wipeAllRemoteData()
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Cloud database wiped successfully."
                }
            } catch {
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Error: \(error.localizedDescription)"
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
        let csv = dataStore.exportTradesCsv()
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
