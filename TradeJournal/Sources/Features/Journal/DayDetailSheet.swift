import SwiftUI

/// Model representing pre-computed day details passed directly to DayDetailSheet
public struct DayDetailContext: Identifiable {
    public var id: String { dateKey }
    public let dateKey: String
    public let stats: DayStats?
    public let trades: [Trade]
    public let note: JournalNote
    
    public init(dateKey: String, stats: DayStats?, trades: [Trade], note: JournalNote) {
        self.dateKey = dateKey
        self.stats = stats
        self.trades = trades
        self.note = note
    }
}

// MARK: - DayDetailSheet

public struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    
    public let dateKey: String
    public let stats: DayStats?
    public let trades: [Trade]
    public let note: JournalNote
    public let onSaveNote: (JournalNote) -> Void
    public let onAddTrade: () -> Void
    
    @State private var noteContent: String = ""
    @State private var rating: Int = 0
    @State private var showDeleteNoteAlert: Bool = false
    @State private var saveStatus: String = ""
    
    public init(
        dateKey: String,
        stats: DayStats?,
        trades: [Trade],
        note: JournalNote,
        onSaveNote: @escaping (JournalNote) -> Void,
        onAddTrade: @escaping () -> Void
    ) {
        self.dateKey = dateKey
        self.stats = stats
        self.trades = trades
        self.note = note
        self.onSaveNote = onSaveNote
        self.onAddTrade = onAddTrade
        _noteContent = State(initialValue: note.content)
        _rating = State(initialValue: note.rating ?? 0)
    }
    
    private func formattedDateTitle(_ key: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        inFormatter.timeZone = TimeZone(identifier: "UTC")
        guard let d = inFormatter.date(from: key) else { return key }
        let outFormatter = DateFormatter()
        outFormatter.locale = Locale(identifier: "en_US")
        outFormatter.dateFormat = "EEEE, MMM d, yyyy"
        outFormatter.timeZone = TimeZone(identifier: "UTC")
        return outFormatter.string(from: d)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    noteCard
                    tradesCard
                    actionButtons
                }
                .padding(14)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(formattedDateTitle(dateKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !noteContent.isEmpty || rating > 0 {
                        Button {
                            showDeleteNoteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(AppColors.loss.opacity(0.85))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brand)
                }
            }
            .alert("Delete note for this day?", isPresented: $showDeleteNoteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    noteContent = ""
                    rating = 0
                    TradeDataStore.shared.deleteCalendarNote(for: dateKey)
                    saveStatus = "Deleted"
                }
            } message: {
                Text("This note will be permanently removed from your calendar and Supabase.")
            }
        }
    }
    
    @ViewBuilder
    private var summaryCard: some View {
        let netPnl = stats?.netPnl ?? .zero
        let isProfit = netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        let tradeCount = stats?.trades ?? trades.count
        
        AppCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    AppCardHeader("Net P&L")
                    AppMonetaryText(
                        Formatters.formatPnL(netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 22, weight: .bold),
                        color: pnlColor
                    )
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    AppCardHeader("Trades")
                    Text("\(tradeCount)")
                        .font(AppTypography.financialNumber(size: 22, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var noteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AppCardHeader("Daily Note")
                    Spacer()
                    if !noteContent.isEmpty || rating > 0 {
                        Button {
                            showDeleteNoteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.loss.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundColor(star <= rating ? .yellow : AppColors.mutedText)
                                .onTapGesture {
                                    rating = (rating == star) ? 0 : star
                                    save()
                                }
                        }
                    }
                }
                
                // Formatting toolbar
                HStack(spacing: 8) {
                    Button {
                        applyFormat(marker: "**")
                    } label: {
                        Text("B")
                            .font(.system(size: 13, weight: .black))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        applyFormat(marker: "*")
                    } label: {
                        Text("I")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .italic()
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        insertNumberedList()
                    } label: {
                        Image(systemName: "list.number")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        insertBullet()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Spacer()
                }
                
                TextField("Write thoughts or notes for this day...", text: $noteContent, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTypography.inputText)
                    .foregroundColor(AppColors.primaryText)
                    .padding(10)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                    )
                
                HStack(spacing: 12) {
                    if !saveStatus.isEmpty {
                        Text(saveStatus)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if !noteContent.isEmpty {
                        Button("Clear") {
                            noteContent = ""
                            save()
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text("Save")
                        }
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brand)
                    }
                }
                
                if noteContent.contains("*") || noteContent.contains("- ") || noteContent.contains("1. ") || noteContent.contains("#") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FORMATTED PREVIEW")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                        
                        Text(LocalizedStringKey(noteContent))
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.primaryText)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.secondaryBackground.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    private var tradesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader("Trades (\(trades.count))")
                
                if trades.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.secondaryText)
                        Text("No closed trades on this day")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(trades) { trade in
                        tradeRow(trade)
                        if trade.id != trades.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func tradeRow(_ trade: Trade) -> some View {
        let isProfit = trade.netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        
        HStack {
            AppBadge(trade.status.rawValue.uppercased(), color: Formatters.statusColor(trade.status))
            Text(trade.symbol)
                .font(AppTypography.bodyBold)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            AppMonetaryText(
                Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                isPrivate: env.isPrivacyModeEnabled,
                font: AppTypography.financialNumber(size: 13, weight: .semibold),
                color: pnlColor
            )
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onAddTrade) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Trade")
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brandTextOnDark)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.brand)
                .cornerRadius(6)
            }
            
            NavigationLink(destination: DailyJournalDetailView(date: dateKey)) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("Full Journal")
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
        }
    }
    
    private func applyFormat(marker: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let res = NoteFormattingEngine.formatInlineSelection(
            value: noteContent,
            start: (noteContent as NSString).length,
            end: (noteContent as NSString).length,
            marker: marker
        )
        noteContent = res.value
        save()
    }
    
    private func insertBullet() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteContent.isEmpty || noteContent.hasSuffix("\n") {
            noteContent += "- "
        } else {
            noteContent += "\n- "
        }
        save()
    }
    
    private func insertNumberedList() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteContent.isEmpty || noteContent.hasSuffix("\n") {
            noteContent += "1. "
        } else {
            noteContent += "\n1. "
        }
        save()
    }

    private func save() {
        let trimmed = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && rating == 0 {
            TradeDataStore.shared.deleteCalendarNote(for: dateKey)
            saveStatus = "Deleted"
            return
        }
        var updated = note
        updated.content = noteContent
        updated.rating = rating > 0 ? rating : nil
        updated.updatedAt = Date()
        onSaveNote(updated)
        saveStatus = "Saved"
    }
}
