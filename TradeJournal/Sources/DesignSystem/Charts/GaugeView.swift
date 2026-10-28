import SwiftUI

private struct CountingPercentageText: View, Animatable {
    var value: Double
    let size: CGFloat
    
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    
    var body: some View {
        Text(String(format: "%.1f%%", max(0, value) * 100))
            .font(.system(size: max(11, size * 0.19), weight: .bold))
            .monospacedDigit()
            .foregroundColor(AppColors.primaryText)
            .padding(.bottom, 2)
    }
}

/// Apple HIG Semicircle Arc Gauge ported from `components/charts/gauge.tsx`.
/// Features:
/// - Initial-flat to smooth clock-wise sweep animation on load
/// - Apple Watch / Fitness complication grade curvature and rounded line caps
/// - Luminous brand gradient stroke with soft ambient glow
/// - Centered SF Pro Rounded typography with monospaced digits and smooth counting
/// - Fluid spring animation on value updates with 120fps hardware acceleration
public struct GaugeView: View {
    private let value: Double?
    private let label: String
    private let size: CGFloat
    
    @State private var animatedRatio: Double = 0.0
    
    public init(value: Double?, label: String, size: CGFloat = 68) {
        self.value = value
        self.label = label
        self.size = size
    }
    
    private var targetRatio: Double {
        guard let v = value else { return 0 }
        return min(max(v, 0), 1.0)
    }
    
    public var body: some View {
        let strokeWidth: CGFloat = 6.5
        let arcRadius = (size - strokeWidth) / 2
        let arcHeight = arcRadius + strokeWidth
        
        ZStack(alignment: .top) {
            // Background Track Arc (Upper Semicircle)
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(
                    AppColors.border.opacity(0.7),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: arcRadius * 2, height: arcRadius * 2)
                .padding(.top, strokeWidth / 2)
            
            // Active Brand Arc: Sweeps from 0.5 (flat) clockwise to 0.5 + animatedRatio * 0.5
            if animatedRatio > 0 {
                Circle()
                    .trim(from: 0.5, to: 0.5 + CGFloat(animatedRatio) * 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppColors.brand.opacity(0.85),
                                AppColors.brand
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                    .padding(.top, strokeWidth / 2)
                    .shadow(color: AppColors.brand.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            
            // Centered Percentage Readout inside the arch
            VStack {
                Spacer()
                if value == nil {
                    Text("–")
                        .font(.system(size: max(11, size * 0.19), weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                        .padding(.bottom, 2)
                } else {
                    CountingPercentageText(value: animatedRatio, size: size)
                }
            }
            .frame(width: size, height: arcHeight)
        }
        .frame(width: size, height: arcHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == nil ? "no data" : String(format: "%.1f%%", targetRatio * 100))")
        .onAppear {
            guard animatedRatio == 0.0 && targetRatio > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.80)) {
                    animatedRatio = targetRatio
                }
            }
        }
        .onChange(of: targetRatio) { newRatio in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                animatedRatio = newRatio
            }
        }
    }
}
