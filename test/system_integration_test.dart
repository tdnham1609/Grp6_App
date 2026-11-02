import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deadmansswitch/models/check_in.dart';
import 'package:deadmansswitch/models/check_in_config.dart';
import 'package:deadmansswitch/models/location_data.dart';
import 'package:deadmansswitch/models/emergency_contact.dart';

void main() {
  group('Hệ thống Tích hợp Sinh Tử - Luồng Kiểm toán Toàn Diện', () {
    final t0 = DateTime(2026, 10, 27, 8, 0, 0);

    test('1. Luồng Check-in: Ghi nhận check-in mới cập nhật chính xác lastCheckInAt và nextCheckInDueAt', () {
      // 1. Người dùng thực hiện check-in tại t0
      final checkIn = CheckIn.create(uid: 'user_audit_1', checkedInAt: t0);
      expect(checkIn.uid, equals('user_audit_1'));
      expect(checkIn.checkedInAt, equals(t0));
      expect(checkIn.syncStatus, equals(SyncStatus.pending));

      // 2. Cấu hình chu kỳ 24 giờ
      const intervalHours = 24;
      final nextDue = CheckInConfig.computeNextDue(t0, intervalHours);
      expect(nextDue, equals(DateTime(2026, 10, 28, 8, 0, 0)));

      final config = CheckInConfig(
        intervalHours: intervalHours,
        reminderMinutesBefore: 120, // 2 giờ trước hạn
        isReminderEnabled: true,
        lastCheckInAt: t0,
        nextCheckInDueAt: nextDue,
        updatedAt: t0,
      );

      // 3. Trạng thái tại t0 + 10 giờ: onTime
      final tPlus10h = t0.add(const Duration(hours: 10));
      expect(config.getStatus(tPlus10h), equals(CheckInStatus.onTime));

      // 4. Trạng thái tại t0 + 22.5 giờ (còn 90 phút trước hạn): dueSoon
      final tDueSoon = t0.add(const Duration(hours: 22, minutes: 30));
      expect(config.getStatus(tDueSoon), equals(CheckInStatus.dueSoon));

      // 5. Trạng thái tại t0 + 24 giờ 1 phút (quá hạn): overdue
      final tOverdue = t0.add(const Duration(hours: 24, minutes: 1));
      expect(config.getStatus(tOverdue), equals(CheckInStatus.overdue));

      // 6. Kiểm tra payload đồng bộ lên Firestore đúng chuẩn Timestamp
      final firestoreMap = config.toFirestoreMap();
      expect(firestoreMap['lastCheckInAt'], isA<Timestamp>());
      expect((firestoreMap['lastCheckInAt'] as Timestamp).toDate(), equals(t0));
      expect(firestoreMap['nextCheckInDueAt'], isA<Timestamp>());
      expect((firestoreMap['nextCheckInDueAt'] as Timestamp).toDate(), equals(nextDue));
    });

    test('2. Luồng Location: Kiểm tra bảo vệ dữ liệu cũ không ghi đè dữ liệu mới', () {
      final locOlder = LocationData(
        latitude: 21.0285,
        longitude: 105.8542,
        accuracy: 10.0,
        timestamp: DateTime(2026, 10, 27, 8, 0, 0),
      );

      final locNewer = LocationData(
        latitude: 21.0300,
        longitude: 105.8500,
        accuracy: 5.0,
        timestamp: DateTime(2026, 10, 27, 8, 30, 0),
      );

      // locNewer phải mới hơn locOlder
      expect(locNewer.isNewerThan(locOlder), isTrue);
      expect(locOlder.isNewerThan(locNewer), isFalse);

      // Mô phỏng logic saveLastLocation trong DatabaseService
      // Khi đã có locNewer trong DB, nếu nhận được locOlder do độ trễ mạng/GPS thì không cho phép ghi đè
      LocationData currentInDb = locNewer;
      bool shouldOverwrite(LocationData incoming) {
        return incoming.isNewerThan(currentInDb);
      }

      expect(shouldOverwrite(locOlder), isFalse, reason: 'Dữ liệu cũ hơn không được ghi đè');

      final locEvenNewer = LocationData(
        latitude: 21.0310,
        longitude: 105.8490,
        accuracy: 8.0,
        timestamp: DateTime(2026, 10, 27, 9, 0, 0),
      );
      expect(shouldOverwrite(locEvenNewer), isTrue, reason: 'Dữ liệu mới hơn được phép ghi đè');
    });

    test('3. Migration SQLite v5: Các cột location và toggle được ánh xạ chính xác', () {
      final loc = LocationData(
        latitude: 10.7769,
        longitude: 106.7009,
        accuracy: 12.5,
        timestamp: DateTime(2026, 10, 27, 10, 0, 0),
      );

      final sqliteMap = loc.toSqlite();
      expect(sqliteMap.containsKey('latitude'), isTrue);
      expect(sqliteMap.containsKey('longitude'), isTrue);
      expect(sqliteMap.containsKey('accuracy'), isTrue);
      expect(sqliteMap.containsKey('location_timestamp'), isTrue);

      // Kiểm tra phục hồi từ SQLite row
      final restored = LocationData.fromSqlite(sqliteMap);
      expect(restored, isNotNull);
      expect(restored!.latitude, equals(10.7769));
      expect(restored.longitude, equals(106.7009));
      expect(restored.accuracy, equals(12.5));
      expect(restored.timestamp, equals(DateTime(2026, 10, 27, 10, 0, 0)));
    });

    test('4. Bảo mật Danh bạ Khẩn cấp: Không cho phép Client tự gán verified/accepted', () {
      // Khi client tạo liên hệ mới, luôn khởi tạo ở trạng thái an toàn
      final contact = EmergencyContact.create(
        uid: 'user_audit_1',
        name: 'Trần Văn Cảnh Báo',
        email: 'alert@example.com',
        phoneNumber: '0901234567',
        relationship: 'Người thân',
      );

      // Client-side defaults
      expect(contact.emailVerified, isFalse);
      expect(contact.consentStatus, equals(ConsentStatus.pending));

      // Ánh xạ sang Firestore map
      final fireMap = contact.toFirestoreMap();
      expect(fireMap['emailVerified'], isFalse);
      expect(fireMap['consentStatus'], equals('pending'));
    });

    test('5. Cô lập dữ liệu: Dữ liệu của 2 người dùng độc lập không can thiệp lẫn nhau', () {
      final checkInUserA = CheckIn.create(uid: 'user_A', checkedInAt: t0);
      final checkInUserB = CheckIn.create(uid: 'user_B', checkedInAt: t0);

      expect(checkInUserA.uid, isNot(equals(checkInUserB.uid)));
      expect(checkInUserA.id, isNot(equals(checkInUserB.id)));

      final contactUserA = EmergencyContact.create(
        uid: 'user_A',
        name: 'Người thân A',
        email: 'a@gmail.com',
        relationship: 'Bố',
      );
      final contactUserB = EmergencyContact.create(
        uid: 'user_B',
        name: 'Người thân B',
        email: 'b@gmail.com',
        relationship: 'Mẹ',
      );

      expect(contactUserA.uid, isNot(equals(contactUserB.uid)));
    });
  });
}
