# Sinh Tử

Ứng dụng Flutter xác nhận an toàn định kỳ, quản lý liên hệ khẩn cấp và gửi email cảnh báo.

## Chạy demo Android cục bộ, không cần deploy Functions

Bản Debug mặc định kết nối Firebase Auth, Firestore và Cloud Functions Emulator. Hãy khởi chạy emulator trước khi chạy app.

### Chuẩn bị email SMTP

Trong Android Studio Terminal tại thư mục dự án, sao chép file mẫu:

```powershell
Copy-Item functions/.env.local.example functions/.env.local
Copy-Item functions/.secret.local.example functions/.secret.local
```

Mở `functions/.secret.local`, thay `SMTP_USER` và `SMTP_FROM` bằng địa chỉ Gmail gửi, `SMTP_PASS` bằng Google App Password. Gmail dùng `smtp.gmail.com`, cổng TLS `587`. App Password yêu cầu bật Xác minh 2 bước; không dùng mật khẩu đăng nhập Gmail. Đặt cả `SEND_DEMO_ALERTS=true` và `SEND_REAL_ALERTS=true` để bật hai luồng gửi khi chạy emulator. Không đưa file này vào Git.

### Khởi chạy emulator

```powershell
npm.cmd --prefix functions run build
firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --export-on-exit=.firebase-demo-data
```

Emulator UI mở tại `http://localhost:4000`. Android Emulator kết nối máy tính qua `10.0.2.2`; bản Release không dùng emulator. Lần chạy sau có thể thêm `--import=.firebase-demo-data` để nạp lại dữ liệu đã xuất.

### Kịch bản demo email

1. Chạy `lib/main.dart` bằng cấu hình Debug trong Android Studio.
2. Đăng ký tài khoản trong app. Tài khoản và dữ liệu demo được lưu trong emulator.
3. Thêm email thử nghiệm trong Danh bạ rồi gửi link xác minh.
4. Mở email trên máy tính đang chạy emulator, bấm link và chấp thuận nhận cảnh báo.
5. Vào **Cài đặt → Gửi email cảnh báo demo** và xác nhận. Email demo sẽ được gửi ngay qua SMTP.

Để demo luồng **quá hạn tự động**, vào **Cài đặt → Bắt đầu demo quá hạn**. Hạn xác nhận sẽ được đặt quá hạn trong emulator với thời gian gia hạn 1 phút. Scheduler chạy mỗi phút, nên email cảnh báo thật thường tới trong khoảng 1–2 phút; giữ emulator mở trong lúc chờ. Luồng này chỉ gửi tới liên hệ đã xác minh và đồng ý nhận cảnh báo.

Link xác minh cục bộ dùng `localhost`, nên mở link trong trình duyệt trên chính máy tính đang chạy emulator. SMTP gửi email thật; Functions, Auth, Firestore và Pub/Sub chạy cục bộ. Bản Debug dùng dữ liệu emulator riêng, còn cấu hình triển khai giữ chu kỳ 15 phút và thời gian gia hạn 3 giờ.
