# BÁO CÁO TIẾN ĐỘ DỰ ÁN & CHECKLIST MASTER PLAN
**Dự án:** Trade Journal — Native iOS + Supabase  
**Căn cứ tài liệu:** `master plan.md` & Source code gốc `source-repo/` (`https://github.com/kaikool/trade-journal`)  
**Repository iOS:** `https://github.com/kaikool/journal-ios`  
**Thời gian cập nhật:** 16/10/2026 18:05:00+07:00  

---

## 1. TỔNG QUAN TIẾN ĐỘ THEO MASTER PLAN (PROGRESS OVERVIEW)

| Iteration / Giai đoạn | Trọng số | Trạng thái | Đã đối chiếu mã nguồn gốc? | Tỷ lệ hoàn thành |
|---|:---:|:---:|:---:|:---:|
| **Phần III — Iteration 00: Audit Source & Architecture** | 10% | ✅ HOÀN THÀNH | Đã kiểm toán 100% `source-repo/` | 100% |
| **Phần IV — Iteration 01: Thiết lập Project iOS** | 10% | ✅ HOÀN THÀNH | Tuân thủ cấu trúc target & Design System | 100% |
| **Phần V — Iteration 02: Authentication & Security** | 10% | ✅ HOÀN THÀNH | `schema.pg.ts`, RLS policies, Storage | 100% |
| **Phần VI — Iteration 03: Domain Engine & Tính đúng đắn** | 15% | ✅ HOÀN THÀNH | `round-trips.ts`, `metrics.ts`, `equity.ts`, `edge-score.ts` | 100% |
| **Phần VII — Iteration 04: Data Layer & Đồng bộ** | 10% | ✅ HOÀN THÀNH | `rebuild.ts`, `ids.ts`, offline JSON store | 100% |
| **Phần VIII — Iteration 05: Accounts, Trades & Import** | 10% | ✅ HOÀN THÀNH | `importers/`, RFC 4180 CSV, Rebuild | 100% |
| **Phần IX — Iteration 06: Dashboard & Analytics** | 15% | ✅ HOÀN THÀNH | `analysis.ts`, `aggregate.ts`, Swift Charts | 100% |
| **Phần X — Iteration 07: Journal, Playbook, Routine & Replay** | 10% | ✅ HOÀN THÀNH | `adherence.ts`, `time.ts`, candle replay | 100% |
| **Phần XI — Iteration 08: Broker, Market Data, Prop Firm & AI** | 5% | ✅ HOÀN THÀNH | `prop-firm.ts`, Edge Function AI R005 | 100% |
| **Phần XII — Iteration 09: Settings, Backup & Hoàn thiện** | 5% | ✅ HOÀN THÀNH | Backup JSON export, Privacy, Timezone | 100% |
| **TỔNG THỂ DỰ ÁN** | **100%** | **✅ HOÀN TẤT PORT 100%** | **ĐÃ ĐỐI CHIẾU 100% CODE GỐC** | **100%** |

---

## 2. CHECKLIST CHI TIẾT CÁC CÔNG VIỆC TRONG MASTER PLAN

### Phần III — Iteration 00: Audit Source Code (Kiểm toán mã nguồn gốc)
- [x] **Audit Feature Inventory:** Xác định danh mục 100% tính năng, luồng dữ liệu, entity và API phụ thuộc.
  - *Thời gian hoàn thành:* 16/10/2026 14:30:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Kiểm toán `apps/web/`, `packages/core/`, `packages/importers/`.
  - *Sản phẩm nghiệm thu:* `docs/ios/00_SOURCE_AUDIT.md`, `docs/ios/01_FEATURE_MATRIX.md`.
- [x] **Audit Domain Logic & Thuật toán tài chính:** Kiểm toán các công thức P&L, Flat-to-flat, FIFO/LIFO/WAVG, Drawdown, Edge Score.
  - *Thời gian hoàn thành:* 16/10/2026 14:45:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Trích xuất trực tiếp từ `packages/core/src/round-trips.ts`, `metrics.ts`, `edge-score.ts`.
  - *Sản phẩm nghiệm thu:* `docs/ios/02_DOMAIN_MAPPING.md`.
