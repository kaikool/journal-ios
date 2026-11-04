import Foundation

// MARK: - The5ers Purchase, Payout & Ledger Synchronization
extension The5ersService {
    // MARK: - Purchase & Account Normalization
    
    /// Derives a clean, professional display name for a The5ers account matching the web source specification.
    public static func the5ersDefaultName(
        from item: [String: Any],
        fallbackLabel: String,
        platform: String? = nil,
        startingBalance: Decimal? = nil,
        balance: Decimal? = nil,
        authoritativeProgramName: String? = nil,
        authoritativeStepName: String? = nil,
        authoritativeAccountType: String? = nil
    ) -> String {
        var fields: [String: Any] = [:]
        for (k, v) in item {
            let clean = k.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            fields[clean] = v
        }
        
        let pkgCandidates: [Any?] = [
            fields["packagename"],
            fields["programname"],
            fields["productname"],
            fields["planname"],
            fields["program"]
        ]
        var packageName: String? = nil
        for cand in pkgCandidates {
            if let str = cand as? String, !str.trimmingCharacters(in: .whitespaces).isEmpty {
                let cleanStr = str.trimmingCharacters(in: .whitespaces)
                let l = cleanStr.lowercased()
                if !l.contains("standard") && l != "funded" && l != "active" && !l.contains("eval") {
                    packageName = cleanStr
                    break
                }
            }
        }
        
        var accountSize: Decimal? = (startingBalance != nil && startingBalance != balance) ? startingBalance : nil
        let sizeCandidates: [Any?] = [
            fields["accountsize"],
            fields["startingbalance"],
            fields["initialbalance"],
            fields["nominalbalance"],
            fields["size"]
        ]
        for cand in sizeCandidates {
            if let num = cand as? NSNumber, num.doubleValue > 0 {
                accountSize = Decimal(string: num.stringValue)
                break
            } else if let str = cand as? String, let dec = Decimal(string: str.trimmingCharacters(in: .whitespaces)), dec > 0 {
                accountSize = dec
                break
            }
        }
        
        var accountNumber: String? = nil
        let accNumCandidates: [Any?] = [
            fields["accountnumber"],
            fields["tradingaccountnumber"],
            fields["login"],
            fields["accountlogin"]
        ]
        for cand in accNumCandidates {
            if let num = cand as? NSNumber, num.intValue > 0 {
                accountNumber = num.stringValue
                break
            } else if let str = cand as? String, !str.isEmpty {
                accountNumber = str.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        let suffix: String? = {
            if let acc = accountNumber { return acc }
            let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: fallbackLabel, range: NSRange(fallbackLabel.startIndex..., in: fallbackLabel)),
               let range = Range(match.range(at: 1), in: fallbackLabel) {
                return String(fallbackLabel[range])
            }
            return nil
        }()
        
        let pLower = (platform ?? String(describing: fields["platform"] ?? fields["tradingplatform"] ?? "")).lowercased()
        let platformTag: String = {
            if pLower.contains("meta-trader-5") || pLower.contains("mt5") { return "MT5" }
            if pLower.contains("meta-trader-4") || pLower.contains("mt4") { return "MT4" }
            if pLower.contains("c-trader") || pLower.contains("ctrader") { return "cTrader" }
            return "MT5"
        }()
        
        let rawCombined = "\(fallbackLabel) \(packageName ?? "") \(fields["type"] ?? "") \(fields["step"] ?? "") \(fields["phase"] ?? "") \(fields["stage"] ?? "")".lowercased()
        
        let pkg: String = {
            if let apn = authoritativeProgramName?.trimmingCharacters(in: .whitespaces), !apn.isEmpty {
                let l = apn.lowercased()
                if l.contains("high stakes") || l.contains("highstakes") || l.contains("high-stakes") { return "High Stakes" }
                if l.contains("hyper growth") || l.contains("hypergrowth") || l.contains("hyper-growth") { return "Hyper Growth" }
                if l.contains("bootcamp") || l.contains("boot camp") { return "Bootcamp" }
                if l.contains("instant") { return "Instant Funding" }
                if !l.contains("standard") && l != "funded" && l != "active" && !l.contains("eval") {
                    return apn
                }
            }
            if rawCombined.contains("high stakes") || rawCombined.contains("highstakes") || rawCombined.contains("high-stakes") || rawCombined.contains("high steaks") || rawCombined.contains("highsteaks") {
                return "High Stakes"
            }
            if rawCombined.contains("hyper growth") || rawCombined.contains("hypergrowth") || rawCombined.contains("hyper-growth") {
                return "Hyper Growth"
            }
            if rawCombined.contains("bootcamp") || rawCombined.contains("boot camp") {
                return "Bootcamp"
            }
            if rawCombined.contains("instant") {
                return "Instant Funding"
            }
            if let p = packageName, !p.isEmpty, !p.lowercased().contains("eval") {
                return p
            }
            return "The5ers \(platformTag)"
        }()
        
        let phase: String = {
            if let asn = authoritativeStepName?.trimmingCharacters(in: .whitespaces), !asn.isEmpty {
                let l = asn.lowercased()
                if l.contains("step 1") || l.contains("phase 1") { return "Phase 1" }
                if l.contains("step 2") || l.contains("phase 2") || l.contains("verification") { return "Phase 2" }
                if l.contains("step 3") || l.contains("phase 3") { return "Phase 3" }
                if l.contains("fund") || l.contains("live") { return "Funded" }
                return asn
            }
            if let aat = authoritativeAccountType?.lowercased() {
                if aat == "funded" { return "Funded" }
            }
            if rawCombined.contains("step 2") || rawCombined.contains("step2") || rawCombined.contains("phase 2") || rawCombined.contains("phase2") || rawCombined.contains("verification") ||
               rawCombined.contains("- 2 -") || rawCombined.contains("- 2-") || rawCombined.contains("-2-") || rawCombined.contains(" - 2 ") || rawCombined.hasSuffix("- 2") {
                return "Phase 2"
            }
            if rawCombined.contains("step 3") || rawCombined.contains("step3") || rawCombined.contains("phase 3") || rawCombined.contains("phase3") ||
               rawCombined.contains("- 3 -") || rawCombined.contains("- 3-") || rawCombined.contains("-3-") || rawCombined.contains(" - 3 ") || rawCombined.hasSuffix("- 3") {
                return "Phase 3"
            }
            if rawCombined.contains("funded") || rawCombined.contains("live") || rawCombined.contains("master") || pkg == "Instant Funding" {
                return "Funded"
            }
            if rawCombined.contains("step 1") || rawCombined.contains("step1") || rawCombined.contains("phase 1") || rawCombined.contains("phase1") || rawCombined.contains("evaluation") ||
               rawCombined.contains("- 1 -") || rawCombined.contains("- 1-") || rawCombined.contains("-1-") || rawCombined.contains(" - 1 ") || rawCombined.hasSuffix("- 1") {
                return "Phase 1"
            }
            return "Phase 1"
        }()
        
        var nameComponents: [String] = [pkg]
        if !phase.isEmpty && phase != pkg {
            nameComponents.append(phase)
        }
        
        if let sz = accountSize, sz > 0 {
            let szInt = NSDecimalNumber(decimal: sz).intValue
            let sizeTag = szInt >= 1000 && szInt % 1000 == 0 ? "$\(szInt / 1000)K" : "$\(szInt)"
            let sizeBare = sizeTag.replacingOccurrences(of: "$", with: "")
            if !pkg.contains(sizeBare) {
                nameComponents.append(sizeTag)
            }
        }
        
        if let s = suffix, !s.isEmpty {
            let sNorm = s.replacingOccurrences(of: "#", with: "")
            if !nameComponents.contains(where: { $0.contains(sNorm) }) {
                nameComponents.append("#\(sNorm)")
            }
        }
        
        // Final deduplication pass to ensure clean presentation without repetitive tokens
        var finalComponents: [String] = []
        for c in nameComponents {
            let cNorm = c.lowercased()
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "")
            let isDupe = finalComponents.contains {
                let eNorm = $0.lowercased()
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: " ", with: "")
                return eNorm == cNorm || (eNorm.contains(cNorm) && cNorm.count >= 3)
            }
            if !isDupe {
                finalComponents.append(c)
            }
        }
        
