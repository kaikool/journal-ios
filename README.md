# Trade Journal — Native iOS

<p align="center">
  <img src="https://raw.githubusercontent.com/kaikool/journal-ios/main/TradeJournal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" height="120" alt="Trade Journal Icon" style="border-radius: 26px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  <strong>Modern, High-Precision Trading Terminal & Journal for iPhone</strong><br>
  Built natively with SwiftUI, Swift Charts, Swift Concurrency, and Supabase.
</p>

<p align="center">
  <a href="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml">
    <img src="https://github.com/kaikool/journal-ios/actions/workflows/build-ipa.yml/badge.svg?branch=main" alt="Build Status" />
  </a>
  <img src="https://img.shields.io/badge/iOS-17.0%2B-blue.svg?logo=apple&logoColor=white" alt="iOS 17.0+" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%7C%206.0-orange.svg?logo=swift&logoColor=white" alt="Swift 5.10 / 6.0" />
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

**Trade Journal** is an institutional-grade trading journal crafted for disciplined forex, futures, metals, crypto, and equity traders. Engineered from the ground up for iOS, it combines high-precision financial arithmetic with an edge-to-edge frosted glass design system.

- **Offline-First & Resilient:** Instant startup via atomic JSON persistence with automatic backup recovery (`.bak`) and quarantine protection.
- **Accurate Financial Modeling:** Zero floating-point rounding errors. Uses exact `Decimal` and `Int64` minor units with standardized lot sizes and tick values (Gold 100 oz/lot, Forex 100k units/lot, Crypto, and CFDs).
- **Edge-to-Edge Frosted Canvas:** Content glides seamlessly under the floating island tab bar and streamlined top navigation.

---

## 🚀 Core Features

### 1. 📊 Terminal Dashboard & Swift Charts
- **Interactive Equity Curve:** Track cumulative equity growth over time with interactive scrubbing and peak-to-trough markers.
- **Underwater Drawdown (%):** Continuous drawdown monitoring against initial balance and peak equity.
- **Session Breakdown:** Automated trade attribution across 5 standard market sessions: Asian, London, London/NY Overlap, New York, and Off-hours.
- **Weekday & Hourly Heatmaps:** Visual insights into performance anomalies across weekdays and times of day.

### 2. ⚡ Flat-to-Flat Reconstruction
- Reconstructs closed round-trip positions from raw execution fills using standard order matching (**FIFO**, **LIFO**, **WAVG**).
- Calculates gross P&L, fees, swaps, net P&L, and holds duration down to the millisecond.

### 3. 🎨 Modern iOS HIG UI/UX
- **Unified Top Bar:** Integrated hamburger drawer menu, interactive **Account Selector Capsule Chip** (`[💳 All Accounts ▾]`), and Quick Add Trade button (`[+ Add]`).
- **Floating Island Bottom Bar:** Translucent `.ultraThinMaterial` frosted glass with specular highlight strokes.
- **Edge-to-Edge Scrolling:** Content slides underneath navigation bars with calibrated 88pt clearance—no truncated text or blocked buttons.

### 4. 💼 Prop Firm Management
- Track funded accounts, challenge phases, and verification rules across major prop firms (**FTMO**, **The5ers**, **Topstep**, **FundedNext**, etc.).
- Automated tracking of fees, resets, refunds, and net payout ROI.

### 5. 🤖 AI Coach & Reflection
- Built-in AI mentor powered by Supabase Edge Functions.
- Analyzes daily performance, identifies revenge trading or overleveraging, and scores execution discipline from 1 to 5 stars.

### 6. 🔄 Multi-Broker Sync & Universal CSV Import
- Direct OAuth & API integration for **cTrader** and **The5ers**.
- Universal RFC 4180 CSV importer with SHA-256 deduplication for **MetaTrader 4/5**, **cTrader**, **TradingView**, **TradeLocker**, and generic formats.

---

## 🛠️ Architecture & Tech Stack

```
TradeJournal/
├── Sources/
│   ├── App/                  # App environment, route coordinator, RootTabView
│   ├── Core/
│   │   ├── Domain/           # Financial models, invariant engines, EdgeScore, FIFO reconstruction
│   │   ├── Data/             # TradeDataStore (reactive state, offline cache, cloud sync)
│   │   ├── Networking/       # Cloud services (Supabase, cTrader OAuth, The5ers sync)
│   │   └── Utilities/        # Privacy masking, high-performance date parsers, logger
│   ├── DesignSystem/
│   │   ├── Charts/           # Swift Charts components (Equity, Drawdown, Heatmap, Weekday)
│   │   ├── Components/       # ShellHeader, FilterBar, Apple HIG buttons & cards
│   │   ├── Formatting/       # Strict financial formatters, currency symbols, pips/ticks
│   │   └── Theme/            # Adaptive dark/light semantic palette matching Web globals
│   └── Features/
│       ├── Dashboard/        # Terminal KPI widgets, multi-currency notices, customizable layout
│       ├── Trades/           # Filterable trade feed, execution breakdown, manual entry sheet
│       ├── Analytics/        # In-depth behavioral reports & drawdown audit
│       ├── Journal/          # Calendar view, daily mindset logs, rich text notebook
│       ├── Playbooks/        # Strategy cards, rule checklists, adherence impact analysis
│       ├── PropFirm/         # Funded account tracker, ledger tabs & payout receipts
│       ├── TradeReplay/      # Tick/candle replay of entry, exit, and MAE/MFE
│       ├── AIReflection/     # AI analysis and psychological feedback
│       ├── Accounts/         # Multi-account manager, initial balance & currency settings
│       └── Settings/         # Cloud sync triggers, CSV/JSON export, API keys
└── Tests/                    # Automated unit & integration tests
```

---

## 📱 Installation & Deployment

### Direct Download (No Mac Required)
Download the latest signed binary directly from GitHub Releases:
- **Download Link:** [TradeJournal.ipa](https://github.com/kaikool/journal-ios/releases/latest/download/TradeJournal.ipa)
- Install onto your iPhone via:
  - **AltStore / AltStore PAL**
  - **Sideloadly**
  - **TrollStore** (iOS 14.0 – 17.0)
  - **LiveContainer**

### Build from Source (macOS)
1. Clone the repository:
   ```bash
   git clone https://github.com/kaikool/journal-ios.git
   cd journal-ios
   ```
2. Generate the Xcode project using `xcodegen`:
   ```bash
   brew install xcodegen
   xcodegen generate
   ```
3. Open `TradeJournal.xcodeproj` in Xcode 16+, select your connected iPhone or iOS Simulator, and press **Cmd + R**.

---

## 📄 Documentation

Comprehensive technical specifications and implementation details are available in the [`docs/`](docs/) directory:

- [Project Status & Roadmap](docs/PROJECT_STATUS_FULL.md)
- [Master Implementation Plan](docs/MASTER_PLAN.md)
- [Automated IPA Build & Release Guide](docs/ios/BUILD_IPA_GUIDE.md)
- [Domain & Financial Formula Mapping](docs/ios/02_DOMAIN_MAPPING.md)
- [Supabase Database & Cloud Architecture](docs/ios/03_SUPABASE_ARCHITECTURE.md)
- [Sync Strategy & Conflict Resolution](docs/ios/06_SYNC_STRATEGY.md)

---

## 🛡️ License

This project is licensed under the [MIT License](LICENSE).
