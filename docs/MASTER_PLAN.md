\# MASTER IMPLEMENTATION PLAN

\# TRADE JOURNAL — NATIVE iOS + SUPABASE



\*\*Repository nguồn:\*\* https://github.com/kaikool/trade-journal



\*\*Mục tiêu:\*\* Chuyển đổi dự án Trade Journal hiện có thành ứng dụng iOS native thực sự bằng Swift và SwiftUI, giữ nguyên nghiệp vụ gốc, sử dụng Supabase làm nền tảng backend duy nhất và hỗ trợ đồng bộ dữ liệu giữa các thiết bị đăng nhập cùng tài khoản.



\*\*Phạm vi hạ tầng bắt buộc:\*\*

\- Không yêu cầu VPS riêng.

\- Không yêu cầu Vercel.

\- Không tự dựng backend độc lập.

\- Không sử dụng cơ sở dữ liệu máy chủ thứ hai.

\- Sử dụng Supabase Auth, PostgreSQL, Storage và các dịch vụ Supabase cần thiết.

\- Supabase Edge Functions chỉ được sử dụng khi có lý do kỹ thuật rõ ràng.



\*\*Nguyên tắc triển khai:\*\* Audit source trước, thiết kế kiến trúc sau, triển khai theo từng iteration nhỏ, kiểm chứng nghiệp vụ bằng test, chỉ hoàn thành khi có bằng chứng nghiệm thu.



\---



\# PHẦN I — MỤC TIÊU VÀ NGUYÊN TẮC BẤT BIẾN



\## 1.1. Mục tiêu cuối cùng



Xây dựng một ứng dụng iOS có thể sử dụng độc lập trên iPhone, với các đặc điểm:



1\. Giao diện native sử dụng SwiftUI, không phải website được bọc trong WebView.

2\. Các chức năng được chuyển đổi từ dự án gốc phải giữ nguyên ý nghĩa nghiệp vụ và kết quả tính toán.

3\. Supabase PostgreSQL là nguồn dữ liệu dùng chung giữa các thiết bị.

4\. Người dùng có thể đăng nhập, xem dữ liệu đã đồng bộ, cập nhật dữ liệu và tiếp tục làm việc trong phạm vi offline được hỗ trợ.

5\. Dữ liệu giao dịch không bị nhân đôi, mất hoặc tính sai khi import, retry, đồng bộ hay cập nhật.

6\. Mọi tính năng được phân loại rõ ràng: đã triển khai, đang triển khai, bị giới hạn, cần thay đổi hoặc chưa có trong source.

7\. Có bộ kiểm thử đủ khả năng phát hiện sai lệch giữa ứng dụng gốc và ứng dụng iOS.

8\. Có tài liệu kỹ thuật để tiếp tục bảo trì, sửa lỗi và mở rộng về sau.



\## 1.2. Các nguyên tắc bắt buộc



\*\*R001 — Không tự ý bỏ chức năng\*\*



Không được loại bỏ tính năng chỉ vì khó port hoặc vì không phù hợp với kiến trúc ban đầu. Nếu không thể giữ nguyên, phải ghi rõ lý do, tác động và phương án thay thế.



\*\*R002 — Không tự phát minh nghiệp vụ\*\*



Mọi quy tắc tính toán phải được truy nguyên từ source code, test, schema hoặc tài liệu đáng tin cậy của dự án. Khi chưa xác định được, đánh dấu là chưa rõ và tiếp tục điều tra.



\*\*R003 — Không làm sai dữ liệu tài chính\*\*



Các phép tính P\&L, commission, trade reconstruction, win rate, MAE, MFE và những chỉ số khác phải tuân theo định nghĩa của dự án gốc.



\*\*R004 — Không mất hoặc nhân đôi dữ liệu\*\*



Các thao tác import, retry, đồng bộ và xử lý lỗi phải có cơ chế chống ghi trùng và phát hiện dữ liệu không nhất quán.



\*\*R005 — Không làm lộ secrets\*\*



Không nhúng service-role key, secret key của nhà cung cấp AI, broker hoặc các khóa có quyền đặc biệt vào mã nguồn hay binary của ứng dụng iOS.



\*\*R006 — Không tạo hạ tầng ngoài phạm vi\*\*



Không tự thêm VPS, Vercel, backend riêng, database riêng hoặc dịch vụ tính phí mới nếu chưa có phê duyệt.



\*\*R007 — Không coi biên dịch thành công là hoàn thành\*\*



Một tính năng chỉ được coi là hoàn tất khi đã đáp ứng tiêu chí nghiệm thu và có kết quả kiểm thử phù hợp.



\*\*R008 — Không tạo artifact rác\*\*



Không xuất hàng loạt CSV, JSON, log hoặc Markdown không cần thiết. Tài liệu phải có mục đích rõ ràng, được cập nhật theo từng iteration.



\*\*R009 — Không đánh tráo tính năng\*\*



Không sử dụng dữ liệu giả, kết quả hardcode hoặc giao diện mô phỏng để tuyên bố tính năng đã được triển khai thực sự.



\*\*R010 — Không che giấu giới hạn\*\*



Nếu một tính năng phụ thuộc tác vụ chạy nền, webhook, API bên ngoài hoặc xử lý phía máy chủ, phải xác định giới hạn thực tế trong kiến trúc iPhone + Supabase.



\---



\# PHẦN II — KIẾN TRÚC MỤC TIÊU



\## 2.1. Kiến trúc tổng thể



\### Lớp 1: Native iOS



Công nghệ dự kiến:



\- Swift.

\- SwiftUI.

\- Swift Concurrency: async/await, Task và các cơ chế đồng bộ phù hợp.

\- MVVM kết hợp các lớp Domain và Application.

\- SwiftData hoặc SQLite cho dữ liệu cục bộ.

\- Keychain cho thông tin xác thực cần lưu an toàn.

\- URLSession cho HTTP khi cần.

\- Supabase Swift SDK cho Auth, truy cập dữ liệu, Storage và các khả năng được SDK hỗ trợ.

\- Swift Testing hoặc XCTest tùy loại test và khả năng tương thích của project.



Không sử dụng WebView để thay thế các màn hình nghiệp vụ chính.



\### Lớp 2: Supabase



Sử dụng các dịch vụ sau:



\*\*Supabase Auth\*\*

\- Đăng ký và đăng nhập theo các phương thức được dự án hỗ trợ.

\- Quản lý phiên đăng nhập.

\- Đăng xuất.

