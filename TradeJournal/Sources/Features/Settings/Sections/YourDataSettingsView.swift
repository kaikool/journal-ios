import SwiftUI

// MARK: - 7. Your Data & Backups Settings View
// Ported 1:1 from `your-data` in `settings/page.tsx` & `api/export/route.ts`
public struct YourDataSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showExportSheet: Bool = false
    @State private var exportedFileUrl: URL? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var seedMessage: String = ""
    
    // Supabase Cloud Configuration
    @State private var supabaseUrl: String = SupabaseService.shared.supabaseUrl
    @State private var supabaseAnonKey: String = SupabaseService.shared.supabaseAnonKey
    @State private var supabaseSyncStatus: String? = nil
    @State private var showWipeConfirmation: Bool = false
    @State private var isWipingSupabase: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Cloud Backup (Supabase)
            SettingsCard(title: "Cloud Backup (Supabase)") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Back up your trades, journals, and accounts to your private cloud database to keep your data safe and sync across devices.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project URL:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("https://your-project.supabase.co", text: $supabaseUrl)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        SecureField("Paste API key (anon or service role)...", text: $supabaseAnonKey)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        
                        Text("Found in your Supabase Dashboard → Project Settings → API.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack(spacing: 8) {
                        AppButton("Backup Now", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, fullWidth: true, isLoading: dataStore.isSyncing) {
                            syncSupabase()
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        AppButton("Sync Center", icon: "slider.horizontal.3", style: .secondary, size: .compact, fullWidth: true) {
                            env.showSyncCenter = true
                        }
                        
                        AppButton("Test", icon: "network", style: .secondary, size: .compact, fullWidth: true) {
                            checkSupabaseConnection()
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        AppButton("Wipe", icon: "trash", style: .destructive, size: .compact, fullWidth: true, isLoading: isWipingSupabase) {
                            showWipeConfirmation = true
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty || isWipingSupabase)
                    }
                    
                    if let status = supabaseSyncStatus {
                        Text(status)
                            .font(AppTypography.caption)
                            .foregroundColor(status.contains("Error") || status.contains("missing") ? AppColors.loss : AppColors.profit)
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
            
            // Card 3: Reset Database
            SettingsCard(title: "Local Database Management") {
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
        .onAppear {
            supabaseUrl = SupabaseService.shared.supabaseUrl
            supabaseAnonKey = SupabaseService.shared.supabaseAnonKey
        }
        .onChange(of: supabaseUrl) { val in
            SupabaseService.shared.configure(url: val, anonKey: supabaseAnonKey)
        }
        .onChange(of: supabaseAnonKey) { val in
            SupabaseService.shared.configure(url: supabaseUrl, anonKey: val)
        }
        .sheet(isPresented: $showExportSheet) {
            if let fileUrl = exportedFileUrl {
                ShareFileSheet(fileUrl: fileUrl)
            }
        }
        .alert("Reset all local data?", isPresented: $showResetConfirmation) {
            Button("Delete all data", role: .destructive) {
                dataStore.resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All trades, journal logs, and notes will be permanently erased from this device.")
        }
        .alert("Wipe All Supabase Remote Data?", isPresented: $showWipeConfirmation) {
            Button("Wipe All Remote Data", role: .destructive) {
                wipeSupabaseData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all application records across all tables in your Supabase database and reset local cache. You can then perform a fresh sync.")
        }
    }
    
    private func checkSupabaseConnection() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Validating Project URL and Anon Key..."
            do {
                let res = try await SupabaseService.shared.pingConnection()
                supabaseSyncStatus = res.message
            } catch {
                supabaseSyncStatus = error.localizedDescription
            }
        }
    }
    
    private func wipeSupabaseData() {
        isWipingSupabase = true
        supabaseSyncStatus = "Wiping all tables on Supabase cloud database..."
        Task {
            do {
                try await SupabaseService.shared.wipeAllRemoteData()
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.dataStore.resetAllData()
                    self.supabaseSyncStatus = "All Supabase tables and local data wiped successfully. You can sync again."
                }
            } catch {
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Wipe error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncSupabase() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Performing bi-directional sync with Supabase..."
            await dataStore.syncWithSupabase()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.supabaseSyncStatus = "Sync error: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.supabaseSyncStatus = summary
                } else {
                    self.supabaseSyncStatus = "Bi-directional sync completed successfully!"
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
        
        guard let data = try? encoder.encode(backup) else { return }
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("trade-journal-export.json")
        try? data.write(to: tempUrl)
        self.exportedFileUrl = tempUrl
        self.showExportSheet = true
    }
    
    private func exportTradesCsv() {
        let csv = dataStore.exportTradesCsv()
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("trades.csv")
        try? csv.data(using: .utf8)?.write(to: tempUrl)
        self.exportedFileUrl = tempUrl
        self.showExportSheet = true
    }
}
