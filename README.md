# Trade Journal — Native iOS

<p align="center">
  <img src="https://raw.githubusercontent.com/kaikool/journal-ios/main/TradeJournal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" height="120" alt="Trade Journal Icon" style="border-radius: 26px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  <strong>Institutional-Grade Trading Terminal, Performance Analytics & AI Execution Coach for iOS</strong><br>
  Engineered natively with SwiftUI, Swift Charts, Swift Concurrency, and Supabase.
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml">
    <img src="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml/badge.svg?branch=main" alt="Build Status" />
  </a>
  <img src="https://img.shields.io/badge/iOS-17.0%2B-007AFF.svg?logo=apple&logoColor=white" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%7C%206.0-F05138.svg?logo=swift&logoColor=white" alt="Swift 5.10 / 6.0" />
  <img src="https://img.shields.io/badge/Architecture-Offline--First-34C759.svg" alt="Offline-First" />
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

**Trade Journal** is a native iOS trading journal and analytical terminal built for Forex, Metals, Indices, Futures, and Crypto traders. It combines deterministic financial accounting with multi-timeframe market visualization, prop firm treasury management, and an context-aware AI coaching engine.

### Core Engineering Principles
- **Deterministic Financial Precision:** Eliminates floating-point drift by executing all P&L, fee, swap, R-multiple, and drawdown calculations using exact `Decimal` and minor-unit (`Int64`) arithmetic. Cloud persistence stores monetary fields as PostgreSQL `numeric(38,10)` serialized via lossless decimal strings.
- **Offline-First Reactivity:** Instant cold start and zero-latency navigation backed by atomic local persistence, automatic snapshot recovery (`.bak`), and asynchronous bidirectional cloud synchronization.
- **Unified Native Design System:** Built strictly on Apple Human Interface Guidelines with an adaptive semantic color system, tactile haptics, and a centralized component architecture.

---

## Key Features

### 📊 Performance Terminal & Analytics
- **Equity & Drawdown Curves:** High-frequency Swift Charts visualizations tracking cumulative net/gross P&L, peak-to-trough underwater drawdown (%), and daily return distribution.
- **Multi-Dimensional Edge Radar:** Quantitative scoring across Win Rate, Profit Factor, Expectancy, Risk-to-Reward, Consistency, and Drawdown Recovery.
- **Temporal & Session Attribution:** Automated performance segmentation across Asian, London, London/NY Overlap, and New York sessions, paired with weekday and hourly heatmaps.
- **Customizable Workspace:** Modular widget layout supporting role-based presets and drag-and-drop card arrangement.

### ⚡ Flat-to-Flat Trade Reconstruction
- **Execution Matching Engines:** Reconstructs complete round-trip trades and partial scale-outs from raw broker fills using **FIFO**, **LIFO**, or **Weighted Average (WAVG)** accounting.
- **Canonical Contract Resolution:** Normalizes broker-specific symbol suffixes (e.g., `XAUUSDm`, `EURUSD.pro`, `US30_i`) to accurately resolve contract multipliers, pip values, and tick sizes across asset classes.
- **Multi-Currency Reporting:** Converts cross-pair profits into the account's base currency using execution-time exchange rates or configurable FX rate tables.

### 🤖 AI Execution Coach & Pre-Trade Desk
- **Multi-Timeframe Pre-Trade Scanner:** Simultaneous `D1 • H4 • M15` candlestick canvas featuring algorithmic detection of liquidity sweeps, order blocks, momentum shifts, and key moving averages.
- **Post-Trade & Live Position Audits:** Contextual AI evaluation of individual trades—analyzing entry timing, stop-loss placement, MAE/MFE efficiency, and rule adherence.
- **Persistent Trader Memory & Research Workspace:** Long-term behavioral memory that tracks verified strengths, recurring psychological leaks, and structured market hypotheses across sessions.

### 📅 Daily Journal, Macro Calendar & Notebook
- **Timezone-Locked Daily Ledger:** Resolves all trading days, streaks, and daily summaries strictly against the trader's configured market timezone.
- **Real-Time Economic Calendar:** Integrated ForexFactory macro feed with impact filtering, live event countdowns, and Actual / Forecast / Previous consensus data.
- **Rich Markdown Notebook:** Structured pre-market and post-market templates, chart screenshot attachments, bidirectional trade linking, and embedded AI inquiry.

