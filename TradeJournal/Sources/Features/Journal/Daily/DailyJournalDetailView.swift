import SwiftUI
import Charts

/// Port 1:1 from `source-repo/apps/web/src/app/journal/[date]/page.tsx`
public struct DailyJournalDetailView: View {
    public let date: String
    public let isModal: Bool
    
    public init(date: String, isModal: Bool = false) {
        self.date = date
        self.isModal = isModal
        let saved = TradeDataStore.shared.getJournalDayNote(date: date)
        let initialText = !saved.isEmpty ? saved : (TradeDataStore.shared.calendarNotes[date]?.content ?? "")
        self._noteText = State(initialValue: initialText)
    }
    
    @Environment(\.dismiss) internal var dismiss
    @ObservedObject internal var dataStore = TradeDataStore.shared
    @EnvironmentObject internal var env: AppEnvironment
    
    @State internal var noteText: String = ""
    @State internal var isSaving: Bool = false
    @State internal var saveStatusMessage: String = ""
    @State internal var showDeleteNoteAlert: Bool = false
    @State internal var isGeneratingAiRecap: Bool = false
    @State internal var aiErrorMessage: String? = nil
    @State internal var selectedTime: String? = nil
    @State internal var selectedTradeForDetail: Trade? = nil
    @State internal var autoSaveTask: Task<Void, Never>? = nil
    @State internal var hasPendingChanges: Bool = false

    internal static let detailIsoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    internal static let detailTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    internal static let detailLongDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, dd MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    internal var dayTrades: [Trade] {
        Self.detailIsoFormatter.timeZone = env.currentTimeZone
        let isoFormatter = Self.detailIsoFormatter
        
        return dataStore.filteredTrades.filter { t in
            let closeKey = t.closedAt.map { isoFormatter.string(from: $0) }
            let openKey = isoFormatter.string(from: t.openedAt)
            return closeKey == date || (t.status == .open && openKey == date)
        }.sorted { ($0.closedAt ?? $0.openedAt) < ($1.closedAt ?? $1.openedAt) }
    }
    
