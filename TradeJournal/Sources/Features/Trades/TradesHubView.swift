import SwiftUI

public enum TradesTabSection: String, CaseIterable, Identifiable {
    case trades = "Lệnh Thực Tế"
    case missed = "Kèo Bị Lỡ"
    case replay = "Replay Biểu Đồ"
    
    public var id: String { rawValue }
}

/// Màn hình điều phối toàn bộ nghiệp vụ Giao Dịch
/// Bao gồm Lệnh Thực Tế (/trades), Kèo Bị Lỡ (/missed), và Replay Biểu Đồ
public struct TradesHubView: View {
    @State private var selectedSection: TradesTabSection = .trades
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            Picker("Phân mục giao dịch", selection: $selectedSection) {
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
