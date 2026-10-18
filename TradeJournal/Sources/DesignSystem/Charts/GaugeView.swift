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
    
    public init(value: Double?, label: String, size: CGFloat = 68) {
        self.value = value
        self.label = label
        self.size = size
    }
    
    private var ratio: Double {
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
            
            // Active Brand Arc
            if ratio > 0 {
                Circle()
                    .trim(from: 0.5, to: 0.5 + CGFloat(ratio) * 0.5)
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
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: ratio)
            }
            
            // Centered Percentage Readout inside the arch
            VStack {
                Spacer()
                Text(value == nil ? "–" : String(format: "%.1f%%", ratio * 100))
                    .font(.system(size: max(11, size * 0.19), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                    .padding(.bottom, 2)
            }
            .frame(width: size, height: arcHeight)
        }
        .frame(width: size, height: arcHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == nil ? "no data" : String(format: "%.1f%%", ratio * 100))")
    }
}
