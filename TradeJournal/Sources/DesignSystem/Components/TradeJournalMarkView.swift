import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
        Group {
            #if canImport(UIKit)
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                TradeJournalMarkShape()
                    .fill(color, style: FillStyle(eoFill: true))
                    .frame(width: size, height: size)
            }
            #else
            TradeJournalMarkShape()
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
            #endif
        }
    }
}

/// Vector path matching 1:1 with SVG path in `source-repo/apps/web/src/components/trade-journal-mark.tsx`:
/// `M5 1h14a4 4 0 0 1 4 4v14a4 4 0 0 1-4 4H5a4 4 0 0 1-4-4V5a4 4 0 0 1 4-4Zm1 2v18h1.5V3H6Zm3.5 11.3 3.5-3.5 2 1.5 3-5 1.7 1-4 6.7-2.6-2-2.3 2.3-1.3-1.3Z`
public struct TradeJournalMarkShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        
        var path = Path()
        
        // 1. Journal outer body: M5 1h14a4 4 0 0 1 4 4v14a4 4 0 0 1-4 4H5a4 4 0 0 1-4-4V5a4 4 0 0 1 4-4Z
        path.move(to: CGPoint(x: 5 * sx, y: 1 * sy))
        path.addLine(to: CGPoint(x: 19 * sx, y: 1 * sy))
        path.addArc(center: CGPoint(x: 19 * sx, y: 5 * sy), radius: 4 * sx, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: 23 * sx, y: 19 * sy))
        path.addArc(center: CGPoint(x: 19 * sx, y: 19 * sy), radius: 4 * sx, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: 5 * sx, y: 23 * sy))
        path.addArc(center: CGPoint(x: 5 * sx, y: 19 * sy), radius: 4 * sx, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 1 * sx, y: 5 * sy))
        path.addArc(center: CGPoint(x: 5 * sx, y: 5 * sy), radius: 4 * sx, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        
        // 2. Spine groove cutout: M6 3h1.5v18H6Z
        path.move(to: CGPoint(x: 6 * sx, y: 3 * sy))
        path.addLine(to: CGPoint(x: 7.5 * sx, y: 3 * sy))
        path.addLine(to: CGPoint(x: 7.5 * sx, y: 21 * sy))
        path.addLine(to: CGPoint(x: 6 * sx, y: 21 * sy))
        path.closeSubpath()
        
        // 3. Zigzag chart cutout: M9.5 14.3l3.5-3.5 2 1.5 3-5 1.7 1-4 6.7-2.6-2-2.3 2.3-1.3-1.3Z
        path.move(to: CGPoint(x: 9.5 * sx, y: 14.3 * sy))
        path.addLine(to: CGPoint(x: 13.0 * sx, y: 10.8 * sy))
        path.addLine(to: CGPoint(x: 15.0 * sx, y: 12.3 * sy))
        path.addLine(to: CGPoint(x: 18.0 * sx, y: 7.3 * sy))
        path.addLine(to: CGPoint(x: 19.7 * sx, y: 8.3 * sy))
        path.addLine(to: CGPoint(x: 15.7 * sx, y: 15.0 * sy))
        path.addLine(to: CGPoint(x: 13.1 * sx, y: 13.0 * sy))
        path.addLine(to: CGPoint(x: 10.8 * sx, y: 15.3 * sy))
        path.closeSubpath()
        
        return path
    }
}
