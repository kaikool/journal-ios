import SwiftUI

// MARK: - Official Transparent Vector App Logo Mark
/// Official Trade Journal mark for headers, sidebars, and navigation touchpoints.
/// Zero background box, crisp dual symmetrical gradient wings with exact centering.
public struct LogoMarkView: View {
    public var size: CGFloat

    public init(size: CGFloat = 48) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            LeftPlayCandleWing()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.204, green: 0.827, blue: 0.600),
                                 Color(red: 0.008, green: 0.518, blue: 0.780)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RightPlayCandleWing()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.220, green: 0.741, blue: 0.973),
                                 Color(red: 0.063, green: 0.725, blue: 0.506)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trade Journal logo")
        .accessibilityAddTraits(.isImage)
    }
}

/// Standalone brand mark bridge for sidebar and dashboard headers
public struct TradeJournalBrandMark: View {
    private let size: CGFloat
    
    public init(
        size: CGFloat = 28,
        primaryColor: Color = AppColors.brand,
        accentColor: Color = AppColors.profit
    ) {
        self.size = size
    }
    
    public var body: some View {
        LogoMarkView(size: size)
    }
}

/// Standalone vector mark bridge for shell header navigation trigger
public struct TradeJournalMarkView: View {
    private let size: CGFloat
    
    public init(size: CGFloat = 24, color: Color? = nil) {
        self.size = size
    }
    
    public var body: some View {
        LogoMarkView(size: size)
    }
}
