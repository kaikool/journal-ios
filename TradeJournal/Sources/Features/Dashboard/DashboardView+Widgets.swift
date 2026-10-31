import SwiftUI
import Charts

// MARK: - Dashboard Card Wrapper with Interactive Reorder Bar

internal struct DashboardCardWrapper<Content: View>: View {
    let cardId: String
    let isEditing: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onHide: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing, let item = DashboardCardRegistry.item(for: cardId) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(item.label)
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Move Up Button
                    ModalCircleButton(icon: "arrow.up", action: onMoveUp)
                    
                    // Move Down Button
                    ModalCircleButton(icon: "arrow.down", action: onMoveDown)
                    
                    // Hide Button
                    ModalCloseButton(action: onHide)
                }
                .appSubCardStyle(cornerRadius: 10, padding: 6)
                .padding(.bottom, 6)
            }
            
            content()
        }
        .overlay(
            isEditing ?
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.brand.opacity(0.4), lineWidth: 1.5)
                : nil
        )
    }
}

// MARK: - Universal Widget Dispatcher & Reorder Wrapper
extension DashboardView {
    
    @ViewBuilder
    internal func renderWidget(id: String, snap: DashboardSnapshot, isCompact: Bool) -> some View {
        DashboardCardWrapper(
            cardId: id,
            isEditing: isEditingLayout,
            onMoveUp: { moveCard(cardId: id, direction: -1) },
            onMoveDown: { moveCard(cardId: id, direction: 1) },
            onHide: { hideCard(cardId: id) }
        ) {
            switch id {
            case "widget-0": widget0NetPnl(snap: snap, isCompact: isCompact)
            case "widget-1": widget1TradeWin(snap: snap, isCompact: isCompact)
            case "widget-2": widget2ProfitFactor(snap: snap, isCompact: isCompact)
            case "widget-3": widget3DayWin(snap: snap, isCompact: isCompact)
            case "widget-4": widget4AvgWinLoss(snap: snap, isCompact: isCompact)
            case "widget-5": widget5EdgeScore(snap: snap)
            case "widget-6": widget6CumulativePnl(snap: snap)
            case "widget-7": widget7DailyPnl(snap: snap)
            case "widget-8": widget8Calendar(snap: snap)
            case "widget-9": widget9Activity(snap: snap)
            case "widget-10": widget10MaxDrawdown(snap: snap, isCompact: isCompact)
            case "widget-11": widget11Streaks(snap: snap, isCompact: isCompact)
            case "widget-12": widget12Expectancy(snap: snap, isCompact: isCompact)
            case "widget-13": widget13AvgDuration(snap: snap, isCompact: isCompact)
            case "widget-14": widget14BestWorstDay(snap: snap, isCompact: isCompact)
            case "widget-15": widget15TradeTimePerformance(snap: snap)
            default: EmptyView()
            }
        }
    }
    
    // MARK: - Apple HIG Reusable Card Container & Header
    
    internal func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().appCardStyle(cornerRadius: 16)
    }
    
    internal func statHeader(_ title: String, icon: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(title.uppercased())
                .font(AppTypography.cardHeaderUppercase)
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            ModalCircleButton(icon: icon, action: {
                NativeHaptics.lightImpact()
                activeTooltip = (title: title, hint: hint)
            })
        }
    }
}
