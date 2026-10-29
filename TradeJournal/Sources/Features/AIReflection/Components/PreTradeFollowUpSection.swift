import SwiftUI

// MARK: - Pre-Trade Follow-Up Inquiry Section
// Manages follow-up discussion history, interactive text field, and thread reset
public struct PreTradeFollowUpSection: View {
    public let analysisResult: String
    @Binding public var followUpMessages: [AICoachMessage]
    @Binding public var followUpQuery: String
    public let isSubmitting: Bool
    public let onResetThread: () -> Void
    public let onSubmit: () -> Void
    
    public init(
        analysisResult: String,
        followUpMessages: Binding<[AICoachMessage]>,
        followUpQuery: Binding<String>,
        isSubmitting: Bool,
        onResetThread: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self.analysisResult = analysisResult
        self._followUpMessages = followUpMessages
        self._followUpQuery = followUpQuery
        self.isSubmitting = isSubmitting
        self.onResetThread = onResetThread
        self.onSubmit = onSubmit
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Conversation turns (filters out any raw full analysis duplicates)
            let visibleMessages = followUpMessages.filter { $0.content != analysisResult }
            if !visibleMessages.isEmpty {
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
            
            // Inquiry Input Bar
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("FOLLOW-UP INQUIRY")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Spacer()
                        
                        if !followUpMessages.isEmpty {
                            Button(action: onResetThread) {
                                Text("New Thread")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        TextField("What if price wicks above PDH before London?...", text: $followUpQuery)
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
