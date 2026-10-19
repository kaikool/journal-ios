# HƯỚNG DẪN TỰ ĐỘNG BUILD FILE .IPA QUA GITHUB ACTIONS

Tài liệu này hướng dẫn cách sử dụng workflow tự động hóa để build file cài đặt **`.ipa`** cho iOS mỗi khi bạn push code lên GitHub.

---

## 1. CẤU TRÚC WORKFLOW VỪA THIẾT LẬP

1. **File cấu hình workflow:** [`.github/workflows/build-ipa.yml`](../../.github/workflows/build-ipa.yml)
2. **File khởi tạo dự án Xcode:** [`project.yml`](../../project.yml) (dùng `xcodegen` tự động tạo `TradeJournal.xcodeproj` chuẩn native)
3. **Môi trường chạy:** `macos-14` (Apple Silicon M1/M2) được trang bị Xcode 15/16 và Swift 5.10+.
4. **Quy trình thực thi:**
   - Kiểm tra mã nguồn (Checkout).
   - Chạy toàn bộ bộ test tự động (`swift test` - 5 test suite).
   - Tự động sinh `TradeJournal.xcodeproj` qua `xcodegen`.
   - Build bản phát hành Release Archive (`xcodebuild archive`).
   - Đóng gói file `.app` vào thư mục `Payload/` và nén thành `TradeJournal.ipa`.
   - Xuất mã kiểm tra toàn vẹn SHA-256.
   - Tải file `.ipa` lên mục **Artifacts** của GitHub Actions (lưu trữ 14 ngày).
   - Tự động tạo **GitHub Release** đính kèm `.ipa` nếu bạn gắn tag phiên bản (ví dụ: `v1.0.0`).

---

## 2. CÁCH KÍCH HOẠT BUILD TRÊN GITHUB

### Cách 1: Tự động kích hoạt khi Push code
Mỗi khi bạn commit và push lên nhánh `main` hoặc `master`:
```bash
git add .
git commit -m "feat: cập nhật tính năng mới"
git push origin main
```
GitHub Actions sẽ tự động phát hiện và tiến hành build file `.ipa` ngay lập tức.

---

### Cách 2: Kích hoạt thủ công qua giao diện GitHub (Manual Trigger)
Nếu bạn chưa muốn push code mới nhưng muốn build lại file `.ipa`:
1. Mở trang repository của bạn trên GitHub.
2. Nhấn vào tab **Actions** ở menu phía trên.
3. Ở danh sách bên trái, chọn workflow **"Build & Package iOS IPA"**.
4. Nhấn nút **Run workflow** (nút màu xanh ở góc phải).
5. Chọn nhánh (branch) và cấu hình (`Release`), sau đó nhấn nút **Run workflow**.

---

### Cách 3: Kích hoạt tạo Bản Phát Hành (GitHub Release) tự động
Khi bạn muốn phát hành một phiên bản chính thức:
```bash
git tag v1.0.0
git push origin v1.0.0
```
Workflow sẽ build file `.ipa` và tự động tạo một trang **Release v1.0.0** trên GitHub chứa sẵn file `TradeJournal.ipa` để tải về bất cứ lúc nào!

---

## 3. CÁCH TẢI VỀ FILE .IPA SAU KHI BUILD THÀNH CÔNG

1. Vào tab **Actions** trên GitHub.
2. Chọn lượt chạy workflow mới nhất vừa hoàn thành (có dấu tích xanh ✅).
3. Cuộn xuống cuối trang đến mục **Artifacts**.
4. Nhấn vào **`TradeJournal-iOS-IPA`** để tải về file nén `.zip`.
5. Giải nén file `.zip`, bạn sẽ nhận được file **`TradeJournal.ipa`** và file checksum `TradeJournal.ipa.sha256`.

---

## 4. CÁCH CÀI ĐẶT FILE .IPA LÊN IPHONE (KHÔNG CẦN JAILBREAK)

File `.ipa` xuất ra đã sẵn sàng để cài đặt trực tiếp lên iPhone thông qua các công cụ Sideload phổ biến nhất hiện nay:

### 1. Dùng Sideloadly (Khuyến nghị cho Windows & Mac)
- Tải phần mềm miễn phí tại: https://sideloadly.io
- Cắm iPhone vào máy tính qua cáp USB.
- Kéo thả file `TradeJournal.ipa` vào Sideloadly.
- Nhập tài khoản Apple ID của bạn (miễn phí) và nhấn **Start**.
- Ứng dụng sẽ được cài trực tiếp vào màn hình chính iPhone.
- Trên iPhone: Vào **Cài đặt > Cài đặt chung > Quản lý VPN & Thiết bị** > Nhấn **Tin cậy** chứng chỉ Apple ID của bạn.

### 2. Dùng AltStore
- Cài đặt AltServer trên máy tính và AltStore trên iPhone.
- Mở AltStore trên iPhone, nhấn dấu **+** ở góc trái trên và chọn file `TradeJournal.ipa` vừa tải về.

### 3. Dùng TrollStore (Nếu thiết bị hỗ trợ iOS 14.0 - 16.6.1 / 17.0)
- Mở file `TradeJournal.ipa` trực tiếp bằng ứng dụng TrollStore trên iPhone để cài đặt vĩnh viễn không cần ký lại sau 7 ngày.