    internal var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: dayTrades)
    }
    
    internal var intradayPoints: [(timeStr: String, cumPnl: Decimal)] {
        var points: [(timeStr: String, cumPnl: Decimal)] = []
        var running: Decimal = 0
        Self.detailTimeFormatter.timeZone = env.currentTimeZone
        let timeFormatter = Self.detailTimeFormatter
        
        let closed = dayTrades.compactMap { trade -> (Date, Decimal)? in
            guard let close = trade.closedAt else { return nil }
            return (close, trade.netPnl)
        }
        for (closeDate, pnl) in closed {
            running += pnl
            let tStr = timeFormatter.string(from: closeDate)
            points.append((timeStr: tStr, cumPnl: running))
        }
        return points
    }
    
    internal var strideTimeStrings: [String] {
        guard !intradayPoints.isEmpty else { return [] }
        if intradayPoints.count <= 4 {
            var unique: [String] = []
            var seen = Set<String>()
            for p in intradayPoints {
                if !seen.contains(p.timeStr) {
                    seen.insert(p.timeStr)
                    unique.append(p.timeStr)
                }
            }
            return unique
        }
        let count = intradayPoints.count
        let indices = [0, count / 3, (count * 2) / 3, count - 1]
        var seen = Set<String>()
        var result: [String] = []
        for idx in indices {
            let t = intradayPoints[idx].timeStr
            if !seen.contains(t) {
                seen.insert(t)
                result.append(t)
            }
        }
        return result
    }
    
    internal var intradayDoubleVals: [Double] {
        intradayPoints.map { NSDecimalNumber(decimal: $0.cumPnl).doubleValue }
    }
    
    internal var intradayYDomainMax: Double {
        let maxData = intradayDoubleVals.max() ?? 0.0
        let minData = intradayDoubleVals.min() ?? 0.0
        if maxData <= 0 && minData < 0 {
            return 0.0
        }
        let top = max(0.0, maxData)
        let span = max(1.0, top - min(0.0, minData))
        return top + (span * 0.06)
    }
    
    internal var intradayYDomainMin: Double {
        let maxData = intradayDoubleVals.max() ?? 0.0
        let minData = intradayDoubleVals.min() ?? 0.0
        if minData >= 0 && maxData > 0 {
            return 0.0
        }
        let bottom = min(0.0, minData)
        let span = max(1.0, max(0.0, maxData) - bottom)
        return bottom - (span * 0.06)
    }
    
    internal var intradayAreaGradient: LinearGradient {
        let top = intradayYDomainMax
        let bottom = intradayYDomainMin
        if bottom >= 0 {
            return LinearGradient(
                colors: [AppColors.brand.opacity(0.28), AppColors.brand.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if top <= 0 {
            return LinearGradient(
                colors: [AppColors.loss.opacity(0.02), AppColors.loss.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand.opacity(0.28), location: 0.0),
                    .init(color: AppColors.brand.opacity(0.02), location: max(0.0, zeroFraction - 0.001)),
                    .init(color: AppColors.loss.opacity(0.02), location: min(1.0, zeroFraction + 0.001)),
                    .init(color: AppColors.loss.opacity(0.28), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    internal var intradayLineGradient: LinearGradient {
        let top = intradayYDomainMax
        let bottom = intradayYDomainMin
        if bottom >= 0 {
            return LinearGradient(colors: [AppColors.brand, AppColors.brand], startPoint: .top, endPoint: .bottom)
        } else if top <= 0 {
            return LinearGradient(colors: [AppColors.loss, AppColors.loss], startPoint: .top, endPoint: .bottom)
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand, location: 0.0),
                    .init(color: AppColors.brand, location: max(0.0, zeroFraction - 0.002)),
                    .init(color: AppColors.loss, location: min(1.0, zeroFraction + 0.002)),
                    .init(color: AppColors.loss, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Card 1: Day stats KPI grid (port 1:1 from web Day stats)
                dayStatsCard
                
                // Card 2: Intraday cumulative net P&L chart
                if !intradayPoints.isEmpty {
                    intradayChartCard
                }
                
                // Card 3: Closed and open trades list
                if !dayTrades.isEmpty {
                    dayTradesCard
                }
                
                // Card 4: Day note editor & AI Recap
                dayNoteCard
                
                // Card 5: Attachments & chart screenshots
                AttachmentsSectionView(ownerType: "day", ownerId: date, title: "Attachments")
                    .padding(.horizontal, 14)
            }
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView(
                title: "Journal · \(date)",
                showFilters: false,
                onBack: { dismiss() },
                isModal: isModal
            )
        }
        .background(AppColors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveEdgeBack(onBack: isModal ? nil : { dismiss() })
        .enableNativePopGesture()
        .sheet(item: $selectedTradeForDetail) { trade in
            TradeDetailView(trade: trade, isModal: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Delete note for \(date)?", isPresented: $showDeleteNoteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                noteText = ""
                dataStore.deleteCalendarNote(for: date)
                saveStatusMessage = "Deleted"
            }
        } message: {
            Text("This note will be permanently removed from your calendar and Supabase.")
        }
        .onAppear {
            loadNote()
        }
        .onDisappear {
            saveNoteImmediately(force: hasPendingChanges)
        }
    }
    

    // MARK: - Actions & Persistence
    
    internal func loadNote() {
        let saved = dataStore.getJournalDayNote(date: date)
        if !saved.isEmpty {
            noteText = saved
        } else if let cal = dataStore.calendarNotes[date] {
            noteText = cal.content
        }
    }
    
    internal func scheduleSaveNote(_ text: String) {
        hasPendingChanges = true
        saveStatusMessage = "Editing..."
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            saveNoteImmediately()
        }
    }
    
    internal func saveNoteImmediately(force: Bool = false) {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard force || hasPendingChanges else { return }
        hasPendingChanges = false
        
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dataStore.deleteCalendarNote(for: date)
            saveStatusMessage = "Cleared"
            return
        }
        dataStore.saveJournalDayNote(date: date, note: noteText)
        dataStore.saveToDisk(immediate: true)
        saveStatusMessage = "Saved"
    }
    
    internal func applyFormat(marker: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let res = NoteFormattingEngine.formatInlineSelection(
            value: noteText,
            start: (noteText as NSString).length,
            end: (noteText as NSString).length,
            marker: marker
        )
        noteText = res.value
        scheduleSaveNote(noteText)
    }
    
    internal func insertBullet() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += "- "
        } else {
            noteText += "\n- "
        }
        scheduleSaveNote(noteText)
    }
    
    internal func insertNumberedList() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += "1. "
        } else {
            noteText += "\n1. "
        }
        scheduleSaveNote(noteText)
    }
    
    internal func generateAiRecap() {
        guard !dayTrades.isEmpty else { return }
        isGeneratingAiRecap = true
        aiErrorMessage = nil
        
        Task {
            do {
                let prompt = "Please summarize the trading day \(date) with \(metrics.closedTrades) trades, Net P&L: \(metrics.netPnl), Win rate: \(metrics.winRate?.description ?? "0"). Highlight 2 strengths and 1 area for discipline improvement."
                let recap = try await AIReflectionService.shared.requestReflection(action: .recap, prompt: prompt, metrics: metrics)
                
                await MainActor.run {
                    self.isGeneratingAiRecap = false
                    let section = self.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "## AI Recap (\(self.date))\n\n\(recap)"
                        : "\n\n## AI Recap (\(self.date))\n\n\(recap)"
                    self.noteText += section
                    self.hasPendingChanges = true
                    self.saveNoteImmediately(force: true)
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingAiRecap = false
                    self.aiErrorMessage = "AI Recap notice: \(error.localizedDescription)"
                }
            }
        }
    }
}
