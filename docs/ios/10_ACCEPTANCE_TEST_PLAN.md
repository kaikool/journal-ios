# KẾ HOẠCH VÀ BẢNG KIỂM THỬ NGHIỆM THU (ACCEPTANCE TEST PLAN)
**Dự án:** Trade Journal — Native iOS + Supabase  
**Mục tiêu:** Định nghĩa danh sách kịch bản kiểm thử cụ thể (Test Cases) để nghiệm thu từng phân hệ.

---

## 1. PHÂN HỆ XÁC THỰC VÀ BẢO MẬT (AUTH & RLS)

| Mã Test Case | Tên Kịch bản | Dữ liệu đầu vào (Input) | Kết quả kỳ vọng (Expected Output) | Trạng thái |
|---|---|---|---|---|
| **TC-AUTH-01** | Đăng ký & Đăng nhập thành công | Email hợp lệ, Mật khẩu $\ge 8$ ký tự | Nhận JWT Session, lưu token an toàn vào Keychain, chuyển vào Dashboard | Chưa thực thi (Chờ Iter 02) |
| **TC-AUTH-02** | Khôi phục phiên khi mở lại app | Đóng app và mở lại sau 1 giờ | App tự động làm mới session qua refresh token, không yêu cầu login lại | Chưa thực thi (Chờ Iter 02) |
| **TC-AUTH-03** | Cách ly dữ liệu người dùng (RLS) | User A truy vấn danh sách `accounts` của User B qua PostgREST | Kết quả trả về danh sách rỗng `[]`, không có dữ liệu rò rỉ | Chưa thực thi (Chờ Iter 02) |
| **TC-AUTH-04** | Kiểm tra lộ lọt Secrets | Quét toàn bộ mã nguồn Swift và App Binary | Không chứa bất kỳ API key OpenAI/Anthropic hay Supabase Service Key nào | Chưa thực thi (Chờ Iter 02) |

---

## 2. PHÂN HỆ TÁI DỰNG TRADE VÀ TÍNH TOÁN TÀI CHÍNH (CORE & FINANCIAL ENGINE)

| Mã Test Case | Tên Kịch bản | Dữ liệu đầu vào (Input) | Kết quả kỳ vọng (Expected Output) | Trạng thái |
|---|---|---|---|---|
| **TC-CORE-01** | Chu kỳ Long đơn giản (Flat to Flat) | Buy 100 @ 10 (fee 1), Sell 100 @ 12 (fee 1) | Direction: Long, Status: Win, Gross P&L: 200, Fees: 2, Net P&L: 198, AvgEntry: 10, AvgExit: 12 | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-CORE-02** | Chu kỳ Short đơn giản | Sell 10,000 @ 1.10, Buy 10,000 @ 1.09 | Direction: Short, Status: Win, Net P&L: 100, Status: Win | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-CORE-03** | Lệnh đảo chiều vị thế (Crossing Flat) | Buy 2 @ 5000, Sell 6 @ 5010 (fee 3), Buy 4 @ 5005 | Sinh 2 trades: Long (Gross 20, Fee 1) và Short (Gross 20, Fee 2) | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-CORE-04** | Tính bất biến P&L qua FIFO, LIFO, WAVG | 2 lần mua, 2 lần bán một phần | Tổng Net P&L của 3 phương pháp là giống hệt nhau (sai số $\le 10^{-6}$) | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-CORE-05** | Tính toán Max Drawdown & Win Rate | Tập 4 trades mẫu (2 thắng, 2 thua) | Win Rate: 50%, Expectancy: 12.5, Drawdown khớp chính xác theo công thức | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-CORE-06** | Tính điểm Edge Score v2 | Trade metrics mẫu | Score (0 - 100) khớp chính xác với kết quả hàm `computeEdgeScore` gốc | **ĐÃ THỰC THI (PASS 100%)** |

---

## 3. PHÂN HỆ NHẬP DỮ LIỆU SAO KÊ (IMPORT PIPELINE)

