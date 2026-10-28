import SwiftUI

// MARK: - Trade AI Coach Follow-Up Discussion Section
// Handles multi-turn chat bubbles, follow-up inquiry text field, and "New Thread" reset button
public struct TradeAICoachFollowUpView: View {
    public let coachingResult: String
    @Binding public var followUpMessages: [AICoachMessage]
    @Binding public var followUpQuery: String
    public let isSubmitting: Bool
    public let onResetThread: () -> Void
    public let onSubmit: () -> Void
    
    public init(
        coachingResult: String,
        followUpMessages: Binding<[AICoachMessage]>,
        followUpQuery: Binding<String>,
        isSubmitting: Bool,
        onResetThread: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self.coachingResult = coachingResult
        self._followUpMessages = followUpMessages
        self._followUpQuery = followUpQuery
        self.isSubmitting = isSubmitting
        self.onResetThread = onResetThread
        self.onSubmit = onSubmit
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // 1. Follow-Up Message History
            if !followUpMessages.isEmpty {
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
            
            // 2. Input Box
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.brand)
                        Text("ASK FOLLOW-UP QUESTION")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Spacer()
                        
                        if !followUpMessages.isEmpty {
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
                    
                    HStack(spacing: 8) {
                        TextField("What if price breaks this support?...", text: $followUpQuery)
                            .font(AppTypography.inputText)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                            .onSubmit {
                                onSubmit()
                            }
                        
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 30, height: 30)
                        } else {
                            Button(action: onSubmit) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(followUpQuery.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
                            }
                            .disabled(followUpQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
