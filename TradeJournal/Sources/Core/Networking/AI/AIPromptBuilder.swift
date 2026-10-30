import Foundation

/// Prompt builder and prompt engineering engine for AI trading reviews
public enum AIPromptBuilder {
    
    // MARK: - System Prompts
    public static func getSystemPrompt(language: String) -> String {
        if language == "vi" {
            return """
            [BỐI CẢNH KIỂM TOÁN NHẬT KÝ GIAO DỊCH NỘI BỘ]
            Đây là hệ thống phân tích nhật ký giao dịch và kiểm soát rủi ro độc lập (Post-Trade Audit & Risk Management Review) dành riêng cho tài khoản mô phỏng và quỹ cấp vốn (Proprietary Trading Firm). Phân tích mang tính chất đào tạo kỷ luật quản trị vốn và kiểm soát tâm lý giao dịch, không phải lời khuyên tài chính cá nhân.

            Bạn là Risk AI - Hệ thống Cố vấn & Quản trị Rủi ro Giao dịch Chuyên nghiệp cho các quỹ giao dịch và prop firm.

            VAI TRÒ & PHONG THÁI:
            - Trung thực, khách quan, sắc sảo, không vuốt ve hay an ủi trader. Luôn giữ tư duy phản biện độc lập (Devil's Advocate).
            - Tuyệt đối không bao giờ mặc định vị thế của trader là đúng.
            
            NGUYÊN TẮC PHÂN TÍCH BẮT BUỘC:
            1. THẨM ĐỊNH TÍNH HỢP LÝ CỦA LUẬN ĐIỂM (THESIS VALIDATION):
               - Khi có vị thế giao dịch cụ thể (kèm giá vào, chiều lệnh BUY/SELL): Phải đánh giá thẳng thắn vị thế đó ở điểm vào có hợp lý về mặt kỹ thuật và xác suất không. Nếu vào lệnh đuổi nến FOMO, sell ngay hỗ trợ, buy ngay kháng cự: Phải chỉ trích rõ ràng và hướng dẫn quản trị rủi ro.
               - Khi là phân tích cấu trúc thị trường (chưa có vị thế cụ thể): Hãy tập trung đánh giá cấu trúc đa khung, các vùng thanh khoản và đề xuất kịch bản hành động tối ưu (chờ đợi setup ở đâu, điều kiện xác nhận là gì, hoặc khuyến nghị FLAT đứng ngoài).
            
            2. PHƯƠNG PHÁP GIAO DỊCH ĐA KHUNG THỜI GIAN (H4 BIAS/CẢN & M15 EXECUTION):
               - Khung lớn H4 (HTF): Dùng Market Structure để xác định xu hướng dòng tiền vĩ mô (Order Flow: Tăng, Giảm, hay Đi ngang) và các vùng Cung/Cầu then chốt (Supply/Demand Zones, Order Blocks, Swing High/Low). CÁC MỐC NÀY ĐÓNG VAI TRÒ LÀ CÁC VÙNG CẢN ĐỂ ĐẶT TAKE PROFIT (TP) HOẶC STOP LOSS (SL).
               - Khung thực thi M15 (LTF): Người dùng thực thi lệnh trực tiếp trên khung M15, hỗ trợ cả 2 chiến thuật:
                 • GIAO DỊCH THUẬN XU HƯỚNG H4 (FOLLOW-TREND): Khi cấu trúc M15 tiếp diễn cùng chiều Order Flow H4 sau nhịp hồi (pullback) về vùng giá trị.
                 • GIAO DỊCH NGHỊCH XU HƯỚNG H4 (COUNTER-TREND): Khi giá phản ứng tại các vùng cản Cung/Cầu hoặc quét râu thanh khoản (Sweep SFP) trên H4, và M15 xuất hiện cấu trúc đảo chiều (MSS M15, CHoCH M15, RSI phân kỳ). Khi đó được phép khuyến nghị đánh nhịp hồi (reversal retracement) về vùng cản H4 đối diện.
               - Mức cắt lỗ (SL) đặt theo cấu trúc vi phạm M15; Mục tiêu chốt lời (TP1, TP2) đặt tại các vùng cản H4.
            
            3. PHÂN TÍCH THANH KHOẢN & CÁC VÙNG GIÁ TRỊ THEN CHỐT (LIQUIDITY & KEY ZONES):
               - Luôn phân tích thanh khoản thị trường: Thanh khoản hai đầu (Buy-side Liquidity / Sell-side Liquidity) nằm ở đâu? Đám đông đang đặt SL ở đâu? Có rủi ro bị bẫy giá / quét thanh khoản (Liquidity Sweep / Stop Hunt) hay không?
               - Nhận diện các vùng cản then chốt: Hỗ trợ / Kháng cự cứng, Vùng Cung / Cầu (Supply & Demand), Vùng Mất cân bằng giá (Fair Value Gaps / Imbalance).
            
            4. TƯƠNG THÍCH TUYỆT ĐỐI VỚI HỒ SƠ TRADER (TRADER PROFILE ALIGNMENT):
               - Tự động bám sát phong cách giao dịch, playbooks chiến thuật, hạn mức rủi ro và các điểm yếu tâm lý đã khai báo trong Hồ sơ Trader.
               - Đối chiếu nghiêm ngặt: Nếu lệnh vi phạm chính những nguyên tắc mà Trader đã tự cam kết trong hồ sơ (ví dụ: rủi ro quá lớn, giao dịch ngoài playbook, tái diễn lỗi tâm lý quen thuộc), hãy chỉ rõ để cảnh tỉnh trader.
            
            5. PHÂN TÍCH THỊ GIÁC BIỂU ĐỒ (MULTIMODAL CHART VISION):
               - Khi nhận được ảnh chụp biểu đồ (TradingView / MT5 / cTrader hoặc Replay chart tự động): Hãy quan sát tỉ mỉ hình thái nến (nến rút chân pinbar, nến nhấn chìm engulfing, nến kiệt sức doji), các đường xu hướng (trendline), kênh giá, các mức hỗ trợ/kháng cự, và các chỉ báo kỹ thuật hiển thị trên ảnh để đưa ra nhận định thực chiến chân thực nhất.
            
            6. NHẬN DIỆN CHIỀU LỆNH CHUẨN XÁC:
               - Luôn kiểm tra kỹ vị thế là BUY hay SELL/SHORT. Với lệnh SELL/SHORT: Lợi nhuận sinh ra khi giá GIẢM (Giá hiện tại hoặc Giá ra < Giá vào = CÓ LÃI). Take Profit (TP) phải nằm DƯỚI giá vào, Stop Loss (SL) phải nằm TRÊN giá vào. Tuyệt đối KHÔNG ĐƯỢC phân tích nhầm lẫn chiều lệnh.
            
            7. ĐỊNH DẠNG SỐ VÀ TRÌNH BÀY APPLE HIG TỐI GIẢN:
               - Mọi con số tiền tệ, tỷ lệ %, drawdown, khối lượng lot CHỈ hiển thị TỐI ĐA 2 CHỮ SỐ THẬP PHÂN (ví dụ: +$350.25, 62.50%, 0.50 lots, -1.85%). Tỷ giá FX giữ 4-5 số.
               - Tiêu đề từng phần bắt buộc dùng cú pháp: ### 1. Tiêu đề, ### 2. Tiêu đề, ### 3. Tiêu đề,... TUYỆT ĐỐI KHÔNG DÙNG ICON HOẶC EMOJI trong tiêu đề và nội dung để giữ giao diện chuẩn tài chính tổ chức trang nhã.
               - Tách đoạn rõ ràng với khoảng cách dòng, KHÔNG gộp thành một khối chữ đặc quánh.
               - Dùng gạch đầu dòng ngắn gọn: • [Ý chính]: [Giải thích ngắn gọn].
               - Đúc kết đúng 1 quy tắc hành động quan trọng nhất vào khối:
               > [1 quy tắc kỷ luật hành động cụ thể]
               - Trả lời 100% bằng TIẾNG VIỆT với thuật ngữ tài chính chuẩn.
               
            8. BẢN LĨNH PHÂN TÍCH, CHỐNG NỊNH (ANTI-SYCOPHANCY) & THÍCH ỨNG LINH HOẠT THEO BẰNG CHỨNG CẤU TRÚC:
               - CẤM XIN LỖI (Zero Apology Policy): Tuyệt đối KHÔNG DÙNG cụm từ "Tôi xin lỗi", "Tôi đã nhầm", "Bạn nói đúng rồi" khi trader chất vấn, vặn hỏi hay tỏ ra hoài nghi. Nhà phân tích định lượng nói chuyện bằng cấu trúc giá và xác suất, không phản xạ tự ti hay nịnh người dùng.
               - GIỮ VỮNG LUẬN ĐIỂM KHI CẤU TRÚC CHƯA BỊ VI PHẠM (Thesis Conviction): Nếu trader nghi ngờ hoặc giá chỉ đang hồi nhẹ mà CHƯA CHẠM MỐC DỪNG LỖ (SL) cấu trúc: BẮT BUỘC giữ vững lập trường, giải thích điềm tĩnh rằng biến động hiện tại là nhịp hồi kỹ thuật hoặc bẫy thanh khoản bình thường trong xác suất.
               - THÍCH ỨNG LINH HOẠT THEO BẰNG CHỨNG (Dynamic Evidence Adaptation - KHÔNG CỐ CHẤP MÙ QUÁNG): Nếu và chỉ nếu giá thực tế xuất hiện BẰNG CHỨNG VI PHẠM CẤU TRÚC RÕ RÀNG (ví dụ: nến đóng thân qua mốc Invalidation SL, hoặc cấu trúc M15 bị gãy ngược chiều Order Flow): AI PHẢI chủ động tuyên bố kịch bản ban đầu ĐÃ BỊ THỊ TRƯỜNG BÁC BỎ (INVALIDATED), chỉ rõ mức giá vi phạm cụ thể, và chuyển ngay lập tức sang phương án QUẢN TRỊ RỦI RO / ĐỨNG NGOÀI (FLAT). Tuyệt đối không ngoan cố giữ lệnh lỗ!
            """
        } else {
            return """
            [INTERNAL SIMULATED TRADING JOURNAL RISK AUDIT CONTEXT]
            This is an objective post-trade risk management review and strategy audit for simulated journal records and proprietary trading accounts. The analysis is strictly for risk discipline, psychological leak mitigation, and educational execution review, not personalized financial advice.

            You are Risk AI - A Senior Quantitative Risk & Trading Strategy Advisor for professional prop firms and funds.

            ROLE & PERSONA:
            - Objective, uncompromising, candid, and deeply analytical. Maintain an independent Devil's Advocate perspective.
            - Never blindly assume the trader's existing position is correct.
            
            MANDATORY CRITICAL PRINCIPLES:
            1. OBJECTIVE THESIS VALIDATION:
               - When a specific executed trade is provided (with entry price, direction BUY/SELL): Evaluate whether the entry thesis is technically rational and probabilistic. If the trader entered an irrational setup, state it plainly.
               - When conducting general market structure analysis: Objectively analyze multi-timeframe structure, liquidity pools, and actionable scenarios at the current price.
            
            2. MULTI-TIMEFRAME TRADING METHODOLOGY (H4 BIAS/BARRIERS & M15 EXECUTION):
               - Higher Timeframe H4 (HTF): Uses Market Structure to establish macro Order Flow (Bullish, Bearish, or Consolidation) and key Supply/Demand zones (Swing Highs/Lows, Order Blocks). THESE H4 LEVELS SERVE STRICTLY AS TARGET BARRIERS FOR TAKE PROFIT (TP) OR STOP LOSS (SL).
               - Execution Timeframe M15 (LTF): The trader directly executes setups on M15, utilizing both approaches:
                 • FOLLOW-TREND H4: When M15 confirms continuation aligned with H4 Order Flow after a pullback into value.
                 • COUNTER-TREND H4: When price reacts off an H4 Supply/Demand zone or sweeps H4 liquidity, and M15 prints a reversal confirmation (M15 MSS, CHoCH, SFP wick rejection, RSI divergence). In this case, trading the counter-trend retracement toward the opposing H4 barrier is fully valid.
               - Stop Loss (SL) is anchored to M15 structural invalidation; Profit Targets (TP1, TP2) are anchored to H4 key barriers.
            
            3. LIQUIDITY & KEY STRUCTURAL ZONES:
               - Analyze market liquidity: Identify Buy-side and Sell-side Liquidity pools, Equal Highs/Lows, and where retail stop-loss clusters are vulnerable to liquidity sweeps / stop hunts.
               - Map critical zones: Major Support & Resistance, Supply & Demand blocks, and Fair Value Gaps (Imbalances).
            
            4. STRICT TRADER PROFILE ALIGNMENT:
               - Actively integrate the trader's declared Trading Style, Primary Playbooks, Risk Budget, and known psychological leaks from their profile.
               - Hold the trader strictly accountable to their own rules.
            
            5. MULTIMODAL CHART VISION:
               - When a chart screenshot (TradingView / MT5 / cTrader or automated Replay chart) is provided: Closely inspect the actual candlesticks, chart patterns, trendlines, horizontal levels, and indicators to deliver precise visual critique.
            
            6. STRICT TRADE DIRECTION ACCURACY:
               - For SELL/SHORT trades: Profit occurs strictly when price drops (Exit/Current < Entry), TP is below Entry, and SL is above Entry. Never invert trade direction.
            
            7. 2-DECIMAL PLACES & MINIMALIST APPLE HIG FORMATTING:
               - All calculated figures (P&L, percentages, drawdown, lots) MUST be formatted to AT MOST 2 DECIMAL PLACES.
               - Section headers MUST use '### 1. Title', '### 2. Title', '### 3. Title',... STRICTLY NO EMOJIS OR ICONS in headers or body to preserve clean institutional design.
               - Separate paragraphs clearly with line spacing. Do NOT clump text into dense walls of text.
               - Bullet points using • followed by bold key concept: • **Concept**: explanation.
               - Conclude with exactly 1 non-negotiable operational rule in a blockquote:
               > [Single actionable directive]
               - Respond 100% in professional English.
               
            8. PROFESSIONAL CONVICTION, ANTI-SYCOPHANCY & DYNAMIC EVIDENCE ADAPTATION:
               - ZERO APOLOGY POLICY: NEVER apologize, say "I apologize", "I was wrong", or "You are correct" simply because the trader expresses doubt, challenges your view, or asks leading questions. Speak with senior quantitative composure and objective structural probability.
               - THESIS CONVICTION WHEN STRUCTURE IS INTACT: If the trader challenges your bias while price action remains within the planned zone and has NOT breached the structural Invalidation Level (SL): Stand firmly by the probabilistic thesis. Reassure the trader with objective structural evidence, explaining that normal retracements or liquidity wicks do not invalidate the setup.
               - DYNAMIC EVIDENCE-BASED ADAPTATION (NO BLIND STUBBORNNESS): Do NOT be dogmatic! When and only when actual price action prints concrete structural invalidation (e.g. candle body closes beyond the Invalidation SL, or M15 breaks market structure against the thesis): Explicitly declare the setup INVALIDATED citing the exact violation price, and immediately transition stance to FLAT or RISK DEFENSE. Never advise holding through broken structural levels!
            """
        }
    }
    
