import SwiftUI

/// Universal Apple HIG Sliding Segmented Bar with matched geometry, spring physics, and haptics.
public struct AppleSlidingSegmentedBar<T: Hashable & Identifiable>: View {
    @Binding private var selection: T
    private let items: [T]
    private let titleFor: (T) -> String
    private let iconFor: ((T) -> String?)?
    private let badgeCountFor: ((T) -> Int?)?
    private let isScrollable: Bool
    @Namespace private var segmentNamespace
    
    public init(
        selection: Binding<T>,
        items: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil,
        badgeCountFor: ((T) -> Int?)? = nil,
        isScrollable: Bool = false
    ) {
        self._selection = selection
        self.items = items
        self.titleFor = titleFor
        self.iconFor = iconFor
        self.badgeCountFor = badgeCountFor
        self.isScrollable = isScrollable
    }
    
    public var body: some View {
        if isScrollable {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items) { item in
                        segmentButton(for: item, isScrollable: true)
                    }
                }
                .padding(3)
            }
            .background(AppColors.secondaryBackground.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    segmentButton(for: item, isScrollable: false)
                }
            }
            .padding(3)
            .background(AppColors.secondaryBackground.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    @ViewBuilder
    private func segmentButton(for item: T, isScrollable: Bool) -> some View {
        let isSelected = selection == item
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
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
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
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
            .frame(maxWidth: isScrollable ? nil : .infinity)
            .padding(.horizontal, isScrollable ? 10 : 0)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.cardBackground)
                        .matchedGeometryEffect(id: "ACTIVE_SEGMENT", in: segmentNamespace)
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

/// Custom Apple HIG Styled Dropdown Field matching app rounded rectangle card aesthetic.
/// Replaces generic system picker grey button with a crisp, theme-aware selector.
public struct AppDropdownField<T: Hashable>: View {
    public let label: String?
    @Binding public var selection: T
    public let options: [T]
    public let titleFor: (T) -> String
    public let iconFor: ((T) -> String?)?
    
    public init(
        label: String? = nil,
        selection: Binding<T>,
        options: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.titleFor = titleFor
        self.iconFor = iconFor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = label, !label.isEmpty {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button {
                        selection = opt
                    } label: {
                        HStack {
                            if let icon = iconFor?(opt) {
                                Image(systemName: icon)
                            }
                            Text(titleFor(opt))
                            if selection == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let icon = iconFor?(selection) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.brand)
                    }
                    
                    Text(titleFor(selection))
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}
