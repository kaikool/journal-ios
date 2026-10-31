# Trade Journal — Native iOS

<p align="center">
  <img src="https://raw.githubusercontent.com/kaikool/journal-ios/main/TradeJournal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" height="120" alt="Trade Journal Icon" style="border-radius: 26px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  <strong>Institutional-Grade Trading Terminal, AI Coach & Prop Firm Ledger for iPhone</strong><br>
  Built natively with SwiftUI, Swift Charts, Swift Concurrency, and Supabase.
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml">
    <img src="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml/badge.svg?branch=main" alt="Build Status" />
  </a>
  <img src="https://img.shields.io/badge/iOS-17.0%2B-blue.svg?logo=apple&logoColor=white" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%7C%206.0-orange.svg?logo=swift&logoColor=white" alt="Swift 5.10 / 6.0" />
  <img src="https://img.shields.io/badge/Design_System-24_Standards_Enforced-0A84FF.svg" alt="24 Design Standards" />
  <img src="https://img.shields.io/badge/Backend-Supabase%20PostgreSQL-3ECF8E.svg?logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License MIT" />
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa">
    <img src="https://img.shields.io/badge/Download_IPA-TradeJournal.ipa-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download TradeJournal.ipa" height="38" />
  </a>
</p>

---

## ✨ Overview

**Trade Journal** is a high-precision native iOS trading terminal, analytical journal, prop firm ledger, and AI-powered execution coach crafted for disciplined Forex, Metals, Indices, Futures, and Crypto traders.

- **Offline-First & Cache-Resilient:** Instant startup via atomic local persistence (`TradeDataStore`) with automatic `.bak` snapshot recovery and background cloud synchronization (`SyncManager`).
- **Exact Financial Arithmetic:** Zero floating-point drift. Uses exact `Decimal` and minor-unit (`Int64`) invariants across contract sizes (Gold 100 oz/lot, Forex 100,000 units/lot, Indices, Crypto, and CFDs). Cloud sync persists monetary columns as PostgreSQL `numeric(38,10)` serialized via exact decimal strings.
- **Single Source of Truth Design System:** Every screen, modal, badge, button, input, and chart HUD is governed by **24 Architectural Standards** inside `TradeJournal/Sources/DesignSystem`—with zero inline UI styling permitted in feature views.

---

## 🚀 Core Capabilities

### 1. 📊 Customizable Terminal Dashboard & Swift Charts
- **Interactive Equity & Drawdown Curves:** Track cumulative P&L, peak-to-trough underwater drawdown (%), and daily return distribution with interactive scrubbing.
- **Edge Score Radar & Risk Gauges:** Multi-axis evaluation of Win Rate, Profit Factor, Expectancy, Risk-Reward Ratio, Consistency, and Max Drawdown Control (`EdgeScoreEngine`).
- **Session, Weekday & Hourly Attribution:** Automated breakdown across Asian, London, London/NY Overlap, New York, and Off-hours sessions (`TimeHeatmapView`, `SessionBreakdownChart`, `WeekdayChart`).
- **Preset & Drag-and-Drop Layout Customizer:** Switch between curated terminal presets or reorder and hide dashboard widgets with native haptic feedback.

### 2. ⚡ Flat-to-Flat Trade Reconstruction & Execution Audit
- **Order Matching Engines:** Reconstructs closed round-trip positions and partial scale-outs from raw execution fills using **FIFO**, **LIFO**, or **WAVG** (`TradeReconstructionEngine`).
- **Broker-Proof Symbol Canonicalization:** Automatically normalizes broker suffixes (`XAUUSDm`, `EURUSD.pro`, `US30_i`, etc.) so contract multipliers, pip values, and tick sizes are always exact (`AssetContractEngine`).
- **Execution Discipline & Failure Taxonomy:** Tag setups against Playbook rules (`TradeRuleCheck`), log execution mistakes (`TradeFailureTaxonomy`), track Missed Trades (`MissedTradesView`), and inspect R-multiples, MAE/MFE, commissions, and overnight swaps.