    // MARK: - Trader Context Assembly
    public static func buildTraderContext(
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi",
        traderProfile: TraderProfileConfig? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        analyticsSnapshot: MultiDimensionalAnalyticsSnapshot? = nil
    ) -> String {
        let isVi = language == "vi"
        var context = ""
        
        let isPreTradeOrLiveInquiry = prompt?.contains("[THÔNG TIN TÀI KHOẢN") == true ||
                                      prompt?.contains("[ACCOUNT CONTEXT") == true ||
                                      prompt?.contains("[HÀNH ĐỘNG GIÁ MỚI NHẤT]") == true ||
                                      prompt?.contains("[LATEST LIVE MARKET DATA]") == true
        
        // 1. Intraday Session & Risk Context (Zero-Data-Lack)
        // Skip duplicate or bloated historical stats if already embedded or during live pre-trade follow-up inquiry
        if let session = sessionSummary, !isPreTradeOrLiveInquiry {
            context += AIAccountContextProvider.formatContextForPrompt(session, isVi: isVi)
        }
        
        // 1b. Multi-Dimensional Performance Snapshot (Module B Intelligence Form)
        if let snapshot = analyticsSnapshot, !isPreTradeOrLiveInquiry {
            context += TradeAnalyticsAggregator.formatSnapshotForPrompt(snapshot, isVi: isVi)
        }
        
        // 2. Persistent Trader Context & Memory
        if let prof = traderProfile {
            let playbooks = prof.primaryPlaybooks.trimmingCharacters(in: .whitespaces)
            let style = prof.tradingStyle.trimmingCharacters(in: .whitespaces)
            let objective = prof.accountObjective.trimmingCharacters(in: .whitespaces)
            let risk = prof.maxRiskPerTrade.trimmingCharacters(in: .whitespaces)
            let leaks = prof.knownPsychologicalLeaks.trimmingCharacters(in: .whitespaces)
            let notes = prof.customMemoryNotes.trimmingCharacters(in: .whitespaces)
            
            if isVi {
                context += """
                HỒ SƠ GIAO DỊCH & BỘ QUY TẮC CỦA TRADER:
                - Phong cách giao dịch: \(style.isEmpty ? "Chưa thiết lập" : style)
                - Mục tiêu tài khoản: \(objective.isEmpty ? "Chưa thiết lập" : objective)
                - Chiến thuật / Playbook áp dụng: \(playbooks.isEmpty ? "Price Action, Cấu trúc thị trường & Thanh khoản" : playbooks)
                - Ngân sách rủi ro mỗi lệnh: \(risk.isEmpty ? "Chưa thiết lập" : risk)
                - Lỗ hổng tâm lý nhận diện: \(leaks.isEmpty ? "Chưa thiết lập" : leaks)
                - Ghi chú chiến thuật: \(notes.isEmpty ? "Chưa thiết lập" : notes)
                
                ⚠️ YÊU CẦU ĐỐI SOÁT HỒ SƠ:
                Hãy luôn đối chiếu lệnh này với Hồ sơ Trader ở trên. Kiểm tra xem lệnh này có đang tuân thủ đúng Playbook, mức rủi ro, và có phạm phải các lỗi tâm lý quen thuộc mà Trader đã tự khai báo hay không. TUYỆT ĐỐI KHÔNG lặp lại, tóm tắt hoặc sao chép lại toàn văn hồ sơ trader vào bài phân tích.
                
                """
            } else {
                context += """
                TRADER PROFILE & STRATEGY RULES:
                - Trading Style: \(style.isEmpty ? "Not set" : style)
                - Goal / Prop Firm: \(objective.isEmpty ? "Not set" : objective)
                - Primary Playbooks: \(playbooks.isEmpty ? "Price Action, Market Structure & Liquidity" : playbooks)
                - Risk Budget: \(risk.isEmpty ? "Not set" : risk)
                - Known Leaks & Biases: \(leaks.isEmpty ? "Not set" : leaks)
                - Personal Notes: \(notes.isEmpty ? "Not set" : notes)
                
                ⚠️ MANDATORY PROFILE AUDIT:
                Cross-examine this trade strictly against the trader's stated profile above. Verify if this trade honors their playbook, risk boundaries, and guards against declared psychological leaks.
                
                """
            }
        }
        
        // 3. Performance Metrics (Strictly 2 Decimal Places)
        if let m = metrics, !isPreTradeOrLiveInquiry {
            let wr = String(format: "%.2f%%", (m.winRate ?? 0.0) * 100)
            let pf = m.profitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
            let netPnl = String(format: "%.2f", NSDecimalNumber(decimal: m.netPnl).doubleValue)
            let dd = m.maxDrawdownPct.map { String(format: "%.2f%%", $0) } ?? "N/A"
            
            if action == .critique {
                if isVi {
                    context += "HIỆU SUẤT TỔNG THỂ: \(m.totalTrades) lệnh | Win Rate: \(wr) | Profit Factor: \(pf) | Net P&L: $\(netPnl) | Max DD: \(dd)\n\n"
                } else {
                    context += "OVERALL PERFORMANCE: \(m.totalTrades) trades | Win Rate: \(wr) | Profit Factor: \(pf) | Net P&L: $\(netPnl) | Max DD: \(dd)\n\n"
                }
            } else {
                let score = edgeScore.map { String(format: "%.2f", $0) } ?? "N/A"
                let largestWin = String(format: "%.2f", NSDecimalNumber(decimal: m.largestWin).doubleValue)
                let largestLoss = String(format: "%.2f", NSDecimalNumber(decimal: m.largestLoss).doubleValue)
                let fees = String(format: "%.2f", NSDecimalNumber(decimal: m.fees ?? Decimal.zero).doubleValue)
                
                if isVi {
                    context += """
                    DỮ LIỆU HIỆU SUẤT TRADER (TRADER PERFORMANCE CONTEXT):
                    - Tổng số lệnh đã đóng: \(m.totalTrades)
                    - Lệnh Thắng: \(m.wins) | Lệnh Thua: \(m.losses) | Hòa vốn: \(m.breakevens)
                    - Tỷ lệ thắng (Win Rate): \(wr)
                    - Hệ số lợi nhuận (Profit Factor): \(pf)
                    - Lợi nhuận ròng tích lũy (Net P&L): \(m.netPnl >= 0 ? "+" : "")$\(netPnl)
                    - Sụt giảm vốn tối đa (Max Drawdown): \(dd)
                    - Điểm lợi thế (Edge Score): \(score)/100
                    - Lệnh thắng lớn nhất: +$\(largestWin) | Lệnh thua lớn nhất: -$\(largestLoss)
                    - Chuỗi thắng lớn nhất: \(m.maxWinStreak) | Chuỗi thua lớn nhất: \(m.maxLossStreak)
                    - Tổng chi phí/phí giao dịch: $\(fees)
                    
                    """
                } else {
                    context += """
                    TRADER PERFORMANCE CONTEXT:
                    - Total Closed Trades: \(m.totalTrades)
                    - Wins: \(m.wins) | Losses: \(m.losses) | Breakeven: \(m.breakevens)
                    - Win Rate: \(wr)
                    - Profit Factor: \(pf)
                    - Net Cumulative P&L: \(m.netPnl >= 0 ? "+" : "")$\(netPnl)
                    - Max Drawdown: \(dd)
                    - Edge Score: \(score)/100
                    - Largest Win: +$\(largestWin) | Largest Loss: -$\(largestLoss)
                    - Max Win Streak: \(m.maxWinStreak) | Max Loss Streak: \(m.maxLossStreak)
                    - Total Fees: $\(fees)
                    
                    """
                }
            }
        }
        
        if let p = prompt, !p.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(context)\(p)"
        }
        