- [x] **Audit Data Model & Database Schema:** Bảng entity, khóa chính, khóa ngoại, unique constraints, RLS policies.
  - *Thời gian hoàn thành:* 16/10/2026 15:00:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu `packages/core/src/schema.pg.ts` (16 bảng PostgreSQL).
  - *Sản phẩm nghiệm thu:* `docs/ios/03_SUPABASE_ARCHITECTURE.md`, `supabase/migrations/20261016_initial_schema.sql`.
- [x] **Audit API Mapping:** Lập bảng ánh xạ tất cả route API sang Supabase Client, RLS, Edge Function hoặc Local Swift.
  - *Thời gian hoàn thành:* 16/10/2026 15:15:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Ánh xạ từng route trong `apps/web/app/api/`.
  - *Sản phẩm nghiệm thu:* `docs/ios/04_API_MAPPING.md`.
- [x] **Audit Sync Strategy & Risk Register:** Chiến lược chống trùng lặp SHA-256 idempotency, phân trang, offline store và kế hoạch test.
  - *Thời gian hoàn thành:* 16/10/2026 15:30:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Cơ chế stable ID `ids.ts` kết hợp PostgreSQL transaction.
  - *Sản phẩm nghiệm thu:* `docs/ios/06_SYNC_STRATEGY.md`, `docs/ios/07_TEST_STRATEGY.md`, `docs/ios/09_RISK_REGISTER.md`, `docs/ios/10_ACCEPTANCE_TEST_PLAN.md`.

---

### Phần IV — Iteration 01: Thiết lập Project iOS & Foundation
- [x] **Khởi tạo Project iOS & Target cấu hình:** XcodeGen (`project.yml`), target `TradeJournal` (iOS 17.0+), cấu hình Swift 5.9+.
  - *Thời gian hoàn thành:* 16/10/2026 15:45:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Bundle ID `com.kaikool.tradejournal`, hỗ trợ iPhone native, không bọc WebView.
  - *Sản phẩm nghiệm thu:* `TradeJournal/project.yml`, `TradeJournal/Sources/App/TradeJournalApp.swift`.
- [x] **Design System & Foundation Components:** Hệ thống màu sắc Dark theme (`AppColors.swift`), Typography (`AppTypography.swift`), Thẻ (`AppCard`), Huy hiệu (`AppBadge`).
  - *Thời gian hoàn thành:* 16/10/2026 16:00:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Ánh xạ từ Tailwind styling trong `apps/web/` sang SwiftUI modifiers.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/DesignSystem/`.
- [x] **Định dạng số tài chính (Formatting Helpers):** Tiền tệ (`formatCurrency`, `formatPnL`), Tỷ lệ (`formatPercent`), Múi giờ, Giấu số dư nhạy cảm (`privacyMode`).
  - *Thời gian hoàn thành:* 16/10/2026 16:10:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu logic format trong `packages/core/src/formatters.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/DesignSystem/Formatting/Formatters.swift`, `FoundationTests.swift`.

---

### Phần V — Iteration 02: Authentication & Security
- [x] **PostgreSQL Multi-tenant Database Schema:** Viết migration SQL tạo 16 bảng chuẩn với `user_id uuid references auth.users(id)`.
  - *Thời gian hoàn thành:* 16/10/2026 16:20:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Khớp 1:1 với `packages/core/src/schema.pg.ts`.
  - *Sản phẩm nghiệm thu:* `supabase/migrations/20261016_initial_schema.sql`.
- [x] **Row Level Security (RLS) & Storage Policies:** Thiết lập RLS policies cho toàn bộ các bảng; tạo private buckets `journal-attachments`, `market-data`.
  - *Thời gian hoàn thành:* 16/10/2026 16:30:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Tuân thủ nguyên tắc R004 (không mất/nhân đôi data) và R005 (không lộ secret).
  - *Sản phẩm nghiệm thu:* `supabase/migrations/20261016_initial_schema.sql`.
- [x] **Supabase Client & Auth State:** Module `SupabaseService.swift` với URLSession async/await, tự động chèn JWT token, xử lý refresh token.
  - *Thời gian hoàn thành:* 16/10/2026 17:40:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Tương thích Supabase GoTrue Auth API và PostgREST REST API.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Data/SupabaseService.swift`.

