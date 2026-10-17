import SwiftUI

/// Apple HIG Semicircle Arc Gauge ported from `components/charts/gauge.tsx`.
/// Features:
/// - Apple Watch / Fitness complication grade curvature and rounded line caps
/// - Luminous brand gradient stroke with soft ambient glow
/// - Centered SF Pro Rounded typography with monospaced digits
/// - Fluid spring animation on value updates
public struct GaugeView: View {
    private let value: Double?
    private let label: String
    private let size: CGFloat
    
    public init(value: Double?, label: String, size: CGFloat = 96) {
        self.value = value
        self.label = label
        self.size = size
    }
    
    private var ratio: Double {
        guard let v = value else { return 0 }
        return min(max(v, 0), 1.0)
    }
    
    public var body: some View {
        let strokeWidth: CGFloat = 8
        let radius = (size / 2) - strokeWidth
        let arcHeight = radius + (strokeWidth / 2) + 4
        
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background Track Arc
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(
                        AppColors.border.opacity(0.6),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: radius * 2, height: radius * 2)
                
                // Active Brand Arc
                if ratio > 0 {
                    Circle()
                        .trim(from: 0.5, to: 0.5 + CGFloat(ratio) * 0.5)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppColors.brand.opacity(0.8),
                                    AppColors.brand
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius * 2)
                        .shadow(color: AppColors.brand.opacity(0.3), radius: 3, x: 0, y: 1)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: ratio)
                }
                
                // Centered Percentage Readout
                Text(value == nil ? "–" : String(format: "%.1f%%", ratio * 100))
                    .font(.system(size: max(12, size * 0.18), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                    .offset(y: radius - 10)
            }
            .frame(width: size, height: arcHeight)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == nil ? "no data" : String(format: "%.1f%%", ratio * 100))")
    }
}