\- Khôi phục phiên.

\- Xử lý hết hạn token và lỗi xác thực.

\- Hỗ trợ khôi phục mật khẩu hoặc xác minh email nếu có trong phạm vi.



\*\*Supabase PostgreSQL\*\*

\- Lưu dữ liệu dùng chung.

\- Lưu tài khoản, giao dịch, nhật ký và các entity thực tế của dự án.

\- Duy trì quan hệ và tính toàn vẹn dữ liệu.

\- Thực thi RLS.

\- Hỗ trợ transaction hoặc RPC khi cần bảo đảm tính nguyên tử.



\*\*Supabase Storage\*\*

\- Lưu file import hoặc attachment nếu nghiệp vụ cần.

\- Quản lý đường dẫn và metadata.

\- Áp dụng quyền truy cập phù hợp.

\- Không để file riêng tư có thể được truy cập công khai ngoài ý muốn.



\*\*Supabase Edge Functions\*\*

Chỉ sử dụng cho các trường hợp thực sự cần xử lý phía máy chủ, chẳng hạn:

\- Giữ bí mật API key của dịch vụ AI.

\- Tích hợp dịch vụ bên ngoài cần credential bí mật.

\- Webhook từ broker hoặc nhà cung cấp.

\- Các thao tác đặc quyền không được phép thực hiện trực tiếp từ client.

\- Tác vụ nền có thể chia thành các bước nhỏ và phù hợp với giới hạn dịch vụ.



Không chuyển toàn bộ nghiệp vụ lên Edge Functions theo mặc định. Không chuyển mọi nghiệp vụ sang client chỉ để tránh sử dụng Edge Functions.



\## 2.2. Phân loại vị trí xử lý



Mỗi nghiệp vụ phải được gán vào một trong các nhóm:



| Nhóm | Vị trí xử lý |

|---|---|

| UI, điều hướng, biểu đồ và tương tác | iOS |

| Quy tắc nghiệp vụ thuần, không cần quyền đặc biệt | Ưu tiên module Swift đã được kiểm thử |

| Lưu dữ liệu dùng chung | Supabase PostgreSQL |

| Đọc/ghi dữ liệu thông thường | Supabase SDK/API với RLS |

| Ghi nhiều bảng cần tính nguyên tử | PostgreSQL transaction hoặc RPC phù hợp |

| API key bí mật và credential bên thứ ba | Edge Function hoặc giải pháp server-side phù hợp |

| File và attachment | Supabase Storage |

| Cache, draft và hàng đợi offline | SwiftData/SQLite |

| Đồng bộ trạng thái từ xa | Supabase và cơ chế đồng bộ do ứng dụng thiết kế |

| Tác vụ chạy nền định kỳ | Đánh giá Supabase scheduler/Edge Functions và giới hạn thực tế |



Không được quyết định vị trí xử lý chỉ dựa trên sự thuận tiện khi viết code. Phải xét tính đúng đắn, bảo mật, khả năng offline và nguy cơ tính toán khác nhau giữa các thiết bị.



\## 2.3. Cấu trúc thư mục dự kiến



Đây là cấu trúc mục tiêu để tham khảo. Sau audit, được phép điều chỉnh để phù hợp với quy mô thực tế.



&#x20;   TradeJournal/

&#x20;     App/

&#x20;       TradeJournalApp.swift

&#x20;       AppEnvironment.swift

&#x20;       AppRouter.swift



&#x20;     DesignSystem/

&#x20;       Components/

&#x20;       Theme/

&#x20;       Typography/

&#x20;       Charts/

&#x20;       Formatting/



&#x20;     Core/

&#x20;       Domain/

&#x20;       Application/

&#x20;       Data/

&#x20;       Networking/

&#x20;       Persistence/

&#x20;       Synchronization/

&#x20;       Security/

&#x20;       Utilities/



&#x20;     Features/

&#x20;       Authentication/

&#x20;       Dashboard/

&#x20;       Accounts/

&#x20;       Trades/

&#x20;       Import/

&#x20;       Analytics/

&#x20;       Journal/

&#x20;       Playbooks/

&#x20;       TradeReplay/

&#x20;       PropFirm/

&#x20;       MarketData/

&#x20;       AIReflection/

&#x20;       Settings/



&#x20;     Resources/

&#x20;       Assets.xcassets/

&#x20;       Localizations/



&#x20;     Tests/

&#x20;       DomainTests/

&#x20;       ImportTests/

&#x20;       SyncTests/

&#x20;       RepositoryTests/

&#x20;       SecurityTests/

&#x20;       DifferentialTests/

&#x20;       UITests/



&#x20;   docs/

&#x20;     ios/

&#x20;       00\_SOURCE\_AUDIT.md

&#x20;       01\_FEATURE\_MATRIX.md

&#x20;       02\_DOMAIN\_MAPPING.md

&#x20;       03\_SUPABASE\_ARCHITECTURE.md

&#x20;       04\_API\_MAPPING.md

&#x20;       05\_IOS\_ARCHITECTURE.md

&#x20;       06\_SYNC\_STRATEGY.md

&#x20;       07\_TEST\_STRATEGY.md

&#x20;       08\_IMPLEMENTATION\_PLAN.md

&#x20;       09\_RISK\_REGISTER.md

&#x20;       10\_ACCEPTANCE\_TEST\_PLAN.md

&#x20;       PROJECT\_STATUS.md



Chỉ tạo module và thư mục thực sự cần thiết. Không tạo hàng loạt file rỗng chỉ để khớp sơ đồ.



\---



\# PHẦN III — ITERATION 00: AUDIT SOURCE



Đây là giai đoạn bắt buộc trước khi viết code port.



\## 3.1. Mục tiêu



Hiểu đầy đủ hệ thống hiện tại, bao gồm nghiệp vụ, data model, API, thuật toán, các tích hợp và những phần chưa hoàn thiện.



Không được bắt đầu rewrite hàng loạt trong giai đoạn này.



\## 3.2. Các khu vực phải đọc



Kiểm tra trực tiếp trong repository:



\- `apps/web`

\- `packages/core`

\- `packages/importers`

\- Database schema và migrations.

\- API routes.

\- Server actions hoặc backend handlers nếu có.

\- Shared types và validation schemas.

\- Các thư viện tính toán.

\- Import parsers.

\- Authentication và authorization.

\- Broker integrations.

\- Market-data integrations.

\- AI integrations.

\- Background jobs, cron jobs và webhook handlers.

\- Test, fixtures và dữ liệu mẫu.

