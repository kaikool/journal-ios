import SwiftUI

// MARK: - Trade AI Coach Follow-Up Message History
// Renders the multi-turn discussion conversation bubbles in the main scroll view
public struct TradeAICoachFollowUpView: View {
    public let coachingResult: String
    public let followUpMessages: [AICoachMessage]
    
    public init(
        coachingResult: String,
        followUpMessages: [AICoachMessage]
    ) {
        self.coachingResult = coachingResult
        self.followUpMessages = followUpMessages
    }
    
    public var body: some View {
        if !followUpMessages.isEmpty {
            VStack(spacing: 12) {
                ForEach(followUpMessages) { msg in
                    if msg.role == "user" {
                        HStack {
                            Spacer(minLength: 32)
                            Text(msg.content)
                                .font(AppTypography.body)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppColors.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else if msg.role == "assistant" && msg.content != coachingResult {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.brand)
                                Text("RISK AI FOLLOW-UP")
                                    .font(AppTypography.cardHeader)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            AIDocumentReaderView(text: msg.content)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Trade AI Coach Bottom Floating Inquiry Dock
// Pinned modern glassmorphic floating bottom input dock
public struct TradeAICoachBottomFloatingInput: View {
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
        VStack(spacing: 6) {
            // Header Row
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.brand)
                Text("ASK FOLLOW-UP QUESTION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                if hasHistory {
                    Button(action: onResetThread) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8, weight: .semibold))
                            Text("New Thread")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.secondaryBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            
            // Sleek Modern Input Pill
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    .padding(.leading, 2)
                
                TextField("Ask a follow-up question...", text: $followUpQuery)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AppColors.primaryText)
                    .onSubmit {
                        if hasQueryText && !isSubmitting {
                            onSubmit()
                        }
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
            .padding(.vertical, 6)
            .background(AppColors.secondaryBackground.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AppColors.cardBackground
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: -4)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(AppColors.border.opacity(0.5)),
            alignment: .top
        )
    }
}
