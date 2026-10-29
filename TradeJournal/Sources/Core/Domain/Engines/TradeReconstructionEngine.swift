import Foundation

/// Trade reconstruction engine pairing raw executions into complete round-trips using FIFO/LIFO
public enum TradeReconstructionEngine {
    
    public static let flatEpsilon: Decimal = Decimal(sign: .plus, exponent: -9, significand: 1) // 1e-9
    
    public struct Options {
        public let method: ProfitCalcMethod
        public let multipliers: [String: Decimal]
        /// Exchange rate context used to express every monetary amount in the reporting currency.
        public let context: CurrencyContext
        /// Currency the broker reports commissions and swap in (usually the account currency).
        public let accountCurrency: String
        /// Journal defaults (used for the break-even band).
        public let defaults: JournalDefaults
        
        public init(
            method: ProfitCalcMethod = .fifo,
            multipliers: [String: Decimal] = [:],
            context: CurrencyContext = .default,
            accountCurrency: String = "USD",
            defaults: JournalDefaults = .empty
        ) {
            self.method = method
            self.multipliers = multipliers
            self.context = context
            self.accountCurrency = accountCurrency.uppercased()
            self.defaults = defaults
        }
    }
    
    private struct OpenLot {
        var quantity: Decimal
        var price: Decimal
    }
    
    private final class OpenCycle {
        var direction: TradeDirection
        var openedAt: Date
        var lots: [OpenLot]
        var entryQuantity: Decimal
        var entryNotional: Decimal
        var exitQuantity: Decimal
        var exitNotional: Decimal
        var grossPnl: Decimal
        var fees: Decimal
        /// Signed swap (negative = cost, positive = credit) in the reporting currency.
        var swap: Decimal
        var executionIds: [String]
        var exits: [ExitAttribution]
        var executionCount: Int
        
        init(direction: TradeDirection, openedAt: Date) {
            self.direction = direction
            self.openedAt = openedAt
            self.lots = []
            self.entryQuantity = 0
            self.entryNotional = 0
            self.exitQuantity = 0
            self.exitNotional = 0
            self.grossPnl = 0
            self.fees = 0
            self.swap = 0
            self.executionIds = []
            self.exits = []
            self.executionCount = 0
        }
        
        var openQuantity: Decimal {
            lots.reduce(Decimal.zero) { $0 + $1.quantity }
        }
    }
    
    /// Converts a broker-reported monetary amount (commission / swap) into the reporting currency.
    private static func toReportingCurrency(_ amount: Decimal, options: Options) -> Decimal {
        let account = options.accountCurrency
        let reporting = options.context.reportingCurrency
        if account == reporting { return amount }
        guard let converted = options.context.convert(amount, from: account, to: reporting) else {
            AppLogger.warning("No \(account)->\(reporting) rate configured; amount \(amount) kept in \(account).")
            return amount
        }
        return converted
    }
    
/// Domain specification matching core web repository
/// Returns matched entry notional (entry price * matched qty) (matched entry notional = entry price * matched qty).
    private static func consumeLots(cycle: OpenCycle, quantity: Decimal, method: ProfitCalcMethod) -> Decimal {
        var remaining = quantity
        var matchedNotional: Decimal = 0
        
        if method == .wavg {
            let totalQty = cycle.openQuantity
            let totalNotional = cycle.lots.reduce(Decimal.zero) { $0 + ($1.quantity * $1.price) }
            let avgPrice = totalQty > 0 ? (totalNotional / totalQty) : 0
            matchedNotional = avgPrice * quantity
            let scale = totalQty > 0 ? ((totalQty - quantity) / totalQty) : 0
            cycle.lots = cycle.lots
                .map { OpenLot(quantity: $0.quantity * scale, price: $0.price) }
                .filter { $0.quantity > flatEpsilon }
            return matchedNotional
        }
        
        while remaining > flatEpsilon && !cycle.lots.isEmpty {
            let index = method == .fifo ? 0 : cycle.lots.count - 1
            var lot = cycle.lots[index]
            let take = min(lot.quantity, remaining)
            matchedNotional += take * lot.price
            lot.quantity -= take
            remaining -= take
            if lot.quantity <= flatEpsilon {
                cycle.lots.remove(at: index)
            } else {
                cycle.lots[index] = lot
            }
        }
        return matchedNotional
    }
    