### 3. 🤖 AI Coach, Pre-Trade Desk & Persistent Memory
- **Pre-Trade Market Scanner (`PreTradeChartCard` & `MultiTimeframeTriVisionCanvas`):** Simultaneous multi-timeframe (`D1 • H4 • M15`) candlestick inspection with automated liquidity sweeps, order blocks, momentum, and moving average snapshots (`LiquidityEngine`, `MarketStateSnapshotBuilder`).
- **Individual Trade AI Audit (`TradeAICoachSheet`):** Deep post-trade and live-position execution critique with interactive follow-up Q&A (`AICoachSessionStore`) and one-tap lesson extraction.
- **Persistent AI Memory & Research Workspace (`AIAdvisorMemoryEngine`, `AIResearchWorkspaceEngine`):** Stores verified trader habits, recurring psychological leaks, and structured market hypotheses synced across devices via Supabase (`SupabaseAIMemorySync`, `SupabaseAIResearchSync`).
- **Agentic Tool Dispatch (`AIToolDispatcher`):** Enables the AI Coach to query account metrics, session summaries, and historical trade slices on demand.

### 4. 📅 Daily Journal, Economic Calendar & Rich Notebook
- **Timezone-Aligned Daily Hub (`JournalHubView`):** All trades, daily summaries, and routines resolve strictly against the trader's configured trading timezone (`JournalIds.dayId(for:timeZone:)`).
- **ForexFactory Economic Calendar (`ForexFactoryService` & `DayEconomicCalendarView`):** Real-time macro event feed with high/medium/low impact filtering, countdown badges, and actual vs. forecast vs. previous figures.
- **Rich Markdown Notebook & AI Note Inquiry (`NotebookView`, `NoteAIInquirySheet`):** Structured templates, trade linking, image attachments (`SupabaseStorageService`), and contextual AI Q&A directly inside journal notes.
- **Daily Routines & Discipline Checklists (`ProgressRoutinesView`):** Track pre-market preparation and post-market review habits.

### 5. 💼 Prop Firm Tracker & Financial Ledger
- **Challenge & Funded Account Lifecycle (`PropFirmTrackerView`):** Monitor Phase 1, Phase 2, and Funded accounts across **The5ers**, **FTMO**, **Topstep**, **FundedNext**, and custom prop firms.
- **Objectives & Drawdown Guardrails (`PropAccountObjectivesChartCard`):** Visual progress bars for profit targets, daily drawdown limits, and maximum static/trailing loss thresholds.
- **Complete Treasury Ledger (`PropFirmLedgerView`):** Track challenge fees, resets, fee refunds, and profit split payouts to compute true Net Prop ROI.

### 6. ⏪ Multi-Timeframe Trade Replay
- **Interactive Candle-by-Candle Playback (`TradeReplayView` & `TradeReplayLandscapeChartView`):** Step forward/backward through historical OHLCV bars (`M1`, `M5`, `M15`, `H1`, `H4`, `D1`) with entry/exit markers, dynamic SL/TP lines, and live unrealized P&L / R-multiple HUDs.

### 7. 🔄 Multi-Broker Sync & Universal CSV Importer
- **Direct Broker Providers (`SyncManager`):**
  - **The5ers (`The5ersSyncProvider`):** Direct account metrics, prop challenge objectives, and trade history synchronization.
  - **Exness (`ExnessSyncProvider`):** Automated terminal sync for Exness accounts.
  - **cTrader (`CTraderSyncProvider`):** OAuth 2.0 integration for cTrader live and demo accounts.
  - **Supabase Cloud (`SupabaseSyncProvider`):** Bidirectional sync for trades, executions, accounts, journal notes, playbooks, prop ledger transactions, AI memories, and chart attachments.
- **Universal RFC 4180 CSV Importer (`StandardCSVImporter`):** Auto-detects **MetaTrader 4/5**, **cTrader**, **TradingView**, and **TradeLocker** statements with deterministic SHA-256 deduplication (`TradeDeduplicator`).

---

## 🏛️ Architecture & Project Structure

The codebase comprises **266 modular Swift files** organized under strict separation of concerns:

