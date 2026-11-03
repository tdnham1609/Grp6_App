import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/check_in_config.dart';
import '../models/emergency_contact.dart';
import '../models/location_data.dart';
import '../services/auth_service.dart';
import '../services/check_in_config_service.dart';
import '../services/database_service.dart';
import '../services/demo_alert_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  final _configService = CheckInConfigService.instance;
  final _locationService = LocationService.instance;
  final _dbService = DatabaseService.instance;
  final _demoAlertService = DemoAlertService();

  CheckInConfig? _config;
  bool _isLoading = true;

  // Location state
  bool _isLocationSharingEnabled = false;
  LocationPermissionStatus _locationPermissionStatus =
      LocationPermissionStatus.notDetermined;
  LocationData? _lastLocation;
  bool _isGettingLocation = false;
  bool _isSendingDemoAlert = false;
  bool _isPreparingOverdueDemo = false;
  bool _isOverdueDemoScheduled = false;
  bool _notificationsEnabled = false;
  bool _exactAlarmEnabled = false;
  bool _healthLoaded = false;

  bool get _showOverdueDemo => kDebugMode && _useFirebaseEmulators;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadLocationState();
    _loadSafetyHealth();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _configService.getConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSafetyHealth() async {
    final notifications = await NotificationService.instance
        .hasNotificationPermission();
    final exactAlarm = await NotificationService.instance
        .hasExactAlarmPermission();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notifications;
      _exactAlarmEnabled = exactAlarm;
      _healthLoaded = true;
    });
  }

  Future<void> _loadLocationState() async {
    final user = AuthService().currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    try {
      final enabled = await _dbService.isLocationSharingEnabled(uid);
      final permStatus = await _locationService.checkPermission();
      final lastLoc = await _dbService.getLastLocation(uid);

      if (mounted) {
        setState(() {
          _isLocationSharingEnabled = enabled;
          _locationPermissionStatus = permStatus;
          _lastLocation = lastLoc;
        });
      }
    } catch (_) {
      // Không để lỗi location ảnh hưởng màn hình Settings
    }
  }

  Future<void> _handleLocationSharingToggle(bool enabled) async {
    final user = AuthService().currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    if (enabled) {
      // Xin quyền khi người dùng bật
      final permStatus = await _locationService.requestPermission();
      if (mounted) {
        setState(() => _locationPermissionStatus = permStatus);
      }

      if (permStatus == LocationPermissionStatus.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Quyền vị trí bị từ chối vĩnh viễn. Vui lòng bật trong Cài đặt hệ thống → Ứng dụng → Quyền.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      if (permStatus == LocationPermissionStatus.serviceDisabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dịch vụ GPS đang tắt. Vui lòng bật GPS trên thiết bị.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      if (permStatus != LocationPermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cần cấp quyền vị trí để bật chia sẻ vị trí.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orangeAccent,
            ),
          );
          return;
        }
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('checkin')
          .set({'isLocationSharingEnabled': enabled}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 7));
    } catch (error) {
      debugPrint(
        'Không thể lưu trạng thái chia sẻ vị trí lên Firebase: $error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể lưu cài đặt vị trí lên Firebase. Hãy kiểm tra emulator/kết nối rồi thử lại.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      await _dbService.saveLocationSharingEnabled(uid, enabled);
    } catch (error) {
      debugPrint('Không thể lưu cài đặt chia sẻ vị trí vào SQLite: $error');
    }

    if (mounted) {
      setState(() => _isLocationSharingEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Đã bật chia sẻ vị trí. Vị trí sẽ được đính kèm khi có cảnh báo.'
                : 'Đã tắt chia sẻ vị trí.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF078D83),
        ),
      );
    }
  }

  Future<void> _handleTestLocation() async {
    final user = AuthService().currentUser;
    final uid = user?.uid;
    if (uid == null) return;
    if (!_isLocationSharingEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hãy bật chia sẻ vị trí trước khi cập nhật GPS.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isGettingLocation = true);

    final result = await _locationService.getCurrentLocation();

    if (!mounted) return;

    setState(() => _isGettingLocation = false);

    if (result.isSuccess && result.location != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('checkin')
            .set({
              'isLocationSharingEnabled': true,
              'lastKnownLocation': {
                'latitude': result.location!.latitude,
                'longitude': result.location!.longitude,
                if (result.location!.accuracy != null)
                  'accuracy': result.location!.accuracy,
                'timestamp': Timestamp.fromDate(result.location!.timestamp),
              },
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 7));
      } catch (error) {
        debugPrint('Không thể đồng bộ GPS lên Firebase: $error');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã lấy được GPS nhưng chưa lưu lên Firebase; email cảnh báo sẽ chưa có vị trí. Hãy kiểm tra emulator/kết nối rồi thử lại.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      try {
        await _dbService.saveLastLocation(uid, result.location!);
      } catch (error) {
        debugPrint('Không thể lưu GPS vào SQLite: $error');
      }

      if (!mounted) return;
      setState(() => _lastLocation = result.location);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã lấy vị trí thành công! Độ chính xác: ${result.location!.accuracyFormatted}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF078D83),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Không thể lấy vị trí.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleDemoAlert() async {
    setState(() => _isSendingDemoAlert = true);
    try {
      final uid = AuthService().currentUser?.uid;
      if (uid == null) return;
      final contactsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('emergency_contacts')
          .where('isActive', isEqualTo: true)
          .get();
      final eligibleContacts = contactsSnapshot.docs
          .map(EmergencyContact.fromFirestore)
          .where(
            (contact) =>
                contact.emailVerified &&
                contact.consentStatus == ConsentStatus.accepted,
          )
          .toList();

      if (!mounted) return;
      if (eligibleContacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cần ít nhất một liên hệ đã xác minh email và đồng ý nhận cảnh báo.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final recipientList = eligibleContacts
          .map((contact) => '${contact.name} — ${contact.email}')
          .join('\n');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Gửi email cảnh báo demo?'),
          content: Text(
            'Email thật sẽ được gửi tới các liên hệ đã xác minh và đồng ý nhận cảnh báo:\n\n'
            '$recipientList\n\n'
            'Email sẽ ghi rõ đây là bản demo, không phải cảnh báo khẩn cấp thật.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Gửi email thật'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await _demoAlertService.sendDemoAlert();
      if (!mounted) return;
      final allSent =
          result.sentCount == result.totalCount && result.failedCount == 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allSent
                ? 'Đã gửi email demo tới ${result.sentCount} liên hệ.'
                : 'Đã gửi ${result.sentCount}/${result.totalCount} email; ${result.failedCount} email lỗi.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: allSent
              ? const Color(0xFF078D83)
              : Colors.deepOrange,
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Không thể gửi email demo.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gửi email demo: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingDemoAlert = false);
    }
  }

  Future<void> _handleOverdueDemo() async {
    if (_isPreparingOverdueDemo || _isOverdueDemoScheduled) return;
    setState(() => _isPreparingOverdueDemo = true);
    try {
      final user = AuthService().currentUser;
      if (user == null) {
        throw StateError('Vui lòng đăng nhập trước khi bắt đầu demo.');
      }

      final config = await _configService.getConfig();
      final now = DateTime.now();
      final demoDueAt = now.subtract(const Duration(seconds: 10));
      final checkInSettings = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('checkin');

      await checkInSettings.set({
        ...config.toFirestoreMap(),
        'nextCheckInDueAt': Timestamp.fromDate(demoDueAt),
        'gracePeriodMinutes': 1,
        'isDeadManSwitchActive': true,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _config = config.copyWith(nextCheckInDueAt: demoDueAt, updatedAt: now);
        _isOverdueDemoScheduled = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã bắt đầu demo quá hạn. Giữ app và emulator mở; email sẽ được gửi sau khoảng 1 phút.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      unawaited(_sendOverdueDemoAfterGrace());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể bắt đầu demo quá hạn: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPreparingOverdueDemo = false);
    }
  }

  Future<void> _sendOverdueDemoAfterGrace() async {
    await Future<void>.delayed(const Duration(seconds: 65));

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable(
            'runOverdueDemoCheck',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>();
      final result = response.data;
      final action = result['action'] as String?;
      final status = result['status'] as String?;
      final recipientsCount = (result['recipientsCount'] as num?)?.toInt() ?? 0;

      final String message;
      if (status == 'alert_sent' && recipientsCount > 0) {
        message =
            'Demo quá hạn hoàn tất: đã gửi email cảnh báo đến $recipientsCount liên hệ.';
      } else if (status == 'partially_sent') {
        message = 'Demo hoàn tất một phần: đã gửi được $recipientsCount email.';
      } else if (status == 'alert_failed') {
        message = 'Không gửi được email cảnh báo. Hãy xem lỗi SMTP trong log Functions.';
      } else if (action == 'TRIGGER_DRY_RUN') {
        message = 'Demo đã chạy ở chế độ mô phỏng, chưa gửi email thật.';
      } else if (action == 'TRIGGER_REAL_ALERT' && recipientsCount == 0) {
        message = 'Chưa có liên hệ đủ điều kiện: cần bật liên hệ và hoàn tất xác minh, đồng ý nhận cảnh báo.';
      } else {
        message =
            'Đã kiểm tra demo quá hạn (trạng thái: ${action ?? 'không xác định'}).';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: status == 'alert_sent' && recipientsCount > 0
                ? const Color(0xFF078D83)
                : Colors.deepOrange,
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      final recovered = await _recoverOverdueDemoResult();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recovered?.message ?? _overdueDemoErrorMessage(error),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: recovered?.color ?? Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      final recovered = await _recoverOverdueDemoResult();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recovered?.message ?? 'Không thể xác nhận kết quả demo. Hãy kiểm tra Lịch sử trước khi chạy lại.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: recovered?.color ?? Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOverdueDemoScheduled = false);
    }
  }

  String _overdueDemoErrorMessage(FirebaseFunctionsException error) {
    final message = error.message ?? '';
    if (error.code == 'unknown' && message.contains('ExecutionException')) {
      return 'Không thể xác nhận kết quả demo. Hãy kiểm tra Lịch sử trước khi chạy lại.';
    }
    return message.isNotEmpty
        ? message
        : 'Không thể chạy kiểm tra demo quá hạn.';
  }

  Future<({String message, Color color})?> _recoverOverdueDemoResult() async {
    final user = AuthService().currentUser;
    final dueAt = _config?.nextCheckInDueAt;
    if (user == null || dueAt == null) return null;

    try {
      final eventSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('alert_events')
          .doc('event_${dueAt.millisecondsSinceEpoch}')
          .get();
      final event = eventSnapshot.data();
      if (event == null) return null;

      final status = event['status'] as String?;
      final recipientsValue = event['recipients'];
      final recipients = recipientsValue is List ? recipientsValue : const [];
      final sentCount = recipients
          .where(
            (recipient) => recipient is Map && recipient['status'] == 'sent',
          )
          .length;

      if (status == 'alert_sent' && sentCount > 0) {
        return (
          message:
              'Demo quá hạn hoàn tất: đã gửi email cảnh báo đến $sentCount liên hệ.',
          color: const Color(0xFF078D83),
        );
      }
      if (status == 'alert_sent' && recipients.isEmpty) {
        return (
          message:
              'Demo đã chạy nhưng chưa có liên hệ đủ điều kiện nhận cảnh báo.',
          color: Colors.deepOrange,
        );
      }
      if (status == 'partially_sent') {
        return (
          message: 'Demo hoàn tất một phần: đã gửi được $sentCount email.',
          color: Colors.deepOrange,
        );
      }
      if (status == 'alert_failed') {
        return (
          message: 'Không gửi được email cảnh báo. Hãy xem lỗi SMTP trong log Functions.',
          color: Colors.deepOrange,
        );
      }
      if (status == 'dry_run_dispatched') {
        return (
          message: 'Demo đã chạy ở chế độ mô phỏng, chưa gửi email thật.',
          color: Colors.deepOrange,
        );
      }
    } catch (_) {
      // Fall back to the callable error if the event cannot be read.
    }
    return null;
  }

  Future<void> _handleIntervalChange(int hours) async {
    try {
      final updated = await _configService.updateConfig(intervalHours: hours);
      if (mounted) {
        setState(() => _config = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã cập nhật chu kỳ kiểm tra: $hours giờ'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF078D83),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi cập nhật: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showCustomIntervalDialog() async {
    final controller = TextEditingController(
      text: _config?.intervalHours.toString() ?? '24',
    );

    final selectedHours = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Chu kỳ tùy chỉnh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập số giờ giữa các lần xác nhận an toàn (1 đến 720 giờ):',
              style: TextStyle(fontSize: 13, color: Color(0xFF52717D)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Số giờ',
                suffixText: 'giờ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF078D83),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val >= 1 && val <= 720) {
                Navigator.pop(ctx, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng nhập số giờ hợp lệ từ 1 đến 720!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (selectedHours != null) {
      await _handleIntervalChange(selectedHours);
    }
  }

  Future<void> _handleReminderToggle(bool enabled) async {
    if (enabled) {
      // Yêu cầu quyền thông báo nếu bật
      await NotificationService.instance.requestPermission();
    }

    try {
      final updated = await _configService.updateConfig(
        isReminderEnabled: enabled,
      );
      if (mounted) {
        setState(() => _config = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Đã bật nhắc nhở thông báo trước hạn.'
                  : 'Đã tắt nhắc nhở thông báo.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF078D83),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _handleReminderTimeChange(int minutes) async {
    try {
      final updated = await _configService.updateConfig(
        reminderMinutesBefore: minutes,
      );
      if (mounted) {
        setState(() => _config = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sẽ gửi thông báo trước: ${minutes ~/ 60 > 0 ? '${minutes ~/ 60} giờ' : '$minutes phút'}',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF078D83),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _healthRow(
    String label,
    bool enabled,
    String actionLabel,
    VoidCallback onPressed,
  ) {
    return Row(
      children: [
        Icon(
          enabled ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 20,
          color: enabled ? const Color(0xFF078D83) : const Color(0xFFB54708),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        if (!enabled)
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đăng xuất'),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng Sinh Tử?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await AuthService().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF078D83);
    const navy = Color(0xFF062C43);
    final user = AuthService().currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F8),
      appBar: AppBar(
        title: const Text(
          'Cài đặt',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF082F49),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: teal))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_notificationsEnabled && _exactAlarmEnabled)
                          ? const Color(0xFFB7DDD8)
                          : const Color(0xFFF2C6A0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            (_notificationsEnabled && _exactAlarmEnabled)
                                ? Icons.health_and_safety_rounded
                                : Icons.warning_amber_rounded,
                            color: (_notificationsEnabled && _exactAlarmEnabled)
                                ? teal
                                : const Color(0xFFB54708),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Sức khỏe thông báo & chạy nền',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF082F49),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _healthRow(
                        'Thông báo nhắc nhở',
                        _notificationsEnabled,
                        'Mở quyền thông báo',
                        () async {
                          await NotificationService.instance.requestPermission();
                          await _loadSafetyHealth();
                        },
                      ),
                      const SizedBox(height: 10),
                      _healthRow(
                        'Báo đúng giờ khi chạy nền',
                        _exactAlarmEnabled,
                        'Cho phép báo thức chính xác',
                        () async {
                          await NotificationService.instance
                              .requestExactAlarmPermission();
                          await _loadSafetyHealth();
                        },
                      ),
                      if (!_healthLoaded)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 1. Thẻ thông tin tài khoản
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: teal.withValues(alpha: 0.15),
                          backgroundImage: user?.photoURL != null
                              ? NetworkImage(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
                              ? Text(
                                  (user?.displayName?.isNotEmpty == true
                                          ? user!.displayName![0]
                                          : user?.email?.isNotEmpty == true
                                          ? user!.email![0]
                                          : 'U')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: teal,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName?.isNotEmpty == true
                                    ? user!.displayName!
                                    : 'Người dùng Sinh Tử',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: navy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? 'Chưa liên kết email',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: navy.withValues(alpha: 0.65),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Xem và chỉnh sửa hồ sơ →',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: teal.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: teal.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Cài đặt Chu kỳ kiểm tra an toàn
                _buildSectionHeader('CHU KỲ XÁC NHẬN AN TOÀN'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _inkSafeSurface(
                    child: Column(
                      children: [
                        _buildIntervalTile(12, '12 giờ (Nửa ngày)'),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _buildIntervalTile(24, '24 giờ (1 ngày - Khuyên dùng)'),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _buildIntervalTile(48, '48 giờ (2 ngày)'),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _buildIntervalTile(72, '72 giờ (3 ngày)'),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.tune_rounded, color: teal),
                          title: const Text('Tùy chỉnh số giờ'),
                          subtitle: Text(
                            ![
                                  12,
                                  24,
                                  48,
                                  72,
                                ].contains(_config?.intervalHours ?? 24)
                                ? 'Đang chọn: ${_config?.intervalHours} giờ'
                                : 'Chọn số giờ khác',
                            style: TextStyle(
                              color:
                                  ![
                                    12,
                                    24,
                                    48,
                                    72,
                                  ].contains(_config?.intervalHours ?? 24)
                                  ? teal
                                  : null,
                              fontWeight:
                                  ![
                                    12,
                                    24,
                                    48,
                                    72,
                                  ].contains(_config?.intervalHours ?? 24)
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _showCustomIntervalDialog,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Cài đặt Nhắc nhở an toàn
                _buildSectionHeader('NHẮC NHỞ AN TOÀN'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _inkSafeSurface(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.notifications_active_rounded,
                            color: teal,
                          ),
                          title: const Text(
                            'Nhắc nhở thông báo',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Nhận thông báo thiết bị trước khi hết hạn xác nhận',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _config?.isReminderEnabled ?? true,
                          activeThumbColor: teal,
                          onChanged: _handleReminderToggle,
                        ),
                        if (_config?.isReminderEnabled ?? true) ...[
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Thời điểm nhắc nhở trước hạn:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: navy,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _buildReminderChip(30, '30 phút'),
                                    _buildReminderChip(60, '1 giờ'),
                                    _buildReminderChip(120, '2 giờ'),
                                    _buildReminderChip(240, '4 giờ'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                _buildSectionHeader('DEMO CẢNH BÁO'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _inkSafeSurface(
                    child: Column(
                      children: [
                        if (_showOverdueDemo)
                          ListTile(
                            leading: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.deepOrange,
                            ),
                            title: const Text(
                              'Bắt đầu demo quá hạn',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Giữ app và emulator mở; gửi cảnh báo thật sau khoảng 1 phút',
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing:
                                _isPreparingOverdueDemo ||
                                    _isOverdueDemoScheduled
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            onTap:
                                _isPreparingOverdueDemo ||
                                    _isOverdueDemoScheduled
                                ? null
                                : _handleOverdueDemo,
                          ),
                        ListTile(
                          leading: const Icon(
                            Icons.mark_email_unread_rounded,
                            color: teal,
                          ),
                          title: const Text(
                            'Gửi email cảnh báo demo',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Gửi ngay email thật tới liên hệ đã đồng ý nhận cảnh báo',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: _isSendingDemoAlert
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: _isSendingDemoAlert ? null : _handleDemoAlert,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Chia sẻ vị trí (GPS)
                _buildLocationSection(),
                const SizedBox(height: 20),

                // 5. Thông tin ứng dụng
                _buildSectionHeader('THÔNG TIN'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _inkSafeSurface(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.info_outline_rounded,
                            color: teal,
                          ),
                          title: const Text('Về ứng dụng Sinh Tử'),
                          subtitle: const Text(
                            'Phiên bản 1.0.0 (Dead Man\'s Switch)',
                          ),
                          onTap: () {
                            showAboutDialog(
                              context: context,
                              applicationName: 'Sinh Tử',
                              applicationVersion: '1.0.0',
                              applicationIcon: const Icon(
                                Icons.shield_moon_rounded,
                                size: 48,
                                color: teal,
                              ),
                              children: const [
                                Text(
                                  'Sinh Tử là ứng dụng bảo vệ an toàn cá nhân, định kỳ xác nhận sự an toàn của bạn để gửi cảnh báo đến người thân khi có sự cố bất trắc.',
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 5. Nút Đăng xuất
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleSignOut(context),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFD32F2F),
                    ),
                    label: const Text(
                      'Đăng xuất',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFFCDD2)),
                      backgroundColor: const Color(0xFFFFEBEE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _inkSafeSurface({required Widget child, double radius = 20}) {
    return Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF6B8793),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildIntervalTile(int hours, String label) {
    final isSelected = (_config?.intervalHours ?? 24) == hours;
    const teal = Color(0xFF078D83);
    return ListTile(
      leading: Icon(
        isSelected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: isSelected ? teal : const Color(0xFF90A4AE),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          color: isSelected ? const Color(0xFF082F49) : null,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, color: teal, size: 20)
          : null,
      onTap: () => _handleIntervalChange(hours),
    );
  }

  Widget _buildReminderChip(int minutes, String label) {
    final isSelected = (_config?.reminderMinutesBefore ?? 120) == minutes;
    const teal = Color(0xFF078D83);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: teal.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? teal : const Color(0xFF52717D),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12.5,
      ),
      side: BorderSide(color: isSelected ? teal : const Color(0xFFD8E2E6)),
      onSelected: (val) {
        if (val) _handleReminderTimeChange(minutes);
      },
    );
  }

  Widget _buildLocationSection() {
    const teal = Color(0xFF078D83);
    const navy = Color(0xFF082F49);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('ĐỊNH VỊ & AN TOÀN'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _inkSafeSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: _isLocationSharingEnabled,
                  title: const Text(
                    'Chia sẻ vị trí khi khẩn cấp',
                    style: TextStyle(fontWeight: FontWeight.w600, color: navy),
                  ),
                  subtitle: const Text(
                    'Khi gửi cảnh báo, toạ độ được tra qua OpenStreetMap để đính kèm địa chỉ gần nhất (ước tính) và vị trí trên bản đồ',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  activeThumbColor: teal,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: teal),
                  ),
                  onChanged: _handleLocationSharingToggle,
                ),
                if (_isLocationSharingEnabled) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Trạng thái quyền
                        Row(
                          children: [
                            Icon(
                              _locationPermissionStatus ==
                                      LocationPermissionStatus.granted
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.warning_amber_rounded,
                              size: 16,
                              color:
                                  _locationPermissionStatus ==
                                      LocationPermissionStatus.granted
                                  ? teal
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _permissionStatusLabel,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      _locationPermissionStatus ==
                                          LocationPermissionStatus.granted
                                      ? const Color(0xFF2E7D32)
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Thông tin vị trí gần nhất
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _lastLocation != null
                                          ? 'Vị trí ghi nhận: ${_lastLocation!.timestampFormatted}'
                                          : 'Chưa có dữ liệu toạ độ',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: navy,
                                      ),
                                    ),
                                    if (_lastLocation != null)
                                      Text(
                                        'Độ chính xác: ${_lastLocation!.accuracyFormatted}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    if (_lastLocation != null)
                                      Text(
                                        'Toạ độ: ${_lastLocation!.latitude.toStringAsFixed(6)}, ${_lastLocation!.longitude.toStringAsFixed(6)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      )
                                    else
                                      const Text(
                                        'Nhấn cập nhật để lưu toạ độ mới nhất',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Nút cập nhật vị trí
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: _isGettingLocation
                                ? null
                                : _handleTestLocation,
                            icon: _isGettingLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: teal,
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location_rounded,
                                    size: 18,
                                    color: teal,
                                  ),
                            label: Text(
                              _isGettingLocation
                                  ? 'Đang lấy toạ độ GPS...'
                                  : 'Cập nhật toạ độ ngay',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: teal,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFB2DFDB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get _permissionStatusLabel {
    switch (_locationPermissionStatus) {
      case LocationPermissionStatus.granted:
        return 'Quyền vị trí: Đã cấp phép';
      case LocationPermissionStatus.denied:
        return 'Quyền vị trí: Đã từ chối (cần cấp lại)';
      case LocationPermissionStatus.deniedForever:
        return 'Quyền vị trí: Bị từ chối vĩnh viễn (mở Cài đặt hệ thống)';
      case LocationPermissionStatus.serviceDisabled:
        return 'Dịch vụ GPS trên thiết bị đang tắt';
      case LocationPermissionStatus.notDetermined:
        return 'Chưa xác định quyền truy cập';
    }
  }
}
