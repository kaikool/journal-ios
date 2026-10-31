# TradeJournal iOS - 24 Architectural Standards & Design System Guidelines

## 1. Absolute Rule: Zero Inline / Ad-hoc Code & Single Source of Truth
All code in this repository **MUST** strictly adhere to the unified Design System across all 24 Architectural Standards.
- **Single Source of Truth**: All UI tokens, components, formatters, and wrappers live exclusively in `TradeJournal/Sources/DesignSystem`. Feature views must consume only from `DesignSystem`. Any future redesign or modification MUST be made directly in the standard component, NEVER by overriding or writing inline styles in feature views.
- Any attempt to write inline styles, raw system fonts, unstandardized buttons, ad-hoc cards, raw currency strings, or direct UIKit haptics will be **automatically detected and rejected by GitHub Actions CI**.

---

## 2. The 24 Standardized Categories

### PART 1: CONTENT & CONTROLS (Standards 01 - 11)

#### Standard 01: Buttons & Actions
- **Primary Action**: `AppPrimaryButton("Title", icon: "...") { ... }`
- **Secondary Action**: `AppSecondaryButton("Title", icon: "...") { ... }`
- **Destructive Action**: `AppDestructiveButton("Title", icon: "...") { ... }`
- **Compact Action Pill**: `AppActionPill("Title", icon: "...") { ... }`
- **Modal Toolbar Circular Buttons**: `ModalCloseButton`, `ModalBackButton`, `ModalDeleteButton`, `ModalPrimaryButton`
- **PROHIBITED**: Writing raw `Button { ... } label: { Text(...).padding().background(...) }`.

#### Standard 02: Badges & Tags
- **Standard**: `AppBadge("Status", style: .profit / .loss / .neutral / .brand)`
- **Menu / Filter Chip**: `AppleMenuChip(title: "...", count: ...)`
- **PROHIBITED**: Writing `Text(...).padding().background(...).clipShape(Capsule())`.

#### Standard 03: Tablist & Segmented Controls
- **Standard**: `AppSegmentedBar(items, selection: $selected, titleFor: { ... })`
- **PROHIBITED**: Writing ad-hoc `HStack { ForEach ... Button }` loops for tab switches.

#### Standard 04: Filter Chips
- **Standard**: `AppFilterChip("Tag", isSelected: ..., count: ...)`
- **PROHIBITED**: Writing inline capsule toggles.

#### Standard 05: Form Fields & Inputs
- **Text Input**: `AppTextField("Label", text: $text, placeholder: "...")`
- **Financial / Decimal Input**: `AppNumericField("Position Size", text: $amount, unit: "Lots")`
- **Floating Point Value Input**: `AppNumericValueField("Amount", value: $amount)`
- **Dropdown Selection**: `AppDropdownField` / `AppDropdownPill` / `AppCompactDropdown`
- **PROHIBITED**: Writing raw `TextField` with custom padding/borders.

#### Standard 06: Selection & Checklist Rows
- **Settings Toggle**: `AppToggleRow("Title", subtitle: "...", isOn: $isOn)`
- **Discipline Checklist**: `AppCheckboxRow("Rule Checked", isChecked: ...)`
- **PROHIBITED**: Writing raw `Toggle` without standardized row typography and design system container.

#### Standard 07: Cards & Headers
- **Card Container**: `AppCard { ... }`
- **Card Section Header**: `AppSectionHeader("SECTION TITLE", icon: "...", badge: "...")`
- **PROHIBITED**: Writing `.background(AppColors.cardBackground).clipShape(RoundedRectangle(cornerRadius: 16))` manually in feature views.

#### Standard 08: Metric Tiles & Financial Display
- **KPI Tiles**: `AppMetricTile(title: "WIN RATE", value: "68.4%", trend: .up)`
- **Hero Figures**: `AppTypography.displayHero`, `AppTypography.numberHero`
- **PROHIBITED**: Hardcoding custom stat blocks with arbitrary font sizes.

#### Standard 09: Feedback & Empty States
- **Empty State**: `AppEmptyState(icon: "tray", title: "...", message: "...")`
- **Loading Spinner**: `LoadingView("Syncing...")`
- **Error Banner**: `ErrorBannerView(message: "...")`
- **PROHIBITED**: Creating custom empty state icons or error layouts.

#### Standard 10: Chart HUDs & Annotations
- **Candlestick Badges**: `AppTypography.badgeMarker`, `AppTypography.badgeMarkerSmall`
- **Timeframe Pills**: Standardized uppercase micro tokens.

#### Standard 11: Typography System (`AppTypography`)
- **PROHIBITED**: Writing `.font(.system(size: ...))` or `.font(.custom(...))` anywhere outside `AppTypography.swift`.
- Use the 9-tier scale: `displayHero`, `metricLarge`, `pageTitle`, `cardHeader`, `rowTitle`, `formLabel`, `statValue`, `badgeStandard`, `caption`.

