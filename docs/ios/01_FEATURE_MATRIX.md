# MA TRẬN TÍNH NĂNG CHI TIẾT (FEATURE MATRIX)
**Dự án:** Trade Journal — iOS Native + Supabase  
**Mục tiêu:** Phân loại toàn bộ tính năng từ source web sang kiến trúc iOS Native, xác định trạng thái thực tế và chiến lược port.

---

## 1. BẢNG TỔNG HỢP PHÂN LOẠI TÍNH NĂNG

| Mã | Tính năng | Vị trí source gốc | Trạng thái gốc | Entity liên quan | Vị trí xử lý đích | Chiến lược Porting iOS |
|---|---|---|---|---|---|---|
| **F01** | **Xác thực người dùng (Auth)** | `apps/web/src/middleware.ts`, `app/api/auth` | Implemented (Single-user password) | `auth.users` | Supabase Auth + iOS Keychain | Chuyển sang Supabase Auth (Email/Password, OAuth Apple/Google) |
| **F02** | **Quản lý tài khoản giao dịch** | `apps/web/src/app/settings`, `src/db/schema.pg.ts` | Implemented and tested | `accounts` | Supabase PostgreSQL + SwiftData | CRUD tài khoản, đồng bộ qua Supabase SDK với RLS |
| **F03** | **Tái dựng Trade (Round-trips)** | `packages/core/src/round-trips.ts` | Implemented and tested | `executions`, `trades` | Swift Domain Engine | Port 1:1 sang Swift, dùng `Decimal`, kiểm thử Differential Testing |
| **F04** | **Tính toán Metrics & Performance** | `packages/core/src/metrics.ts`, `equity.ts` | Implemented and tested | `trades` | Swift Domain Engine | Port 1:1 sang Swift; tính toán trên background thread |
| **F05** | **Edge Score v2** | `packages/core/src/edge-score.ts` | Implemented and tested | `trades`, `TradeMetrics` | Swift Domain Engine | Port 1:1 sang Swift, giữ nguyên 6 trọng số và ngưỡng pinned |
| **F06** | **Bộ lọc đa chiều & Phân tích R** | `packages/core/src/analysis.ts` | Implemented and tested | `trades`, `playbooks` | Swift Domain Engine | Lọc phía client hoặc kết hợp PostgREST query parameters |
| **F07** | **Nhập dữ liệu sao kê (Import Engine)** | `packages/importers/src/` | Implemented and tested | `executions`, `import_batches` | Swift Importers Engine | Đọc file trực tiếp trên iPhone qua `UIDocumentPicker`, preview, batch insert |
| **F08** | **Ghi nhận & Hash Execution chống trùng** | `apps/web/src/server/executions.ts`, `ids.ts` | Implemented and tested | `executions` | Swift + Supabase RPC | SHA-256 fingerprint, unique constraint `(account_id, content_hash)` |
| **F09** | **Nhật ký theo ngày (Journal Calendar)** | `apps/web/src/app/journal`, `calendar` | Implemented and tested | `journal_days` | Supabase PostgreSQL + SwiftData | Hiển thị lịch SwiftUI, hỗ trợ Markdown note, lưu draft offline |
| **F10** | **Notebook (Thư mục & Ghi chú)** | `apps/web/src/app/notebook`, `api/notes` | Implemented and tested | `folders`, `notes` | Supabase PostgreSQL + SwiftData | Quản lý folder dạng cây, liên kết ghi chú với `trade_key` hoặc `date` |
| **F11** | **Playbooks & Quy tắc giao dịch** | `apps/web/src/app/playbooks`, `api/playbooks` | Implemented and tested | `playbooks`, `trade_rule_checks` | Supabase PostgreSQL + SwiftData | Định nghĩa setup mẫu, checklist kiểm tra việc tuân thủ quy tắc |
| **F12** | **Kỷ luật & Thói quen (Progress Rules)** | `apps/web/src/app/progress` | Implemented and tested | `progress_rules`, `progress_checks` | Supabase PostgreSQL + SwiftData | Theo dõi checklist thói quen hàng ngày theo các thứ trong tuần |
| **F13** | **Giao dịch bỏ lỡ (Missed Trades)** | `apps/web/src/app/missed` | Implemented and tested | `missed_trades` | Supabase PostgreSQL + SwiftData | Nhật ký các cơ hội setup chuẩn nhưng bị bỏ lỡ hoặc không vào lệnh |
| **F14** | **Sổ cái tài chính Prop Firm (Ledger)** | `apps/web/src/app/prop-firms`, `lib/prop-firms.ts` | Implemented and tested | `prop_accounts`, `prop_entries`, `prop_receipts`, `prop_audit` | Supabase PostgreSQL + SwiftData | Quản lý tiền mặt, chi phí, hoàn tiền, yêu cầu rút thưởng, tính ROI |
| **F15** | **Tích hợp The5ers MCP** | `apps/web/src/server/the5ers/` | Implemented and tested | `accounts`, `prop_entries`, `prop_receipts` | Supabase Edge Function + Swift | OAuth flow với The5ers MCP, đồng bộ thông tin tài khoản và rút tiền |
| **F16** | **Đồng bộ sàn tự động (Broker Sync)** | `apps/web/src/server/sync.ts`, `@luxalgo/broker-sdk` | Implemented but limited on iOS | `accounts`, `executions` | Supabase Edge Function hoặc On-demand client | Client trigger sync theo nhu cầu; không duy trì cron nền 24/7 trên iPhone |
| **F17** | **Dữ liệu nến & Replay (Market Data)** | `apps/web/src/lib/market-data.ts`, `trade-replay.ts` | Implemented and tested | `market_csv_datasets`, Storage | Supabase Storage + Swift Charts | Tải CSV nến từ Supabase Storage, render nến native và chạy thanh trượt replay |
| **F18** | **Ước tính MAE/MFE (Excursions)** | `apps/web/src/lib/excursions.ts` | Implemented and tested | `trade_excursions` | Swift Domain Engine | Tính toán cục bộ sự biến động vốn bất lợi/thuận lợi tối đa |
| **F19** | **File đính kèm (Attachments)** | `apps/web/src/server/storage.ts` | Implemented and tested | `attachments`, Storage | Supabase Storage + Swift | Lưu ảnh chụp biểu đồ / file sao kê PDF vào private bucket với RLS |
| **F20** | **AI Reflection (Ask, Critique, Recap)** | `apps/web/src/app/api/ai/` | Implemented and tested | AI Services | Supabase Edge Functions | Edge Function gọi OpenAI/Anthropic, giữ kín API Key, trả kết quả về app |
| **F21** | **Cài đặt & Tùy chọn hiển thị** | `apps/web/src/app/settings` | Implemented and tested | `settings` | Supabase PostgreSQL + SwiftData | Múi giờ, chế độ riêng tư (ẩn số dư), đơn vị tiền tệ mặc định |