\- README, tài liệu thiết kế và cấu hình deployment.



Danh sách trên là các vị trí cần kiểm tra, không phải khẳng định mọi file hoặc module đều đang tồn tại.



\## 3.3. Các nội dung audit bắt buộc



\### A. Feature inventory



Với mỗi tính năng, ghi lại:



\- Tên và mục đích.

\- Vị trí source code.

\- Trạng thái thực tế.

\- Luồng dữ liệu vào và ra.

\- Entity liên quan.

\- API hoặc dịch vụ phụ thuộc.

\- Test hiện có.

\- Khả năng port sang iOS.

\- Thay đổi kiến trúc cần thiết.

\- Điều kiện nghiệm thu.



Phân loại trạng thái:



\- Implemented and tested.

\- Implemented but insufficiently tested.

\- Partially implemented.

\- UI only or placeholder.

\- Documented but not found in source.

\- Not applicable to iOS without redesign.

\- Unknown; further investigation required.



\### B. Domain logic



Tìm chính xác nơi thực hiện:



\- Dựng lại trade từ executions/fills.

\- Xử lý entry và exit.

\- Xử lý nhiều fills cho một trade.

\- P\&L và phí.

\- Win/loss/breakeven.

\- MAE/MFE và các chỉ số liên quan.

\- Định nghĩa RR nếu có.

\- Tính toán dashboard và analytics.

\- Các quy tắc thời gian, phiên giao dịch và timezone.

\- Cách xử lý sửa đổi, hủy hoặc thiếu dữ liệu.

\- Cách tính các chỉ số theo tài khoản, chiến lược hoặc thời gian.



Không tự đặt công thức khi chưa tìm được định nghĩa gốc.



\### C. Data model



Lập sơ đồ entity và quan hệ.



Với mỗi bảng, ghi rõ:



\- Primary key.

\- Foreign keys.

\- Unique constraints.

\- Indexes.

\- Nullable fields.

\- Default values.

\- Timestamp semantics.

\- User ownership.

\- RLS policies.

\- Trigger hoặc database function liên quan.

\- Cách migration được quản lý.

\- Các bảng là nguồn dữ liệu gốc và các bảng chứa dữ liệu suy ra.



\### D. API mapping



Liệt kê tất cả API routes và phân loại từng route:



1\. Có thể gọi trực tiếp Supabase với RLS.

2\. Cần PostgreSQL function/RPC hoặc transaction.

3\. Cần Supabase Edge Function.

4\. Chuyển sang xử lý local bằng Swift.

5\. Cần thiết kế lại.

6\. Chưa đủ thông tin để quyết định.



Không mặc định API route cũ có thể được thay bằng một truy vấn Supabase đơn giản. Phải đọc logic và side effects thực tế.



\### E. Integration audit



Với từng broker hoặc dịch vụ bên ngoài, xác định:



\- Cách xác thực.

\- Nơi lưu credentials.

\- Có cần webhook không.

\- Có polling không.

\- Tần suất cập nhật.

\- Giới hạn API.

\- Cơ chế retry.

\- Cách xử lý token hết hạn.

\- Có cần tác vụ chạy khi iPhone không mở app không.

\- Có thể hỗ trợ bằng Supabase hay không.

\- Chi phí và giới hạn cần kiểm tra.



\### F. Báo cáo kết thúc



Giai đoạn audit chỉ hoàn tất khi có:



\- Feature matrix.

\- Domain mapping.

\- Data model mapping.

\- API mapping.

\- Security assessment.

\- Sync architecture.

\- Risk register.

\- Implementation plan.

\- Acceptance test plan.

\- Danh sách câu hỏi chưa giải quyết.



Sau đó dừng và báo cáo. Không tự động chuyển sang viết toàn bộ ứng dụng.



\---



\# PHẦN IV — ITERATION 01: THIẾT LẬP PROJECT IOS



\## 4.1. Khởi tạo



\- Tạo hoặc cấu hình project iOS.

\- Chọn deployment target dựa trên yêu cầu thực tế và khả năng tương thích dependency.

\- Cấu hình Swift version.

\- Cấu hình Debug, Test và Release.

\- Cấu hình bundle identifier và signing.

\- Thiết lập quản lý dependency.

\- Thiết lập test targets.

\- Thiết lập logging và xử lý lỗi thống nhất.



\## 4.2. Foundation



Xây dựng các thành phần cơ sở:



\- App entry point.

\- App environment.

\- Dependency container.

\- Navigation.

\- Design system cơ bản.

\- Error model.

\- Loading và empty states.

\- Formatting cho tiền, tỷ lệ, giá và thời gian.

\- Configuration theo môi trường.

\- Logging không làm lộ thông tin nhạy cảm.



\## 4.3. Điều kiện nghiệm thu



\- App build thành công.

\- App chạy được trên Simulator và thiết bị thật.

\- Các môi trường không dùng chung secrets ngoài ý muốn.

\- Test target hoạt động.

\- Không có WebView làm nền tảng cho các màn hình chính.

\- Không có API key bí mật trong client.



\---



\# PHẦN V — ITERATION 02: AUTHENTICATION VÀ SECURITY



\## 5.1. Authentication



Triển khai các luồng có trong phạm vi:



\- Đăng nhập.

\- Đăng xuất.

\- Khôi phục phiên.

\- Xử lý token hết hạn.

\- Xử lý mất mạng khi khởi động.

\- Hiển thị trạng thái xác thực.

\- Khôi phục mật khẩu hoặc xác minh email nếu cần.

\- Xử lý user bị vô hiệu hóa hoặc không còn quyền truy cập.



Không giả định người dùng đã đăng nhập chỉ vì tồn tại local cache.



\## 5.2. RLS và quyền dữ liệu



Với mọi bảng chứa dữ liệu riêng tư:



\- Xác định ownership.

\- Xây dựng policy đọc.

\- Xây dựng policy insert.

\- Xây dựng policy update.

\- Xây dựng policy delete.

\- Kiểm tra quyền thông qua `auth.uid()` hoặc cơ chế phù hợp.

\- Kiểm tra quan hệ giữa các bảng để ngăn truy cập chéo user.

\- Kiểm tra quyền truy cập Storage.

\- Xác nhận quyền SQL không vô tình vượt qua RLS.



Không cho client tự khai báo `user\_id` rồi mặc định tin tưởng giá trị đó.



\## 5.3. Security test



Tối thiểu phải có test:



\- User A không đọc được dữ liệu riêng của User B.

