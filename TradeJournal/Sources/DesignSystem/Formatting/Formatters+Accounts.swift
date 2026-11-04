import Foundation

// MARK: - Account & Reference Clean Formatters
extension Formatters {
    // MARK: - Account & Reference Clean Formatters
    
    /// Cleans raw broker/prop labels into standardized, professional account titles:
    /// e.g. "HighStakes Phase 1 · $100K · #123456"
    public static func cleanAccountName(_ raw: String, balance: Decimal? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Trading Account" }
        
        // 1. Split existing delimited strings (' - ', ' · ', ' • ', ' | ') and perform smart deduplication
        let normalizedDelimiters: String = {
            var s = trimmed
            s = s.replacingOccurrences(of: " · ", with: " - ")
            s = s.replacingOccurrences(of: " • ", with: " - ")
            s = s.replacingOccurrences(of: " | ", with: " - ")
            // Standardize any dash with or without surrounding spaces e.g. " -$50K", "-50K", " - 1"
            let dashPattern = #"\s*-\s*"#
            if let regex = try? NSRegularExpression(pattern: dashPattern) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " - ")
            }
            return s
        }()
        let rawParts = normalizedDelimiters.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var deduplicatedParts: [String] = []
        for part in rawParts {
            let pLower = part.lowercased()
            // Skip raw platform placeholders if they appear as separate segments
            if (pLower.hasPrefix("meta-trader") || pLower.hasPrefix("c-trader") || pLower.hasPrefix("account the5ers_")) && rawParts.count > 1 {
                continue
            }
            let pNorm = pLower.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: "")
            
            let isDupe = deduplicatedParts.contains { existing in
                let eNorm = existing.lowercased()
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if eNorm == pNorm { return true }
                // If one contains the other (e.g. "highstakes50k" contains "highstakes" or "50k")
                if pNorm.count >= 3 && eNorm.contains(pNorm) { return true }
                if eNorm.count >= 3 && pNorm.contains(eNorm) { return true }
                return false
            }
            
            if !isDupe {
                deduplicatedParts.append(part)
            } else {
                // If the incoming part is more descriptive (e.g. "High Stakes 50K" vs "High Stakes"), upgrade it
                if let idx = deduplicatedParts.firstIndex(where: { existing in
                    let eNorm = existing.lowercased()
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    return pNorm.count > eNorm.count && pNorm.contains(eNorm)
                }) {
                    deduplicatedParts[idx] = part
                }
            }
        }
        
        let candidate = deduplicatedParts.joined(separator: " · ")
        let lower = candidate.lowercased()
        
        // Check if any word of 4+ characters repeats in the candidate (e.g. "highstakes" repeating)
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 }
        let hasRepeatingWord = Set(words).count != words.count
        
        // Only preserve if candidate is strictly in standard " · " format, has no hyphens or duplicate words
        let isAlreadyClean = trimmed.contains(" · ") && !trimmed.contains("-") && !hasRepeatingWord && !lower.contains("meta-trader") && !lower.contains("c-trader") && !lower.hasPrefix("the5ers_")
        if isAlreadyClean && deduplicatedParts.count >= 2 {
            return candidate
        }
        
        let isRawIdOrPrefix = lower.hasPrefix("account the5ers_") ||
                              lower.hasPrefix("account ") ||
                              lower.hasPrefix("the5ers_")
        
        let isRawPlatform = lower.contains("meta-trader") ||
                            lower.contains("meta-trade") ||
                            lower.contains("metatrader") ||
                            lower.contains("c-trader") ||
                            lower.contains("ctrader") ||
                            lower.contains("trader-evolution") ||
                            lower.contains("traderevolution") ||
                            isRawIdOrPrefix
        
        guard isRawPlatform || lower.contains("phase") || lower.contains("step") || lower.contains("stakes") || lower.contains("bootcamp") || lower.contains("growth") else {
            return candidate
        }
        
        let platformTag: String
        if lower.contains("meta-trader-5") || lower.contains("meta-trade-5") || lower.contains("mt5") {
            platformTag = "MT5"
        } else if lower.contains("meta-trader-4") || lower.contains("meta-trade-4") || lower.contains("mt4") {
            platformTag = "MT4"
        } else if lower.contains("c-trader") || lower.contains("ctrader") {
            platformTag = "cTrader"
        } else if lower.contains("trader-evolution") || lower.contains("traderevolution") {
            platformTag = "TraderEvolution"
        } else {
            platformTag = "MT5"
        }
        
        var suffix = ""
        let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            suffix = String(trimmed[range])
        }
        
        let pkg: String = {
            if lower.contains("high stakes") || lower.contains("highstakes") || lower.contains("high-stakes") || lower.contains("high steaks") || lower.contains("highsteaks") {
                return "High Stakes"
            }
            if lower.contains("hyper growth") || lower.contains("hypergrowth") || lower.contains("hyper-growth") {
                return "Hyper Growth"
            }
            if lower.contains("bootcamp") || lower.contains("boot camp") {
                return "Bootcamp"
            }
            if lower.contains("instant") {
                return "Instant Funding"
            }
            if lower.hasPrefix("ftmo") {
                return "FTMO \(platformTag)"
            }
            return "The5ers \(platformTag)"
        }()
        
        let phase: String = {
            if lower.contains("step 2") || lower.contains("step2") || lower.contains("phase 2") || lower.contains("phase2") || lower.contains("verification") ||
               lower.contains("- 2 -") || lower.contains("- 2-") || lower.contains("-2-") || lower.contains(" - 2 ") || lower.hasSuffix("- 2") || lower.hasSuffix("-2") {
                return "Phase 2"
            }
            if lower.contains("step 3") || lower.contains("step3") || lower.contains("phase 3") || lower.contains("phase3") ||
               lower.contains("- 3 -") || lower.contains("- 3-") || lower.contains("-3-") || lower.contains(" - 3 ") || lower.hasSuffix("- 3") || lower.hasSuffix("-3") {
                return "Phase 3"
            }
            if lower.contains("funded") || lower.contains("live") || lower.contains("master") || pkg == "Instant Funding" {
                return "Funded"
            }
            if lower.contains("step 1") || lower.contains("step1") || lower.contains("phase 1") || lower.contains("phase1") || lower.contains("evaluation") ||
               lower.contains("- 1 -") || lower.contains("- 1-") || lower.contains("-1-") || lower.contains(" - 1 ") || lower.hasSuffix("- 1") || lower.hasSuffix("-1") {
                return "Phase 1"
            }
            return ""
        }()
        
        var components: [String] = [pkg]
        if !phase.isEmpty && phase != pkg {
            components.append(phase)
        }
        
        // Extract size from balance or raw string e.g. "50K", "$100k"
        let sizeCandidate: String? = {
            if let b = balance, b > 0 {
                let bInt = NSDecimalNumber(decimal: b).intValue
                if bInt >= 1000 && bInt % 1000 == 0 {
                    return "$\(bInt / 1000)K"
                }
                return "$\(bInt)"
            }
            if let regex = try? NSRegularExpression(pattern: #"(?i)\$?(\d{1,4})\s*k\b"#),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                return "$\(trimmed[range].uppercased())K"
            }
            return nil
        }()
        if let sz = sizeCandidate {
            let sizeBare = sz.replacingOccurrences(of: "$", with: "").lowercased()
            let alreadyHasSize = components.contains { c in
                c.replacingOccurrences(of: "$", with: "").lowercased().contains(sizeBare)
            }
            if !alreadyHasSize {
                components.append(sz)
            }
        }
        
        if !suffix.isEmpty {
            let sNorm = suffix.replacingOccurrences(of: "#", with: "")
            if !components.contains(where: { $0.contains(sNorm) }) {
                components.append("#\(sNorm)")
            }
        }
        
        var finalCleaned: [String] = []
        for c in components {
            let cNorm = c.lowercased()
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")
            let exists = finalCleaned.contains { existing in
                let eNorm = existing.lowercased()
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: " ", with: "")
                return eNorm == cNorm || (cNorm.count >= 4 && eNorm.contains(cNorm)) || (eNorm.count >= 4 && cNorm.contains(eNorm))
            }
            if !exists {
                finalCleaned.append(c)
            }
        }
        return finalCleaned.joined(separator: " · ")
    }
    
    /// Produces a concise account label tailored for tight navigation bars (e.g. "HighStakes P1 · $50K" or "cTrader #7657")
    public static func compactAccountName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Account" }
        
        // Handle dash-separated format: [Package, Phase, Size, #Number]
        let sep = trimmed.contains(" - ") ? " - " : (trimmed.contains(" · ") ? " · " : "")
        if !sep.isEmpty {
            let parts = trimmed.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 4, let p0Raw = parts.first {
                let p0 = p0Raw.replacingOccurrences(of: " ", with: "")
                let p1 = parts[1].replacingOccurrences(of: "Phase ", with: "P").replacingOccurrences(of: "Step ", with: "P")
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 3, let p0Raw = parts.first {
                let p0 = p0Raw.replacingOccurrences(of: " ", with: "")
                let p1 = parts[1]
                let p2 = parts[2]
                return "\(p0) \(p1) · \(p2)"
            } else if parts.count == 2, let p0 = parts.first, let p1 = parts.last {
                return "\(p0) \(p1)"
            }
        }
        
        let cleaned = cleanAccountName(trimmed)
        if cleaned.contains(" - ") {
            return compactAccountName(cleaned)
        }
        return cleaned
    }
    
    /// Formats technical UUIDs, SHA256 hashes, or internal database keys into clean references
    public static func formatReference(_ ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        if trimmed.hasPrefix("the5ers_purchase_") {
            let hash = String(trimmed.dropFirst("the5ers_purchase_".count))
            return "Order #\(hash.prefix(8))"
        }
        if trimmed.hasPrefix("the5ers_payout_") {
            let hash = String(trimmed.dropFirst("the5ers_payout_".count))
            return "Payout #\(hash.prefix(8))"
        }
        if trimmed.hasPrefix("the5ers_received_") || trimmed.hasPrefix("the5ers_rcpt_") {
            let rest = trimmed.components(separatedBy: "_").last ?? trimmed
            return "Receipt #\(rest.prefix(8))"
        }
        if trimmed.hasPrefix("THE5ERS-") {
            let rest = String(trimmed.dropFirst("THE5ERS-".count))
            return "THE5ERS #\(rest.prefix(8))"
        }
        if trimmed.count > 24 && !trimmed.contains(" ") {
            return "#\(trimmed.prefix(8))"
        }
        return trimmed
    }
    
    /// Formats entity IDs cleanly
    public static func formatEntityId(_ id: String) -> String {
        if id.hasPrefix("the5ers_") {
            let sub = String(id.dropFirst(8))
            return sub.count > 12 ? "#\(sub.prefix(8))" : sub
        }
        if id.count > 16 {
            return "#\(id.prefix(8))"
        }
        return id
    }
    
    /// Formats raw ISO date strings or day strings into clean human-readable date (e.g. "Oct 1, 2026")
    public static func formatDisplayDate(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Pending settlement"
        }
        if let d = isoFractionalFormatter.date(from: raw) {
            return dateOnly(d)
        }
        if let d = isoBasicFormatter.date(from: raw) {
            return dateOnly(d)
        }
        if let d = date(fromIsoDay: raw) {
            return dateOnly(d)
        }
        return raw
    }
    
    /// Cleans verbose or system-generated notes from prop transactions (e.g. stripping ISO order timestamps)
    public static func cleanTransactionNote(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parenIndex = cleaned.range(of: " (The5ers official order") {
            cleaned = String(cleaned[..<parenIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let parenIndex = cleaned.range(of: " (The5ers") {
            cleaned = String(cleaned[..<parenIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }
}