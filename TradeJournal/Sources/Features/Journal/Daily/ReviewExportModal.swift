import SwiftUI

/// Modal for exporting and sharing daily review
public struct ReviewExportModal: View {
    public let title: String
    public let exportText: String
    @Environment(\.dismiss) private var dismiss
    
    public init(title: String, exportText: String) {
        self.title = title
        self.exportText = exportText
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: .constant(exportText))
                    .font(AppTypography.monoCaption)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(16)
                
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = exportText
                    #endif
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to Clipboard")
                    }
                    .font(AppTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
