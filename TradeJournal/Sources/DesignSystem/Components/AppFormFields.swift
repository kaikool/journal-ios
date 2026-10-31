import SwiftUI

public typealias AppTextField = AppFormField

/// Unified Apple HIG Form Field
/// Standard form text input with label, optional leading icon, trailing badge/unit, and subtle border stroke.
public struct AppFormField: View {
    public let label: String?
    public let subtitle: String?
    @Binding public var text: String
    public let placeholder: String
    public let icon: String?
    public let trailingText: String?
    public let isSecure: Bool
    public let errorMessage: String?
    public let height: CGFloat
    public let showClearButton: Bool
    
    public init(
        _ label: String? = nil,
        text: Binding<String>,
        placeholder: String = "",
        subtitle: String? = nil,
        icon: String? = nil,
        trailingText: String? = nil,
        isSecure: Bool = false,
        errorMessage: String? = nil,
        height: CGFloat = 36,
        showClearButton: Bool = false
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.subtitle = subtitle
        self.icon = icon
        self.trailingText = trailingText
        self.isSecure = isSecure
        self.errorMessage = errorMessage
        self.height = height
        self.showClearButton = showClearButton
    }
    
    public init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        showClearButton: Bool = false
    ) {
        self.init(nil, text: text, placeholder: placeholder, icon: icon, showClearButton: showClearButton)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if label != nil || subtitle != nil {
                HStack {
                    if let label = label {
                        Text(label)
                            .font(AppTypography.formLabel)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    }
                }
            }
            
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.captionMedium)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(AppTypography.formInput)
                        .foregroundColor(AppColors.primaryText)
                } else {
                    TextField(placeholder, text: $text)
                        .font(AppTypography.formInput)
                        .foregroundColor(AppColors.primaryText)
                }
                
                if showClearButton && !text.isEmpty {
                    ModalCloseButton {
                        text = ""
                    }
                }
                
                if let trailingText = trailingText, !trailingText.isEmpty {
                    Text(trailingText)
                        .font(AppTypography.statLabel)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(AppColors.secondaryBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        errorMessage != nil ? AppColors.loss.opacity(0.8) : AppColors.border.opacity(0.35),
                        lineWidth: errorMessage != nil ? 1.0 : 0.5
                    )
            )
            
            if let err = errorMessage, !err.isEmpty {
                Text(err)
                    .font(AppTypography.footnote)
                    .foregroundColor(AppColors.loss)
                    .padding(.leading, 2)
            }
        }
    }
}

public struct AppNumericValueField<T: BinaryFloatingPoint>: View {
    public let placeholder: String
    @Binding public var value: T?
    public let height: CGFloat
    
    public init(_ placeholder: String = "", value: Binding<T?>, height: CGFloat = 36) {
        self.placeholder = placeholder
        self._value = value
        self.height = height
    }
    
    public var body: some View {
        TextField(
            placeholder,
            value: Binding(
                get: { value.map { Double($0) } },
                set: { value = $0.map { T($0) } }
            ),
            format: .number
        )
        .font(AppTypography.formInputMono)
        .keyboardType(.decimalPad)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(AppColors.secondaryBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Standardized Decimal input field for financial and configuration values
public struct AppDecimalField: View {
    public let placeholder: String
    @Binding public var value: Decimal
    public let height: CGFloat
    
    public init(_ placeholder: String = "", value: Binding<Decimal>, height: CGFloat = 36) {
        self.placeholder = placeholder
        self._value = value
        self.height = height
    }
    
    public var body: some View {
        TextField(
            placeholder,
            value: $value,
            format: .number
        )
        .font(AppTypography.formInputMono)
        .keyboardType(.decimalPad)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(AppColors.secondaryBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Unified Apple HIG Numeric / Decimal Form Field
/// Tailored for financial quantities, prices, pips, stops, and targets with monospaced digits.
public struct AppNumericField: View {
    public let label: String?
    public let subtitle: String?
    @Binding public var text: String
    public let placeholder: String
    public let icon: String?
    public let unit: String?
    public let height: CGFloat
    
    public init(
        _ label: String? = nil,
        text: Binding<String>,
        placeholder: String = "0.00",
        subtitle: String? = nil,
        icon: String? = nil,
        unit: String? = nil,
        height: CGFloat = 36
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.subtitle = subtitle
        self.icon = icon
        self.unit = unit
        self.height = height
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if label != nil || subtitle != nil {
                HStack {
                    if let label = label {
                        Text(label)
                            .font(AppTypography.formLabel)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    }
                }
            }
            
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.captionMedium)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .font(AppTypography.formInputMono)
                    .foregroundColor(AppColors.primaryText)
                
                if let unit = unit, !unit.isEmpty {
                    Text(unit)
                        .font(AppTypography.badgeStandard)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(AppColors.secondaryBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.border.opacity(0.35), lineWidth: 0.5)
            )
        }
    }
}

