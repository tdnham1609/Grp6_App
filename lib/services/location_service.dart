import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_data.dart';

/// Trạng thái quyền vị trí dạng đơn giản để UI sử dụng
enum LocationPermissionStatus {
  /// Quyền đã được cấp (whenInUse hoặc always)
  granted,

  /// Người dùng chưa quyết định (chưa được hỏi)
  notDetermined,

  /// Người dùng đã từ chối nhưng có thể hỏi lại
  denied,

  /// Người dùng đã từ chối vĩnh viễn — cần vào Settings hệ thống để bật
  deniedForever,

  /// Dịch vụ GPS trên thiết bị bị tắt
  serviceDisabled,
}

/// Kết quả lấy vị trí, bao gồm cả trường hợp lỗi
class LocationResult {
  final LocationData? location;
  final String? errorMessage;
  final bool isSuccess;

  const LocationResult._({this.location, this.errorMessage, required this.isSuccess});

  factory LocationResult.success(LocationData location) =>
      LocationResult._(location: location, isSuccess: true);

  factory LocationResult.failure(String message) =>
      LocationResult._(errorMessage: message, isSuccess: false);
}

/// Service quản lý quyền truy cập và lấy vị trí GPS
///
/// Nguyên tắc thiết kế:
/// - Chỉ lấy vị trí khi người dùng chủ động yêu cầu
/// - Chỉ xin quyền foreground (whenInUse), không yêu cầu background
/// - Không theo dõi GPS liên tục
/// - Không làm app crash khi định vị thất bại
/// - Không ghi toạ độ GPS vào log
class LocationService {
  /// GeolocatorPlatform cho phép inject mock trong test
  final GeolocatorPlatform _geolocator;

  static final LocationService instance = LocationService();

  LocationService({GeolocatorPlatform? geolocator})
      : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  /// Thời gian tối đa chờ lấy vị trí trước khi timeout
  static const Duration _locationTimeout = Duration(seconds: 15);

  // ─── QUẢN LÝ QUYỀN ─────────────────────────────────────────────────────

  /// Kiểm tra dịch vụ GPS trên thiết bị có đang bật không
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await _geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Lỗi kiểm tra dịch vụ GPS: $e');
      return false;
    }
  }

  /// Kiểm tra trạng thái quyền vị trí hiện tại
  /// Không hiển thị dialog xin quyền — chỉ kiểm tra
  Future<LocationPermissionStatus> checkPermission() async {
    try {
      final serviceEnabled = await _geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }

      final permission = await _geolocator.checkPermission();
      return _mapPermission(permission);
    } catch (e) {
      debugPrint('Lỗi kiểm tra quyền vị trí: $e');
      return LocationPermissionStatus.denied;
    }
  }

  /// Yêu cầu người dùng cấp quyền vị trí
  /// Chỉ gọi khi người dùng chủ động bật tính năng chia sẻ vị trí
  Future<LocationPermissionStatus> requestPermission() async {
    try {
      final serviceEnabled = await _geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }

      // Kiểm tra quyền hiện tại trước khi hỏi
      final currentPermission = await _geolocator.checkPermission();
      if (currentPermission == LocationPermission.whileInUse ||
          currentPermission == LocationPermission.always) {
        return LocationPermissionStatus.granted;
      }

      if (currentPermission == LocationPermission.deniedForever) {
        return LocationPermissionStatus.deniedForever;
      }

      // Hiển thị dialog xin quyền hệ thống
      final result = await _geolocator.requestPermission();
      return _mapPermission(result);
    } catch (e) {
      debugPrint('Lỗi yêu cầu quyền vị trí: $e');
      return LocationPermissionStatus.denied;
    }
  }

  // ─── LẤY VỊ TRÍ ──────────────────────────────────────────────────────

  /// Lấy vị trí hiện tại của thiết bị
  ///
  /// Yêu cầu: Quyền vị trí đã được cấp VÀ GPS đang bật
  /// Nếu thất bại, trả về [LocationResult.failure] kèm thông báo lỗi rõ ràng
  /// Không bao giờ throw exception ra ngoài
  Future<LocationResult> getCurrentLocation() async {
    try {
      // Kiểm tra dịch vụ GPS
      final serviceEnabled = await _geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failure(
          'Dịch vụ GPS đang tắt. Vui lòng bật GPS trong cài đặt thiết bị.',
        );
      }

      // Kiểm tra quyền
      final permission = await _geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationResult.failure(
          'Chưa được cấp quyền truy cập vị trí. Vui lòng cấp quyền trong cài đặt ứng dụng.',
        );
      }

      // Lấy vị trí với timeout để không treo app vô hạn
      final position = await _geolocator
          .getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: _locationTimeout,
            ),
          );

      final locationData = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy > 0 ? position.accuracy : null,
        timestamp: position.timestamp,
      );

      if (!locationData.isValid) {
        return LocationResult.failure(
          'Vị trí nhận được không hợp lệ. Vui lòng thử lại.',
        );
      }

      return LocationResult.success(locationData);
    } on TimeoutException {
      return LocationResult.failure(
        'Hết thời gian chờ GPS. Vui lòng đảm bảo bạn ở nơi có tín hiệu GPS tốt và thử lại.',
      );
    } on LocationServiceDisabledException {
      return LocationResult.failure(
        'Dịch vụ GPS đang tắt. Vui lòng bật GPS trong cài đặt thiết bị.',
      );
    } on PermissionDeniedException {
      return LocationResult.failure(
        'Quyền truy cập vị trí bị từ chối.',
      );
    } catch (e) {
      debugPrint('Lỗi lấy vị trí hiện tại: $e');
      return LocationResult.failure(
        'Không thể lấy vị trí. Vui lòng kiểm tra GPS và thử lại.',
      );
    }
  }

  /// Lấy vị trí cuối cùng đã biết từ cache hệ thống
  ///
  /// Nhanh hơn getCurrentLocation nhưng có thể trả về vị trí cũ hoặc null
  /// UI phải hiển thị rõ timestamp để người dùng biết vị trí này không phải vị trí hiện tại
  Future<LocationResult> getLastKnownLocation() async {
    try {
      final position = await _geolocator.getLastKnownPosition();
      if (position == null) {
        return LocationResult.failure(
          'Không có vị trí đã biết trước đó trên thiết bị.',
        );
      }

      final locationData = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy > 0 ? position.accuracy : null,
        timestamp: position.timestamp,
      );

      if (!locationData.isValid) {
        return LocationResult.failure(
          'Vị trí đã biết không hợp lệ.',
        );
      }

      return LocationResult.success(locationData);
    } catch (e) {
      debugPrint('Lỗi lấy vị trí đã biết: $e');
      return LocationResult.failure(
        'Không thể lấy vị trí đã biết trước đó.',
      );
    }
  }

  // ─── TIỆN ÍCH NỘI BỘ ──────────────────────────────────────────────────

  /// Chuyển đổi từ enum geolocator sang enum đơn giản của ứng dụng
  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.notDetermined;
    }
  }
}
