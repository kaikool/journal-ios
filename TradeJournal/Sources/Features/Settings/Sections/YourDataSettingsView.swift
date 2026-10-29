import SwiftUI

// MARK: - 7. Your Data & Backups Settings View
// Clean Apple HIG settings view: Built-in cloud sync, Wipe tools for dev, Export & Local reset
public struct YourDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showExportSheet: Bool = false
    @State private var exportedFileUrl: URL? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var showWipeConfirmation: Bool = false
    @State private var isWipingSupabase: Bool = false
    @State private var supabaseSyncStatus: String? = nil
    
    @State private var supabaseUrl: String = SupabaseService.shared.supabaseUrl
    @State private var supabaseAnonKey: String = SupabaseService.shared.supabaseAnonKey
    @State private var showSupabaseConfig: Bool = false
    @State private var configSaveStatus: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Cloud Database
            SettingsCard(title: "Cloud Database") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Supabase Cloud Storage")
                                .font(AppTypography.headline)
                            Text("Trades, accounts, and journals automatically sync to your private cloud database.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                        Text(SupabaseService.shared.isConfigured ? "Connected" : "Not configured")
                            .font(AppTypography.captionBold)
                            .foregroundColor(SupabaseService.shared.isConfigured ? AppColors.profit : AppColors.secondaryText)
                    }
                    
                    DisclosureGroup(isExpanded: $showSupabaseConfig) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Hardware-backed credentials (AES-256 Keychain). Leave empty to use environment variables.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .padding(.top, 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Project URL")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                TextField("https://your-project.supabase.co", text: $supabaseUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anon Public Key")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                SecureField("Enter Supabase Anon Key", text: $supabaseAnonKey)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            
                            HStack(spacing: 12) {
                                AppButton("Save Credentials", icon: "checkmark.circle", style: .primary, size: .compact) {
                                    saveSupabaseConfig()
                                }
                                
                                if SupabaseService.shared.isConfigured {
                                    AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact) {
                                        disconnectSupabase()
                                    }
                                }
                            }
                            
                            if let saveStatus = configSaveStatus {
                                Text(saveStatus)
                                    .font(AppTypography.caption)
                                    .foregroundColor(saveStatus.contains("error") ? AppColors.loss : AppColors.profit)
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(AppColors.brand)
                            Text("Database Credentials & Connection")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                    }
                    
                    Divider()
                    
                    HStack(spacing: 12) {
                        AppButton("Sync now", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, fullWidth: true, isLoading: dataStore.isSyncing) {
                            syncSupabase()
                        }
                        .disabled(!SupabaseService.shared.isConfigured)
                        
                        AppButton("Wipe cloud data", icon: "trash", style: .destructive, size: .compact, fullWidth: true, isLoading: isWipingSupabase) {
                            showWipeConfirmation = true
                        }
                        .disabled(isWipingSupabase || dataStore.isSyncing || !SupabaseService.shared.isConfigured)
                    }
                    
                    if let status = supabaseSyncStatus {
                        Text(status)
                            .font(AppTypography.caption)
                            .foregroundColor(status.contains("Error") || status.contains("error") ? AppColors.loss : AppColors.profit)
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
    
    private func saveSupabaseConfig() {
        let cleanUrl = supabaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        SupabaseService.shared.configure(url: cleanUrl, anonKey: cleanKey)
        configSaveStatus = "Supabase configuration saved securely in Apple Keychain."
    }
    
    private func disconnectSupabase() {
        supabaseUrl = ""
        supabaseAnonKey = ""
        SupabaseService.shared.configure(url: "", anonKey: "")
        configSaveStatus = "Disconnected from Supabase."
    }
    
    private func syncSupabase() {
        Task {
            supabaseSyncStatus = "Syncing with cloud database..."
            await dataStore.syncWithSupabase()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.supabaseSyncStatus = "Sync error: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.supabaseSyncStatus = summary
                } else {
                    self.supabaseSyncStatus = "Cloud sync completed successfully!"
                }
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
                    self.supabaseSyncStatus = "Cloud database wiped successfully."
                }
            } catch {
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Wipe error: \(error.localizedDescription)"
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