---

## 2. PHÂN LOẠI CHI TIẾT TỪNG PHÂN HỆ

### 2.1. Phân hệ Cốt lõi & Giao dịch (Core & Trading)
- **F03 — Trade Reconstruction (`round-trips.ts`):**
  - *Input:* Danh sách các bản ghi `Execution` (id, symbol, side, qty, price, fee, executedAt, importMetadata).
  - *Output:* Danh sách `RoundTrip` (key, status, openedAt, closedAt, grossPnl, fees, netPnl, avgEntry, avgExit, exits).
  - *Ràng buộc:* Deterministic sort (thời gian -> order -> id). Chia phần lệnh crossing qua flat. Phương pháp FIFO/LIFO/WAVG không làm thay đổi tổng P&L chu kỳ hoàn tất.
  - *Porting:* Port sang module Swift `TradeEngine`. Bộ test differential so sánh trực tiếp kết quả với bản gốc.

- **F04 — Performance Metrics (`metrics.ts`):**
  - *Chỉ số bắt buộc:* Win rate (wins/closed), Profit Factor (gross profit / gross loss, cờ vô cực nếu không có lệnh thua), Expectancy, Average Win/Loss, Max Drawdown & Max Drawdown %, Day Win Rate, Chuỗi thắng/thua liên tiếp (streaks), Thời gian giữ lệnh trung bình.
  - *Porting:* Triển khai trong Swift struct `TradeMetricsCalculator`. Sử dụng `Decimal` cho tiền tệ để tránh sai số `Double`.

### 2.2. Phân hệ Nhập sao kê (Import Pipeline)
- **F07 — Multi-format Importer:**
  - *Luồng thực thi trên iOS:*
    1. Người dùng chọn file `.csv` hoặc `.html` từ ứng dụng Files.
    2. Engine Swift nhận diện định dạng tự động (`detectFormat`).
    3. Phân tích nội dung, chuyển đổi sang mảng `ImportedExecution`.
    4. Hiển thị màn hình Preview: tổng số lệnh, lệnh hợp lệ, số lệnh bị trùng, cảnh báo và lỗi chi tiết.
    5. Xác nhận nạp: Gửi batch executions lên Supabase PostgreSQL qua RPC hoặc transaction có kiểm tra hash chống trùng.
    6. Tự động kích hoạt tính toán lại các `trades` tương ứng.

### 2.3. Phân hệ Sổ cái Quỹ (Prop Firm Tracker)
- **F14 — Prop Ledger:**
  - *Đặc điểm:* Toàn bộ giá trị tài chính lưu dạng số nguyên minor units (cents) như `amountMinor`, `feeMinor`, `renewalMinor` để loại bỏ hoàn toàn sai số dấu phẩy động.
  - *Nghiệp vụ:* Phân tách rõ ràng giữa "Yêu cầu rút tiền" (Requested payout - chưa phải tiền mặt) và "Thực nhận" (Receipts - tiền đã về tài khoản ngân hàng).
  - *Porting:* Port nguyên vẹn data model sang Supabase PostgreSQL và SwiftData.

### 2.4. Phân hệ Tích hợp Ngoại vi & Bảo mật
- **F15 & F16 — External Integrations:**
  - Cần chuyển các thao tác yêu cầu Secret Token / Webhook / OAuth Client Secret sang **Supabase Edge Functions** để bảo đảm quy tắc **R005 — Không làm lộ secrets** và tuân thủ giới hạn nền của iOS.
- **F20 — AI Features:**
  - Client gửi context giao dịch ẩn danh (không lộ PII) lên Supabase Edge Function. Edge Function sử dụng key lưu an toàn trong Supabase Vault để gọi Anthropic/OpenAI và trả kết quả về app.
