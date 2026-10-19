import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Redesigned modern Apple HIG trading journal brand mark:
/// Crisp, dynamic financial emblem featuring ascending candlestick bars with a breakout trendline spline and glowing apex.
/// Standalone vector mark without artificial bounding boxes or double background wrappers.
public struct TradeJournalBrandMark: View {
    private let size: CGFloat
    private let primaryColor: Color
    private let accentColor: Color
    
    public init(
        size: CGFloat = 24,
        primaryColor: Color = AppColors.brand,
        accentColor: Color = AppColors.profit
    ) {
        self.size = size
        self.primaryColor = primaryColor
        self.accentColor = accentColor
    }
    
    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            
            // 1. Candlestick wicks & bodies (3 ascending financial bars)
            let colWidth = w * 0.18
            let colCorner = colWidth * 0.35
            
            // Candle 1 (left)
            let c1Wick = Path(CGRect(x: w * 0.16, y: h * 0.44, width: w * 0.035, height: h * 0.48))
            context.fill(c1Wick, with: .color(primaryColor.opacity(0.35)))
            let c1Body = Path(roundedRect: CGRect(x: w * 0.088, y: h * 0.50, width: colWidth, height: h * 0.36), cornerRadius: colCorner)
            context.fill(c1Body, with: .color(primaryColor.opacity(0.65)))
            
            // Candle 2 (middle)
            let c2Wick = Path(CGRect(x: w * 0.46, y: h * 0.24, width: w * 0.035, height: h * 0.64))
            context.fill(c2Wick, with: .color(primaryColor.opacity(0.45)))
            let c2Body = Path(roundedRect: CGRect(x: w * 0.388, y: h * 0.30, width: colWidth, height: h * 0.50), cornerRadius: colCorner)
            context.fill(c2Body, with: .color(primaryColor.opacity(0.85)))
            
            // Candle 3 (right / peak)
            let c3Wick = Path(CGRect(x: w * 0.76, y: h * 0.08, width: w * 0.035, height: h * 0.74))
            context.fill(c3Wick, with: .color(accentColor.opacity(0.55)))
            let c3Body = Path(roundedRect: CGRect(x: w * 0.688, y: h * 0.14, width: colWidth, height: h * 0.60), cornerRadius: colCorner)
            context.fill(
                c3Body,
                with: .linearGradient(
                    Gradient(colors: [primaryColor, accentColor]),
                    startPoint: CGPoint(x: w * 0.688, y: h * 0.74),
                    endPoint: CGPoint(x: w * 0.868, y: h * 0.14)
                )
            )
            
            // 2. Dynamic breakout trendline curve
            var curve = Path()
            curve.move(to: CGPoint(x: w * 0.06, y: h * 0.78))
            curve.addCurve(
                to: CGPoint(x: w * 0.88, y: h * 0.18),
                control1: CGPoint(x: w * 0.32, y: h * 0.72),
                control2: CGPoint(x: w * 0.56, y: h * 0.34)
            )
            
            context.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [primaryColor.opacity(0.6), primaryColor, accentColor]),
                    startPoint: CGPoint(x: 0, y: h * 0.8),
                    endPoint: CGPoint(x: w, y: h * 0.1)
                ),
                style: StrokeStyle(lineWidth: max(1.8, w * 0.09), lineCap: .round, lineJoin: .round)
            )
            
            // 3. Glowing Apex Node
            let dotSize = w * 0.15
            let dotRect = CGRect(x: w * 0.81, y: h * 0.11, width: dotSize, height: dotSize)
            // Halo glow
            context.fill(
                Path(ellipseIn: dotRect.insetBy(dx: -w * 0.03, dy: -w * 0.03)),
                with: .color(accentColor.opacity(0.35))
            )
            // Crisp core point
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trade Journal logo")
        .accessibilityAddTraits(.isImage)
    }
}

/// Standalone vector mark for headers, sidebars, and branded touchpoints.
public struct TradeJournalMarkView: View {
    private let size: CGFloat
    private let color: Color
    
    public init(size: CGFloat = 20, color: Color = AppColors.brand) {
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        TradeJournalBrandMark(size: size, primaryColor: color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trade Journal icon")
            .accessibilityAddTraits(.isImage)
    }
}