\- User A không sửa được dữ liệu riêng của User B.

\- User A không xóa được dữ liệu riêng của User B.

\- Không truy cập file riêng tư bằng đường dẫn không được phép.

\- Đăng xuất không để lại quyền thao tác qua phiên cũ.

\- Không có service-role key trong bundle.

\- Các thao tác đặc quyền không thể bị gọi tùy tiện từ client.



\## 5.4. Điều kiện nghiệm thu



Đăng nhập và quyền dữ liệu phải được kiểm chứng trước khi triển khai các tính năng tài chính quan trọng.



\---



\# PHẦN VI — ITERATION 03: DOMAIN ENGINE VÀ TÍNH ĐÚNG ĐẮN



\## 6.1. Mục tiêu



Port các quy tắc nghiệp vụ cốt lõi sang Swift theo source gốc.



Không triển khai analytics hàng loạt trước khi xác minh được các phép tính nền tảng.



\## 6.2. Trade reconstruction



Đọc và mô tả thuật toán hiện tại trước khi port.



Phải xác định cách xử lý:



\- Một trade gồm nhiều executions/fills.

\- Nhiều lần entry.

\- Partial exits.

\- Đóng vị thế theo từng phần.

\- Các executions đến không đúng thứ tự.

\- Dữ liệu đến trễ.

\- Executions bị hủy hoặc điều chỉnh nếu source hỗ trợ.

\- Các giao dịch không ghép được.

\- Position reversal nếu source hỗ trợ.

\- Phí và commission.

\- Các trường hợp thiếu dữ liệu.

\- Quy tắc phân loại trade hoàn tất và chưa hoàn tất.



Không tự bổ sung quy tắc mới chỉ vì thấy hợp lý về mặt trading.



\## 6.3. Độ chính xác số



\- Dùng `Decimal` hoặc biểu diễn số chính xác phù hợp.

\- Tránh cộng dồn sai số nhị phân từ `Double` trong các phép tính tiền tệ.

\- Xác định quy tắc rounding từ source.

\- Xác định cách xử lý currency và tick size.

\- Không tự giả định mọi tài khoản dùng cùng currency.

\- Giữ nguyên độ chính xác của giá, số lượng và phí khi cần.



\## 6.4. Differential testing



Tạo bộ dữ liệu mẫu đại diện cho các trường hợp nghiệp vụ.



Chạy cùng input qua:



1\. Logic của bản gốc.

2\. Logic Swift đã port.



So sánh output theo từng trường quan trọng.



Các trường có thể cần so sánh tùy data model:



\- Trade identity.

\- Entry/exit.

\- Quantity.

\- Fees.

\- Realized P\&L.

\- Status.

\- Timestamp.

\- MAE/MFE.

\- Các chỉ số analytics được suy ra.



Không chỉ so sánh tổng P\&L; phải phát hiện sai lệch ở từng trade.



\## 6.5. Điều kiện nghiệm thu



\- Các test nghiệp vụ cốt lõi đều chạy.

\- Sai lệch được phân loại và giải thích.

\- Không có khác biệt chưa giải thích trong những trường được xác định là bắt buộc phải tương đương.

\- Nếu source gốc có bug đã biết, phải ghi nhận riêng thay vì âm thầm sửa trong bản port.



\---



\# PHẦN VII — ITERATION 04: DATA LAYER VÀ ĐỒNG BỘ



\## 7.1. Quy tắc dữ liệu



Supabase PostgreSQL là nguồn dữ liệu dùng chung.



Local database trên iPhone dùng để:



\- Cache dữ liệu đã tải.

\- Lưu draft.

\- Lưu thao tác chờ đồng bộ.

\- Hỗ trợ offline trong phạm vi đã xác định.

\- Giảm truy vấn lặp.

\- Giữ trạng thái giao diện ổn định khi kết nối kém.



Local database không được coi là nguồn dữ liệu cuối cùng có thể tự ghi đè dữ liệu trên Supabase mà không kiểm tra.



\## 7.2. Thiết kế sync engine



Xây dựng các thành phần:



\- Local persistence.

\- Remote repository.

\- Sync coordinator.

\- Pending operation queue.

\- Retry policy.

\- Idempotency.

\- Conflict resolution.

\- Error recovery.

\- Sync state tracking.

\- Refresh khi app foreground.

\- Refresh khi kết nối mạng được khôi phục.

\- Phân trang và đồng bộ tăng dần.



\## 7.3. Idempotency và chống trùng



Mỗi thao tác ghi có thể retry phải có định danh ổn định.



Đối với dữ liệu import và executions:



\- Dùng khóa định danh ổn định khi có.

\- Sử dụng unique constraints phù hợp.

\- Không chỉ dựa vào timestamp để phát hiện trùng.

\- Nếu source không cung cấp ID ổn định, thiết kế fingerprint có cơ sở và ghi rõ giới hạn.

\- Phân biệt một lần import mới với việc import lại cùng dữ liệu.

\- Ghi nhận kết quả import và lỗi có thể phục hồi.



Không cho phép retry sau timeout tạo ra bản ghi trùng chỉ vì client không nhận được response lần đầu.



\## 7.4. Conflict resolution



Không áp dụng một chính sách duy nhất cho tất cả entity.



Ví dụ, cần đánh giá riêng:



\- Ghi chú có thể cho phép quy tắc last-write-wins nếu có lý do.

\- Executions và lịch sử giao dịch cần quy tắc bảo toàn dữ liệu nghiêm ngặt hơn.

\- Các trường dẫn xuất có thể cần tính lại từ nguồn dữ liệu chuẩn.

\- Thao tác xóa cần xử lý tombstone hoặc cơ chế tương đương nếu hỗ trợ offline.



Mọi quy tắc phải được ghi trong `06\_SYNC\_STRATEGY.md`.



\## 7.5. Không giả định Realtime là sync engine



Realtime có thể giúp thông báo thay đổi, nhưng ứng dụng vẫn cần:



\- Tải dữ liệu khi mở app.

\- Refresh khi quay lại foreground.

\- Xử lý mất kết nối.

\- Phân trang dữ liệu lớn.

\- Kiểm tra dữ liệu thay đổi trong thời gian offline.

\- Xử lý sự kiện bị bỏ lỡ.

\- Kiểm soát thứ tự và phiên bản bản ghi.



Không yêu cầu ứng dụng giữ kết nối Realtime liên tục khi iOS không cho phép.



\## 7.6. Điều kiện nghiệm thu



