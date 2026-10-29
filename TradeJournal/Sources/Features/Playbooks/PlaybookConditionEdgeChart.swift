import SwiftUI

// MARK: - Condition Rule Stat Model

public struct ConditionRuleStat: Identifiable, Equatable {
    public let id: String
    public let index: Int
    public let rule: String
    public let wins: Int
    public let losses: Int
    public let breakEvens: Int
    public let total: Int
    public let winRate: Double?
    
    public init(
        id: String,
        index: Int,
        rule: String,
        wins: Int,
        losses: Int,
        breakEvens: Int,
        total: Int,
        winRate: Double?
    ) {
        self.id = id
        self.index = index
        self.rule = rule
        self.wins = wins
        self.losses = losses
        self.breakEvens = breakEvens
        self.total = total
        self.winRate = winRate
    }
}

// MARK: - Playbook Condition Edge Chart (Diverging Win/Loss Bar Chart)

/// A centered butterfly / diverging bar chart showing winning vs losing trades
/// for each playbook checklist condition when checked, matching the WeekdayChart HIG aesthetic.
/// - Left side (Red): Losses
/// - Center: Condition index badge (1), (2), ...
/// - Right side (Green): Wins
/// - Top: Dynamic auto-scaling trade count scale
/// - Bottom: Detailed breakdown table with sample size line
public struct PlaybookConditionEdgeChart: View {
    public let playbook: Playbook
    public let trades: [Trade]
    public let assessments: [PlaybookRuleAssessment]
    
    @State private var selectedIndex: Int? = nil
    @State private var lastHapticIndex: Int? = nil
    @State private var animProgress: Double = 0.0
    
    public init(
        playbook: Playbook,
        trades: [Trade],
        assessments: [PlaybookRuleAssessment]
    ) {
        self.playbook = playbook
        self.trades = trades
        self.assessments = assessments
    }
    
    // MARK: - Computed Stats
    
    public var conditionStats: [ConditionRuleStat] {
        playbook.rules.enumerated().map { idx, rule in
            let matchingTradeKeys = Set(
                assessments.filter {
                    $0.playbookId == playbook.id &&
                    $0.rule == rule &&
                    $0.followed == true
                }.map { $0.tradeKey }
            )
            
            let evaluatedTrades = trades.filter { matchingTradeKeys.contains($0.key) }
            let wins = evaluatedTrades.filter { $0.netPnl > 0 || $0.status == .win }.count
            let losses = evaluatedTrades.filter { $0.netPnl < 0 || $0.status == .loss }.count
            let be = evaluatedTrades.filter { $0.netPnl == 0 || $0.status == .breakeven }.count
            let total = evaluatedTrades.count
            let wr = total > 0 ? Double(wins) / Double(total) : nil
            
            return ConditionRuleStat(
                id: "\(playbook.id)_\(idx)",
                index: idx + 1,
                rule: rule,
                wins: wins,
                losses: losses,
                breakEvens: be,
                total: total,
                winRate: wr
            )
        }
    }
    
    private var activeStat: ConditionRuleStat? {
        guard let idx = selectedIndex else { return nil }
        return conditionStats.first { $0.index == idx }
    }
    
    private var maxScaleValue: Int {
        let maxSingle = conditionStats.map { max($0.wins, $0.losses) }.max() ?? 0
        return max(maxSingle, 1)
    }
    
    private var maxTotalTrades: Int {
        max(conditionStats.map { $0.total }.max() ?? 0, 1)
    }
    
    private var scaleTicks: [Int] {
        let m = maxScaleValue
        if m <= 1 {
            return [1]
        } else if m <= 3 {
            return [m, 1]
        } else if m <= 5 {
            return [m, 2, 1]
        } else if m <= 10 {
            return [10, 5, 1]
        } else if m <= 20 {
            return [20, 10, 5]
        } else {
            let step = max(Int(ceil(Double(m) / 3.0)), 1)
            return [step * 3, step * 2, step]
        }
    }
    
    private var scaleMax: Int {
        scaleTicks.first ?? maxScaleValue
    }
    
    // MARK: - Body
    
    public var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                headerView
                
