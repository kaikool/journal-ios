import SwiftUI

/// Modal action sheet enabling granular control over synchronization sources, date horizons, and cloud backups.
public struct SyncCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var syncManager = SyncManager.shared
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var ctrader = CTraderService.shared
    @ObservedObject private var the5ers = The5ersService.shared
    @ObservedObject private var exness = ExnessService.shared
    private let supabase = SupabaseService.shared
    
    @State private var options: SyncOptions = SyncManager.shared.savedQuickSyncOptions
    @State private var showCustomDatePicker: Bool = false
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var saveConfirmationMessage: String? = nil
    @State private var syncTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Section 1: Market Sources (Brokers & Prop Firms)
                        sourcesSection
                        
                        // Section 2: Time Horizon (Date Filter)
                        timeHorizonSection
                        
                        // Section 3: Data Elements & Cloud Backup
                        dataElementsSection
                        
                        // Section 4: Sync Status & Results Log
                        syncResultsLogSection
                        
                        Spacer(minLength: 28)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sync Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveAsQuickSyncDefault()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark")
                            Text("Save Default")
                        }
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brand)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .onAppear {
            self.options = syncManager.savedQuickSyncOptions
            if let start = options.customStartDate { self.customStart = start }
            if let end = options.customEndDate { self.customEnd = end }
        }
    }
    
    // MARK: - Section 1: Market Sources
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MARKET CONNECTIONS")
                    .font(AppTypography.cardHeader)
                    .tracking(0.5)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                    env.selectedTab = .settings
                } label: {
                    Text("+ Manage Connections")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brand)
                        .lineLimit(1)
                }
            }
            
            VStack(spacing: 8) {
                // cTrader Source Card
                let ctraderAccountCount = ctrader.discoveredAccounts.count > 0 ? ctrader.discoveredAccounts.count : dataStore.accounts.filter { $0.id.hasPrefix("ctrader_") || $0.broker.lowercased() == "ctrader" }.count
                let ctraderSubtitle: String = {
                    if !ctrader.isConfigured {
                        return "Not configured"
                    }
                    if ctraderAccountCount > 0 {
                        return "Connected · \(ctraderAccountCount) linked account(s)"
                    }
                    return "Connected · Ready to fetch accounts"
                }()
                
                sourceRow(
                    id: "ctrader",
                    title: "cTrader",
                    subtitle: ctraderSubtitle,
                    icon: "chart.xyaxis.line",
                    isConfigured: ctrader.isConfigured
                )
                
                // The5ers Source Card
                sourceRow(
                    id: "the5ers",
                    title: "The5ers",
                    subtitle: the5ers.isConfigured ? "Connected · Prop accounts & payouts" : "Not configured",
                    icon: "building.columns",
                    isConfigured: the5ers.isConfigured
                )
                
                // Exness Source Card
                let exnessSubtitle: String = {
                    if !exness.isConfigured {
                        return "Not configured"
                    }
                    if exness.isConnected {
                        let formattedBal = Formatters.formatCurrency(exness.balance, currency: exness.currency)
                        return "Connected · Balance: \(formattedBal)"
                    }
                    return "Configured · Ready to sync"
                }()
                
                sourceRow(
                    id: "exness",
                    title: "Exness",
                    subtitle: exnessSubtitle,
                    icon: "chart.line.uptrend.xyaxis",
                    isConfigured: exness.isConfigured
                )
            }
        }
    }
    
    private func sourceRow(id: String, title: String, subtitle: String, icon: String, isConfigured: Bool) -> some View {
        let isEnabled = options.enabledProviderIds.contains(id)
        
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isConfigured ? AppColors.brand : AppColors.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppColors.brand.opacity(isConfigured ? 0.12 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.subheadlineBold)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            if isConfigured {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newVal in
                        if newVal {
                            options.enabledProviderIds.insert(id)
                        } else {
                            options.enabledProviderIds.remove(id)
                        }
                    }
                ))
                .labelsHidden()
                .tint(AppColors.brand)
            } else {
                Text("Setup")
                    .font(AppTypography.captionBold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.input)
                    .foregroundColor(AppColors.secondaryText)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
        )
    }
    
    // MARK: - Section 2: Time Horizon
    private var timeHorizonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIME HORIZON (DATE FILTER)")
                .font(AppTypography.cardHeader)
                .tracking(0.5)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            VStack(spacing: 12) {
                // Segmented picker for pre-set horizons with clean Apple style labels
                HStack(spacing: 6) {
                    ForEach(SyncDateRangeMode.allCases) { mode in
                        let label: String = {
                            switch mode {
                            case .last7Days: return "7D"
                            case .last30Days: return "30D"
                            case .last90Days: return "90D"
                            case .allTime: return "ALL"
                            case .custom: return "Custom"
                            }
                        }()
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                options.dateRangeMode = mode
                                showCustomDatePicker = (mode == .custom)
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(options.dateRangeMode == mode ? AppColors.brand : Color.clear)
                                )
                                .foregroundColor(options.dateRangeMode == mode ? .white : AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(AppColors.input)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                // Custom Date Picker expansion
                if options.dateRangeMode == .custom {
                    VStack(spacing: 8) {
                        DatePicker("From:", selection: $customStart, displayedComponents: .date)
                            .font(AppTypography.subheadline)
                        DatePicker("To:", selection: $customEnd, displayedComponents: .date)
                            .font(AppTypography.subheadline)
                    }
                    .padding(12)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: customStart) { val in
                        options.customStartDate = val
                    }
                    .onChange(of: customEnd) { val in
                        options.customEndDate = val
                    }
                }
            }
        }
    }
    
    // MARK: - Section 3: Data Elements & Cloud Backup
    private var dataElementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATA SCOPE & CLOUD BACKUP")
                .font(AppTypography.cardHeader)
                .tracking(0.5)
                .foregroundColor(AppColors.secondaryText)
            
            VStack(spacing: 10) {
                Toggle(isOn: $options.includeHistoricalDeals) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closed Trades & Orders")
                            .font(AppTypography.subheadlineBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("Imports completed trades while preserving your personal notes, setups, and tags.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .tint(AppColors.brand)
                
                Divider().background(AppColors.border.opacity(0.4))
                
                Toggle(isOn: $options.includeOpenPositions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Open Positions")
                            .font(AppTypography.subheadlineBold)
                            .foregroundColor(AppColors.primaryText)
                        Text("Syncs current open positions and floating P&L to monitor active risk.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .tint(AppColors.brand)
                
                Divider().background(AppColors.border.opacity(0.4))
                
                Toggle(isOn: $options.backupToCloud) {
                    HStack(spacing: 8) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(supabase.isConfigured ? AppColors.brand : AppColors.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cloud Backup (Supabase)")
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                            Text(supabase.isConfigured ? "Uploads new trades and journal updates to your private cloud storage." : "Configure in Settings → Data & backups")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                .tint(AppColors.brand)
                .disabled(!supabase.isConfigured)
            }
            .padding(14)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
            )
        }
    }
    
    // MARK: - Section 4: Live Results Log
    private var syncResultsLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNC ACTIVITY LOG")
                .font(AppTypography.cardHeader)
                .tracking(0.5)
                .foregroundColor(AppColors.secondaryText)
            
            VStack(alignment: .leading, spacing: 8) {
                if syncManager.isSyncing {
                    syncInProgressView
                } else if syncManager.lastSyncResults.isEmpty {
                    Text("No recent synchronization activity in this session.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(12)
                } else {
                    let results = Array(syncManager.lastSyncResults.values)
                    ForEach(results) { res in
                        syncResultRow(res)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
            )
        }
    }
    
    private var syncInProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.brand))
                .scaleEffect(0.8)
            Text(syncManager.currentProgress ?? "Synchronizing data...")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brand)
        }
        .padding(12)
    }
    
    private func syncResultRow(_ res: SyncResult) -> some View {
        let isSuccess = res.success
        let statusIcon = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let statusColor = isSuccess ? AppColors.profit : AppColors.loss
        let rowBackground = isSuccess ? AppColors.surface : AppColors.loss.opacity(0.08)
        let messageColor = isSuccess ? AppColors.secondaryText : AppColors.loss
        
        return HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(res.providerName)
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text(Formatters.formatTime(res.timestamp))
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Text(res.message)
                    .font(AppTypography.caption)
                    .foregroundColor(messageColor)
            }
        }
        .padding(10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            if let confirmation = saveConfirmationMessage {
                Text(confirmation)
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.profit)
                    .transition(.opacity)
            }
            
            if syncManager.isSyncing {
                AppButton(
                    "Stop Synchronization",
                    icon: "stop.fill",
                    style: .destructive,
                    size: .regular,
                    fullWidth: true
                ) {
                    cancelSync()
                }
            } else {
                AppButton(
                    "Start Synchronization",
                    icon: "arrow.triangle.2.circlepath",
                    style: .primary,
                    size: .regular,
                    fullWidth: true
                ) {
                    startSync()
                }
                .disabled(options.enabledProviderIds.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.4)),
            alignment: .top
        )
    }
    
    private func saveAsQuickSyncDefault() {
        syncManager.savedQuickSyncOptions = options
        withAnimation {
            saveConfirmationMessage = "Options saved as default Quick Sync!"
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                saveConfirmationMessage = nil
            }
        }
    }
    
    private func cancelSync() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        syncTask?.cancel()
        syncTask = nil
        syncManager.cancelSync()
    }
    
    private func startSync() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        syncTask?.cancel()
        syncTask = Task {
            _ = await syncManager.performSync(with: options)
        }
    }
}