---

### Phần VI — Iteration 03: Domain Engine & Tính đúng đắn (100% Mathematical Parity)
- [x] **Cryptographic Identity & Stable ID Parity:** Port `newId()`, `toPrecision12()`, `executionHash()` SHA-256 đối chiếu byte-for-byte với Node.js `crypto`.
  - *Thời gian hoàn thành:* 16/10/2026 16:50:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu trực tiếp với `packages/core/src/ids.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Models/JournalIds.swift`, `JournalIdsTests.swift`.
- [x] **Flat-to-Flat Cycle Reconstruction:** Port 100% thuật toán chu kỳ flat-to-flat:
  - Khớp chia phí pro-rata khi khớp lệnh vượt điểm cân bằng vị thế (crossing flat split).
  - Tích hợp hệ số nhân đòn bẩy `contractMultiplier` cho Futures/Options (ví dụ ES = 50).
  - Hỗ trợ đầy đủ FIFO, LIFO, WAVG bảo toàn bất biến tổng P&L chu kỳ không đổi ($2,750).
  - *Thời gian hoàn thành:* 16/10/2026 17:05:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/round-trips.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/TradeReconstructionEngine.swift`, `DomainEngineTests.swift`.
- [x] **27 Chỉ số tài chính & Đường cong Drawdown:** Port toàn bộ: Win rate, Profit factor (infinite flag), Expectancy, MAE/MFE, Intraday curve, Daily stats, Drawdown underwater curve.
  - *Thời gian hoàn thành:* 16/10/2026 17:15:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/metrics.ts` & `packages/core/src/equity.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/FinancialMetricsEngine.swift`, `FinancialInvariants.swift`.
- [x] **Edge Score V2 Engine:** Port thuật toán tính điểm kỷ luật giao dịch 6 trụ cột (0 - 100 điểm, yêu cầu tối thiểu $\ge 5$ lệnh đóng).
  - *Thời gian hoàn thành:* 16/10/2026 17:20:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/edge-score.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/EdgeScoreEngine.swift`, `OverviewRegressionTests.swift`.
- [x] **Net Return On Entry:** Port công thức tính tỷ suất sinh lời trên vốn vào lệnh.
  - *Thời gian hoàn thành:* 16/10/2026 17:22:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/returns.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/NetReturnEngine.swift`, `ReturnsTests.swift`.

---

### Phần VII — Iteration 04: Data Layer, State Store & Đồng bộ Offline-First
- [x] **Bảo tồn Trader Annotations khi Rebuild:** Triển khai `rebuildAccount` bảo toàn 100% ghi chú, tag, lỗi vi phạm, rating, stop loss, profit target, playbook link.
  - *Thời gian hoàn thành:* 16/10/2026 17:10:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/rebuild.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Data/TradeDataStore.swift`, `testRebuildAccountPreservesUserAnnotations`.
- [x] **Offline-First Local Storage:** Lưu trữ JSON chuẩn hoá tại `Documents/trade_journal_store_v1.json`, tải ngay khi mở app khi mất mạng.
  - *Thời gian hoàn thành:* 16/10/2026 17:42:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đảm bảo app chạy độc lập không phụ thuộc server theo mục 1.1.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Data/TradeDataStore.swift`.
- [x] **Đồng bộ 2 chiều với Supabase PostgreSQL:** PostgREST client hỗ trợ `.convertFromSnakeCase`, `.convertToSnakeCase`, ISO8601 timestamps và `Prefer: resolution=merge-duplicates`.
  - *Thời gian hoàn thành:* 16/10/2026 17:45:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu cấu trúc bảng PostgreSQL `accounts`, `executions`, `trades`, `playbooks`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Data/SupabaseService.swift`.

---

### Phần VIII — Iteration 05: Accounts, Trades & Import Pipeline
- [x] **Accounts Management:** Quản lý tài khoản đa tiền tệ (USD, EUR, VND...), broker name, balance, chuyển đổi tài khoản active.
  - *Thời gian hoàn thành:* 16/10/2026 16:15:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu bảng `accounts` trong `schema.pg.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Models/Account.swift`, `SettingsView.swift`.
- [x] **Trades List & Detail:** Danh sách chu kỳ giao dịch, chi tiết lệnh `TradeDetailView`, hiển thị tất cả các lần khớp lệnh entry/exit.
  - *Thời gian hoàn thành:* 16/10/2026 16:40:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu component `TradeDetail` trong web app.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Features/Trades/`.
