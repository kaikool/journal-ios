# Trade Journal — Native iOS

<p align="center">
  <img src="https://raw.githubusercontent.com/kaikool/journal-ios/main/TradeJournal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" height="120" alt="Trade Journal Icon" style="border-radius: 26px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  <strong>Native iOS Trading Terminal, Performance Journal, Prop Firm Ledger & AI Execution Coach</strong><br>
  Built with SwiftUI, Swift Charts, Swift Concurrency, and Supabase PostgreSQL.
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml">
    <img src="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml/badge.svg?branch=main" alt="Build Status" />
  </a>
  <img src="https://img.shields.io/badge/iOS-17.0%2B-007AFF.svg?logo=apple&logoColor=white" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%7C%206.0-F05138.svg?logo=swift&logoColor=white" alt="Swift 5.10 / 6.0" />
  <img src="https://img.shields.io/badge/Backend-Supabase%20PostgreSQL-3ECF8E.svg?logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License MIT" />
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa">
    <img src="https://img.shields.io/badge/Download_IPA-TradeJournal.ipa-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download TradeJournal.ipa" height="38" />
  </a>
</p>

---

## Overview

**Trade Journal** is a native iOS trading journal and analytical terminal designed for Forex, Metals, Indices, Futures, and Crypto traders. It unifies order-fill reconstruction, multi-account prop firm tracking, historical candle replay, macro economic calendar monitoring, and multi-provider AI coaching into an offline-first mobile workspace.

---

## Core Modules & Capabilities

### 1. Terminal Dashboard & Quantitative Analytics (`Features/Dashboard`, `Features/Analytics`)
- **Equity & Underwater Drawdown Curves:** Interactive Swift Charts tracking cumulative Net/Gross P&L, peak-to-trough drawdown percentage, and daily return bars.
- **Multi-Axis Edge Score (`EdgeScoreEngine`):** Evaluates trading edge across Win Rate, Profit Factor, Expectancy, Risk-to-Reward, Consistency, and Max Drawdown Control.
- **Temporal & Session Attribution:** Breakdowns across Asian, London, London/NY Overlap, and New York sessions (`SessionBreakdownChart`), alongside weekday and hourly heatmaps (`TimeHeatmapView`, `WeekdayChart`).
- **Customizable Layout (`DashboardCustomizerSheet`):** Role-based layout presets and drag-and-drop widget ordering.

### 2. Trade Reconstruction & Execution Audit (`Core/Domain/Engines`, `Features/Trades`)
- **Flat-to-Flat Order Matching (`TradeReconstructionEngine`):** Reconstructs closed round-trip positions and partial scale-outs from raw execution fills using **FIFO**, **LIFO**, or **Weighted Average (WAVG)**.
- **Exact Decimal Accounting (`FinancialInvariants`, `AssetContractEngine`):** Computes Gross P&L, Commissions, Overnight Swaps (`netP&L = grossP&L − fees + swap`), R-Multiples, and MAE/MFE using exact `Decimal` arithmetic and normalized broker contract sizes (`XAUUSD` 100 oz/lot, standard FX 100,000 units/lot, Indices, and Crypto).
- **Playbook & Discipline Tracking (`Features/Playbooks`):** Setup checklists (`TradeRuleCheck`), mistake categorization (`TradeFailureTaxonomy`), and Missed Trade logging (`MissedTradesView`).

### 3. AI Execution Coach, Pre-Trade Desk & Memory (`Features/AIReflection`, `Core/Networking/AI`)
- **Multi-Timeframe Market Structure Scanner:** Multi-timeframe (`D1 • H4 • H1 • M15`) interactive candlestick inspection with order blocks, momentum, EMA 21/50, and 3-line Wilder RSI system (`CandleChartView`, `MarketCandleChartView`, `MarketStateSnapshotBuilder`).
- **Trade Audit & Interactive Follow-Up (`TradeAICoachSheet`):** Context-aware AI evaluation of live and closed trades with multi-turn Q&A (`AICoachSessionStore`) and lesson extraction (`SupabaseTradeLessonSync`).
- **Persistent AI Memory & Research Workspace (`AIAdvisorMemoryEngine`, `AIResearchWorkspaceEngine`):** Tracks verified trader habits, recurring psychological leaks, and structured market hypotheses across sessions.
- **Multi-Provider AI Routing (`AIFallbackProvider`):** Supports Google Gemini, Groq Cloud, OpenRouter, and Supabase Edge Functions (`supabase/functions/ai-reflection`).

### 4. Daily Journal, Economic Calendar & Rich Notebook (`Features/Journal`)
- **Timezone-Aligned Daily Ledger:** Resolves daily logs, trading streaks, and session windows strictly against the trader's active market timezone (`JournalIds.dayId(for:timeZone:)`).
- **Economic Calendar (`ForexFactoryService`, `DayEconomicCalendarView`):** Macro news feed with high/medium/low impact filtering, countdown badges, and Actual / Forecast / Previous figures.
- **Markdown Notebook & Routines (`NotebookView`, `ProgressRoutinesView`):** Rich note editor with templates, chart attachments (`SupabaseStorageService`), trade linking, embedded AI note inquiry (`NoteAIInquirySheet`), and daily pre/post-market checklists.

