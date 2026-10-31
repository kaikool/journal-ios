import SwiftUI

/// Global status notification banner for background synchronization
/// Displays real-time progress, errors (with link to Settings), and success confirmations.
public struct GlobalSyncBannerView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    @State private var dismissTimer: Task<Void, Never>? = nil
    @State private var isDismissed: Bool = false
    
    public init() {}
    
    public var body: some View {
        Group {
            if let error = dataStore.lastSyncError, !isDismissed, !error.lowercased().contains("cancel") {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.loss)
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.loss)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        env.selectedTab = .settings
                    } label: {
                        Text("Settings")
                            .font(AppTypography.badgeStandard)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.loss.opacity(0.18))
                            .foregroundColor(AppColors.loss)
                            .clipShape(Capsule())
                    }
                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.loss.opacity(0.12))
                .overlay(
                    Divider().background(AppColors.loss.opacity(0.3)),
                    alignment: .bottom
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let summary = dataStore.lastSyncSummary, !isDismissed && (summary.contains("completed") || summary.contains("successful") || summary.contains("synchronized")) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.profit)
                    Text(summary)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.profit.opacity(0.12))
                .overlay(
                    Divider().background(AppColors.profit.opacity(0.3)),
                    alignment: .bottom
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    scheduleAutoDismiss()
                }
            }
        }
        .onChange(of: dataStore.lastSyncSummary) { _ in
            isDismissed = false
            if !dataStore.isSyncing {
                scheduleAutoDismiss()
            }
        }
        .onChange(of: dataStore.lastSyncError) { _ in
            isDismissed = false
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: dataStore.isSyncing)
    }
    
    private func scheduleAutoDismiss() {
        dismissTimer?.cancel()
        dismissTimer = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run {
                withAnimation { isDismissed = true }
            }
        }
    }
}