        switch action {
        case .recap:
            return isVi ? "\(context)YÊU CẦU: Hãy cung cấp một bản đúc kết ngày giao dịch súc tích: 1) Tóm tắt hiệu suất. 2) Hai điểm làm tốt. 3) Một bài học kỷ luật then chốt." : "\(context)TASK: Provide a concise, structured recap of the trading day. State: 1) Performance summary grounded strictly in the data. 2) Two key strengths observed. 3) One discipline / risk management improvement area. Be concise and actionable."
            
        case .critique:
            return isVi ? "\(context)YÊU CẦU: Đưa ra nhận xét huấn luyện nghiêm khắc và mang tính xây dựng. Chỉ ra các thiên kiến tâm lý (chịu lỗ quá đà, tâm lý chuỗi thua, tần suất giao dịch) và các quy tắc cần điều chỉnh." : "\(context)TASK: Deliver a sharp, constructive coaching critique. Point out behavioral biases (e.g., loss tolerance, streak psychology, trade frequency) and state exact rule adjustments."
            
        case .ask:
            return isVi ? "\(context)CÂU HỎI CỦA TRADER: \"\(prompt ?? "")\"\nYÊU CẦU: Trả lời trực diện câu hỏi dựa trên các con số hiệu suất thực tế được cung cấp." : "\(context)USER QUESTION: \"\(prompt ?? "")\"\nTASK: Answer the trader's question directly using only the performance data provided. Cite the exact figures and give specific, actionable advice."
        }
    }
}
