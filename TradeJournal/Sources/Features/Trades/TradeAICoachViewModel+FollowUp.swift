import Foundation
import UIKit

// MARK: - Live Position Snapshot & Follow-Up Chat Execution
extension TradeAICoachViewModel {
    
    public func buildLivePositionSnapshot(dataStore: TradeDataStore, isVi: Bool) -> String {
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
        let unpnlStr = Formatters.currency(unpnl, currency: currentTrade.accountCurrency)
        
        // R Multiple
        let rMultStr: String = {
            if let r = currentTrade.rMultiple {
                return Formatters.rMultiple(r)
            }
            if let sl = currentTrade.stopLoss, sl > 0 {
                let riskDist = abs(currentTrade.avgEntry - sl)
                if riskDist > 0 {
                    let liveR = priceDelta / riskDist
                    let liveRDouble = (liveR as NSDecimalNumber).doubleValue
                    return Formatters.rMultiple(liveRDouble)
                }
            }
            return "N/A"
        }()
        
        // SL / TP Distances
        let slInfo: String = {
            guard let sl = currentTrade.stopLoss, sl > 0 else { return isVi ? "Chưa đặt (Rủi ro mở)" : "None (Uncapped risk)" }
            let slPriceStr = Formatters.price(sl, symbol: currentTrade.symbol)
            let slDelta = isShort ? (sl - curPrice) : (curPrice - sl)
            let slPips = slDelta / pipDivisor
            let slPipsDouble = (slPips as NSDecimalNumber).doubleValue
            let status = slDelta < 0 ? (isVi ? "ĐANG VI PHẠM SL" : "SL BREACHED") : "\(Formatters.pips(slPipsDouble))"
            return "\(slPriceStr) (\(status))"
        }()
        
        let tpInfo: String = {
            guard let tp = currentTrade.profitTarget, tp > 0 else { return isVi ? "Chưa đặt (Chạy theo trailing/cấu trúc)" : "None (Discretionary runner)" }
            let tpPriceStr = Formatters.price(tp, symbol: currentTrade.symbol)
            let tpDelta = isShort ? (curPrice - tp) : (tp - curPrice)
            let tpPips = tpDelta / pipDivisor
            let tpPipsDouble = (tpPips as NSDecimalNumber).doubleValue
            let tpStatus = tpDelta <= 0 ? (isVi ? "ĐÃ ĐẠT TP" : "TP HIT") : "\(Formatters.pips(tpPipsDouble)) \(isVi ? "nữa" : "away")"
            return "\(tpPriceStr) (\(tpStatus))"
        }()
        
        let durationStr: String = {
            let endTime = currentTrade.closedAt ?? Date()
            let diff = endTime.timeIntervalSince(currentTrade.openedAt)
            if diff < 60 { return "\(Int(diff))s" }
            if diff < 3600 { return "\(Int(diff / 60))m" }
            let h = Int(diff / 3600)
            let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(h)h \(m)m"
        }()
        
        let play = dataStore.playbooks.first(where: { $0.id == currentTrade.playbookId })?.title ?? "Discretionary"
        
        if isVi {
            return """
            [SNAPSHOT VỊ THẾ LIVE - DỮ LIỆU THỜI GIAN THỰC]:
            • Mã tài sản: \(currentTrade.symbol) (\(currentTrade.direction == .short ? "SELL / SHORT" : "BUY / LONG"))
            • Trạng thái lệnh: \(isOpen ? "ĐANG MỞ (LIVE)" : "ĐÃ ĐÓNG (REVIEW)")
            • Khối lượng: \(volStr) Lots
            • Giá vào lệnh (Entry): \(entryPriceStr) (Lúc \(openedStr))
            • Giá hiện tại / Giá đóng: \(curPriceStr) (Snapshot lúc \(nowStr))
            • Biến động pips hiện tại: \(pipsDeltaStr)
            • Lợi nhuận tạm tính (P&L): \(unpnlStr) (R-Multiple: \(rMultStr))
            • Cắt lỗ (SL): \(slInfo)
            • Chốt lời (TP): \(tpInfo)
            • Thời gian giữ lệnh: \(durationStr)
            • Chiến lược Playbook: \(play)
            """
        } else {
            return """
            [REAL-TIME LIVE POSITION SNAPSHOT]:
            • Asset: \(currentTrade.symbol) (\(currentTrade.direction == .short ? "SELL / SHORT" : "BUY / LONG"))
            • Position State: \(isOpen ? "OPEN (LIVE)" : "CLOSED (POST-MORTEM)")
            • Volume: \(volStr) Lots
            • Avg Entry: \(entryPriceStr) (Opened: \(openedStr))
            • Current/Exit Price: \(curPriceStr) (At: \(nowStr))
            • Floating Pips: \(pipsDeltaStr)
            • Unrealized/Net P&L: \(unpnlStr) (R-Multiple: \(rMultStr))
            • Stop Loss (SL): \(slInfo)
            • Take Profit (TP): \(tpInfo)
            • Trade Duration: \(durationStr)
            • Playbook Strategy: \(play)
            """
        }
    }

    public func submitFollowUpQuestion(dataStore: TradeDataStore) {
        let q = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSubmittingFollowUp else { return }
        
        let userMsg = AICoachMessage(role: "user", content: q)
        self.followUpMessages.append(userMsg)
        self.followUpQuery = ""
        self.isSubmittingFollowUp = true
        
        let chartBase64 = selectedChartImage?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        
        Task {
            if self.isOpen || self.activeBars == nil {
                await refreshActiveBars(dataStore: dataStore, force: true)
            }
            
            var historyToSend: [AICoachMessage] = []
            if !self.coachingResult.isEmpty {
                historyToSend.append(AICoachMessage(role: "assistant", content: self.coachingResult))
            }
            historyToSend.append(contentsOf: self.followUpMessages)
            
            let isVi = (dataStore.aiSettings.language.isEmpty || dataStore.aiSettings.language == "vi")
            let liveSnapshot = buildLivePositionSnapshot(dataStore: dataStore, isVi: isVi)
            
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
                self.followUpMessages.append(AICoachMessage(role: "assistant", content: response))
                self.isSubmittingFollowUp = false
                self.isSavedToNotes = false
                self.isSavedToNotebook = false
                AICoachSessionStore.shared.save(key: self.trade.key, result: self.coachingResult, followUps: self.followUpMessages)
            } catch {
                self.followUpMessages.append(AICoachMessage(role: "assistant", content: "Error: \(error.localizedDescription)"))
                self.isSubmittingFollowUp = false
            }
        }
    }
}