    private static func finalizeCycle(
        cycle: OpenCycle,
        accountId: String,
        symbol: String,
        assetClass: AssetClass?,
        closedAt: Date?,
        keyCollisions: inout [String: Int],
        importGroup: String?,
        contractMultiplier: Decimal?,
        breakevenThreshold: Decimal
    ) -> Trade {
        let openQty = cycle.openQuantity
        let netPnl = cycle.grossPnl - cycle.fees + cycle.swap
        let isOpen = openQty > flatEpsilon
        
        let status: TradeStatus
        if isOpen {
            status = .open
        } else if abs(netPnl) <= max(breakevenThreshold, flatEpsilon) {
            status = .breakeven
        } else if netPnl > 0 {
            status = .win
        } else {
            status = .loss
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let openedAtStr = isoFormatter.string(from: cycle.openedAt)
        
        var baseKey = "\(accountId)|\(symbol)|\(cycle.direction.rawValue)|\(openedAtStr)"
        if let group = importGroup, !group.isEmpty {
            let encodedGroup = group.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? group
            baseKey += "|import:\(encodedGroup)"
        }
        
        let collision = keyCollisions[baseKey] ?? 0
        keyCollisions[baseKey] = collision + 1
        let key = collision == 0 ? baseKey : "\(baseKey)|\(collision)"
        
        let avgEntry = cycle.entryQuantity > 0 ? (cycle.entryNotional / cycle.entryQuantity) : 0
        let avgExit = cycle.exitQuantity > 0 ? (cycle.exitNotional / cycle.exitQuantity) : nil
        
        let durationMs: Int64?
        if !isOpen, let closedAt = closedAt {
            durationMs = Int64((closedAt.timeIntervalSince(cycle.openedAt)) * 1000)
        } else {
            durationMs = nil
        }
        
        return Trade(
            key: key,
            accountId: accountId,
            symbol: symbol,
            assetClass: assetClass,
            direction: cycle.direction,
            status: status,
            openedAt: cycle.openedAt,
            closedAt: isOpen ? nil : closedAt,
            quantity: cycle.entryQuantity,
            openQuantity: isOpen ? openQty : 0,
            avgEntry: avgEntry,
            avgExit: avgExit,
            grossPnl: cycle.grossPnl,
            fees: cycle.fees,
            swap: cycle.swap,
            netPnl: netPnl,
            executionCount: cycle.executionCount,
            executionIds: cycle.executionIds,
            exits: cycle.exits,
            durationMs: durationMs,
            contractMultiplier: contractMultiplier
        )
    }
    
/// Domain specification matching core web repository
    public static func buildRoundTrips(
        executions: [Execution],
        options: Options = Options()
    ) -> [Trade] {
        var trips: [Trade] = []
        var keyCollisions: [String: Int] = [:]
        
// 1. Group by accountId + symbol + importGroup + symbol + importGroup
        var groups: [String: [Execution]] = [:]
        for execution in executions {
// Core implementation detail
            let groupKey = "\(execution.accountId)\u{0000}\(execution.symbol)"
            groups[groupKey, default: []].append(execution)
        }
        
// 2. Process each group sequentially
        for (_, groupExecutions) in groups {
            var group = groupExecutions
            // Stable chronological ordering of executions within the symbol group
            group.sort {
                if $0.executedAt != $1.executedAt {
                    return $0.executedAt < $1.executedAt
                }
                return $0.id < $1.id
            }
            
            guard let first = group.first else { continue }
            let accountId = first.accountId
            let symbol = first.symbol
            let multiplier = AssetContractEngine.contractMultiplier(for: symbol, customMultipliers: options.multipliers)
            let assetClass = group.first(where: { $0.assetClass != nil })?.assetClass
                ?? AssetContractEngine.assetClass(for: symbol)
            let customMultiplier = AssetContractEngine.customMultiplier(for: symbol, multipliers: options.multipliers)
            
            var cycle: OpenCycle? = nil
            
            for execution in group {
                var signedQty = execution.side == .buy ? execution.quantity : -execution.quantity
                var feeRemaining = toReportingCurrency(execution.fee, options: options)
                var swapRemaining = toReportingCurrency(execution.swap ?? 0, options: options)
                var counted = false
                
                while abs(signedQty) > flatEpsilon {
                    if cycle == nil {
                        cycle = OpenCycle(
                            direction: signedQty > 0 ? .long : .short,
                            openedAt: execution.executedAt
                        )
                    }
                    guard let activeCycle = cycle else { break }
                    
                    let isEntry = (activeCycle.direction == .long && signedQty > 0) ||
                                  (activeCycle.direction == .short && signedQty < 0)
                    
                    if !counted {
                        activeCycle.executionIds.append(execution.id)
                        activeCycle.executionCount += 1
                        counted = true
                    } else if !activeCycle.executionIds.contains(execution.id) {
                        activeCycle.executionIds.append(execution.id)
                        activeCycle.executionCount += 1
                    }
                    
                    if isEntry {
                        let qty = abs(signedQty)
                        activeCycle.lots.append(OpenLot(quantity: qty, price: execution.price))
                        activeCycle.entryQuantity += qty
                        activeCycle.entryNotional += qty * execution.price
                        activeCycle.fees += feeRemaining + defaultFeeShare(quantity: qty, reportedFee: execution.fee, options: options, accountId: accountId, symbol: symbol)
                        activeCycle.swap += swapRemaining
                        feeRemaining = 0
                        swapRemaining = 0
                        signedQty = 0
                    } else {
                        let openQty = activeCycle.openQuantity
                        let exitQty = min(abs(signedQty), openQty)
                        let matchedNotional = consumeLots(cycle: activeCycle, quantity: exitQty, method: options.method)
                        let avgMatchedEntry = exitQty > 0 ? (matchedNotional / exitQty) : 0
                        let exitNotional = exitQty * execution.price
                        
                        let chunkGross = AssetContractEngine.calculateGrossPnlDetailed(
                            symbol: symbol,
                            direction: activeCycle.direction,
                            quantity: exitQty,
                            entryPrice: avgMatchedEntry,
                            exitPrice: execution.price,
                            customMultiplier: customMultiplier,
                            context: options.context,
                            entryNotional: matchedNotional
                        ).amount
                        
                        // Fee and swap are split proportionally over the chunks of this execution.
                        // Multiplying before dividing keeps the split exact, and the last chunk of an
                        // execution takes the remainder so the parts always add up to the original.
                        let feeShare: Decimal
                        let swapShare: Decimal
                        let remainingQtyAfterChunk = abs(signedQty) - exitQty
                        if remainingQtyAfterChunk <= flatEpsilon {
                            feeShare = feeRemaining
                            swapShare = swapRemaining
                        } else {
                            feeShare = (feeRemaining * exitQty) / abs(signedQty)
                            swapShare = (swapRemaining * exitQty) / abs(signedQty)
                        }
                        
                        activeCycle.grossPnl += chunkGross
                        activeCycle.fees += feeShare + defaultFeeShare(quantity: exitQty, reportedFee: execution.fee, options: options, accountId: accountId, symbol: symbol)
                        activeCycle.swap += swapShare
                        feeRemaining -= feeShare
                        swapRemaining -= swapShare
                        activeCycle.exitQuantity += exitQty
                        activeCycle.exitNotional += exitNotional
                        activeCycle.exits.append(ExitAttribution(
                            executionId: execution.id,
                            grossPnl: chunkGross,
                            quantity: exitQty
                        ))
                        
                        if activeCycle.direction == .long {
                            signedQty += exitQty
                        } else {
                            signedQty -= exitQty
                        }
                        
                        if activeCycle.openQuantity <= flatEpsilon {
                            trips.append(
                                finalizeCycle(
                                    cycle: activeCycle,
                                    accountId: accountId,
                                    symbol: symbol,
                                    assetClass: assetClass,
                                    closedAt: execution.executedAt,
                                    keyCollisions: &keyCollisions,
                                    importGroup: nil,
                                    contractMultiplier: multiplier != 1 ? multiplier : nil,
                                    breakevenThreshold: resolveBreakevenThreshold(
                                        for: activeCycle,
                                        options: options,
                                        multiplier: multiplier
                                    )
                                )
                            )
                            cycle = nil
                        }
                    }
                }
                
                if feeRemaining != 0, let activeCycle = cycle {
                    activeCycle.fees += feeRemaining
                }
                if swapRemaining != 0, let activeCycle = cycle {
                    activeCycle.swap += swapRemaining
                }
            }
            
            // Finalize any remaining open position at the end of the execution stream
            if let activeCycle = cycle {
                trips.append(
                    finalizeCycle(
                        cycle: activeCycle,
                        accountId: accountId,
                        symbol: symbol,
                        assetClass: assetClass,
                        closedAt: nil,
                        keyCollisions: &keyCollisions,
                        importGroup: nil,
                        contractMultiplier: multiplier != 1 ? multiplier : nil,
                        breakevenThreshold: resolveBreakevenThreshold(for: activeCycle, options: options, multiplier: multiplier)
                    )
                )
            }
        }
        
        // Sort reconstructed trades chronologically by open time
        trips.sort {
            if $0.openedAt != $1.openedAt {
                return $0.openedAt < $1.openedAt
            }
            return $0.key < $1.key
        }
        
        return trips
    }
    
    /// Fee configured in the journal defaults for fills that do not carry a broker commission.
    /// Broker reported fees always win, so the rule is only a fallback.
    private static func defaultFeeShare(
        quantity: Decimal,
        reportedFee: Decimal,
        options: Options,
        accountId: String,
        symbol: String
    ) -> Decimal {
        guard reportedFee == 0 else { return 0 }
        return JournalDefaultsEngine.defaultFeePerUnit(
            quantity: quantity,
            accountId: accountId,
            symbol: symbol,
            defaults: options.defaults
        )
    }
    
    /// Break-even band (net P&L) configured for the journal, in the reporting currency.
    private static func resolveBreakevenThreshold(for cycle: OpenCycle, options: Options, multiplier: Decimal) -> Decimal {
        let avgEntry = cycle.entryQuantity > 0 ? (cycle.entryNotional / cycle.entryQuantity) : 0
        return JournalDefaultsEngine.breakevenThreshold(
            defaults: options.defaults,
            entryPrice: avgEntry,
            quantity: cycle.entryQuantity,
            multiplier: multiplier
        )
    }
}
