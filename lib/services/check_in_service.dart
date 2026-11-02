import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/check_in.dart';
import '../models/location_data.dart';
import 'database_service.dart';
import 'check_in_config_service.dart';
import 'location_service.dart';

/// Kết quả sau khi thực hiện thao tác check-in
class CheckInResult {
  final CheckIn checkIn;
  final bool isSynced;
  final String? message;

  const CheckInResult({
    required this.checkIn,
    required this.isSynced,
    this.message,
  });
}

/// Service điều phối nghiệp vụ check-in an toàn
/// Quản lý luồng lưu SQLite cục bộ (offline-first) và đồng bộ Cloud Firestore
class CheckInService {
  final DatabaseService? _customDbService;
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final LocationService? _customLocationService;

  bool _isSyncing = false;

  /// Singleton mặc định
  static final CheckInService instance = CheckInService();

  CheckInService({
    DatabaseService? dbService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    LocationService? locationService,
  }) : _customDbService = dbService,
       _customFirestore = firestore,
       _customAuth = auth,
       _customLocationService = locationService;

  DatabaseService get _dbService =>
      _customDbService ?? DatabaseService.instance;

  LocationService get _locationService =>
      _customLocationService ?? LocationService.instance;

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

  /// Lấy UID của người dùng hiện tại từ Firebase Auth
  /// Đảm bảo không nhận UID tuỳ ý từ UI để bảo vệ quyền sở hữu
  String? get currentUid => _auth?.currentUser?.uid;

  /// Kiểm tra có đang trong quá trình đồng bộ hay không
  bool get isSyncing => _isSyncing;

