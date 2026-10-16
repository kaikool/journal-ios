import Foundation
import CryptoKit

/// Port 1:1 từ `apps/web/src/server/ids.ts`.
public enum JournalIds {
    
    public static func newId() -> String {
        var bytes = [UInt8](repeating: 0, count: 9)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    public static func nowIso() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
    
    public static func toPrecision12(_ value: Decimal) -> String {
        let d = NSDecimalNumber(decimal: value).doubleValue
        return toPrecision12(d)
    }
    
    public static func toPrecision12(_ d: Double) -> String {
        if d == 0 { return "0.00000000000" }
        let sign = d < 0 ? "-" : ""
        let absD = abs(d)
        let exponent = floor(log10(absD))
        let decimals = 11 - Int(exponent)
        if decimals >= 0 && decimals <= 20 {
            return String(format: "%@%0.*f", sign, decimals, absD)
        } else {
            return String(format: "%@%0.11e", sign, absD)
        }
    }
    
    /// Content hash for execution dedup: identical fills insert once per account.
    /// Port 1:1 từ `apps/web/src/server/ids.ts` `executionHash`.
    public static func executionHash(
        symbol: String,
        side: String,
        quantity: Decimal,
        price: Decimal,
        executedAt: String,
        importMetadataGroup: String? = nil,
        importMetadataId: String? = nil
    ) -> String {
        var parts: [String] = [
            symbol,
            side,
            toPrecision12(quantity),
            toPrecision12(price),
            executedAt
        ]
        if let id = importMetadataId {
            parts.append(contentsOf: ["history", importMetadataGroup ?? "", id])
        }
        let joined = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }
    
    public static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
