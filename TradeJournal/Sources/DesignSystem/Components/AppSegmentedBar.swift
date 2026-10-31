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
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selection = item
            }
        } label: {
            HStack(spacing: 4) {
                if let icon = iconFor?(item) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(titleFor(item))
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
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
