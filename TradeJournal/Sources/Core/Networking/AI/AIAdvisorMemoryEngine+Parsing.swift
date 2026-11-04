import Foundation

// MARK: - AI Advisor Memory Engine Parsing & Extraction Helpers
extension AIAdvisorMemoryEngine {
    
    /// Extracts the first decimal number from a string, immune to trailing text annotations like "2740 (D1 PDH)" or "2730 (EMA 21)".
    public static func extractFirstPrice(from text: String) -> Decimal? {
        let sanitized = text.replacingOccurrences(of: ",", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:\.[0-9]+)?"#) else { return nil }
        let ns = sanitized as NSString
        guard let match = regex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return Decimal(string: ns.substring(with: match.range))
    }
    
    /// Parses an AI analysis output string into a structured AdvisorCommitmentRecord with discrete setup fields.
    public func extractCommitment(
        from analysisText: String,
        symbol: String,
        fallbackBalance: String? = nil,
        fallbackVolume: String? = nil,
        accountBalance: Decimal? = nil,
        riskPercentage: Decimal? = nil,
        targetRiskRewardRatio: Double? = nil
    ) -> AdvisorCommitmentRecord {
        var bias = "FLAT"
        var entry: String? = nil
        var sl: String? = nil
        var tp1: String? = nil
        var tp2: String? = nil
        var volume: String? = fallbackVolume
        var balance: String? = fallbackBalance
        var rrRatio: String? = nil
        var trigger: String? = nil
        
        // 1. Structured JSON Extraction (First priority)
        if let jsonStart = analysisText.range(of: "{"),
           let jsonEnd = analysisText.range(of: "}", options: .backwards),
           jsonStart.lowerBound < jsonEnd.lowerBound {
            let jsonString = String(analysisText[jsonStart.lowerBound...jsonEnd.lowerBound])
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let d = obj["direction"] as? String {
                    let u = d.uppercased()
                    bias = u.contains("BUY") ? "BUY" : (u.contains("SELL") ? "SELL" : "FLAT")
                }
                if let e = obj["entry"] { entry = "\(e)" }
                if let s = obj["stopLoss"] { sl = "\(s)" }
                if let t1 = obj["takeProfit1"] { tp1 = "\(t1)" }
                if let t2 = obj["takeProfit2"] { tp2 = "\(t2)" }
                if let v = obj["volume"] { volume = "\(v)" }
                if let rr = obj["riskRewardRatio"] { rrRatio = "\(rr)" }
                if let trig = obj["trigger"] as? String { trigger = trig }
            }
        }
        
        // 2. Line-by-Line Regex Fallback Parser
        func cleanField(_ raw: String) -> String {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "^[-•*\\s>\\[\\]]+", with: "", options: .regularExpression)
            if let colonIdx = s.firstIndex(of: ":") {
                let after = s[s.index(after: colonIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty { s = after }
            }
            s = s.replacingOccurrences(of: "[*`\\[\\]]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return s
        }
        
        let lines = analysisText.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Direction / Bias
            if lower.contains("direction:") || lower.contains("hướng:") || lower.contains("bias:") || lower.contains("kết luận:") || lower.contains("verdict:") {
                if lower.contains("sell") || lower.contains("short") || lower.contains("bán") {
                    bias = "SELL"
                } else if lower.contains("buy") || lower.contains("long") || lower.contains("mua") {
                    bias = "BUY"
                } else if lower.contains("flat") || lower.contains("đứng ngoài") || lower.contains("stand aside") {
                    bias = "FLAT"
                }
            }
            
            // Balance
            if lower.contains("balance:") || lower.contains("số dư:") || lower.contains("vốn:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    balance = val
                }
            }
            
            // Entry
            if entry == nil, lower.contains("entry:") || lower.contains("optimal entry") || lower.contains("điểm vào") || lower.contains("vùng vào lệnh") || lower.contains("vào lệnh tại:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    entry = val
                }
            }
            
