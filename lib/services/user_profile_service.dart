import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

/// Service quản lý hồ sơ người dùng trên Firestore.
/// Collection: users/{uid}
///
/// Nguyên tắc:
/// - Không ghi đè createdAt khi đăng nhập lại.
/// - Không xóa dữ liệu người dùng đã tùy chỉnh.
/// - Không lưu mật khẩu hoặc token vào Firestore.
class UserProfileService {
  static final UserProfileService _instance = UserProfileService._internal();
  factory UserProfileService() => _instance;
  UserProfileService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _db.collection('users');

  // ─── Đọc ─────────────────────────────────────────────────────────────────

  /// Lấy hồ sơ của người dùng hiện tại (một lần)
  Future<UserProfile?> fetchCurrentUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return fetchUserProfile(uid);
  }

  /// Lấy hồ sơ theo UID (một lần)
  Future<UserProfile?> fetchUserProfile(String uid) async {
    try {
      final doc = await _usersCol.doc(uid).get();
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    } catch (e) {
      throw 'Không thể tải hồ sơ: ${e.toString()}';
    }
  }

  /// Stream theo dõi hồ sơ realtime (dùng cho UI)
  Stream<UserProfile?> streamCurrentUserProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _usersCol.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  // ─── Tạo ─────────────────────────────────────────────────────────────────

  /// Tạo hồ sơ mới sau khi đăng ký email/password.
  /// Gọi sau registerWithEmailPassword thành công.
  Future<void> createProfileForEmailUser({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final profile = UserProfile(
      uid: uid,
      displayName: displayName.trim(),
      email: email.trim(),
      photoUrl: null,
      provider: 'password',
      createdAt: DateTime.now(), // local placeholder; server sẽ ghi đè
      updatedAt: DateTime.now(),
    );

    try {
      await _usersCol.doc(uid).set(profile.toCreateMap());
    } catch (e) {
      throw 'Không thể tạo hồ sơ: ${e.toString()}';
    }
  }

  /// Tạo hoặc cập nhật hồ sơ khi đăng nhập Google.
  ///
  /// Logic:
  /// - Nếu document chưa tồn tại → tạo mới.
  /// - Nếu đã tồn tại → chỉ cập nhật photoUrl và updatedAt.
  ///   Không ghi đè displayName đã được người dùng tùy chỉnh.
  Future<void> upsertProfileForGoogleUser({
    required String uid,
    required String email,
    required String googleDisplayName,
    required String? googlePhotoUrl,
  }) async {
    try {
      final docRef = _usersCol.doc(uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        // Tạo hồ sơ lần đầu đăng nhập Google
        final profile = UserProfile(
          uid: uid,
          displayName: googleDisplayName.trim(),
          email: email.trim(),
          photoUrl: googlePhotoUrl,
          provider: 'google',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await docRef.set(profile.toCreateMap());
      } else {
        // Hồ sơ đã tồn tại: chỉ cập nhật những trường được phép
        // KHÔNG ghi đè displayName để tôn trọng tùy chỉnh của người dùng
        await docRef.update({
          'photoUrl': googlePhotoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw 'Không thể đồng bộ hồ sơ Google: ${e.toString()}';
    }
  }

  // ─── Cập nhật ─────────────────────────────────────────────────────────────

  /// Cập nhật họ tên người dùng.
  /// Đồng thời cập nhật cả Firebase Auth displayName.
  Future<void> updateDisplayName(String newName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw 'Người dùng chưa đăng nhập.';

    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw 'Họ và tên không được để trống.';

    try {
      // Cập nhật Firebase Auth profile
      await user.updateDisplayName(trimmed);

      // Cập nhật Firestore
      await _usersCol.doc(user.uid).update({
        'displayName': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Không thể cập nhật tên: ${e.toString()}';
    }
  }

  // ─── Phục hồi ─────────────────────────────────────────────────────────────

  /// Thử tạo lại hồ sơ nếu đăng ký thành công nhưng Firestore thất bại.
  /// Gọi khi đăng nhập lại và phát hiện hồ sơ chưa tồn tại.
  Future<void> ensureProfileExists(User user) async {
    try {
      final doc = await _usersCol.doc(user.uid).get();
      if (doc.exists) return; // Hồ sơ đã có, không cần làm gì

      // Xác định provider
      final provider = user.providerData.isNotEmpty
          ? (user.providerData.first.providerId == 'google.com'
                ? 'google'
                : 'password')
          : 'password';

      final profile = UserProfile(
        uid: user.uid,
        displayName: user.displayName ?? '',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        provider: provider,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _usersCol.doc(user.uid).set(profile.toCreateMap());
    } catch (_) {
      // Không throw — đây là thao tác phục hồi, không chặn luồng đăng nhập
    }
  }
}