  /// Ghi nhận lượt check-in an toàn mới
  /// 1. Ghi nhận thời gian hiện tại
  /// 2. Lưu ngay vào SQLite cục bộ (hoạt động kể cả khi mất mạng)
  /// 3. Nếu người dùng đã đăng nhập, thử đồng bộ lên Firestore: users/{uid}/checkins/{checkinId}
  /// 4. Không bao giờ làm ứng dụng bị crash nếu kết nối mạng thất bại
  Future<CheckInResult> recordCheckIn() async {
    final user = _auth?.currentUser;
    final uid = user?.uid ?? 'guest';
    final now = DateTime.now();

    var record = CheckIn.create(
      uid: uid,
      checkedInAt: now,
      syncStatus: SyncStatus.pending,
    );

    // 1. Lưu SQLite cục bộ trước tiên
    try {
      await _dbService.insertCheckIn(record);
    } catch (e) {
      debugPrint('Lỗi lưu SQLite check-in: $e');
    }

    // Cập nhật cấu hình thời hạn an toàn tiếp theo & lên lịch nhắc nhở
    try {
      await CheckInConfigService.instance.updateOnCheckIn(now);
    } catch (e) {
      debugPrint('Lỗi cập nhật hạn an toàn sau check-in: $e');
    }

    // Nếu chưa đăng nhập Firebase hoặc Firebase chưa khởi tạo, kết thúc ở trạng thái lưu cục bộ
    final firestore = _firestore;
    if (user == null || firestore == null) {
      return CheckInResult(
        checkIn: record,
        isSynced: false,
        message: 'Đã lưu an toàn trên thiết bị (Chưa đăng nhập tài khoản).',
      );
    }

    // 2. Thử đồng bộ lên Cloud Firestore
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('checkins')
          .doc(record.id)
          .set(record.toFirestoreMap())
          .timeout(const Duration(seconds: 7));

      // Đồng bộ thành công -> Cập nhật trạng thái SQLite
      await _dbService.markAsSynced(record.id);
      record = record.copyWith(syncStatus: SyncStatus.synced);

      // Tự động cập nhật vị trí lần cuối cùng của user vào cài đặt checkin nếu đang bật chia sẻ vị trí
      try {
        final isLocSharing = await _dbService.isLocationSharingEnabled(user.uid);
        if (isLocSharing) {
          LocationData? loc;
          final cached = await _locationService.getLastKnownLocation();
          if (cached.isSuccess && cached.location != null) {
            loc = cached.location;
          }
          try {
            final fresh = await _locationService.getCurrentLocation();
            if (fresh.isSuccess && fresh.location != null) {
              loc = fresh.location;
            }
          } catch (_) {}

          if (loc != null) {
            await _dbService.saveLastLocation(user.uid, loc);
            await firestore
                .collection('users')
                .doc(user.uid)
                .collection('settings')
                .doc('checkin')
                .set({
                  'isLocationSharingEnabled': true,
                  'lastKnownLocation': {
                    'latitude': loc.latitude,
                    'longitude': loc.longitude,
                    if (loc.accuracy != null) 'accuracy': loc.accuracy,
                    'timestamp': Timestamp.fromDate(loc.timestamp),
                  },
                }, SetOptions(merge: true));
          }
        }
      } catch (locErr) {
        debugPrint('Không thể đồng bộ vị trí khi check-in: $locErr');
      }

      return CheckInResult(
        checkIn: record,
        isSynced: true,
        message: 'Đã xác nhận an toàn và đồng bộ đám mây thành công!',
      );
    } catch (e) {
      // Bắt mọi lỗi mạng, timeout hoặc permission
      debugPrint('Chưa thể đồng bộ check-in lên Firestore: $e');
      return CheckInResult(
        checkIn: record,
        isSynced: false,
        message: 'Đã lưu an toàn trên máy. Sẽ tự động đồng bộ khi có mạng.',
      );
    }
  }

  /// Đồng bộ tất cả các bản ghi check-in đang chờ (pending) lên Cloud Firestore
  /// Có cờ chống gọi lặp, không tạo vòng lặp vô hạn
  Future<int> syncPendingCheckIns() async {
    if (_isSyncing) return 0;

    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user == null || firestore == null) return 0;

    _isSyncing = true;
    int syncedCount = 0;

    try {
      final pendingList = await _dbService.getPendingCheckIns(user.uid);
      if (pendingList.isEmpty) {
        return 0;
      }

      for (final record in pendingList) {
        try {
          await firestore
              .collection('users')
              .doc(user.uid)
              .collection('checkins')
              .doc(record.id)
              .set(record.toFirestoreMap())
              .timeout(const Duration(seconds: 7));

          await _dbService.markAsSynced(record.id);
          syncedCount++;
        } catch (e) {
          debugPrint('Lỗi đồng bộ bản ghi ${record.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('Lỗi quét bản ghi chờ đồng bộ: $e');
    } finally {
      _isSyncing = false;
    }

    return syncedCount;
  }

  /// Lấy toàn bộ lịch sử check-in của người dùng hiện tại
  /// - Kết hợp lịch sử cục bộ SQLite và Cloud Firestore
  /// - Loại bỏ trùng lặp dựa trên ID duy nhất
  /// - Không để lộ dữ liệu của người dùng khác khi đăng xuất
  Future<List<CheckIn>> getCheckInHistory() async {
    final user = _auth?.currentUser;
    if (user == null) {
      return [];
    }

    // 1. Đọc dữ liệu cục bộ trước (phản hồi tức thì)
    List<CheckIn> localList = [];
    try {
      localList = await _dbService.getCheckIns(uid: user.uid);
    } catch (e) {
      debugPrint('Lỗi đọc check-ins từ SQLite: $e');
    }

    final firestore = _firestore;
    if (firestore == null) {
      return localList;
    }

    // 2. Thử tải dữ liệu mới nhất từ Firestore
    try {
      final querySnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('checkins')
          .orderBy('checkedInAt', descending: true)
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 7));

      final remoteList = querySnapshot.docs
          .map((doc) => CheckIn.fromFirestore(doc))
          .toList();

      if (remoteList.isNotEmpty) {
        // Cập nhật lại SQLite để đồng bộ cho các lần mở app offline tiếp theo
        await _dbService.upsertCheckIns(remoteList);
      }

      // Hợp nhất dữ liệu tránh trùng lặp: Map key là id
      final map = <String, CheckIn>{};
      for (final item in localList) {
        map[item.id] = item;
      }
      for (final item in remoteList) {
        // Dữ liệu từ Firestore chắc chắn là đã synced
        map[item.id] = item;
      }

      final combined = map.values.toList()
        ..sort((a, b) => b.checkedInAt.compareTo(a.checkedInAt));

      return combined;
    } catch (e) {
      debugPrint('Không thể tải lịch sử từ Firestore (Offline mode): $e');
      // Trả về dữ liệu cục bộ khi offline
      return localList;
    }
  }

  /// Lấy thời điểm check-in gần đây nhất
  Future<DateTime?> getLatestCheckInTime() async {
    final user = _auth?.currentUser;
    if (user == null) return null;

    final latest = await _dbService.getLatestCheckIn(user.uid);
    return latest?.checkedInAt;
  }
}
