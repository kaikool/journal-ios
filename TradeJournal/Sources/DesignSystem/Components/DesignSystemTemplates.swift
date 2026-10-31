import SwiftUI

/// Canonical UI Templates conforming to the TradeJournal Design System
/// Reference these templates when creating new views to ensure 100% architectural consistency.

// MARK: - Template 1: Standard Feature Section Card
public struct StandardFeatureCardTemplate: View {
    public let title: String
    public let icon: String
    public let badge: String?
    public let onAction: (() -> Void)?
    
    public init(
        title: String = "FEATURE SECTION",
        icon: String = "sparkles",
        badge: String? = "Active",
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.onAction = onAction
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Standard Header
                AppSectionHeader(
                    title,
                    icon: icon,
                    badge: badge,
                    actionTitle: onAction != nil ? "View all" : nil,
                    actionIcon: onAction != nil ? "chevron.right" : nil,
                    onAction: onAction
                )
                
                // 2. Standard Metric Row
                HStack(spacing: 12) {
                    AppMetricTile(title: "Win Rate", value: "68.4%", trend: .up)
                    AppMetricTile(title: "Profit Factor", value: "2.35", trend: .up)
                    AppMetricTile(title: "Net P&L", value: "+$4,820", trend: .up)
                }
                
                // 3. Body Text using AppTypography
                Text("Consistent risk parameters maintained across London and New York session setups.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // 4. Standard Action Pill
                HStack {
                    Spacer()
                    AppActionPill("Detailed Breakdown", icon: "arrow.up.right") {
                        onAction?()
                    }
                }
            }
        }
    }
}

// MARK: - Template 2: Standard Modal Sheet Container
public struct StandardModalSheetTemplate: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputName: String = ""
    @State private var inputAmount: String = ""
    @State private var isChecked: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Form Card
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("ENTRY SPECIFICATIONS", icon: "slider.horizontal.3")
                            
                            AppTextField("Trade Setup Name", text: $inputName, placeholder: "e.g. London ICT Silver Bullet")
                            
                            AppNumericField("Position Size", text: $inputAmount, placeholder: "1.00", unit: "Lots")
                            
                            AppCheckboxRow(
                                "Higher Timeframe Bias Aligned",
                                subtitle: "Confirmed on 4H / 1D order flow",
                                isChecked: isChecked
                            ) {
                                isChecked.toggle()
                            }
                        }
                    }
                    
                    // Section 2: Action Button
                    AppPrimaryButton("Save Setup", icon: "checkmark") {
                        dismiss()
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(AppColors.background)
            .navigationTitle("New Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton {
                        dismiss()
                    }
                }
            }
        }
    }
}
