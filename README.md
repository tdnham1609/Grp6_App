# Sinh Tử

**Sinh Tử** là ứng dụng Flutter Android giúp người dùng xác nhận trạng thái an toàn theo chu kỳ và cảnh báo người thân nếu không phản hồi đúng hạn.

Ứng dụng phù hợp cho người sống một mình, làm việc xa nhà, di chuyển một mình hoặc tham gia hoạt động có rủi ro. Người dùng có thể check-in nhanh từ app, notification hoặc Android Home Screen Widget; hệ thống tính deadline tiếp theo và thông báo người liên hệ khẩn cấp nếu quá hạn.

## Vấn đề ứng dụng giải quyết

- Người sống một mình có thể quên hoặc không mở app để xác nhận đang an toàn.
- Người thân khó biết tình trạng người được theo dõi khi cuộc gọi hoặc tin nhắn không được phản hồi.
- Việc theo dõi thủ công không có mốc thời gian nhất quán.
- Người dùng cần check-in ngay cả khi mất mạng và có cơ chế đồng bộ sau.
- Android có thể không gửi nhắc nhở nếu chưa cấp notification/exact alarm permission.
- Người thân cần trạng thái tóm tắt mà không truy cập dữ liệu cá nhân hoặc lịch sử đầy đủ.

Sinh Tử biến quy trình thành chuỗi:

```text
check-in -> tính deadline -> nhắc nhở -> thời gian gia hạn -> cảnh báo người liên hệ
```

## Tính năng

### An toàn và check-in

- Thiết lập chu kỳ check-in theo giờ.
- Trạng thái **An toàn**, **Sắp đến hạn**, **Quá hạn** và **Chưa có dữ liệu**.
- Tính deadline tiếp theo sau mỗi lần xác nhận.
- Lưu lịch sử check-in cục bộ và đồng bộ Firestore.
- Sử dụng event theo từng deadline để chống cảnh báo trùng lặp.

### Check-in nhanh

- Android Home Screen Widget.
- Nút **Tôi vẫn an toàn** trên notification.
- Hiển thị xác nhận trên màn hình khóa tùy Android và cài đặt thiết bị.
- Dialog xác nhận trước khi ghi nhận để giảm thao tác nhầm.

### Offline-first

- Lưu check-in và cấu hình bằng SQLite.
- Hiển thị banner mất mạng và số bản ghi chờ đồng bộ.
- Tự động đồng bộ khi mạng trở lại.
- Đồng bộ thủ công trong màn hình lịch sử.

### Quyền chạy nền

- Kiểm tra quyền notification Android.
- Kiểm tra quyền báo đúng giờ/exact alarm.
- Hướng dẫn người dùng cấp quyền cần thiết trong Settings.

### Danh bạ khẩn cấp

- Thêm, sửa, tạm tắt hoặc xóa danh bạ.
- Gửi link xác minh email và consent opt-in.
- Chỉ liên hệ đã xác minh email và chấp thuận mới nhận cảnh báo.
- Không cho phép người liên hệ tự xác minh hoặc đồng ý consent qua client.

### Dashboard người thân

- Người thân xem trạng thái tóm tắt của người được theo dõi.
- Dùng Firestore trực tiếp nên không cần callable dashboard Function.
- Chủ tài khoản đồng bộ danh sách email đã xác minh/chấp thuận vào `trustedStatuses`.
- Hiển thị tên, quan hệ, lần check-in cuối, deadline và trạng thái an toàn/quá hạn/tạm dừng.

## Kiến trúc

```text
Flutter App
  ├── Firebase Authentication
  ├── Cloud Firestore
  ├── SQLite offline-first
  ├── Android AppWidget
  ├── Local notification và notification action
  └── Cloud Functions
        ├── xác minh liên hệ
        ├── consent opt-in
        ├── kiểm tra quá hạn
        └── gửi email cảnh báo
```

### Công nghệ sử dụng