### 💼 Prop Firm Tracker & Treasury Ledger
- **Evaluation & Funded Lifecycle:** Track Phase 1, Phase 2, and Funded accounts across major proprietary trading firms (**The5ers**, **FTMO**, **Topstep**, **FundedNext**, and custom programs).
- **Risk & Objective Guardrails:** Real-time monitoring of profit targets, daily drawdown limits, and static/trailing maximum loss thresholds.
- **True Net ROI Accounting:** Dedicated ledger for challenge fees, resets, fee refunds, and profit-split payouts.

### ⏪ Multi-Timeframe Trade Replay
- **Historical Candle Playback:** Interactive bar-by-bar replay across `M1`, `M5`, `M15`, `H1`, `H4`, and `D1` resolutions with synchronized entry/exit markers, dynamic SL/TP levels, and real-time unrealized P&L / R-multiple telemetry.

### 🔄 Multi-Broker Sync & Universal CSV Import
- **Direct Broker Integrations:** Native synchronization providers for **The5ers**, **Exness**, and **cTrader** (OAuth 2.0), alongside **Supabase** cloud backup.
- **Universal Statement Importer:** RFC 4180 CSV parser supporting **MetaTrader 4/5**, **cTrader**, **TradingView**, and **TradeLocker** exports with deterministic SHA-256 fill deduplication.

---

## System Architecture

```text
TradeJournal/
├── Sources/
│   ├── App/                        # Application lifecycle, environment container & root navigation
│   ├── Core/
│   │   ├── Domain/
│   │   │   ├── Models/             # Immutable financial entities, currency contexts & journal schemas
│   │   │   └── Engines/            # Pure domain engines (FIFO/LIFO/WAVG, EdgeScore, Liquidity, PropFirm)
│   │   ├── Data/                   # Reactive TradeDataStore, local persistence & Supabase sync modules
│   │   ├── Networking/             # Broker API clients, market data feeds, economic calendar & AI services
│   │   ├── Sync/                   # Unified SyncManager & provider implementations
│   │   └── Utilities/              # Keychain security, privacy masking, haptics & structured logging
│   ├── DesignSystem/               # Centralized UI tokens, typography, formatters, charts & HIG components
│   └── Features/
│       ├── Dashboard/              # Terminal KPI widgets, equity curves & layout customizer
│       ├── Trades/                 # Trade feed, execution audit views, manual entry & AI trade coach
│       ├── AIReflection/           # AI Coach hub, pre-trade multi-timeframe desk, memory & research
│       ├── Journal/                # Calendar analytics, daily journal, economic calendar & rich notebook
│       ├── Playbooks/              # Strategy playbooks, rule checklists & expectancy attribution
│       ├── PropFirm/               # Prop account tracker, objective gauges & payout ledger
│       ├── TradeReplay/            # Portrait & landscape historical candle replay engine
│       ├── Analytics/              # Behavioral & drawdown deep-dive reports
│       ├── Accounts/               # Multi-account management & currency configuration
│       ├── Import/                 # Universal CSV statement mapper & deduplication preview
│       └── Settings/               # Broker connections, AI provider config & data management
└── docs/                           # Technical specifications, database schemas & sync architecture
```

---

## Installation & Getting Started

### Direct Installation (Pre-built IPA)
Download the latest release binary directly from GitHub Releases:
- **Latest Binary:** [TradeJournal.ipa](https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa)
- Install on iOS 17.0+ devices via **AltStore**, **SideStore**, **Sideloadly**, **TrollStore**, or **LiveContainer**.

### Building from Source
1. **Clone the repository:**
   ```bash
   git clone https://github.com/kaikool/journal-ios.git
   cd journal-ios
   ```
2. **Generate the Xcode project:**
   ```bash
   brew install xcodegen
   xcodegen generate
   ```
3. **Build and Run:**
   Open `TradeJournal.xcodeproj` in **Xcode 16.0+**, select an iOS 17.0+ simulator or physical device, and press `Cmd + R`.

---

## Documentation

In-depth architectural specifications are available in the [`docs/`](docs/) directory:

- [Master Architecture & System Plan](docs/MASTER_PLAN.md)
- [Domain Models & Financial Formulas](docs/ios/02_DOMAIN_MAPPING.md)
- [Supabase Database & Storage Schema](docs/ios/03_SUPABASE_ARCHITECTURE.md)
- [Multi-Provider Synchronization Strategy](docs/ios/06_SYNC_STRATEGY.md)
- [Automated IPA Build & Release Pipeline](docs/ios/BUILD_IPA_GUIDE.md)

---

## License

Released under the [MIT License](LICENSE).
