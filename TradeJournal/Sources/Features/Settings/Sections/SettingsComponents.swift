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
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.leading, 4)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
            )
            
            if let f = footer, !f.isEmpty {
                Text(f)
                    .font(.system(size: 11, weight: .regular))
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