| Mã Test Case | Tên Kịch bản | Dữ liệu đầu vào (Input) | Kết quả kỳ vọng (Expected Output) | Trạng thái |
|---|---|---|---|---|
| **TC-IMP-01** | Nhận diện tự động 13 định dạng sàn | File sao kê MetaTrader, IBKR, NinjaTrader | Engine nhận diện chính xác định dạng tương ứng | **MIỄN THỰC THI (Theo yêu cầu người dùng)** |
| **TC-IMP-02** | Xem trước và cảnh báo lỗi (Preview) | File CSV chứa dòng thiếu giá, dòng sai ngày | Hiển thị Preview: báo rõ dòng bị lỗi, cho phép bỏ qua hoặc sửa | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-IMP-03** | Chống nhân đôi khi nhập lặp lại | Nhập cùng 1 file sao kê lần thứ 2 | Số lượng inserted = 0, duplicates = N, không tăng số lượng executions | **ĐÃ THỰC THI (PASS 100%)** |
| **TC-IMP-04** | Tự động cập nhật Trades sau Import | Nạp thành công executions mới | Bảng `trades` tự động rebuild và cập nhật các chu kỳ tương ứng | **ĐÃ THỰC THI (PASS 100%)** |

---

## 4. PHÂN HỆ ĐỒNG BỘ ĐA THIẾT BỊ VÀ OFFLINE (SYNC & RESILIENCE)

| Mã Test Case | Tên Kịch bản | Dữ liệu đầu vào (Input) | Kết quả kỳ vọng (Expected Output) | Trạng thái |
|---|---|---|---|---|
| **TC-SYNC-01** | Thao tác ghi ngoại tuyến | Bật Airplane Mode, thêm ghi chú nhật ký | Ghi chú được lưu vào SwiftData, gắn cờ `pending_sync` | Chưa thực thi (Chờ Iter 04) |
| **TC-SYNC-02** | Tự động đồng bộ khi khôi phục mạng | Tắt Airplane Mode | Hàng đợi tự động gửi request lên Supabase, chuyển trạng thái `synced` | Chưa thực thi (Chờ Iter 04) |
| **TC-SYNC-03** | Đồng bộ đa thiết bị | Thiết bị A sửa tag của Trade X | Thiết bị B kéo làm mới (Pull-to-refresh) thấy tag mới của Trade X | Chưa thực thi (Chờ Iter 04) |
| **TC-SYNC-04** | Giải quyết xung đột ghi chú (Fork copy) | Hai thiết bị cùng sửa 1 note khi offline | Không bị ghi đè mất chữ; bản ghi cũ lưu thành `[Xung đột] Tên ghi chú` | Chưa thực thi (Chờ Iter 04) |

---

## 5. PHÂN HỆ SỔ CÁI QUỸ VÀ AI REFLECTION (PROP FIRM & AI)

| Mã Test Case | Tên Kịch bản | Dữ liệu đầu vào (Input) | Kết quả kỳ vọng (Expected Output) | Trạng thái |
|---|---|---|---|---|
| **TC-PROP-01** | Ghi nhận chi phí và yêu cầu rút tiền | Mua gói 150 USD, Yêu cầu rút 1,000 USD (90% split) | Net Spend: 150 USD, Expected Net Payout: 900 USD, Outstanding: 900 USD | Chưa thực thi (Chờ Iter 08) |
| **TC-PROP-02** | Ghi nhận thực nhận tiền mặt (Receipts) | Nhận đợt 1: 400 USD, đợt 2: 500 USD | Outstanding chuyển về 0 USD, Net Cash: +750 USD, ROI: 500% | Chưa thực thi (Chờ Iter 08) |
| **TC-AI-01** | Hỏi đáp AI (Ask your Journal) | Gửi câu hỏi "Phiên nào tôi trade hiệu quả nhất?" | Edge function gọi AI với context rút gọn, trả về câu trả lời có trích dẫn số liệu | Chưa thực thi (Chờ Iter 08) |
