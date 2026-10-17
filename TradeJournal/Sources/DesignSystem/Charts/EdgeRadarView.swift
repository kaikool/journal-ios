import SwiftUI

/// 6-Axis Edge Score Radar Chart ported from `components/charts/edge-radar.tsx`.
/// Built to Apple HIG standards:
/// - Concentric geometric guide polygons with quiet gridline styling
/// - Luminous brand-filled area with glowing stroke
/// - Precision vertex nodes featuring multi-layer glowing beads
/// - Floating typographic label capsules with monospaced score badges
public struct EdgeRadarView: View {
    private let components: EdgeScoreComponents
    private let height: CGFloat
    
    private struct RadarMetric {
        let label: String
        let value: Double
    }
    
    public init(components: EdgeScoreComponents, height: CGFloat = 220) {
        self.components = components
        self.height = height
    }
    
    private var metrics: [RadarMetric] {
        [
            RadarMetric(label: "Win %", value: components.winRate),
            RadarMetric(label: "Profit factor", value: components.profitFactor),
            RadarMetric(label: "Avg win/loss", value: components.avgWinLoss),
            RadarMetric(label: "Drawdown", value: components.drawdown),
            RadarMetric(label: "Recovery", value: components.recovery),
            RadarMetric(label: "Consistency", value: components.consistency)
        ]
    }
    
    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let actualHeight = geo.size.height
            let center = CGPoint(x: width / 2, y: actualHeight / 2)
            let radius = max(24, min(width / 2 - 56, actualHeight / 2 - 32))
            
            ZStack {
                // Background concentric grid rings (25%, 50%, 75%, 100%)
                ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { fraction in
                    polygonPath(center: center, radius: radius * fraction, sides: 6)
                        .stroke(AppColors.border.opacity(fraction == 1.0 ? 0.6 : 0.3), lineWidth: 0.8)
                }
                
                // Radial spoke lines from center to outer vertices
                Path { path in
                    for i in 0..<6 {
                        let angle = angleForIndex(i)
                        let endPoint = CGPoint(
                            x: center.x + radius * CGFloat(cos(angle)),
                            y: center.y + radius * CGFloat(sin(angle))
                        )
                        path.move(to: center)
                        path.addLine(to: endPoint)
                    }
                }
                .stroke(AppColors.border.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                
                // Data polygon fill
                radarDataPath(center: center, radius: radius)
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.brand.opacity(0.4),
                                AppColors.brand.opacity(0.18)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                
                // Data polygon stroke with subtle shadow
                radarDataPath(center: center, radius: radius)
                    .stroke(AppColors.brand, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: AppColors.brand.opacity(0.35), radius: 4, x: 0, y: 1)
                
                // Vertex Nodes (Apple-style 3-layer glowing beads)
                ForEach(0..<metrics.count, id: \.self) { i in
                    let m = metrics[i]
                    let angle = angleForIndex(i)
                    let normalizedVal = max(0.0, min(100.0, m.value)) / 100.0
                    let pt = CGPoint(
                        x: center.x + radius * CGFloat(normalizedVal * cos(angle)),
                        y: center.y + radius * CGFloat(normalizedVal * sin(angle))
                    )
                    
                    ZStack {
                        Circle()
                            .fill(AppColors.brand.opacity(0.25))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(AppColors.brand)
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 2, height: 2)
                    }
                    .position(pt)
                }
                
                // Axis Label Capsules
                ForEach(0..<metrics.count, id: \.self) { i in
                    let m = metrics[i]
                    let angle = angleForIndex(i)
                    let labelRadius = radius + 22
                    let pt = CGPoint(
                        x: center.x + labelRadius * CGFloat(cos(angle)),
                        y: center.y + labelRadius * CGFloat(sin(angle))
                    )
                    
                    HStack(spacing: 3) {
                        Text(m.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(Int(round(m.value)))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppColors.cardBackground.opacity(0.92))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                    .position(pt)
                }
            }
        }
        .frame(height: height)
    }
    
    // MARK: - Geometry Helpers
    
    private func angleForIndex(_ index: Int) -> Double {
        return -Double.pi / 2.0 + Double(index) * (2.0 * Double.pi / 6.0)
    }
    
    private func polygonPath(center: CGPoint, radius: CGFloat, sides: Int) -> Path {
        var path = Path()
        guard sides > 2 else { return path }
        
        for i in 0..<sides {
            let angle = -Double.pi / 2.0 + Double(i) * (2.0 * Double.pi / Double(sides))
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
    
    private func radarDataPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        guard !metrics.isEmpty else { return path }
        
        for i in 0..<metrics.count {
            let m = metrics[i]
            let angle = angleForIndex(i)
            let normalizedVal = max(0.0, min(100.0, m.value)) / 100.0
            let point = CGPoint(
                x: center.x + radius * CGFloat(normalizedVal * cos(angle)),
                y: center.y + radius * CGFloat(normalizedVal * sin(angle))
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
