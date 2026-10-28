import SwiftUI
import UIKit

// MARK: - Full-Screen Chart Lightbox Viewer
// Minimalist, high-contrast modal preview for TradingView and Replay chart images
public struct FullScreenChartLightboxView: View {
    @Environment(\.dismiss) private var dismiss
    public let image: UIImage
    
    public init(image: UIImage) {
        self.image = image
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
            .navigationTitle("Chart Vision Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(.white)
                }
            }
        }
    }
}
