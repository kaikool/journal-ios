import SwiftUI

/// Standard Modal Sheet Container matching Apple HIG
/// Wraps modal sheet content with unified navigation bar, inline title, and ModalCloseButton.
public struct AppSheetContainer<Content: View>: View {
    public let title: String
    public let onClose: () -> Void
    public let content: Content
    
    public init(_ title: String, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }
    
    public var body: some View {
        NavigationStack {
            content
                .background(AppColors.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton(action: onClose)
                    }
                }
        }
    }
}
