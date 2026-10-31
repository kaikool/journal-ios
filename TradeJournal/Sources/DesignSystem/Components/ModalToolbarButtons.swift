import SwiftUI

/// Standardized Modal Action Buttons adhering 1:1 to the Shell Header design system.
/// Every modal in the application uses these buttons for 100% unified visual hierarchy:
/// - 32pt height standardized touch targets
/// - Identical typography (`12.5pt`, `.semibold`, `.rounded`)
/// - Identical Emerald Brand Capsule for primary actions (`Done`, `Save`, `Create`)
/// - Identical 32x32 Circular Pods for icon actions (`xmark`, `trash`, `edit`, `back`)
/// - Tactile ApplePressableButtonStyle with native spring feedback

// MARK: - Circular Dismiss Button (xmark)
public struct ModalDismissButton: View {
    let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Close")
    }
}

// MARK: - Circular Back Button (chevron.left)
public struct ModalBackButton: View {
    let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Back")
    }
}

// MARK: - Circular Delete Button (trash)
public struct ModalDeleteButton: View {
    let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.loss.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppColors.loss.opacity(0.3), lineWidth: 0.6)
                    )
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.loss)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Delete")
    }
}

// MARK: - Primary Action Button (e.g. Done, Save, Create)
public struct ModalPrimaryButton: View {
    let title: String
    let icon: String?
    let isEnabled: Bool
    let action: () -> Void
    
    public init(_ title: String, icon: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.mediumImpact()
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isEnabled ? .white : AppColors.secondaryText.opacity(0.6))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isEnabled ? AppColors.brand : AppColors.secondaryBackground)
            .clipShape(Capsule())
            .shadow(color: isEnabled ? AppColors.brand.opacity(0.3) : .clear, radius: 3, x: 0, y: 1)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .disabled(!isEnabled)
    }
}

// MARK: - Secondary Cancel Button
public struct ModalSecondaryButton: View {
    let title: String
    let action: () -> Void
    
    public init(_ title: String = "Cancel", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

// MARK: - Circular Icon Action Button (e.g. AI Coach, Edit, Settings)
public struct ModalIconButton: View {
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void
    
    public init(icon: String, color: Color = AppColors.secondaryText, label: String = "", action: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.label = label
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}
