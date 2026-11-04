import SwiftUI

// MARK: - Standard 27: Unified In-App Notification Center Sheet
public struct NotificationCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var coordinator = AppNotificationCoordinator.shared
    
    public init() {}
    
    public var body: some View {
        AppSheetContainer("Alerts & Activity", onClose: { dismiss() }) {
            VStack(spacing: 0) {
                if coordinator.recentNotifications.isEmpty {
                    VStack {
                        Spacer()
                        AppEmptyState(
                            icon: "bell.slash",
                            title: "No Alerts Yet",
                            message: "High-impact economic news, discipline warnings, and session routines will appear here."
                        )
                        Spacer()
                    }
                } else {
                    HStack {
                        Text("\(coordinator.recentNotifications.count) Total Alerts")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        if coordinator.unreadCount > 0 {
                            Button("Mark All Read") {
                                NativeHaptics.lightImpact()
                                coordinator.markAllAsRead()
                            }
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.brand)
                            .padding(.trailing, 8)
                        }
                        Button("Clear All") {
                            NativeHaptics.lightImpact()
                            coordinator.clearAll()
                        }
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.loss)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(coordinator.recentNotifications) { item in
                                notificationRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .onAppear {
            coordinator.markAllAsRead()
        }
    }
    
    private func notificationRow(_ item: NotificationItem) -> some View {
        Button {
            NativeHaptics.selection()
            handleItemTap(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AppBadge(item.category.label, style: badgeStyle(for: item.category))
                    
                    Spacer()
                    
                    Text(Formatters.formatTime(item.timestamp, timeZone: env.currentTimeZone))
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Text(item.title)
                    .font(AppTypography.rowTitle)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Text(item.body)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .appCardStyle(cornerRadius: 10, padding: 0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func badgeStyle(for category: NotificationCategory) -> AppBadgeStyle {
        switch category {
        case .disciplineTilt:
            return .loss
        case .economicNews:
            return .brand
        case .marketStructure:
            return .neutral
        case .preSessionRoutine:
            return .brand
        case .dailyJournalReview:
            return .profit
        }
    }
    
    private func handleItemTap(_ item: NotificationItem) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            switch item.category {
            case .economicNews:
                env.selectedTab = .calendar
            case .dailyJournalReview:
                env.selectedTab = .journal
                env.requestOpenTodayJournal = true
            case .disciplineTilt:
                env.selectedTab = .dashboard
                env.requestAddTrade = true
            case .preSessionRoutine:
                if item.userInfo["type"] == "morning_routine" {
                    env.selectedTab = .progress
                } else {
                    env.selectedTab = .dashboard
                    env.requestAddTrade = true
                }
            case .marketStructure:
                env.selectedTab = .trades
            }
        }
    }
}