            // Stop Loss
            if sl == nil, lower.contains("stop loss:") || lower.contains("sl:") || lower.contains("cắt lỗ:") || lower.contains("invalidation:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    sl = val
                }
            }
            
            // Take Profit 1
            if tp1 == nil, lower.contains("take profit 1:") || lower.contains("tp 1:") || lower.contains("tp1:") || lower.contains("chốt lời 1:") || lower.contains("mục tiêu 1:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    tp1 = val
                }
            } else if tp1 == nil && (lower.contains("target tp:") || lower.contains("targets:") || lower.contains("mục tiêu chốt lời:") || lower.contains("take profit:")) && !lower.contains("tp 2") && !lower.contains("tp2") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    tp1 = val
                }
            }
            
            // Take Profit 2
            if tp2 == nil, lower.contains("take profit 2:") || lower.contains("tp 2:") || lower.contains("tp2:") || lower.contains("chốt lời 2:") || lower.contains("mục tiêu 2:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && !val.lowercased().contains("không") && !val.lowercased().contains("none") && !val.lowercased().contains("n/a") {
                    tp2 = val
                }
            }
            
            // Volume
            if volume == fallbackVolume, lower.contains("volume:") || lower.contains("khối lượng:") || lower.contains("lot:") || lower.contains("size:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    volume = val
                }
            }
            
            // R:R
            if rrRatio == nil, lower.contains("r:r") || lower.contains("risk/reward") || lower.contains("tỷ lệ r:r") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    rrRatio = val
                }
            }
            
            // Trigger
            if trigger == nil, lower.contains("điều kiện kích hoạt:") || lower.contains("trigger:") || lower.contains("điều kiện cần chờ:") {
                trigger = cleanField(trimmed)
            }
        }
        
        // 3. Mathematical Verification of Volume and R:R via AssetContractEngine
        if let entryStr = entry, let slStr = sl {
            if let eNum = Self.extractFirstPrice(from: entryStr),
               let sNum = Self.extractFirstPrice(from: slStr),
               eNum > 0, sNum > 0, eNum != sNum {
                var balNum = accountBalance
                if balNum == nil, let bStr = balance ?? fallbackBalance {
                    balNum = Self.extractFirstPrice(from: bStr)
                }
                let activeRiskPct = riskPercentage ?? Decimal(1)
                if let b = balNum, b > 0 {
                    if let size = AssetContractEngine.calculatePositionSize(
                        symbol: symbol,
                        balance: b,
                        riskPercentage: activeRiskPct,
                        entryPrice: eNum,
                        stopLoss: sNum
                    ) {
                        volume = String(format: "%.2f lots (Rủi ro $%.2f)", (size.lots as NSDecimalNumber).doubleValue, (size.riskAmount as NSDecimalNumber).doubleValue)
                    }
                }
                
                let riskDist = abs(eNum - sNum)
                if let tpStr = tp1, let tNum = Self.extractFirstPrice(from: tpStr), tNum > 0 {
                    let rewardDist = abs(tNum - eNum)
                    if riskDist > 0 {
                        let calculatedRR = (rewardDist / riskDist as NSDecimalNumber).doubleValue
                        rrRatio = String(format: "1:%.1f", calculatedRR)
                    }
                } else if let targetRR = targetRiskRewardRatio, targetRR > 0 {
                    rrRatio = String(format: "1:%.1f", targetRR)
                }
            }
        }
        
        // Summary
        let nonHeaders = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        let summary = nonHeaders.prefix(3).joined(separator: " ")
        
        return AdvisorCommitmentRecord(
            symbol: symbol,
            bias: bias,
            plannedEntry: entry,
            invalidationSL: sl,
            targetTP: tp1,
            takeProfit1: tp1,
            takeProfit2: tp2,
            volume: volume,
            balance: balance,
            riskRewardRatio: rrRatio,
            triggerCondition: trigger,
            thesisSummary: summary.isEmpty ? analysisText.prefix(200).description : summary
        )
    }
}
