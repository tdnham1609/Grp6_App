import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deadmansswitch/models/user_profile.dart';

void main() {
  group('UserProfile', () {
    final now = DateTime(2024, 1, 15, 10, 30);

    final sampleMap = {
      'uid': 'test-uid-123',
      'displayName': 'Nguyễn Văn A',
      'email': 'test@gmail.com',
      'photoUrl': null,
      'provider': 'password',
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };

    test('fromMap tạo đúng từ Map', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');

      expect(profile.uid, equals('test-uid-123'));
      expect(profile.displayName, equals('Nguyễn Văn A'));
      expect(profile.email, equals('test@gmail.com'));
      expect(profile.photoUrl, isNull);
      expect(profile.provider, equals('password'));
      expect(profile.createdAt, equals(now));
    });

    test('fromMap dùng uid tham số nếu map không có uid', () {
      final mapWithoutUid = Map<String, dynamic>.from(sampleMap)..remove('uid');
      final profile = UserProfile.fromMap(mapWithoutUid, 'fallback-uid');

      expect(profile.uid, equals('fallback-uid'));
    });

    test('fromMap dùng giá trị mặc định nếu thiếu trường', () {
      final sparseMap = {
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };
      final profile = UserProfile.fromMap(sparseMap, 'uid-fallback');

      expect(profile.displayName, equals(''));
      expect(profile.email, equals(''));
      expect(profile.provider, equals('password'));
    });

    test('copyWith thay đổi đúng trường', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');
      final updated = profile.copyWith(displayName: 'Trần Thị B');

      expect(updated.displayName, equals('Trần Thị B'));
      expect(updated.email, equals(profile.email));
      expect(updated.uid, equals(profile.uid));
      expect(updated.provider, equals(profile.provider));
    });

    test('copyWith không thay đổi trường không được chỉ định', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');
      final updated = profile.copyWith();

      expect(updated.displayName, equals(profile.displayName));
      expect(updated.photoUrl, equals(profile.photoUrl));
    });

    test('toCreateMap chứa đúng các key cần thiết', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');
      final map = profile.toCreateMap();

      expect(map.containsKey('uid'), isTrue);
      expect(map.containsKey('displayName'), isTrue);
      expect(map.containsKey('email'), isTrue);
      expect(map.containsKey('photoUrl'), isTrue);
      expect(map.containsKey('provider'), isTrue);
      expect(map.containsKey('createdAt'), isTrue);
      expect(map.containsKey('updatedAt'), isTrue);
      // createdAt và updatedAt phải là FieldValue.serverTimestamp()
      expect(map['createdAt'], isA<FieldValue>());
      expect(map['updatedAt'], isA<FieldValue>());
    });

    test('toCreateMap không lưu mật khẩu hay token', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');
      final map = profile.toCreateMap();

      expect(map.containsKey('password'), isFalse);
      expect(map.containsKey('token'), isFalse);
      expect(map.containsKey('idToken'), isFalse);
      expect(map.containsKey('accessToken'), isFalse);
    });

    test('toString trả về chuỗi có thông tin cần thiết', () {
      final profile = UserProfile.fromMap(sampleMap, 'test-uid-123');
      final str = profile.toString();

      expect(str, contains('test-uid-123'));
      expect(str, contains('Nguyễn Văn A'));
      expect(str, contains('password'));
    });

    test('_timestampToDateTime trả về DateTime.now() khi val null', () {
      final sparseMap = {'createdAt': null, 'updatedAt': null};
      // Không throw
      expect(() => UserProfile.fromMap(sparseMap, 'uid'), returnsNormally);
    });
  });
}
