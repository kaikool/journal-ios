# BẢNG QUẢN LÝ VÀ KIỂM SOÁT RỦI RO (RISK REGISTER)
**Dự án:** Trade Journal — Native iOS + Supabase  
**Phân loại:** Đánh giá mức độ ảnh hưởng (Impact) và Xác suất (Probability)

---

## 1. BẢNG MA TRẬN RỦI RO KỸ THUẬT

| Mã | Rủi ro nhận diện | Xác suất | Tác động | Mức độ rủi ro | Chiến lược kiểm soát & Giảm thiểu |
|---|---|---|---|---|---|
| **RSK-01** | **Sai lệch logic dựng lại Trade** | Trung bình | Rất cao | **NGHIÊM TRỌNG** | Thực hiện Differential Testing đối chiếu 1:1 giữa Swift Engine và logic gốc TypeScript trên cùng một tập fixtures. Dùng `Decimal` chống sai số nhị phân. |
| **RSK-02** | **Dữ liệu bị nhân đôi khi Import hoặc Retry** | Cao | Cao | **CAO** | Sử dụng mã băm `content_hash` (SHA-256) và thiết lập ràng buộc duy nhất `UNIQUE (user_id, account_id, content_hash)` trên PostgreSQL. Áp dụng idempotency key cho mọi thao tác ghi. |
| **RSK-03** | **Đồng bộ sai lệch giữa nhiều thiết bị** | Trung bình | Cao | **CAO** | Xây dựng hàng đợi `PendingQueue` có thứ tự FIFO, phân biệt rõ chính sách LWW cho ghi chú và tính toán lại cho dữ liệu dẫn xuất. Lưu bản sao xung đột khi cần. |
| **RSK-04** | **Cấu hình RLS sai gây rò rỉ dữ liệu chéo** | Thấp | Rất cao | **NGHIÊM TRỌNG** | Bắt buộc thêm `user_id` vào 100% bảng. Viết bộ Integration Test tự động với 2 tài khoản User A và User B kiểm tra các quyền SELECT, INSERT, UPDATE, DELETE và Storage. |
| **RSK-05** | **Giới hạn chạy nền của iOS đối với Broker Sync** | Rất cao | Trung bình | **TRUNG BÌNH** | Không tuyên bố hỗ trợ đồng bộ tự động 24/7 trên iPhone. Hướng dẫn người dùng đồng bộ On-demand khi mở ứng dụng, hoặc dùng Supabase pg_cron + Edge Function nếu broker hỗ trợ API không cần IP cố định. |
| **RSK-06** | **Edge Functions vượt giới hạn thời gian (Timeout)** | Thấp | Trung bình | **THẤP** | Chia nhỏ batch dữ liệu khi xử lý AI hoặc đồng bộ ngoài, giới hạn tối đa 500 records mỗi đợt. Lưu checkpoint để tiếp tục khi bị ngắt. |
| **RSK-07** | **Chi phí dịch vụ AI gia tăng ngoài dự kiến** | Trung bình | Trung bình | **TRUNG BÌNH** | Tối thiểu hóa context gửi tới AI: chỉ gửi các số liệu thống kê rút gọn (Aggregates), không gửi raw executions. Cho phép người dùng nhập API key cá nhân của họ. |
| **RSK-08** | **Thiếu dữ liệu nến cho tính năng Replay** | Trung bình | Thấp | **THẤP** | Tuân thủ nguyên tắc R009 & R010: Không tự bịa đặt giá giả lập. Khi thiếu nến từ file CSV hoặc API, hiển thị thông báo rõ ràng "Chưa có dữ liệu nến cho khoảng thời gian này". |
| **RSK-09** | **Môi trường phát triển hiện tại trên Windows** | Cao | Trung bình | **TRUNG BÌNH** | Toàn bộ mã nguồn Swift, kiến trúc, data model, migration SQL và test fixtures được viết chuẩn theo chuẩn SPM/Xcode. Biên dịch và đóng gói `.ipa` cuối cùng được thực hiện trên macOS / Xcode / CI Runner. |

---

## 2. QUY TRÌNH ỨNG PHÓ KHI XẢY RA SỰ CỐ DỮ LIỆU

1. **Khi phát hiện sai lệch số liệu P&L hoặc Trade:**
   - Sử dụng lệnh `rebuildAccount` để tính toán lại toàn bộ bảng `trades` trực tiếp từ dữ liệu gốc `executions`.
   - Vì bảng `trades` là dạng materialized từ các `executions`, việc rebuild đảm bảo dữ liệu luôn có thể phục hồi về trạng thái đúng đắn 100%.

2. **Khi phát hiện xung đột dữ liệu cục bộ:**
   - Dữ liệu chưa đồng bộ được giữ an toàn trong SwiftData. Người dùng có thể xem lại bản nháp và chủ động quyết định ghi đè hoặc lưu thành bản ghi mới.
