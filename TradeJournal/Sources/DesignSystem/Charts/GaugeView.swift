import SwiftUI

/// Semicircle Gauge ported 1:1 from `components/charts/gauge.tsx`:
/// Semicircle gauge measuring 0–1 ratios (Trade win %, Day win %).
/// Always renders % value in center with visual arc.
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
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Background track
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(
                        AppColors.border,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .frame(width: size - 14, height: size - 14)
                
                // Active Brand Progress
                if ratio > 0 {
                    Circle()
                        .trim(from: 0.5, to: 0.5 + (0.5 * CGFloat(ratio)))
                        .stroke(
                            AppColors.brand,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: size - 14, height: size - 14)
                }
                
                // Percentage Text
                VStack(spacing: 0) {
                    Text(value == nil ? "–" : String(format: "%.1f%%", ratio * 100))
                        .font(AppTypography.financialNumber(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                }
                .offset(y: 4)
            }
            .frame(width: size, height: size / 2 + 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == nil ? "no data" : String(format: "%.1f%%", ratio * 100))")
    }
}
