import SwiftUI

// MARK: - TradeJournal Professional Animated Candlestick Loader
// Exact mathematical coordinates and fluid physics:
// 1. Shockwave radar sonar expansion
// 2. Breathing central candlestick wick & body
// 3. Dynamic left/right play wings with sheen sweep overlay
public struct TradeJournalProLoader: View {
    public var size: CGFloat

    public init(size: CGFloat = 64) {
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = 2.2
            let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
            let s = size / 512.0

            let openAmount = sin(phase * .pi)
            let shearY = sin(phase * 2 * .pi) * 16 * s
            let spreadX = openAmount * 18 * s
            let candleScaleY = max(0.05, sin(phase * .pi) * 1.05)
            let sonarProgress = phase > 0.72 ? (phase - 0.72) / 0.28 : 0.0

            ZStack {
                // 1. VÒNG SÓNG XUNG KÍCH (Shockwave Ring)
                if sonarProgress > 0 {
                    RoundedRectangle(cornerRadius: 28 * s)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "34D399"), Color(hex: "38BDF8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: (1.0 - sonarProgress) * 7 * s
                        )
                        .frame(width: 220 * s, height: 220 * s)
                        .rotationEffect(.degrees(45))
                        .scaleEffect(0.75 + sonarProgress * 0.65)
                        .opacity(1.0 - sonarProgress)
                }

                // 2. CÂY NẾN SỐNG Ở CHÍNH GIỮA TÂM (Central Living Candlestick)
                ZStack {
                    Capsule()
                        .fill(Color(hex: "7DD3FC"))
                        .frame(width: 6 * s, height: 270 * s * candleScaleY)
                        .opacity(Double(openAmount))

                    RoundedRectangle(cornerRadius: 10 * s)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A7F3D0"), Color(hex: "38BDF8"), Color(hex: "34D399")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 42 * s, height: 156 * s * candleScaleY)
                        .opacity(Double(openAmount))
                }
                .shadow(color: Color(hex: "34D399").opacity(0.7), radius: 8 * s)

                // 3. HAI KHỐI NÚT PLAY ĐỐI XỨNG TUYỆT ĐỐI (Dual Symmetrical Play Wings)
                ZStack {
                    LeftPlayCandleWing()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "34D399"), Color(hex: "0284C7")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: -spreadX, y: -shearY)

                    RightPlayCandleWing()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "38BDF8"), Color(hex: "10B981")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: spreadX, y: shearY)
                }
                .frame(width: size, height: size)
                .overlay {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.45), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 85 * s, height: size * 1.4)
                        .rotationEffect(.degrees(25))
                        .offset(x: CGFloat(phase * 2.0 - 1.0) * size)
                        .blendMode(.plusLighter)
                }
                .mask {
                    ZStack {
                        LeftPlayCandleWing()
                            .offset(x: -spreadX, y: -shearY)
                        RightPlayCandleWing()
                            .offset(x: spreadX, y: shearY)
                    }
                    .frame(width: size, height: size)
                }
                .shadow(color: Color(hex: "38BDF8").opacity(0.4), radius: 12 * s)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Cánh Trái chuẩn tọa độ tuyệt đối (Left Wing Shape)
