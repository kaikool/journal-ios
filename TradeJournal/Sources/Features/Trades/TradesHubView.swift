import SwiftUI

public enum TradesTabSection: String, CaseIterable, Identifiable {
    case trades = "Trades"
    case missed = "Missed trades"
    case replay = "Trade replay"
    
    public var id: String { rawValue }
}

/// Navigation coordinator for trades modules:
/// Trades (/trades), Missed trades (/missed), and Trade replay
public struct TradesHubView: View {
    @State private var selectedSection: TradesTabSection = .trades
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG iOS 27 Sliding Segmented Bar
            AppleSlidingSegmentedBar(
                selection: $selectedSection,
                items: TradesTabSection.allCases,
                titleFor: { $0.rawValue },
                iconFor: { section in
                    switch section {
                    case .trades: return "list.bullet.rectangle"
                    case .missed: return "bookmark.slash"
                    case .replay: return "play.circle"
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
            
            Divider().background(AppColors.border.opacity(0.5))
            
            switch selectedSection {
            case .trades:
                TradesListView()
            case .missed:
                MissedTradesView()
            case .replay:
                TradeReplayHubView()
            }
        }
        .background(AppColors.background)
    }
}
