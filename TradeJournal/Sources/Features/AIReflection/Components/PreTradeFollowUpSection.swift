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
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .padding(.leading, 6)
                
                TextField("Ask a follow-up question...", text: $followUpQuery)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppColors.primaryText)
                    .onSubmit {
                        if hasQueryText && !isSubmitting {
                            onSubmit()
                        }
                    }
                
                if hasHistory && !hasQueryText {
                    Button(action: onResetThread) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(AppColors.secondaryBackground.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New Thread")
                }
                
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.85)
                        .frame(width: 34, height: 34)
                } else {
                    Button(action: onSubmit) {
                        ZStack {
                            Circle()
                                .fill(hasQueryText ? AppColors.brand : AppColors.secondaryBackground.opacity(0.85))
                                .frame(width: 34, height: 34)
                            
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(hasQueryText ? .white : AppColors.secondaryText.opacity(0.4))
                        }
                    }
                    .disabled(!hasQueryText)
                    .animation(.easeInOut(duration: 0.15), value: hasQueryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColors.border.opacity(0.65), lineWidth: 1.0)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
    }
}
