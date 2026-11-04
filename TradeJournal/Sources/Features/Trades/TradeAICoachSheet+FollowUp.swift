import SwiftUI
import UIKit

// MARK: - Live Position Snapshot & Follow-Up Chat Execution
extension TradeAICoachSheet {
    
    internal func buildLivePositionSnapshot(isVi: Bool) -> String {
        let currentTrade = dataStore.trades.first(where: { $0.key == trade.key }) ?? trade
        let latestBar = activeBars?.last
        let curPrice: Decimal = {
            if let barClose = latestBar?.close {
                return barClose
            }
            if isOpen {
                return currentTrade.avgEntry
            } else {
                return currentTrade.avgExit ?? currentTrade.avgEntry
            }
        }()
        let isShort = currentTrade.direction == .short
        
        let tz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
        let nowStr = Formatters.isoDateTime(Date(), timeZone: tz)
        let openedStr = Formatters.isoDateTime(currentTrade.openedAt, timeZone: tz)
        
        let entryPriceStr = Formatters.price(currentTrade.avgEntry, symbol: currentTrade.symbol)
        let curPriceStr = Formatters.price(curPrice, symbol: currentTrade.symbol)
        let activeVol: Decimal = (isOpen && currentTrade.openQuantity > 0) ? currentTrade.openQuantity : currentTrade.quantity
        let volStr = (currentTrade.isPartiallyClosed && isOpen)
            ? "\(Formatters.formatDecimal(currentTrade.openQuantity, maxDecimals: 2)) / \(Formatters.formatDecimal(currentTrade.quantity, maxDecimals: 2))"
            : Formatters.formatDecimal(currentTrade.quantity, maxDecimals: 2)
        
        // P&L and Points
        let priceDelta = isShort ? (currentTrade.avgEntry - curPrice) : (curPrice - currentTrade.avgEntry)
        let spec = AssetContractEngine.spec(for: currentTrade.symbol)
        let pipDivisor: Decimal = spec.pipSize > 0 ? spec.pipSize : 0.0001
        let pipsDelta = priceDelta / pipDivisor
        let pipsDeltaDouble = (pipsDelta as NSDecimalNumber).doubleValue
        let pipsDeltaStr = Formatters.pips(pipsDeltaDouble, signed: true)
        
        // Unrealized P&L
        let unpnl: Decimal = {
            if isOpen {
                let floatingGross = AssetContractEngine.calculateGrossPnl(
                    symbol: currentTrade.symbol,
                    direction: currentTrade.direction,
                    quantity: activeVol,
                    entryPrice: currentTrade.avgEntry,
                    exitPrice: curPrice,
                    customMultiplier: AssetContractEngine.customMultiplier(for: currentTrade.symbol, multipliers: dataStore.multipliers),
                    conversionRates: dataStore.currencyConversion.rates
                )
                if currentTrade.isPartiallyClosed {
                    return currentTrade.netPnl + floatingGross
                }
                return floatingGross
            } else {
                return currentTrade.netPnl
            }
        }()
        let pnlStr = Formatters.formatPnL(unpnl, currency: "USD")
        
        // R-Multiple
        let rStr: String = {
            guard let sl = currentTrade.stopLoss else { return "N/A" }
            let riskPerUnit = abs(currentTrade.avgEntry - sl)
            guard riskPerUnit > 0 else { return "N/A" }
            let r = priceDelta / riskPerUnit
            let rDouble = (r as NSDecimalNumber).doubleValue
            return Formatters.formatRMultiple(rDouble)
        }()
        
        // Target Distances
        let slDistStr: String = {
            guard let sl = currentTrade.stopLoss else { return isVi ? "Chưa cài" : "Not set" }
            let dist = abs(curPrice - sl)
            let pips = dist / pipDivisor
            return "\(Formatters.pips(pips)) (SL @ \(Formatters.price(sl, symbol: currentTrade.symbol)))"
        }()
        let tpDistStr: String = {
            guard let tp = currentTrade.profitTarget else { return isVi ? "Chưa cài" : "Not set" }
            let dist = abs(tp - curPrice)
            let pips = dist / pipDivisor
            return "\(Formatters.pips(pips)) (TP @ \(Formatters.price(tp, symbol: currentTrade.symbol)))"
        }()
        
        // Extremes reached (MFE / MAE)
        let extremesStr: String = {
            guard let b = activeBars, !b.isEmpty else { return "" }
            let highs = b.map { $0.high }
            let lows = b.map { $0.low }
            guard let maxH = highs.max(), let minL = lows.min() else { return "" }
            let bestPrice = isShort ? minL : maxH
            let worstPrice = isShort ? maxH : minL
            let bestDelta = isShort ? (currentTrade.avgEntry - bestPrice) : (bestPrice - currentTrade.avgEntry)
            let worstDelta = isShort ? (currentTrade.avgEntry - worstPrice) : (worstPrice - currentTrade.avgEntry)
            let bestPips = (bestDelta / pipDivisor as NSDecimalNumber).doubleValue
            let worstPips = (worstDelta / pipDivisor as NSDecimalNumber).doubleValue
            let bestPriceStr = Formatters.price(bestPrice, symbol: currentTrade.symbol)
            let worstPriceStr = Formatters.price(worstPrice, symbol: currentTrade.symbol)
            let bestPipsStr = Formatters.pips(bestPips, signed: true)
            let worstPipsStr = Formatters.pips(worstPips, signed: true)
            
            if isVi {
                return "\n  • Đỉnh lợi nhuận từng đạt (MFE): \(bestPriceStr) (\(bestPipsStr))\n  • Mức sụt giảm tối đa từng chịu (MAE): \(worstPriceStr) (\(worstPipsStr))"
            } else {
                return "\n  • Max Favorable Excursion (MFE Peak): \(bestPriceStr) (\(bestPipsStr))\n  • Max Adverse Excursion (MAE Drawdown): \(worstPriceStr) (\(worstPipsStr))"
            }
        }()
        
        let durationStr: String = {
            let diff = Date().timeIntervalSince(currentTrade.openedAt)
            let mins = Int(max(1, diff / 60))
            let hours = mins / 60
            if hours > 0 {
                return "\(hours)h \(mins % 60)m"
            } else {
                return "\(mins)m"
            }
        }()
        
        let partialInfoVi = (currentTrade.isPartiallyClosed && isOpen)
            ? "\n• Chốt lời một phần (Partial TP): Đã bỏ túi (Banked): \(Formatters.formatPnL(currentTrade.netPnl, currency: "USD")) | Khối lượng còn lại: \(Formatters.formatDecimal(currentTrade.openQuantity, maxDecimals: 2)) lots"
            : ""
        let partialInfoEn = (currentTrade.isPartiallyClosed && isOpen)
            ? "\n• Partial Close: Banked profit: \(Formatters.formatPnL(currentTrade.netPnl, currency: "USD")) | Active runner volume: \(Formatters.formatDecimal(currentTrade.openQuantity, maxDecimals: 2)) lots"
            : ""
        
        if isVi {
            return """
            [TRẠNG THÁI VỊ THẾ THỜI GIAN THỰC (CẬP NHẬT TẠI \(nowStr))]:
            • Cặp tiền: \(currentTrade.symbol) | Vị thế: \(isShort ? "SELL / SHORT" : "BUY / LONG") | Khối lượng: \(volStr) lots\(partialInfoVi)
            • Thời gian mở: \(openedStr) (Thời gian đã giữ lệnh: \(durationStr))
            • Giá vào (Entry): \(entryPriceStr)
            • Thị giá hiện tại: \(curPriceStr) (Biên độ lãi/lỗ hiện tại: \(pipsDeltaStr))
            • Lợi nhuận tạm tính hiện tại: \(pnlStr) (Tỷ lệ: \(rStr))
            • Cắt lỗ (SL hiện tại): \(slDistStr)
            • Chốt lời (TP hiện tại): \(tpDistStr)\(extremesStr)
            """
        } else {
            return """
            [EXACT REAL-TIME POSITION STATE AT THIS MOMENT (TIMESTAMP: \(nowStr))]:
            • Symbol: \(currentTrade.symbol) | Direction: \(isShort ? "SELL / SHORT" : "BUY / LONG") | Volume: \(volStr) lots\(partialInfoEn)
            • Opened At: \(openedStr) (Time elapsed: \(durationStr))
            • Entry Price: \(entryPriceStr)
            • Current Market Price: \(curPriceStr) (Delta: \(pipsDeltaStr))
            • Unrealized P&L Right Now: \(pnlStr) (Current R: \(rStr))
            • Distance to Stop Loss (SL): \(slDistStr)
            • Distance to Take Profit (TP): \(tpDistStr)\(extremesStr)
            """
        }
    }

