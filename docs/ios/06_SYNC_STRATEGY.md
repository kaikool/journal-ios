# CHIẾN LƯỢC ĐỒNG BỘ DỮ LIỆU VÀ XỬ LÝ OFFLINE (SYNC STRATEGY)
**Dự án:** Trade Journal — iOS Native  
**Nguồn dữ liệu chuẩn (Single Source of Truth):** Supabase PostgreSQL  
**Bộ nhớ cục bộ (Local Cache & Drafts):** SwiftData

---

## 1. NGUYÊN TẮC BẤT BIẾN VỀ DỮ LIỆU (DATA INVARIANTS)

1. **Supabase PostgreSQL là nguồn dữ liệu chân lý duy nhất (Authoritative Source of Truth):**
   Mọi trạng thái đồng bộ giữa các thiết bị (iPhone, iPad, Web) đều lấy PostgreSQL làm mốc đối chiếu.
2. **SwiftData trên iPhone là Local Cache và Hàng đợi tạm:**
   - Dùng để tải giao diện ngay lập tức khi mở app (Instant Launch).
   - Hỗ trợ xem lại lịch sử giao dịch và phân tích khi không có kết nối mạng (Offline Read).
   - Lưu trữ các bản nháp (drafts) và hàng đợi thao tác chờ gửi (Pending Operations Queue).
   - Local database không bao giờ tự ý ghi đè dữ liệu trên Supabase mà không kiểm tra phiên bản hoặc dấu thời gian.
3. **Chống nhân đôi dữ liệu (Zero Duplication):**
   Mọi thao tác ghi nhận `executions` và `import` phải có định danh ổn định (Idempotency Key).

---

## 2. CƠ CHẾ IDEMPOTENCY VÀ CHỐNG TRÙNG LẶP

### 2.1. Mã băm nội dung cho Executions (`content_hash`)
Mỗi lần khớp lệnh `Execution` được tính toán mã SHA-256 xác định từ các thuộc tính kinh tế cốt lõi:
```
content_hash = SHA256(symbol + "|" + side + "|" + quantity + "|" + price + "|" + executed_at)
```
Trên database PostgreSQL, ràng buộc duy nhất được thiết lập:
```sql
UNIQUE (user_id, account_id, content_hash)
```
Khi người dùng thử nhập lại cùng một file sao kê, hoặc khi mạng bị gián đoạn và app gửi lại (retry), câu lệnh `INSERT ... ON CONFLICT (user_id, account_id, content_hash) DO NOTHING` sẽ tự động bỏ qua các bản ghi đã tồn tại mà không tạo ra bản ghi trùng.

### 2.2. Khóa ổn định cho Trade (`trade.key`)
Khóa của `RoundTrip` được sinh theo công thức:
```
trade_key = "\(account_id)|\(symbol)|\(direction)|\(opened_at)"
```
Khi nạp lại executions hoặc tính toán lại, các thông tin ghi chú thủ công (`notes`, `tags`, `mistakes`, `stop_loss`, `rating`) được bảo toàn tuyệt đối bằng cách neo vào khóa ổn định này.

---

## 3. HÀNG ĐỢI THAO TÁC NGOẠI TUYẾN (PENDING QUEUE)

Khi thiết bị mất kết nối mạng hoặc mạng chập chờn, mọi thao tác tạo mới, sửa đổi hoặc xóa được ghi nhận vào bảng `PendingOperation` trong SwiftData:

```swift
struct PendingOperation: Codable {
    let id: UUID
    let entityType: String     // "note", "trade_annotation", "account", "prop_entry"
    let entityId: String
    let operationType: String  // "create", "update", "delete"
    let payloadJson: String
    let createdAt: Date
    var retryCount: Int
    var lastError: String?
}
```

### Quy trình giải phóng hàng đợi (Queue Flush):
1. **Phát hiện mạng khôi phục:** Lớp `NetworkMonitor` phát hiện kết nối Internet khả dụng.
2. **Thực thi tuần tự:** Hàng đợi được xử lý theo thứ tự FIFO (First-In, First-Out).
3. **Xử lý lỗi & Retry:**
   - Nếu thành công: Xóa thao tác khỏi hàng đợi.
   - Nếu lỗi tạm thời (Timeout, 5xx): Tạm dừng và thử lại với chiến lược Exponential Backoff (1s, 2s, 4s, tối đa 30s).
   - Nếu lỗi logic (4xx, xung đột dữ liệu): Giữ lại bản ghi, thông báo cho người dùng và ghi nhận vào nhật ký sự cố.

---

## 4. CHÍNH SÁCH GIẢI QUYẾT XUNG ĐỘT (CONFLICT RESOLUTION POLICIES)

Không áp dụng một quy tắc chung cho tất cả các loại dữ liệu:

| Loại thực thể | Chính sách xung đột | Lý do nghiệp vụ |
|---|---|---|
| **Executions (Fills)** | **Bất biến (Immutable & Append-Only)** | Các lần khớp lệnh là sự kiện lịch sử thực tế; chỉ thêm mới, không ghi đè. Trùng hash thì bỏ qua. |
| **Trades (Derived)** | **Remote Recomputed Authoritative** | Dữ liệu dẫn xuất được tái lập đồng nhất theo quy tắc toán học từ danh sách executions. |
| **Trade Annotations (Tags, Notes, StopLoss)** | **Last-Write-Wins (LWW)** | Dựa trên `reviewed_at` hoặc `updated_at` của thiết bị có mốc thời gian mới hơn. |
| **Ghi chú Nhật ký (Journal & Notes)** | **LWW kèm Tạo Bản sao xung đột (Fork Copy)** | Nếu 2 thiết bị cùng sửa nội dung một ghi chú khi offline, bản ghi mới hơn sẽ được áp dụng, đồng thời bản ghi còn lại được lưu thành `[Xung đột] Tên ghi chú` để tránh mất dữ liệu của người dùng. |
| **Sổ cái Quỹ (Prop Ledger)** | **Strict Invariant & Audit Log** | Mọi sửa đổi trên `prop_entries` bắt buộc phải kèm lý do (`reason`) và được lưu vết vào `prop_audit`. |

---

## 5. VÒNG ĐỜI ĐỒNG BỘ (SYNC LIFECYCLE)

1. **Khởi động ứng dụng (App Launch):**
   - Đọc dữ liệu từ SwiftData hiển thị tức thì lên màn hình.
   - Kiểm tra phiên đăng nhập và kết nối mạng.
   - Gửi yêu cầu đồng bộ tăng dần: `SELECT * FROM ... WHERE updated_at > :last_sync_timestamp`.
2. **Quay lại màn hình chính (App Foreground):**
   - Nếu khoảng thời gian từ lần đồng bộ trước vượt quá 60 giây, tự động kích hoạt kiểm tra cập nhật mới từ server.
3. **Thao tác kéo để làm mới (Pull-to-Refresh):**
   - Cho phép người dùng chủ động ép làm mới dữ liệu trên bất kỳ màn hình nào.
4. **Phân trang dữ liệu (Pagination):**
   - Đối với tài khoản có hàng chục nghìn executions, việc tải dữ liệu được chia thành các batch 500 bản ghi để bảo đảm bộ nhớ RAM trên iPhone không bị quá tải.