### 5. Prop Firm Tracker & Treasury Ledger (`Features/PropFirm`)
- **Challenge & Funded Account Lifecycle (`PropFirmTrackerView`):** Tracks evaluation phases (Phase 1, Phase 2) and Funded accounts across **The5ers**, **FTMO**, **Topstep**, **FundedNext**, and custom firms.
- **Objective Guardrails (`PropAccountObjectivesChartCard`):** Visual progress tracking for profit targets, daily drawdown limits, and maximum loss thresholds.
- **Financial Ledger (`PropFirmLedgerView`):** Records challenge fees, resets, fee refunds, and profit-split payouts to calculate net prop trading ROI.

### 6. Multi-Timeframe Trade Replay (`Features/TradeReplay`)
- **Historical Candle Playback (`TradeReplayView`, `TradeReplayLandscapeChartView`):** Bar-by-bar OHLCV playback across `M1`, `M5`, `M15`, `H1`, `H4`, and `D1` timeframes (`MarketDataService` / OANDA feed) with entry/exit markers, dynamic SL/TP lines, and live unrealized P&L telemetry.

### 7. Multi-Broker Sync & Universal CSV Importer (`Core/Sync`, `Features/Import`)
- **Direct Broker & Cloud Providers (`SyncManager`):**
  - **The5ers (`The5ersSyncProvider`):** Direct synchronization of prop accounts, balance/equity metrics, and trade history.
  - **Exness (`ExnessSyncProvider`):** REST API synchronization for Exness accounts.
  - **cTrader (`CTraderSyncProvider`):** OAuth 2.0 account and deal history sync.
  - **Supabase Cloud (`SupabaseSyncProvider`):** Bidirectional PostgreSQL and Storage sync with offline-first local caching (`TradeDataStore`).
- **Universal CSV Importer (`StandardCSVImporter`):** Auto-detects **MetaTrader 4/5**, **cTrader**, **TradingView**, and **TradeLocker** statements with deterministic SHA-256 fill deduplication (`TradeDeduplicator`).

---

## Repository Structure

```text
.
├── .github/workflows/
│   └── build-ipa.yml               # CI/CD pipeline: Design System audit, XcodeGen & Release IPA packaging
├── TradeJournal/
│   ├── Resources/                  # Assets.xcassets & bundled configuration
│   ├── Sources/
│   │   ├── App/                    # AppEnvironment, TradeJournalApp & SplashScreenView
│   │   ├── Core/
│   │   │   ├── Data/               # TradeDataStore (offline cache) & Supabase sync services
│   │   │   ├── Domain/
│   │   │   │   ├── Engines/        # 27 domain engines (FIFO/LIFO/WAVG, EdgeScore, Liquidity, CSV, PropFirm)
│   │   │   │   └── Models/         # 21 financial & journal domain models
│   │   │   ├── Networking/         # The5ers, Exness, cTrader, ForexFactory, MarketData & AI clients
│   │   │   ├── Sync/               # SyncManager & broker/cloud sync providers
│   │   │   └── Utilities/          # KeychainHelper, NativeHaptics, PrivacyMask & AppLogger
│   │   ├── DesignSystem/           # Single Source of Truth UI components, Swift Charts, Theme & Typography
│   │   └── Features/               # Dashboard, Trades, AIReflection, Journal, Playbooks, PropFirm,
│   │                               # TradeReplay, Analytics, Accounts, Import & Settings
│   └── Tests/                      # Unit & financial invariant test suite
├── supabase/
│   ├── functions/ai-reflection/    # Supabase Edge Function for AI coaching & reflection
│   └── migrations/                 # PostgreSQL schema migrations (trades, numeric(38,10), MAE/MFE, AI memory)
├── scripts/
│   └── check_design_system.js      # Automated static analyzer enforcing Design System standards in CI
├── AppSecrets.plist.example        # Template for local API keys & cloud credentials
├── Package.swift                   # Swift Package Manager manifest
└── project.yml                     # XcodeGen project specification
```

---

## Installation & Development

### 1. Direct Sideload (Pre-built IPA)
Download the latest unsigned release binary from GitHub Releases:
- **Direct Download:** [TradeJournal.ipa](https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa)
- Sideload onto iOS 17.0+ devices via **TrollStore**, **AltStore**, **SideStore**, **Sideloadly**, or **ESign / LiveContainer**.

### 2. Local Build from Source (macOS + Xcode 16+)
1. **Clone the repository:**
   ```bash
   git clone https://github.com/kaikool/journal-ios.git
   cd journal-ios
   ```
2. **Configure API Credentials (Optional for Local Build):**
   Copy `AppSecrets.plist.example` to `TradeJournal/Resources/AppSecrets.plist` and populate your keys (`GEMINI_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OANDA_API_KEY`, `EXNESS_API_KEY`). `AppSecrets.plist` is git-ignored so credentials are never committed.
3. **Generate the Xcode Project & Run:**
   ```bash
   brew install xcodegen
   xcodegen generate
   open TradeJournal.xcodeproj
   ```
4. **Verify Design System Compliance:**
   ```bash
   node scripts/check_design_system.js
   ```

---

## License

This project is licensed under the [MIT License](LICENSE).
