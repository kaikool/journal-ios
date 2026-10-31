import SwiftUI

/// Standardized Confirmation Dialog Helper
/// Enforces consistent destructive action verification across trade deletion, database reset, and discarding edits.
public extension View {
    func appConfirmationAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String = "Delete",
        isDestructive: Bool = true,
        onConfirm: @escaping () -> Void
    ) -> some View {
        self.alert(title, isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button(confirmTitle, role: isDestructive ? .destructive : nil) {
                NativeHaptics.mediumImpact()
                onConfirm()
            }
        } message: {
            Text(message)
        }
    }
}
