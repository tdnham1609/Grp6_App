import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:deadmansswitch/models/location_data.dart';
import 'package:deadmansswitch/services/location_service.dart';

/// Fake platform để kiểm thử LocationService mà không cần thiết bị thật
class FakeGeolocatorPlatform extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? currentPosition;
  Position? lastKnownPosition;
  Exception? errorToThrow;

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (errorToThrow != null) throw errorToThrow!;
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    if (errorToThrow != null) throw errorToThrow!;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    if (errorToThrow != null) throw errorToThrow!;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    if (currentPosition != null) return currentPosition!;
    throw const LocationServiceDisabledException();
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return lastKnownPosition;
  }
}

Position _createPosition({
  required double latitude,
  required double longitude,
  required double accuracy,
  required DateTime timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 10.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );
}

void main() {
  group('LocationData Model', () {
    final now = DateTime(2026, 10, 27, 12, 0, 0);

    test('Khởi tạo LocationData với đầy đủ thuộc tính', () {
      final loc = LocationData(
        latitude: 21.0285,
        longitude: 105.8542,
        accuracy: 8.5,
        timestamp: now,
      );

      expect(loc.latitude, equals(21.0285));
      expect(loc.longitude, equals(105.8542));
      expect(loc.accuracy, equals(8.5));
      expect(loc.timestamp, equals(now));
      expect(loc.isValid, isTrue);
    });

    test('isValid kiểm tra toạ độ hợp lệ và bất hợp lệ', () {
      // Hợp lệ
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          timestamp: now,
        ).isValid,
        isTrue,
      );
      expect(
        LocationData(
          latitude: 90,
          longitude: 180,
          timestamp: now,
        ).isValid,
        isTrue,
      );
      expect(
        LocationData(
          latitude: -90,
          longitude: -180,
          timestamp: now,
        ).isValid,
        isTrue,
      );

      // Bất hợp lệ
      expect(
        LocationData(
          latitude: 90.1,
          longitude: 100,
          timestamp: now,
        ).isValid,
        isFalse,
      );
      expect(
        LocationData(
          latitude: -90.1,
          longitude: 100,
          timestamp: now,
        ).isValid,
        isFalse,
      );
      expect(
        LocationData(
          latitude: 21,
          longitude: 180.1,
          timestamp: now,
        ).isValid,
        isFalse,
      );
      expect(
        LocationData(
          latitude: 21,
          longitude: -180.1,
          timestamp: now,
        ).isValid,
        isFalse,
      );
    });

    test('isNewerThan so sánh timestamp chính xác', () {
      final older = LocationData(
        latitude: 21.0,
        longitude: 105.0,
        timestamp: DateTime(2026, 10, 27, 10, 0, 0),
      );
      final newer = LocationData(
        latitude: 21.0,
        longitude: 105.0,
        timestamp: DateTime(2026, 10, 27, 11, 0, 0),
      );

      expect(newer.isNewerThan(older), isTrue);
      expect(older.isNewerThan(newer), isFalse);
    });

    test('accuracyFormatted trả về nhãn chính xác theo độ lớn', () {
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          accuracy: null,
          timestamp: now,
        ).accuracyFormatted,
        equals('Không rõ'),
      );
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          accuracy: 5.0,
          timestamp: now,
        ).accuracyFormatted,
        contains('Rất cao'),
      );
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          accuracy: 25.0,
          timestamp: now,
        ).accuracyFormatted,
        contains('Cao'),
      );
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          accuracy: 75.0,
          timestamp: now,
        ).accuracyFormatted,
        contains('Trung bình'),
      );
      expect(
        LocationData(
          latitude: 0,
          longitude: 0,
          accuracy: 150.0,
          timestamp: now,
        ).accuracyFormatted,
        contains('Thấp'),
      );
    });

    test('toSqlite và fromSqlite chuyển đổi dữ liệu toàn vẹn', () {
      final loc = LocationData(
        latitude: 21.0285,
        longitude: 105.8542,
        accuracy: 12.3,
        timestamp: now,
      );

      final map = loc.toSqlite();
      expect(map['latitude'], equals(21.0285));
      expect(map['longitude'], equals(105.8542));
      expect(map['accuracy'], equals(12.3));
      expect(map['location_timestamp'], equals(now.toIso8601String()));

      final restored = LocationData.fromSqlite(map);
      expect(restored, isNotNull);
      expect(restored!.latitude, equals(loc.latitude));
      expect(restored.longitude, equals(loc.longitude));
      expect(restored.accuracy, equals(loc.accuracy));
      expect(restored.timestamp, equals(loc.timestamp));
    });

    test('fromSqlite trả về null khi dữ liệu thiếu hoặc không hợp lệ', () {
      expect(LocationData.fromSqlite({}), isNull);
      expect(
        LocationData.fromSqlite({
          'latitude': 21.0,
          'longitude': 105.0,
          // thiếu timestamp
        }),
        isNull,
      );
      expect(
        LocationData.fromSqlite({
          'latitude': 21.0,
          'longitude': 105.0,
          'location_timestamp': 'invalid-date-string',
        }),
        isNull,
      );
    });

    test('toString không làm lộ toạ độ chi tiết vì lý do bảo mật riêng tư', () {
      final loc = LocationData(
        latitude: 21.028511,
        longitude: 105.854299,
        accuracy: 10.0,
        timestamp: now,
      );

      final str = loc.toString();
      expect(str, isNot(contains('21.028511')));
      expect(str, isNot(contains('105.854299')));
      expect(str, contains('LocationData'));
      expect(str, contains('accuracy'));
    });

    test('Equality và hashCode hoạt động chuẩn xác', () {
      final loc1 = LocationData(
        latitude: 21.0,
        longitude: 105.0,
        timestamp: now,
      );
      final loc2 = LocationData(
        latitude: 21.0,
        longitude: 105.0,
        timestamp: now,
      );
      final loc3 = LocationData(
        latitude: 21.1,
        longitude: 105.0,
        timestamp: now,
      );

      expect(loc1, equals(loc2));
      expect(loc1.hashCode, equals(loc2.hashCode));
      expect(loc1, isNot(equals(loc3)));
    });
  });

  group('LocationResult Model', () {
    test('LocationResult.success tạo đối tượng thành công', () {
      final loc = LocationData(
        latitude: 10.0,
        longitude: 20.0,
        timestamp: DateTime.now(),
      );
      final result = LocationResult.success(loc);

      expect(result.isSuccess, isTrue);
      expect(result.location, equals(loc));
      expect(result.errorMessage, isNull);
    });

    test('LocationResult.failure tạo đối tượng thất bại với thông báo', () {
      final result = LocationResult.failure('Lỗi GPS');

      expect(result.isSuccess, isFalse);
      expect(result.location, isNull);
      expect(result.errorMessage, equals('Lỗi GPS'));
    });
  });

  group('LocationService với FakeGeolocatorPlatform', () {
    late FakeGeolocatorPlatform fakePlatform;
    late LocationService locationService;
    final now = DateTime(2026, 10, 27, 14, 0, 0);

    setUp(() {
      fakePlatform = FakeGeolocatorPlatform();
      locationService = LocationService(geolocator: fakePlatform);
    });

    test('isLocationServiceEnabled gọi platform đúng cách', () async {
      fakePlatform.serviceEnabled = true;
      expect(await locationService.isLocationServiceEnabled(), isTrue);

      fakePlatform.serviceEnabled = false;
      expect(await locationService.isLocationServiceEnabled(), isFalse);
    });

    test('checkPermission trả về serviceDisabled nếu GPS tắt', () async {
      fakePlatform.serviceEnabled = false;
      final status = await locationService.checkPermission();
      expect(status, equals(LocationPermissionStatus.serviceDisabled));
    });

    test('checkPermission ánh xạ các quyền chính xác', () async {
      fakePlatform.serviceEnabled = true;

      fakePlatform.permission = LocationPermission.whileInUse;
      expect(
        await locationService.checkPermission(),
        equals(LocationPermissionStatus.granted),
      );

      fakePlatform.permission = LocationPermission.always;
      expect(
        await locationService.checkPermission(),
        equals(LocationPermissionStatus.granted),
      );

      fakePlatform.permission = LocationPermission.denied;
      expect(
        await locationService.checkPermission(),
        equals(LocationPermissionStatus.denied),
      );

      fakePlatform.permission = LocationPermission.deniedForever;
      expect(
        await locationService.checkPermission(),
        equals(LocationPermissionStatus.deniedForever),
      );

      fakePlatform.permission = LocationPermission.unableToDetermine;
      expect(
        await locationService.checkPermission(),
        equals(LocationPermissionStatus.notDetermined),
      );
    });

    test('requestPermission trả về serviceDisabled nếu GPS tắt', () async {
      fakePlatform.serviceEnabled = false;
      final status = await locationService.requestPermission();
      expect(status, equals(LocationPermissionStatus.serviceDisabled));
    });

    test('requestPermission trả về granted nếu quyền đã được cấp trước đó',
        () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.whileInUse;

      final status = await locationService.requestPermission();
      expect(status, equals(LocationPermissionStatus.granted));
    });

    test('requestPermission trả về deniedForever nếu đã bị từ chối vĩnh viễn',
        () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.deniedForever;

      final status = await locationService.requestPermission();
      expect(status, equals(LocationPermissionStatus.deniedForever));
    });

    test('getCurrentLocation trả về lỗi nếu GPS bị tắt', () async {
      fakePlatform.serviceEnabled = false;

      final result = await locationService.getCurrentLocation();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Dịch vụ GPS đang tắt'));
    });

    test('getCurrentLocation trả về lỗi nếu chưa cấp quyền', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.denied;

      final result = await locationService.getCurrentLocation();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Chưa được cấp quyền'));
    });

    test('getCurrentLocation thành công khi có đủ điều kiện', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.whileInUse;
      fakePlatform.currentPosition = _createPosition(
        latitude: 21.0285,
        longitude: 105.8542,
        accuracy: 15.0,
        timestamp: now,
      );

      final result = await locationService.getCurrentLocation();
      expect(result.isSuccess, isTrue);
      expect(result.location, isNotNull);
      expect(result.location!.latitude, equals(21.0285));
      expect(result.location!.longitude, equals(105.8542));
      expect(result.location!.accuracy, equals(15.0));
    });

    test('getCurrentLocation xử lý TimeoutException an toàn', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.whileInUse;
      fakePlatform.errorToThrow = TimeoutException('GPS timeout');

      final result = await locationService.getCurrentLocation();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Hết thời gian chờ GPS'));
    });

    test('getLastKnownLocation thành công khi có cache', () async {
      fakePlatform.lastKnownPosition = _createPosition(
        latitude: 10.7769,
        longitude: 106.7009,
        accuracy: 20.0,
        timestamp: now,
      );

      final result = await locationService.getLastKnownLocation();
      expect(result.isSuccess, isTrue);
      expect(result.location, isNotNull);
      expect(result.location!.latitude, equals(10.7769));
      expect(result.location!.longitude, equals(106.7009));
    });

    test('getLastKnownLocation trả về failure khi cache rỗng', () async {
      fakePlatform.lastKnownPosition = null;

      final result = await locationService.getLastKnownLocation();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Không có vị trí đã biết'));
    });
  });
}
