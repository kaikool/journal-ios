import SwiftUI

// MARK: - 1. General Settings View
// Ported 1:1 from `TimeZoneSettings` in `journal-settings.tsx`
public struct GeneralSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var displayTz: String = ""
    @State private var importTz: String = ""
    @State private var statusMessage: String = ""
    @State private var isSaved: Bool = false
    
    private let commonTimeZones = [
        "UTC",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "Europe/London",
        "Europe/Berlin",
        "Europe/Paris",
        "Asia/Dubai",
        "Asia/Bangkok",
        "Asia/Singapore",
        "Asia/Hong_Kong",
        "Asia/Tokyo",
        "Australia/Sydney"
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // MARK: - 1. Appearance (Theme)
            SettingsCard(title: "Appearance") {
                Picker("Theme", selection: Binding(
                    get: { env.appTheme },
                    set: { env.setAppTheme($0) }
                )) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag(AppTheme.system)
                    Label("Dark", systemImage: "moon.fill").tag(AppTheme.dark)
                    Label("Light", systemImage: "sun.max.fill").tag(AppTheme.light)
                }
                .pickerStyle(.segmented)
            }
            
            // MARK: - 2. Haptics & Vibration
            SettingsCard(title: "Haptics & Touch") {
                Toggle("Haptic Feedback", isOn: $env.isHapticsEnabled)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .tint(AppColors.brand)
                    .onChange(of: env.isHapticsEnabled) { enabled in
                        if enabled {
                            NativeHaptics.success()
                        }
                    }
            }
            
            // MARK: - 3. Timezones
            SettingsCard(title: "Timezones") {
                VStack(alignment: .leading, spacing: 16) {
                    // Display timezone
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display timezone (IANA)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppleMenuChip(title: "Timezone", selectionText: displayTz, icon: "globe") {
                            ForEach(commonTimeZones, id: \.self) { tz in
                                Button(tz) {
                                    displayTz = tz
                                    isSaved = false
                                }
                            }
                        }
                        
                        Button {
                            displayTz = TimeZone.current.identifier
                            isSaved = false
                        } label: {
                            Text("Use device timezone (\(TimeZone.current.identifier))")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.brand)
                        }
                    }
                    
                    Divider()
                    
                    // Default import timezone
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default import timezone (IANA)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppleMenuChip(title: "Import timezone", selectionText: importTz, icon: "clock") {
                            ForEach(commonTimeZones, id: \.self) { tz in
                                Button(tz) {
                                    importTz = tz
                                    isSaved = false
                                }
                            }
                        }
                        
                        Text("Used for file imports and broker sync without timezone offset.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack(spacing: 12) {
                        AppButton("Save timezones", icon: "checkmark", style: .primary, size: .compact) {
                            dataStore.generalSettings.displayTimeZone = displayTz
                            dataStore.generalSettings.defaultImportTimeZone = importTz
                            if let tz = TimeZone(identifier: displayTz) {
                                env.currentTimeZone = tz
                            }
                            dataStore.saveToDisk()
                            isSaved = true
                            statusMessage = "Timezones saved."
                        }
                        
                        if isSaved {
                            Text(statusMessage)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                }
            }
        }
        .onAppear {
            displayTz = dataStore.generalSettings.displayTimeZone
            importTz = dataStore.generalSettings.defaultImportTimeZone
        }
    }
}
