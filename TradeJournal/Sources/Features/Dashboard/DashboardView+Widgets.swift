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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(item.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Move Up Button
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Move Down Button
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Hide Button
                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.loss)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    internal func statHeader(_ title: String, icon: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                activeTooltip = (title: title, hint: hint)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(AppColors.secondaryBackground.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}
