import Foundation
import Combine

// MARK: - Reset, Demo Data & CSV Export
extension TradeDataStore {
    public func resetAllData() {
        executions.removeAll()
        executionHashes.removeAll()
        trades.removeAll()
        calendarNotes.removeAll()
        propAccounts.removeAll()
        propEntries.removeAll()
        propReceipts.removeAll()
        propAudits.removeAll()
        attachments.removeAll()
        createInitialDefaultAccount()
        rebuildAllAccounts()
        saveToDisk(immediate: true)
        AppLogger.info("Reset all trading data to 100% clean blank state.")
    }
    
    public func loadDemoData() {
        if let existing = accounts.first(where: { $0.broker == "demo" }) {
            if existing.archivedAt != nil {
                archiveAccount(id: existing.id, archived: false)
            }
            selectedAccountId = existing.id
            return
        }
        
        let demoAccountId = JournalIds.newId()
        let demoAccount = Account(
            id: demoAccountId,
            name: "Demo data",
            broker: "demo",
            kind: .import,
            currency: "USD",
            initialBalance: 25000,
            profitCalcMethod: .fifo,
            autoSync: false,
            visibleInJournal: true
        )
        accounts.append(demoAccount)
        
        let fills = generateDemoExecutions(demoAccountId: demoAccountId)
        importExecutions(accountId: demoAccountId, newExecutions: fills)
        selectedAccountId = demoAccountId
        saveToDisk(immediate: true)
        AppLogger.info("Loaded demo data: \(fills.count) executions for demo account \(demoAccountId)")
    }

    private func generateDemoExecutions(demoAccountId: String) -> [Execution] {
        var fills: [Execution] = []
        var s: Double = 42
        let rnd: () -> Double = {
            s = Double((Int64(s * 1103515245) + 12345) % 2147483648)
            return s / 2147483648.0
        }
        
        struct Spec {
            let symbol: String
            let price: Double
            let qtyMin: Double
            let qtyMax: Double
        }
        let symbols: [Spec] = [
            Spec(symbol: "NVDA", price: 128, qtyMin: 50, qtyMax: 150),
            Spec(symbol: "TSLA", price: 242, qtyMin: 30, qtyMax: 100),
            Spec(symbol: "AAPL", price: 226, qtyMin: 50, qtyMax: 200),
            Spec(symbol: "AMD", price: 158, qtyMin: 80, qtyMax: 250),
            Spec(symbol: "META", price: 512, qtyMin: 20, qtyMax: 60),
            Spec(symbol: "SPY", price: 556, qtyMin: 40, qtyMax: 120)
        ]
        
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        
        func atDate(day: Date, minute: Int) -> Date {
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = 9 + (minute + 30) / 60
            c.minute = (minute + 30) % 60
            c.second = 15
            return cal.date(from: c) ?? day
        }
        
        for dayOffset in 2...16 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let w = cal.component(.weekday, from: day)
            if w == 1 || w == 7 { continue }
            
            let numTrades = 1 + Int(rnd() * 3)
            var minute = 15 + Int(rnd() * 20)
            for _ in 0..<numTrades {
                let spec = symbols[Int(rnd() * Double(symbols.count))]
                let isBuy = rnd() < 0.7
                let entrySide: TradeSide = isBuy ? .buy : .sell
                let exitSide: TradeSide = isBuy ? .sell : .buy
                let quantity = round(spec.qtyMin + rnd() * (spec.qtyMax - spec.qtyMin))
                let slippage = (rnd() - 0.5) * 0.4
                let entry = spec.price + slippage
                let entryTime = atDate(day: day, minute: minute)
                
                fills.append(Execution(
                    accountId: demoAccountId,
                    symbol: spec.symbol,
                    side: entrySide,
                    quantity: Decimal(quantity),
                    price: Decimal(string: String(format: "%.2f", entry)) ?? Decimal(entry),
                    fee: 1,
                    executedAt: entryTime,
                    assetClass: "equity",
                    source: "import"
                ))
                
                let hold = 20 + Int(rnd() * 120)
                let exitTime = atDate(day: day, minute: minute + hold)
                let win = rnd() < 0.58
                let movePct = win ? (0.006 + rnd() * 0.02) : -(0.005 + rnd() * 0.015)
                let exit = isBuy ? (entry * (1 + movePct)) : (entry * (1 - movePct))
                
                if rnd() < 0.3 {
                    let part1 = round(quantity * 0.5)
                    let part2 = quantity - part1
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(part1),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                    let exit2Time = atDate(day: day, minute: minute + hold + 15)
                    let exit2 = exit * (1 + (rnd() - 0.5) * 0.004)
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(part2),
                        price: Decimal(string: String(format: "%.2f", exit2)) ?? Decimal(exit2),
                        fee: 1,
                        executedAt: exit2Time,
                        assetClass: "equity",
                        source: "import"
                    ))
                } else {
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(quantity),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                }
                minute += hold + 10 + Int(rnd() * 50)
                if minute > 340 { break }
            }
        }
        
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now) {
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "NVDA",
                side: .buy,
                quantity: 120,
                price: 131.42,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 44),
                assetClass: "equity",
                source: "import"
            ))
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "SPY",
                side: .sell,
                quantity: 80,
                price: 561.18,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 92),
                assetClass: "equity",
                source: "import"
            ))
        }
        return fills
    }
    
    // MARK: - CSV Export
    
    /// Exports all trades to standard CSV format
    public func exportTradesCsv() -> String {
        var lines = ["Key,Account,Symbol,Direction,Status,OpenedAt,ClosedAt,Quantity,AvgEntry,AvgExit,GrossPnL,Fees,Swap,NetPnL,Notes,Tags"]
        let f = ISO8601DateFormatter()
        
        let escapeCsv: (String) -> String = { text in
            if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
                let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return text
        }
        
        for t in trades {
            let row = [
                escapeCsv(t.key),
                escapeCsv(t.accountId),
                escapeCsv(t.symbol),
                escapeCsv(t.direction.rawValue),
                escapeCsv(t.status.rawValue),
                escapeCsv(f.string(from: t.openedAt)),
                escapeCsv(t.closedAt.map { f.string(from: $0) } ?? ""),
                "\(t.quantity)",
                "\(t.avgEntry)",
                t.avgExit.map { "\($0)" } ?? "",
                "\(t.grossPnl)",
                "\(t.fees)",
                "\(t.swapAmount)",
                "\(t.netPnl)",
                escapeCsv(t.notes ?? ""),
                escapeCsv(t.tags.joined(separator: ";"))
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
}
