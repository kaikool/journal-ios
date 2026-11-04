import Foundation

// MARK: - The5ers Account Payload Parsing & Store Upsert
extension The5ersService {
    /// Extracts a Decimal requirement from either a plain number or a The5ers `{ "value": number, "unit": "currency" | "percent" }` object
    internal func extractRequirementDecimal(_ val: Any?, startingBalance: Decimal?) -> Decimal? {
        guard let val = val else { return nil }
        if let rawDict = val as? [String: Any] {
            let dict = sourceFields(rawDict)
            let usdCandidate = firstValue(in: dict, keys: ["currencyvalue", "amountusd", "usd", "dollaramount"])
            if let amt = sourceNumber(usdCandidate), amt != 0 {
                return abs(amt)
            }
            let numCandidate = firstValue(in: dict, keys: ["value", "amount", "limit", "threshold", "target", "goal", "max", "cap", "required"])
            guard let num = sourceNumber(numCandidate), num != 0 else {
                return nil
            }
            let absNum = abs(num)
            let unit = String(describing: dict["unit"] ?? "currency").lowercased()
            if unit.contains("percent") || unit == "%" || unit == "pct" {
                if let sb = startingBalance, sb > 0 {
                    return absNum < 1 ? (absNum * sb) : ((absNum * sb) / 100)
                }
            }
            if let sb = startingBalance, sb >= 1000 {
                if absNum > 0 && absNum <= 25 {
                    return (absNum * sb) / 100
                }
                if absNum > (sb * 70) / 100 && absNum < sb {
                    return sb - absNum
                }
            }
            return absNum
        }
        if let num = sourceNumber(val), num != 0 {
            let absNum = abs(num)
            if let sb = startingBalance, sb >= 1000 {
                if absNum > 0 && absNum < 1 {
                    return absNum * sb
                }
                if absNum >= 1 && absNum <= 25 {
                    return (absNum * sb) / 100
                }
                if absNum > (sb * 70) / 100 && absNum < sb {
                    return sb - absNum
                }
            }
            return absNum
        }
        return nil
    }
    
    /// Extracts an Int requirement from either a plain integer or a The5ers `{ "value": number, "unit": "days" }` object
    internal func extractRequirementInt(_ val: Any?) -> Int? {
        guard let val = val else { return nil }
        if let rawDict = val as? [String: Any] {
            let dict = sourceFields(rawDict)
            let candidate = firstValue(in: dict, keys: ["value", "currentvalue", "current", "completed", "count", "threshold", "target", "required", "min", "days"])
            if let i = candidate as? Int { return i }
            if let n = candidate as? NSNumber { return n.intValue }
            if let d = sourceNumber(candidate) { return NSDecimalNumber(decimal: d).intValue }
            return nil
        }
        if let i = val as? Int { return i }
        if let n = val as? NSNumber { return n.intValue }
        if let d = sourceNumber(val) { return NSDecimalNumber(decimal: d).intValue }
        return nil
    }
    
