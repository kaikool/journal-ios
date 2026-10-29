import SwiftUI

// MARK: - Day Economic Calendar View (USD Focus)
public struct DayEconomicCalendarView: View {
    public let events: [ForexFactoryEvent]
    public let timeZone: TimeZone
    
    public init(events: [ForexFactoryEvent], timeZone: TimeZone = .current) {
        self.events = events
        self.timeZone = timeZone
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private func formattedTime(for date: Date?) -> String {
        guard let d = date else { return "All Day" }
        Self.timeFormatter.timeZone = timeZone
        return Self.timeFormatter.string(from: d)
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Clean title without third-party branding or out-of-place icon
                HStack {
                    AppCardHeader("Economic Calendar")
                    
                    Spacer()
                    
                    Text("\(events.count) \(events.count == 1 ? "event" : "events")")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                VStack(spacing: 8) {
                    ForEach(events) { event in
                        eventRow(event)
                        if event.id != events.last?.id {
                            Divider().background(AppColors.border.opacity(0.4))
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func eventRow(_ event: ForexFactoryEvent) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Event Time in user's active timezone
            VStack(alignment: .leading, spacing: 1) {
                Text(formattedTime(for: event.date))
                    .font(AppTypography.number(12, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
            }
            .frame(width: 44, alignment: .leading)
            
            // Impact Badge
            impactBadge(event.impact)
            
            // Title & Forecast / Previous
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 12, weight: event.impact == .high ? .bold : .medium))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                
                if !event.forecast.isEmpty || !event.previous.isEmpty {
                    HStack(spacing: 6) {
                        if !event.forecast.isEmpty {
                            HStack(spacing: 3) {
                                Text("Forecast:")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(event.forecast)
                                    .font(AppTypography.number(10, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(AppColors.secondaryBackground.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        
                        if !event.previous.isEmpty {
                            HStack(spacing: 3) {
                                Text("Prev:")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(event.previous)
                                    .font(AppTypography.number(10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(AppColors.secondaryBackground.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
            }
            
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func impactBadge(_ impact: ForexFactoryImpact) -> some View {
        switch impact {
        case .high:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("HIGH")
                    .font(AppTypography.badgeMicro)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(AppColors.loss.opacity(0.14))
            .foregroundColor(AppColors.loss)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AppColors.loss.opacity(0.25), lineWidth: 0.5)
            )
            
        case .medium:
            Text("MED")
                .font(AppTypography.badgeMicro)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AppColors.warning.opacity(0.14))
                .foregroundColor(AppColors.warning)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(AppColors.warning.opacity(0.25), lineWidth: 0.5)
                )
            
        case .low:
            Text("LOW")
                .font(AppTypography.badgeMicro)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(AppColors.secondaryBackground)
                .foregroundColor(AppColors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            
        default:
            Text(impact.shortLabel)
                .font(AppTypography.badgeMicro)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(AppColors.secondaryBackground)
                .foregroundColor(AppColors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}
