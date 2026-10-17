import Foundation

/// Domain specification matching core web repository for robust date parsing
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
    
    /// Safely parses an arbitrary date string into `Date`
    public static func parse(_ string: String?) -> Date? {
        guard let raw = string else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        // 1. Unix Epoch Timestamp numeric string
        if let num = Double(trimmed) {
            if num > 1_000_000_000_000 { // milliseconds
                return Date(timeIntervalSince1970: num / 1000.0)
            } else if num > 100_000_000 { // seconds
                return Date(timeIntervalSince1970: num)
            }
        }

        // 2. Direct ISO8601 checks
        if let d = iso8601WithFractionalSeconds.date(from: trimmed) {
            return d
        }
        if let d = iso8601Standard.date(from: trimmed) {
            return d
        }

        // 3. Normalize common date string representations
        // If string matches YYYY.MM.DD or YYYY/MM/DD, normalize separator
        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if prefix.contains(".") {
                trimmed = trimmed.replacingOccurrences(of: ".", with: "-", range: trimmed.startIndex..<trimmed.index(trimmed.startIndex, offsetBy: 10))
            } else if prefix.contains("/") {
                trimmed = trimmed.replacingOccurrences(of: "/", with: "-", range: trimmed.startIndex..<trimmed.index(trimmed.startIndex, offsetBy: 10))
            }
        }

        // If space between date and time (YYYY-MM-DD HH:mm:ss), also test normalized 'T' version
        var tNormalized = trimmed
        if let spaceIdx = trimmed.firstIndex(of: " "), trimmed.distance(from: trimmed.startIndex, to: spaceIdx) == 10 {
            tNormalized.replaceSubrange(spaceIdx...spaceIdx, with: "T")
        }

        // Try standard formatters on both original and T-normalized
        for f in formatters {
            if let d = f.date(from: trimmed) {
                return d
            }
            if tNormalized != trimmed, let d = f.date(from: tNormalized) {
                return d
            }
        }

        // 4. Truncate microsecond fractions (>3 digits) to 3 digits for ISO8601
        // e.g. 2026-10-15T12:34:56.123456+00:00 -> 2026-10-15T12:34:56.123+00:00
        if let dotIdx = tNormalized.firstIndex(of: ".") {
            let afterDot = tNormalized[dotIdx...]
            let nonDigitIdx = afterDot.firstIndex(where: { !$0.isNumber && $0 != "." }) ?? tNormalized.endIndex
            let fractionPart = String(tNormalized[dotIdx..<nonDigitIdx])
            if fractionPart.count > 4 { // . + >3 digits
                let truncatedFraction = String(fractionPart.prefix(4))
                var truncatedString = tNormalized
                truncatedString.replaceSubrange(dotIdx..<nonDigitIdx, with: truncatedFraction)
                if let d = iso8601WithFractionalSeconds.date(from: truncatedString) {
                    return d
                }
                for f in formatters {
                    if let d = f.date(from: truncatedString) {
                        return d
                    }
                }
            }
        }

        // 5. Fallback date extraction: If we can extract YYYY-MM-DD from the string, return that day
        let regex = try? NSRegularExpression(pattern: #"(\d{4})[-/.](\d{2})[-/.](\d{2})"#)
        if let match = regex?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let yRange = Range(match.range(at: 1), in: raw),
           let mRange = Range(match.range(at: 2), in: raw),
           let dRange = Range(match.range(at: 3), in: raw),
           let y = Int(raw[yRange]), let m = Int(raw[mRange]), let d = Int(raw[dRange]) {
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
}
