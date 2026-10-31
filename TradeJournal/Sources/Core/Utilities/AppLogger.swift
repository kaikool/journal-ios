import Foundation
import os.log

/// Standard logging system adhering to security guidelines without leaking secrets.
public enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.kaikool.tradejournal"
    private static let logger = Logger(subsystem: subsystem, category: "TradeJournal")
    
    public static func debug(_ message: String) {
        #if DEBUG
        logger.debug("🔍 [DEBUG] \(sanitize(message), privacy: .public)")
        #endif
    }
    
    public static func info(_ message: String) {
        #if DEBUG
        logger.info("ℹ️ [INFO] \(sanitize(message), privacy: .public)")
        #endif
    }
    
    public static func warning(_ message: String) {
        logger.warning("⚠️ [WARN] \(sanitize(message), privacy: .public)")
    }
    
    public static func warn(_ message: String) {
        warning(message)
    }
    
    public static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            logger.error("🛑 [ERROR] \(sanitize(message), privacy: .public) | Details: \(sanitize(error.localizedDescription), privacy: .public)")
        } else {
            logger.error("🛑 [ERROR] \(sanitize(message), privacy: .public)")
        }
    }
    
    /// Masks sensitive strings such as API keys, bearer tokens, or credentials
    private static func sanitize(_ text: String) -> String {
        var result = text
        // Mask Bearer tokens
        result = result.replacingOccurrences(of: "Bearer\\s+[A-Za-z0-9._-]+", with: "Bearer [REDACTED]", options: .regularExpression)
        // Mask keys with sk-... or sb_... prefix
        result = result.replacingOccurrences(of: "(sk-[A-Za-z0-9]{20,})", with: "[SECRET_KEY_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(sbp_[A-Za-z0-9]{20,})", with: "[SUPABASE_KEY_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(AIza[A-Za-z0-9_-]{30,})", with: "[GEMINI_KEY_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(gsk_[A-Za-z0-9]{30,})", with: "[GROQ_KEY_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(sk-or-[A-Za-z0-9._-]+)", with: "[OPENROUTER_KEY_REDACTED]", options: .regularExpression)
        return result
    }
}

/// Standard application error model
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
            return "No network connection. The application is operating in offline mode."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .invalidData(let desc):
            return "Invalid data: \(desc)"
        case .importFailed(let reason):
            return "Could not load data: \(reason)"
        case .syncConflict(let id):
            return "Sync conflict occurred for record \(id)."
        case .unknown(let desc):
            return "Unknown error: \(desc)"
        }
    }
}
