# BÁO CÁO AUDIT SOURCE CODE DỰ ÁN GỐC (SOURCE AUDIT REPORT)
**Dự án:** Trade Journal  
**Source Repository:** https://github.com/kaikool/trade-journal  
**Thời điểm thực hiện Audit:** Tháng 10/2026  
**Môi trường thẩm định:** Windows 11 / Node.js v22.23.1 / Git 2.54.0

---

## 1. TỔNG QUAN HỆ THỐNG VÀ KIẾN TRÚC HIỆN TẠI

Kho mã nguồn gốc `trade-journal` là một **monorepo TypeScript** sử dụng `pnpm workspaces`, bao gồm 3 package/ứng dụng chính:

1. **`packages/core` (`@luxalgo/journal-core`)**:
   - Engine tính toán nghiệp vụ thuần túy (pure domain engine), không phụ thuộc UI, framework hay I/O.
   - Nhiệm vụ: Tái dựng vòng đời giao dịch (round-trip reconstruction flat-to-flat), phân bổ chi phí và P&L (FIFO/LIFO/WAVG), tính toán chỉ số hiệu suất (TradeMetrics), đường cong vốn (Equity Curve), Drawdown, thống kê chuỗi thắng/thua, phân tích R-multiple và tính toán điểm mở hiệu suất Edge Score v2.
   - Trạng thái kiểm thử: Đầy đủ unit tests với Vitest (`round-trips.test.ts`, `metrics.test.ts`, `analysis.test.ts`, `returns.test.ts`, `overview-regression.test.ts`).

2. **`packages/importers` (`@luxalgo/journal-importers`)**:
   - Bộ thư viện phân tích và chuẩn hóa dữ liệu giao dịch từ 13 định dạng sao kê/broker và file CSV tùy chỉnh.
   - Các định dạng hỗ trợ: MetaTrader 4/5 (HTML report và CSV Deals), Interactive Brokers (IBKR Statement CSV & Flex Query), ThinkorSwim, TradeZella, Tradervue, TopstepX, TradingView, NinjaTrader (kèm cơ chế review/reconciliation), Tradovate, Webull, DasTrader, Generic History, và Dynamic CSV Column Mapper.
   - Xử lý lệch timezone, định dạng số, phân tách đơn vị tiền tệ, và liên kết vị thế (position-based vs execution-based).
   - Trạng thái kiểm thử: Có unit test và fixture test mẫu (`dates.test.ts`, `history.test.ts`, `importers.test.ts`, `ninjatrader.test.ts`).

3. **`apps/web` (Next.js 15 App Router & Drizzle ORM)**:
   - Giao diện người dùng Web desktop/responsive (React 19, Tailwind CSS, Radix UI, Recharts, ECharts).
   - Backend API: Next.js Route Handlers (`src/app/api/...`), middleware xác thực session HMAC.
   - Cơ sở dữ liệu: Thiết kế lai SQLite / PostgreSQL (`src/db/schema.pg.ts`) qua Drizzle ORM. Đã có kịch bản di trú sang Supabase (`scripts/migrate-to-supabase.ts`).
   - Tích hợp ngoại vi:
     - Broker sync: Binance, Bybit, OKX, Topstep qua `@luxalgo/broker-sdk`.
     - The5ers Prop Firm MCP: Giao thức OAuth Authorization Code + PKCE S256, đồng bộ tài khoản, vị thế, chi phí mua gói và lịch sử rút tiền (payouts).
     - Prop Firm Expense Ledger: Quản lý chi phí thi tuyển, tài khoản quỹ, hoàn tiền và chi trả thưởng (cash ledger).
     - Market Data & Replay: Kết nối London Strategic Edge (LSE REST) và nạp CSV nến lưu tại Storage; tính toán Maximum Adverse Excursion (MAE) và Maximum Favorable Excursion (MFE).
     - AI Reflection: Tích hợp OpenAI / Anthropic (`ai` SDK) cho 3 tác vụ: Ask Your Journal, Trade Critique, và Day Recap.
     - Cron job: `/api/cron/broker-sync` đồng bộ định kỳ theo lịch.

---

## 2. PHÁT HIỆN KIẾN TRÚC QUAN TRỌNG NHẤT (CRITICAL FINDINGS)

### Phát hiện 1: Cơ chế xác thực nguyên bản là Single-User / Shared Password
- **Thực tế source code:** Trong `apps/web/src/middleware.ts`, toàn bộ hệ thống được bảo vệ bởi biến môi trường `JOURNAL_PASSWORD`. Người dùng đăng nhập bằng mật khẩu chung, sau đó server tạo cookie `journal_session` ký HMAC SHA-256.
- **Hệ quả trên Database:** Toàn bộ các bảng trong `src/db/schema.pg.ts` (`accounts`, `executions`, `trades`, `notes`, `folders`, `prop_accounts`,...) **hoàn toàn không có cột `user_id`**.
- **Yêu cầu chuyển đổi:** Để đáp ứng yêu cầu của người dùng là **ứng dụng iOS độc lập, đồng bộ đa thiết bị dựa trên tài khoản Supabase Auth và phân quyền RLS**:
  - Bắt buộc phải bổ sung trường `user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE` vào toàn bộ các bảng lưu dữ liệu người dùng.
  - Thiết lập chính sách Row Level Security (RLS) gắn chặt với `auth.uid() = user_id` cho mọi thao tác SELECT, INSERT, UPDATE, DELETE.

