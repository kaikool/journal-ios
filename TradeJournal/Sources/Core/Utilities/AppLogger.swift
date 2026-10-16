import Foundation
import os.log

/// Hệ thống logging chuẩn hóa, tuân thủ nguyên tắc R005 không làm lộ secrets hoặc thông tin nhạy cảm.
public enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.kaikool.tradejournal"
    private static let logger = Logger(subsystem: subsystem, category: "TradeJournal")
    
    public static func debug(_ message: String) {
        #if DEBUG
        logger.debug("🔍 [DEBUG] \(sanitize(message), privacy: .public)")
        #endif
    }
    
    public static func info(_ message: String) {
        logger.info("ℹ️ [INFO] \(sanitize(message), privacy: .public)")
    }
    
    public static func warning(_ message: String) {
        logger.warning("⚠️ [WARN] \(sanitize(message), privacy: .public)")
    }
    
    public static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            logger.error("🛑 [ERROR] \(sanitize(message), privacy: .public) | Details: \(sanitize(error.localizedDescription), privacy: .public)")
        } else {
            logger.error("🛑 [ERROR] \(sanitize(message), privacy: .public)")
        }
    }
    
    /// Loại bỏ các chuỗi nhạy cảm có khả năng là API keys, bearer tokens hoặc passwords
    private static func sanitize(_ text: String) -> String {
        var result = text
        // Mặt nạ hóa Bearer tokens
        result = result.replacingOccurrences(of: "Bearer\\s+[A-Za-z0-9._-]+", with: "Bearer [REDACTED]", options: .regularExpression)
        // Mặt nạ hóa key có định dạng sk-... hoặc sb_...
        result = result.replacingOccurrences(of: "(sk-[A-Za-z0-9]{20,})", with: "[SECRET_KEY_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(sbp_[A-Za-z0-9]{20,})", with: "[SUPABASE_KEY_REDACTED]", options: .regularExpression)
        return result
    }
}

/// Mô hình lỗi chuẩn hóa toàn ứng dụng
public enum AppError: LocalizedError, Equatable {
    case networkUnavailable
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case invalidData(description: String)
    case importFailed(reason: String)
    case syncConflict(entityId: String)
    case unknown(description: String)
    
    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Không có kết nối mạng. Ứng dụng đang hoạt động ở chế độ ngoại tuyến."
        case .unauthorized:
            return "Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại."
        case .serverError(let code, let msg):
            return "Lỗi máy chủ (\(code)): \(msg)"
        case .invalidData(let desc):
            return "Dữ liệu không hợp lệ: \(desc)"
        case .importFailed(let reason):
            return "Không thể nạp dữ liệu: \(reason)"
        case .syncConflict(let id):
            return "Xảy ra xung đột đồng bộ cho bản ghi \(id)."
        case .unknown(let desc):
            return "Lỗi không xác định: \(desc)"
        }
    }
}
