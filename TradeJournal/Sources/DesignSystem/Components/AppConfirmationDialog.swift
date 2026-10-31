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
    
    func appConfirmationAlert<T>(
        isPresented: Binding<Bool>,
        presenting: T?,
        title: @escaping (T) -> String,
        message: @escaping (T) -> String,
        confirmTitle: String = "Delete",
        isDestructive: Bool = true,
        onConfirm: @escaping (T) -> Void
    ) -> some View {
        self.alert(
            presenting != nil ? title(presenting!) : "",
            isPresented: isPresented,
            presenting: presenting
        ) { item in
            Button("Cancel", role: .cancel) {}
            Button(confirmTitle, role: isDestructive ? .destructive : nil) {
                NativeHaptics.mediumImpact()
                onConfirm(item)
            }
        } message: { item in
            Text(message(item))
        }
    }
    
    func appInfoAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String
    ) -> some View {
        self.alert(title, isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
    
    func appPromptAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        placeholder: String,
        text: Binding<String>,
        confirmTitle: String = "Confirm",
        isDestructive: Bool = false,
        onCancel: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        self.alert(title, isPresented: isPresented) {
            TextField(placeholder, text: text)
            Button("Cancel", role: .cancel) { onCancel?() }
            Button(confirmTitle, role: isDestructive ? .destructive : nil) {
                NativeHaptics.mediumImpact()
                onConfirm()
            }
        } message: {
            if let msg = message {
                Text(msg)
            }
        }
    }
    
    func appTransactionActionAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        placeholder: String,
        text: Binding<String>,
        onVoid: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        self.alert(title, isPresented: isPresented) {
            TextField(placeholder, text: text)
            Button("Cancel", role: .cancel) { onCancel() }
            Button("Void transaction", role: .destructive) {
                NativeHaptics.mediumImpact()
                onVoid()
            }
            Button("Delete permanently", role: .destructive) {
                NativeHaptics.heavyImpact()
                onDelete()
            }
        } message: {
            Text(message)
        }
    }
}
