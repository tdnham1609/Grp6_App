import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái đồng bộ của bản ghi check-in
class SyncStatus {
  static const String synced = 'synced';
  static const String pending = 'pending';
}

/// Mô hình bản ghi điểm danh an toàn (CheckIn)
/// Lưu trữ cả trong SQLite cục bộ và Cloud Firestore: users/{uid}/checkins/{id}
class CheckIn {
  final String id;
  final String uid;
  final DateTime checkedInAt;
  final DateTime createdAt;
  final String syncStatus;

  const CheckIn({
    required this.id,
    required this.uid,
    required this.checkedInAt,
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
  });

  /// Kiểm tra bản ghi đã được đồng bộ lên Cloud Firestore hay chưa
  bool get isSynced => syncStatus == SyncStatus.synced;

  /// Tạo bản ghi mới cho người dùng
  factory CheckIn.create({
    required String uid,
    DateTime? checkedInAt,
    String? id,
    String syncStatus = SyncStatus.pending,
  }) {
    final now = DateTime.now();
    final checkTime = checkedInAt ?? now;
    final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
    final generatedId =
        id ??
        'checkin_${checkTime.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000000}_$randomSuffix';

    return CheckIn(
      id: generatedId,
      uid: uid,
      checkedInAt: checkTime,
      createdAt: now,
      syncStatus: syncStatus,
    );
  }

  /// Tạo CheckIn từ Cloud Firestore DocumentSnapshot
  factory CheckIn.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CheckIn.fromMap(data, id: doc.id, syncStatus: SyncStatus.synced);
  }

  /// Tạo CheckIn từ Map thông thường
  factory CheckIn.fromMap(
    Map<String, dynamic> data, {
    String? id,
    String? syncStatus,
  }) {
    return CheckIn(
      id: data['id'] as String? ?? id ?? '',
      uid: data['uid'] as String? ?? '',
      checkedInAt: _parseDateTime(data['checkedInAt'] ?? data['checked_at']),
      createdAt: _parseDateTime(data['createdAt'] ?? data['created_at']),
      syncStatus:
          syncStatus ??
          (data['sync_status'] as String? ??
              data['syncStatus'] as String? ??
              SyncStatus.pending),
    );
  }

  /// Tạo CheckIn từ một hàng trong bảng SQLite
  factory CheckIn.fromSqlite(Map<String, dynamic> row) {
    return CheckIn(
      id: row['id'] as String,
      uid: row['uid'] as String? ?? '',
      checkedInAt:
          DateTime.tryParse(row['checked_at'] as String? ?? '') ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      syncStatus: row['sync_status'] as String? ?? SyncStatus.pending,
    );
  }

  static DateTime _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  /// Chuyển thành Map để lưu vào bảng SQLite check_ins
  Map<String, dynamic> toSqlite() {
    return {
      'id': id,
      'uid': uid,
      'checked_at': checkedInAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  /// Chuyển thành Map để đẩy lên Cloud Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'uid': uid,
      'checkedInAt': Timestamp.fromDate(checkedInAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Tạo bản sao có sửa đổi một số trường
  CheckIn copyWith({
    String? id,
    String? uid,
    DateTime? checkedInAt,
    DateTime? createdAt,
    String? syncStatus,
  }) {
    return CheckIn(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckIn && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'CheckIn(id: $id, uid: $uid, checkedInAt: $checkedInAt, syncStatus: $syncStatus)';
  }
}
