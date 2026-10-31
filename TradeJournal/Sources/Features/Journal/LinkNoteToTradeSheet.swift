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
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.secondaryText)
                    Text(noteTitle.isEmpty ? "Untitled Note" : noteTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.cardBackground)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Search Input (Standard 36pt)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.system(size: 12))
                    
                    TextField("Search trade by symbol", text: $searchText)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.secondaryText)
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Trades List (Single Line Rows)
                if filteredTrades.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No matching trades")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredTrades, id: \.key) { trade in
                            let isLinked = trade.key == currentTradeKey
                            Button {
                                linkTrade(trade)
                            } label: {
                                tradeRow(trade, isLinked: isLinked)
                            }
                            .buttonStyle(.plain)
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
                
                if currentTradeKey != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalDeleteButton(title: "Unlink") { unlinkTrade() }
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Text(trade.direction == .short ? "SELL" : "BUY")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(trade.direction == .short ? AppColors.loss : AppColors.profit)
                .lineLimit(1)
            
            Text("Entry \(Formatters.price(trade.avgEntry))")
                .font(.system(size: 13))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            Text(df.string(from: trade.openedAt))
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText.opacity(0.8))
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            Text(Formatters.currency(trade.netPnl))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                .lineLimit(1)
            
            if isLinked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
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
