import SwiftUI

// MARK: - AI Reflection Custom Inquiry Card
public struct AIReflectionCustomInquiryCard: View {
    @Binding public var userPrompt: String
    @Binding public var selectedChartImage: UIImage?
    public let isLoading: Bool
    public let onOpenTraderProfile: () -> Void
    public let onAttachPhoto: () -> Void
    public let onSubmit: (String) -> Void
    
    public init(
        userPrompt: Binding<String>,
        selectedChartImage: Binding<UIImage?>,
        isLoading: Bool,
        onOpenTraderProfile: @escaping () -> Void,
        onAttachPhoto: @escaping () -> Void,
        onSubmit: @escaping (String) -> Void
    ) {
        self._userPrompt = userPrompt
        self._selectedChartImage = selectedChartImage
        self.isLoading = isLoading
        self.onOpenTraderProfile = onOpenTraderProfile
        self.onAttachPhoto = onAttachPhoto
        self.onSubmit = onSubmit
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ask Custom Question")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    Button(action: onOpenTraderProfile) {
                        Text("Trader Profile")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                if let image = selectedChartImage {
                    HStack(spacing: 8) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 38)
                            .cornerRadius(5)
                            .clipped()
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppColors.border, lineWidth: 0.8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Attached Chart Image (Vision)")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.brand)
                            Text("Risk AI will analyze this chart alongside your inquiry.")
                                .font(AppTypography.captionMicro)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button(action: { selectedChartImage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .appSubCardStyle(cornerRadius: 6, padding: 6)
                }
                
                HStack(spacing: 8) {
                    Button(action: onAttachPhoto) {
                        Image(systemName: selectedChartImage != nil ? "photo.fill" : "photo.badge.plus")
                            .font(AppTypography.formInput)
                            .foregroundColor(selectedChartImage != nil ? AppColors.brand : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    
                    AppTextField("Enter question or instruction for Risk AI...", text: $userPrompt)
                    
                    if !userPrompt.isEmpty {
                        Button(action: { userPrompt = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.secondaryText)
                                .font(AppTypography.caption)
                        }
                    }
                    
                    Button(action: {
                        onSubmit(userPrompt)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(AppTypography.displayHero)
                            .foregroundColor(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
                    }
                    .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .appSubCardStyle(cornerRadius: 8, padding: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .padding(.vertical, 2)
        }
    }
}
