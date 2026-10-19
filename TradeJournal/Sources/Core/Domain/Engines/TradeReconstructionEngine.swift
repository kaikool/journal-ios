import Foundation

/// Trade reconstruction engine pairing raw executions into complete round-trips using FIFO/LIFO
public enum TradeReconstructionEngine {
    
    public static let flatEpsilon: Decimal = Decimal(sign: .plus, exponent: -9, significand: 1) // 1e-9
    
    public struct Options {
        public let method: ProfitCalcMethod
        public let multipliers: [String: Decimal]
        
        public init(method: ProfitCalcMethod = .fifo, multipliers: [String: Decimal] = [:]) {
            self.method = method
            self.multipliers = multipliers
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
            self.executionIds = []
            self.exits = []
            self.executionCount = 0
        }
        
        var openQuantity: Decimal {
            lots.reduce(Decimal.zero) { $0 + $1.quantity }
        }
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
        contractMultiplier: Decimal?
    ) -> Trade {
        let openQty = cycle.openQuantity
        let netPnl = cycle.grossPnl - cycle.fees
        let isOpen = openQty > flatEpsilon
        
        let status: TradeStatus
        if isOpen {
            status = .open
        } else if abs(netPnl) <= flatEpsilon {
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
            
            var cycle: OpenCycle? = nil
            
            for execution in group {
                var signedQty = execution.side == .buy ? execution.quantity : -execution.quantity
                var feeRemaining = execution.fee
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
                        activeCycle.fees += feeRemaining
                        feeRemaining = 0
                        signedQty = 0
                    } else {
                        let openQty = activeCycle.openQuantity
                        let exitQty = min(abs(signedQty), openQty)
                        let matchedNotional = consumeLots(cycle: activeCycle, quantity: exitQty, method: options.method)
                        let avgMatchedEntry = exitQty > 0 ? (matchedNotional / exitQty) : 0
                        let exitNotional = exitQty * execution.price
                        
                        let chunkGross = AssetContractEngine.calculateGrossPnl(
                            symbol: symbol,
                            direction: activeCycle.direction,
                            quantity: exitQty,
                            entryPrice: avgMatchedEntry,
                            exitPrice: execution.price,
                            customMultiplier: options.multipliers[symbol]
                        )
                        
                        let feeShare: Decimal
                        if abs(signedQty) > 0 {
                            feeShare = feeRemaining * (exitQty / abs(signedQty))
                        } else {
                            feeShare = 0
                        }
                        
                        activeCycle.grossPnl += chunkGross
                        activeCycle.fees += feeShare
                        feeRemaining -= feeShare
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
                                    contractMultiplier: multiplier != 1 ? multiplier : nil
                                )
                            )
                            cycle = nil
                        }
                    }
                }
                
                if feeRemaining != 0, let activeCycle = cycle {
                    activeCycle.fees += feeRemaining
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
                        contractMultiplier: multiplier != 1 ? multiplier : nil
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
}