```text
TradeJournal/
├── Sources/
│   ├── App/                        # AppEnvironment, TradeJournalApp, SplashScreenView
│   ├── Core/
│   │   ├── Data/                   # TradeDataStore (offline-first cache + reactive state)
│   │   │   └── Supabase/           # Modular cloud sync engines (Trades, Journal, PropFirm, AIMemory, Storage)
│   │   ├── Domain/
│   │   │   ├── Engines/            # 27 pure domain engines (FIFO/LIFO/WAVG, EdgeScore, Liquidity, CSV, PropFirm)
│   │   │   └── Models/             # 21 strongly-typed financial & domain models
│   │   ├── Networking/             # CTraderService, The5ersService, ExnessService, ForexFactory, MarketData
│   │   │   └── AI/                 # AIReflectionService, AIPromptBuilder, AIAdvisorMemoryEngine, Fallback client
│   │   ├── Sync/                   # Unified SyncManager & provider protocols
│   │   │   └── Providers/          # Supabase, The5ers, Exness, and cTrader sync providers
│   │   └── Utilities/              # NativeHaptics, PrivacyMask, KeychainHelper, Logger
│   ├── DesignSystem/               # SINGLE SOURCE OF TRUTH (24 Architectural Standards)
│   │   ├── Charts/                 # 11 Swift Charts & Canvas components (Candle, TriVision, Equity, Radar)
│   │   ├── Components/             # 32 standardized HIG components (Buttons, Badges, Cards, Sheets, Inputs)
│   │   ├── Formatting/             # Formatters.swift (Currency, Percent, R-Multiple, Pips, Compact numbers)
│   │   ├── Theme/                  # AppColors, AppSpacing, AppAnimations
│   │   └── Typography/             # AppTypography (9-tier semantic type scale)
│   └── Features/
│       ├── Accounts/               # Multi-account selector, cards, balance & currency configuration
│       ├── AIReflection/           # AI Coach Hub, Pre-Trade Desk, Memory Manager, Research Workspace
│       ├── Analytics/              # Deep performance & behavioral drawdown breakdowns
│       ├── Dashboard/              # Customizable terminal widgets (Financial, Curve, Risk, Activity)
│       ├── Import/                 # Statement CSV importer & mapping preview
│       ├── Journal/                # Daily Journal, Calendar Insights, Economic Calendar, Rich Notebook
│       ├── Playbooks/              # Strategy playbooks, rule checklists & condition edge charts
│       ├── PropFirm/               # Prop firm overview, accounts, payouts, transactions & objective charts
│       ├── Settings/               # Connections, AI config, market data, currency rates & data management
│       ├── TradeReplay/            # Portrait & landscape candle replay studio
│       └── Trades/                 # Trade list, detail audit cards, manual entry, targets & AI Coach sheet
├── scripts/
│   └── check_design_system.js      # Automated 24-Standard static analysis & multi-line AST/context auditor
└── check_swift.js                  # Fast Swift syntax & delimiter balance verifier
```

---

## 🎨 24 Architectural Standards (Zero Inline UI Policy)

All UI in `TradeJournal/Sources/Features` consumes exclusively from `TradeJournal/Sources/DesignSystem`. Writing inline styles, raw system fonts, ad-hoc buttons, manual card backgrounds, or unformatted currency strings in feature views is strictly prohibited and automatically blocked by CI.