        return finalComponents.joined(separator: " · ")
    }
    
    internal func isLikelyPurchaseDictionary(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        let hasCost = keys.contains("netpaid") || keys.contains("price") || keys.contains("priceusd") ||
                      keys.contains("cost") || keys.contains("fee") || keys.contains("amount") || keys.contains("total")
        let hasIdentity = keys.contains("id") || keys.contains("orderid") || keys.contains("purchaseid") ||
                          keys.contains("reference") || keys.contains("ref") || keys.contains("purchaseref") ||
                          keys.contains("items") || keys.contains("placedat")
        return (hasCost || keys.contains("items")) && (hasIdentity || keys.contains("status"))
    }
    
    internal func extractAnyPurchaseCollection(from unwrapped: Any?) -> [[String: Any]] {
        guard let unwrapped = unwrapped else { return [] }
        if let s = unwrapped as? String {
            if let parsed = extractJsonFromText(s) {
                return extractAnyPurchaseCollection(from: parsed)
            }
            return []
        }
        if let dict = unwrapped as? [String: Any] {
            if let data = dict["data"] as? [String: Any] {
                if let p = data["purchases"] as? [[String: Any]], !p.isEmpty { return p }
                if let p = data["orders"] as? [[String: Any]], !p.isEmpty { return p }
            }
            if let p = dict["purchases"] as? [[String: Any]], !p.isEmpty { return p }
            if let p = dict["orders"] as? [[String: Any]], !p.isEmpty { return p }
            if isLikelyPurchaseDictionary(dict) {
                return [dict]
            }
            let possibleKeys = ["purchases", "orders", "transactions", "history", "data", "lineitems", "rows", "records", "challenges", "invoices"]
            for k in possibleKeys {
                if let arr = dict[k] as? [[String: Any]], !arr.isEmpty {
                    return arr
                }
                if let subDict = dict[k] as? [String: Any] {
                    let sub = extractAnyPurchaseCollection(from: subDict)
                    if !sub.isEmpty { return sub }
                }
            }
            if let res = dict["result"] {
                let sub = extractAnyPurchaseCollection(from: res)
                if !sub.isEmpty { return sub }
            }
        }
        if let arr = unwrapped as? [[String: Any]] {
            return arr.filter { isLikelyPurchaseDictionary($0) }
        }
        return []
    }
    
    @MainActor
    internal func syncPurchases(
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount]
    ) async {
        lastStatus = "Loading purchases and evaluation fees from the5ers_purchase..."
        var allPurchases: [[String: Any]] = []
        var seenPurchaseIds = Set<String>()
        
        // 1. Fetch paginated orders from official the5ers_purchase 'list'
        var page = 1
        while page <= 10 {
            if Task.isCancelled || isCancelledByUser { break }
            let pArgs: [String: Any] = [
                "operation": "list",
                "contract_version": "1.0",
                "page": page,
                "limit": 50
            ]
            guard let res = try? await callMcpTool(name: "the5ers_purchase", arguments: pArgs),
                  !(res["isError"] as? Bool ?? false) else { break }
            let unwrapped = unwrapMcpToolResult(res)
            let rows = extractAnyPurchaseCollection(from: unwrapped)
            if rows.isEmpty { break }
            for r in rows {
                let pId = String(describing: r["ref"] ?? r["id"] ?? r["orderid"] ?? r["order_id"] ?? r["purchaseid"] ?? UUID().uuidString)
                if !seenPurchaseIds.contains(pId) {
                    seenPurchaseIds.insert(pId)
                    allPurchases.append(r)
                }
            }
            if let dict = unwrapped as? [String: Any],
               let pagination = dict["pagination"] as? [String: Any],
               let hasMore = pagination["has_more"] as? Bool,
               !hasMore {
                break
            }
            if rows.count < 50 { break }
            page += 1
        }
        
        // Fallback without pagination parameters if paginated query was empty
        if allPurchases.isEmpty {
            let fallbackArgsList: [[String: Any]] = [
                ["operation": "list", "contract_version": "1.0", "limit": 50],
                ["operation": "list"]
            ]
            for pArgs in fallbackArgsList {
                if Task.isCancelled || isCancelledByUser { break }
                if let res = try? await callMcpTool(name: "the5ers_purchase", arguments: pArgs),
                   !(res["isError"] as? Bool ?? false) {
                    let unwrapped = unwrapMcpToolResult(res)
                    let rows = extractAnyPurchaseCollection(from: unwrapped)
                    if !rows.isEmpty {
                        for r in rows {
                            let pId = String(describing: r["ref"] ?? r["id"] ?? r["orderid"] ?? r["order_id"] ?? r["purchaseid"] ?? UUID().uuidString)
                            if !seenPurchaseIds.contains(pId) {
                                seenPurchaseIds.insert(pId)
                                allPurchases.append(r)
                            }
                        }
                        break
                    }
                }
            }
        }
        
        if !allPurchases.isEmpty {
            mergePurchases(allPurchases, into: dataStore, targetAccounts: targetAccounts)
        }
    }
    
    @MainActor
    internal func mergePurchases(
        _ rawPurchases: [[String: Any]],
        into dataStore: TradeDataStore,
        targetAccounts: [The5ersMcpAccount]
    ) {
        for purchase in rawPurchases {
            let fields = sourceFields(purchase)
            
            let status = String(describing: fields["status"] ?? "completed").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isRefunded = (fields["refunded"] as? Bool) ?? (fields["isrefunded"] as? Bool) ?? false
            let invalidStatuses: Set<String> = ["cancelled", "canceled", "failed", "declined", "rejected", "expired", "abandoned", "unpaid", "void", "voided", "refunded", "pending"]
            guard !invalidStatuses.contains(status) && !isRefunded else { continue }
            
            let rawDate = String(describing: fields["placedat"] ?? fields["date"] ?? fields["createdat"] ?? fields["purchasedat"] ?? fields["timestamp"] ?? "")
            let date = FlexibleDateParser.parse(rawDate) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = fmt.string(from: date)
            
            var currency = String(describing: fields["currency"] ?? "USD").uppercased()
            
            var itemNames: [String] = []
            var productType = "challenge_fee"
            var itemsTotal: Double = 0
            if let items = (fields["items"] ?? fields["purchases"] ?? fields["lineitems"]) as? [[String: Any]] {
                for it in items {
                    let itFields = sourceFields(it)
                    if (itFields["refunded"] as? Bool) == true || (itFields["isrefunded"] as? Bool) == true {
                        continue
                    }
                    if let n = (itFields["name"] ?? itFields["productname"] ?? itFields["title"] ?? itFields["description"]) as? String, !n.isEmpty {
                        itemNames.append(n)
                    }
                    if let pt = (itFields["producttype"] ?? itFields["category"] ?? itFields["type"]) as? String, !pt.isEmpty {
                        productType = pt.lowercased()
                    }
                    if let np = sourceNumber(itFields["netpaid"] ?? itFields["priceusd"] ?? itFields["price"] ?? itFields["amount"]), np > 0 {
                        itemsTotal += NSDecimalNumber(decimal: np).doubleValue
                    }
                }
            }
            
            var priceNum: Double = 0
            // 1. Prioritize authoritative line-item `netPaid` sum (always in USD per The5ers MCP purchase schema)
            if itemsTotal > 0 {
                priceNum = itemsTotal
                currency = "USD"
            } else {
                // 2. Fallback to order-level USD-denominated fields (`priceUsd`, `netPaid`, `total`, `amount`)
                for k in ["priceusd", "price_usd", "netpaid", "net_paid", "total", "amount", "price", "cost", "value"] {
                    if let val = fields[k] {
                        if let n = val as? NSNumber, n.doubleValue > 0 {
                            priceNum = n.doubleValue
                            currency = "USD"
                            break
                        }
                        if let s = val as? String {
                            let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if let d = Double(clean), d > 0 {
                                priceNum = d
                                currency = "USD"
                                break
                            }
                        }
                    }
                }
            }
            guard priceNum > 0 else { continue }
            let amountMinor = Int64(round(priceNum * 100))
            
            let orderRef = String(describing: fields["ref"] ?? fields["id"] ?? fields["orderid"] ?? fields["order_id"] ?? fields["purchaseid"] ?? fields["purchase_id"] ?? "")
            let title = itemNames.isEmpty ? (fields["name"] as? String ?? "The5ers Program Evaluation") : itemNames.joined(separator: ", ")
            let purchaseHash = JournalIds.sha256Hex([rawDate, currency, title, amountMinor])
            let entryId = !orderRef.isEmpty ? "the5ers_purchase_\(orderRef)" : "the5ers_purchase_\(purchaseHash)"
            let shortRef = !orderRef.isEmpty && !orderRef.contains("opaque") ? "Order #\(orderRef.prefix(8))" : "Order #\(purchaseHash.prefix(8))"
            
            // Normalize category matching EXPENSE_CATEGORIES: "evaluation", "reset", "activation", etc.
            let normalizedCategory: String = {
                let validCategories: Set<String> = [
                    "evaluation", "reset", "activation", "subscription",
                    "platform", "market_data", "transfer", "other"
                ]
                let cleanType = productType.lowercased().trimmingCharacters(in: .whitespaces)
                let titleLower = title.lowercased()
                if validCategories.contains(cleanType) && cleanType != "other" {
                    return cleanType
                }
                if cleanType.contains("program") || cleanType.contains("challenge") || cleanType.contains("eval") || cleanType.contains("bootcamp") || cleanType.contains("hyper") || cleanType.contains("high stakes") {
                    return "evaluation"
                }
                if titleLower.contains("high stakes") || titleLower.contains("bootcamp") || titleLower.contains("hyper") || titleLower.contains("eval") || titleLower.contains("challenge") || titleLower.contains("program") {
                    return "evaluation"
                }
                if cleanType.contains("reset") || titleLower.contains("reset") { return "reset" }
                if cleanType.contains("activat") || titleLower.contains("activat") { return "activation" }
                return "evaluation"
            }()
            
            // Per docs/the5ers.md:52 and domain rules, purchase expenses are firm-wide ('The5ers')
            // and must NEVER be attributed to an individual trading account.
            if let existingIdx = dataStore.propEntries.firstIndex(where: {
                $0.id == entryId ||
                (!orderRef.isEmpty && !orderRef.contains("opaque") && ($0.id.contains(orderRef) || $0.reference.contains(orderRef))) ||
                ($0.kind == "expense" && $0.firm.lowercased() == "the5ers" && $0.amountMinor == amountMinor && FlexibleDateParser.areDatesClose($0.occurredOn, dateStr, maxDays: 1))
            }) {
                var existing = dataStore.propEntries[existingIdx]
                existing.id = entryId
                existing.amountMinor = amountMinor
                existing.currency = currency
                existing.occurredOn = dateStr
                existing.category = normalizedCategory
                existing.accountId = nil
                existing.status = .completed
                if existing.reference.isEmpty {
                    existing.reference = shortRef
                }
                if existing.notes.isEmpty {
                    existing.notes = title
                }
                dataStore.propEntries[existingIdx] = existing
            } else {
                let entry = PropEntryItem(
                    id: entryId,
                    accountId: nil,
                    firm: "The5ers",
                    kind: "expense",
                    category: normalizedCategory,
                    currency: currency,
                    amountMinor: amountMinor,
                    occurredOn: dateStr,
                    status: .completed,
                    reference: shortRef,
                    notes: title
                )
                dataStore.propEntries.append(entry)
            }
        }
    }
}
