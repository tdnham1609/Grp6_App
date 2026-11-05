import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/emergency_contact.dart';
import 'database_service.dart';
import 'trusted_contact_dashboard_service.dart';

/// Kết quả yêu cầu tạo mã xác minh email và link opt-in
class VerificationResult {
  final bool success;
  final String message;
  final String? emailMasked;
  final String? verificationUrl;
  final bool isDryRun;

  const VerificationResult({
    required this.success,
    required this.message,
    this.emailMasked,
    this.verificationUrl,
    this.isDryRun = true,
  });
}

/// Service quản lý danh bạ khẩn cấp nhận cảnh báo (Emergency Contacts)
/// Hỗ trợ Offline-first, cô lập chặt chẽ theo UID và đồng bộ Cloud Firestore
class EmergencyContactService {
  final DatabaseService? _customDbService;
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final FirebaseFunctions? _customFunctions;

  static final EmergencyContactService instance = EmergencyContactService();

  EmergencyContactService({
    DatabaseService? dbService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _customDbService = dbService,
       _customFirestore = firestore,
       _customAuth = auth,
       _customFunctions = functions;

  DatabaseService get _dbService =>
      _customDbService ?? DatabaseService.instance;

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

  FirebaseFunctions? get _functions {
    if (_customFunctions != null) return _customFunctions;
    try {
      return FirebaseFunctions.instance;
    } catch (_) {
      return null;
    }
  }

  /// Lấy danh sách liên hệ khẩn cấp của người dùng hiện tại
  /// - Đọc từ SQLite cục bộ trước để phản hồi tức thì
  /// - Tải từ Cloud Firestore khi có mạng và cập nhật cache cục bộ
  /// - Cô lập hoàn toàn theo UID (không làm rò rỉ dữ liệu khi đổi tài khoản)
  Future<List<EmergencyContact>> getContacts() async {
    final user = _auth?.currentUser;
    if (user == null) {
      return [];
    }

    // 1. Đọc từ SQLite cục bộ
    List<EmergencyContact> localList = [];
    try {
      localList = await _dbService.getEmergencyContacts(uid: user.uid);
    } catch (e) {
      debugPrint('Lỗi đọc danh bạ từ SQLite: $e');
    }

    final firestore = _firestore;
    if (firestore == null) {
      return localList;
    }

    // 2. Thử tải dữ liệu mới nhất từ Firestore: users/{uid}/emergency_contacts
    try {
      final snapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .orderBy('createdAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 7));

      final remoteList = snapshot.docs
          .map((doc) => EmergencyContact.fromFirestore(doc))
          .toList();

      try {
        await TrustedContactDashboardService.instance.syncMyStatus();
      } catch (_) {}

      if (remoteList.isNotEmpty) {
        // Cập nhật lại SQLite để đồng bộ cho các lần mở app offline tiếp theo
        await _dbService.upsertEmergencyContacts(remoteList);
      }

      // Hợp nhất dữ liệu tránh trùng lặp
      final map = <String, EmergencyContact>{};
      for (final item in localList) {
        map[item.id] = item;
      }
      for (final item in remoteList) {
        map[item.id] = item;
      }

      final combined = map.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return combined;
    } catch (e) {
      debugPrint('Không thể tải danh bạ từ Firestore (Offline mode): $e');
      return localList;
    }
  }

  /// Thêm liên hệ khẩn cấp mới
  Future<EmergencyContact> addContact({
    required String name,
    required String email,
    String? phoneNumber,
    required String relationship,
  }) async {
    final user = _auth?.currentUser;
    if (user == null) {
      throw StateError('Bạn cần đăng nhập để quản lý danh bạ khẩn cấp.');
    }

    // Validate dữ liệu
    final nameErr = EmergencyContact.validateName(name);
    if (nameErr != null) throw ArgumentError(nameErr);

    final emailErr = EmergencyContact.validateEmail(email);
    if (emailErr != null) throw ArgumentError(emailErr);

    final phoneErr = EmergencyContact.validatePhone(phoneNumber);
    if (phoneErr != null) throw ArgumentError(phoneErr);

    final contact = EmergencyContact.create(
      uid: user.uid,
      name: name,
      email: email,
      phoneNumber: phoneNumber,
      relationship: relationship,
    );

    // 1. Lưu SQLite cục bộ
    try {
      await _dbService.insertEmergencyContact(contact);
    } catch (e) {
      debugPrint('Lỗi lưu danh bạ vào SQLite: $e');
    }

    // 2. Đồng bộ Firestore
    final firestore = _firestore;
    if (firestore != null) {
      try {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('emergency_contacts')
            .doc(contact.id)
            .set(contact.toFirestoreMap())
            .timeout(const Duration(seconds: 7));
        await TrustedContactDashboardService.instance.syncMyStatus();
      } catch (e) {
        debugPrint('Chưa thể đồng bộ liên hệ lên Firestore: $e');
      }
    }

    return contact;
  }

  /// Cập nhật thông tin liên hệ
  /// Chú ý: Không cho phép client tự sửa emailVerified = true hay consentStatus = 'accepted'
  Future<EmergencyContact> updateContact(EmergencyContact updated) async {
    final user = _auth?.currentUser;
    if (user == null || user.uid != updated.uid) {
      throw StateError('Không có quyền cập nhật liên hệ này.');
    }

    final nameErr = EmergencyContact.validateName(updated.name);
    if (nameErr != null) throw ArgumentError(nameErr);

    final emailErr = EmergencyContact.validateEmail(updated.email);
    if (emailErr != null) throw ArgumentError(emailErr);

    final phoneErr = EmergencyContact.validatePhone(updated.phoneNumber);
    if (phoneErr != null) throw ArgumentError(phoneErr);

    final refreshed = updated.copyWith(updatedAt: DateTime.now());

    // 1. Lưu SQLite
    try {
      await _dbService.updateEmergencyContact(refreshed);
    } catch (e) {
      debugPrint('Lỗi cập nhật liên hệ trong SQLite: $e');
    }

    // 2. Lưu Firestore
    final firestore = _firestore;
    if (firestore != null) {
      try {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('emergency_contacts')
            .doc(refreshed.id)
            .set(refreshed.toFirestoreMap())
            .timeout(const Duration(seconds: 7));
        await TrustedContactDashboardService.instance.syncMyStatus();
      } catch (e) {
        debugPrint('Chưa thể cập nhật liên hệ lên Firestore: $e');
      }
    }

    return refreshed;
  }

  /// Xóa liên hệ khẩn cấp
  Future<void> deleteContact(String contactId) async {
    final user = _auth?.currentUser;
    if (user == null) return;

    // 1. Xóa SQLite
    try {
      await _dbService.deleteEmergencyContact(contactId, user.uid);
    } catch (e) {
      debugPrint('Lỗi xóa liên hệ trong SQLite: $e');
    }

    // 2. Xóa Firestore
    final firestore = _firestore;
    if (firestore != null) {
      try {
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('emergency_contacts')
            .doc(contactId)
            .delete()
            .timeout(const Duration(seconds: 7));
        await TrustedContactDashboardService.instance.syncMyStatus();
      } catch (e) {
        debugPrint('Chưa thể xóa liên hệ trên Firestore: $e');
      }
    }
  }

  /// Bật / Tắt nhận cảnh báo của người liên hệ
  Future<EmergencyContact> toggleContactActive(EmergencyContact contact) async {
    return updateContact(contact.copyWith(isActive: !contact.isActive));
  }

  /// Yêu cầu tạo mã xác minh email và gửi link đồng ý nhận cảnh báo
  Future<VerificationResult> requestContactVerification(
    String contactId,
  ) async {
    final user = _auth?.currentUser;
    if (user == null) {
      return const VerificationResult(
        success: false,
        message: 'Bạn cần đăng nhập để thực hiện thao tác này.',
      );
    }

    final functions = _functions;
    if (functions == null) {
      return const VerificationResult(
        success: false,
        message: 'Chưa khởi tạo kết nối Cloud Functions.',
      );
    }

    // The contacts screen can still show an offline SQLite copy when the
    // Firestore Emulator has no corresponding document (for example, after
    // switching from production Firebase to a fresh local emulator). The
    // callable only reads Firestore, so safely migrate an unverified,
    // pending contact before asking the server to create its token.
    final firestore = _firestore;
    if (firestore == null) {
      return const VerificationResult(
        success: false,
        message: 'Chưa khởi tạo kết nối Firestore.',
      );
    }

    try {
      final contactRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .doc(contactId);
      final remoteContact = await contactRef.get().timeout(
        const Duration(seconds: 7),
      );

      if (!remoteContact.exists) {
        final localContacts = await _dbService.getEmergencyContacts(
          uid: user.uid,
        );
        EmergencyContact? localContact;
        for (final candidate in localContacts) {
          if (candidate.id == contactId) {
            localContact = candidate;
            break;
          }
        }

        if (localContact == null ||
            localContact.uid != user.uid ||
            localContact.emailVerified ||
            localContact.consentStatus != ConsentStatus.pending) {
          return const VerificationResult(
            success: false,
            message: 'Liên hệ chưa có trên máy chủ và không thể đồng bộ an toàn. Hãy xóa rồi thêm lại liên hệ này.',
          );
        }

        await contactRef
            .set(localContact.toFirestoreMap())
            .timeout(const Duration(seconds: 7));
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ liên hệ trước khi xác minh: $e');
      return const VerificationResult(
        success: false,
        message: 'Không thể đồng bộ liên hệ lên Firebase. Hãy kiểm tra kết nối rồi thử lại.',
      );
    }

    await TrustedContactDashboardService.instance.syncMyStatus();
    return const VerificationResult(
      success: true,
      message:
          'Đã tạo lời mời demo. Người nhận hãy đăng nhập bằng Gmail này, xác minh Firebase Auth rồi chọn Đồng ý trong mục Người thân.',
      isDryRun: true,
    );
  }
}