    internal func submitFollowUpQuestion() {
        let q = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSubmittingFollowUp else { return }
        
        let userMsg = AICoachMessage(role: "user", content: q)
        self.followUpMessages.append(userMsg)
        self.followUpQuery = ""
        self.isSubmittingFollowUp = true
        
        let chartBase64 = selectedChartImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        
        Task {
            if self.isOpen || self.activeBars == nil {
                await refreshActiveBars(force: true)
            }
            
            var historyToSend: [AICoachMessage] = []
            if !self.coachingResult.isEmpty {
                historyToSend.append(AICoachMessage(role: "assistant", content: self.coachingResult))
            }
            historyToSend.append(contentsOf: self.followUpMessages)
            
            let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
            let liveSnapshot = buildLivePositionSnapshot(isVi: isVi)
            
            var promptComponents: [String] = []
            promptComponents.append(isVi ? "CÂU HỎI CỦA TRADER:\n\"\(q)\"" : "TRADER INQUIRY:\n\"\(q)\"")
            promptComponents.append(liveSnapshot)

            if let b = activeBars, !b.isEmpty {
                let footprintData = await SessionFootprintCoordinator.shared.loadKeyLevels(for: trade.symbol, recentBars: b)
                let pats = SessionFootprintCoordinator.shared.scanConfluentPatterns(bars: b, keyLevels: footprintData.levels)
                let footprintBlock = AIPromptBuilder.buildFootprintAndPatternsBlock(
                    symbol: trade.symbol,
                    currentPrice: b.last?.close ?? trade.avgEntry,
                    keyLevels: footprintData.levels,
                    sessionProfiles: footprintData.profiles,
                    developingProfiles: footprintData.developingProfiles,
                    patterns: pats,
                    isVi: isVi
                )
                if !footprintBlock.isEmpty {
                    promptComponents.append(footprintBlock)
                }

                let h1Series = AIPromptBuilder.buildH1CandleSeriesSummary(
                    bars: b,
                    count: 15,
                    symbol: trade.symbol,
                    isVi: isVi
                )
                let h1Block = isVi ? """
                [DIỄN BIẾN CHUỖI 15 NẾN H1 GẦN NHẤT (OHLC + WILDER RSI 14)]:
                \(h1Series)
                """ : """
                [RECENT 15-CANDLE H1 EXECUTION SERIES (OHLC + WILDER RSI 14)]:
                \(h1Series)
                """
                promptComponents.append(h1Block)
            }

            var augmentedPrompt = promptComponents.joined(separator: "\n\n")
            if isVi {
                augmentedPrompt += """


                CHỈ THỊ PHÂN TÍCH & TRẢ LỜI:
                - BẮT BUỘC: Trả lời 100% bằng TIẾNG VIỆT, đi thẳng vào câu hỏi của trader.
                - ĐỐI CHIẾU với các mốc Footprint POC bậc thang (Weekly POC, Daily POC, Tokyo/London/NY POC, Naked POC) và phản ứng nến Price Action (rút râu, từ chối giá, engulfing).
                - Đưa ra kết luận hành động dứt khoát: Giữ nguyên lệnh, Dời SL về hòa vốn (BE), hay Chốt một phần lợi nhuận (nêu rõ số lot chốt và mức SL mới).
                """
            } else {
                augmentedPrompt += """


                ANALYSIS & RESPONSE DIRECTIVE:
                - Respond directly and concisely in English to the trader's inquiry.
                - Correlate directly with the Footprint Staircase POC levels (Weekly, Daily, Session, Naked POCs) and real-time Price Action reactions.
                - Provide a decisive operational directive: Hold, Move SL to BE, Partial TP (state volume and new SL), or Close Now.
                """
            }
            
            do {
                let response = try await AIReflectionService.shared.requestReflection(
                    action: .ask,
                    prompt: augmentedPrompt,
                    metrics: nil,
                    edgeScore: nil,
                    language: dataStore.aiSettings.language,
                    chartImageBase64: chartBase64,
                    sessionSummary: nil,
                    conversationHistory: historyToSend
                )
                await MainActor.run {
                    self.followUpMessages.append(AICoachMessage(role: "assistant", content: response))
                    self.isSubmittingFollowUp = false
                    self.isSavedToNotes = false
                    self.isSavedToNotebook = false
                    AICoachSessionStore.shared.save(key: self.trade.key, result: self.coachingResult, followUps: self.followUpMessages)
                }
            } catch {
                await MainActor.run {
                    self.followUpMessages.append(AICoachMessage(role: "assistant", content: "Error: \(error.localizedDescription)"))
                    self.isSubmittingFollowUp = false
                }
            }
        }
    }
}