    /// Recursively extracts program rules, targets, stop-loss limits, and consistency metrics from `the5ers_program`, `the5ers_consistency`, and `the5ers_account` payloads
    internal func parseProgramAndHealthPayload(
        _ raw: Any?,
        startingBalance: inout Decimal?,
        profitTarget: inout Decimal?,
        maxLoss: inout Decimal?,
        maxDailyLoss: inout Decimal?,
        minTradingDays: inout Int?,
        currentTradingDays: inout Int?,
        winningDays: inout Int?,
        programName: inout String?,
        stepName: inout String?,
        accountType: inout String?,
        depth: Int = 0
    ) {
        guard depth <= 5, let raw = raw else { return }
        if let arr = raw as? [[String: Any]] {
            for item in arr {
                let r = sourceFields(item)
                let rNameVal = firstValue(in: r, keys: ["name", "key", "type", "id", "label", "rule"])
                let rName = String(describing: rNameVal ?? "").lowercased()
                if rName.contains("profitable") || rName.contains("winning") {
                    let cvVal = firstValue(in: r, keys: ["currentvalue", "current", "completed", "count", "achieved", "value"])
                    if let cv = extractRequirementInt(cvVal) {
                        winningDays = cv
                    }
                    let thVal = firstValue(in: r, keys: ["threshold", "target", "required", "min", "minimum", "limit"])
                    if minTradingDays == nil, let th = extractRequirementInt(thVal), th > 0 {
                        minTradingDays = th
                    }
                } else if rName.contains("trading") && rName.contains("day") {
                    let cvVal = firstValue(in: r, keys: ["currentvalue", "current", "completed", "count"])
                    if let cv = extractRequirementInt(cvVal) {
                        currentTradingDays = cv
                    }
                    let thVal = firstValue(in: r, keys: ["threshold", "target", "required", "min", "minimum", "limit", "value"])
                    if minTradingDays == nil, let th = extractRequirementInt(thVal), th > 0 {
                        minTradingDays = th
                    }
                } else if rName.contains("target") || rName.contains("profitgoal") || rName.contains("profit_goal") {
                    let ptVal = firstValue(in: r, keys: ["target", "threshold", "limit", "value", "amount", "goal"])
                    if profitTarget == nil, let pt = extractRequirementDecimal(ptVal, startingBalance: startingBalance) {
                        profitTarget = pt
                    }
                } else if rName.contains("daily") && (rName.contains("loss") || rName.contains("drawdown") || rName.contains("pause") || rName.contains("stop") || rName.contains("cap")) {
                    let dlVal = firstValue(in: r, keys: ["limit", "threshold", "max", "value", "amount"])
                    if maxDailyLoss == nil, let dl = extractRequirementDecimal(dlVal, startingBalance: startingBalance) {
                        maxDailyLoss = dl
                    }
                } else if (rName.contains("max") || rName.contains("total") || rName.contains("stopout")) && (rName.contains("loss") || rName.contains("drawdown") || rName.contains("stop")) {
                    let mlVal = firstValue(in: r, keys: ["limit", "threshold", "max", "value", "amount"])
                    if maxLoss == nil, let ml = extractRequirementDecimal(mlVal, startingBalance: startingBalance) {
                        maxLoss = ml
                    }
                }
                // Check if this array item is an active step in a steps/phases list
                let statusStr = String(describing: r["status"] ?? "").lowercased()
                let isCurrBool = (r["iscurrent"] as? Bool == true) || (r["current"] as? Bool == true) || (r["active"] as? Bool == true)
                let isCurrStatus = statusStr == "active" || statusStr == "in_progress" || statusStr == "inprogress" || statusStr == "current"
                if isCurrBool || isCurrStatus {
                    parseProgramAndHealthPayload(
                        item,
                        startingBalance: &startingBalance,
                        profitTarget: &profitTarget,
                        maxLoss: &maxLoss,
                        maxDailyLoss: &maxDailyLoss,
                        minTradingDays: &minTradingDays,
                        currentTradingDays: &currentTradingDays,
                        winningDays: &winningDays,
                        programName: &programName,
                        stepName: &stepName,
                        accountType: &accountType,
                        depth: depth + 1
                    )
                }
            }
            return
        }
        
        guard let rawDict = raw as? [String: Any] else { return }
        let d = sourceFields(rawDict)
        
        // 1. Starting balance
        if startingBalance == nil {
            let sbVal = firstValue(in: d, keys: ["startingbalance", "initialbalance", "basebalance", "accountsize", "nominalbalance"])
            if let sb = sourceNumber(sbVal), sb > 0 {
                startingBalance = sb
            }
        }
        
        // 2. Program & Step names
        if programName == nil {
            for k in ["programname", "programtitle", "name"] {
                if let s = d[k] as? String {
                    let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && !["active", "closed", "open", "usd", "eur", "profitable-days", "winning-days"].contains(clean.lowercased()) {
                        programName = clean
                        break
                    }
                }
            }
        }
        if stepName == nil {
            for k in ["stepname", "phasename", "currentstepname", "levelname"] {
                if let s = d[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stepName = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        if accountType == nil {
            for k in ["phase", "accounttype"] {
                if let s = d[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    accountType = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        
        // 3. Profit Target
        if profitTarget == nil {
            let targetCandidate = firstValue(in: d, keys: [
                "profittarget", "profitgoal", "targetprofit", "profitobjective", "target", "goal", "targetamount"
            ])
            if let pt = extractRequirementDecimal(targetCandidate, startingBalance: startingBalance), pt > 0 {
                profitTarget = pt
            }
        }
        
        // 4. Max Loss (Stop-out / Terminate)
        if maxLoss == nil {
            let maxLossCandidate = firstValue(in: d, keys: [
                "maxtotalloss", "maxloss", "maximumloss", "losslimit", "totallosslimit", "maxdrawdown", "maximumdrawdown", "totaldrawdown", "stopoutlevel", "maxstoploss"
            ])
            if let ml = extractRequirementDecimal(maxLossCandidate, startingBalance: startingBalance), ml > 0 {
                maxLoss = ml
            }
        }
        
        // 5. Max Daily Loss (Daily Cap / Daily Pause)
        if maxDailyLoss == nil {
            let dailyLossCandidate = firstValue(in: d, keys: [
                "maxdailyloss", "dailylosslimit", "dailyloss", "alloweddailylosses", "dailydrawdown", "maxdailydrawdown", "dailypause", "dailystoploss", "dailycap"
            ])
            if let dl = extractRequirementDecimal(dailyLossCandidate, startingBalance: startingBalance), dl > 0 {
                maxDailyLoss = dl
            }
        }
        
        // 6. Winning Days, Trading Days & Min Required Days
        if winningDays == nil {
            let winDaysCandidate = firstValue(in: d, keys: [
                "winningdays", "profitabledays", "profitabletradingdays", "currentwinningdays", "currentprofitabledays", "completedwinningdays", "completedprofitabledays"
            ])
            if let wd = extractRequirementInt(winDaysCandidate), wd >= 0 {
                winningDays = wd
            }
        }
        if currentTradingDays == nil {
            let trdDaysCandidate = firstValue(in: d, keys: [
                "tradingdays", "currenttradingdays", "activedays", "completedtradingdays"
            ])
            if let td = extractRequirementInt(trdDaysCandidate), td >= 0 {
                currentTradingDays = td
            }
        }
        if minTradingDays == nil {
            let minDaysCandidate = firstValue(in: d, keys: [
                "minprofitabledays", "minimumprofitabledays", "minwinningdays", "requiredwinningdays", "mintradingdays", "minimumtradingdays", "minactivedays", "requireddays"
            ])
            if let md = extractRequirementInt(minDaysCandidate), md > 0 {
                minTradingDays = md
            }
        }
        
        // 7. Inspect nested containers
        if let currStep = rawDict["currentStep"] as? [String: Any] ?? d["currentstep"] as? [String: Any] {
            if stepName == nil, let sn = (currStep["name"] ?? currStep["title"] ?? currStep["label"]) as? String, !sn.trimmingCharacters(in: .whitespaces).isEmpty {
                stepName = sn.trimmingCharacters(in: .whitespaces)
            }
            parseProgramAndHealthPayload(
                currStep,
                startingBalance: &startingBalance,
                profitTarget: &profitTarget,
                maxLoss: &maxLoss,
                maxDailyLoss: &maxDailyLoss,
                minTradingDays: &minTradingDays,
                currentTradingDays: &currentTradingDays,
                winningDays: &winningDays,
                programName: &programName,
                stepName: &stepName,
                accountType: &accountType,
                depth: depth + 1
            )
        }
        
        let nestedContainers = [
            "data", "authoritative", "derived", "rules", "program", "progression", "journey",
            "requirements", "objectives", "limits", "metrics", "progress", "summary",
            "consistency", "steps", "phases", "stages", "items"
        ]
        for key in nestedContainers {
            if let sub = d[key] {
                parseProgramAndHealthPayload(
                    sub,
                    startingBalance: &startingBalance,
                    profitTarget: &profitTarget,
                    maxLoss: &maxLoss,
                    maxDailyLoss: &maxDailyLoss,
                    minTradingDays: &minTradingDays,
                    currentTradingDays: &currentTradingDays,
                    winningDays: &winningDays,
                    programName: &programName,
                    stepName: &stepName,
                    accountType: &accountType,
                    depth: depth + 1
                )
            }
        }
    }
    
    /// Upserts a single The5ersMcpAccount into dataStore.propAccounts and dataStore.accounts (preserving exact name & status rules)
    @MainActor
    internal func upsertAccountIntoStore(_ acc: The5ersMcpAccount, into dataStore: TradeDataStore) {
        let rawStatus = acc.status.trimmingCharacters(in: .whitespaces).lowercased()
        let isBlocked = (acc.tradingBlocked == true)
        let mappedStatus = mapPropStatus(rawStatus: rawStatus, isBlocked: isBlocked)
        
        let rawProg = acc.program.trimmingCharacters(in: .whitespaces).lowercased()
        let rawLabel = acc.label.trimmingCharacters(in: .whitespaces).lowercased()
        let mappedProgram = mapPropProgram(rawProg: rawProg, rawLabel: rawLabel)
        
        let startingMinor = NSDecimalNumber(decimal: (acc.startingBalance ?? acc.balance) * 100).int64Value
        let journalAccId = acc.id.hasPrefix("the5ers_") ? acc.id : "the5ers_\(acc.id)"
        let isActive = (mappedStatus == .active)
        
        let balMinor: Int64 = NSDecimalNumber(decimal: acc.balance * 100).int64Value
        let eqMinor: Int64? = acc.equity.map { NSDecimalNumber(decimal: $0 * 100).int64Value }
        let settledPayoutsMinor = dataStore.propEntries
            .filter { entry in
                guard entry.firm == "The5ers", entry.kind == "payout", entry.status == .completed, !entry.voided, let accId = entry.accountId else { return false }
                return accId == journalAccId || TradeDataStore.isSameAccountId(accId, journalAccId)
            }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let pnlMinor: Int64? = {
            if let pnl = acc.profitAndLoss ?? acc.totalNetProfit {
                return NSDecimalNumber(decimal: pnl * 100).int64Value
            }
            if balMinor > 0 && startingMinor > 0 {
                return (balMinor - startingMinor) + settledPayoutsMinor
            }
            return nil
        }()
        let feesMinor: Int64? = {
            if let f = acc.totalFees {
                return NSDecimalNumber(decimal: abs(f) * 100).int64Value
            }
            return nil
        }()
        
        let accountNumber: String? = {
            let pattern = #"(?:…|\.{3}|[-_·\s#])?(\d{3,12})\s*$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: acc.label, range: NSRange(acc.label.startIndex..., in: acc.label)),
               let range = Range(match.range(at: 1), in: acc.label) {
                return String(acc.label[range])
            }
            return nil
        }()
        
        let existingLinkedAcc = dataStore.accounts.first(where: { a in
            a.id == journalAccId ||
            a.name == acc.label ||
            (accountNumber.map { accNum in a.id.cleanAccountId == accNum || a.name.contains(accNum) } ?? false)
        })
        let linkedAccountId = existingLinkedAcc?.id ?? journalAccId
        
        upsertPropAccountItem(
            acc: acc,
            journalAccId: journalAccId,
            linkedAccountId: linkedAccountId,
            mappedProgram: mappedProgram,
            mappedStatus: mappedStatus,
            startingMinor: startingMinor,
            balMinor: balMinor,
            eqMinor: eqMinor,
            pnlMinor: pnlMinor,
            feesMinor: feesMinor,
            accountNumber: accountNumber,
            into: dataStore
        )
        
        upsertTradingAccount(
            acc: acc,
            journalAccId: journalAccId,
            mappedProgram: mappedProgram,
            isActive: isActive,
            accountNumber: accountNumber,
            into: dataStore
        )
    }

    private func mapPropStatus(rawStatus: String, isBlocked: Bool) -> PropStatus {
        if rawStatus.contains("term") || rawStatus.contains("breach") || rawStatus.contains("fail") || rawStatus.contains("viola") || rawStatus.contains("disqual") {
            return .breached
        }
        if rawStatus.contains("pass") || rawStatus.contains("qualif") {
            return .passed
        }
        if rawStatus.contains("close") || rawStatus.contains("ended") || rawStatus.contains("expir") || rawStatus.contains("arch") {
            return .closed
        }
        if rawStatus.contains("inact") || rawStatus.contains("disab") {
            return .inactive
        }
        if isBlocked {
            return .closed
        }
        if rawStatus == "active" || rawStatus == "open" || rawStatus == "available" || rawStatus == "trading" {
            return .active
        }
        return .closed
    }

    private func mapPropProgram(rawProg: String, rawLabel: String) -> PropProgram {
        if rawProg.contains("instant") || rawLabel.contains("instant") { return .instantFunded }
        if rawProg.contains("step2") || rawProg.contains("step 2") || rawProg.contains("phase2") || rawProg.contains("phase 2") || rawProg.contains("verification") || rawLabel.contains("phase 2") || rawLabel.contains("step 2") || rawLabel.contains("high stakes - 2") { return .verification }
        if rawProg.contains("fund") || rawProg.contains("live") || rawProg.contains("master") || rawProg.contains("step 3") || rawProg.contains("phase 3") || rawLabel.contains("funded") || rawLabel.contains("live") || rawLabel.contains("step 3") || rawLabel.contains("phase 3") { return .funded }
        return .evaluation
    }

    private func upsertPropAccountItem(
        acc: The5ersMcpAccount,
        journalAccId: String,
        linkedAccountId: String,
        mappedProgram: PropProgram,
        mappedStatus: PropStatus,
        startingMinor: Int64,
        balMinor: Int64,
        eqMinor: Int64?,
        pnlMinor: Int64?,
        feesMinor: Int64?,
        accountNumber: String?,
        into dataStore: TradeDataStore
    ) {
        if let existingIndex = dataStore.propAccounts.firstIndex(where: { p in
            TradeDataStore.isSameAccountId(p.id, journalAccId) ||
            p.name == acc.label ||
            (accountNumber.map { accNum in p.id.cleanAccountId == accNum || p.name.contains(accNum) } ?? false)
        }) {
            let old = dataStore.propAccounts[existingIndex]
            dataStore.propAccounts[existingIndex] = PropAccountItem(
                id: old.id,
                firm: "The5ers",
                name: acc.label,
                program: mappedProgram,
                status: mappedStatus,
                currency: acc.currency,
                sizeMinor: startingMinor,
                parentId: old.parentId,
                journalAccountId: linkedAccountId,
                openedOn: old.openedOn,
                closedOn: old.closedOn,
                renewalOn: old.renewalOn,
                renewalMinor: old.renewalMinor,
                notes: old.notes,
                archived: old.archived,
                revision: old.revision + 1,
                createdAt: old.createdAt,
                updatedAt: JournalIds.nowIso(),
                balanceMinor: balMinor,
                equityMinor: eqMinor,
                netPnlMinor: pnlMinor ?? old.netPnlMinor,
                totalFeesMinor: feesMinor ?? old.totalFeesMinor,
                totalTrades: acc.totalTrades ?? old.totalTrades,
                winRate: acc.winRate ?? old.winRate,
                profitFactor: acc.profitFactor ?? old.profitFactor,
                profitTargetMinor: acc.profitTarget.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value } ?? old.profitTargetMinor,
                maxLossMinor: acc.maxLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value } ?? old.maxLossMinor,
                maxDailyLossMinor: acc.maxDailyLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value } ?? old.maxDailyLossMinor,
                minTradingDays: acc.minTradingDays ?? old.minTradingDays,
                currentTradingDays: acc.currentTradingDays ?? old.currentTradingDays,
                winningDays: acc.winningDays ?? old.winningDays,
                currentStepName: acc.currentStepName ?? old.currentStepName
            )
        } else {
            let newPropAccount = PropAccountItem(
                id: journalAccId,
                firm: "The5ers",
                name: acc.label,
                program: mappedProgram,
                status: mappedStatus,
                currency: acc.currency,
                sizeMinor: startingMinor,
                journalAccountId: linkedAccountId,
                openedOn: acc.createdAt ?? DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
                notes: "Synced from The5ers MCP Hub (Protocol 2025-03-26)",
                archived: false,
                balanceMinor: balMinor,
                equityMinor: eqMinor,
                netPnlMinor: pnlMinor,
                totalFeesMinor: feesMinor,
                totalTrades: acc.totalTrades,
                winRate: acc.winRate,
                profitFactor: acc.profitFactor,
                profitTargetMinor: acc.profitTarget.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                maxLossMinor: acc.maxLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                maxDailyLossMinor: acc.maxDailyLoss.map { NSDecimalNumber(decimal: abs($0) * 100).int64Value },
                minTradingDays: acc.minTradingDays,
                currentTradingDays: acc.currentTradingDays,
                winningDays: acc.winningDays,
                currentStepName: acc.currentStepName
            )
            dataStore.propAccounts.append(newPropAccount)
        }
    }

    private func upsertTradingAccount(
        acc: The5ersMcpAccount,
        journalAccId: String,
        mappedProgram: PropProgram,
        isActive: Bool,
        accountNumber: String?,
        into dataStore: TradeDataStore
    ) {
        if let accIdx = dataStore.accounts.firstIndex(where: { a in
            TradeDataStore.isSameAccountId(a.id, journalAccId) ||
            a.name == acc.label ||
            (accountNumber.map { accNum in a.id.cleanAccountId == accNum || a.name.contains(accNum) } ?? false)
        }) {
            var old = dataStore.accounts[accIdx]
            old.name = acc.label
            old.broker = "The5ers"
            old.currency = acc.currency
            if let sb = acc.startingBalance, sb > 0 {
                old.initialBalance = sb
            }
            old.autoSync = isActive
            old.lastSyncAt = Date()
            old.propProgram = mappedProgram.rawValue
            dataStore.accounts[accIdx] = old
        } else {
            let newAcc = Account(
                id: journalAccId,
                name: acc.label,
                broker: "The5ers",
                kind: .sync,
                currency: acc.currency,
                initialBalance: acc.startingBalance ?? (acc.balance > 0 ? acc.balance : Decimal.zero),
                autoSync: isActive,
                archivedAt: nil,
                visibleInJournal: true,
                propProgram: mappedProgram.rawValue
            )
            dataStore.accounts.append(newAcc)
        }
    }
}
