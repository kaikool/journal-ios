import SwiftUI

/// Missed trades management view
/// Port 1:1 from `source-repo/apps/web/src/app/missed/page.tsx`
public struct MissedTradesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var searchText: String = ""
    @State private var showArchived: Bool = false
    @State private var showAddSheet: Bool = false
    @State private var editingTrade: MissedTrade? = nil
    
    public init() {}
    
    private var filteredTrades: [MissedTrade] {
        dataStore.missedTrades.filter { trade in
            let isArchived = trade.archivedAt != nil
            guard isArchived == showArchived else { return false }
            
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if query.isEmpty { return true }
            return trade.symbol.lowercased().contains(query) || trade.notes.lowercased().contains(query)
        }.sorted { $0.observedAt > $1.observedAt }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Missed trades",
                showFilters: false
            ) {
                AppActionPill("Log opportunity", icon: "plus") {
                    editingTrade = nil
                    showAddSheet = true
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Record setups you watched but did not take. These observations never enter your trade count, P&L, or win rate.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                HStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.secondaryText)
                            .font(.system(size: 13))
                        TextField("Search symbol or notes…", text: $searchText)
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
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
                    
                    // Show archived toggle
                    Button {
                        showArchived.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showArchived ? "checkmark.square.fill" : "square")
                                .foregroundColor(showArchived ? AppColors.brand : AppColors.secondaryText)
                                .font(.system(size: 14))
                            Text("Show archived")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            
            Divider()
                .overlay(AppColors.border)
            
            if filteredTrades.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredTrades) { trade in
                        missedTradeRow(trade)
                            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $showAddSheet) {
            AddMissedTradeSheet(tradeToEdit: editingTrade)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundColor(AppColors.secondaryText)
            
            Text(showArchived ? "No archived opportunities here yet" : "No opportunities recorded yet")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
            
            Text("Record setups you watched but did not take, to review execution discipline and identify hesitation patterns.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if !showArchived {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    editingTrade = nil
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Log Missed Opportunity")
                    }
                    .font(AppTypography.subheadlineBold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(AppColors.brand)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
            Spacer()
        }
    }
    
    private func missedTradeRow(_ trade: MissedTrade) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(trade.symbol)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Text(trade.direction.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(trade.direction.lowercased() == "long" ? AppColors.brand : AppColors.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((trade.direction.lowercased() == "long" ? AppColors.brand : AppColors.warning).opacity(0.12))
                    .clipShape(Capsule())
                
                if let pbId = trade.playbookId, let pb = dataStore.playbooks.first(where: { $0.id == pbId }) {
                    AppBadge(text: pb.name, color: AppColors.secondaryText)
                }
                
                Spacer()
                
                Text(formatDate(trade.observedAt))
                    .font(AppTypography.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
            }
            
            // Pricing grid (Entry, Stop, Target, R:R)
            HStack(spacing: 16) {
                if let entry = trade.entry {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entry").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(entry))
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                if let stop = trade.stop {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(stop))
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.loss)
                    }
                }
                if let target = trade.target {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                        Text(Formatters.price(target))
                            .font(AppTypography.captionBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.profit)
                    }
                }
                if let entry = trade.entry, let stop = trade.stop, let target = trade.target {
                    let risk = abs(entry - stop)
                    let reward = abs(target - entry)
                    if risk > 0 {
                        let rr = (reward as NSDecimalNumber).doubleValue / (risk as NSDecimalNumber).doubleValue
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("R : R").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                            Text(String(format: "1 : %.1f", rr))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(AppColors.brand)
                        }
                    }
                }
            }
            
            if !trade.notes.isEmpty {
                Divider().background(AppColors.border.opacity(0.4))
                Text(trade.notes)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1.5)
        .contextMenu {
            Button {
                editingTrade = trade
                showAddSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button {
                dataStore.toggleArchiveMissedTrade(id: trade.id)
            } label: {
                Label(trade.archivedAt == nil ? "Archive" : "Restore", systemImage: trade.archivedAt == nil ? "archivebox" : "arrow.up.bin")
            }
            
            Button(role: .destructive) {
                dataStore.deleteMissedTrade(id: trade.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func formatDate(_ iso: String) -> String {
        if let d = FlexibleDateParser.parse(iso) {
            let f = DateFormatter()
            f.dateFormat = "dd/MM/yyyy HH:mm"
            return f.string(from: d)
        }
        return iso
    }
}

/// Sheet for logging or editing missed trade opportunities
public struct AddMissedTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    private let tradeToEdit: MissedTrade?
    
    @State private var symbol: String = ""
    @State private var direction: String = "long"
    @State private var observedDate: Date = Date()
    @State private var entryText: String = ""
    @State private var stopText: String = ""
    @State private var targetText: String = ""
    @State private var selectedPlaybookId: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String? = nil
    
    public init(tradeToEdit: MissedTrade? = nil) {
        self.tradeToEdit = tradeToEdit
        if let t = tradeToEdit {
            _symbol = State(initialValue: t.symbol)
            _direction = State(initialValue: t.direction)
            _entryText = State(initialValue: t.entry != nil ? "\(t.entry!)" : "")
            _stopText = State(initialValue: t.stop != nil ? "\(t.stop!)" : "")
            _targetText = State(initialValue: t.target != nil ? "\(t.target!)" : "")
            _selectedPlaybookId = State(initialValue: t.playbookId ?? "")
            _notes = State(initialValue: t.notes)
            _observedDate = State(initialValue: FlexibleDateParser.parse(t.observedAt) ?? Date())
        }
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Opportunity Details") {
                    TextField("Symbol (e.g. EURUSD, XAUUSD, NQ)", text: $symbol)
                        .autocapitalization(.allCharacters)
                    
                    Picker("Direction", selection: $direction) {
                        Text("BUY / LONG").tag("long")
                        Text("SELL / SHORT").tag("short")
                    }
                    .pickerStyle(.segmented)
                    
                    DatePicker("Observed at", selection: $observedDate)
                }
                
                Section("Planned Prices") {
                    TextField("Planned entry", text: $entryText)
                        .keyboardType(.decimalPad)
                    TextField("Planned stop loss", text: $stopText)
                        .keyboardType(.decimalPad)
                    TextField("Planned take profit", text: $targetText)
                        .keyboardType(.decimalPad)
                }
                
                Section("Playbook") {
                    Picker("Associated playbook", selection: $selectedPlaybookId) {
                        Text("None").tag("")
                        ForEach(dataStore.playbooks) { pb in
                            Text(pb.name).tag(pb.id)
                        }
                    }
                }
                
                Section("Review & Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                if let err = errorMessage {
                    Section {
                        Text(err).foregroundColor(AppColors.loss).font(AppTypography.caption)
                    }
                }
            }
            .navigationTitle(tradeToEdit == nil ? "Log Missed Opportunity" : "Edit Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.accent)
                }
            }
        }
    }
    
    private func save() {
        let cleanSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanSymbol.isEmpty else {
            errorMessage = "Please enter an instrument symbol."
            return
        }
        
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let observedIso = fmt.string(from: observedDate)
        
        let item = MissedTrade(
            id: tradeToEdit?.id ?? JournalIds.newId(),
            symbol: cleanSymbol,
            direction: direction,
            observedAt: observedIso,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            entry: Decimal(string: entryText.replacingOccurrences(of: ",", with: ".")),
            stop: Decimal(string: stopText.replacingOccurrences(of: ",", with: ".")),
            target: Decimal(string: targetText.replacingOccurrences(of: ",", with: ".")),
            notes: notes,
            createdAt: tradeToEdit?.createdAt ?? JournalIds.nowIso(),
            archivedAt: tradeToEdit?.archivedAt
        )
        
        dataStore.saveMissedTrade(item)
        dismiss()
    }
}