| # | Standard Category | Canonical DesignSystem API |
| :--- | :--- | :--- |
| **01** | **Buttons & Actions** | `AppPrimaryButton`, `AppSecondaryButton`, `AppDestructiveButton`, `AppActionPill`, `ModalCloseButton`, `ModalCircleButton` |
| **02** | **Badges & Tags** | `AppBadge`, `AppTag`, `AppleMenuChip`, `AppRatioBar` |
| **03** | **Segmented Controls** | `AppSegmentedBar`, `AppBinarySegmentedToggle` |
| **04** | **Filter Chips** | `AppFilterChip` |
| **05** | **Form Fields & Inputs** | `AppTextField`, `AppNumericField`, `AppNumericValueField`, `AppDropdownField`, `AppSearchBar` |
| **06** | **Selection & Checklist Rows** | `AppToggleRow`, `AppCheckboxRow` |
| **07** | **Cards & Containers** | `AppCard`, `.appCardStyle()`, `.appSubCardStyle()`, `AppFloatingBar`, `AppChatBubble`, `AppSectionHeader` |
| **08** | **Metric Tiles & KPIs** | `AppMetricTile` |
| **09** | **Feedback & Empty States** | `AppEmptyState`, `LoadingView`, `TradeJournalProLoader`, `ErrorBannerView` |
| **10** | **Chart HUDs & Annotations** | `AppTypography.badgeMarker`, `AppTypography.badgeMarkerSmall` |
| **11** | **Typography System** | `AppTypography` (`displayHero`, `metricLarge`, `pageTitle`, `cardHeader`, `rowTitle`, `body`, `caption`, etc.) |
| **12** | **Spacing & Layout Grid** | `AppSpacing` (`micro`, `small`, `standard`, `cardPadding`, `pageMargin`, `sectionGutter`) |
| **13** | **Modal Sheet Presentation** | `AppSheetContainer` |
| **14** | **Confirmation Dialogs** | `.appConfirmationAlert(...)`, `.appInfoAlert(...)`, `.appTransactionActionAlert(...)` |
| **15** | **Loading Shimmer Skeletons** | `AppSkeleton` |
| **16** | **Native Haptics Feedback** | `NativeHaptics` (`lightImpact()`, `mediumImpact()`, `heavyImpact()`, `selection()`, `success()`, `error()`) |
| **17** | **Animation Presets** | `AppAnimations` (`springQuick`, `springStandard`, `sheetSpring`, `easeInOutFast`) |
| **18** | **Financial Formatters** | `Formatters` (`currency`, `percent`, `rMultiple`, `price`, `signedCurrency`) |
| **19** | **Semantic Color Hierarchy** | `AppColors` (`brand`, `profit`, `loss`, `warning`, `background`, `cardBackground`, `primaryText`, `secondaryText`, `border`) |
| **20** | **Timezone & Date Alignment** | `AppEnvironment.shared.currentTimeZone`, `JournalIds.dayId(for:timeZone:)` |
| **21** | **Minimum Touch Targets** | 44×44pt minimum interactive hit bounds per Apple HIG |
| **22** | **Safe Keyboard Handling** | `ScrollView` wrapping with safe keyboard dismissal on all editable forms |
| **23** | **Offline-First Resilience** | Non-blocking `TradeDataStore` local state with background `SyncManager` reconciliation |
| **24** | **Safe Math & Zero Force-Unwrap** | Defensive optional binding and zero-division guards across all financial engines |

---

## 🔒 CI/CD Governance & Quality Gates

Every push and pull request to `main` runs the automated GitHub Actions pipeline (`.github/workflows/build-ipa.yml`):

1. **Swift Syntax Verification (`node check_swift.js`):** Validates delimiter balance, string literals, and structural integrity across all 266 Swift files.
2. **24-Standard Design System Audit (`node scripts/check_design_system.js`):** Performs single-line and multi-line context scanning across `TradeJournal/Sources` to reject any inline UI styling, raw fonts, ad-hoc colors, or unstandardized components.
3. **XcodeGen & Unsigned Release IPA Build:** Generates `TradeJournal.xcodeproj` via `xcodegen`, compiles the Release `iphoneos` binary on macOS `arm64`, packages `TradeJournal.ipa`, and publishes it to GitHub Releases.

To run the verification gates locally:

```bash
node check_swift.js
node scripts/check_design_system.js
```

---

## 📱 Installation & Local Development

### Option 1: Direct IPA Install (No Mac Required)
Download the latest pre-built binary from GitHub Releases:
- **Latest Release:** [Download TradeJournal.ipa](https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa)
- Sideload onto your iPhone using **AltStore**, **SideStore**, **Sideloadly**, **TrollStore**, or **LiveContainer**.

### Option 2: Build from Source (macOS + Xcode 16+)
1. Clone the repository:
   ```bash
   git clone https://github.com/kaikool/journal-ios.git
   cd journal-ios
   ```
2. Run the Design System & Syntax checks:
   ```bash
   node check_swift.js && node scripts/check_design_system.js
   ```
3. Generate the Xcode project and open it:
   ```bash
   brew install xcodegen
   xcodegen generate
   open TradeJournal.xcodeproj
   ```

---

## 📄 Technical Documentation

Detailed architectural and domain references are available in [`docs/`](docs/):
- [Project Status & Full Audit](docs/PROJECT_STATUS_FULL.md)
- [Master Architecture Plan](docs/MASTER_PLAN.md)
- [Domain & Financial Formula Mapping](docs/ios/02_DOMAIN_MAPPING.md)
- [Supabase Database & Cloud Architecture](docs/ios/03_SUPABASE_ARCHITECTURE.md)
- [Multi-Provider Sync & Conflict Resolution](docs/ios/06_SYNC_STRATEGY.md)
- [Automated IPA Build & Release Guide](docs/ios/BUILD_IPA_GUIDE.md)

---

## 🛡️ License

This project is licensed under the [MIT License](LICENSE).
