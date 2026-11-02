import Foundation

// MARK: - Pre-Trade Multi-Timeframe Prompt Builder Extension
// Integrates Master Institutional Trader Persona, Dynamic Contract Sizing,
// Empirical Behavioral Leak Mining, and Live Price Action Dynamics (H1/M15).
extension AIPromptBuilder {
    
    /// Assembles a streamlined, high-signal multi-timeframe market structure prompt (D1, H4, H1, M15) for pre-trade forward planning.
    public static func buildPreTradeAnalysisPrompt(
        symbol: String,
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar] = [],
        marketSnapshot: MarketStateSnapshot? = nil,
        events: [ForexFactoryEvent] = [],
        language: String = "vi",
        sessionSummary: AIAccountSessionSummary? = nil,
        traderProfile: TraderProfileConfig? = nil,
        displayTimeZone: String = "UTC",
        previousAnalysis: String? = nil,
        liveCandleUpdate: String? = nil,
        hasImage: Bool = false
    ) -> String {
        let isVi = language == "vi"
        
        func formatPrice(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        let execBars = !h1Bars.isEmpty ? h1Bars : m15Bars
        
        let currentPrice: String = {
            if let last = execBars.last ?? h4Bars.last ?? d1Bars.last {
                return formatPrice(last.close)
            }
            return "N/A"
        }()
        
        // 1. D1 Macro Range (PDH / PDL / PDC / 14-day ADR)
        let d1PDH: String
        let d1PDL: String
        let d1PDC: String
        let d1ADR: String
        if d1Bars.count >= 2 {
            let prevDay = d1Bars[d1Bars.count - 2]
            d1PDH = formatPrice(prevDay.high)
            d1PDL = formatPrice(prevDay.low)
            d1PDC = formatPrice(prevDay.close)
            
            let lookback = min(14, d1Bars.count - 1)
            let ranges = d1Bars.suffix(lookback).map { $0.high - $0.low }
            let avgRange = ranges.reduce(Decimal.zero, +) / Decimal(lookback)
            d1ADR = formatPrice(avgRange)
        } else {
            d1PDH = "N/A"
            d1PDL = "N/A"
            d1PDC = "N/A"
            d1ADR = "N/A"
        }
        
        // 2. Trend & Momentum Analysis (EMA 21/50 Multi-Timeframe)
        let emaAnalysis = MovingAverageEngine.analyzeMultiTimeframe(
            barsD1: d1Bars,
            barsH4: h4Bars,
            barsH1: h1Bars,
            barsM15: m15Bars,
            symbol: symbol
        )
        
        func formatEMALevels(_ snap: TimeframeEMASnapshot?, tfName: String) -> String {
            guard let snap = snap, let e21 = snap.ema21, let e50 = snap.ema50 else {
                return isVi ? "Chua du du lieu nen tinh EMA 21/50" : "Insufficient bars for EMA 21/50"
            }
            let p21 = formatPrice(e21)
            let p50 = formatPrice(e50)
            let cur = snap.currentPrice
            let dist = cur - e21
            let distVal = formatPrice(abs(dist))
            
            let posDesc: String
            if isVi {
                posDesc = dist >= 0 ? "Gia tren EMA 21 (+\(distVal))" : "Gia duoi EMA 21 (-\(distVal))"
            } else {
                posDesc = dist >= 0 ? "Price above EMA 21 (+\(distVal))" : "Price below EMA 21 (-\(distVal))"
            }
            
            let spreadDesc: String
            if isVi {
                spreadDesc = e21 >= e50 ? "EMA 21 > EMA 50 (Thien Tang)" : "EMA 21 < EMA 50 (Thien Giam)"
            } else {
                spreadDesc = e21 >= e50 ? "EMA 21 > EMA 50 (Bullish)" : "EMA 21 < EMA 50 (Bearish)"
            }
            
            return "EMA(21) = \(p21) | EMA(50) = \(p50) | \(posDesc) | \(spreadDesc)"
        }
        
        let d1EMAStr = formatEMALevels(emaAnalysis.d1, tfName: "D1")
        let h4EMAStr = formatEMALevels(emaAnalysis.h4, tfName: "H4")
        let h1EMAStr = formatEMALevels(emaAnalysis.h1, tfName: "H1")
        
        // Accurate H4 Swing High & Swing Low Detection
        let h4Pivots = LiquidityEngine.identifyPivots(bars: h4Bars, window: 2, timeframe: "H4")
        let h4SwingHighStr: String = {
            if let high = h4Pivots.filter({ $0.type == .buySide }).last?.price {
                return formatPrice(high)
            }
            if let maxBar = h4Bars.suffix(20).max(by: { $0.high < $1.high }) {
                return formatPrice(maxBar.high)
            }
            return "N/A"
        }()
        let h4SwingLowStr: String = {
            if let low = h4Pivots.filter({ $0.type == .sellSide }).last?.price {
                return formatPrice(low)
            }
            if let minBar = h4Bars.suffix(20).min(by: { $0.low < $1.low }) {
                return formatPrice(minBar.low)
            }
            return "N/A"
        }()
        
        // 3. Institutional Liquidity & SFP Sweeps
        let liquidity = LiquidityEngine.analyzeLiquidity(
            symbol: symbol,
            barsM15: execBars,
            barsH4: h4Bars,
            barsD1: d1Bars
        )
        
        // 3b. Recent H4 Candles (Last 3 bars OHLC)
        let h4CandlesSummary = buildH4CandleSummary(bars: h4Bars, count: 3, isVi: isVi)
        
        // 3c. 24-Candle H1 Execution Series (OHLC + EMA 21/50 + Wilder RSI 14)
        let h1CandlesSummary = buildH1CandleSeriesSummary(bars: execBars, count: 24, symbol: symbol, isVi: isVi)
        
        // 3d. 16-Candle M15 Micro-Execution Series
        let m15CandlesSummary = buildM15CandleSeriesSummary(bars: m15Bars, count: 16, symbol: symbol, isVi: isVi)
        
        // 3e. Live Unclosed Candle Dynamics (Current Price Action Pulse)
        let liveCandlePulse = buildLiveUnclosedCandlePulse(bar: execBars.last ?? m15Bars.last, isVi: isVi)
        
        let nearestBSLStr: String = {
            if let bsl = liquidity.nearestBSL {
                let dist = liquidity.distanceToBSLPips.map { " (khoang cach \(formatPrice($0)))" } ?? ""
                return "\(bsl.label) tai \(formatPrice(bsl.price))\(dist)"
            }
            return isVi ? "Khong co moc BSL gan" : "No nearby BSL pool"
        }()
        
        let nearestSSLStr: String = {
            if let ssl = liquidity.nearestSSL {
                let dist = liquidity.distanceToSSLPips.map { " (khoang cach \(formatPrice($0)))" } ?? ""
                return "\(ssl.label) tai \(formatPrice(ssl.price))\(dist)"
            }
            return isVi ? "Khong co moc SSL gan" : "No nearby SSL pool"
        }()
        
        let sweepsStr: String = {
            if liquidity.recentSweeps.isEmpty {
                return isVi ? "Khong co nhip quet gan day" : "No recent sweeps"
            }
            return liquidity.recentSweeps.prefix(2).map { sw in
                let typeStr = sw.sweepType == .buySideSwept ? "Quet dinh (Bearish SFP)" : "Quet day (Bullish SFP)"
                return "\(sw.levelName) [\(typeStr)] tai \(formatPrice(sw.sweptPrice)), rau \(formatPrice(sw.wickExtreme))"
            }.joined(separator: "; ")
        }()
        
        // 4. H1 Momentum & RSI Metrics
        let momentumWindow = MomentumEngine.computeWindow(bars: execBars, windowSize: 10)
        let rsiVal = momentumWindow.currentRSI.map { ($0 as NSDecimalNumber).doubleValue }
        let rsiStr: String = {
            guard let val = rsiVal else { return "N/A" }
            let zone: String
            if isVi {
                if val >= 70 { zone = "Qua Mua (>70)" }
                else if val <= 30 { zone = "Qua Ban (<30)" }
                else if val >= 50 { zone = "Thien Tang / Phe Mua kiem soat (50-70)" }
                else { zone = "Thien Giam / Phe Ban kiem soat (30-50)" }
            } else {
                if val >= 70 { zone = "Overbought (>70)" }
                else if val <= 30 { zone = "Oversold (<30)" }
                else if val >= 50 { zone = "Bullish Control (50-70)" }
                else { zone = "Bearish Control (30-50)" }
            }
            return String(format: "%.1f (%@)", val, zone)
        }()
        
        let rsiSignalStr: String = {
            guard let rsi = rsiVal, let ema = momentumWindow.currentEMA9.map({ ($0 as NSDecimalNumber).doubleValue }) else {
                return "N/A"
            }
            let status: String
            if isVi {
                status = rsi >= ema ? "RSI tren Signal (Dong luong Mua)" : "RSI duoi Signal (Dong luong Ban)"
            } else {
                status = rsi >= ema ? "RSI above Signal (Bullish)" : "RSI below Signal (Bearish)"
            }
            return String(format: "%.1f [%@]", ema, status)
        }()
        
        let divStr = isVi ? (momentumWindow.divergenceVi ?? "Khong co phan ky") : (momentumWindow.divergenceEn ?? "None")
        
        // 5. Macro News Catalyst
        let newsBlock: String = {
            let now = Date()
            let highImpacts = events.filter { $0.impact == .high }
            if let nextEvent = highImpacts.first(where: { ($0.date ?? Date.distantPast) > now }),
               let eventDate = nextEvent.date {
                let diffMin = Int(eventDate.timeIntervalSince(now) / 60)
                let timeDesc = diffMin >= 60 ? "\(diffMin / 60)h \(diffMin % 60)m" : "\(diffMin) phut"
                return isVi
                    ? "[LICH TIN TUC]: \(nextEvent.title) (\(nextEvent.country)) cong bo trong \(timeDesc)"
                    : "[CATALYST EVENT]: \(nextEvent.title) (\(nextEvent.country)) in \(timeDesc)"
            }
            return isVi ? "Khong co tin tuc quan trong trong 12h toi" : "No high-impact events within 12h"
        }()
        
        // 6. Active Account Context & Official Contract Sizing
        let tradesToday = sessionSummary?.totalTradesToday ?? 0
        let winsToday = sessionSummary?.winsToday ?? 0
        let lossesToday = sessionSummary?.lossesToday ?? 0
        let beToday = sessionSummary?.breakevensToday ?? 0
        let openToday = sessionSummary?.openTradesToday ?? 0
        
        let todayTradesDesc = isVi
            ? "Tong \(tradesToday) lenh (\(winsToday) Thang | \(lossesToday) Thua | \(beToday) Hoa) | Lenh dang mo: \(openToday)"
            : "Total \(tradesToday) trades (\(winsToday) W | \(lossesToday) L | \(beToday) BE) | Open: \(openToday)"
            
        let pnlTodayVal = sessionSummary.map { NSDecimalNumber(decimal: $0.netPnlToday).doubleValue } ?? 0.0
        let pnlTodayStr = (pnlTodayVal >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlTodayVal))
        
        let streak = sessionSummary?.currentStreakToday ?? 0
        let streakStr: String = {
            if streak > 0 { return isVi ? "Thang \(streak) lenh lien tiep (+)" : "\(streak) wins in a row (+)" }
            if streak < 0 { return isVi ? "Dang thua \(abs(streak)) lenh lien tiep (-)" : "In a \(abs(streak))-loss losing streak (-)" }
            return isVi ? "Chua co chuoi lenh hom nay" : "No active streak today"
        }()
        
        let dailyBufferStr: String = {
            if let buf = sessionSummary?.dailyLossBufferRemainingUsd {
                let limit = sessionSummary?.dailyLossLimitUsd.map { String(format: "$%.2f", ($0 as NSDecimalNumber).doubleValue) } ?? (isVi ? "Theo quy dinh" : "Rule-based")
                let bufVal = (buf as NSDecimalNumber).doubleValue
                return isVi
                    ? "Han muc lo ngay: \(limit) | Dem lo con lai: $\(String(format: "%.2f", bufVal))"
                    : "Daily Loss Limit: \(limit) | Remaining Buffer: $\(String(format: "%.2f", bufVal))"
            }
            return isVi
                ? "Han muc rui ro ngay: 2-3 lenh | Dang tuan thu ky luat"
                : "Daily Risk Budget: 2-3 trades | Disciplined"
        }()
        
        let isStreakOrBufferBreached = streak <= -2 || (sessionSummary?.dailyLossBufferRemainingUsd.map { $0 <= 0 } ?? false)
        
        let riskGuardrailWarning: String = {
            if isStreakOrBufferBreached {
                return isVi
                    ? "\n[CANH BAO RUI RO BAT BUOC]: Trader dang co chuoi thua (-2 lenh tro len) hoac dem lo ngay da cham nguong. AI BAT BUOC TU VAN DUNG NGOAI (FLAT), KHONG MO LENH MOI DE BAO VE TAI KHOAN.\n"
                    : "\n[CRITICAL RISK GUARDRAIL]: Trader is on a losing streak (-2 or worse) or daily loss buffer is exhausted. AI MUST ADVISE FLAT (STAND ASIDE), NO NEW TRADES.\n"
            }
            return ""
        }()
        
        let realBalStr: String = {
            if let bal = sessionSummary?.balance {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return Formatters.formatCurrency(bal, currency: curr)
            }
            return "N/A"
        }()
        
        let equityStr: String = {
            if let eq = sessionSummary?.equity, let bal = sessionSummary?.balance, eq != bal {
                let curr = sessionSummary?.accountCurrency ?? "USD"
                return "| Von rong (Equity): \(Formatters.formatCurrency(eq, currency: curr))"
            }
            return ""
        }()
        
        // Authoritative Contract Specs & Mathematically Grounded Risk
        let instrumentSpec = AssetContractEngine.spec(for: symbol)
        let numericRisk = traderProfile?.numericRiskPercent ?? Decimal(1.0)
        let targetRR = traderProfile?.targetRiskRewardRatio ?? 3.0
        let targetRiskDollars: Decimal = {
            if let bal = sessionSummary?.balance, bal > 0 {
                return bal * (numericRisk / 100)
            }
            return 0
        }()
        let targetRiskDollarsStr = String(format: "$%.2f", (targetRiskDollars as NSDecimalNumber).doubleValue)
        
        let contractSizingBlockVi = """
        [QUY CACH HOP DONG VA TOAN HOC KHOI LUONG LENH (ASSET CONTRACT SIZING)]:
        - Tai san: \(symbol) | Nhom: \(instrumentSpec.assetCategory.rawValue)
        - Kich thuoc hop dong chuan (1.00 lot): \(instrumentSpec.contractSize) don vi
        - Buoc gia Pip: \(instrumentSpec.pipSize)
        - So du thuc te: \(realBalStr) \(equityStr)
        - Ty le rui ro cai dat: \(numericRisk)% von
        - Ngan sach rui ro toi da: \(targetRiskDollarsStr) USD (So tien lo toi da neu cham SL)
        - Muc tieu Ty le Risk/Reward bat buoc: Toi thieu 1:\(String(format: "%.1f", targetRR)) (BAT BUOC TUAN THU)
        - CONG THUC TOAN HOC TINH SO LOT:
          So Lot = (So tien rui ro $) / (|Entry - SL| x Kich thuoc hop dong x Ty gia quy doi)
          Luu y: Khi dua ra thong so Volume trong Setup, bat buoc tinh theo so tien rui ro \(targetRiskDollarsStr) o tren.
        """
        
        let contractSizingBlockEn = """
        [AUTHORITATIVE CONTRACT SIZING & MATHEMATICAL RISK PARAMETERS]:
        - Instrument: \(symbol) | Asset Class: \(instrumentSpec.assetCategory.rawValue)
        - Standard Contract Size (1.00 lot): \(instrumentSpec.contractSize) units
        - Pip Size: \(instrumentSpec.pipSize)
        - Authoritative Balance: \(realBalStr) \(equityStr)
        - Configured Risk Per Trade: \(numericRisk)%
        - Max Risk Dollar Budget: \(targetRiskDollarsStr) USD (Maximum allowed loss at Stop Loss)
        - Mandatory Target Risk/Reward Ratio: Minimum 1:\(String(format: "%.1f", targetRR)) (NON-NEGOTIABLE)
        - MATHEMATICAL POSITION SIZING FORMULA:
          Lots = (Risk Budget $) / (|Entry - SL| x Contract Size x Conversion Rate)
        """
        
        // 7. Empirical Behavioral Leaks Mined from Database
        let behavioralLeaksBlock: String = {
            let mining = TraderBehaviorMiningEngine.mineLeaks(from: TradeDataStore.shared.trades, targetSymbol: symbol)
            return TraderBehaviorMiningEngine.formatForPrompt(result: mining, isVi: isVi)
        }()
        
        // 8. Follow-up Live Update & Thesis Continuity
        var liveUpdateBlock = ""
        if let update = liveCandleUpdate, !update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liveUpdateBlock = isVi
                ? "\n[DIEN BIEN GIA THUC TE VUA CAP NHAT]:\n\(update)\n"
                : "\n[LIVE MARKET PRICE ACTION UPDATE]:\n\(update)\n"
        }
        
        var thesisContinuityBlock = ""
        if let prev = previousAnalysis, !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let condensedPrev = prev.count > 600
                ? String(prev.prefix(600)) + "\n[...trich luoc ke hoach truoc...]"
                : prev
            thesisContinuityBlock = isVi
                ? "\n[KE HOACH DA DUA RA TRUOC DO]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n[DOI CHIEU]: Kiem tra nen moi xem dieu kien kich hoat da dien ra chua, hay cau truc ban dau da bi vi pham.\n"
                : "\n[PRIOR TRADING PLAN]:\n\"\"\"\n\(condensedPrev)\n\"\"\"\n[CONTINUITY]: Check if the entry trigger occurred or if the structure was invalidated.\n"
        }
        
        if isVi {
            return """
            [THONG TIN TAI KHOAN VA TRANG THAI RUI RO]:
            - So du thuc te: \(realBalStr) \(equityStr)
            - Trang thai lenh hom nay: \(todayTradesDesc)
            - PnL rong hom nay: \(pnlTodayStr) | Chuoi lenh: \(streakStr)
            - \(dailyBufferStr)\(riskGuardrailWarning)
            \(contractSizingBlockVi)
            \(behavioralLeaksBlock)
            [CAU TRUC THI TRUONG VA CHI BAO KY THUAT (EMA 21/50 & RSI 14)]:
            - Cap tien: \(symbol) | Thi gia hien tai: \(currentPrice)

            - Khung D1 (Macro Bias): Xu huong [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              EMA D1: \(d1EMAStr)
              Moc gia then chot: Dinh PDH: \(d1PDH) | Day PDL: \(d1PDL) | ADR 14 ngay: \(d1ADR)

            - Khung H4 (Cau truc song va Can TP/SL): Xu huong [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              EMA H4: \(h4EMAStr)
              Moc gia then chot: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              3 nen H4 gan nhat:
            \(h4CandlesSummary)

            - Khung H1 (Thuc thi va Dong luong): Xu huong [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              EMA H1: \(h1EMAStr)
              RSI(14) Wilder: Muc hien tai: \(rsiStr) | Signal: \(rsiSignalStr) | Phan ky: [\(divStr)]
              Vung thanh khoan: BSL gan nhat: \(nearestBSLStr) | SSL gan nhat: \(nearestSSLStr)
              Quet thanh khoan SFP: \(sweepsStr)

            - HANH DONG GIA SONG (LIVE CANDLE PULSE):
            \(liveCandlePulse)

            - Chuoi 24 nen H1 gan nhat (24 gio giao dich lien tuc):
            \(h1CandlesSummary)

            - Chuoi 16 nen M15 gan nhat (4 gio vi mo thuc thi):
            \(m15CandlesSummary)

            - Tin tuc kinh te: \(newsBlock)
            \(liveUpdateBlock)\(thesisContinuityBlock)
            VAI TRO VA NGUYEN TAC CUA NHA GIAO DICH CHUYEN NGHIEP:
            Ban la mot Senior Institutional Portfolio Manager & Master Trader (Nha Giao Dich Chuyen Nghiep kiem Truong Phong Rui Ro Quy).
            Triet ly giao dich:
            1. Giao dich la bai toan bao ve von va cho doi loi the bat doi xung. Tha dung ngoai (FLAT) con hon vao mot lenh kem chat luong hoac R:R khong dat chuan.
            2. Luon nhin thi truong bang con mat hoai nghi, boc tach bay thanh khoan cua phe to chuc.
            3. Phan bien toan dien: Tu chu ky xu huong, can bay thanh khoan, den tin hieu kich hoat nen song va ty le R:R.

            NHIEM VU PHAN TICH VA LAP KE HOACH GIAO DICH (4 PHAN):

            ### 1. Phan bien Xu huong vi mo D1 va Chu ky dong tien
            - Xu huong D1 dang o giai doan nao: Chan song mo rong hay da keo dan bien do (Overextended) xa khoi EMA(21) D1 va sap can kiet luc mua/ban?
            - Phan bien xung dot da khung: D1 tang nhung H4 suy kiet hoac dang tiep can can lon thi tuyet doi khong du dinh.
            - Muc tieu thanh khoan ngay: Kha nang tim ve PDH (\(d1PDH)) hoac PDL (\(d1PDL)).

            ### 2. Cau truc song H4 va Boc tach Bay thanh khoan to chuc
            - Phan dinh ro: Dau la cac vung can bay (Retail Support/Resistance / Equal Highs-Lows) - noi dam dong nho le dat SL de to chuc quet sach?
            - Xac dinh cac vung Cung/Cau to chuc thuc thu (Unmitigated Order Block, Fair Value Gap, Liquidity Void) de lam can muc tieu TP hoac bao ve SL.
            - Neu gia dang o vung tranh chap vo dinh (No-man's land) khong co loi the cau truc: Phan bien ro khong co co so thiet lap can tin cay.

            ### 3. Doc vi Hanh dong Gia Song H1/M15 (Live Price Action Tape Reading) va Tin hieu kich hoat
            - Doc vi cay nen song hien tai va chuoi nen H1/M15: Than nen co hep hay mo rong? Rau nen dang bi tu choi gia the nao? Phe Mua hay Ban dang chiem uu the thuc te ngay luc nay?
            - Tin hieu kich hoat: Da co nhip quet thanh khoan SFP, pha vo cau truc vi mo MSS/CHoCH hoac nen dong than xac nhan chua?
            - Phan bien thoi diem: Cam doan dinh day, cam vao lenh don dau khi nen chua xac nhan. Neu chua co tin hieu kich hoat: Bat buoc dung ngoai (FLAT).

            ### 4. Ke hoach lenh hoan chinh (Trading Blueprint) va Ky luat R:R >= 1:\(String(format: "%.1f", targetRR))
            - KET LUAN RO RANG: [BUY (LONG) / SELL (SHORT) / FLAT (DUNG NGOAI)].
            - LOAI SETUP: [THUAN XU HUONG DONG TIEN] hoac [NGHICH XU HUONG BAT SONG HOI TU CAN H4].
            - KHOA CHAT TY LE R:R: Toi thieu 1:\(String(format: "%.1f", targetRR)).
              NGUYEN TAC TU CHOI: Neu khoang cach tu Entry toi can TP1 khong du dat ty le R:R 1:\(String(format: "%.1f", targetRR)): Bat buoc ket luan FLAT (Dung ngoai), tu choi vao lenh kem chat luong va giai thich ro vung gia nao moi dat chuan.
            - NEU KHUYEN NGHI VAO LENH (BUY/SELL):
              - Diem vao toi uu (Entry).
              - Cat lo bat buoc (Structural Invalidation SL): Muc gia SL cu the vi pham cau truc.
              - Chot loi (Targets): TP 1 va TP 2 tai can H4.
              - Khoi luong (Volume): Tinh chinh xac so lot theo muc rui ro \(numericRisk)% va so tien rui ro \(targetRiskDollarsStr).
              - Ty le R:R thuc te dat duoc: [Ghi ro so R:R, vi du 1:3.2].
            - NEU KHUYEN NGHI FLAT (DUNG NGOAI): Giai thich ro dieu kien nen/can gi can kien nhan cho them.

            BAT BUOC KET THUC BANG BANG THONG SO SETUP DUNG DINH DANG SAU:
            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY hoac SELL hoac FLAT]
            - Balance: \(realBalStr)
            - Entry: [Muc gia hoac vung gia vao lenh]
            - Stop loss: [Muc gia SL cu the]
            - Take profit 1: [Muc gia TP 1]
            - Take profit 2: [Muc gia TP 2 neu co, neu khong ghi Khong]
            - R:R Ratio: [Ty le R:R, vi du 1:3.2]
            - Volume: [Khoi luong lot khuyen nghi tinh theo so tien rui ro \(targetRiskDollarsStr), vi du 1.00 lot]
            - Date time: [Thoi gian hien tai]

            ```json
            {
              "direction": "[BUY hoac SELL hoac FLAT]",
              "entry": [muc gia entry dang so hoac null],
              "stopLoss": [muc gia sl dang so hoac null],
              "takeProfit1": [muc gia tp1 dang so hoac null],
              "takeProfit2": [muc gia tp2 dang so hoac null],
              "riskRewardRatio": "[vi du 1:3.2]",
              "volume": "[vi du 1.00 lot]"
            }
            ```

            > [Dung 1 cau quy tac ky luat hanh dong khong khoan nhuong cua nha giao dich chuyen nghiep]
            """
        } else {
            return """
            [ACCOUNT CONTEXT & RISK PROFILE]:
            - Authoritative Balance: \(realBalStr) \(equityStr)
            - Today's Trade Activity: \(todayTradesDesc)
            - Today's Net P&L: \(pnlTodayStr) | Current Streak: \(streakStr)
            - \(dailyBufferStr)\(riskGuardrailWarning)
            \(contractSizingBlockEn)
            \(behavioralLeaksBlock)
            [MARKET STRUCTURE & INDICATORS (EMA 21/50 & RSI 14)]:
            - Symbol: \(symbol) | Current Price: \(currentPrice)

            - D1 Macro Bias: Trend [\(emaAnalysis.d1?.trend.label ?? "N/A")]
              EMA D1: \(d1EMAStr)
              Key Levels: PDH: \(d1PDH) | PDL: \(d1PDL) | 14-Day ADR: \(d1ADR)

            - H4 Swing Structure & Barriers: Trend [\(emaAnalysis.h4?.trend.label ?? "N/A")]
              EMA H4: \(h4EMAStr)
              Key Swing Levels: Swing High: \(h4SwingHighStr) | Swing Low: \(h4SwingLowStr)
              Recent 3 H4 Bars:
            \(h4CandlesSummary)

            - H1 Execution & Momentum: Trend [\(emaAnalysis.h1?.trend.label ?? "N/A")]
              EMA H1: \(h1EMAStr)
              Wilder RSI(14): Current: \(rsiStr) | Signal: \(rsiSignalStr) | Divergence: [\(divStr)]
              Liquidity: BSL: \(nearestBSLStr) | SSL: \(nearestSSLStr) | Sweeps: \(sweepsStr)

            - LIVE CANDLE PULSE:
            \(liveCandlePulse)

            - Recent 24 H1 Candles (24-Hour Continuous Market Cycle):
            \(h1CandlesSummary)

            - Recent 16 M15 Candles (4-Hour Micro Execution):
            \(m15CandlesSummary)

            - Catalyst News: \(newsBlock)
            \(liveUpdateBlock)\(thesisContinuityBlock)
            ROLE & INSTITUTIONAL MINDSET:
            You are a SENIOR INSTITUTIONAL PORTFOLIO MANAGER & MASTER TRADER.
            Core philosophy:
            1. Capital preservation and asymmetric edge come first. Standing aside (FLAT) is far better than taking low-quality or sub-3R trades.
            2. Maintain a skeptical institutional mindset, identifying retail traps set by Smart Money.
            3. Full-spectrum critique: from trend exhaustion and fake barriers to live tape reading and strict R:R.

            TASK: INSTITUTIONAL PRE-TRADE PLAN & FULL-SPECTRUM CRITIQUE:

            ### 1. D1 Macro Regime & Trend Cycle Audit
            - Evaluate current trend stage: Healthy expansion or overextended and due for exhaustion?
            - Identify multi-timeframe conflicts: Never buy into HTF resistance.

            ### 2. H4 Structure & Liquidity Trap Unmasking
            - Differentiate retail liquidity traps (Equal Highs/Lows) from genuine unmitigated Order Blocks and Fair Value Gaps.

            ### 3. H1/M15 Live Price Action Tape Reading & Trigger Confirmation
            - Read live unclosed candle pulse and wick dynamics. Look for displacement and SFP sweeps. Forbid front-running.

            ### 4. Actionable Execution Blueprint & Strict R:R >= 1:\(String(format: "%.1f", targetRR))
            - Decisive Verdict: [BUY / SELL / FLAT].
            - Strict R:R Enforcement: If setup space to TP1 cannot yield at least 1:\(String(format: "%.1f", targetRR)), conclude FLAT immediately.

            [PRE-TRADE SETUP SPECIFICATION]
            - Direction: [BUY or SELL or FLAT]
            - Balance: \(realBalStr)
            - Entry: [Entry price]
            - Stop loss: [Specific SL price]
            - Take profit 1: [Specific TP1 price]
            - Take profit 2: [Specific TP2 price if any, otherwise None]
            - R:R Ratio: [Expected R:R ratio, e.g. 1:3.2]
            - Volume: [Recommended lots based on \(targetRiskDollarsStr) risk]
            - Date time: [Current date and time]

            ```json
            {
              "direction": "[BUY or SELL or FLAT]",
              "entry": [numeric entry price or null],
              "stopLoss": [numeric SL price or null],
              "takeProfit1": [numeric TP1 price or null],
              "takeProfit2": [numeric TP2 price or null],
              "riskRewardRatio": "[e.g. 1:3.2]",
              "volume": "[e.g. 1.00 lot]"
            }
            ```

            > [Single non-negotiable operational directive of an elite institutional trader]
            """
        }
    }

    // MARK: - Live Unclosed Candle Dynamics Helper
    public static func buildLiveUnclosedCandlePulse(bar: MarketBar?, isVi: Bool) -> String {
        guard let b = bar else {
            return isVi ? "Chua co du lieu nen song" : "No live candle data"
        }
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        let delta = b.close - b.open
        let deltaStr = (delta >= 0 ? "+" : "") + fmt(delta)
        let bodyType = delta >= 0 ? (isVi ? "TANG" : "BULLISH") : (isVi ? "GIAM" : "BEARISH")
        
        let upperWick = b.high - max(b.open, b.close)
        let lowerWick = min(b.open, b.close) - b.low
        let upperWickStr = fmt(upperWick)
        let lowerWickStr = fmt(lowerWick)
        
        let rejectionDesc: String = {
            if upperWick > lowerWick * 2 && upperWick > 0 {
                return isVi ? "Rau tren dai (\(upperWickStr)) -> Phe Ban dang tu choi gia cao" : "Long upper wick (\(upperWickStr)) -> Sellers rejecting highs"
            }
            if lowerWick > upperWick * 2 && lowerWick > 0 {
                return isVi ? "Rau duoi dai (\(lowerWickStr)) -> Phe Mua dang tu choi gia thap (Rut chan)" : "Long lower wick (\(lowerWickStr)) -> Buyers rejecting lows"
            }
            return isVi ? "Than nen dang phat trien can bang" : "Developing candle body"
        }()
        
        if isVi {
            return "  - Nen hien tai: Mo: \(fmt(b.open)) | Cao: \(fmt(b.high)) | Thap: \(fmt(b.low)) | Hien tai: \(fmt(b.close))\n  - Trang thai nen song: [\(bodyType) \(deltaStr)] | Rau tren: \(upperWickStr) | Rau duoi: \(lowerWickStr)\n  - Hanh vi gia song: \(rejectionDesc)"
        } else {
            return "  - Live Candle: O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | Live: \(fmt(b.close))\n  - Real-time State: [\(bodyType) \(deltaStr)] | Upper Wick: \(upperWickStr) | Lower Wick: \(lowerWickStr)\n  - Live Action Insight: \(rejectionDesc)"
        }
    }

    // MARK: - 3-Candle H4 Summary Helper
    public static func buildH4CandleSummary(bars: [MarketBar], count: Int = 3, isVi: Bool = true) -> String {
        guard !bars.isEmpty else { return isVi ? "Khong co du lieu nen H4" : "No H4 candle data" }
        let slice = bars.suffix(count)
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        let n = slice.count
        var lines: [String] = []
        for (idx, b) in slice.enumerated() {
            let offset = n - 1 - idx
            let label = offset == 0 ? (isVi ? "H4 [Nen hien tai]" : "H4 [Live Candle]") : "H4 [-\(offset * 4)h]"
            lines.append("  - \(label): O: \(fmt(b.open)) | H: \(fmt(b.high)) | L: \(fmt(b.low)) | C: \(fmt(b.close))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 24-Candle H1 Execution Series Helper (OHLC + EMA 21/50 + Wilder RSI 14)
    public static func buildH1CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 24,
        symbol: String = "",
        isVi: Bool = true
    ) -> String {
        guard !bars.isEmpty else { return isVi ? "Khong co du lieu nen H1" : "No H1 candle data" }
        
        let ema21 = MovingAverageEngine.calculateEMA(period: 21, bars: bars)
        let ema50 = MovingAverageEngine.calculateEMA(period: 50, bars: bars)
        let momentumWindow = MomentumEngine.computeWindow(bars: bars, windowSize: count)
        
        let n = bars.count
        let takeCount = min(count, n)
        let startIndex = n - takeCount
        
        let rsiMap: [Int64: Decimal] = {
            var map: [Int64: Decimal] = [:]
            for p in momentumWindow.points {
                map[Int64(p.date.timeIntervalSince1970 * 1000)] = p.rsi14
            }
            return map
        }()
        
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        var lines: [String] = []
        for i in startIndex..<n {
            let bar = bars[i]
            let offset = n - 1 - i
            let timeLabel = offset == 0 ? (isVi ? "[Nen song]" : "[Live]") : "[-t-\(offset)h]"
            
            let e21Str = i < ema21.count ? fmt(ema21[i]) : "N/A"
            let e50Str = i < ema50.count ? fmt(ema50[i]) : "N/A"
            
            let rsiVal: String = {
                if let r = rsiMap[bar.timestamp] {
                    return String(format: "%.1f", (r as NSDecimalNumber).doubleValue)
                }
                let ptIndex = i - (n - momentumWindow.points.count)
                if ptIndex >= 0 && ptIndex < momentumWindow.points.count {
                    let r = momentumWindow.points[ptIndex].rsi14
                    return String(format: "%.1f", (r as NSDecimalNumber).doubleValue)
                }
                return "N/A"
            }()
            
            let num = lines.count + 1
            let numStr = num < 10 ? "0\(num)" : "\(num)"
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close)) | EMA21: \(e21Str) | EMA50: \(e50Str) | RSI: \(rsiVal)"
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }

    // MARK: - 16-Candle M15 Micro-Execution Series Helper
    public static func buildM15CandleSeriesSummary(
        bars: [MarketBar],
        count: Int = 16,
        symbol: String = "",
        isVi: Bool = true
    ) -> String {
        guard !bars.isEmpty else { return isVi ? "Khong co du lieu nen M15" : "No M15 candle data" }
        
        let n = bars.count
        let takeCount = min(count, n)
        let startIndex = n - takeCount
        
        func fmt(_ p: Decimal) -> String {
            let d = (p as NSDecimalNumber).doubleValue
            if d >= 1000 { return String(format: "%.2f", d) }
            if d >= 100 { return String(format: "%.2f", d) }
            if d >= 10 { return String(format: "%.3f", d) }
            return String(format: "%.5f", d)
        }
        
        var lines: [String] = []
        for i in startIndex..<n {
            let bar = bars[i]
            let offset = n - 1 - i
            let timeLabel = offset == 0 ? (isVi ? "[Nen song]" : "[Live]") : "[-t-\(offset * 15)m]"
            let num = lines.count + 1
            let numStr = num < 10 ? "0\(num)" : "\(num)"
            let line = "  - #\(numStr) \(timeLabel): O: \(fmt(bar.open)) | H: \(fmt(bar.high)) | L: \(fmt(bar.low)) | C: \(fmt(bar.close))"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
