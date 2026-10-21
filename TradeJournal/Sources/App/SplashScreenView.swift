import SwiftUI

public struct SplashScreenView: View {
    @State private var isAnimating: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Branded App Logo or Terminal Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.brand.opacity(0.22),
                                    AppColors.brand.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(AppColors.brand.opacity(0.4), lineWidth: 1.2)
                        )
                        .shadow(color: AppColors.brand.opacity(isAnimating ? 0.45 : 0.20), radius: isAnimating ? 28 : 14, x: 0, y: 8)
                        .scaleEffect(isAnimating ? 1.02 : 0.98)
                    
                    #if canImport(UIKit)
                    if UIImage(named: "AppLogo") != nil {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 58, height: 58)
                    } else {
                        defaultLogoContent
                    }
                    #else
                    defaultLogoContent
                    #endif
                }
                
                VStack(spacing: 6) {
                    Text("Trade Journal")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("PROFESSIONAL EXECUTION TERMINAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                // Subtle glowing loading dots
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(AppColors.brand)
                            .frame(width: 6, height: 6)
                            .opacity(isAnimating ? 1.0 : 0.3)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var defaultLogoContent: some View {
        Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.brand, Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
