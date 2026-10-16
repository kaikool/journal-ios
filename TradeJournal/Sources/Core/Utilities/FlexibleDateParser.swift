import Foundation

/// Bộ phân tích ngày tháng linh hoạt, chuẩn xác và chịu lỗi cao (Tương thích 100% với Postgres, Supabase, ISO8601, Unix Timestamp)
public enum FlexibleDateParser {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let iso8601Standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private static let pgTimestampWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()
    
    private static let pgTimestampStandard: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        return f
    }()
    
    private static let pgTimestampNoTz: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    /// Phân tích một chuỗi bất kỳ sang `Date` một cách an toàn
    public static func parse(_ string: String?) -> Date? {
        guard let raw = string else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        // 1. ISO 8601 kèm mili-giây (.123Z)
        if let d = iso8601WithFractionalSeconds.date(from: trimmed) {
            return d
        }
        
        // 2. ISO 8601 chuẩn
        if let d = iso8601Standard.date(from: trimmed) {
            return d
        }
        
        // 3. PostgreSQL TIMESTAMPTZ (VD: 2026-10-16 12:34:56.123456+00)
        if let d = pgTimestampWithMillis.date(from: trimmed) {
            return d
        }
        
        // 4. PostgreSQL TIMESTAMP với timezone (VD: 2026-10-16 12:34:56+00)
        if let d = pgTimestampStandard.date(from: trimmed) {
            return d
        }
        
        // 5. PostgreSQL TIMESTAMP không timezone (VD: 2026-10-16 12:34:56)
        if let d = pgTimestampNoTz.date(from: trimmed) {
            return d
        }
        
        // 6. Định dạng chỉ có ngày (VD: 2026-10-16)
        if let d = dateOnlyFormatter.date(from: trimmed) {
            return d
        }
        
        // 7. Unix Epoch Timestamp dạng chuỗi số
        if let num = Double(trimmed) {
            if num > 1_000_000_000_000 { // milliseconds
                return Date(timeIntervalSince1970: num / 1000.0)
            } else if num > 100_000_000 { // seconds
                return Date(timeIntervalSince1970: num)
            }
        }
        
        return nil
    }
}