\- Dữ liệu ghi thành công trên iPhone có thể xuất hiện trên thiết bị khác sau khi đồng bộ.

\- Thao tác offline được xử lý theo chính sách đã công bố.

\- Retry không tạo duplicate.

\- Conflict không làm mất dữ liệu im lặng.

\- Lỗi sync có thể được quan sát và phục hồi.



\---



\# PHẦN VIII — ITERATION 05: ACCOUNTS, TRADES VÀ IMPORT



\## 8.1. Accounts



Port chức năng quản lý tài khoản đúng với phạm vi source:



\- Danh sách tài khoản.

\- Chi tiết tài khoản.

\- Bộ lọc và trạng thái.

\- Các trường cấu hình liên quan.

\- Trạng thái đồng bộ.

\- Liên kết với trades và executions.



Không tự bổ sung hoặc bỏ các trường nghiệp vụ khi chưa audit.



\## 8.2. Trades



Xây dựng:



\- Danh sách trades.

\- Chi tiết trade.

\- Các trường giá và số lượng.

\- P\&L và phí.

\- Trạng thái.

\- Bộ lọc.

\- Liên kết tới account.

\- Lịch sử hoặc nguồn executions nếu có.

\- Các chỉ số phụ trợ mà source thực sự hỗ trợ.



Phân biệt rõ dữ liệu gốc với dữ liệu suy ra.



\## 8.3. Import pipeline



Luồng đề xuất:



1\. Chọn file.

2\. Kiểm tra loại file và kích thước.

3\. Parse dữ liệu.

4\. Validate schema và các trường bắt buộc.

5\. Chuẩn hóa định dạng.

6\. Hiển thị preview.

7\. Báo lỗi và cảnh báo.

8\. Kiểm tra dữ liệu trùng.

9\. Xác nhận import.

10\. Ghi dữ liệu theo cách có thể phục hồi.

11\. Tính hoặc cập nhật các dữ liệu suy ra.

12\. Hiển thị kết quả import.

13\. Cho phép xem lỗi chi tiết.



Các bước cụ thể phải phù hợp với importer gốc.



\## 8.4. Import phải có khả năng phục hồi



\- Không ghi một phần dữ liệu rồi báo thành công toàn bộ.

\- Nếu cần chia batch, phải có trạng thái từng batch.

\- Không mất thông tin về các dòng bị lỗi.

\- Cho phép xử lý lại các dòng thất bại.

\- Không tạo trùng khi retry.

\- Không yêu cầu người dùng import lại toàn bộ file chỉ vì một phần dữ liệu thất bại.



\## 8.5. Điều kiện nghiệm thu



Kiểm thử file hợp lệ, file rỗng, file sai cấu trúc, thiếu trường, trùng dữ liệu, dữ liệu lớn, lỗi mạng giữa quá trình import và import lặp lại.



\---



\# PHẦN IX — ITERATION 06: DASHBOARD VÀ ANALYTICS



\## 9.1. Nguyên tắc



Port đúng các chỉ số thực sự tồn tại trong dự án gốc.



Không tự thêm công thức hoặc đổi định nghĩa chỉ số nhằm làm giao diện đẹp hơn.



\## 9.2. Các nhóm cần audit



Tùy source thực tế, bao gồm:



\- Tổng quan tài khoản.

\- Số lượng trades.

\- Win rate.

\- Net/gross P\&L.

\- Commission và phí.

\- Profit factor.

\- Expectancy.

\- RR.

\- Equity curve.

\- Drawdown.

\- Kết quả theo ngày, tuần, tháng.

\- Kết quả theo strategy hoặc setup.

\- Phân tích theo thời gian hoặc phiên giao dịch.

\- Các chiều phân tích bổ sung được hỗ trợ.



Danh sách này là danh mục cần kiểm tra, không phải khẳng định mọi chỉ số đều có trong source.



\## 9.3. Kiểm soát phép tính



Với mỗi chỉ số:



\- Ghi công thức nguồn.

\- Xác định tập dữ liệu đầu vào.

\- Xác định cách xử lý trade chưa đóng.

\- Xác định quy tắc loại trừ dữ liệu lỗi hoặc thiếu.

\- Xác định cách xử lý phí.

\- Xác định timezone và biên khoảng thời gian.

\- Xác định rounding.

\- Tạo test đối chiếu.



\## 9.4. UI



\- Dùng SwiftUI native.

\- Biểu đồ có trục, đơn vị và tooltip phù hợp.

\- Có loading, empty và error states.

\- Bộ lọc phải nhất quán.

\- Không hiển thị giá trị stale như dữ liệu mới nhất.

\- Thể hiện trạng thái đồng bộ khi cần.

\- Tránh tính toán toàn bộ lịch sử trên main thread.



\## 9.5. Điều kiện nghiệm thu



Cùng một tập dữ liệu và bộ lọc phải cho ra cùng kết quả với logic gốc theo các quy tắc đã xác minh.



\---



\# PHẦN X — ITERATION 07: JOURNAL, PLAYBOOK, ROUTINE VÀ REPLAY



Chỉ triển khai các module được xác nhận có trong source hoặc đã được phê duyệt trong phạm vi.



\## 10.1. Journal



\- Danh sách nhật ký.

\- Nhật ký theo ngày.

\- Tạo và sửa nội dung.

\- Liên kết với trade nếu source hỗ trợ.

\- Lưu draft.

\- Đồng bộ nội dung.

\- Hiển thị trạng thái save/sync.

\- Xử lý xung đột chỉnh sửa.



\## 10.2. Playbooks và routines



\- Danh sách.

\- Chi tiết.

\- Các thuộc tính nghiệp vụ.

\- Liên kết với trade hoặc journal.

\- Quy tắc cập nhật và xóa.

\- Đồng bộ nhiều thiết bị.



Không tự định nghĩa lại cấu trúc playbook hoặc routine khi chưa hiểu data model gốc.



\## 10.3. Missed opportunities



Nếu có trong source:



\- Port đúng cách lưu dữ liệu.

\- Giữ nguyên quan hệ với ngày, trade hoặc setup.

\- Bảo toàn các trường và quy tắc thống kê.

\- Không tự biến chúng thành trades thật nếu nghiệp vụ gốc phân biệt hai loại.



\## 10.4. Trade replay



Nếu có trong source:



\- Xác định dữ liệu lịch sử cần thiết.

\- Xác định nguồn market data.

\- Xác định cách xử lý timestamp và timezone.

