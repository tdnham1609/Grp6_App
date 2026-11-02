import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái thời hạn an toàn của người dùng
enum CheckInStatus {
  /// Đang trong thời hạn an toàn bình thường
  onTime,

  /// Sắp đến hạn xác nhận (trong khoảng thời gian nhắc nhở trước)
  dueSoon,

  /// Đã quá thời hạn xác nhận an toàn
  overdue,

  /// Chưa có dữ liệu xác nhận
  noData,
}

/// Cấu hình chu kỳ điểm danh và thời hạn xác nhận an toàn
/// Lưu trữ cả trong SQLite (bảng user_settings) và Firestore (users/{uid}/settings/checkin)
class CheckInConfig {
  final int intervalHours;
  final int reminderMinutesBefore;
  final bool isReminderEnabled;
  final DateTime? lastCheckInAt;
  final DateTime? nextCheckInDueAt;
  final DateTime updatedAt;

  const CheckInConfig({
    this.intervalHours = 24,
    this.reminderMinutesBefore = 120, // 2 giờ trước hạn
    this.isReminderEnabled = true,
    this.lastCheckInAt,
    this.nextCheckInDueAt,
    required this.updatedAt,
  });

  /// Cấu hình mặc định ban đầu
  factory CheckInConfig.defaultConfig() {
    return CheckInConfig(
      intervalHours: 24,
      reminderMinutesBefore: 120,
      isReminderEnabled: true,
      updatedAt: DateTime.now(),
    );
  }

  /// Tính toán thời hạn tiếp theo dựa trên thời điểm check-in và số giờ chu kỳ
  static DateTime computeNextDue(DateTime checkInTime, int hours) {
    return checkInTime.add(Duration(hours: hours));
  }

  /// Lấy trạng thái an toàn hiện tại
  CheckInStatus getStatus([DateTime? now]) {
    if (lastCheckInAt == null || nextCheckInDueAt == null) {
      return CheckInStatus.noData;
    }

    final current = now ?? DateTime.now();

    if (current.isAfter(nextCheckInDueAt!)) {
      return CheckInStatus.overdue;
    }

    final diffMinutes = nextCheckInDueAt!.difference(current).inMinutes;
    if (diffMinutes <= reminderMinutesBefore) {
      return CheckInStatus.dueSoon;
    }

    return CheckInStatus.onTime;
  }

  /// Thời gian còn lại cho đến hạn tiếp theo (có thể âm nếu đã quá hạn)
  Duration? getRemainingDuration([DateTime? now]) {
    if (nextCheckInDueAt == null) return null;
    return nextCheckInDueAt!.difference(now ?? DateTime.now());
  }

  /// Chuỗi hiển thị thân thiện thời gian còn lại
  String getRemainingFormatted([DateTime? now]) {
    final status = getStatus(now);
    if (status == CheckInStatus.noData || nextCheckInDueAt == null) {
      return 'Chưa có lịch xác nhận';
    }

    final current = now ?? DateTime.now();

    if (status == CheckInStatus.overdue) {
      final overdueDiff = current.difference(nextCheckInDueAt!);
      final hours = overdueDiff.inHours;
      final minutes = overdueDiff.inMinutes % 60;
      if (hours > 0) {
        return 'Quá hạn $hours giờ $minutes phút';
      }
      return 'Quá hạn $minutes phút';
    }

    final remainDiff = nextCheckInDueAt!.difference(current);
    final hours = remainDiff.inHours;
    final minutes = remainDiff.inMinutes % 60;

    if (hours > 0) {
      return 'Còn $hours giờ $minutes phút';
    }
    return 'Còn $minutes phút';
  }

  /// Chuyển thành Map lưu Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'intervalHours': intervalHours,
      'reminderMinutesBefore': reminderMinutesBefore,
      'isReminderEnabled': isReminderEnabled,
      'lastCheckInAt': lastCheckInAt != null
          ? Timestamp.fromDate(lastCheckInAt!)
          : null,
      'nextCheckInDueAt': nextCheckInDueAt != null
          ? Timestamp.fromDate(nextCheckInDueAt!)
          : null,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Tạo CheckInConfig từ Firestore DocumentSnapshot
  factory CheckInConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CheckInConfig.fromMap(data);
  }

  /// Tạo CheckInConfig từ Map
  factory CheckInConfig.fromMap(Map<String, dynamic> data) {
    return CheckInConfig(
      intervalHours: (data['intervalHours'] as num?)?.toInt() ?? 24,
      reminderMinutesBefore:
          (data['reminderMinutesBefore'] as num?)?.toInt() ?? 120,
      isReminderEnabled: data['isReminderEnabled'] as bool? ?? true,
      lastCheckInAt: _parseDateTime(
        data['lastCheckInAt'] ?? data['last_checkin_at'],
      ),
      nextCheckInDueAt: _parseDateTime(
        data['nextCheckInDueAt'] ?? data['next_due_at'],
      ),
      updatedAt:
          _parseDateTime(data['updatedAt'] ?? data['updated_at']) ??
          DateTime.now(),
    );
  }

  /// Chuyển thành Map lưu vào SQLite bảng user_settings
  Map<String, dynamic> toSqlite(String uid) {
    return {
      'uid': uid,
      'interval_hours': intervalHours,
      'reminder_minutes': reminderMinutesBefore,
      'is_reminder_enabled': isReminderEnabled ? 1 : 0,
      'last_checkin_at': lastCheckInAt?.toIso8601String(),
      'next_due_at': nextCheckInDueAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Tạo CheckInConfig từ SQLite row
  factory CheckInConfig.fromSqlite(Map<String, dynamic> row) {
    return CheckInConfig(
      intervalHours: row['interval_hours'] as int? ?? 24,
      reminderMinutesBefore: row['reminder_minutes'] as int? ?? 120,
      isReminderEnabled: (row['is_reminder_enabled'] as int? ?? 1) == 1,
      lastCheckInAt: row['last_checkin_at'] != null
          ? DateTime.tryParse(row['last_checkin_at'] as String)
          : null,
      nextCheckInDueAt: row['next_due_at'] != null
          ? DateTime.tryParse(row['next_due_at'] as String)
          : null,
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String && val.isNotEmpty) return DateTime.tryParse(val);
    return null;
  }

  CheckInConfig copyWith({
    int? intervalHours,
    int? reminderMinutesBefore,
    bool? isReminderEnabled,
    DateTime? lastCheckInAt,
    DateTime? nextCheckInDueAt,
    DateTime? updatedAt,
  }) {
    return CheckInConfig(
      intervalHours: intervalHours ?? this.intervalHours,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      isReminderEnabled: isReminderEnabled ?? this.isReminderEnabled,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      nextCheckInDueAt: nextCheckInDueAt ?? this.nextCheckInDueAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