                if playbook.rules.isEmpty {
                    emptyRulesView
                } else {
                    chartContainer
                    
                    Divider().background(AppColors.border.opacity(0.4))
                    
                    breakdownTable
                }
            }
        }
        .onAppear {
            guard animProgress == 0.0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                    animProgress = 1.0
                }
            }
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    
                    Text(activeStat.map { "CONDITION (\($0.index)) EDGE" } ?? "CONDITION WIN / LOSS EDGE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                }
                
                Text(activeStat.map { stat in
                    let wrStr = stat.winRate.map { " · WR \(Int($0 * 100))%" } ?? ""
                    return "\(stat.total) trades · \(stat.wins)W / \(stat.losses)L\(wrStr)"
                } ?? "Win & loss count when condition is checked")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            }
            .frame(height: 38, alignment: .leading)
            
            Spacer()
            
            if let active = activeStat {
                if let wr = active.winRate {
                    Text("\(Int(wr * 100))% WR")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(wr >= 0.5 ? AppColors.profit : AppColors.loss)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((wr >= 0.5 ? AppColors.profit : AppColors.loss).opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Text("0 trades")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.loss).frame(width: 6, height: 6)
                        Text("Loss")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.profit).frame(width: 6, height: 6)
                        Text("Win")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .frame(height: 38)
    }
    
    // MARK: - Empty Rules View
    
    @ViewBuilder
    private var emptyRulesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 24))
                .foregroundColor(AppColors.secondaryText)
            Text("No Checklist Rules")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
            Text("Edit this playbook to add checklist conditions.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Chart Container
    
    @ViewBuilder
    private var chartContainer: some View {
        VStack(spacing: 8) {
            scaleAxisHeader
            
            VStack(spacing: 7) {
                ForEach(conditionStats) { stat in
                    divergingRow(stat: stat)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Scale Axis Header
    
    @ViewBuilder
    private var scaleAxisHeader: some View {
        HStack(spacing: 0) {
            // Left: Losses scale ticks (descending towards center)
            HStack(spacing: 0) {
                Text("LOSSES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.loss.opacity(0.8))
                
                Spacer()
                
                ForEach(scaleTicks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        .frame(minWidth: 16)
                    if tick != scaleTicks.last {
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Center Zero indicator
            Text("0")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 32)
            
            // Right: Wins scale ticks (ascending from center)
            HStack(spacing: 0) {
                ForEach(scaleTicks.reversed(), id: \.self) { tick in
                    Text("\(tick)")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        .frame(minWidth: 16)
                    if tick != scaleTicks.first {
                        Spacer()
                    }
                }
                
                Spacer()
                
                Text("WINS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.profit.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
    
    // MARK: - Diverging Row
    
    @ViewBuilder
    private func divergingRow(stat: ConditionRuleStat) -> some View {
        let isSelected = selectedIndex == stat.index
        
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            if selectedIndex == stat.index {
                selectedIndex = nil
            } else {
                selectedIndex = stat.index
            }
        } label: {
            GeometryReader { geo in
                let centerWidth: CGFloat = 32
                let halfWidth = max((geo.size.width - centerWidth) / 2, 40)
                let maxBar = max(halfWidth - 28, 10)
                
                let lossBarWidth = scaleMax > 0 ? (CGFloat(stat.losses) / CGFloat(scaleMax)) * maxBar * CGFloat(animProgress) : 0
                let winBarWidth = scaleMax > 0 ? (CGFloat(stat.wins) / CGFloat(scaleMax)) * maxBar * CGFloat(animProgress) : 0
                
                HStack(spacing: 0) {
                    // LEFT SIDE: LOSSES (Red, extending towards center from right to left)
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        
                        if stat.losses > 0 {
                            Text("\(stat.losses)")
                                .font(.system(size: 10.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(AppColors.loss)
                                .lineLimit(1)
                        }
                        
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.loss.opacity(0.75), AppColors.loss],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(lossBarWidth, stat.losses > 0 ? 4 : 0), height: 14)
                    }
                    .frame(width: halfWidth, alignment: .trailing)
                    
                    // CENTER BADGE: (1), (2), ...
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? AppColors.brand : AppColors.brand.opacity(0.12))
                            .frame(width: 28, height: 20)
                        
                        Text("(\(stat.index))")
                            .font(.system(size: 10.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(isSelected ? .white : AppColors.brand)
                    }
                    .frame(width: centerWidth)
                    
                    // RIGHT SIDE: WINS (Green, extending from center towards right)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.profit, AppColors.profit.opacity(0.75)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(winBarWidth, stat.wins > 0 ? 4 : 0), height: 14)
                        
                        if stat.wins > 0 {
                            Text("\(stat.wins)")
                                .font(.system(size: 10.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(AppColors.profit)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .frame(width: halfWidth, alignment: .leading)
                }
            }
            .frame(height: 24)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppColors.secondaryBackground.opacity(0.8) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Breakdown Table
    
    @ViewBuilder
    private var breakdownTable: some View {
        VStack(spacing: 6) {
            ForEach(conditionStats) { stat in
                let isSelected = selectedIndex == stat.index
                
                HStack(spacing: 8) {
                    // Index badge
                    Text("(\(stat.index))")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.brand)
                        .frame(width: 26, alignment: .leading)
                    
                    // Rule text
                    Text(stat.rule)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer(minLength: 4)
                    
                    // Total trades volume line (visual indicator of sample size)
                    HStack(spacing: 4) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.border.opacity(0.35))
                                .frame(width: 36, height: 3.5)
                            
                            let ratio = maxTotalTrades > 0 ? CGFloat(stat.total) / CGFloat(maxTotalTrades) : 0
                            Capsule()
                                .fill(AppColors.brand)
                                .frame(width: max(36 * ratio, stat.total > 0 ? 4 : 0), height: 3.5)
                        }
                        
                        Text("\(stat.total)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 18, alignment: .trailing)
                    }
                    
                    // Win Rate Pill
                    if let wr = stat.winRate {
                        Text("\(Int(wr * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((wr >= 0.5 ? AppColors.profit : AppColors.loss).opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundColor(wr >= 0.5 ? AppColors.profit : AppColors.loss)
                            .frame(width: 44, alignment: .center)
                    } else {
                        Text("–")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 44, alignment: .center)
                    }
                    
                    // Wins / Losses count
                    HStack(spacing: 2) {
                        Text("\(stat.wins)W")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(stat.wins > 0 ? AppColors.profit : AppColors.secondaryText)
                        Text("/")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText.opacity(0.5))
                        Text("\(stat.losses)L")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(stat.losses > 0 ? AppColors.loss : AppColors.secondaryText)
                    }
                    .frame(width: 50, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? AppColors.brand.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    if selectedIndex == stat.index {
                        selectedIndex = nil
                    } else {
                        selectedIndex = stat.index
                    }
                }
            }
        }
    }
}