\- Xác định những trường hợp replay không có đủ dữ liệu.

\- Tối ưu tải dữ liệu và render biểu đồ.

\- Không giả lập dữ liệu giá nhưng hiển thị như dữ liệu thật.



\## 10.5. Điều kiện nghiệm thu



Nội dung tạo mới hoặc chỉnh sửa được lưu đúng, đồng bộ đúng và không làm thay đổi dữ liệu trade ngoài ý muốn.



\---



\# PHẦN XI — ITERATION 08: BROKER, MARKET DATA, PROP FIRM VÀ AI



Đây là nhóm có rủi ro kiến trúc cao nhất vì có thể phụ thuộc API bên ngoài, credentials và tác vụ nền.



Mỗi tích hợp phải có một quyết định kỹ thuật riêng dựa trên audit.



\## 11.1. Broker integration



Kiểm tra:



\- Các broker thực sự được hỗ trợ.

\- Cơ chế lấy dữ liệu.

\- Credential requirements.

\- API limits.

\- Token lifecycle.

\- Polling hoặc webhook.

\- Incremental sync.

\- Duplicate detection.

\- Error recovery.

\- Tác vụ cần chạy khi app không mở.



Nếu broker yêu cầu API secret không được phép đặt trên iPhone, phải sử dụng phương án server-side phù hợp. Ưu tiên Edge Functions hoặc dịch vụ Supabase khác khi đáp ứng được yêu cầu.



Không tuyên bố hỗ trợ đồng bộ tự động 24/7 chỉ dựa vào việc ứng dụng có thể gọi API khi mở.



\## 11.2. Market data



Xác định:



\- Nguồn dữ liệu.

\- Quyền sử dụng.

\- Chi phí.

\- Giới hạn API.

\- Lưu lượng.

\- Độ trễ.

\- Cách cache.

\- Quy tắc timestamp.

\- Những tính năng cần dữ liệu lịch sử.



Không tự tạo giá giả để thay cho nguồn dữ liệu chưa kết nối.



\## 11.3. Prop-firm ledger



Nếu có trong source:



\- Port các entity và quy tắc thực tế.

\- Xác định các trường số dư, giao dịch hoặc trạng thái.

\- Xác định quy tắc cập nhật.

\- Giữ lịch sử cần thiết.

\- Không để phép tính trên client tạo ra số liệu chính thức khác với nguồn chuẩn.



\## 11.4. AI reflection



Nếu có trong source:



\- Kiểm tra provider và luồng request.

\- Không nhúng API key vào app.

\- Đánh giá dữ liệu nào được gửi cho nhà cung cấp.

\- Tối thiểu hóa dữ liệu nhạy cảm.

\- Có trạng thái loading, success, error và retry.

\- Xử lý giới hạn request.

\- Kiểm soát chi phí.

\- Không ghi đè nội dung người dùng bằng phản hồi AI mà không có hành động rõ ràng.



\## 11.5. Tác vụ nền



Phải ghi rõ cho từng workflow:



\- Cần chạy khi app đang mở hay không.

\- Cần chạy khi app đóng hay không.

\- Có thể chạy theo lịch bằng dịch vụ Supabase hay không.

\- Có cần webhook hay không.

\- Có thể chia thành batch nhỏ hay không.

\- Có giới hạn thời gian, tài nguyên hoặc chi phí nào.

\- Nếu không đáp ứng được, chức năng sẽ thay đổi thế nào.



Không giả định iOS có thể duy trì tác vụ nền vô thời hạn.



\## 11.6. Điều kiện nghiệm thu



Mỗi tích hợp phải được kiểm thử với API thật hoặc môi trường test phù hợp. Nếu chưa có credentials hoặc chưa thể kết nối, ghi rõ trạng thái là chưa nghiệm thu.



\---



\# PHẦN XII — ITERATION 09: SETTINGS, BACKUP VÀ HOÀN THIỆN



\## 12.1. Settings



Port các thiết lập thực sự có trong source:



\- Tài khoản.

\- Cấu hình giao dịch.

\- Preferences.

\- Các tích hợp.

\- Quản lý phiên.

\- Các tùy chọn hiển thị.

\- Các tính năng dữ liệu và bảo mật.



\## 12.2. Backup và recovery



Không mặc định rằng Supabase Storage thay thế hoàn toàn backup PostgreSQL.



Phải xác định:



\- Cơ chế backup phù hợp với khả năng Supabase hiện có.

\- Phạm vi backup.

\- Thời gian lưu.

\- Cách khôi phục.

\- Cách bảo vệ file import.

\- Cách xử lý dữ liệu cục bộ bị hỏng.

\- Quy trình khôi phục sau khi người dùng đăng nhập lại.



Không tuyên bố backup thành công khi mới chỉ xuất được file trên iPhone.



\## 12.3. Hiệu năng



Kiểm thử với dataset thực tế hoặc dataset lớn đại diện.



Tối ưu:



\- Phân trang.

\- Truy vấn có index.

\- Tải dữ liệu theo nhu cầu.

\- Cache.

\- Tính toán nặng.

\- Render biểu đồ.

\- Import batch.

\- Bộ nhớ.

\- Main-thread responsiveness.



Không tối ưu bằng cách làm thay đổi nghiệp vụ hoặc độ chính xác.



\## 12.4. Điều kiện nghiệm thu



Các luồng cốt lõi hoạt động ổn định trên thiết bị thật, lỗi được xử lý rõ ràng và không còn vấn đề nghiêm trọng chưa được công bố.



\---



\# PHẦN XIII — TESTING VÀ ACCEPTANCE CRITERIA



\## 13.1. Unit tests



Kiểm tra:



\- Domain entities.

\- Financial calculations.

\- Trade reconstruction.

\- Import parsing.

\- Validation.

\- Formatting.

\- Date/time rules.

\- Filtering.

\- Conflict-resolution logic.



\## 13.2. Integration tests



Kiểm tra:



\- Supabase Auth.

\- Repository.

\- Database operations.

\- RLS.

\- Storage permissions.

\- Import transactions.

\- Sync queue.

\- Retry và idempotency.

\- Các Edge Functions thực sự được triển khai.



\## 13.3. Differential tests



Dùng dữ liệu đầu vào giống nhau cho bản gốc và bản Swift.



So sánh:



\- Entity output.

\- Trade reconstruction.

\- P\&L.

\- Fees.

\- Status.

\- Analytics.

\- Time boundaries.

\- Rounding.



Sai lệch phải được phân loại:



