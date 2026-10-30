import SwiftUI

// MARK: - Pre-Trade Follow-Up Message History
// Renders the multi-turn discussion conversation bubbles in the main scroll view
public struct PreTradeFollowUpSection: View {
    public let analysisResult: String
    public let followUpMessages: [AICoachMessage]
    
    public init(
        analysisResult: String,
        followUpMessages: [AICoachMessage]
    ) {
        self.analysisResult = analysisResult
        self.followUpMessages = followUpMessages
    }
    
    public var body: some View {
        let visibleMessages = followUpMessages.filter { $0.content != analysisResult }
        if !visibleMessages.isEmpty {
            VStack(spacing: 12) {
                ForEach(visibleMessages) { msg in
                    if msg.role == "user" {
                        HStack {
                            Spacer()
                            Text(msg.content)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppColors.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .frame(maxWidth: 280, alignment: .trailing)
                        }
                    } else {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(AppColors.profit)
                                        .frame(width: 5, height: 5)
                                    Text("RISK AI FOLLOW-UP")
                                        .font(AppTypography.badgeMicro)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                JournalNotesMarkdownView(text: msg.content)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pre-Trade Bottom Floating Inquiry Dock
// Pinned modern glassmorphic floating bottom input dock
public struct PreTradeBottomFloatingInput: View {
    @Binding public var followUpQuery: String
    public let isSubmitting: Bool
    public let hasHistory: Bool
    public let onResetThread: () -> Void
    public let onSubmit: () -> Void
    
    public init(
        followUpQuery: Binding<String>,
        isSubmitting: Bool,
        hasHistory: Bool,
        onResetThread: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self._followUpQuery = followUpQuery
        self.isSubmitting = isSubmitting
        self.hasHistory = hasHistory
        self.onResetThread = onResetThread
        self.onSubmit = onSubmit
    }
    
    private var hasQueryText: Bool {
        !followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Sleek Floating Input Pill
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    .padding(.leading, 4)
                
                TextField("Ask a follow-up question...", text: $followUpQuery)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AppColors.primaryText)
                    .onSubmit {
                        if hasQueryText && !isSubmitting {
                            onSubmit()
                        }
                    }
                
                if hasHistory && !hasQueryText {
                    Button(action: onResetThread) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(AppColors.secondaryBackground.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New Thread")
                }
                
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 28, height: 28)
                } else {
                    Button(action: onSubmit) {
                        ZStack {
                            Circle()
                                .fill(hasQueryText ? AppColors.brand : AppColors.secondaryBackground.opacity(0.8))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(hasQueryText ? .white : AppColors.secondaryText.opacity(0.4))
                        }
                    }
                    .disabled(!hasQueryText)
                    .animation(.easeInOut(duration: 0.15), value: hasQueryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.border.opacity(0.55), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}
