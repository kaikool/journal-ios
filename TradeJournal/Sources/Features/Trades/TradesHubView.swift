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
            Picker("Trades section", selection: $selectedSection) {
                ForEach(TradesTabSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
            
            Divider()
            
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
