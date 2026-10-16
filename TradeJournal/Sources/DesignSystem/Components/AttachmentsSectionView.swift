import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Thành phần giao diện quản lý tệp đính kèm và ảnh chụp màn hình biểu đồ
/// Port 1:1 từ `source-repo/apps/web/src/components/attachments.tsx`
public struct AttachmentsSectionView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public let ownerType: String
    public let ownerId: String
    public let title: String
    
    @State private var showPhotoPicker: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var previewAttachment: Attachment? = nil
    @State private var itemToDelete: Attachment? = nil
    @State private var errorMessage: String? = nil
    @State private var isProcessing: Bool = false
    
    public init(ownerType: String, ownerId: String, title: String = "Tệp đính kèm & Ảnh biểu đồ") {
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.title = title
    }
    
    private var attachments: [Attachment] {
        dataStore.attachmentsFor(ownerType: ownerType, ownerId: ownerId)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "paperclip")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                Text("\(attachments.count) tệp (Tối đa 8MB)")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
            }
            
            // Thanh công cụ thêm tệp
            HStack(spacing: 12) {
                // 1. Thư viện ảnh / Ảnh chụp màn hình biểu đồ
                Button {
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                        Text("Thêm ảnh / Screenshot")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.cardBackground)
                    .foregroundColor(AppColors.accent)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                
                // 2. Chọn file tài liệu / PDF từ Tệp
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                        Text("Tệp / PDF")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.cardBackground)
                    .foregroundColor(AppColors.secondaryText)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.loss)
            }
            
            // Danh sách tệp đính kèm dạng Grid
            if !attachments.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(attachments) { att in
                        AttachmentCardView(attachment: att) {
                            previewAttachment = att
                        } onDelete: {
                            itemToDelete = att
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            #if canImport(UIKit)
            UIKitImagePicker(isPresented: $showPhotoPicker) { data, name in
                do {
                    _ = try dataStore.addAttachment(
                        ownerType: ownerType,
                        ownerId: ownerId,
                        name: name,
                        data: data
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            #endif
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        .sheet(item: $previewAttachment) { att in
            AttachmentPreviewSheet(attachment: att)
        }
        .alert("Xóa tệp đính kèm?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Hủy", role: .cancel) { itemToDelete = nil }
            Button("Xóa", role: .destructive) {
                if let att = itemToDelete {
                    try? dataStore.deleteAttachment(id: att.id)
                    itemToDelete = nil
                }
            }
        } message: {
            Text("Tệp sẽ bị xóa khỏi nhật ký và bộ nhớ máy.")
        }
    }

    
    private func handleImportedFile(_ result: Result<[URL], Error>) {
        isProcessing = true
        errorMessage = nil
        do {
            let urls = try result.get()
            if let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Không có quyền truy cập tệp đã chọn."
                    isProcessing = false
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                _ = try dataStore.addAttachment(
                    ownerType: ownerType,
                    ownerId: ownerId,
                    name: name,
                    data: data
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}

// MARK: - Attachment Card View

public struct AttachmentCardView: View {
    let attachment: Attachment
    var onPreview: () -> Void
    var onDelete: () -> Void
    
    private var isImage: Bool {
        attachment.mime.hasPrefix("image/")
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onPreview) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.cardBackground)
                        .frame(height: 110)
                    
                    if isImage, let data = TradeDataStore.shared.attachmentFileData(storagePath: attachment.storagePath),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 110)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: isImage ? "photo" : "doc.text.fill")
                                .font(.system(size: 28))
                                .foregroundColor(AppColors.accent)
                            Text(isImage ? "Ảnh biểu đồ" : "Tài liệu PDF")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Text("\(max(1, attachment.size / 1024)) KB")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.loss.opacity(0.8))
                        .padding(4)
                }
            }
        }
        .padding(8)
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Attachment Preview Sheet

public struct AttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: Attachment
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                
                if attachment.mime.hasPrefix("image/"),
                   let data = TradeDataStore.shared.attachmentFileData(storagePath: attachment.storagePath),
                   let uiImage = UIImage(data: data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 64))
                            .foregroundColor(AppColors.accent)
                        Text(attachment.name)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text("Kích thước: \(attachment.size / 1024) KB • MIME: \(attachment.mime)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding()
                }
            }
            .navigationTitle(attachment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

#if canImport(UIKit)
public struct UIKitImagePicker: UIViewControllerRepresentable {
    @Binding public var isPresented: Bool
    public var onImagePicked: (Data, String) -> Void
    
    public init(isPresented: Binding<Bool>, onImagePicked: @escaping (Data, String) -> Void) {
        self._isPresented = isPresented
        self.onImagePicked = onImagePicked
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: UIKitImagePicker
        
        init(_ parent: UIKitImagePicker) {
            self.parent = parent
        }
        
        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                let name = "screenshot-\(Int(Date().timeIntervalSince1970)).jpg"
                parent.onImagePicked(data, name)
            }
            parent.isPresented = false
        }
        
        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
#endif