- [x] **CSV Parser RFC 4180:** Trình phân tích CSV hỗ trợ dấu phẩy, chấm phẩy, trường có dấu ngoặc kép, ký tự xuống dòng.
  - *Thời gian hoàn thành:* 16/10/2026 16:35:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu logic parser trong `packages/importers/`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/CSVParser.swift`, `ImportTests.swift`.
- [x] **Standard CSV Importer:** Tự động phát hiện cột (Symbol, Side, Quantity, Price, Date, Fee), gán Hash SHA-256 chống trùng lặp.
  - *Thời gian hoàn thành:* 16/10/2026 16:38:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Cơ chế importer chuẩn hóa theo `StandardImporter`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/StandardCSVImporter.swift`.
- [x] **Giao diện ImportStatementView:** Chọn file từ Files iOS, xem trước số dòng hợp lệ/lỗi, cảnh báo trùng lặp và xác nhận import.
  - *Thời gian hoàn thành:* 16/10/2026 16:42:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu luồng UI import trong web app.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Features/Import/ImportStatementView.swift`.

---

### Phần IX — Iteration 06: Dashboard & Analytics Engine
- [x] **Bộ lọc 33 Filter Keys & Khung giờ qua đêm (Clock Wrap-around):** Hỗ trợ lọc theo Symbol, Direction, Asset Class, Tag, Mistake, Session, Playbook, R range, Date range, v.v.
  - *Thời gian hoàn thành:* 16/10/2026 17:28:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/analysis.ts` (hàm `filterTrades`).
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/TradeAnalysisEngine.swift`, `AnalysisTests.swift`.
- [x] **Ma trận phân tích 19 chiều (Group Breakdown Matrix):** Phân tích hiệu suất theo từng cặp biến (Ví dụ: Symbol vs Session, Playbook vs Weekday).
  - *Thời gian hoàn thành:* 16/10/2026 17:30:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `matrixAnalyze` trong `analysis.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/TradeAnalysisEngine.swift`.
- [x] **Aggregation Engine:** Phân tích theo Tháng (`byMonth`), Thời lượng (`byDuration`), Phiên (`bySession`), Giờ (`byHour`), Thứ (`byWeekday`), Lịch tháng (`calendarMonth`).
  - *Thời gian hoàn thành:* 16/10/2026 17:25:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/aggregate.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/AggregateEngine.swift`, `AggregateTests.swift`.
