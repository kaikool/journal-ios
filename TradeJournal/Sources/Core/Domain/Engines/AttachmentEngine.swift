import Foundation

/// Internal domain documentation
/// Domain specification matching core web repository
public enum AttachmentEngine {
    
    /// Internal domain documentation
    public static let maxAttachmentSize: Int = 8 * 1024 * 1024
    
    /// Internal domain documentation
    public static let validOwnerTypes: Set<String> = [
        "trade", "day", "note", "missed", "prop-account", "prop-entry"
    ]
    
    /// Internal domain documentation
/// Ported 1:1 from `attachmentMime` trong `attachment-validation.ts`
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
    
    /// Internal domain documentation
/// Ported 1:1 from `safeName` trong `route.ts`
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
    
    /// Internal domain documentation
/// Ported 1:1 from `storagePath` trong `route.ts`:
    /// `attachments/<ownerType>/<ownerId>/<id>/<name>`
    public static func storagePath(ownerType: String, ownerId: String, id: String, name: String) -> String {
        let encOwnerId = ownerId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ownerId
        let encName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "attachments/\(ownerType)/\(encOwnerId)/\(id)/\(encName)"
    }
    
    /// Internal domain documentation
/// Ported 1:1 from `uploadChartScreenshot` trong `chart-screenshot-upload.ts`
    public static func validateChartScreenshotPng(dataUrl: String) throws -> Data {
        let prefix = "data:image/png;base64,"
        guard dataUrl.hasPrefix(prefix) else {
            throw AttachmentError.notPng
        }
        
        let base64String = String(dataUrl.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: base64String) else {
            throw AttachmentError.invalidData
        }
        
        // Internal implementation note
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
    
    /// Internal domain documentation
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
            return "Attachment contains no data."
        case .fileTooLarge(let size, let max):
            return "File exceeds maximum allowed size (\(size / 1024 / 1024) MB > \(max / 1024 / 1024) MB)."
        case .unsupportedType:
            return "Only image files (PNG, JPEG, WebP) or PDF documents are supported."
        case .ownerNotFound(let msg):
            return "Attachment parent entity not found: \(msg)"
        }
    }
}
