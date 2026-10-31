import SwiftUI

// MARK: - Link Note to Trade / Order Ticket Sheet
/// Standard minimalist sheet for linking a Notebook note with an executed trade ticket.
public struct LinkNoteToTradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public let noteId: String
    public let noteTitle: String
    public let currentTradeKey: String?
    public var onLinked: ((Trade, String) -> Void)?
    public var onUnlinked: (() -> Void)?
    
    @State private var searchText: String = ""
    
    public init(
        noteId: String,
        noteTitle: String,
        currentTradeKey: String? = nil,
        onLinked: ((Trade, String) -> Void)? = nil,
        onUnlinked: (() -> Void)? = nil
    ) {
        self.noteId = noteId
        self.noteTitle = noteTitle
        self.currentTradeKey = currentTradeKey
        self.onLinked = onLinked
        self.onUnlinked = onUnlinked
    }
    
    private var filteredTrades: [Trade] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let trades = dataStore.trades
        
        let filtered: [Trade]
        if query.isEmpty {
            filtered = trades
        } else {
            filtered = trades.filter { trade in
                let sym = trade.symbol.lowercased()
                let matchTicket = trade.executionIds.contains(where: { $0.lowercased().contains(query) }) || trade.key.lowercased().contains(query)
                return sym.contains(query) || matchTicket
            }
        }
        
        return filtered.sorted { t1, t2 in
            if (t1.status == .open) != (t2.status == .open) {
                return t1.status == .open
            }
            return t1.openedAt > t2.openedAt
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Single-line Note Context Banner
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Text(noteTitle.isEmpty ? "Untitled Note" : noteTitle)
                        .font(AppTypography.rowTitle)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.cardBackground)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Search Input (Standard 34pt Capsule)
                AppSearchBar("Search trade by symbol", text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Trades List (Single Line Rows)
                if filteredTrades.isEmpty {
                    AppEmptyState(
                        icon: "magnifyingglass",
                        title: "No matching trades",
                        message: "Try searching with a different symbol, ticket number, or date."
                    )
                } else {
                    List {
                        ForEach(filteredTrades, id: \.key) { trade in
                            let isLinked = trade.key == currentTradeKey
                            tradeRow(trade, isLinked: isLinked)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    linkTrade(trade)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(isLinked ? AppColors.secondaryBackground.opacity(0.4) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Link Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if currentTradeKey != nil {
                        ModalDeleteButton(title: "Unlink") { unlinkTrade() }
                    } else {
                        ModalPrimaryButton("Done") { dismiss() }
                    }
                }
            }
        }
    }
    
    private func tradeRow(_ trade: Trade, isLinked: Bool) -> some View {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        df.timeZone = .current
        
        return HStack(spacing: 8) {
            Text(trade.symbol)
                .font(AppTypography.rowTitle)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Text(trade.direction == .short ? "SELL" : "BUY")
                .font(AppTypography.badgeStandard)
                .foregroundColor(trade.direction == .short ? AppColors.loss : AppColors.profit)
                .lineLimit(1)
            
            Text("Entry \(Formatters.price(trade.avgEntry))")
                .font(AppTypography.statLabel)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            Text(df.string(from: trade.openedAt))
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText.opacity(0.8))
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            Text(Formatters.currency(trade.netPnl))
                .font(AppTypography.statValue)
                .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                .lineLimit(1)
            
            if isLinked {
                Image(systemName: "checkmark")
                    .font(AppTypography.actionButtonCompact)
                    .foregroundColor(AppColors.brand)
            }
        }
        .frame(height: 40)
    }
    
    private func linkTrade(_ trade: Trade) {
        let ticket = trade.executionIds.first ?? trade.id
        try? dataStore.patchNote(id: noteId, tradeKey: .some(trade.key))
        
        let commitments = AIAdvisorMemoryEngine.shared.activeCommitments
        if let matching = commitments.first(where: {
            $0.symbol.uppercased() == trade.symbol.uppercased()
        }) {
            AIAdvisorMemoryEngine.shared.linkCommitment(
                commitmentId: matching.id,
                tradeKey: trade.key,
                orderTicket: ticket
            )
        }
        
        onLinked?(trade, ticket)
        dismiss()
    }
    
    private func unlinkTrade() {
        try? dataStore.patchNote(id: noteId, tradeKey: .some(nil))
        onUnlinked?()
        dismiss()
    }
}
