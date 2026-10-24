import SwiftUI

public struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "#05080F") : Color(hex: "#FFFFFF"))
                .ignoresSafeArea()
            
            #if canImport(UIKit)
            if UIImage(named: "SplashImage") != nil {
                Image("SplashImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                fallbackSplashContent
            }
            #else
            fallbackSplashContent
            #endif
        }
    }
    
    private var fallbackSplashContent: some View {
        VStack(spacing: 20) {
            #if canImport(UIKit)
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 84, height: 84)
            } else {
                defaultIcon
            }
            #else
            defaultIcon
            #endif
            
            VStack(spacing: 6) {
                Text("TRADE JOURNAL")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .tracking(6)
                
                Text("PRECISION ANALYTICS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }
    
    private var defaultIcon: some View {
        Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.brand, Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
