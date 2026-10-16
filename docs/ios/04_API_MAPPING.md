# BẢN ĐỒ ÁNH XẠ API SANG KIẾN TRÚC MỚI (API MAPPING)
**Dự án:** Trade Journal — Chuyển đổi từ Next.js Route Handlers sang iOS Native + Supabase

---

## 1. NGUYÊN TẮC PHÂN LOẠI API

Mọi API route cũ của ứng dụng Web được phân loại vào một trong 5 nhóm xử lý:
1. **Direct PostgREST (RLS):** Gọi trực tiếp từ iOS qua Supabase Swift SDK với Row Level Security.
2. **Local Swift Engine:** Xử lý hoàn toàn trên thiết bị (tính toán analytics, parse file import, export dữ liệu) giúp app chạy tức thì và hỗ trợ offline.
3. **Supabase RPC / Transaction:** Thủ tục lưu trữ PostgreSQL khi cần ghi nhiều bảng nguyên tử.
4. **Supabase Edge Function:** Xử lý server-side khi cần giữ bí mật API keys hoặc gọi dịch vụ ngoài.
5. **Redesign / Replaced:** Thay thế bằng cơ chế native của iOS.

---

## 2. BẢNG ÁNH XẠ CHI TIẾT TỪNG API ROUTE

| Route gốc (Next.js) | HTTP Method | Chức năng nghiệp vụ | Vị trí xử lý đích | Cơ chế triển khai trên iOS / Supabase |
|---|---|---|---|---|
| `/api/auth` | GET, POST, DELETE | Đăng nhập mật khẩu chung, kiểm tra session | **Supabase Auth** | Thay thế bằng `supabase.auth.signInWithPassword`, `signOut`, `session` |
| `/api/trades` | GET | Lấy danh sách trades có lọc và phân trang | **Direct PostgREST + Local** | Truy vấn bảng `trades` theo `account_id`, lọc cục bộ bằng Swift Engine |
| `/api/trades/[key]` | GET, POST, DELETE | Xem chi tiết, cập nhật ghi chú/tag, xóa trade | **Direct PostgREST** | Đọc/ghi bảng `trades` với RLS `auth.uid() = user_id` |
| `/api/trades/bulk` | POST | Cập nhật hàng loạt playbook, tag, xóa | **Direct PostgREST** | Batch update bảng `trades` qua PostgREST |
| `/api/trades/lookup` | GET | Tìm kiếm trade nhanh theo symbol/ngày | **Direct PostgREST** | PostgREST filter trên bảng `trades` |
| `/api/trades/[key]/rules` | GET, POST | Đọc & đánh giá tuân thủ quy tắc playbook | **Direct PostgREST** | Bảng `trade_rule_checks` |
| `/api/executions` | GET, POST | Lấy executions, thêm lệnh thủ công | **Direct PostgREST / RPC** | Đọc/ghi bảng `executions` với content hash chống trùng |
| `/api/import` | POST | Nhập file sao kê từ nhiều sàn/broker | **Local Swift + Supabase** | **Local Swift Engine** parse file CSV/HTML -> Xem trước (Preview) -> Batch insert vào `executions` |
| `/api/stats` | GET | Tính toán tổng quan win rate, profit factor, drawdown | **Local Swift Engine** | **Tính trực tiếp trên iPhone** bằng `computeMetrics` từ danh sách `trades` đã cache |
| `/api/analysis` | GET | Phân tích R-multiple, holding time, volume | **Local Swift Engine** | **Tính trực tiếp trên iPhone** bằng `packages/core/analysis.ts` đã port sang Swift |
| `/api/performance-trends` | GET | Xu hướng hiệu suất theo chu kỳ thời gian | **Local Swift Engine** | Swift computation trên background thread |
| `/api/calendar` | GET | Lịch giao dịch P&L theo ngày/tháng | **Local Swift Engine** | Tính từ `dailyStats` trên danh sách trades |
| `/api/journal` | GET | Lấy ghi chú nhật ký các ngày | **Direct PostgREST** | Bảng `journal_days` |
| `/api/journal/[date]` | GET, POST | Đọc/sửa ghi chú ngày cụ thể | **Direct PostgREST** | Bảng `journal_days` (hỗ trợ offline lưu draft vào SwiftData) |
| `/api/folders` | GET, POST | Quản lý thư mục notebook | **Direct PostgREST** | Bảng `folders` |
| `/api/folders/[id]` | DELETE | Xóa thư mục | **Direct PostgREST** | Bảng `folders` (cascade hoặc soft-delete) |
| `/api/notes` | GET, POST | Quản lý danh sách ghi chú | **Direct PostgREST** | Bảng `notes` |
| `/api/notes/[id]` | GET, PUT, DELETE | Đọc, cập nhật, xóa note markdown | **Direct PostgREST** | Bảng `notes` (hỗ trợ offline draft) |
| `/api/playbooks` | GET, POST | Danh sách chiến lược playbook | **Direct PostgREST** | Bảng `playbooks` |
| `/api/playbooks/[id]` | GET, PUT, DELETE | Chi tiết, sửa, xóa playbook | **Direct PostgREST** | Bảng `playbooks` |
| `/api/prop-firms` | GET, POST | Sổ cái tài khoản quỹ, chi phí, payout | **Direct PostgREST + Local** | Bảng `prop_accounts`, `prop_entries`, `prop_receipts`. Tính toán cash metrics bằng Swift |
| `/api/prop-firms/csv` | POST | Nhập/xuất sổ cái tiền mặt prop firm | **Local Swift + Supabase** | Parse CSV cục bộ trên iPhone, commit transaction lên Supabase |
| `/api/attachments` | POST | Tải lên file ảnh chụp màn hình biểu đồ | **Supabase Storage** | Upload trực tiếp lên Supabase Storage bucket `journal-attachments` |
| `/api/attachments/[id]` | GET, DELETE | Tải/xóa file đính kèm | **Supabase Storage** | Storage download / delete với policy kiểm tra sở hữu |
| `/api/market-data/connections` | GET, POST | Cấu hình nhà cung cấp dữ liệu nến LSE | **Supabase Edge Function** | Edge function lưu credential bảo mật hoặc cấu hình người dùng |
| `/api/market-data/csv` | POST | Tải lên bộ nến lịch sử CSV | **Supabase Storage + Local** | Lưu CSV vào bucket `market-data`, parse và render trên client |
| `/api/trades/[key]/market-data` | GET | Lấy nến thị trường cho trade detail | **Supabase Storage + Local** | Đọc nến từ Storage, Swift Engine tính MAE/MFE (`excursions.ts`) |
| `/api/ai/ask` | POST | Hỏi đáp tự nhiên dựa trên lịch sử journal | **Supabase Edge Function** | `ai-reflection` Edge Function gọi Anthropic/OpenAI với secret key |
| `/api/ai/critique` | POST | Đánh giá, phê bình trade | **Supabase Edge Function** | `ai-reflection` Edge Function |
| `/api/ai/recap` | POST | Tổng kết ngày giao dịch | **Supabase Edge Function** | `ai-reflection` Edge Function |
| `/api/the5ers` | GET, POST | OAuth và đồng bộ The5ers MCP | **Supabase Edge / Swift** | Đăng nhập OAuth qua `ASWebAuthenticationSession`, lưu token Keychain |
| `/api/cron/broker-sync` | GET | Cron job đồng bộ sàn | **Redesign / On-demand** | Người dùng bấm refresh trên app hoặc dùng pg_cron + Edge Function |
| `/api/export` | GET | Xuất toàn bộ journal ra CSV/JSON | **Local Swift Engine** | Xuất trực tiếp trên iPhone qua `ShareSheet` |
| `/api/settings` | GET, POST | Cài đặt người dùng (múi giờ, tiền tệ) | **Direct PostgREST** | Bảng `settings` với RLS |

---

## 3. LỢI ĐIỂM KIẾN TRÚC MỚI

1. **Hiệu năng vượt trội (Zero Latency Analytics):**  
   Trong bản Web, mỗi lần thay đổi bộ lọc, trình duyệt phải gửi HTTP request tới `/api/stats`, `/api/analysis`. Trên iOS, toàn bộ dữ liệu trades được cache trong SwiftData và được tính toán ngay lập tức trên máy bằng Swift Engine với tốc độ milli-giây.

2. **Hoạt động Offline hoàn hảo:**  
   Người dùng có thể xem lại lịch sử lệnh, phân tích biểu đồ, ghi chú nhật ký ngay cả khi đang trên máy bay hoặc mất mạng. Khi có mạng trở lại, các thao tác tạo mới/sửa đổi sẽ được đẩy lên Supabase thông qua hàng đợi đồng bộ (Sync Queue).

3. **Bảo mật tuyệt đối (Zero Secret Leakage):**  
   Không có bất kỳ API Key của OpenAI, Anthropic hay Service Role Key nào xuất hiện trong mã nguồn iOS. Mọi yêu cầu nhạy cảm đều được ủy quyền qua Supabase Edge Functions.
