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
                            .font(.system(size: 11, weight: .medium))
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
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.brand)
                            Text("Risk AI will analyze this chart alongside your inquiry.")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button(action: { selectedChartImage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(6)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .cornerRadius(6)
                }
                
                HStack(spacing: 8) {
                    Button(action: onAttachPhoto) {
                        Image(systemName: selectedChartImage != nil ? "photo.fill" : "photo.badge.plus")
                            .font(.system(size: 15))
                            .foregroundColor(selectedChartImage != nil ? AppColors.brand : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    
                    TextField("Enter question or instruction for Risk AI...", text: $userPrompt)
                        .font(AppTypography.inputText)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.vertical, 8)
                    
                    if !userPrompt.isEmpty {
                        Button(action: { userPrompt = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.secondaryText)
                                .font(.system(size: 14))
                        }
                    }
                    
                    Button(action: {
                        onSubmit(userPrompt)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? AppColors.secondaryText.opacity(0.4) : AppColors.brand)
                    }
                    .disabled(userPrompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal, 10)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .padding(.vertical, 2)
        }
    }
}
