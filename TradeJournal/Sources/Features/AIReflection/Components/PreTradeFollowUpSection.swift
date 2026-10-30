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
// Pinned floating bottom input tool enabling immediate follow-up inquiries from anywhere in the document
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
    
    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.brand)
                Text("ASK FOLLOW-UP QUESTION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                if hasHistory {
                    Button(action: onResetThread) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text("New Thread")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 8) {
                TextField("Hỏi tiếp về kế hoạch này (Ask follow-up question)...", text: $followUpQuery)
                    .font(AppTypography.inputText)
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                    )
                    .onSubmit {
                        onSubmit()
                    }
                
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.85)
                        .frame(width: 32, height: 32)
                } else {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(followUpQuery.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.secondaryText.opacity(0.35) : AppColors.brand)
                    }
                    .disabled(followUpQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            AppColors.cardBackground
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: -4)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(AppColors.border.opacity(0.6)),
            alignment: .top
        )
    }
}
