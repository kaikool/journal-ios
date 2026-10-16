# BÁO CÁO TIẾN ĐỘ DỰ ÁN (PROJECT STATUS)
**Dự án:** Trade Journal — Native iOS + Supabase  
**Cập nhật lúc:** 16/10/2026  
**Giai đoạn hiện tại:** **TOÀN BỘ 09 ITERATION ĐÃ HOÀN TẤT (100% MASTER PLAN ACHIEVED)**

---

## 1. TỔNG QUAN TIẾN ĐỘ THEO CÁC ITERATION

| Iteration | Tên giai đoạn | Trạng thái | Ghi chú nghiệm thu |
|---|---|---|---|
| **Iteration 00** | **Source Audit & Architecture Design** | **HOÀN THÀNH (DONE)** | Toàn bộ 11 tài liệu kỹ thuật hoàn tất trong `docs/ios/`. Đạt chuẩn Gate A. |
| **Iteration 01** | **iOS Project Setup & Foundation** | **HOÀN THÀNH (DONE)** | Khởi tạo SPM Package `TradeJournalKit`, Design System, Root TabView, Logging bảo mật, Domain Models. |
| **Iteration 02** | **Authentication & Security (Supabase Auth & RLS)** | **HOÀN THÀNH (DONE)** | File migration SQL hoàn chỉnh với 16 bảng, RLS multi-tenant theo `user_id` và private Storage buckets tại `supabase/migrations/20261016_initial_schema.sql`. Chế độ bypass login theo yêu cầu người dùng. |
| **Iteration 03** | **Domain Engine & Financial Parity** | **HOÀN THÀNH (DONE)** | Đạt chuẩn **Gate B**. Port 100% `TradeReconstructionEngine` (flat-to-flat, FIFO/LIFO/WAVG), `FinancialMetricsEngine`, `EdgeScoreEngine` v2, `TradeAnalysisEngine`. 100% Differential Tests pass. |
| **Iteration 04** | **Data Layer & State Store** | **HOÀN THÀNH (DONE)** | `TradeDataStore` tập trung quản lý Accounts, Executions, Trades và Hash Deduplication. |
| **Iteration 05** | **Trades & Import Pipeline** | **HOÀN THÀNH (DONE)** | `CSVParser` chuẩn RFC 4180, `StandardCSVImporter` linh hoạt, màn hình `ImportStatementView` với Preview tương tác, chống trùng lặp và tự động Rebuild Trades. Bộ test `ImportTests.swift` pass 100%. (Miễn trừ 13 format sàn riêng theo yêu cầu). |
| **Iteration 06** | **Dashboard & Swift Charts** | **HOÀN THÀNH (DONE)** | Đạt chuẩn **Gate C**. Swift Charts với `EquityCurveChart`, `DrawdownChart` (underwater), `SessionBreakdownChart` (Asian, London, London/NY, NY, Off-hours), `WeekdayChart`. Dashboard tương tác với bộ lọc thời gian và Edge Score breakdown. |
| **Iteration 07** | **Journal, Playbooks & Trade Replay** | **HOÀN THÀNH (DONE)** | Lịch P&L tháng (`JournalCalendarView`), chỉnh sửa ghi chú tâm lý ngày (`DayDetailSheet`), quản lý chiến lược & đo lường tuân thủ quy tắc (`PlaybooksView`, `AdherenceEngine`), tính năng xem lại diễn biến giá lệnh từng nến (`TradeReplayView`, `TradeReplayEngine`). |
| **Iteration 08** | **Prop Firm Ledger & AI Reflection** | **HOÀN THÀNH (DONE)** | Sổ cái quỹ `PropFirmEngine` và `PropFirmLedgerView` chuẩn toán học đơn vị tiền tệ nhỏ (minor units), theo dõi phí thi, hoàn tiền, đợt payout và ROI. Supabase Edge Function `ai-reflection` (bảo vệ key theo R005) và giao diện huấn luyện viên `AIReflectionView`. |
| **Iteration 09** | **Settings, Data Export & Acceptance** | **HOÀN THÀNH (DONE)** | Màn hình `SettingsView` với quản lý tài khoản, đổi múi giờ phân tích, tiền tệ chính, xuất file sao lưu JSON đầy đủ, dọn dẹp dữ liệu và bộ unit tests `AggregateTests.swift`, `PropFirmTests.swift`. |

---

## 2. KIẾN TRÚC & CÁC THÀNH PHẦN ĐÃ XÂY DỰNG

