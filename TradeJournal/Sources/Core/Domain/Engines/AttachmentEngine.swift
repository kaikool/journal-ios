import Foundation

/// Engine xử lý và xác thực tệp đính kèm & ảnh chụp màn hình biểu đồ
/// Port 1:1 từ `source-repo/apps/web/src/lib/attachment-validation.ts` và `chart-screenshot-upload.ts`
public enum AttachmentEngine {
    
    /// Giới hạn kích thước tối đa: 8 MB
    public static let maxAttachmentSize: Int = 8 * 1024 * 1024
    
    /// Các loại đối tượng sở hữu tệp đính kèm hợp lệ
    public static let validOwnerTypes: Set<String> = [
        "trade", "day", "note", "missed", "prop-account", "prop-entry"
    ]
    
    /// Xác định MIME type từ magic bytes thực tế của file, không tin tưởng extension hay header do client gửi
    /// Port 1:1 từ `attachmentMime` trong `attachment-validation.ts`
    public static func attachmentMime(data: Data) -> String? {
        let bytes = [UInt8](data.prefix(32))
        guard !bytes.isEmpty else { return nil }
        
        let startsWith = { (pattern: [UInt8]) -> Bool in
            guard bytes.count >= pattern.count else { return false }
            return zip(bytes, pattern).allSatisfy { $0 == $1 }
        }
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            return "image/png"
        }
        
        // JPEG: FF D8 FF
        if startsWith([0xff, 0xd8, 0xff]) {
            return "image/jpeg"
        }
        
        // WEBP: RIFF .... WEBP
        if startsWith([0x52, 0x49, 0x46, 0x46]) && bytes.count >= 12 {
            let webpTag = Array(bytes[8..<12])
            if webpTag == [0x57, 0x45, 0x42, 0x50] {
                return "image/webp"
            }
        }
        
        // PDF: %PDF- (25 50 44 2D)
        if startsWith([0x25, 0x50, 0x44, 0x2d]) {
            return "application/pdf"
        }
        
        return nil
    }
    
    /// Chuẩn hóa tên tệp an toàn (Safe Name)
    /// Port 1:1 từ `safeName` trong `route.ts`
    public static func safeName(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let basename = (trimmed as NSString).lastPathComponent
        let sanitized = basename
            .replacingOccurrences(of: #"[^\w. -]+"#, with: "_", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let result = String(sanitized.prefix(200))
        return result.isEmpty ? "attachment" : result
    }
    
    /// Đường dẫn lưu trữ (Storage Path)
    /// Port 1:1 từ `storagePath` trong `route.ts`:
    /// `attachments/<ownerType>/<ownerId>/<id>/<name>`
    public static func storagePath(ownerType: String, ownerId: String, id: String, name: String) -> String {
        let encOwnerId = ownerId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ownerId
        let encName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "attachments/\(ownerType)/\(encOwnerId)/\(id)/\(encName)"
    }
    
    /// Kiểm tra tính hợp lệ và trích xuất dữ liệu ảnh chụp màn hình biểu đồ (Data URL Base64)
    /// Port 1:1 từ `uploadChartScreenshot` trong `chart-screenshot-upload.ts`
    public static func validateChartScreenshotPng(dataUrl: String) throws -> Data {
        let prefix = "data:image/png;base64,"
        guard dataUrl.hasPrefix(prefix) else {
            throw AttachmentError.notPng
        }
        
        let base64String = String(dataUrl.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: base64String) else {
            throw AttachmentError.invalidData
        }
        
        // Kiểm tra chữ ký magic bytes của PNG
        let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        guard data.count >= signature.count else {
            throw AttachmentError.invalidData
        }
        let head = [UInt8](data.prefix(signature.count))
        guard head == signature else {
            throw AttachmentError.invalidData
        }
        
        return data
    }
    
    /// Kiểm tra toàn bộ dữ liệu tệp đính kèm trước khi lưu trữ
    public static func validateAttachment(
        data: Data,
        declaredName: String
    ) throws -> (mime: String, cleanName: String) {
        guard !data.isEmpty else {
            throw AttachmentError.emptyFile
        }
        
        guard data.count <= maxAttachmentSize else {
            throw AttachmentError.fileTooLarge(size: data.count, max: maxAttachmentSize)
        }
        
        guard let mime = attachmentMime(data: data) else {
            throw AttachmentError.unsupportedType
        }
        
        let cleanName = safeName(declaredName)
        return (mime, cleanName)
    }
}

public enum AttachmentError: LocalizedError, Equatable {
    case notPng
    case invalidData
    case emptyFile
    case fileTooLarge(size: Int, max: Int)
    case unsupportedType
    case ownerNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .notPng:
            return "Chart screenshot is not a PNG image."
        case .invalidData:
            return "Chart screenshot data is invalid."
        case .emptyFile:
            return "Tệp đính kèm không có nội dung."
        case .fileTooLarge(let size, let max):
            return "Tệp vượt quá kích thước tối đa cho phép (\(size / 1024 / 1024) MB > \(max / 1024 / 1024) MB)."
        case .unsupportedType:
            return "Chỉ hỗ trợ tệp hình ảnh (PNG, JPEG, WebP) hoặc tài liệu PDF."
        case .ownerNotFound(let msg):
            return "Không tìm thấy đối tượng gắn tệp đính kèm: \(msg)"
        }
    }
}
