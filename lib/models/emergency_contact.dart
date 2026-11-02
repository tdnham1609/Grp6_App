import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái đồng ý nhận cảnh báo khẩn cấp của người liên hệ
class ConsentStatus {
  static const String pending = 'pending'; // Chờ người nhận xác nhận đồng ý
  static const String accepted = 'accepted'; // Người nhận đã đồng ý
  static const String declined = 'declined'; // Người nhận đã từ chối
  static const String revoked = 'revoked'; // Người nhận đã thu hồi sự đồng ý
}

/// Mô hình liên hệ khẩn cấp (Emergency Contact)
/// Lưu tại Firestore: users/{uid}/emergency_contacts/{contactId}
/// và SQLite cục bộ (bảng emergency_contacts)
class EmergencyContact {
  final String id;
  final String uid;
  final String name;
  final String email;
  final String? phoneNumber;
  final String relationship;
  final bool emailVerified;
  final String consentStatus;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmergencyContact({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    this.phoneNumber,
    required this.relationship,
    this.emailVerified = false,
    this.consentStatus = ConsentStatus.pending,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Tạo liên hệ mới (mặc định chưa xác minh và trạng thái chờ đồng ý)
  factory EmergencyContact.create({
    required String uid,
    required String name,
    required String email,
    String? phoneNumber,
    required String relationship,
    String? id,
  }) {
    final now = DateTime.now();
    final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
    final generatedId =
        id ??
        'contact_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000000}_$randomSuffix';

    return EmergencyContact(
      id: generatedId,
      uid: uid,
      name: name.trim(),
      email: email.trim().toLowerCase(),
      phoneNumber: phoneNumber?.trim().isEmpty == true
          ? null
          : phoneNumber?.trim(),
      relationship: relationship.trim(),
      emailVerified: false, // Bắt buộc false khi mới tạo
      consentStatus: ConsentStatus.pending, // Bắt buộc pending
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Chuyển thành Map lưu Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
      'emailVerified': emailVerified,
      'consentStatus': consentStatus,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Tạo EmergencyContact từ Firestore DocumentSnapshot
  factory EmergencyContact.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return EmergencyContact.fromMap(data, id: doc.id);
  }

  /// Tạo EmergencyContact từ Map
  factory EmergencyContact.fromMap(Map<String, dynamic> data, {String? id}) {
    return EmergencyContact(
      id: data['id'] as String? ?? id ?? '',
      uid: data['uid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phoneNumber:
          data['phoneNumber'] as String? ?? data['phone_number'] as String?,
      relationship: data['relationship'] as String? ?? 'Khác',
      emailVerified:
          data['emailVerified'] as bool? ??
          data['email_verified'] == 1 || data['email_verified'] == true,
      consentStatus:
          data['consentStatus'] as String? ??
          data['consent_status'] as String? ??
          ConsentStatus.pending,
      isActive:
          data['isActive'] as bool? ??
          (data['is_active'] != null ? data['is_active'] == 1 : true),
      createdAt: _parseDateTime(data['createdAt'] ?? data['created_at']),
      updatedAt: _parseDateTime(data['updatedAt'] ?? data['updated_at']),
    );
  }

  /// Chuyển thành Map lưu SQLite
  Map<String, dynamic> toSqlite() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'email': email,
      'phone_number': phoneNumber,
      'relationship': relationship,
      'email_verified': emailVerified ? 1 : 0,
      'consent_status': consentStatus,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Tạo EmergencyContact từ SQLite row
  factory EmergencyContact.fromSqlite(Map<String, dynamic> row) {
    return EmergencyContact(
      id: row['id'] as String,
      uid: row['uid'] as String? ?? '',
      name: row['name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      phoneNumber: row['phone_number'] as String?,
      relationship: row['relationship'] as String? ?? 'Khác',
      emailVerified: (row['email_verified'] as int? ?? 0) == 1,
      consentStatus: row['consent_status'] as String? ?? ConsentStatus.pending,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static DateTime _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String && val.isNotEmpty) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  EmergencyContact copyWith({
    String? id,
    String? uid,
    String? name,
    String? email,
    String? phoneNumber,
    String? relationship,
    bool? emailVerified,
    String? consentStatus,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      relationship: relationship ?? this.relationship,
      emailVerified: emailVerified ?? this.emailVerified,
      consentStatus: consentStatus ?? this.consentStatus,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Validate họ tên liên hệ
  static String? validateName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập tên người thân';
    if (v.length < 2) return 'Tên phải có ít nhất 2 ký tự';
    if (v.length > 60) return 'Tên không được vượt quá 60 ký tự';
    return null;
  }

  /// Validate địa chỉ email
  static String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập email nhận cảnh báo';
    final emailRegex = RegExp(r'^[\w\.\+\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(v)) {
      return 'Định dạng email không hợp lệ';
    }
    return null;
  }

  /// Validate số điện thoại (tùy chọn)
  static String? validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // Không bắt buộc
    final phoneRegex = RegExp(r'^[0-9+ ]{9,15}$');
    if (!phoneRegex.hasMatch(v)) {
      return 'Số điện thoại không hợp lệ (9-15 chữ số)';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyContact &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
