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
                VStack(alignment: .leading, spacing: 14) {
                    Text("Select your preferred visual style or adapt automatically to system settings.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 10) {
                        themeOptionButton(
                            theme: .system,
                            title: "System",
                            icon: "circle.lefthalf.filled",
                            description: "Match iOS"
                        )
                        
                        themeOptionButton(
                            theme: .dark,
                            title: "Dark",
                            icon: "moon.fill",
                            description: "Terminal"
                        )
                        
                        themeOptionButton(
                            theme: .light,
                            title: "Light",
                            icon: "sun.max.fill",
                            description: "Daylight"
                        )
                    }
                }
            }
            
            // MARK: - 2. Haptics & Vibration
            SettingsCard(title: "Haptics & Touch") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $env.isHapticsEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Haptic Feedback")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            Text("Tactile vibrations when scrubbing charts, swiping trades, and switching tabs.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .tint(AppColors.brand)
                    .onChange(of: env.isHapticsEnabled) { enabled in
                        if enabled {
                            NativeHaptics.success()
                        }
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
                        
                        Text("Trade times, calendars, journal days, and analytics use this timezone.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Button {
                            displayTz = TimeZone.current.identifier
                            isSaved = false
                        } label: {
                            Text("Use this device's timezone (\(TimeZone.current.identifier))")
                                .font(AppTypography.caption)
                                .underline()
                                .foregroundColor(AppColors.accent)
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
                        
                        Text("Used for timestamps without an offset in file imports and IBKR broker sync. You can override it for each file. Existing trades are not changed; correcting an IBKR account's timezone requires a separate account for recovery.")
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
    
    private func themeOptionButton(theme: AppTheme, title: String, icon: String, description: String) -> some View {
        let isSelected = env.appTheme == theme
        return Button {
            NativeHaptics.selection()
            env.setAppTheme(theme)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                    
                    Text(description)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppColors.brand.opacity(env.colorScheme == .dark ? 0.16 : 0.08) : AppColors.secondaryBackground.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppColors.brand : AppColors.border.opacity(0.4), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}