public struct LeftPlayCandleWing: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 512.0
        let ox = rect.minX + (rect.width - 512.0 * s) / 2.0
        let oy = rect.minY + (rect.height - 512.0 * s) / 2.0
        var p = Path()
        p.move(to: CGPoint(x: ox + 238 * s, y: oy + 118 * s))
        p.addCurve(to: CGPoint(x: ox + 246 * s, y: oy + 126 * s), control1: CGPoint(x: ox + 243 * s, y: oy + 118 * s), control2: CGPoint(x: ox + 246 * s, y: oy + 121 * s))
        p.addLine(to: CGPoint(x: ox + 246 * s, y: oy + 168 * s))
        p.addLine(to: CGPoint(x: ox + 232 * s, y: oy + 168 * s))
        p.addCurve(to: CGPoint(x: ox + 216 * s, y: oy + 184 * s), control1: CGPoint(x: ox + 223 * s, y: oy + 168 * s), control2: CGPoint(x: ox + 216 * s, y: oy + 175 * s))
        p.addLine(to: CGPoint(x: ox + 216 * s, y: oy + 328 * s))
        p.addCurve(to: CGPoint(x: ox + 232 * s, y: oy + 344 * s), control1: CGPoint(x: ox + 216 * s, y: oy + 337 * s), control2: CGPoint(x: ox + 223 * s, y: oy + 344 * s))
        p.addLine(to: CGPoint(x: ox + 246 * s, y: oy + 344 * s))
        p.addLine(to: CGPoint(x: ox + 246 * s, y: oy + 386 * s))
        p.addCurve(to: CGPoint(x: ox + 238 * s, y: oy + 394 * s), control1: CGPoint(x: ox + 246 * s, y: oy + 391 * s), control2: CGPoint(x: ox + 243 * s, y: oy + 394 * s))
        p.addCurve(to: CGPoint(x: ox + 229 * s, y: oy + 390 * s), control1: CGPoint(x: ox + 235 * s, y: oy + 394 * s), control2: CGPoint(x: ox + 232 * s, y: oy + 393 * s))
        p.addLine(to: CGPoint(x: ox + 114 * s, y: oy + 275 * s))
        p.addCurve(to: CGPoint(x: ox + 114 * s, y: oy + 237 * s), control1: CGPoint(x: ox + 103 * s, y: oy + 264 * s), control2: CGPoint(x: ox + 103 * s, y: oy + 248 * s))
        p.addLine(to: CGPoint(x: ox + 229 * s, y: oy + 122 * s))
        p.addCurve(to: CGPoint(x: ox + 238 * s, y: oy + 118 * s), control1: CGPoint(x: ox + 232 * s, y: oy + 119 * s), control2: CGPoint(x: ox + 235 * s, y: oy + 118 * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cánh Phải chuẩn tọa độ tuyệt đối (Right Wing Shape)
public struct RightPlayCandleWing: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 512.0
        let ox = rect.minX + (rect.width - 512.0 * s) / 2.0
        let oy = rect.minY + (rect.height - 512.0 * s) / 2.0
        var p = Path()
        p.move(to: CGPoint(x: ox + 274 * s, y: oy + 118 * s))
        p.addCurve(to: CGPoint(x: ox + 266 * s, y: oy + 126 * s), control1: CGPoint(x: ox + 269 * s, y: oy + 118 * s), control2: CGPoint(x: ox + 266 * s, y: oy + 121 * s))
        p.addLine(to: CGPoint(x: ox + 266 * s, y: oy + 168 * s))
        p.addLine(to: CGPoint(x: ox + 280 * s, y: oy + 168 * s))
        p.addCurve(to: CGPoint(x: ox + 296 * s, y: oy + 184 * s), control1: CGPoint(x: ox + 289 * s, y: oy + 168 * s), control2: CGPoint(x: ox + 296 * s, y: oy + 175 * s))
        p.addLine(to: CGPoint(x: ox + 296 * s, y: oy + 328 * s))
        p.addCurve(to: CGPoint(x: ox + 280 * s, y: oy + 344 * s), control1: CGPoint(x: ox + 296 * s, y: oy + 337 * s), control2: CGPoint(x: ox + 289 * s, y: oy + 344 * s))
        p.addLine(to: CGPoint(x: ox + 266 * s, y: oy + 344 * s))
        p.addLine(to: CGPoint(x: ox + 266 * s, y: oy + 386 * s))
        p.addCurve(to: CGPoint(x: ox + 274 * s, y: oy + 394 * s), control1: CGPoint(x: ox + 266 * s, y: oy + 391 * s), control2: CGPoint(x: ox + 269 * s, y: oy + 394 * s))
        p.addCurve(to: CGPoint(x: ox + 283 * s, y: oy + 390 * s), control1: CGPoint(x: ox + 277 * s, y: oy + 394 * s), control2: CGPoint(x: ox + 280 * s, y: oy + 393 * s))
        p.addLine(to: CGPoint(x: ox + 398 * s, y: oy + 275 * s))
        p.addCurve(to: CGPoint(x: ox + 398 * s, y: oy + 237 * s), control1: CGPoint(x: ox + 409 * s, y: oy + 264 * s), control2: CGPoint(x: ox + 409 * s, y: oy + 248 * s))
        p.addLine(to: CGPoint(x: ox + 283 * s, y: oy + 122 * s))
        p.addCurve(to: CGPoint(x: ox + 274 * s, y: oy + 118 * s), control1: CGPoint(x: ox + 280 * s, y: oy + 119 * s), control2: CGPoint(x: ox + 277 * s, y: oy + 118 * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Reusable Blur Overlay Loading Modifier
// Displays TradeJournalProLoader centered with adaptive light/dark blur and NO unnecessary text
public struct TradeJournalLoadingOverlay: View {
    public let size: CGFloat
    
    public init(message: String? = nil, size: CGFloat = 64) {
        self.size = size
    }
    
    public var body: some View {
        ZStack(alignment: .center) {
            // Adaptive system blur responding to light/dark mode seamlessly
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Clean centered animated loader, no distracting text
            TradeJournalProLoader(size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

public struct TradeJournalLoadingModifier: ViewModifier {
    public let isLoading: Bool
    public let message: String?
    public let size: CGFloat
    
    public init(isLoading: Bool, message: String?, size: CGFloat = 64) {
        self.isLoading = isLoading
        self.message = message
        self.size = size
    }
    
    public func body(content: Content) -> some View {
        ZStack(alignment: .center) {
            content
                .blur(radius: isLoading ? 8 : 0)
                .disabled(isLoading)
                .animation(.easeInOut(duration: 0.28), value: isLoading)
            
            if isLoading {
                TradeJournalLoadingOverlay(message: message, size: size)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isLoading)
    }
}

public extension View {
    /// Overlays the professional TradeJournal candlestick loading animation and blurs the underlying content
    func tradeJournalLoading(
        _ isLoading: Bool,
        message: String? = nil,
        size: CGFloat = 64
    ) -> some View {
        modifier(TradeJournalLoadingModifier(isLoading: isLoading, message: message, size: size))
    }
}