\- Bug của bản port.

\- Bug đã tồn tại trong bản gốc.

\- Dữ liệu đầu vào khác nhau.

\- Khác biệt môi trường.

\- Khác biệt được chủ động phê duyệt.



Không được tự bỏ test chỉ vì kết quả không khớp.



\## 13.4. Offline và sync tests



Tối thiểu kiểm thử:



1\. Tạo dữ liệu khi online.

2\. Tạo dữ liệu khi offline.

3\. Đóng app trước khi sync.

4\. Mở app lại.

5\. Retry sau timeout.

6\. Retry sau lỗi server.

7\. Hai thiết bị sửa cùng một bản ghi.

8\. Một thiết bị xóa, thiết bị khác vẫn giữ cache.

9\. Import lại cùng file.

10\. Mất kết nối giữa quá trình import.

11\. Session hết hạn giữa quá trình sync.

12\. Dữ liệu thay đổi trên server khi iPhone offline.



\## 13.5. Security tests



\- Cross-user access.

\- RLS enforcement.

\- Storage access.

\- Credential leakage.

\- Session expiry.

\- Unauthorized RPC/Edge Function calls.

\- Input validation.

\- Access sau logout.



\## 13.6. UI tests



\- Login/logout.

\- Điều hướng chính.

\- Danh sách và chi tiết trade.

\- Import.

\- Dashboard.

\- Journal.

\- Loading/empty/error states.

\- Các thao tác lưu và đồng bộ.



\## 13.7. Definition of Done



Một iteration chỉ hoàn thành khi:



\- Code được triển khai.

\- Build thành công.

\- Test liên quan chạy thành công.

\- Không có lỗi nghiêm trọng chưa giải thích.

\- Tài liệu được cập nhật.

\- `PROJECT\_STATUS.md` phản ánh đúng trạng thái.

\- Có ghi nhận các giới hạn và công việc còn lại.

\- Các tiêu chí nghiệm thu của iteration được đáp ứng.



\---



\# PHẦN XIV — QUẢN LÝ ITERATION VÀ SOURCE CODE



\## 14.1. Quy trình làm việc bắt buộc



Với mỗi iteration:



1\. Đọc trạng thái hiện tại.

2\. Đọc tài liệu liên quan.

3\. Kiểm tra source và dependency.

4\. Xác định phạm vi nhỏ, cụ thể.

5\. Xác định file cần tạo hoặc sửa.

6\. Triển khai.

7\. Build.

8\. Chạy test liên quan.

9\. Kiểm tra diff.

10\. Sửa lỗi.

11\. Cập nhật tài liệu.

12\. Cập nhật `PROJECT\_STATUS.md`.

13\. Báo cáo kết quả và điểm chưa hoàn thành.



Không triển khai đồng thời quá nhiều module chưa có dependency rõ ràng.



\## 14.2. Quy tắc chỉnh sửa



\- Không xóa source gốc chỉ vì đã bắt đầu port.

\- Không xóa test để làm build xanh.

\- Không sửa fixture chỉ để che giấu sai lệch.

\- Không thay đổi schema hoặc migration một cách âm thầm.

\- Không thay đổi công thức nghiệp vụ mà không ghi nhận.

\- Không tạo abstraction phức tạp nếu chưa có nhu cầu.

\- Không thêm dependency chỉ để thay thế một đoạn code đơn giản.

\- Không sinh file báo cáo lặp lại cho cùng một trạng thái.

\- Không để TODO quan trọng bị che giấu trong code mà không ghi trong status.



\## 14.3. Báo cáo cuối iteration



Mỗi báo cáo cần có:



\- Mục tiêu.

\- Phạm vi đã thực hiện.

\- File đã thêm/sửa.

\- Nghiệp vụ đã triển khai.

\- Test đã chạy.

\- Kết quả build.

\- Lỗi còn tồn tại.

\- Rủi ro.

\- Việc cần làm tiếp theo.

\- Trạng thái nghiệm thu.



Không ghi “completed” nếu còn tiêu chí bắt buộc chưa đạt.



\---



\# PHẦN XV — BỘ TÀI LIỆU NGHIỆM THU



Tất cả tài liệu đặt trong `docs/ios/`.



\## 15.1. Danh sách file



\*\*`00\_SOURCE\_AUDIT.md`\*\*



Tổng quan source code, module, dependency, trạng thái implementation và bằng chứng thực tế.



\*\*`01\_FEATURE\_MATRIX.md`\*\*



Bảng feature-by-feature: chức năng, source files, trạng thái, phụ thuộc, kế hoạch port và acceptance criteria.



\*\*`02\_DOMAIN\_MAPPING.md`\*\*



Entity, quan hệ, quy tắc nghiệp vụ, công thức, financial invariants và các trường hợp biên.



\*\*`03\_SUPABASE\_ARCHITECTURE.md`\*\*



Kiến trúc Auth, PostgreSQL, Storage, RLS, Edge Functions và các quyết định bảo mật.



\*\*`04\_API\_MAPPING.md`\*\*



Mỗi API route cũ được ánh xạ sang Supabase trực tiếp, RPC, Edge Function, xử lý local hoặc redesign.



\*\*`05\_IOS\_ARCHITECTURE.md`\*\*



Cấu trúc module, luồng dữ liệu, dependency, navigation và trách nhiệm từng lớp.



\*\*`06\_SYNC\_STRATEGY.md`\*\*



Cache, offline queue, retry, idempotency, conflict resolution, incremental sync và recovery.



\*\*`07\_TEST\_STRATEGY.md`\*\*



Unit, integration, differential, security, offline và UI tests.



\*\*`08\_IMPLEMENTATION\_PLAN.md`\*\*



Iteration, dependency, thứ tự triển khai và điều kiện nghiệm thu.



\*\*`09\_RISK\_REGISTER.md`\*\*



Rủi ro, mức độ ảnh hưởng, xác suất, cách giảm thiểu và quyết định còn thiếu.



\*\*`10\_ACCEPTANCE\_TEST\_PLAN.md`\*\*



Danh sách test case cụ thể, input, expected result và trạng thái thực thi.



\*\*`PROJECT\_STATUS.md`\*\*



Trạng thái hiện tại, iteration đang làm, việc đã xong, việc chưa xong, lỗi và bước tiếp theo.



\## 15.2. Quy tắc cập nhật tài liệu



\- Không viết lại toàn bộ tài liệu nếu chỉ cần cập nhật một phần.

\- Không sao chép cùng nội dung vào nhiều file.