### Phát hiện 2: Bảng `trades` là Materialized View của `executions`
- **Quy tắc bất biến:** `executions` (các lần khớp lệnh thực tế) là chân lý nguyên tử (atomic source of truth). Bảng `trades` (vòng đời flat-to-flat) được sinh tự động thông qua hàm `rebuildAccountInTransaction`.
- Khi người dùng thêm, sửa hoặc nhập executions, hệ thống chạy thuật toán `buildRoundTrips` và cập nhật bảng `trades` thông qua Upsert (`ON CONFLICT (key) DO UPDATE`). Các trường ghi chú thủ công của người dùng (`notes`, `tagsJson`, `mistakesJson`, `playbookId`, `rating`, `stopLoss`, `profitTarget`, `reviewedAt`) được bảo toàn nhờ khóa ổn định `key = accountId|symbol|direction|openedAt`.

### Phát hiện 3: Tích hợp Broker SDK & Secret Management
- Quá trình đồng bộ broker sử dụng `@luxalgo/broker-sdk`. Thông tin API Key / Secret của sàn được mã hóa đối xứng AES-256-GCM với `JOURNAL_SECRET` và lưu trong cột `accounts.credentials_enc`.
- Trên iOS Native, việc giữ kết nối broker nền liên tục (background 24/7) hoặc nhúng secret vào binary là vi phạm nguyên tắc bảo mật R005 và giới hạn vòng đời của hệ điều hành iOS.

---

## 3. BẢNG KIỂM KÊ MODULE VÀ THƯ MỤC NGUỒN

| Phân hệ / Thư mục | Chức năng nghiệp vụ chính | Khả năng port sang iOS Native | Ghi chú kiến trúc |
|---|---|---|---|
| `packages/core/src/round-trips.ts` | Thuật toán tái dựng trade, ghép lot FIFO/LIFO/WAVG | Port trực tiếp 100% sang Swift | Dùng `Decimal` để bảo toàn độ chính xác tài chính |
| `packages/core/src/metrics.ts` | Tính toán chỉ số hiệu suất, win rate, expectancy, drawdown | Port trực tiếp 100% sang Swift | Giữ nguyên công thức và quy tắc chia |
| `packages/core/src/equity.ts` | Tạo đường cong vốn, điểm drawdown, thống kê ngày | Port trực tiếp 100% sang Swift | Tương thích Swift Charts |
| `packages/core/src/edge-score.ts` | Tính toán điểm hiệu suất Edge Score v2 (0 - 100) | Port trực tiếp 100% sang Swift | Công thức có trọng số pinned v2 |
| `packages/core/src/analysis.ts` | Bộ lọc đa chiều, tính R-multiple thực tế và kế hoạch | Port trực tiếp 100% sang Swift | Sử dụng cho màn hình Trades & Reports |
| `packages/importers/src/` | Phân tích 13 định dạng CSV/HTML + generic mapper | Port sang Swift Importer Engine | Parse trực tiếp trên iPhone qua `String` / File Stream |
| `apps/web/src/db/schema.pg.ts` | Định nghĩa schema PostgreSQL cho Drizzle | Chuyển thành Supabase Migration SQL | Bổ sung `user_id`, RLS, Indexes |
| `apps/web/src/server/executions.ts` | Hash execution chống trùng, insert batch, trigger rebuild | Port sang Swift / Supabase RPC | Idempotency qua `content_hash` |
| `apps/web/src/server/the5ers/` | OAuth PKCE, đồng bộ tài khoản The5ers, vị thế, payouts | Supabase Edge Function hoặc Swift OAuth | Bảo mật token trong Keychain |
| `apps/web/src/lib/prop-firms.ts` | Quản lý sổ cái tiền mặt Prop Firm (spend, payouts, receipts) | Port sang Swift Domain & Supabase | Tiền tệ lưu dạng số nguyên minor units (cents) |
| `apps/web/src/lib/excursions.ts` | Tính toán MAE/MFE từ nến thị trường | Port sang Swift Domain Engine | Tính toán cục bộ sau khi tải nến từ Storage |
| `apps/web/src/app/api/ai/` | Hỏi đáp nhật ký, nhận xét trade, tóm tắt ngày | Supabase Edge Functions | Giữ kín API key AI trên server |
| `apps/web/src/server/sync.ts` | Broker sync (@luxalgo/broker-sdk) | Client-side on-demand hoặc Edge Function | Đánh giá giới hạn chạy nền iOS |

---

## 4. KẾT LUẬN VÀ KHUYẾN NGHỊ AUDIT

1. **Về mặt nghiệp vụ lõi (Core Domain & Importers):**
   Hệ thống có cấu trúc toán học và quy tắc xử lý cực kỳ chặt chẽ, tách biệt hoàn toàn khỏi framework Web. Việc chuyển đổi sang Swift Engine sẽ đạt độ tương thích và độ chính xác 100% thông qua Differential Testing.

2. **Về mặt Data Model & Supabase:**
   Cần tạo bộ migration SQL hoàn chỉnh cho Supabase PostgreSQL bao gồm:
   - Thêm cột `user_id` cho 16 bảng dữ liệu.
   - Kích hoạt RLS và thiết lập Policy kiểm tra `auth.uid() = user_id`.
   - Tạo các hàm PostgreSQL / RPC để xử lý batch insert executions và trigger rebuild trade đảm bảo tính nguyên tử (Atomicity).

3. **Về mặt iOS Native:**
   Toàn bộ UI Web sẽ được thay thế bằng giao diện SwiftUI nguyên bản, tận dụng Swift Charts, SwiftData (cache offline) và Keychain Services.
