# TradeJournal iOS - Development & UI Guidelines

## 1. Absolute Rule: Design System & Typography Compliance
All views, components, sheets, HUDs, charts, and modal dialogs in this repository **MUST** strictly adhere to the unified Design System (`TradeJournal/Sources/DesignSystem`).

### Strict Prohibitions
- **NO INLINE FONTS**: Never write `.font(.system(size: ...))` or `.font(.custom(...))` anywhere outside `AppTypography.swift`.
- **NO RAW TEXT HEADINGS**: Never use raw `.font(.largeTitle)`, `.font(.title)`, etc. Always use semantic `AppTypography` tokens.
- **NO AD-HOC BUTTONS**: Do not build custom unstyled `Button { ... } label: { ... }` with ad-hoc padding/backgrounds when standard `AppButton`, `AppPrimaryButton`, `AppSecondaryButton`, `AppDestructiveButton`, `AppActionPill`, or `ModalToolbarButtons` can be used.
- **NO AD-HOC CARDS**: Always wrap section content in `AppCard { ... }`.
- **NO AD-HOC FORM INPUTS**: Use `AppTextField` and `AppNumericField` for all user inputs.

---

## 2. Standard Design System Component Usage

Component Type | Standard Component | Example Usage
:--- | :--- | :---
**Button (Primary)** | `AppPrimaryButton` / `AppButton(..., style: .primary)` | Main actions (Save, Submit, Connect)
**Button (Secondary/Outline)** | `AppSecondaryButton` / `AppButton(..., style: .secondary)` | Secondary actions (Cancel, Filter, Manage)
**Button (Destructive)** | `AppDestructiveButton` / `AppButton(..., style: .destructive)` | Delete trade, Reset database
**Action Pill** | `AppActionPill` | Compact interactive action links
**Modal Toolbar Buttons** | `ModalCloseButton`, `ModalBackButton`, `ModalDeleteButton` | Standard circular modal navigation controls
**Badges & Pills** | `AppBadge`, `AppleMenuChip` | Status, win/loss, tags, regime indicators
**Segmented / Tabs** | `AppSegmentedBar` | Tab switching, timeframe selectors
**Filter Chips** | `AppFilterChip` | Filter toggles with active indicator & count
**Form Fields** | `AppTextField`, `AppNumericField`, `AppDropdown` | Text fields, decimal numbers, dropdowns
**Checklist & Rows** | `AppToggleRow`, `AppCheckboxRow` | Toggle settings, checklist compliance items
**Card Containers** | `AppCard` | Standard Apple-style rounded container with subtle border
**Section Headers** | `AppSectionHeader` | Standardized uppercase card section header with icon & badge
**Metric Tiles** | `AppMetricTile` | KPI cards, label/value pairs, trend indicators
**Empty States** | `AppEmptyState` | Standard icon pod, title, subtitle, and action button
**Feedback Banners** | `ErrorBannerView`, `LoadingView` | Feedback, loading, and error states

---

## 3. Typography Semantic Tokens (`AppTypography`)

Scale Tier | Token | Usage
:--- | :--- | :---
**Tier 1: Hero Financial** | `AppTypography.displayHero`, `displayHeroLarge`, `numberHero` | Net P&L hero, Total Balance
**Tier 2: Major Metric** | `AppTypography.displayMajor`, `metricLarge`, `metricMedium` | KPI card hero numbers, Drawdown %
**Tier 3: Page & Modal** | `AppTypography.pageTitle`, `sheetTitle` | Top navigation bar title, Sheet header title
**Tier 4: Section & Card** | `AppTypography.cardHeader`, `cardTitle`, `cardHeaderUppercase` | Card title, uppercase section headers
**Tier 5: Row & Inputs** | `AppTypography.rowTitle`, `rowPrimary`, `formInput`, `body` | List items, TextField content, body copy
**Tier 6: Subtitles & Labels** | `AppTypography.rowSubtitle`, `formLabel`, `subheadline` | Secondary item descriptions, input labels
**Tier 7: Key-Value Pairs** | `AppTypography.statLabel`, `statValue`, `numberSmall` | Stat label/value pairs with monospaced digits
**Tier 8: Badges & Actions** | `AppTypography.actionButton`, `actionPill`, `badgeStandard`, `badgeMicro`, `badgeMarker` | Button labels, pills, tags, chart markers
**Tier 9: Micro & Footers** | `AppTypography.caption`, `captionMicro`, `footnote` | Timestamps, metadata, footnotes, hints

---

## 4. Verification Before Submitting
Before pushing any code, you **MUST** run:
1. `node check_swift.js` - verifies balanced AST syntax across all Swift files.
2. `node scripts/check_design_system.js` - verifies 100% compliance with DesignSystem & AppTypography.