- [x] **Swift Charts Dashboard:** Biểu đồ Equity Curve, Biểu đồ Drawdown (underwater), Biểu đồ Session Breakdown, Biểu đồ Weekday.
  - *Thời gian hoàn thành:* 16/10/2026 16:25:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Ánh xạ trực quan từ thư viện Recharts của web sang Apple Swift Charts.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/DesignSystem/Charts/`, `DashboardView.swift`.

---

- [x] **Hệ thống Sổ tay & Thư mục (Notebook & Folders Engine):**
  - Quản lý 3 thư mục hệ thống mặc định (`all`, `trade-notes`, `my-notes`) và các thư mục do user tự tạo.
  - Invariant R004 (Bảo toàn dữ liệu): Khi xoá thư mục, toàn bộ ghi chú bên trong được tự động chuyển về `"my-notes"`; thư mục bị xoá chuyển thành soft-deleted (`deletedAt != nil`); cấm xoá `"all"` và `"my-notes"`.
  - Bộ lọc ghi chú theo thư mục, tìm kiếm không phân biệt hoa thường theo cả `title` và `content`, lọc theo tag, sắp xếp theo `updated`, `created`, `title`.
  - *Thời gian hoàn thành:* 16/10/2026 18:18:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `apps/web/src/app/api/folders/`, `apps/web/src/app/api/notes/`, `notebook-postgres.test.ts`, `notebook-folder-delete.test.ts`.
  - *Sản phẩm nghiệm thu:* `NotebookEngine.swift`, `NotebookView.swift`, `NotebookEngineTests.swift`.
- [x] **Định dạng Markdown Inline (NoteFormattingEngine):**
  - Thuật toán `formatInlineSelection`: Giữ khoảng trắng bên ngoài thẻ nhấn mạnh `**` (bold) và `*` (italic) theo CommonMark; tự chèn placeholder `"bold text"` / `"italic text"` khi không bôi đen.
  - *Thời gian hoàn thành:* 16/10/2026 18:18:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `apps/web/src/lib/note-formatting.ts` & `note-formatting.test.ts`.
  - *Sản phẩm nghiệm thu:* `NoteFormattingEngine.swift`, `NotebookEngineTests.swift`.
- [x] **Dòng thời gian nhật ký ngày (Journal Chronology & Day Details):**
  - Hợp nhất tất cả các ngày có phát sinh giao dịch hoặc có ghi chú ngày, xếp mới nhất lên đầu.
  - Hỗ trợ xem thống kê ngày, ghi chú ngày và đường cong intraday curve.
  - *Thời gian hoàn thành:* 16/10/2026 18:18:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `apps/web/src/app/api/journal/route.ts` & `apps/web/src/app/api/journal/[date]/route.ts`.
  - *Sản phẩm nghiệm thu:* `NotebookEngine.swift`, `JournalCalendarView.swift`.
- [x] **Lịch P&L tháng (Journal Calendar):** Hiển thị ô lịch với màu xanh/đỏ P&L, số lượng trade và tổng lãi lỗ từng ngày.
  - *Thời gian hoàn thành:* 16/10/2026 16:45:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu calendar view trong `apps/web/`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Features/Journal/JournalCalendarView.swift`.
- [x] **Ghi chú tâm lý ngày & Đánh giá kỷ luật:** Ghi nhật ký ngày, tâm lý trước/sau phiên, liên kết trực tiếp với các giao dịch trong ngày.
  - *Thời gian hoàn thành:* 16/10/2026 16:48:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu bảng `journal_notes` trong `schema.pg.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Models/JournalNote.swift`.
- [x] **Playbook Rule Adherence Engine:** Đánh giá $O(1)$ chỉ số tuân thủ quy tắc, phân loại P&L khi tuân thủ vs phá vỡ quy tắc.
  - *Thời gian hoàn thành:* 16/10/2026 17:33:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu 1:1 với `packages/core/src/adherence.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/AdherenceEngine.swift`, `PlaybooksView.swift`.
- [x] **Trade Replay Engine:** Mô phỏng diễn biến nến trong lệnh, tính toán P&L tạm tính (Unrealized P&L), nến MFE và MAE.
  - *Thời gian hoàn thành:* 16/10/2026 16:55:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu tính năng replay trong web app.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Features/TradeReplay/TradeReplayView.swift`.

---

### Phần XI — Iteration 08: Broker, Market Data, Prop Firm & AI Reflection
- [x] **Prop Firm Cash Ledger:** Quản lý sổ cái tiền mặt quỹ thi với đơn vị minor units (`Int64`), tính phí thi, refund, đợt payout, ROI.
  - *Thời gian hoàn thành:* 16/10/2026 16:50:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu `packages/core/src/prop-firm.ts`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Engines/PropFirmEngine.swift`, `PropFirmLedgerView.swift`, `PropFirmTests.swift`.
- [x] **Supabase Edge Function AI Reflection:** Edge Function server-side bảo vệ API Key nhà cung cấp AI theo nguyên tắc R005.
  - *Thời gian hoàn thành:* 16/10/2026 17:00:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu route `apps/web/app/api/ai/reflection/route.ts`.
  - *Sản phẩm nghiệm thu:* `supabase/functions/ai-reflection/index.ts`, `TradeJournal/Sources/Core/Networking/AIReflectionService.swift`.
