import Foundation

// MARK: - The5ers Payouts & Settlement Receipts Synchronization
extension The5ersService {
    internal func isLikelyPayoutDictionary(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        let hasAmount = keys.contains("amount") || keys.contains("payoutamount") || keys.contains("netamount") ||
                        keys.contains("grossamount") || keys.contains("grossprofit") || keys.contains("receivedamount") ||
                        keys.contains("withdrawalamount") || keys.contains("paidamount") || keys.contains("netpaid") ||
                        keys.contains("finalamount") || keys.contains("usershare")
        let hasIdentity = keys.contains("payoutid") || keys.contains("withdrawalid") || keys.contains("requestid") ||
                          keys.contains("id") || keys.contains("ref")
        let hasDate = keys.contains("requestedat") || keys.contains("completedat") || keys.contains("paymentdate") ||
                      keys.contains("settledat") || keys.contains("paidat") || keys.contains("date") || keys.contains("createdat")
        let hasStatus = keys.contains("status") || keys.contains("method")
        return hasAmount && (hasIdentity || hasDate || hasStatus)
    }
    
    internal func extractAnyPayoutCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPayoutCollection(from: parsed)
            }
            return []
        }
        if let dict = unwrapped as? [String: Any] {
            if let data = dict["data"] as? [String: Any] {
                if let p = data["payouts"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["payout_history"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["history"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["requests"] as? [[String: Any]], !p.isEmpty { return p }
            }
            if let p = dict["payouts"] as? [[String: Any]], !p.isEmpty { return p }
            if let p = dict["payout_history"] as? [[String: Any]], !p.isEmpty { return p }
            if isLikelyPayoutDictionary(dict) {
                return [dict]
            }
            let possibleKeys = [
                "payouts", "withdrawals", "items", "history", "notifications",
                "data", "rows", "records", "payout_history", "list", "results",
                "transfers", "payments", "transactions", "payoutRequests", "requests", "settlements"
            ]
            for k in possibleKeys {
                if let arr = dict[k] as? [[String: Any]], !arr.isEmpty {
                    return arr
                }
                if let subDict = dict[k] as? [String: Any] {
                    let sub = extractAnyPayoutCollection(from: subDict)
                    if !sub.isEmpty { return sub }
                }
            }
            if let res = dict["result"] {
                let sub = extractAnyPayoutCollection(from: res)
                if !sub.isEmpty { return sub }
            }
        }
        if let arr = unwrapped as? [[String: Any]] {
            return arr.filter { isLikelyPayoutDictionary($0) }
        }
        return []
    }
    
    @MainActor
    internal func syncPayouts(
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount]
    ) async {
        lastStatus = "Loading withdrawal and payout history from the5ers_wallet & the5ers_payout..."
        guard !targetAccounts.isEmpty else { return }
        
        // 1. Query authoritative customer-wide withdrawal summary from `the5ers_wallet.overview`
        var walletTotalPaidOut: Decimal? = nil
        var walletPaidCount: Int? = nil
        var walletPendingCount: Int? = nil
        var walletLastPaidAmount: Decimal? = nil
        var walletLastPaidAt: String? = nil
        
        if let wRes = try? await callMcpTool(name: "the5ers_wallet", arguments: [
            "operation": "overview",
            "contract_version": "1.0"
        ]), !(wRes["isError"] as? Bool ?? false) {
            let uWallet = unwrapMcpToolResult(wRes)
            if let wData = (uWallet as? [String: Any])?["data"] as? [String: Any] ?? uWallet as? [String: Any],
               let withdrawals = wData["withdrawals"] as? [String: Any] {
                walletTotalPaidOut = sourceNumber(withdrawals["totalPaidOut"] ?? withdrawals["total_paid_out"])
                walletPaidCount = extractRequirementInt(withdrawals["paidCount"] ?? withdrawals["paid_count"])
                walletPendingCount = extractRequirementInt(withdrawals["pendingCount"] ?? withdrawals["pending_count"])
                walletLastPaidAmount = sourceNumber(withdrawals["lastPaidAmount"] ?? withdrawals["last_paid_amount"])
                walletLastPaidAt = withdrawals["lastPaidAt"] as? String ?? (withdrawals["last_paid_at"] as? String)
            }
        }
        
        let fundedOrProfitableAccounts = targetAccounts.filter { acc in
            let l = "\(acc.program) \(acc.label) \(acc.status)".lowercased()
            return l.contains("fund") || l.contains("instant") || l.contains("live") || l.contains("master") ||
                   l.contains("pass") || l.contains("step 3") || l.contains("phase 3") ||
                   (acc.profitAndLoss ?? 0) > 0
        }
        let candidateAccounts = fundedOrProfitableAccounts.isEmpty ? targetAccounts : fundedOrProfitableAccounts
        
        var allRawPayouts: [[String: Any]] = []
        var seenPayoutIds = Set<String>()
        var accountSplitMap: [String: Double] = [:]
        
        for acc in candidateAccounts {
            if Task.isCancelled || isCancelledByUser { break }
            
            // A. Query 'eligibility' for userPayoutPercentage (e.g. 80.0, 85.0, 100.0)
            let eligArgs: [String: Any] = [
                "operation": "eligibility",
                "account_ref": acc.ref,
                "contract_version": "1.0"
            ]
            if let eligRes = try? await callMcpTool(name: "the5ers_payout", arguments: eligArgs),
               !(eligRes["isError"] as? Bool ?? false) {
                let unwrapped = unwrapMcpToolResult(eligRes)
                if let eDict = (unwrapped as? [String: Any])?["data"] as? [String: Any] ?? unwrapped as? [String: Any] {
                    if let split = eDict["userPayoutPercentage"] as? NSNumber {
                        accountSplitMap[acc.ref] = split.doubleValue
                    }
                }
            }
            
            // B. Query 'explain' for recorded split breakdown and traderSplitPercent
            var latestPayoutDict: [String: Any]? = nil
            let explainArgs: [String: Any] = [
                "operation": "explain",
                "account_ref": acc.ref,
                "contract_version": "1.0"
            ]
            if let explainRes = try? await callMcpTool(name: "the5ers_payout", arguments: explainArgs),
               !(explainRes["isError"] as? Bool ?? false) {
                let unwrappedExplain = unwrapMcpToolResult(explainRes)
                if let expDict = (unwrappedExplain as? [String: Any])?["data"] as? [String: Any] ?? unwrappedExplain as? [String: Any] {
                    if let avail = expDict["available"] as? [String: Any] {
                        if let split = avail["traderSplitPercent"] as? NSNumber ?? avail["userPayoutPercentage"] as? NSNumber {
                            accountSplitMap[acc.ref] = split.doubleValue
                        }
                    }
                    if let latest = expDict["latestPayout"] as? [String: Any] {
                        var p = latest
                        if p["account_ref"] == nil { p["account_ref"] = acc.ref }
                        if p["currency"] == nil { p["currency"] = acc.currency }
                        if let b = latest["breakdown"] as? [String: Any] {
                            for (k, v) in b { p[k] = v }
                        }
                        latestPayoutDict = p
                    }
                }
            }
            
            // C. Query 'history' for past payouts (paginated across pages 1...5)
            var historyPayouts: [[String: Any]] = []
            for page in 1...5 {
                let histArgs: [String: Any] = [
                    "operation": "history",
                    "account_ref": acc.ref,
                    "page": page,
                    "limit": 50,
                    "contract_version": "1.0"
                ]
                if let histRes = try? await callMcpTool(name: "the5ers_payout", arguments: histArgs),
                   !(histRes["isError"] as? Bool ?? false) {
                    let unwrappedHist = unwrapMcpToolResult(histRes)
                    let rows = extractAnyPayoutCollection(from: unwrappedHist)
                    if rows.isEmpty { break }
                    for var r in rows {
                        if r["account_ref"] == nil { r["account_ref"] = acc.ref }
                        if r["currency"] == nil { r["currency"] = acc.currency }
                        if let s = accountSplitMap[acc.ref], r["split_percent"] == nil {
                            r["split_percent"] = s
                        }
                        // If this history payout matches latestPayout, enrich with detailed breakdown
                        if let latest = latestPayoutDict {
                            let histReq = String(describing: r["requestedAt"] ?? r["requested_at"] ?? "")
                            let latestReq = String(describing: latest["requestedAt"] ?? latest["requested_at"] ?? "")
                            let histAmt = String(describing: r["amount"] ?? "")
                            let latestAmt = String(describing: latest["amount"] ?? "")
                            if (!histReq.isEmpty && histReq == latestReq) || (!histAmt.isEmpty && histAmt == latestAmt) {
                                for (k, v) in latest {
                                    if r[k] == nil { r[k] = v }
                                }
                            }
                        }
                        historyPayouts.append(r)
                    }
                    if rows.count < 50 { break }
                } else {
                    break
                }
            }
            
            if !historyPayouts.isEmpty {
                for p in historyPayouts {
                    let reqDate = String(describing: p["requestedAt"] ?? p["requested_at"] ?? "")
                    let amt = String(describing: p["amount"] ?? "")
                    let pId = String(describing: p["id"] ?? p["payout_id"] ?? p["withdrawalid"] ?? "\(acc.ref)_\(reqDate)_\(amt)")
                    if !seenPayoutIds.contains(pId) {
                        seenPayoutIds.insert(pId)
                        allRawPayouts.append(p)
                    }
                }
            } else if let latest = latestPayoutDict {
                let reqDate = String(describing: latest["requestedAt"] ?? latest["requested_at"] ?? "")
                let amt = String(describing: latest["amount"] ?? "")
                let pId = String(describing: latest["id"] ?? latest["payout_id"] ?? latest["withdrawalid"] ?? "\(acc.ref)_\(reqDate)_\(amt)")
                if !seenPayoutIds.contains(pId) {
                    seenPayoutIds.insert(pId)
                    allRawPayouts.append(latest)
                }
            }
        }
        
        var syncedCompletedReceiptIds: [String] = []
        
        for pay in allRawPayouts {
            let fields = sourceFields(pay)
            let rawId = String(describing: fields["id"] ?? fields["payoutid"] ?? fields["withdrawalid"] ?? fields["requestid"] ?? fields["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            let status = String(describing: fields["status"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            let isReversed = (fields["reversed"] as? Bool) == true
            guard !isReversed else { continue }
            
            let completedAtStr = String(describing: fields["completedat"] ?? fields["paidat"] ?? fields["settledat"] ?? "").trimmingCharacters(in: .whitespaces)
            let hasCompletedDate = !completedAtStr.isEmpty && completedAtStr.lowercased() != "null" && completedAtStr.lowercased() != "<null>"
            let isRejected = ["rejected", "cancelled", "canceled", "declined", "failed", "reversed"].contains(status)
            let isCompleted = !isRejected && (["completed", "paid", "received", "settled", "approved", "processed", "success", "successful", "done"].contains(status) || hasCompletedDate)
            let payoutStatus: PayoutStatus = isCompleted ? .completed : (isRejected ? .rejected : .requested)
            
            // 1. Extract Trader Split percentage/ratio
            let splitPercentVal: Double? = {
                for key in [
                    "splitpercent", "split_percent", "profitsplit", "profit_split",
                    "tradersplit", "trader_split", "profitshare", "profit_share",
                    "split", "splitrate", "split_rate", "percentage", "rate", "share"
                ] {
                    if let sp = fields[key] {
                        if let n = sp as? NSNumber { return n.doubleValue }
                        if let s = sp as? String {
                            let clean = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean) { return d }
                        }
                    }
                }
                let payAccRef = String(describing: fields["accountref"] ?? fields["accountid"] ?? fields["ref"] ?? "")
                if let known = accountSplitMap[payAccRef] ?? accountSplitMap[payAccRef.cleanAccountId] {
                    return known
                }
                return nil
            }()
            
            // 2. Extract Explicit Gross Amount (NEVER include availableProfit which is total account profit before withdrawal)
            let explicitGross: Double? = {
                for k in ["requestedamount", "requested_amount", "grossamount", "gross_amount", "grossprofit", "gross_profit", "tradingprofit", "trading_profit"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                return nil
            }()
            
            let feeVal: Double = {
                if let f = fields["fee"] ?? fields["fees"] ?? fields["transferfee"] ?? fields["transfer_fee"] ?? fields["commission"] {
                    if let n = f as? NSNumber { return n.doubleValue }
                    if let s = f as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
                }
                return 0
            }()
            let feeMinor = Int64(round(feeVal * 100))
            
            // 3. Extract Explicit Net Received Amount (NEVER include requestedAmount which is Gross!)
            let explicitNet: Double? = {
                for k in ["finalamount", "final_amount", "receivedamount", "received_amount", "netamount", "net_amount", "paidamount", "paid_amount", "netpaid", "traderprofit", "trader_profit", "tradershare", "trader_share", "payoutamount", "payout_amount", "withdrawalamount", "withdrawal_amount", "net"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                if let us = sourceNumber(fields["usershare"] ?? fields["user_share"]), us > 0 {
                    let usDouble = NSDecimalNumber(decimal: us).doubleValue
                    return max(0, usDouble - feeVal)
                }
                return nil
            }()
            
            // 4. Extract Generic Amount (in `payout.history`, `amount` is the gross payout requested)
            let genericAmount: Double? = {
                for k in ["amount", "total", "price", "value"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 { return n.doubleValue }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 { return d }
                        }
                    }
                }
                return nil
            }()
            
            let effectiveSplit = splitPercentVal ?? 100.0
            let ratio = effectiveSplit > 1.0 ? (effectiveSplit / 100.0) : effectiveSplit
            let splitBps = Int(round(ratio * 10000.0))
            
            let netReceivedMinor: Int64
            let grossMinor: Int64
            
            if let en = explicitNet {
                netReceivedMinor = Int64(round(en * 100))
                if let eg = explicitGross, eg >= en {
                    grossMinor = Int64(round(eg * 100))
                } else if let ga = genericAmount, ga >= en {
                    grossMinor = Int64(round(ga * 100))
                } else if splitPercentVal != nil && ratio > 0 {
                    grossMinor = Int64(round(Double(netReceivedMinor) / ratio))
                } else {
                    grossMinor = netReceivedMinor
                }
            } else if let eg = explicitGross {
                grossMinor = Int64(round(eg * 100))
                if let sp = splitPercentVal, sp < 100.0 {
                    netReceivedMinor = max(0, Int64((Double(grossMinor) * Double(splitBps) + 5000) / 10000) - feeMinor)
                } else {
                    netReceivedMinor = grossMinor
                }
            } else if let ga = genericAmount {
                // Per The5ers MCP spec (source-repo/apps/web/src/server/the5ers/data.ts:1840-1854):
                // In payout history, reported amount represents received cash under owner confirmation.
                // Do not invent artificial gross/split multipliers unless explicit split info exists.
                let amtMinor = Int64(round(ga * 100))
                if let sp = splitPercentVal, sp < 100.0 {
                    grossMinor = amtMinor
                    netReceivedMinor = max(0, Int64((Double(grossMinor) * Double(splitBps) + 5000) / 10000) - feeMinor)
                } else {
                    netReceivedMinor = amtMinor
                    grossMinor = amtMinor
                }
            } else {
                continue
            }
            
            let dateVal = fields["receivedat"] ?? fields["paidat"] ?? fields["settledat"] ?? fields["paymentdate"] ?? fields["completedat"] ?? fields["requestedat"] ?? fields["createdat"] ?? fields["date"]
            let rawDate = String(describing: dateVal ?? "")
            let parsedDate = FlexibleDateParser.parse(rawDate) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = fmt.string(from: parsedDate)
            
            let payAccRef = String(describing: fields["accountref"] ?? fields["accountid"] ?? fields["ref"] ?? "")
            let matchedAcc = candidateAccounts.first(where: {
                $0.id == payAccRef || $0.ref == payAccRef || "the5ers_\($0.id)" == payAccRef || $0.id.cleanAccountId == payAccRef.cleanAccountId || $0.ref.cleanAccountId == payAccRef.cleanAccountId
            })
            let primaryAccId: String? = {
                if let m = matchedAcc {
                    return m.id.hasPrefix("the5ers_") ? m.id : "the5ers_\(m.id)"
                }
                if !payAccRef.isEmpty && !payAccRef.contains("opaque") {
                    return payAccRef.hasPrefix("the5ers_") ? payAccRef : "the5ers_\(payAccRef)"
                }
                let fundedAccs = candidateAccounts.filter { $0.program.lowercased().contains("fund") || $0.label.lowercased().contains("fund") }
                if let firstFunded = fundedAccs.first {
                    return firstFunded.id.hasPrefix("the5ers_") ? firstFunded.id : "the5ers_\(firstFunded.id)"
                }
                return candidateAccounts.first.map { $0.id.hasPrefix("the5ers_") ? $0.id : "the5ers_\($0.id)" }
            }()
            let currency = "USD"
            
            let cleanAcc = (primaryAccId ?? "the5ers").cleanAccountId
            let identityKey = !rawId.isEmpty && !rawId.contains("opaque") ? rawId : "\(dateStr)_\(netReceivedMinor)"
            let stablePayoutHash = JournalIds.sha256Hex([cleanAcc, identityKey])
            let payoutEntryId = "the5ers_payout_\(stablePayoutHash)"
            let rcptId = "the5ers_rcpt_\(stablePayoutHash)"
            let canonicalId = PropFirmEngine.canonicalPayoutId(stablePayoutHash)
            let shortRef = !rawId.isEmpty && !rawId.contains("opaque") ? "Payout #\(rawId.prefix(8))" : "Payout #\(stablePayoutHash.prefix(8))"
            
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == payoutEntryId ||
                PropFirmEngine.canonicalPayoutId($0.id) == canonicalId ||
                (!rawId.isEmpty && !rawId.contains("opaque") && ($0.id.contains(rawId) || $0.reference.contains(rawId))) ||
                ($0.kind == "payout" && $0.firm.lowercased() == "the5ers" && 
                 ($0.amountMinor == grossMinor || $0.amountMinor == netReceivedMinor || abs($0.amountMinor - netReceivedMinor) <= 100) && 
                 FlexibleDateParser.areDatesClose($0.occurredOn, dateStr, maxDays: 1))
            }) {
                let existing = dataStore.propEntries[existingIdx]
                let updatedEntry = PropEntryItem(
                    id: payoutEntryId,
                    accountId: primaryAccId ?? existing.accountId,
                    firm: existing.firm,
                    kind: existing.kind,
                    category: existing.category,
                    currency: currency,
                    amountMinor: grossMinor,
                    splitBps: splitBps,
                    feeMinor: feeMinor,
                    occurredOn: dateStr,
                    dueOn: existing.dueOn,
                    status: payoutStatus,
                    parentId: existing.parentId,
                    reference: existing.reference.isEmpty ? shortRef : existing.reference,
                    notes: existing.notes.isEmpty ? "The5ers Official Withdrawal" : existing.notes,
                    voided: existing.voided,
                    revision: existing.revision + 1,
                    createdAt: existing.createdAt,
                    updatedAt: JournalIds.nowIso()
                )
                dataStore.propEntries[existingIdx] = updatedEntry
            } else {
                let payoutEntry = PropEntryItem(
                    id: payoutEntryId,
                    accountId: primaryAccId,
                    firm: "The5ers",
                    kind: "payout",
                    category: "payout",
                    currency: currency,
                    amountMinor: grossMinor,
                    splitBps: splitBps,
                    feeMinor: feeMinor,
                    occurredOn: dateStr,
                    status: payoutStatus,
                    reference: shortRef,
                    notes: "The5ers Official Withdrawal"
                )
                dataStore.propEntries.append(payoutEntry)
            }
            
            // Settlement receipt records actual cash in-pocket
            if isCompleted && !isReversed {
                syncedCompletedReceiptIds.append(rcptId)
                if let rIdx = dataStore.propReceipts.firstIndex(where: {
                    $0.id == rcptId ||
                    $0.payoutId == payoutEntryId ||
                    PropFirmEngine.canonicalPayoutId($0.payoutId) == canonicalId ||
                    PropFirmEngine.canonicalPayoutId($0.id) == canonicalId ||
                    (!rawId.isEmpty && !rawId.contains("opaque") && ($0.id.contains(rawId) || $0.reference.contains(rawId)))
                }) {
                    let existingRcpt = dataStore.propReceipts[rIdx]
                    let updatedRcpt = PropReceiptItem(
                        id: rcptId,
                        payoutId: payoutEntryId,
                        kind: existingRcpt.kind,
                        amountMinor: netReceivedMinor,
                        occurredOn: dateStr,
                        reference: existingRcpt.reference.isEmpty ? "Receipt #\(stablePayoutHash.prefix(8))" : existingRcpt.reference,
                        notes: existingRcpt.notes.isEmpty ? "The5ers Settlement Receipt" : existingRcpt.notes,
                        voided: existingRcpt.voided,
                        createdAt: existingRcpt.createdAt
                    )
                    dataStore.propReceipts[rIdx] = updatedRcpt
                } else {
                    let rcpt = PropReceiptItem(
                        id: rcptId,
                        payoutId: payoutEntryId,
                        kind: "receipt",
                        amountMinor: netReceivedMinor,
                        occurredOn: dateStr,
                        reference: "Receipt #\(stablePayoutHash.prefix(8))",
                        notes: "The5ers Settlement Receipt"
                    )
                    dataStore.propReceipts.append(rcpt)
                }
            }
        }
        
        // 3. Cross-module reconciliation with `the5ers_wallet.overview.withdrawals.totalPaidOut`
        if let totalPaidDec = walletTotalPaidOut, totalPaidDec > 0 {
            let authPaidMinor = NSDecimalNumber(decimal: totalPaidDec * 100).int64Value
            let the5ersReceiptIndices = dataStore.propReceipts.indices.filter { idx in
                let r = dataStore.propReceipts[idx]
                return !r.voided && r.kind == "receipt" && (r.id.hasPrefix("the5ers_") || r.payoutId.hasPrefix("the5ers_"))
            }
            let currentPaidSum = the5ersReceiptIndices.reduce(Int64(0)) { $0 + dataStore.propReceipts[$1].amountMinor }
            
            if the5ersReceiptIndices.isEmpty {
                // `the5ers_wallet` has authoritative paid withdrawals that weren't in per-account `payout.history`
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                let dateStr = fmt.string(from: FlexibleDateParser.parse(walletLastPaidAt ?? "") ?? Date())
                let fallbackAccId = candidateAccounts.first.map { $0.id.hasPrefix("the5ers_") ? $0.id : "the5ers_\($0.id)" }
                let hash = JournalIds.sha256Hex(["wallet_reconciled", dateStr, authPaidMinor])
                let pId = "the5ers_payout_\(hash)"
                let rId = "the5ers_rcpt_\(hash)"
                let entry = PropEntryItem(
                    id: pId,
                    accountId: fallbackAccId,
                    firm: "The5ers",
                    kind: "payout",
                    category: "payout",
                    currency: "USD",
                    amountMinor: authPaidMinor,
                    splitBps: 10000,
                    feeMinor: 0,
                    occurredOn: dateStr,
                    status: .completed,
                    reference: "Wallet #\(hash.prefix(8))",
                    notes: "Reconciled from The5ers Wallet Overview"
                )
                let rcpt = PropReceiptItem(
                    id: rId,
                    payoutId: pId,
                    kind: "receipt",
                    amountMinor: authPaidMinor,
                    occurredOn: dateStr,
                    reference: "Receipt #\(hash.prefix(8))",
                    notes: "Reconciled from The5ers Wallet Overview"
                )
                dataStore.propEntries.append(entry)
                dataStore.propReceipts.append(rcpt)
            } else if let rIdx = the5ersReceiptIndices.first, abs(currentPaidSum - authPaidMinor) > 10 {
                // Single payout where `history` only had gross `amount` and default split differed from actual wallet net paid out
                let oldRcpt = dataStore.propReceipts[rIdx]
                dataStore.propReceipts[rIdx] = PropReceiptItem(
                    id: oldRcpt.id,
                    payoutId: oldRcpt.payoutId,
                    kind: oldRcpt.kind,
                    amountMinor: authPaidMinor,
                    occurredOn: oldRcpt.occurredOn,
                    reference: oldRcpt.reference,
                    notes: oldRcpt.notes,
                    voided: oldRcpt.voided,
                    createdAt: oldRcpt.createdAt
                )
            }
        }
        
        dataStore.deduplicatePropEntries()
        dataStore.deduplicatePropReceipts()
        dataStore.saveToDisk()
        dataStore.objectWillChange.send()
    }
}
