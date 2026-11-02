import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deadmansswitch/models/check_in_config.dart';

void main() {
  group('CheckInConfig Model & Logic thời hạn', () {
    final t0 = DateTime(2025, 5, 20, 10, 0, 0);

    test('Tính toán thời hạn tiếp theo chính xác theo số giờ chu kỳ', () {
      final due12 = CheckInConfig.computeNextDue(t0, 12);
      expect(due12, equals(DateTime(2025, 5, 20, 22, 0, 0)));

      final due24 = CheckInConfig.computeNextDue(t0, 24);
      expect(due24, equals(DateTime(2025, 5, 21, 10, 0, 0)));

      final due48 = CheckInConfig.computeNextDue(t0, 48);
      expect(due48, equals(DateTime(2025, 5, 22, 10, 0, 0)));

      final due72 = CheckInConfig.computeNextDue(t0, 72);
      expect(due72, equals(DateTime(2025, 5, 23, 10, 0, 0)));
    });

    test('Xác định đúng trạng thái onTime (Đúng hạn / An toàn)', () {
      final due = t0.add(const Duration(hours: 24)); // 10:00 ngày hôm sau
      final config = CheckInConfig(
        intervalHours: 24,
        reminderMinutesBefore: 120, // 2 giờ trước hạn (08:00)
        lastCheckInAt: t0,
        nextCheckInDueAt: due,
        updatedAt: t0,
      );

      // Tại thời điểm 15:00 cùng ngày (còn 19 tiếng)
      final status = config.getStatus(t0.add(const Duration(hours: 5)));
      expect(status, equals(CheckInStatus.onTime));
    });

    test(
      'Xác định đúng trạng thái dueSoon (Sắp đến hạn trong ngưỡng nhắc nhở)',
      () {
        final due = t0.add(const Duration(hours: 24)); // 10:00 ngày hôm sau
        final config = CheckInConfig(
          intervalHours: 24,
          reminderMinutesBefore: 120, // 2 giờ trước hạn (08:00)
          lastCheckInAt: t0,
          nextCheckInDueAt: due,
          updatedAt: t0,
        );

        // Tại thời điểm 08:30 ngày hôm sau (còn 90 phút, nằm trong ngưỡng 120 phút)
        final status = config.getStatus(
          due.subtract(const Duration(minutes: 90)),
        );
        expect(status, equals(CheckInStatus.dueSoon));
      },
    );

    test('Xác định đúng trạng thái overdue (Đã quá hạn)', () {
      final due = t0.add(const Duration(hours: 24)); // 10:00 ngày hôm sau
      final config = CheckInConfig(
        intervalHours: 24,
        reminderMinutesBefore: 120,
        lastCheckInAt: t0,
        nextCheckInDueAt: due,
        updatedAt: t0,
      );

      // Tại thời điểm 10:05 ngày hôm sau (quá hạn 5 phút)
      final status = config.getStatus(due.add(const Duration(minutes: 5)));
      expect(status, equals(CheckInStatus.overdue));
    });

    test('Xác định trạng thái noData khi chưa từng check-in', () {
      final config = CheckInConfig.defaultConfig();
      expect(config.getStatus(), equals(CheckInStatus.noData));
    });

    test('getRemainingFormatted hiển thị thời gian còn lại thân thiện', () {
      final due = t0.add(const Duration(hours: 24));
      final config = CheckInConfig(
        intervalHours: 24,
        reminderMinutesBefore: 120,
        lastCheckInAt: t0,
        nextCheckInDueAt: due,
        updatedAt: t0,
      );

      // Còn 5 giờ 30 phút
      final testTime1 = due.subtract(const Duration(hours: 5, minutes: 30));
      expect(
        config.getRemainingFormatted(testTime1),
        equals('Còn 5 giờ 30 phút'),
      );

      // Còn 45 phút
      final testTime2 = due.subtract(const Duration(minutes: 45));
      expect(config.getRemainingFormatted(testTime2), equals('Còn 45 phút'));

      // Quá hạn 2 giờ 15 phút
      final testTime3 = due.add(const Duration(hours: 2, minutes: 15));
      expect(
        config.getRemainingFormatted(testTime3),
        equals('Quá hạn 2 giờ 15 phút'),
      );
    });

    test(
      'Thay đổi chu kỳ tính lại thời hạn dựa trên lần check-in gần nhất',
      () {
        final config24 = CheckInConfig(
          intervalHours: 24,
          reminderMinutesBefore: 120,
          lastCheckInAt: t0,
          nextCheckInDueAt: t0.add(const Duration(hours: 24)),
          updatedAt: t0,
        );

        // Đổi chu kỳ sang 12 giờ
        final newDue = CheckInConfig.computeNextDue(
          config24.lastCheckInAt!,
          12,
        );
        final config12 = config24.copyWith(
          intervalHours: 12,
          nextCheckInDueAt: newDue,
        );

        expect(config12.intervalHours, equals(12));
        expect(
          config12.nextCheckInDueAt,
          equals(t0.add(const Duration(hours: 12))),
        );
      },
    );

    test('Bật / Tắt nhắc nhở an toàn', () {
      final config = CheckInConfig.defaultConfig();
      expect(config.isReminderEnabled, isTrue);

      final disabledConfig = config.copyWith(isReminderEnabled: false);
      expect(disabledConfig.isReminderEnabled, isFalse);
    });

    test('Chuyển đổi SQLite toSqlite và fromSqlite toàn vẹn dữ liệu', () {
      final original = CheckInConfig(
        intervalHours: 48,
        reminderMinutesBefore: 60,
        isReminderEnabled: true,
        lastCheckInAt: t0,
        nextCheckInDueAt: t0.add(const Duration(hours: 48)),
        updatedAt: t0,
      );

      final row = original.toSqlite('user_test_uid');
      expect(row['uid'], equals('user_test_uid'));
      expect(row['interval_hours'], equals(48));
      expect(row['reminder_minutes'], equals(60));
      expect(row['is_reminder_enabled'], equals(1));
      expect(row['last_checkin_at'], equals(t0.toIso8601String()));

      final restored = CheckInConfig.fromSqlite(row);
      expect(restored.intervalHours, equals(48));
      expect(restored.reminderMinutesBefore, equals(60));
      expect(restored.isReminderEnabled, isTrue);
      expect(restored.lastCheckInAt, equals(t0));
      expect(
        restored.nextCheckInDueAt,
        equals(t0.add(const Duration(hours: 48))),
      );
    });

    test('Chuyển đổi Firestore toFirestoreMap và fromMap với Timestamp', () {
      final original = CheckInConfig(
        intervalHours: 12,
        reminderMinutesBefore: 30,
        isReminderEnabled: false,
        lastCheckInAt: t0,
        nextCheckInDueAt: t0.add(const Duration(hours: 12)),
        updatedAt: t0,
      );

      final map = original.toFirestoreMap();
      expect(map['intervalHours'], equals(12));
      expect(map['reminderMinutesBefore'], equals(30));
      expect(map['isReminderEnabled'], isFalse);
      expect(map['isDeadManSwitchActive'], isTrue);
      expect(map['gracePeriodMinutes'], equals(180));
      expect(map['lastCheckInAt'], isA<Timestamp>());
      expect(map['nextCheckInDueAt'], isA<Timestamp>());

      final restored = CheckInConfig.fromMap(map);
      expect(restored.intervalHours, equals(12));
      expect(restored.reminderMinutesBefore, equals(30));
      expect(restored.isReminderEnabled, isFalse);
      expect(restored.isDeadManSwitchActive, isTrue);
      expect(restored.gracePeriodMinutes, equals(180));
      expect(restored.lastCheckInAt, equals(t0));
      expect(
        restored.nextCheckInDueAt,
        equals(t0.add(const Duration(hours: 12))),
      );
    });

    test(
      'Cô lập cấu hình theo UID không để rò rỉ giữa người dùng khác nhau',
      () {
        final configUserA = CheckInConfig(
          intervalHours: 12,
          lastCheckInAt: t0,
          nextCheckInDueAt: t0.add(const Duration(hours: 12)),
          updatedAt: t0,
        );

        final configUserB = CheckInConfig(
          intervalHours: 72,
          lastCheckInAt: t0,
          nextCheckInDueAt: t0.add(const Duration(hours: 72)),
          updatedAt: t0,
        );

        final sqliteTable = <String, Map<String, dynamic>>{
          'user_A': configUserA.toSqlite('user_A'),
          'user_B': configUserB.toSqlite('user_B'),
        };

        // Đọc cấu hình user A
        final loadedA = CheckInConfig.fromSqlite(sqliteTable['user_A']!);
        expect(loadedA.intervalHours, equals(12));

        // Đọc cấu hình user B
        final loadedB = CheckInConfig.fromSqlite(sqliteTable['user_B']!);
        expect(loadedB.intervalHours, equals(72));

        // Không bị lẫn lộn giữa hai người dùng
        expect(loadedA.intervalHours, isNot(equals(loadedB.intervalHours)));
      },
    );
  });
}
