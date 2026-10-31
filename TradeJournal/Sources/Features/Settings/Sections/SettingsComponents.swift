import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared Settings UI Card Wrapper (Apple HIG Inset-Grouped Standard)
public struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content
    
    public init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(AppTypography.cardHeaderUppercase)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.leading, 4)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .appCardStyle(cornerRadius: 12, padding: 14)
            
            if let f = footer, !f.isEmpty {
                Text(f)
                    .font(AppTypography.disclaimer)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Native iOS File Share Sheet
#if canImport(UIKit)
public struct ShareFileSheet: UIViewControllerRepresentable {
    let fileUrl: URL
    
    public init(fileUrl: URL) {
        self.fileUrl = fileUrl
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
public struct ShareFileSheet: View {
    let fileUrl: URL
    
    public init(fileUrl: URL) {
        self.fileUrl = fileUrl
    }
    
    public var body: some View {
        Text("Saved to \(fileUrl.path)")
    }
}
#endif