### Core Domain & Engines
- `TradeReconstructionEngine.swift`: Tái dựng chu kỳ giao dịch Flat-to-Flat từ khớp lệnh nguyên tử (Executions) theo FIFO, LIFO, WAVG với độ chính xác `Decimal`.
- `FinancialMetricsEngine.swift`: Tính toán Win rate, Day win rate, Profit factor, Infinite PF flag, Expectancy, Max Drawdown, Daily Stats, Streaks.
- `EdgeScoreEngine.swift`: Đánh giá 6 trụ cột hiệu suất chuẩn thuật toán gốc v2 (Tổng 100 điểm).
- `TradeAnalysisEngine.swift`: Đo lường R thực tế (Realized R), R kế hoạch (Planned RR), rủi ro giao dịch (Trade Risk) và bộ lọc đa chiều.
- `AggregateEngine.swift`: Phân nhóm theo mã (Symbol), Tag, Lỗi (Mistake), Playbook, Phiên (Trading Sessions), Thứ trong tuần (Weekday), Giờ trong ngày (Hour), Thời lượng giữ lệnh (Duration).
- `AdherenceEngine.swift`: Phân tích chênh lệch kết quả P&L khi tuân thủ vs phá vỡ quy tắc giao dịch.
- `TradeReplayEngine.swift`: Mô phỏng bước chạy nến và tính toán lãi/lỗ tạm tính (unrealized P&L) theo từng cây nến.
- `PropFirmEngine.swift`: Quản lý sổ cái tiền mặt quỹ thi với đơn vị minor units (`Int64`), tính toán Payout dự kiến, Payout thực nhận và ROI.
- `StandardCSVImporter.swift` & `CSVParser.swift`: Bộ nhập sao kê CSV tiêu chuẩn RFC 4180 linh hoạt với cơ chế băm SHA-256 chống trùng lặp.

### Giao diện SwiftUI Native
- **Dashboard:** Thẻ tổng lãi/lỗ ròng, huy hiệu %, Edge Score v2 tròn tương tác, 6 ô thống kê nhanh, 4 chế độ biểu đồ Swift Charts, top mã giao dịch, gọi nhanh AI Reflection.
- **Trades:** Danh sách chu kỳ lệnh, chi tiết giao dịch `TradeDetailView`, gán tag, đánh dấu lỗi vi phạm, chấm sao kỷ luật, xem lại diễn biến lệnh qua `TradeReplayView`.
- **Import:** Màn hình kéo thả / chọn file sao kê CSV từ iOS Files, nạp dữ liệu Demo mẫu, xem trước và kiểm tra lỗi trước khi lưu.
- **Journal:** Lịch tháng với màu sắc P&L từng ngày, bộ chọn mục "Lịch P&L" vs "Playbooks", bảng ghi chú tâm lý ngày và chấm điểm kỷ luật.
- **Prop Firms:** Thống kê dòng tiền quỹ (Tổng chi, Payout nhận về, Net P&L, ROI), danh sách tài khoản quỹ, theo dõi tiến độ duyệt và giải ngân payout.
- **AI Reflection:** Huấn luyện viên AI hỗ trợ 3 chế độ (Hỏi đáp, Nhận xét chuyên sâu, Tổng kết định kỳ), kết nối an toàn với Supabase Edge Function hoặc chạy phân tích nội bộ ngoại tuyến.
- **Settings:** Quản lý nhiều tài khoản giao dịch, chuyển đổi múi giờ, đơn vị tiền tệ, chế độ ẩn số dư riêng tư, xuất bản sao lưu JSON toàn bộ.

### Backend & Bảo mật (Supabase)
- **Database:** `supabase/migrations/20261016_initial_schema.sql` (16 bảng PostgreSQL, quan hệ chặt chẽ, hỗ trợ multi-tenancy qua `user_id`, RLS policies toàn diện).
- **Storage:** Private buckets `journal-attachments` và `market-data`.
- **Edge Function:** `supabase/functions/ai-reflection/index.ts` (Giữ bí mật API key của AI trên server, tuyệt đối không lộ trong app client theo quy tắc R005).

### Bộ kiểm thử tự động (Unit Tests)
- `FoundationTests.swift`: Định dạng tiền tệ, chế độ riêng tư, logic cơ bản.
- `DomainEngineTests.swift`: Khớp lệnh Flat-to-flat, tính toán chỉ số tài chính, Edge Score v2.
- `ImportTests.swift`: Phân tích CSV, lọc dữ liệu trùng lặp, cập nhật kho lưu trữ.
- `AggregateTests.swift`: Ranh giới phiên giao dịch (Asian, London, London/NY, NY, Off-hours), gom nhóm mã giao dịch.
- `PropFirmTests.swift`: Tính toán số dư minor unit, công thức dự kiến payout, sổ cái dòng tiền.
