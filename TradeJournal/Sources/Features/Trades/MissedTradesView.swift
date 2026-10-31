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
        let q = (env.isSearchActive ? env.searchQuery : searchText).trimmingCharacters(in: .whitespaces).lowercased()
        return dataStore.missedTrades.filter { trade in
            let isArchived = trade.archivedAt != nil
            guard isArchived == showArchived else { return false }
            
            if q.isEmpty { return true }
            return trade.symbol.lowercased().contains(q) || trade.notes.lowercased().contains(q)
        }.sorted { $0.observedAt > $1.observedAt }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Compact Segmented Status Switcher
                Picker("Status", selection: $showArchived) {
                    Text("Active").tag(false)
                    Text("Archived").tag(true)
                }
                .pickerStyle(.segmented)
                
                if filteredTrades.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTrades) { trade in
                            missedTradeRow(trade)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
        .onReceive(env.$requestNewMissedTrade) { requested in
            if requested {
                env.requestNewMissedTrade = false
                editingTrade = nil
                showAddSheet = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
                AppPrimaryButton("Log Opportunity", icon: "plus", height: 38) {
                    editingTrade = nil
                    showAddSheet = true
                }
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
                JournalNotesMarkdownView(text: trade.notes)
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

/// Sheet for logging or editing missed trade opportunities with Apple HIG dark luxury cards
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
    
    private static let quickSymbols = ["EURUSD", "XAUUSD", "GBPUSD", "BTCUSDT", "NQ", "US30"]
    
    public init(tradeToEdit: MissedTrade? = nil) {
        self.tradeToEdit = tradeToEdit
        if let t = tradeToEdit {
            _symbol = State(initialValue: t.symbol)
            _direction = State(initialValue: t.direction)
            _entryText = State(initialValue: Formatters.formatDecimalInput(t.entry, maxDecimals: 5))
            _stopText = State(initialValue: Formatters.formatDecimalInput(t.stop, maxDecimals: 5))
            _targetText = State(initialValue: Formatters.formatDecimalInput(t.target, maxDecimals: 5))
            _selectedPlaybookId = State(initialValue: t.playbookId ?? "")
            _notes = State(initialValue: t.notes)
            _observedDate = State(initialValue: FlexibleDateParser.parse(t.observedAt) ?? Date())
        }
    }
    
    // Live Planned R:R computation
    private var plannedRRInfo: (ratio: Double, isValidDirection: Bool)? {
        guard let entry = Decimal(string: entryText.replacingOccurrences(of: ",", with: ".")),
              let stop = Decimal(string: stopText.replacingOccurrences(of: ",", with: ".")),
              let target = Decimal(string: targetText.replacingOccurrences(of: ",", with: ".")),
              entry > 0 else {
            return nil
        }
        
        let isLong = direction == "long"
        let validDir = isLong ? (stop < entry && target > entry) : (stop > entry && target < entry)
        let risk = abs(entry - stop)
        let reward = abs(target - entry)
        guard risk > 0 else { return nil }
        let rr = (reward as NSDecimalNumber).doubleValue / (risk as NSDecimalNumber).doubleValue
        return (rr, validDir)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Error Banner
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.loss)
                            Text(err)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.loss)
                            Spacer()
                        }
                        .padding(12)
                        .background(AppColors.loss.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    
                    // Card 1: Opportunity Details
                    opportunityCard
                    
                    // Card 2: Planned Prices & R:R
                    plannedPricesCard
                    
                    // Card 3: Playbook Selection
                    playbookCard
                    
                    // Card 4: Post-Mortem & Notes
                    notesCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.background)
            .navigationTitle(tradeToEdit == nil ? "Log Opportunity" : "Edit Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save") {
                        save()
                    }
                }
            }
        }
    }
    
    // MARK: - Opportunity Card
    private var opportunityCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("OPPORTUNITY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                // Symbol Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbol")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("e.g. EURUSD, XAUUSD, NQ...", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                        
                        if !symbol.isEmpty {
                            Button {
                                symbol = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.secondaryText)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.8), lineWidth: 0.5)
                    )
                }
                
                // Quick Symbol Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.quickSymbols, id: \.self) { sym in
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                symbol = sym
                            } label: {
                                Text(sym)
                                    .font(.system(size: 11, weight: symbol == sym ? .bold : .medium))
                                    .foregroundColor(symbol == sym ? AppColors.brand : AppColors.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(symbol == sym ? AppColors.brand.opacity(0.14) : AppColors.secondaryBackground)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(symbol == sym ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: 0.6)
                                    )
                            }
                        }
                    }
                }
                
                // Direction Toggle
                VStack(alignment: .leading, spacing: 6) {
                    Text("Direction")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 10) {
                        directionButton(title: "BUY / LONG", isBuy: true, isSelected: direction == "long") {
                            direction = "long"
                        }
                        
                        directionButton(title: "SELL / SHORT", isBuy: false, isSelected: direction == "short") {
                            direction = "short"
                        }
                    }
                }
                
                // Observed At Date
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.brand)
                        Text("Observed At")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    DatePicker("", selection: $observedDate)
                        .labelsHidden()
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func directionButton(title: String, isBuy: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isBuy ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? (isBuy ? AppColors.profit.opacity(0.18) : AppColors.loss.opacity(0.18))
                    : AppColors.secondaryBackground
            )
            .foregroundColor(
                isSelected
                    ? (isBuy ? AppColors.profit : AppColors.loss)
                    : AppColors.secondaryText
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? (isBuy ? AppColors.profit.opacity(0.6) : AppColors.loss.opacity(0.6))
                            : AppColors.border.opacity(0.6),
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Planned Prices Card
    private var plannedPricesCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PLANNED TARGETS (R:R)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    if let info = plannedRRInfo {
                        HStack(spacing: 4) {
                            Text("1 : \(String(format: "%.2f", info.ratio)) R")
                                .font(AppTypography.number(11, weight: .bold))
                                .foregroundColor(info.isValidDirection ? AppColors.brand : .orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(info.isValidDirection ? AppColors.brand.opacity(0.12) : Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                
                // 3 numeric input boxes
                VStack(spacing: 10) {
                    TradeNumericInputBlock(
                        title: "Planned Entry",
                        subtitle: "Desired execution price",
                        text: $entryText,
                        placeholder: "0.00"
                    )
                    
                    TradeNumericInputBlock(
                        title: "Planned Stop Loss",
                        subtitle: "Invalidation level",
                        text: $stopText,
                        placeholder: "0.00"
                    )
                    
                    TradeNumericInputBlock(
                        title: "Planned Take Profit",
                        subtitle: "Primary target",
                        text: $targetText,
                        placeholder: "0.00"
                    )
                }
                
                if let info = plannedRRInfo, !info.isValidDirection {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(direction == "long" ? "For BUY, Stop Loss must be below Entry and Take Profit above." : "For SELL, Stop Loss must be above Entry and Take Profit below.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    // MARK: - Playbook Card
    private var playbookCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("PLAYBOOK")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                let playbookOptions = [""] + dataStore.playbooks.map { $0.id }
                AppDropdownField(
                    label: "Associated playbook",
                    selection: $selectedPlaybookId,
                    options: playbookOptions,
                    titleFor: { id in
                        if id.isEmpty { return "None" }
                        return dataStore.playbooks.first(where: { $0.id == id })?.name ?? id
                    }
                )
            }
        }
    }
    
    // MARK: - Post-Mortem Notes Card
    private var notesCard: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("POST-MORTEM & NOTES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text("Why did you miss this setup? Describe your thesis, entry trigger, hesitation, or psychological factor.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                RichNoteEditor(
                    text: $notes,
                    placeholder: "e.g. Hesitated on M5 fair value gap entry due to earlier loss. Setup ran cleanly to 2.5R target...",
                    minHeight: 120,
                    allowPreviewToggle: true
                )
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
