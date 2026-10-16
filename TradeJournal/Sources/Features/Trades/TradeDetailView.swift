import SwiftUI

public struct TradeDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State var trade: Trade
    @State private var showReplayView: Bool = false
    @State private var newTag: String = ""
    @State private var newMistake: String = ""
    
    public init(trade: Trade) {
        self._trade = State(initialValue: trade)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header PnL Card
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(trade.symbol)
                                .font(AppTypography.headline)
                            AppBadge(
                                text: trade.direction.rawValue.uppercased(),
                                color: trade.direction == .long ? AppColors.profit : AppColors.loss
                            )
                            AppBadge(
                                text: trade.status.rawValue.uppercased(),
                                color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                            )
                            Spacer()
                            Button(action: { showReplayView = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                    Text("Replay")
                                }
                                .font(AppTypography.captionBold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.accent.opacity(0.15))
                                .foregroundColor(AppColors.accent)
                                .cornerRadius(12)
                            }
                        }
                        
                        Divider().background(AppColors.border)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lãi/Lỗ Ròng")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                    .foregroundColor(Formatters.pnlColor(trade.netPnl))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Khối lượng")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(trade.quantity)")
                                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                }
                
                // Pricing & Execution Details
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Thông số vào / ra lệnh")
                            .font(AppTypography.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Giá vào TB")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(trade.avgEntry)")
                                    .font(AppTypography.subheadlineBold)
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("Giá ra TB")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(trade.avgExit != nil ? "\(trade.avgExit!)" : "Đang mở")
                                    .font(AppTypography.subheadlineBold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Phí GD")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))
                                    .font(AppTypography.subheadlineBold)
                            }
                        }
                        
                        Divider().background(AppColors.border.opacity(0.5))
                        
                        HStack {
                            Text("Thời gian mở:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(Formatters.formatDateTime(trade.openedAt, timeZone: env.currentTimeZone))
                                .font(AppTypography.caption)
                        }
                        
                        if let closedAt = trade.closedAt {
                            HStack {
                                Text("Thời gian đóng:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text(Formatters.formatDateTime(closedAt, timeZone: env.currentTimeZone))
                                    .font(AppTypography.caption)
                            }
                        }
                    }
                }
                
                // Annotations: Mistakes & Tags
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ghi chú & Đánh giá sai lầm")
                            .font(AppTypography.headline)
                        
                        // Rating
                        HStack {
                            Text("Đánh giá lệnh:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= (trade.rating ?? 0) ? "star.fill" : "star")
                                    .foregroundColor(star <= (trade.rating ?? 0) ? .yellow : AppColors.secondaryText)
                                    .onTapGesture {
                                        trade.rating = star
                                        persistTradeUpdates()
                                    }
                            }
                        }
                        
                        // Tags
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(trade.tags, id: \.self) { tag in
                                        AppBadge(text: "#\(tag)", color: AppColors.accent)
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("Thêm tag...", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                Button("Thêm") {
                                    let clean = newTag.trimmingCharacters(in: .whitespaces)
                                    if !clean.isEmpty && !trade.tags.contains(clean) {
                                        trade.tags.append(clean)
                                        newTag = ""
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                        
                        // Mistakes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sai lầm vi phạm:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(trade.mistakes, id: \.self) { mistake in
                                        AppBadge(text: "⚠️ \(mistake)", color: AppColors.loss)
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("VD: FOMO, Dời SL...", text: $newMistake)
                                    .textFieldStyle(.roundedBorder)
                                Button("Thêm") {
                                    let clean = newMistake.trimmingCharacters(in: .whitespaces)
                                    if !clean.isEmpty && !trade.mistakes.contains(clean) {
                                        trade.mistakes.append(clean)
                                        newMistake = ""
                                        persistTradeUpdates()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(trade.symbol)
        .background(AppColors.background)
        .navigationDestination(isPresented: $showReplayView) {
            let fills = dataStore.executions.filter { trade.executionIds.contains($0.id) }
            TradeReplayView(trade: trade, executions: fills)
        }
    }
    
    private func persistTradeUpdates() {
        if let idx = dataStore.trades.firstIndex(where: { $0.key == trade.key }) {
            dataStore.trades[idx] = trade
        }
    }
}
