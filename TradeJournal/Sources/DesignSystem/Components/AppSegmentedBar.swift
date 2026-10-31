import SwiftUI

/// Universal Apple HIG Sliding Segmented Bar & Tab List
/// Features spring physics, matched geometry highlight, haptic feedback, and luxury dark mode styling.
public struct AppSegmentedBar<T: Hashable>: View {
    @Binding private var selection: T
    private let items: [T]
    private let titleFor: (T) -> String
    private let iconFor: ((T) -> String?)?
    private let badgeCountFor: ((T) -> Int?)?
    private let isScrollable: Bool
    private let height: CGFloat
    @Namespace private var segmentNamespace
    
    public init(
        selection: Binding<T>,
        items: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil,
        badgeCountFor: ((T) -> Int?)? = nil,
        isScrollable: Bool = false,
        height: CGFloat = 36
    ) {
        self._selection = selection
        self.items = items
        self.titleFor = titleFor
        self.iconFor = iconFor
        self.badgeCountFor = badgeCountFor
        self.isScrollable = isScrollable
        self.height = height
    }
    
    public var body: some View {
        if isScrollable {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items, id: \.self) { item in
                        segmentButton(for: item, isScrollable: true)
                    }
                }
                .padding(3)
            }
            .frame(height: height)
            .background(AppColors.secondaryBackground.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
            )
        } else {
            HStack(spacing: 2) {
                ForEach(items, id: \.self) { item in
                    segmentButton(for: item, isScrollable: false)
                }
            }
            .padding(3)
            .frame(height: height)
            .background(AppColors.secondaryBackground.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
            )
        }
    }
    
    @ViewBuilder
    private func segmentButton(for item: T, isScrollable: Bool) -> some View {
        let isSelected = selection == item
        Button {
            NativeHaptics.lightImpact()
            withAnimation(AppAnimations.springStandard) {
                selection = item
            }
        } label: {
            HStack(spacing: 4) {
                if let icon = iconFor?(item) {
                    Image(systemName: icon)
                        .font(isSelected ? AppTypography.actionButtonCompact : AppTypography.captionMedium)
                }
                Text(titleFor(item))
                    .font(isSelected ? AppTypography.actionButtonCompact : AppTypography.captionMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if let count = badgeCountFor?(item), count > 0 {
                    Text("\(count)")
                        .font(AppTypography.badgeMicro)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(isSelected ? AppColors.brand : AppColors.cardBackground)
                        .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
            .frame(maxWidth: isScrollable ? nil : .infinity, maxHeight: .infinity)
            .padding(.horizontal, isScrollable ? 12 : 0)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.cardBackground)
                        .matchedGeometryEffect(id: "ACTIVE_SEGMENT", in: segmentNamespace)
                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

// MARK: - Standardized 2-choice tactile segmented toggle (Apple HIG)
public struct AppBinarySegmentedToggle<T: Equatable>: View {
    @Binding private var selection: T
    private let firstOption: T
    private let firstTitle: String
    private let firstIcon: String
    private let firstActiveColor: Color
    
    private let secondOption: T
    private let secondTitle: String
    private let secondIcon: String
    private let secondActiveColor: Color
    
    public init(
        selection: Binding<T>,
        firstOption: T,
        firstTitle: String,
        firstIcon: String,
        firstActiveColor: Color = AppColors.profit,
        secondOption: T,
        secondTitle: String,
        secondIcon: String,
        secondActiveColor: Color = AppColors.loss
    ) {
        self._selection = selection
        self.firstOption = firstOption
        self.firstTitle = firstTitle
        self.firstIcon = firstIcon
        self.firstActiveColor = firstActiveColor
        self.secondOption = secondOption
        self.secondTitle = secondTitle
        self.secondIcon = secondIcon
        self.secondActiveColor = secondActiveColor
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Button {
                NativeHaptics.selection()
                selection = firstOption
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: firstIcon)
                        .font(AppTypography.actionButton)
                    Text(firstTitle)
                        .font(AppTypography.actionButton)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selection == firstOption ? firstActiveColor : AppColors.secondaryBackground)
                .foregroundColor(selection == firstOption ? .white : AppColors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            Button {
                NativeHaptics.selection()
                selection = secondOption
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: secondIcon)
                        .font(AppTypography.actionButton)
                    Text(secondTitle)
                        .font(AppTypography.actionButton)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selection == secondOption ? secondActiveColor : AppColors.secondaryBackground)
                .foregroundColor(selection == secondOption ? .white : AppColors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}
