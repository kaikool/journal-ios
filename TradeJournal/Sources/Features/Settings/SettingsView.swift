import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 7 Canonical Settings Sections (1:1 port from apps/web/src/app/settings/page.tsx)
public enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "general"
    case trading = "trading"
    case currencyConversion = "currency-conversion"
    case marketData = "market-data"
    case connections = "the5ers"
    case aiSettings = "ai-settings"
    case yourData = "your-data"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .general: return "General"
        case .trading: return "Trading"
        case .currencyConversion: return "Currency conversion"
        case .marketData: return "Market data"
        case .connections: return "Connections"
        case .aiSettings: return "AI"
        case .yourData: return "Data & backups"
        }
    }
    
    public var iconName: String {
        switch self {
        case .general: return "globe"
        case .trading: return "slider.horizontal.3"
        case .currencyConversion: return "arrow.left.arrow.right"
        case .marketData: return "chart.xyaxis.line"
        case .connections: return "link"
        case .aiSettings: return "sparkles"
        case .yourData: return "cylinder.split.1x2"
        }
    }
    
    public var description: String {
        switch self {
        case .general:
            return "Choose the timezones used to display and import your trades."
        case .trading:
            return "Manage contract multipliers, breakeven rules, fees, and risk defaults."
        case .currencyConversion:
            return "Set a reporting currency and saved exchange rates for combined performance."
        case .marketData:
            return "Connect price history and market data feeds for replay and trade analysis."
        case .connections:
            return "Connect broker APIs, cTrader accounts, and prop firm feeds."
        case .aiSettings:
            return "Configure AI provider, language, and trader profile rules."
        case .yourData:
            return "Manage cloud sync, export backups, and local storage."
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var activeSection: SettingsSection = .general
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: activeSection.iconName)
                            .foregroundColor(AppColors.brand)
                            .font(.system(size: 14))
                        Text(activeSection.label)
                            .font(AppTypography.pageTitle)
                            .foregroundColor(AppColors.primaryText)
                    }
                    Text(activeSection.description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                // Active Section Content (Preserving State)
                Group {
                    switch activeSection {
                    case .general:
                        GeneralSettingsView()
                    case .trading:
                        TradingSettingsView()
                    case .currencyConversion:
                        CurrencyConversionSettingsView()
                    case .marketData:
                        MarketDataSettingsView()
                    case .connections:
                        ConnectionsSettingsView()
                    case .aiSettings:
                        AiSettingsView()
                    case .yourData:
                        YourDataSettingsView()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            sectionSelectorBar
                .padding(.vertical, 8)
                .background(Color.clear)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
    }
    
    private var sectionSelectorBar: some View {
        AppleSlidingSegmentedBar(
            selection: $activeSection,
            items: SettingsSection.allCases,
            titleFor: { $0.label },
            iconFor: { $0.iconName },
            isScrollable: true
        )
        .padding(.horizontal, 14)
    }
}
