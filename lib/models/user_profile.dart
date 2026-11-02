import 'package:cloud_firestore/cloud_firestore.dart';

/// Mô hình hồ sơ người dùng, ánh xạ tới Firestore collection: users/{uid}
class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String provider; // 'password' | 'google'
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Tạo UserProfile từ Firestore DocumentSnapshot
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: data['uid'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      provider: data['provider'] as String? ?? 'password',
      createdAt: _timestampToDateTime(data['createdAt']),
      updatedAt: _timestampToDateTime(data['updatedAt']),
    );
  }

  /// Tạo UserProfile từ Map thông thường (dùng cho cache nội bộ hoặc test)
  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    return UserProfile(
      uid: data['uid'] as String? ?? uid,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      provider: data['provider'] as String? ?? 'password',
      createdAt: _timestampToDateTime(data['createdAt']),
      updatedAt: _timestampToDateTime(data['updatedAt']),
    );
  }

  static DateTime _timestampToDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    return DateTime.now();
  }

  /// Map dùng khi TẠO MỚI hồ sơ — dùng FieldValue.serverTimestamp() cho timestamps
  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'provider': provider,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Tạo bản sao với thay đổi một số trường
  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? provider,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      provider: provider ?? this.provider,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, displayName: $displayName, email: $email, provider: $provider)';
  }
}
