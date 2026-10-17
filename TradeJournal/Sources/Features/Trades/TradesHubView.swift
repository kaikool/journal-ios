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
    @Namespace private var sectionNamespace
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG Sliding Pill Segmented Bar
            HStack(spacing: 4) {
                ForEach(TradesTabSection.allCases) { section in
                    let isSelected = selectedSection == section
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if section == .trades {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 11))
                            } else if section == .missed {
                                Image(systemName: "bookmark.slash")
                                    .font(.system(size: 11))
                            } else {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 11))
                            }
                            
                            Text(section.rawValue)
                                .font(AppTypography.captionBold)
                        }
                        .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppColors.cardBackground)
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
                                    .matchedGeometryEffect(id: "TradesHubPill", in: sectionNamespace)
                            }
                        }
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(4)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
