import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/check_in_config.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// Service quản lý cấu hình chu kỳ check-in, tính toán thời hạn tiếp theo
/// và điều phối thông báo nhắc nhở an toàn
class CheckInConfigService {
  final DatabaseService? _customDbService;
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final NotificationService? _customNotificationService;

  static final CheckInConfigService instance = CheckInConfigService();

  CheckInConfigService({
    DatabaseService? dbService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  }) : _customDbService = dbService,
       _customFirestore = firestore,
       _customAuth = auth,
       _customNotificationService = notificationService;

  DatabaseService get _dbService =>
      _customDbService ?? DatabaseService.instance;

  NotificationService get _notificationService =>
      _customNotificationService ?? NotificationService.instance;

  FirebaseFirestore? get _firestore {
    if (_customFirestore != null) return _customFirestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  /// Lấy cấu hình check-in hiện tại của người dùng
  /// - Phản hồi ngay từ SQLite cục bộ (offline-first)
  /// - Tải từ Firestore nếu có kết nối mạng và cập nhật cache cục bộ
  Future<CheckInConfig> getConfig() async {
    final user = _auth?.currentUser;
    final uid = user?.uid ?? 'guest';

    // 1. Đọc từ SQLite cục bộ
    CheckInConfig? localConfig;
    try {
      localConfig = await _dbService.getCheckInConfig(uid);
    } catch (e) {
      debugPrint('Lỗi đọc cấu hình từ SQLite: $e');
    }

    // Nếu là guest hoặc không có Firestore, trả về localConfig hoặc mặc định
    final firestore = _firestore;
    if (user == null || firestore == null) {
      return localConfig ?? CheckInConfig.defaultConfig();
    }

    // 2. Thử tải cấu hình từ Firestore: users/{uid}/settings/checkin
    try {
      final doc = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('checkin')
          .get()
          .timeout(const Duration(seconds: 7));

      if (doc.exists) {
        final remoteConfig = CheckInConfig.fromFirestore(doc);

        // Nếu bản ghi trên Firestore mới hơn hoặc cục bộ chưa có thì lưu lại cục bộ
        if (localConfig == null ||
            remoteConfig.updatedAt.isAfter(localConfig.updatedAt)) {
          await _dbService.saveCheckInConfig(user.uid, remoteConfig);
          return remoteConfig;
        }
      } else if (localConfig != null) {
        // Chưa có trên Firestore nhưng có cục bộ -> đồng bộ lên Firestore
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('checkin')
            .set(localConfig.toFirestoreMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 7));
      }
    } catch (e) {
      debugPrint(
        'Không thể tải cấu hình từ Firestore (sử dụng cache cục bộ): $e',
      );
    }

    if (localConfig != null) {
      return localConfig;
    }

    // 3. Nếu chưa có ở cả hai nơi, khởi tạo cấu hình mặc định (kết hợp với lần check-in gần nhất)
    final latestCheckIn = await _dbService.getLatestCheckIn(uid);
    final lastTime = latestCheckIn?.checkedInAt;
    final nextDue = lastTime != null
        ? CheckInConfig.computeNextDue(lastTime, 24)
        : null;

    final initialConfig = CheckInConfig(
      intervalHours: 24,
      reminderMinutesBefore: 120,
      isReminderEnabled: true,
      lastCheckInAt: lastTime,
      nextCheckInDueAt: nextDue,
      updatedAt: DateTime.now(),
    );

    try {
      await _dbService.saveCheckInConfig(uid, initialConfig);
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('checkin')
          .set(initialConfig.toFirestoreMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 7));
    } catch (_) {}

    return initialConfig;
  }

  /// Cập nhật cài đặt chu kỳ hoặc nhắc nhở
  /// Quy tắc tính thời hạn khi đổi chu kỳ:
  /// - Nếu đã có `lastCheckInAt`, tính lại `nextCheckInDueAt = lastCheckInAt + newIntervalHours`
  /// - Huỷ lịch nhắc nhở cũ và đặt lịch nhắc mới phù hợp với thời hạn mới
  Future<CheckInConfig> updateConfig({
    int? intervalHours,
    int? reminderMinutesBefore,
    bool? isReminderEnabled,
  }) async {
    final user = _auth?.currentUser;
    final uid = user?.uid ?? 'guest';

    final current = await getConfig();
    final newInterval = intervalHours ?? current.intervalHours;
    final newReminderMinutes =
        reminderMinutesBefore ?? current.reminderMinutesBefore;
    final newReminderEnabled = isReminderEnabled ?? current.isReminderEnabled;

    // Tính lại thời hạn tiếp theo
    DateTime? newNextDue;
    if (current.lastCheckInAt != null) {
      newNextDue = CheckInConfig.computeNextDue(
        current.lastCheckInAt!,
        newInterval,
      );
    }

    final updated = current.copyWith(
      intervalHours: newInterval,
      reminderMinutesBefore: newReminderMinutes,
      isReminderEnabled: newReminderEnabled,
      nextCheckInDueAt: newNextDue,
      updatedAt: DateTime.now(),
    );

    // 1. Lưu SQLite cục bộ
    try {
      await _dbService.saveCheckInConfig(uid, updated);
    } catch (e) {
      debugPrint('Lỗi lưu cấu hình vào SQLite: $e');
    }

    // 2. Thử lưu Firestore
    final firestore = _firestore;
    if (user != null && firestore != null) {
      try {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('checkin')
            .set(updated.toFirestoreMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 7));
      } catch (e) {
        debugPrint('Chưa thể đồng bộ cấu hình lên Firestore: $e');
      }
    }

    // 3. Lập lịch hoặc huỷ thông báo nhắc nhở
    if (updated.isReminderEnabled && updated.nextCheckInDueAt != null) {
      await _notificationService.scheduleReminder(
        dueTime: updated.nextCheckInDueAt!,
        reminderMinutesBefore: updated.reminderMinutesBefore,
      );
    } else {
      await _notificationService.cancelReminder();
    }

    return updated;
  }

  /// Cập nhật thời hạn khi người dùng thực hiện check-in thành công
  Future<CheckInConfig> updateOnCheckIn(DateTime checkInTime) async {
    final user = _auth?.currentUser;
    final uid = user?.uid ?? 'guest';

    final current = await getConfig();
    final nextDue = CheckInConfig.computeNextDue(
      checkInTime,
      current.intervalHours,
    );

    final updated = current.copyWith(
      lastCheckInAt: checkInTime,
      nextCheckInDueAt: nextDue,
      updatedAt: DateTime.now(),
    );

    // Lưu cục bộ
    try {
      await _dbService.saveCheckInConfig(uid, updated);
    } catch (e) {
      debugPrint('Lỗi lưu cấu hình sau check-in: $e');
    }

    // Đồng bộ Firestore
    final firestore = _firestore;
    if (user != null && firestore != null) {
      try {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('checkin')
            .set(updated.toFirestoreMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 7));
      } catch (e) {
        debugPrint('Chưa thể đồng bộ hạn check-in lên Firestore: $e');
      }
    }

    // Lên lịch nhắc nhở cho chu kỳ mới
    if (updated.isReminderEnabled) {
      await _notificationService.scheduleReminder(
        dueTime: nextDue,
        reminderMinutesBefore: updated.reminderMinutesBefore,
      );
    }

    return updated;
  }
}
