# Trade Journal — Native iOS (Swift & SwiftUI)

> Ứng dụng Nhật ký Giao dịch (Trade Journal) Native iOS sử dụng **SwiftUI**, **Swift Charts**, **Swift Concurrency** và **Supabase** (PostgreSQL, RLS, Storage, Edge Functions).

![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)
![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg)
![Supabase](https://img.shields.io/badge/Backend-Supabase-green.svg)
![License MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)

---

## 🌟 Tính Năng Nổi Bật

- **Tái dựng Chu kỳ Lệnh (Flat-to-Flat):** Tính toán khớp lệnh chuẩn xác theo FIFO, LIFO, WAVG từ các lần khớp lệnh nguyên tử (Executions).
- **Độ chính xác tài chính tuyệt đối:** Sử dụng kiểu dữ liệu `Decimal` và `Int64` (minor units), bảo toàn toàn vẹn P&L, phí hoa hồng và khối lượng.
- **Biểu đồ Swift Charts Native:**
  - Đường cong vốn lũy kế (Cumulative Equity Curve) với gradient tương tác.
  - Biểu đồ sụt giảm vốn chìm dưới nước (Underwater Drawdown %).
  - Phân tích hiệu suất theo 5 phiên giao dịch chuẩn UTC (`Asian`, `London`, `London/NY Overlap`, `New York`, `Off-hours`).
  - Phân tích P&L và Win rate theo các ngày trong tuần.
- **Edge Score v2:** Đánh giá năng lực nhà giao dịch theo 6 trụ cột kỹ thuật (Tổng 100 điểm).
- **Nhật Ký & Tâm Lý Giao Dịch (Journal):** Lịch P&L tháng trực quan, ghi chú tâm lý (mindset), chấm điểm kỷ luật 1-5 sao.
- **Quản lý Chiến lược (Playbooks):** Tạo checklist quy tắc bắt buộc và đo lường sự chênh lệch P&L giữa việc tuân thủ vs vi phạm quy tắc.
- **Tua lại Diễn biến Lệnh (Trade Replay):** Xem lại diễn biến nến và lãi/lỗ tạm tính thả nổi tại từng thời điểm vào/ra lệnh.
- **Sổ Cái Quỹ (Prop Firm Ledger):** Quản lý tài khoản quỹ (Topstep, FTMO, The5ers...), theo dõi dòng tiền (phí thi, reset, payout) và tỷ suất ROI.
- **AI Trader Reflection:** Huấn luyện viên AI hỗ trợ Hỏi đáp, Nhận xét chuyên sâu và Tổng kết hiệu suất (bảo mật API key qua Supabase Edge Function).
- **Import Sao Kê CSV:** Bộ nạp sao kê CSV chuẩn RFC 4180 linh hoạt, cơ chế băm SHA-256 chống trùng lặp dữ liệu.
- **Chế độ Riêng tư (Privacy Mode):** Ẩn nhanh số dư và P&L khi xem tại nơi công cộng.
- **Sao lưu & Xuất dữ liệu:** Xuất bản sao lưu toàn bộ dữ liệu dạng JSON qua iOS ShareSheet.

---

## 🏗️ Cấu Trúc Dự Án

```
TradeJournal/
  ├── Sources/
  │   ├── App/                  # App environment, routing, RootTabView, @main entry
  │   ├── Core/
  │   │   ├── Domain/           # Models, Engines (Reconstruction, Metrics, EdgeScore, Aggregates, PropFirm)
  │   │   ├── Data/             # TradeDataStore (quản lý trạng thái client tập trung)
  │   │   ├── Networking/       # AIReflectionService (kết nối Supabase Edge Function)
  │   │   └── Utilities/        # Logger bảo mật, Error handling
  │   ├── DesignSystem/
  │   │   ├── Charts/           # Swift Charts (EquityCurve, Drawdown, Session, Weekday)
  │   │   ├── Components/       # Card, Badge, Button, EmptyState
  │   │   ├── Formatting/       # Tiền tệ, số thập phân, phần trăm, ngày giờ
  │   │   ├── Theme/            # Bảng màu ngữ nghĩa (profit, loss, accent...)
  │   │   └── Typography/       # Typography hỗ trợ monospace financial numbers
  │   └── Features/
  │       ├── Dashboard/        # Màn hình tổng quan, KPI cards, bộ lọc thời gian
  │       ├── Trades/           # Danh sách lệnh, chi tiết giao dịch, gán tag & lỗi
  │       ├── Import/           # Nhập file CSV, kiểm tra lỗi, chống trùng lặp
  │       ├── Journal/          # Lịch P&L tháng, ghi chú tâm lý ngày
  │       ├── Playbooks/        # Quản lý chiến lược và tỷ lệ tuân thủ quy tắc
  │       ├── TradeReplay/      # Tua lại diễn biến giá từng cây nến
  │       ├── PropFirm/         # Sổ cái quỹ, tài khoản và tiến độ payout
  │       ├── AIReflection/     # Giao diện phản hồi từ huấn luyện viên AI
  │       └── Settings/         # Quản lý tài khoản, đổi múi giờ, sao lưu JSON
  └── Tests/                    # Bộ kiểm thử tự động (Foundation, Domain, Import, Aggregate, PropFirm)
```

---

## 🚀 Tự Động Build File `.ipa` (GitHub Actions)

Mỗi lần push code lên nhánh `main`, GitHub Actions sẽ tự động:
1. Chạy toàn bộ bộ test kiểm thử tự động (`swift test`).
2. Sinh file `TradeJournal.xcodeproj` chuẩn native qua `xcodegen`.
3. Build bản Release và đóng gói thành file **`TradeJournal.ipa`**.
4. Xuất file cài đặt vào mục **Artifacts** trong tab **Actions** của repository để bạn tải về cài đặt trực tiếp lên iPhone (qua Sideloadly, AltStore hoặc TrollStore).

Chi tiết xem tại: [`docs/ios/BUILD_IPA_GUIDE.md`](docs/ios/BUILD_IPA_GUIDE.md).

---

## 🛠️ Chạy trên Xcode (macOS)

1. Mở thư mục dự án bằng Xcode (hoặc mở file `Package.swift`).
2. Hoặc sinh project Xcode:
   ```bash
   brew install xcodegen
   xcodegen generate
   open TradeJournal.xcodeproj
   ```
3. Chọn thiết bị đích (iOS Simulator hoặc iPhone kết nối qua cáp) chạy iOS 17.0+ và nhấn **Run (Cmd + R)**.

---

## 🗄️ Backend Supabase

File migration SQL hoàn chỉnh (16 bảng PostgreSQL, phân quyền RLS multi-tenant theo `user_id`, private buckets):
`supabase/migrations/20261016_initial_schema.sql`

Supabase Edge Function cho AI Reflection:
`supabase/functions/ai-reflection/index.ts`