---

### PART 2: FOUNDATIONS & SYSTEM INTERACTIONS (Standards 12 - 17)

#### Standard 12: Spacing & Layout Grid (`AppSpacing`)
- Use `AppSpacing.micro` (4pt), `.small` (8pt), `.standard` (12pt), `.cardPadding` (14pt), `.pageMargin` (16pt), `.sectionGutter` (24pt).
- **PROHIBITED**: Using random hardcoded padding numbers (e.g. 11, 13, 17, 23).

#### Standard 13: Modal Sheet Presentation (`AppSheetContainer`)
- Standard: `AppSheetContainer("Title", onClose: { dismiss() }) { ... }`
- **PROHIBITED**: Manually constructing navigation toolbars and close buttons inside sheets.

#### Standard 14: Confirmation Dialogs (`appConfirmationAlert`)
- Standard: `.appConfirmationAlert(...)`, `.appInfoAlert(...)`, `.appTransactionActionAlert(...)`
- **PROHIBITED**: Writing raw `.alert(...)` with custom ad-hoc buttons.

#### Standard 15: Loading Shimmer Skeletons (`AppSkeleton`)
- Standard: `AppSkeleton(height: 20)`
- **PROHIBITED**: Letting views flash empty or jump layout before data loads.

#### Standard 16: Native Haptics Feedback (`NativeHaptics`)
- Standard: `NativeHaptics.lightImpact()`, `NativeHaptics.mediumImpact()`, `NativeHaptics.heavyImpact()`, `NativeHaptics.selection()`, `NativeHaptics.success()`, `NativeHaptics.error()`
- **PROHIBITED**: Calling `UIImpactFeedbackGenerator` or `UISelectionFeedbackGenerator` directly, or calling `.lightImpact()` without `NativeHaptics.` prefix.

#### Standard 17: Animation Presets (`AppAnimations`)
- Standard: `AppAnimations.springQuick`, `AppAnimations.springStandard`, `AppAnimations.sheetSpring`, `AppAnimations.easeInOutFast`
- **PROHIBITED**: Hardcoding `.spring(response: ..., dampingFraction: ...)` repeatedly.

---

### PART 3: FINTECH POLISH & PRODUCTION RESILIENCE (Standards 18 - 24)

#### Standard 18: Financial Formatters (`Formatters`)
- Standard: `Formatters.formatCurrency(amount, currency: ...)`, `Formatters.formatPercent(rate)`, `Formatters.formatRMultiple(r)`
- **PROHIBITED**: Hardcoding string concatenations like `"$\(pnl)"` or manual string formatting for financial figures.

#### Standard 19: Semantic Color Hierarchy (`AppColors`)
- Standard: `AppColors.brand`, `AppColors.profit`, `AppColors.loss`, `AppColors.background`, `AppColors.cardBackground`, `AppColors.primaryText`, `AppColors.secondaryText`, `AppColors.border`
- **PROHIBITED**: Using ad-hoc `Color(hex:)` or arbitrary RGB literals directly inside feature views.

#### Standard 20: Timezone & Date Alignment
- Standard: Always resolve dates and daily journals against `AppEnvironment.shared.currentTimeZone` and `JournalIds.dayId(for:timeZone:)`.
- **PROHIBITED**: Using raw system `Date()` or `Calendar.current` without considering the user's active trading timezone.

#### Standard 21: Minimum Touch Target Bounds
- Standard: All interactive elements must maintain at least 44x44pt tactile bounds as required by Apple Human Interface Guidelines.
- **PROHIBITED**: Small tappable icons without `.frame(minWidth: 44, minHeight: 44)` or expanded contentShape hit targets.

#### Standard 22: Safe Keyboard Handling
- Standard: All editable forms must be embedded in `ScrollView` with appropriate keyboard dismiss modes and layout safety.
- **PROHIBITED**: Placing input fields at fixed bottom coordinates where the iOS virtual keyboard covers them.

#### Standard 23: Offline-First & Network Resilience
- Standard: `TradeDataStore` cache-first architecture. All user data, metrics, and journal entries are instantly queryable locally and synced seamlessly in background.
- **PROHIBITED**: Freezing the UI thread or blocking rendering on remote network requests.

#### Standard 24: Zero Unsafe Force-Unwrapping & Safe Math
- Standard: Defensive optional binding (`guard let`, `if let`, nil-coalescing `??`) and safe zero-division handling (`guard denominator != 0 else { return 0 }`).
- **PROHIBITED**: Using force-unwrap `!` on dynamic trade data, API payloads, or array indices.

---

## 3. GitHub CI Enforcement Gate
Every push and pull request runs:
1. `node check_swift.js` - Swift syntax balance verification across all Swift files.
2. `node scripts/check_design_system.js` - Strict 24-standard compliance audit.
If any violation is detected across any of the 24 standards, **the GitHub Actions build immediately halts and rejects the commit**.
