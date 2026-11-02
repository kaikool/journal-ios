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
                        AppChatBubble(role: .user) {
                            Text(msg.content)
                                .font(AppTypography.bodyMedium)
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
                                JournalNotesMarkdownView(text: AIDocumentParser.stripTechnicalMetadata(from: msg.content))
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
                    .font(AppTypography.formInput)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .padding(.leading, 6)
                
                AppTextField("Ask a follow-up question...", text: $followUpQuery)
                    .onSubmit {
                        if hasQueryText && !isSubmitting {
                            onSubmit()
                        }
                    }
                
                if hasHistory && !hasQueryText {
                    ModalCircleButton(icon: "arrow.counterclockwise", action: onResetThread)
                        .help("New Thread")
                }
                
                if isSubmitting {
                    TradeJournalProLoader(size: 20)
                        .frame(width: 34, height: 34)
                } else {
                    ModalCircleButton(icon: "arrow.up", action: onSubmit)
                    .disabled(!hasQueryText)
                    .animation(.easeInOut(duration: 0.15), value: hasQueryText)
                }
            }
            .appCardStyle(cornerRadius: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
    }
}
