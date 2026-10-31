# TradeJournal iOS - 17-Component Architecture & Design System Guidelines

## 1. Absolute Rule: Zero Inline / Ad-hoc Code
All code in this repository **MUST** strictly adhere to the unified Design System across all 17 categories.
Any attempt to write inline styles, raw system fonts, unstandardized buttons, ad-hoc cards, or direct UIKit haptics will be **automatically detected and rejected by GitHub Actions CI**.

---

## 2. The 17 Standardized Component Categories

### Category 1: Buttons & Actions
- **Primary Action**: `AppPrimaryButton("Title", icon: "...") { ... }`
- **Secondary Action**: `AppSecondaryButton("Title", icon: "...") { ... }`
- **Destructive Action**: `AppDestructiveButton("Title", icon: "...") { ... }`
- **Compact Action Pill**: `AppActionPill("Title", icon: "...") { ... }`
- **Modal Toolbar Circular Buttons**: `ModalCloseButton`, `ModalBackButton`, `ModalDeleteButton`, `ModalPrimaryButton`
- **PROHIBITED**: Writing raw `Button { ... } label: { Text(...).padding().background(...) }`.

### Category 2: Badges & Tags
- **Standard**: `AppBadge("Status", style: .profit / .loss / .neutral / .brand)`
- **Menu / Filter Chip**: `AppleMenuChip(title: "...", count: ...)`
- **PROHIBITED**: Writing `Text(...).padding().background(...).clipShape(Capsule())`.

### Category 3: Tablist & Segmented Controls
- **Standard**: `AppSegmentedBar(items, selection: $selected, titleFor: { ... })`
- **PROHIBITED**: Writing ad-hoc `HStack { ForEach ... Button }` loops for tab switches.

### Category 4: Filter Chips
- **Standard**: `AppFilterChip("Tag", isSelected: ..., count: ...)`
- **PROHIBITED**: Writing inline capsule toggles.

### Category 5: Form Fields & Inputs
- **Text Input**: `AppTextField("Label", text: $text, placeholder: "...")`
- **Financial / Decimal Input**: `AppNumericField("Position Size", text: $amount, unit: "Lots")`
- **Dropdown Selection**: `AppDropdownField` / `AppDropdownPill`
- **PROHIBITED**: Writing raw `TextField` with custom padding/borders.

### Category 6: Selection & Checklist Rows
- **Settings Toggle**: `AppToggleRow("Title", subtitle: "...", isOn: $isOn)`
- **Discipline Checklist**: `AppCheckboxRow("Rule Checked", isChecked: ...)`
- **PROHIBITED**: Writing raw `Toggle` without standardized row typography.

### Category 7: Cards & Headers
- **Card Container**: `AppCard { ... }`
- **Card Section Header**: `AppSectionHeader("SECTION TITLE", icon: "...", badge: "...")`
- **PROHIBITED**: Writing `.background(AppColors.cardBackground).clipShape(RoundedRectangle(cornerRadius: 16))`.

### Category 8: Metric Tiles & Financial Display
- **KPI Tiles**: `AppMetricTile(title: "WIN RATE", value: "68.4%", trend: .up)`
- **Hero Figures**: `AppTypography.displayHero`, `AppTypography.numberHero`
- **PROHIBITED**: Hardcoding custom stat blocks with arbitrary font sizes.

### Category 9: Feedback & Empty States
- **Empty State**: `AppEmptyState(icon: "tray", title: "...", message: "...")`
- **Loading Spinner**: `LoadingView("Syncing...")`
- **Error Banner**: `ErrorBannerView(message: "...")`
- **PROHIBITED**: Creating custom empty state icons or error layouts.

### Category 10: Chart HUDs & Annotations
- **Candlestick Badges**: `AppTypography.badgeMarker`, `AppTypography.badgeMarkerSmall`
- **Timeframe Pills**: Standardized uppercase micro tokens.

### Category 11: Typography System (`AppTypography`)
- **PROHIBITED**: Writing `.font(.system(size: ...))` or `.font(.custom(...))` anywhere outside `AppTypography.swift`.
- Use the 9-tier scale: `displayHero`, `metricLarge`, `pageTitle`, `cardHeader`, `rowTitle`, `formLabel`, `statValue`, `badgeStandard`, `caption`.

### Category 12: Spacing & Layout Grid (`AppSpacing`)
- Use `AppSpacing.micro` (4pt), `.small` (8pt), `.standard` (12pt), `.cardPadding` (14pt), `.pageMargin` (16pt), `.sectionGutter` (24pt).
- **PROHIBITED**: Using random hardcoded padding numbers (e.g. 11, 13, 17, 23).

### Category 13: Modal Sheet Presentation (`AppSheetContainer`)
- Standard: `AppSheetContainer("Title", onClose: { dismiss() }) { ... }`
- **PROHIBITED**: Manually constructing navigation toolbars and close buttons inside sheets.

### Category 14: Confirmation Dialogs (`appConfirmationAlert`)
- Standard: `.appConfirmationAlert(isPresented: $show, title: "...", message: "...", onConfirm: { ... })`
- **PROHIBITED**: Writing custom `.alert(...)` with unstandardized destructive buttons.

### Category 15: Loading Shimmer Skeletons (`AppSkeleton`)
- Standard: `AppSkeleton(height: 20)`
- **PROHIBITED**: Letting views flash empty or jump layout before data loads.

### Category 16: Haptics Feedback (`NativeHaptics`)
- Standard: `NativeHaptics.lightImpact()`, `NativeHaptics.mediumImpact()`, `NativeHaptics.selection()`
- **PROHIBITED**: Calling `UIImpactFeedbackGenerator` or `UISelectionFeedbackGenerator` directly.

### Category 17: Animation Presets (`AppAnimations`)
- Standard: `AppAnimations.springQuick`, `AppAnimations.springStandard`, `AppAnimations.sheetSpring`, `AppAnimations.easeInOutFast`
- **PROHIBITED**: Hardcoding `.spring(response: ..., dampingFraction: ...)` repeatedly.

---

## 3. GitHub CI Enforcement Gate
Every push and pull request runs:
1. `node check_swift.js` - Swift syntax balance.
2. `node scripts/check_design_system.js` - Strict 17-category compliance audit.
If any violation is detected, **the GitHub Actions build immediately halts and rejects the commit**.