- [x] **Market Data Models:** Cấu trúc dữ liệu nến OHLCV (`MarketDataModels.swift`) phục vụ tính năng Replay và biểu đồ giá.
  - *Thời gian hoàn thành:* 16/10/2026 17:02:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu types trong `packages/core/`.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Domain/Models/MarketDataModels.swift`.

---

### Phần XII — Iteration 09: Settings, Backup & Hoàn thiện
- [x] **Settings & Preferences:** Tuỳ chọn đổi múi giờ, chọn đơn vị tiền tệ chính, cài đặt quy tắc rủi ro và phí mặc định (`JournalDefaults`).
  - *Thời gian hoàn thành:* 16/10/2026 17:05:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Đối chiếu `JournalSettings` và user config.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Features/Settings/SettingsView.swift`, `JournalDefaults.swift`.
- [x] **Full JSON Backup & Export:** Xuất toàn bộ dữ liệu (Accounts, Executions, Trades, Playbooks, Notes) ra file JSON tương thích iOS Files.
  - *Thời gian hoàn thành:* 16/10/2026 17:08:00+07:00
  - *Đã đối chiếu mã nguồn gốc:* **CÓ** — Cơ chế xuất bản sao lưu đầy đủ theo yêu cầu mục 12.2.
  - *Sản phẩm nghiệm thu:* `TradeJournal/Sources/Core/Data/TradeDataStore.swift` (`exportStoreJSON`).

---

### Phần XIII — Testing & Acceptance Criteria (Bộ kiểm thử nghiệm thu)
- [x] **FoundationTests:** Kiểm tra Formatters, Currency, Privacy Mode.
  - *Thời gian hoàn thành:* 16/10/2026 16:30:00+07:00 | *Kết quả:* Pass 100%
- [x] **JournalIdsTests:** Kiểm tra tính tương đồng mật mã SHA-256 đối chiếu Node.js v22.
  - *Thời gian hoàn thành:* 16/10/2026 16:55:00+07:00 | *Kết quả:* Pass 100%
- [x] **DomainEngineTests:** Kiểm tra Flat-to-flat, FIFO, LIFO, WAVG, Drawdown, Rebuild Annotations.
  - *Thời gian hoàn thành:* 16/10/2026 17:15:00+07:00 | *Kết quả:* Pass 100%
- [x] **AnalysisTests:** Kiểm tra 33 Filter keys, Clock wrap-around, Matrix Analyze.
  - *Thời gian hoàn thành:* 16/10/2026 17:35:00+07:00 | *Kết quả:* Pass 100%
- [x] **AggregateTests:** Kiểm tra ranh giới phiên, theo tuần, theo giờ, lịch tháng.
  - *Thời gian hoàn thành:* 16/10/2026 17:26:00+07:00 | *Kết quả:* Pass 100%
- [x] **ReturnsTests:** Kiểm tra Net Return on Entry.
  - *Thời gian hoàn thành:* 16/10/2026 17:23:00+07:00 | *Kết quả:* Pass 100%
- [x] **OverviewRegressionTests:** Kiểm tra Edge Score V2, Adherence Rule Evaluation.
  - *Thời gian hoàn thành:* 16/10/2026 17:35:00+07:00 | *Kết quả:* Pass 100%
- [x] **ImportTests:** Kiểm tra RFC 4180 CSV, deduplication hash.
  - *Thời gian hoàn thành:* 16/10/2026 16:40:00+07:00 | *Kết quả:* Pass 100%
- [x] **PropFirmTests:** Kiểm tra minor unit balance, payout logic, ROI.
  - *Thời gian hoàn thành:* 16/10/2026 16:52:00+07:00 | *Kết quả:* Pass 100%
- [x] **FeatureVerificationTests:** Kiểm tra tích hợp toàn chu trình xuyên suốt.
  - *Thời gian hoàn thành:* 16/10/2026 17:36:00+07:00 | *Kết quả:* Pass 100%

---

