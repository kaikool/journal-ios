import SwiftUI
import UIKit

// MARK: - Full-Screen Chart Lightbox Viewer
// Edge-to-edge full-screen viewer with interactive pinch-to-zoom, pan, and double-tap zoom
public struct FullScreenChartLightboxView: View {
    @Environment(\.dismiss) private var dismiss
    public let image: UIImage
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    public init(image: UIImage) {
        self.image = image
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Full-screen image with pinch & pan gestures
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                let delta = val / lastScale
                                lastScale = val
                                scale = max(1.0, min(scale * delta, 5.0))
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale <= 1.0 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { val in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + val.translation.width,
                                    height: lastOffset.height + val.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if scale > 1.2 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
            }
            .ignoresSafeArea()
            
            // Floating Top Controls
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.brand)
                        Text("Chart Vision")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                // Subtle zoom hint at bottom
                if scale == 1.0 {
                    Text("Pinch or double-tap to zoom")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 16)
                }
            }
        }
        .statusBarHidden(true)
    }
}