- Flutter / Dart
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Functions và TypeScript
- SQLite qua `sqflite`
- Android AppWidget qua `home_widget`
- Local notification qua `flutter_local_notifications`
- Firebase Emulator Suite

## Demo Android bằng Firebase Production

Release không kết nối emulator mặc định. Chạy app production Firebase bằng:

```powershell
flutter run
```

Chạy với emulator Android:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

Android Emulator kết nối máy chủ qua `10.0.2.2`. Các cấu hình phải tồn tại trong:

- `android/app/google-services.json`
- `lib/firebase_options.dart`
- `.firebaserc`

Không commit credentials, SMTP password, Firebase Admin private key hoặc secret.

## Chạy demo local bằng Firebase Emulator

### Chuẩn bị SMTP

```powershell
Copy-Item functions/.env.local.example functions/.env.local
Copy-Item functions/.secret.local.example functions/.secret.local
```

Điền Google App Password trong `functions/.secret.local`. Không dùng mật khẩu đăng nhập Gmail trực tiếp.

Ví dụ:

```text
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=dia-chi-gmail@gmail.com
SMTP_FROM=dia-chi-gmail@gmail.com
SMTP_PASS=google-app-password
SEND_DEMO_ALERTS=true
SEND_REAL_ALERTS=true
```

### Khởi chạy emulator

```powershell
npm.cmd --prefix functions run build
firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --export-on-exit=.firebase-demo-data
```

Emulator UI:

```text
http://localhost:4000
```

Lần chạy sau có thể import dữ liệu demo:

```powershell
firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --import=.firebase-demo-data
```

## Kịch bản demo

1. Đăng ký tài khoản Email/Password.
2. Thêm một danh bạ khẩn cấp.
3. Gửi link xác minh email.
4. Mở link bằng máy đang chạy emulator.
5. Chấp thuận consent nhận cảnh báo.
6. Check-in từ app, notification hoặc Android Widget.
7. Mở tab **Người thân** để xem dashboard trạng thái.
8. Bật reminder và kiểm tra health permission trong Cài đặt.
9. Tùy chọn chạy demo email hoặc đặt deadline quá hạn trong emulator.

Luồng demo quá hạn có thể đặt gia hạn ngắn để kiểm tra cảnh báo. Cấu hình production giữ chu kỳ quét 15 phút và gia hạn 3 giờ.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build apk --debug
npm.cmd --prefix functions run build
npm.cmd --prefix functions test
firebase deploy --only firestore:rules
```

## Spark và Blaze

Dashboard người thân hiện đọc trực tiếp Firestore, không cần deploy Callable Function riêng và phù hợp cho Firebase Spark trong giới hạn quota demo.

Các scheduled Cloud Functions chạy cron, Secret Manager, API build hoặc email production có thể yêu cầu Firebase Blaze tùy tài nguyên và cấu hình project. Khi chưa có ngân sách cloud, nên dùng Firebase Emulator để demo các luồng server-side.

## Bảo mật và giới hạn

- Notification action trên lockscreen có thể làm giảm rủi ro bỏ sót check-in nhưng cũng có thể dẫn đến thao tác nhầm.
- Android có thể giới hạn notification/background task theo OEM, phiên bản hoặc chế độ tiết kiệm pin.
- Home Widget có giao diện và hành vi khác nhau tùy launcher.
- Dashboard người thân chỉ hiển thị trạng thái tóm tắt; không truy cập lịch sử check-in hoặc vị trí.
- Không được dùng Dead Man's Switch là giải pháp an toàn duy nhất trong tình huống khẩn cấp thực tế.
- Khi triển khai production, ứng dụng nên có cơ chế kiểm tra vị trí, thông báo đa kênh và quy trình bảo vệ dữ liệu cá nhân.

## Cấu trúc thư mục

```text
lib/
  app/
  models/
  screens/
  services/
  widgets/
functions/
  src/
android/
  app/src/main/
firestore.rules
firebase.json
```