\- Các quyết định kiến trúc phải có lý do.

\- Mọi giới hạn chưa giải quyết phải được ghi rõ.

\- Phân biệt kế hoạch, implementation và kết quả đã kiểm chứng.

\- Không ghi kết quả test chưa thực sự chạy.



\---



\# PHẦN XVI — RỦI RO CẦN KIỂM SOÁT



\## Rủi ro 1: Sai logic dựng lại trade



\*\*Tác động:\*\* sai toàn bộ các chỉ số phụ thuộc trade.



\*\*Giảm thiểu:\*\* audit source, xác định nguồn dữ liệu gốc và differential testing.



\## Rủi ro 2: Dữ liệu bị nhân đôi



\*\*Tác động:\*\* P\&L và số lượng trade không chính xác.



\*\*Giảm thiểu:\*\* stable IDs, unique constraints, idempotency và import tests.



\## Rủi ro 3: Đồng bộ sai giữa nhiều thiết bị



\*\*Tác động:\*\* mất ghi chú, ghi đè dữ liệu hoặc dashboard không nhất quán.



\*\*Giảm thiểu:\*\* sync queue, versioning, conflict policy và refresh sau reconnect.



\## Rủi ro 4: RLS cấu hình sai



\*\*Tác động:\*\* rò rỉ dữ liệu giữa người dùng.



\*\*Giảm thiểu:\*\* test bằng nhiều user, kiểm tra cả SELECT/INSERT/UPDATE/DELETE và Storage.



\## Rủi ro 5: Tác vụ broker cần chạy liên tục



\*\*Tác động:\*\* không thể giữ nguyên hành vi nếu chỉ phụ thuộc iPhone.



\*\*Giảm thiểu:\*\* xác định chính xác yêu cầu; dùng dịch vụ Supabase phù hợp khi khả thi; công bố giới hạn nếu không thể đáp ứng.



\## Rủi ro 6: Edge Functions vượt giới hạn



\*\*Tác động:\*\* tác vụ timeout hoặc không xử lý hết dữ liệu.



\*\*Giảm thiểu:\*\* chia batch, lưu checkpoint, idempotency và kiểm tra giới hạn dịch vụ hiện hành.



\## Rủi ro 7: Chi phí dịch vụ tăng



\*\*Tác động:\*\* vượt ngân sách do truy vấn, lưu file, AI hoặc đồng bộ.



\*\*Giảm thiểu:\*\* ước lượng tải, theo dõi usage, giới hạn request và đánh giá chi phí trước khi bật các workflow nặng.



\## Rủi ro 8: Thiếu dữ liệu lịch sử cho replay



\*\*Tác động:\*\* không thể tái tạo biểu đồ lịch sử như bản gốc.



\*\*Giảm thiểu:\*\* audit nguồn dữ liệu và quyền truy cập; không giả lập dữ liệu thiếu.



\## Rủi ro 9: Phụ thuộc source chưa hoàn thiện



\*\*Tác động:\*\* port một tính năng vốn chưa hoàn thiện hoặc chưa có test.



\*\*Giảm thiểu:\*\* phân loại implementation status và ghi rõ feature parity có thể đạt được.



\---



\# PHẦN XVII — THỨ TỰ THỰC HIỆN VÀ GATE NGHIỆM THU



Thứ tự chính:



1\. Iteration 00 — Source audit.

2\. Iteration 01 — iOS foundation.

3\. Iteration 02 — Authentication và security.

4\. Iteration 03 — Domain engine và financial parity.

5\. Iteration 04 — Data layer và synchronization.

6\. Iteration 05 — Accounts, trades và import.

7\. Iteration 06 — Dashboard và analytics.

8\. Iteration 07 — Journal, playbooks và replay.

9\. Iteration 08 — Broker, market data, prop firm và AI.

10\. Iteration 09 — Settings, recovery, performance và release readiness.



Các iteration có thể được chia nhỏ hơn khi source phức tạp. Không được gộp các bước chỉ để rút ngắn báo cáo.



\## Gate A — Trước khi viết code port



Phải hoàn thành audit, feature matrix, domain mapping, API mapping, security review và implementation plan.



\## Gate B — Trước khi triển khai giao dịch thực tế



Phải có domain tests và kết quả so sánh với logic gốc.



\## Gate C — Trước khi triển khai đồng bộ diện rộng



Phải có RLS tests, idempotency tests và conflict-resolution policy.



\## Gate D — Trước khi công bố tính năng



Phải đạt acceptance criteria và có test evidence.



\## Gate E — Trước khi release



Phải hoàn thành kiểm thử thiết bị thật, security review, lỗi nghiêm trọng, tài liệu và cấu hình phát hành.



\---



\# PHẦN XVIII — YÊU CẦU BẮT ĐẦU THỰC HIỆN



Bắt đầu từ \*\*Iteration 00: Source Audit\*\*.



Trong iteration đầu tiên:



1\. Kiểm tra repository thực tế.

2\. Đọc các module và test quan trọng.

3\. Lập feature matrix.

4\. Xác định domain logic và schema.

5\. Lập API mapping sang kiến trúc iPhone + Supabase.

6\. Thiết kế sync strategy.

7\. Đánh giá security và các tích hợp bên ngoài.

8\. Viết đầy đủ bộ tài liệu audit.

9\. Cập nhật `PROJECT\_STATUS.md`.

10\. Dừng lại để báo cáo kết quả.



Không triển khai ứng dụng hàng loạt trong iteration audit.



Sau khi audit hoàn tất, báo cáo ngắn gọn:



\- Những gì source thực sự đang có.

\- Các nghiệp vụ quan trọng nhất.

\- Những phần có thể port trực tiếp.

\- Những phần cần redesign.

\- Những phần bị giới hạn bởi iPhone + Supabase.

\- Các rủi ro lớn nhất.

\- Thứ tự triển khai đề xuất.

\- Các quyết định cần xác nhận trước khi code.



\*\*Điều kiện hoàn thành cuối cùng:\*\* một ứng dụng iOS native có thể sử dụng trên iPhone, dữ liệu dùng chung được lưu trên Supabase, các chức năng đã port giữ đúng nghiệp vụ gốc theo phạm vi nghiệm thu, bảo mật được kiểm chứng và mọi giới hạn còn lại được công bố rõ ràng.



Không tuyên bố toàn bộ ứng dụng hoàn tất nếu còn tính năng bắt buộc chưa triển khai hoặc chưa có bằng chứng kiểm thử.

