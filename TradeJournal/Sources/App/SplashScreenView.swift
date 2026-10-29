import SwiftUI

public struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .center) {
            // 1. Full-screen Vector Adaptive Gradient
            splashBackground
                .ignoresSafeArea()
            
            // 2. Center Ambient Radial Glow
            ambientGlow
                .ignoresSafeArea()
            
            // 3. Absolute Mathematical Screen Center: Animated Brand Cluster
            VStack(spacing: 24) {
                // Living Candlestick Icon & Animation
                TradeJournalProLoader(size: 88)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color(hex: "38BDF8").opacity(0.35)
                            : Color(hex: "0284C7").opacity(0.20),
                        radius: 16,
                        x: 0,
                        y: 6
                    )
                
                // Typography & Brand Hierarchy
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Text("TRADE ")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(colorScheme == .dark ? Color(hex: "E2E8F0") : Color(hex: "0F172A"))
                            .tracking(8)
                        
                        Text("JOURNAL")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(hex: "34D399"), Color(hex: "38BDF8")]
                                        : [Color(hex: "059669"), Color(hex: "0284C7")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .tracking(8)
                    }
                    
                    // Accent Divider
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(hex: "34D399"), Color(hex: "38BDF8")]
                                    : [Color(hex: "059669"), Color(hex: "0284C7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 80, height: 2)
                        .opacity(0.55)
                    
                    Text("PRECISION ANALYTICS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(5)
                        .foregroundColor(Color(hex: "64748B"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    
    private var splashBackground: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(hex: "111E32"), Color(hex: "0A111E"), Color(hex: "05080F")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "FFFFFF"), Color(hex: "F0F9FF"), Color(hex: "E0F2FE")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
    
    private var ambientGlow: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color(hex: "38BDF8").opacity(0.16) : Color(hex: "38BDF8").opacity(0.10),
                Color.clear
            ]),
            center: .center,
            startRadius: 20,
            endRadius: 300
        )
    }
}
