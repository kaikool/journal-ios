import SwiftUI
import UIKit

// MARK: - Dedicated AI Trade Coach Sheet
// Provides deep tactical, psychological, and risk advice tailored specifically for a single position.
// For OPEN positions: evaluates live TP target, trailing SL to breakeven, and risk exposure.
// For CLOSED positions: delivers forensic post-mortem, execution critique, and 1 non-negotiable lesson.
public struct TradeAICoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public let trade: Trade
    public var onTradeUpdated: ((Trade) -> Void)? = nil
    
    @State private var coachingResult: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isSavedToNotes: Bool = false
    @State private var isSavedToNotebook: Bool = false
    @State private var showCopiedAlert: Bool = false
    
    public init(trade: Trade, onTradeUpdated: ((Trade) -> Void)? = nil) {
        self.trade = trade
        self.onTradeUpdated = onTradeUpdated
    }
    
    private var isOpen: Bool {
        trade.status == .open || trade.closedAt == nil
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Trade Context Pill
                    tradeContextCard
                    
                    // 2. Loading, Error, or AI Result Document
                    if isLoading {
                        loadingCard
                    } else if let error = errorMessage {
                        errorCard(error)
                    } else if !coachingResult.isEmpty {
                        aiResultCard
                        
                        // 3. Compact Action Bar
                        bottomActionBar
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("AI Trade Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.primaryText)
                }
            }
        }
        .task {
            await runCoachingAnalysis()
        }
    }
    
    // MARK: - 1. Trade Context Card
    private var tradeContextCard: some View {
        AppCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        let isShort = trade.direction == .short
                        Text(isShort ? "SELL" : "BUY")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isShort ? AppColors.warning.opacity(0.12) : AppColors.brand.opacity(0.12))
                            .foregroundColor(isShort ? AppColors.warning : AppColors.brand)
                            .cornerRadius(4)
                        
                        Text(isOpen ? "OPEN POSITION" : "CLOSED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(isOpen ? AppColors.brand : AppColors.secondaryText)
                            .cornerRadius(4)
                    }
                    
                    let volStr = String(format: "%.2f", NSDecimalNumber(decimal: trade.quantity).doubleValue)
                    let entryStr = Formatters.price(trade.avgEntry)
                    let exitStr = trade.avgExit.map { Formatters.price($0) } ?? (isOpen ? "Live" : "N/A")
                    
                    Text("\(volStr) lots • Entry: \(entryStr) → \(exitStr)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                let pnlVal = NSDecimalNumber(decimal: trade.netPnl).doubleValue
                let pnlStr = (trade.netPnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pnlStr)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColors.profit)
                            .frame(width: 5, height: 5)
                        Text("LIVE AI")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - 2. Loading View
    private var loadingCard: some View {
        AppCard {
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.brand))
                    .scaleEffect(1.1)
                
                Text(isOpen ? "Evaluating market structure, TP targets & trailing SL..." : "Extracting trade post-mortem & non-negotiable lesson...")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }
    
    // MARK: - 3. Error Card
    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundColor(AppColors.warning)
                
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    Task { await runCoachingAnalysis() }
                }) {
                    Text("Retry Analysis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - 4. AI Result Card
    private var aiResultCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(parseCoachingBlocks(coachingResult), id: \.id) { block in
                    renderCoachingBlock(block)
                }
            }
            .padding(.vertical, 4)
            .textSelection(.enabled)
        }
    }
    
    // MARK: - 5. Bottom Action Bar (Compact, Tidy, Minimalist)
    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Append to Trade Notes
                Button(action: appendToNotes) {
                    HStack(spacing: 5) {
                        Image(systemName: isSavedToNotes ? "checkmark" : "note.text.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isSavedToNotes ? "Appended" : "Append to Notes")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isSavedToNotes ? AppColors.profit : AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
                }
                .disabled(isSavedToNotes)
                
                // Save to Notebook
                Button(action: saveToNotebook) {
                    HStack(spacing: 5) {
                        Image(systemName: isSavedToNotebook ? "checkmark" : "bookmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isSavedToNotebook ? "Saved" : "Notebook")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isSavedToNotebook ? AppColors.profit : AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
                }
                .disabled(isSavedToNotebook)
                
                // Copy Button
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showCopiedAlert ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
                }
                
                // Regenerate
                Button(action: {
                    Task { await runCoachingAnalysis() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                        )
                }
            }
        }
    }
    
    // MARK: - Block Renderer
    @ViewBuilder
    private func renderCoachingBlock(_ block: CoachingBlock) -> some View {
        switch block.kind {
        case .header:
            Text(LocalizedStringKey(block.content))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
                .padding(.top, 4)
            
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AppColors.brand)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
                    .padding(.vertical, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground.opacity(0.6))
            .cornerRadius(8)
            
        case .numbered(let num):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 20, alignment: .leading)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
            }
            .padding(.leading, 2)
            
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.top, 1)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
            }
            .padding(.leading, 4)
            
        case .paragraph:
            Text(LocalizedStringKey(block.content))
                .font(AppTypography.body)
                .foregroundColor(AppColors.primaryText)
                .lineSpacing(4)
        }
    }
    
    // MARK: - Block Parsing & Sanitization
    private struct CoachingBlock: Identifiable {
        let id = UUID()
        enum Kind { case header, quote, numbered(Int), bullet, paragraph }
        let kind: Kind
        let content: String
    }
    
    private func sanitizeMarkdown(_ str: String) -> String {
        var s = str.replacingOccurrences(of: "* *", with: "*")
        s = s.replacingOccurrences(of: "• •", with: "•")
        s = s.replacingOccurrences(of: "- -", with: "-")
        return s
    }
    
    private func parseCoachingBlocks(_ text: String) -> [CoachingBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [CoachingBlock] = []
        var paragraphBuffer: [String] = []
        
        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: " ")
                blocks.append(CoachingBlock(kind: .paragraph, content: sanitizeMarkdown(joined)))
                paragraphBuffer = []
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flushParagraph()
                let clean = trimmed.replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                blocks.append(CoachingBlock(kind: .header, content: sanitizeMarkdown(clean)))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                let clean = trimmed.replacingOccurrences(of: "> ", with: "")
                blocks.append(CoachingBlock(kind: .quote, content: sanitizeMarkdown(clean)))
            } else if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(trimmed[match])
                let digits = prefix.filter { $0.isNumber }
                let num = Int(digits) ?? 1
                var clean = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                clean = sanitizeMarkdown(clean)
                blocks.append(CoachingBlock(kind: .numbered(num), content: clean))
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                var clean = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                while clean.hasPrefix("* ") || clean.hasPrefix("• ") || clean.hasPrefix("- ") {
                    clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                clean = sanitizeMarkdown(clean)
                blocks.append(CoachingBlock(kind: .bullet, content: clean))
            } else {
                paragraphBuffer.append(trimmed)
            }
        }
        flushParagraph()
        
        return blocks.isEmpty ? [CoachingBlock(kind: .paragraph, content: sanitizeMarkdown(text))] : blocks
    }
    
    // MARK: - Coaching Logic & Context Fetching
    private func runCoachingAnalysis() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
            self.isSavedToNotes = false
            self.isSavedToNotebook = false
        }
        
        // 1. Fetch 12-hour candlestick context around trade
        var candleSummary: String? = nil
        do {
            let res = try await MarketDataService.shared.fetchBarsForTrade(
                trade: trade,
                config: dataStore.marketConnections,
                resolution: "15m"
            )
            if !res.bars.isEmpty {
                let count = res.bars.count
                let highs = res.bars.map { NSDecimalNumber(decimal: $0.high).doubleValue }
                let lows = res.bars.map { NSDecimalNumber(decimal: $0.low).doubleValue }
                let maxH = highs.max() ?? 0
                let minL = lows.min() ?? 0
                let lastClose = NSDecimalNumber(decimal: res.bars.last?.close ?? 0).doubleValue
                
                // Format the last 12 bars into a concise OHLC progression stream
                let sampleSlice = res.bars.suffix(12)
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                let barFlow = sampleSlice.map { b in
                    let t = timeFormatter.string(from: b.time)
                    let o = String(format: "%.2f", NSDecimalNumber(decimal: b.open).doubleValue)
                    let h = String(format: "%.2f", NSDecimalNumber(decimal: b.high).doubleValue)
                    let l = String(format: "%.2f", NSDecimalNumber(decimal: b.low).doubleValue)
                    let c = String(format: "%.2f", NSDecimalNumber(decimal: b.close).doubleValue)
                    return "[\(t)] O:\(o) H:\(h) L:\(l) C:\(c)"
                }.joined(separator: " -> ")
                
                candleSummary = "\(count) x 15m bars (\(res.provider)). High: \(String(format: "%.2f", maxH)) | Low: \(String(format: "%.2f", minL)) | Last Close: \(String(format: "%.2f", lastClose)). Flow: \(barFlow)"
            }
        } catch {
            candleSummary = "Feed unavailable / Not connected. Ground all critique purely on recorded Entry, Exit, SL, TP, duration and P&L. Do not guess or invent chart patterns."
        }
        
        // 2. Request AI Trade Coaching
        do {
            let response = try await AIReflectionService.shared.requestTradeCoaching(
                trade: trade,
                language: dataStore.aiSettings.language,
                recentCandlesSummary: candleSummary
            )
            await MainActor.run {
                self.coachingResult = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Actions
    private func appendToNotes() {
        guard !coachingResult.isEmpty else { return }
        let dateStr = JournalIds.todayDateString()
        let prefix = isOpen ? "Live Coaching (\(dateStr))" : "AI Post-Mortem (\(dateStr))"
        let addition = "\n\n--- [\(prefix)] ---\n\(coachingResult)"
        
        let existingNotes = trade.notes ?? ""
        let newNotes = (existingNotes + addition).trimmingCharacters(in: .whitespacesAndNewlines)
        
        dataStore.updateTradeAnnotations(
            key: trade.key,
            notes: newNotes,
            tags: trade.tags,
            mistakes: trade.mistakes,
            stopLoss: trade.stopLoss,
            profitTarget: trade.profitTarget,
            rating: trade.rating,
            playbookId: trade.playbookId,
            reviewedAt: Date()
        )
        
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            onTradeUpdated?(updated)
        }
        
        isSavedToNotes = true
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func saveToNotebook() {
        guard !coachingResult.isEmpty else { return }
        let targetFolderName = "Trade Insights"
        let folder: NotebookFolder
        if let existing = dataStore.folders.first(where: { $0.name.lowercased() == targetFolderName.lowercased() }) {
            folder = existing
        } else {
            do {
                folder = try dataStore.createFolder(name: targetFolderName)
            } catch {
                AppLogger.warning("Failed to create folder: \(error.localizedDescription)")
                return
            }
        }
        
        let dateStr = JournalIds.todayDateString()
        let title = isOpen
            ? "[AI Live Coach] \(trade.symbol) \(trade.side.uppercased()) (\(dateStr))"
            : "[AI Post-Mortem] \(trade.symbol) \(trade.side.uppercased()) (\(dateStr))"
        
        do {
            _ = try dataStore.createNote(
                folderId: folder.id,
                title: title,
                content: coachingResult,
                tags: ["#ai-coach", "#trade-audit", "#\(trade.symbol.lowercased())"],
                tradeKey: trade.key,
                dayDate: dateStr
            )
            isSavedToNotebook = true
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            AppLogger.warning("Failed to save note: \(error.localizedDescription)")
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = coachingResult
        showCopiedAlert = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
}
