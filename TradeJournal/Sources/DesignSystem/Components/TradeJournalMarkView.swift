import SwiftUI

/// Trade Journal vector mark matching 100% of SVG vector in `trade-journal-mark.tsx`:
/// Flat journal silhouette with continuous financial chart path through it.
public struct TradeJournalMarkView: View {
    private let size: CGFloat
    private let color: Color
    
    public init(size: CGFloat = 20, color: Color = AppColors.brand) {
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        TradeJournalMarkShape()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Vector path matching 1:1 with SVG path in `source-repo/apps/web/src/components/trade-journal-mark.tsx`:
/// `M5 1h14a4 4 0 0 1 4 4v14a4 4 0 0 1-4 4H5a4 4 0 0 1-4-4V5a4 4 0 0 1 4-4Zm1 2v18h1.5V3H6Zm3.5 11.3 3.5-3.5 2 1.5 3-5 1.7 1-4 6.7-2.6-2-2.3 2.3-1.3-1.3Z`
public struct TradeJournalMarkShape: Shape {
    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        
        var path = Path()
        
        // Journal rounded rect (4pt corner radius)
        path.addRoundedRect(
            in: CGRect(x: 1 * sx, y: 1 * sy, width: 22 * sx, height: 22 * sy),
            cornerSize: CGSize(width: 4 * sx, height: 4 * sy)
        )
        
        // Journal spine
        let spine = Path(CGRect(x: 6 * sx, y: 3 * sy, width: 1.5 * sx, height: 18 * sy))
        
        // Zigzag path icon
        var chart = Path()
        chart.move(to: CGPoint(x: 9.5 * sx, y: 14.3 * sy))
        chart.addLine(to: CGPoint(x: 13.0 * sx, y: 10.8 * sy))
        chart.addLine(to: CGPoint(x: 15.0 * sx, y: 12.3 * sy))
        chart.addLine(to: CGPoint(x: 18.0 * sx, y: 7.3 * sy))
        chart.addLine(to: CGPoint(x: 19.7 * sx, y: 8.3 * sy))
        chart.addLine(to: CGPoint(x: 15.7 * sx, y: 15.0 * sy))
        chart.addLine(to: CGPoint(x: 13.1 * sx, y: 13.0 * sy))
        chart.addLine(to: CGPoint(x: 10.8 * sx, y: 15.3 * sy))
        chart.closeSubpath()
        
        return path
    }
}
