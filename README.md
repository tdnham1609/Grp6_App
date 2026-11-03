# Sinh Tử

**Sinh Tử** là ứng dụng Flutter hỗ trợ xác nhận an toàn định kỳ và cảnh báo người thân khẩn cấp khi người dùng không còn phản hồi đúng hạn. Ứng dụng kết hợp Flutter, Firebase Authentication, Cloud Firestore và Cloud Functions để tạo một luồng Dead Man's Switch đơn giản, trực quan và có thể mở rộng.

## Vấn đề ứng dụng giải quyết

- Người sống một mình có thể quên hoặc không có cơ hội mở app để xác nhận mình đang an toàn.
- Người thân khó biết tình trạng người cần theo dõi khi liên hệ thông thường không phản hồi.
- Việc theo dõi thủ công qua tin nhắn, cuộc gọi hoặc đồng hồ định kỳ thiếu tính nhất quán.
- Người dùng mất mạng vẫn cần lưu lại check-in để đồng bộ sau.
- Việc bấm mở app hoặc đợi cảnh báo có thể làm quá muộn thời điểm cần hỗ trợ.

Sinh Tử giúp chuyển quy trình này thành một chu kỳ định kỳ rõ ràng: người dùng check-in, hệ thống tính hạn tiếp theo, nhắc nhở trước hạn và kích hoạt cảnh báo nếu người dùng không xác nhận.

## Tính năng chính

### An toàn và check-in

- Đặt chu kỳ check-in theo giờ, thời gian nhắc nhở và trạng thái bật/tắt Switch.
- Ghi nhận lần xác nhận an toàn theo thời gian máy chủ.
- Theo dõi trạng thái **An toàn**, **Sắp đến hạn**, **Quá hạn** và **Không có dữ liệu**.
- Xem lịch sử check-in theo cục bộ và Firebase.

### Check-in nhanh

- Android home screen widget để xác nhận từ màn hình chính.
- Nút **Tôi vẫn an toàn** trên thông báo nhắc nhở Android.
- Có dialog xác nhận trước khi ghi nhận trên app để giảm thao tác nhầm.
- Thông báo có thể hiển thị trên màn hình khóa tùy cấu hình của thiết bị và Android.

### Hoạt động offline

- Lưu check-in và cấu hình vào SQLite.
- Hiển thị banner trạng thái mạng và số bản ghi đang chờ đồng bộ.
- Tự động đồng bộ các bản ghi pending khi mạng trở lại.
- Cho phép người dùng đồng bộ thủ công trong màn hình lịch sử.

### Thông báo và sức khỏe thiết bị

- Kiểm tra quyền thông báo Android.
- Kiểm tra quyền báo đúng giờ/exact alarm.
- Gợi ý người dùng cấp quyền cần thiết để nhắc nhở chạy đúng hạn.

### Danh bạ khẩn cấp và xác minh

- Thêm, sửa, tắt và xóa liên hệ khẩn cấp.
- Gửi liên kết xác minh email và consent opt-in.
- Chỉ liên hệ đã xác minh email và chấp thuận mới nhận cảnh báo.
- Che một phần địa chỉ email trong luồng xác minh.

### Dashboard người thân

- Người thân xem trạng thái tóm tắt của người được theo dõi.
- Dùng Firestore client-side, không bắt buộc deploy callable Function mới.
- Chủ tài khoản tự đồng bộ danh sách người thân đã xác minh và consent.
- Dashboard chỉ hiển thị trạng thái tóm tắt, lần check-in cuối và hạn tiếp theo.

## Kiến trúc dữ liệu

- Flutter App: giao diện, SQLite offline và Firebase client.
- Firebase Authentication: đăng ký, đăng nhập và danh tính người dùng.
- Cloud Firestore: hồ sơ, cấu hình, lịch sử, danh bạ và trạng thái dashboard.
- Cloud Functions: xác minh liên hệ, email và cảnh báo quá hạn khi môi trường server được cấu hình.
- Android AppWidget: check-in và trạng thái nhanh từ launcher.

## Công nghệ sử dụng

- Flutter / Dart
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Functions
- SQLite qua `sqflite`
- Android AppWidget / `home_widget`
- Local Notifications
- Firebase Emulator Suite
- Node.js / TypeScript cho Functions

## Cấu hình Firebase Production

Ứng dụng mặc định **không dùng Firebase Emulator** khi chạy bình thường. Để kết nối emulator trong quá trình phát triển Android:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

Bản Release kết nối trực tiếp Firebase production và yêu cầu giữ các file sau:

- `android/app/google-services.json`
- `lib/firebase_options.dart`
- `.firebaserc`

## Chạy emulator cho demo

Chuẩn bị email SMTP:

```powershell
Copy-Item functions/.env.local.example functions/.env.local
Copy-Item functions/.secret.local.example functions/.secret.local
```

Điền Gmail App Password vào `functions/.secret.local`, không commit file chứa credential. Sau đó chạy:

```powershell
npm.cmd --prefix functions run build
firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --export-on-exit=.firebase-demo-data
```

Emulator UI mặc định tại `http://localhost:4000`. Android Emulator kết nối máy host qua `10.0.2.2`. Có thể import dữ liệu lần sau bằng:

```powershell
firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --import=.firebase-demo-data
```

## Kịch bản demo

1. Chạy app với emulator hoặc production Firebase.
2. Đăng ký tài khoản Email/Password.
3. Thêm danh bạ khẩn cấp.
4. Gửi link xác minh email.
5. Chấp thuận consent từ liên kết xác minh.
6. Check-in từ app, notification hoặc Android widget.
7. Mở **Người thân** để xem dashboard trạng thái tóm tắt.
8. Tùy chọn chạy cảnh báo demo hoặc đặt lịch quá hạn trong emulator.

## Câu lệnh kiểm tra

```powershell
flutter test
flutter analyze
flutter build apk --debug
npm.cmd --prefix functions run build
npm.cmd --prefix functions test
```

## Lưu ý Spark / Blaze

Dashboard người thân hiện đọc trực tiếp Firestore nên có thể chạy trên Firebase Spark (gói miễn phí) trong điều kiện quota demo. Các scheduled Cloud Functions chạy định kỳ và gửi email production vẫn có thể yêu cầu Firebase Blaze tùy cơ chế billing/API của project. Vì vậy nên dùng emulator để demo chức năng này khi chưa có ngân sách cloud.

## Bảo mật

Không commit:

- SMTP password hoặc token
- Google App Password
- Firebase Admin credential
- File chứa API secrets trong thư mục Functions
- APK hoặc build output

Tất cả giao thức xác minh consent và cảnh báo cần được xem xét lại trước triển khai production, đặc biệt khi ứng dụng xử lý dữ liệu sức khỏe, vị trí và thông tin liên hệ cá nhân.
