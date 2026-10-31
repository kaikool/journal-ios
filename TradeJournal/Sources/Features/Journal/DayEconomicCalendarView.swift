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
                    .font(event.impact == .high ? AppTypography.captionBold : AppTypography.captionMedium)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                
                if !event.forecast.isEmpty || !event.previous.isEmpty {
                    HStack(spacing: 6) {
                        if !event.forecast.isEmpty {
                            AppBadge("Forecast: \(event.forecast)", style: .neutral)
                        }
                        
                        if !event.previous.isEmpty {
                            AppBadge("Prev: \(event.previous)", style: .neutral)
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
            AppBadge("HIGH", icon: "exclamationmark.triangle.fill", style: .loss)
        case .medium:
            AppBadge("MED", style: .warning)
        case .low:
            AppBadge("LOW", style: .neutral)
        default:
            AppBadge(impact.shortLabel, style: .neutral)
        }
    }
}
