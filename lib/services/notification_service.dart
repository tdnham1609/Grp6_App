import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Service quản lý thông báo cục bộ (Local Notifications)
/// Nhắc nhở người dùng trước khi đến thời hạn điểm danh an toàn
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// ID duy nhất cho thông báo nhắc nhở check-in (tránh tạo nhiều thông báo trùng)
  static const int reminderNotificationId = 1001;

  /// Khởi tạo cấu hình thông báo
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Khởi tạo cơ sở dữ liệu múi giờ
      tz_data.initializeTimeZones();

      // 2. Cấu hình icon và channel cho Android
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // 3. Cấu hình cho iOS / macOS
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Đã bấm vào thông báo: ${response.payload}');
        },
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint(
        'Khởi tạo NotificationService thất bại (Môi trường test/không hỗ trợ): $e',
      );
    }
  }

  /// Yêu cầu người dùng cấp quyền thông báo
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) return false;

      if (Platform.isAndroid) {
        final androidImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await androidImpl?.requestNotificationsPermission();
        return granted ?? false;
      }

      if (Platform.isIOS) {
        final iosImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('Yêu cầu quyền thông báo thất bại: $e');
    }
    return false;
  }

  /// Lên lịch thông báo nhắc nhở trước thời hạn check-in
  /// - Tự động huỷ lịch cũ trước khi đặt lịch mới (tránh trùng)
  /// - Bỏ qua nếu thời điểm nhắc nhở nằm trong quá khứ
  Future<void> scheduleReminder({
    required DateTime dueTime,
    required int reminderMinutesBefore,
    String? title,
    String? body,
  }) async {
    try {
      await initialize();

      // Luôn huỷ thông báo cũ trước
      await cancelReminder();

      final reminderTime = dueTime.subtract(
        Duration(minutes: reminderMinutesBefore),
      );
      final now = DateTime.now();

      // Nếu thời điểm nhắc nhở đã qua thì không lên lịch trong quá khứ
      if (reminderTime.isBefore(now)) {
        debugPrint(
          'Thời điểm nhắc nhở ($reminderTime) đã qua thời gian hiện tại ($now). Bỏ qua lên lịch.',
        );
        return;
      }

      final scheduledTZ = tz.TZDateTime.from(reminderTime, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'sinh_tu_checkin_reminders',
        'Nhắc nhở an toàn Sinh Tử',
        channelDescription:
            'Thông báo nhắc bạn xác nhận trạng thái an toàn trước khi hết hạn',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final notifTitle = title ?? 'Sinh Tử: Sắp đến hạn xác nhận an toàn';
      final notifBody =
          body ??
          'Chỉ còn ${reminderMinutesBefore ~/ 60 > 0 ? '${reminderMinutesBefore ~/ 60} giờ ' : ''}${reminderMinutesBefore % 60 > 0 ? '${reminderMinutesBefore % 60} phút' : ''} trước khi hết hạn. Hãy mở app và bấm "Tôi vẫn an toàn".';

      try {
        await _notificationsPlugin.zonedSchedule(
          id: reminderNotificationId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledTZ,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint(
          'Đã lên lịch thông báo thành công vào thời điểm: $reminderTime',
        );
      } catch (scheduleErr) {
        // Fallback sang inexact nếu hệ thống không cho phép exact alarm
        await _notificationsPlugin.zonedSchedule(
          id: reminderNotificationId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledTZ,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint(
          'Đã lên lịch thông báo (inexact) vào thời điểm: $reminderTime',
        );
      }
    } catch (e) {
      debugPrint('Lỗi khi lên lịch thông báo nhắc nhở: $e');
    }
  }

  /// Huỷ thông báo nhắc nhở hiện tại
  Future<void> cancelReminder() async {
    try {
      await _notificationsPlugin.cancel(id: reminderNotificationId);
      debugPrint('Đã huỷ thông báo nhắc nhở #$reminderNotificationId');
    } catch (e) {
      debugPrint('Lỗi huỷ thông báo: $e');
    }
  }
}