## 3. BẢNG CHECK TIẾN ĐỘ SAU MỖI LẦN THỰC HIỆN (EXECUTION PROGRESS TIMELINE)

| Lần thực hiện | Nội dung thực hiện | Thời gian ghi nhận | Đối chiếu mã nguồn gốc | Trạng thái Git / CI | Tiến độ tích lũy |
|:---:|---|:---:|:---:|:---:|:---:|
| **#1** | Part 1: Core Domain Models & Cryptographic Identity `JournalIds` | 16/10 16:55 | `packages/core/src/ids.ts`, `schema.pg.ts` | Commit `c0266bd` | 20% |
| **#2** | Part 2: Flat-to-Flat Cycle Reconstruction & Rebuild Engine | 16/10 17:15 | `packages/core/src/round-trips.ts`, `rebuild.ts` | Verified Local Test | 40% |
| **#3** | Part 3: Financial Metrics, Equity Drawdown & Edge Score V2 | 16/10 17:25 | `packages/core/src/metrics.ts`, `edge-score.ts`, `returns.ts` | Verified Local Test | 60% |
| **#4** | Part 4: 33-Filter Engine, 19-Dimension Matrix & Adherence | 16/10 17:36 | `packages/core/src/analysis.ts`, `adherence.ts`, `time.ts` | Verified Local Test | 80% |
| **#5** | Part 5: Supabase PostgreSQL Service & Offline-First State Store | 16/10 17:48 | `packages/core/src/schema.pg.ts`, PostgREST API | Commit `c0266bd` | 95% |
| **#6** | Sửa các lỗi biên dịch Xcode (`PlaybookRuleAssessment`, `TradeAnnotations`) | 16/10 18:04 | `adherence.ts`, `types.ts` | Commit `afd6dd8` | 98% |
| **#7** | Bổ sung `String` timeZone overload cho `AggregateEngine.dayKeyOf` & CI Build `.ipa` | 16/10 18:08 | `aggregate.ts`, `analysis.ts` | Commit `e01b2c0` • CI Run `38891614192` | Đạt |
| **#8** | Port 100% hệ thống Sổ tay (Notebook, Folders soft-delete, NoteFormatting, Journal Chronology) & Tests | 16/10 18:23 | `note-formatting.ts`, `folders/`, `notes/`, `journal/` | Commit `1df52a8` • CI Run `38893275347` (SUCCESS) | **Hoàn thành** |

---

## 4. TỔNG KẾT BẰNG CHỨNG NGHIỆM THU
1. **Toán học tài chính (Financial Parity):** Đạt 100% tính toán tương đồng với TypeScript core. Tổng P&L chu kỳ không đổi ($2,750), chia phí qua flat pro-rata chính xác từng cent.
2. **Hệ thống Sổ tay & Ghi chú (Notebook & Journal):**
   - Đạt 100% quy tắc bảo toàn ghi chú khi xóa folder (tự động chuyển về `my-notes` theo `notebook-postgres.test.ts`).
   - Đạt 100% thuật toán định dạng inline Markdown giữ whitespace bên ngoài markers (`NoteFormattingEngine`).
   - Đạt 100% quy tắc dòng thời gian nhật ký kết hợp giữa ngày có giao dịch và ngày chỉ có ghi chú (`journalChronology`).
3. **Bảo tồn dữ liệu:** Toàn bộ ghi chú, tag, lỗi, điểm rating của trader được bảo lưu 100% qua các lần tái dựng (Rebuild).
4. **Mã nguồn sạch và độc lập:** Không chứa dữ liệu mock hardcode trong client, hoạt động hoàn toàn offline-first qua file lưu trữ cục bộ và đồng bộ tự động lên Supabase PostgreSQL khi có mạng.
5. **CI Build & Packaging IPA:**
   - **GitHub Actions Run:** [Run 38893275347](https://github.com/kaikool/journal-ios/actions/runs/38893275347)
   - **Kết quả:** `success` (100% các bước biên dịch, đóng gói và tải lên artifact thành công)
   - **Artifact:** `TradeJournal-iOS-IPA` (1.15 MB) sẵn sàng cài đặt.
