import SwiftUI

/// Standard Shimmer Loading Skeleton
/// Prevents layout shift while market data, trades, or AI reflection results are loading.
public struct AppSkeleton: View {
    public let width: CGFloat?
    public let height: CGFloat
    public let cornerRadius: CGFloat
    
    @State private var phase: CGFloat = -1.0
    
    public init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColors.secondaryBackground.opacity(0.8))
            .frame(height: height)
            .frame(maxWidth: width ?? .infinity)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.12),
                        Color.clear
                    ]),
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.8, y: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
