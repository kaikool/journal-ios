import Foundation

/// Domain specification matching core web repository for robust date parsing.
/// Highly optimized with an internal thread-safe NSCache and fast-path ISO8601 / SQL parsers
/// to ensure 0ms latency during high-volume batch syncs and UI table rendering.
public enum FlexibleDateParser {
    private static let parseCache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 4096
        return cache
    }()

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

    private static let fastDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let fastSqlDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let fallbackDateRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\d{4})[-/.](\d{2})[-/.](\d{2})"#)
    }()

    private static let formatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssX",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSSX",
            "yyyy-MM-dd HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSX",
            "yyyy-MM-dd HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ssX",
            "yyyy-MM-dd HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy.MM.dd HH:mm",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm",
            "dd.MM.yyyy HH:mm:ss",
            "dd.MM.yyyy HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd"
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = pattern
            return f
        }
    }()
    
    /// Safely parses an arbitrary date string into `Date` with instant O(1) cache lookups
    public static func parse(_ string: String?) -> Date? {
        guard let raw = string else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        let key = trimmed as NSString
        if let cached = parseCache.object(forKey: key) {
            return cached as Date
        }
        
        guard let parsed = internalParse(trimmed) else {
            return nil
        }
        parseCache.setObject(parsed as NSDate, forKey: key)
        return parsed
    }
    
    private static func internalParse(_ trimmed: String) -> Date? {
        // 1. Unix Epoch Timestamp numeric string
        if let num = Double(trimmed) {
            if num > 1_000_000_000_000 { // milliseconds
                return Date(timeIntervalSince1970: num / 1000.0)
            } else if num > 100_000_000 { // seconds
                return Date(timeIntervalSince1970: num)
            }
        }

        // 2. Fast-path: Pure ISO Date (yyyy-MM-dd, 10 chars)
        if trimmed.count == 10, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-" {
            if let d = fastDayFormatter.date(from: trimmed) {
                return d
            }
        }

        // 3. Fast-path: Standard SQL DateTime (yyyy-MM-dd HH:mm:ss, 19 chars)
        if trimmed.count == 19, trimmed.contains(" ") {
            if let d = fastSqlDateTimeFormatter.date(from: trimmed) {
                return d
            }
        }

        // 4. Fast-path: ISO8601 Direct Checks (with microsecond truncation for Supabase/Postgres)
        var candidate = trimmed
        if let spaceIdx = candidate.firstIndex(of: " "), candidate.distance(from: candidate.startIndex, to: spaceIdx) == 10 {
            candidate.replaceSubrange(spaceIdx...spaceIdx, with: "T")
        }
        
        // Truncate >3 fraction digits (e.g. .123456+00:00 -> .123+00:00) so ISO8601 parser succeeds instantly
        if let dotIdx = candidate.firstIndex(of: ".") {
            let afterDot = candidate[dotIdx...]
            let nonDigitIdx = afterDot.firstIndex(where: { !$0.isNumber && $0 != "." }) ?? candidate.endIndex
            let fractionPart = String(candidate[dotIdx..<nonDigitIdx])
            if fractionPart.count > 4 { // . + >3 digits
                let truncatedFraction = String(fractionPart.prefix(4))
                candidate.replaceSubrange(dotIdx..<nonDigitIdx, with: truncatedFraction)
            }
        }

        if let d = iso8601WithFractionalSeconds.date(from: candidate) {
            return d
        }
        if let d = iso8601Standard.date(from: candidate) {
            return d
        }
        if candidate != trimmed {
            if let d = iso8601WithFractionalSeconds.date(from: trimmed) {
                return d
            }
            if let d = iso8601Standard.date(from: trimmed) {
                return d
            }
        }

        // 5. Normalize common date string representations (/ or .)
        var normalized = trimmed
        if normalized.count >= 10 {
            let prefix = String(normalized.prefix(10))
            if prefix.contains(".") {
                normalized = normalized.replacingOccurrences(of: ".", with: "-", range: normalized.startIndex..<normalized.index(normalized.startIndex, offsetBy: 10))
            } else if prefix.contains("/") {
                normalized = normalized.replacingOccurrences(of: "/", with: "-", range: normalized.startIndex..<normalized.index(normalized.startIndex, offsetBy: 10))
            }
        }

        var tNormalized = normalized
        if let spaceIdx = normalized.firstIndex(of: " "), normalized.distance(from: normalized.startIndex, to: spaceIdx) == 10 {
            tNormalized.replaceSubrange(spaceIdx...spaceIdx, with: "T")
        }

        // 6. Try standard formatters
        for f in formatters {
            if let d = f.date(from: normalized) {
                return d
            }
            if tNormalized != normalized, let d = f.date(from: tNormalized) {
                return d
            }
        }

        // 7. Fallback date extraction: If we can extract YYYY-MM-DD from the string, return that day
        if let regex = fallbackDateRegex,
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let yRange = Range(match.range(at: 1), in: trimmed),
           let mRange = Range(match.range(at: 2), in: trimmed),
           let dRange = Range(match.range(at: 3), in: trimmed),
           let y = Int(trimmed[yRange]), let m = Int(trimmed[mRange]), let d = Int(trimmed[dRange]) {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = 12
            comps.minute = 0
            comps.second = 0
            comps.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = Calendar(identifier: .gregorian).date(from: comps) {
                return date
            }
        }

        return nil
    }
    
    /// Checks whether two date strings represent dates within `maxDays` days of each other (useful for cross-timezone matching).
    public static func areDatesClose(_ d1Str: String?, _ d2Str: String?, maxDays: Int = 1) -> Bool {
        guard let s1 = d1Str, let s2 = d2Str, !s1.isEmpty, !s2.isEmpty else { return false }
        if s1 == s2 { return true }
        guard let d1 = parse(s1), let d2 = parse(s2) else { return false }
        let diffSecs = abs(d1.timeIntervalSince(d2))
        return diffSecs <= Double(maxDays * 86400 + 7200) // maxDays + 2hr buffer for DST/tz
    }
}
