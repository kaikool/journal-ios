import Foundation

// MARK: - Parsed Pre-Trade Bias Note Representation
public struct ParsedPreTradeNote: Sendable, Equatable {
    public let orderTicket: String?
    public let symbol: String
    public let bias: String // BUY, SELL, FLAT
    public let plannedEntry: String?
    public let invalidationSL: String?
    public let targetTP: String?
    public let thesisSummary: String
    public let commitmentId: String?
    
    public init(
        orderTicket: String? = nil,
        symbol: String,
        bias: String,
        plannedEntry: String? = nil,
        invalidationSL: String? = nil,
        targetTP: String? = nil,
        thesisSummary: String,
        commitmentId: String? = nil
    ) {
        self.orderTicket = orderTicket
        self.symbol = symbol
        self.bias = bias
        self.plannedEntry = plannedEntry
        self.invalidationSL = invalidationSL
        self.targetTP = targetTP
        self.thesisSummary = thesisSummary
        self.commitmentId = commitmentId
    }
}

// MARK: - Pre-Trade Note Binding Helper
/// Facilitates explicit binding between Order Tickets, Trade Notes, and AI Advisor Commitments.
public struct PreTradeNoteBinding: Sendable {
    public static let tagHeader = "> **[PRE-TRADE BIAS"
    public static let tagFooter = "> <!-- END_PRE_TRADE_BIAS -->"
    
    /// Formats a clean, readable Markdown block to be embedded into trade notes
    public static func formatMarkdownBlock(
        orderTicket: String?,
        commitment: AdvisorCommitmentRecord
    ) -> String {
        let ticketLabel = (orderTicket?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? " • TICKET #\(orderTicket!.replacingOccurrences(of: "#", with: ""))"
            : ""
        var lines: [String] = []
        lines.append("\(tagHeader)\(ticketLabel)]**")
        lines.append("> - **Symbol**: \(commitment.symbol) | **Bias**: \(commitment.bias)")
        if let entry = commitment.plannedEntry, !entry.isEmpty {
            lines.append("> - **Planned Entry**: \(entry)")
        }
        if let sl = commitment.invalidationSL, !sl.isEmpty {
            lines.append("> - **Stop Loss (SL)**: \(sl)")
        }
        if let tp1 = commitment.takeProfit1 ?? commitment.targetTP, !tp1.isEmpty {
            lines.append("> - **Take Profit 1**: \(tp1)")
        }
        if let tp2 = commitment.takeProfit2, !tp2.isEmpty {
            lines.append("> - **Take Profit 2**: \(tp2)")
        }
        if let vol = commitment.volume, !vol.isEmpty {
            lines.append("> - **Volume**: \(vol)")
        }
        if let bal = commitment.balance, !bal.isEmpty {
            lines.append("> - **Balance**: \(bal)")
        }
        if let trigger = commitment.triggerCondition, !trigger.isEmpty {
            lines.append("> - **Trigger Condition**: \(trigger)")
        }
        lines.append("> - **Thesis**: \(commitment.thesisSummary)")
        lines.append("> - **Commitment ID**: `\(commitment.id)`")
        lines.append(tagFooter)
        return lines.joined(separator: "\n")
    }
    
    /// Parses a pre-trade block from a trade's note text
    public static func parseFromNote(_ note: String) -> ParsedPreTradeNote? {
        guard let headerRange = note.range(of: tagHeader) else {
            // Check fallback for any custom header containing PRE-TRADE BIAS
            if let customRange = note.range(of: "PRE-TRADE BIAS", options: .caseInsensitive) {
                return parseFreeform(note, from: customRange.lowerBound)
            }
            return nil
        }
        
        let sub = note[headerRange.lowerBound...]
        let endIdx = sub.range(of: tagFooter)?.upperBound ?? sub.endIndex
        let blockText = String(sub[..<endIdx])
        
        // Extract ticket: TICKET #12345
        var ticket: String? = nil
        if let ticketMatch = blockText.range(of: "TICKET #([0-9a-zA-Z_-]+)", options: .regularExpression) {
            let matched = String(blockText[ticketMatch])
            ticket = matched.replacingOccurrences(of: "TICKET #", with: "").trimmingCharacters(in: .whitespaces)
        }
        
        var symbol = ""
        var bias = "FLAT"
        var entry: String? = nil
        var sl: String? = nil
        var tp: String? = nil
        var summary = ""
        var commitId: String? = nil
        
        let lines = blockText.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("**Symbol**:") {
                let parts = trimmed.components(separatedBy: "|")
                if let symPart = parts.first {
                    symbol = symPart.replacingOccurrences(of: ">", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: "**Symbol**:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                if parts.count > 1 {
                    bias = parts[1].replacingOccurrences(of: "**Bias**:", with: "").trimmingCharacters(in: .whitespaces)
                }
            } else if trimmed.contains("**Planned Entry**:") {
                entry = trimmed.replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "**Planned Entry**:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains("**Stop Loss (SL)**:") {
                sl = trimmed.replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "**Stop Loss (SL)**:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains("**Take Profit (TP)**:") {
                tp = trimmed.replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "**Take Profit (TP)**:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains("**Thesis**:") || trimmed.contains("**Plan Summary**:") {
                summary = trimmed.replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "**Thesis**:", with: "")
                    .replacingOccurrences(of: "**Plan Summary**:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains("**Commitment ID**:") {
                commitId = trimmed.replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "**Commitment ID**:", with: "")
                    .replacingOccurrences(of: "`", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        
        return ParsedPreTradeNote(
            orderTicket: ticket,
            symbol: symbol,
            bias: bias,
            plannedEntry: entry,
            invalidationSL: sl,
            targetTP: tp,
            thesisSummary: summary,
            commitmentId: commitId
        )
    }
    
    private static func parseFreeform(_ note: String, from startIdx: String.Index) -> ParsedPreTradeNote? {
        let sub = String(note[startIdx...])
        var bias = "FLAT"
        if sub.localizedCaseInsensitiveContains("bias: buy") || sub.localizedCaseInsensitiveContains("bias**: buy") {
            bias = "BUY"
        } else if sub.localizedCaseInsensitiveContains("bias: sell") || sub.localizedCaseInsensitiveContains("bias**: sell") {
            bias = "SELL"
        } else if sub.localizedCaseInsensitiveContains("bias: flat") || sub.localizedCaseInsensitiveContains("bias**: flat") || sub.localizedCaseInsensitiveContains("đứng ngoài") {
            bias = "FLAT"
        }
        
        return ParsedPreTradeNote(
            orderTicket: nil,
            symbol: "",
            bias: bias,
            plannedEntry: nil,
            invalidationSL: nil,
            targetTP: nil,
            thesisSummary: sub.prefix(200).description,
            commitmentId: nil
        )
    }
}
