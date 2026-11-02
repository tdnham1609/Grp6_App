import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deadmansswitch/models/emergency_contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmergencyContact Model & Validation', () {
    test('EmergencyContact.create khởi tạo mặc định an toàn', () {
      final contact = EmergencyContact.create(
        uid: 'user_123',
        name: '  Nguyễn Văn A  ',
        email: '  UserA@Example.COM ',
        phoneNumber: '  0912345678  ',
        relationship: 'Bố mẹ',
      );

      expect(contact.uid, equals('user_123'));
      expect(contact.name, equals('Nguyễn Văn A'));
      expect(contact.email, equals('usera@example.com')); // Lowercase & trimmed
      expect(contact.phoneNumber, equals('0912345678'));
      expect(contact.relationship, equals('Bố mẹ'));
      // Ràng buộc bảo mật: Client không được tự gán verified/accepted
      expect(contact.emailVerified, isFalse);
      expect(contact.consentStatus, equals(ConsentStatus.pending));
      expect(contact.isActive, isTrue);
      expect(contact.id, isNotEmpty);
      expect(contact.createdAt, isNotNull);
      expect(contact.updatedAt, isNotNull);
    });

    test('EmergencyContact.create xử lý phoneNumber rỗng thành null', () {
      final contact = EmergencyContact.create(
        uid: 'user_123',
        name: 'Trần Thị B',
        email: 'tranthib@gmail.com',
        phoneNumber: '   ',
        relationship: 'Bạn bè',
      );

      expect(contact.phoneNumber, isNull);
    });

    test('validateName hoạt động chính xác', () {
      expect(EmergencyContact.validateName(null), contains('Vui lòng nhập'));
      expect(EmergencyContact.validateName('   '), contains('Vui lòng nhập'));
      expect(EmergencyContact.validateName('A'), contains('ít nhất 2 ký tự'));
      expect(
        EmergencyContact.validateName('A' * 61),
        contains('không được vượt quá 60'),
      );
      expect(EmergencyContact.validateName('Nguyễn Văn A'), isNull);
    });

    test('validateEmail hoạt động chính xác', () {
      expect(EmergencyContact.validateEmail(null), contains('Vui lòng nhập'));
      expect(EmergencyContact.validateEmail('   '), contains('Vui lòng nhập'));
      expect(
        EmergencyContact.validateEmail('invalid-email'),
        contains('không hợp lệ'),
      );
      expect(
        EmergencyContact.validateEmail('abc@domain'),
        contains('không hợp lệ'),
      );
      expect(EmergencyContact.validateEmail('contact@example.com'), isNull);
      expect(
        EmergencyContact.validateEmail('user.name+tag@sub.domain.vn'),
        isNull,
      );
    });

    test('validatePhone xử lý trường tùy chọn chính xác', () {
      // Tùy chọn: rỗng hoặc null được coi là hợp lệ
      expect(EmergencyContact.validatePhone(null), isNull);
      expect(EmergencyContact.validatePhone(''), isNull);
      expect(EmergencyContact.validatePhone('   '), isNull);

      // Định dạng không hợp lệ
      expect(
        EmergencyContact.validatePhone('abc123456'),
        contains('không hợp lệ'),
      );
      expect(
        EmergencyContact.validatePhone('12345'),
        contains('không hợp lệ'),
      ); // Quá ngắn (< 9)
      expect(
        EmergencyContact.validatePhone('1234567890123456'),
        contains('không hợp lệ'),
      ); // Quá dài (> 15)

      // Hợp lệ
      expect(EmergencyContact.validatePhone('0912345678'), isNull);
      expect(EmergencyContact.validatePhone('+84912345678'), isNull);
    });

    test('Serialization SQLite toSqlite và fromSqlite nhất quán', () {
      final original = EmergencyContact.create(
        uid: 'user_456',
        name: 'Lê Văn C',
        email: 'levanc@domain.com',
        phoneNumber: '0987654321',
        relationship: 'Anh/Chị/Em',
      );

      final sqliteMap = original.toSqlite();
      expect(sqliteMap['id'], equals(original.id));
      expect(sqliteMap['uid'], equals('user_456'));
      expect(sqliteMap['name'], equals('Lê Văn C'));
      expect(sqliteMap['email'], equals('levanc@domain.com'));
      expect(sqliteMap['phone_number'], equals('0987654321'));
      expect(sqliteMap['relationship'], equals('Anh/Chị/Em'));
      expect(sqliteMap['email_verified'], equals(0));
      expect(sqliteMap['consent_status'], equals('pending'));
      expect(sqliteMap['is_active'], equals(1));

      final restored = EmergencyContact.fromSqlite(sqliteMap);
      expect(restored.id, equals(original.id));
      expect(restored.uid, equals(original.uid));
      expect(restored.name, equals(original.name));
      expect(restored.email, equals(original.email));
      expect(restored.phoneNumber, equals(original.phoneNumber));
      expect(restored.relationship, equals(original.relationship));
      expect(restored.emailVerified, isFalse);
      expect(restored.consentStatus, equals(ConsentStatus.pending));
      expect(restored.isActive, isTrue);
    });

    test('Serialization Firestore toFirestoreMap và fromMap nhất quán', () {
      final now = DateTime.utc(2026, 10, 26, 10, 0, 0);
      final contact = EmergencyContact(
        id: 'contact_abc',
        uid: 'user_789',
        name: 'Phạm Thị D',
        email: 'phamthid@domain.com',
        phoneNumber: null,
        relationship: 'Vợ/Chồng',
        emailVerified: false,
        consentStatus: ConsentStatus.pending,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final firestoreMap = contact.toFirestoreMap();
      expect(firestoreMap['id'], equals('contact_abc'));
      expect(firestoreMap['uid'], equals('user_789'));
      expect(firestoreMap['emailVerified'], isFalse);
      expect(firestoreMap['consentStatus'], equals('pending'));
      expect(firestoreMap['createdAt'], isA<Timestamp>());
      expect(firestoreMap['updatedAt'], isA<Timestamp>());

      final restored = EmergencyContact.fromMap(firestoreMap);
      expect(restored.id, equals('contact_abc'));
      expect(restored.uid, equals('user_789'));
      expect(restored.name, equals('Phạm Thị D'));
      expect(restored.phoneNumber, isNull);
      expect(restored.emailVerified, isFalse);
      expect(restored.consentStatus, equals(ConsentStatus.pending));
      expect(restored.isActive, isTrue);
    });

    test(
      'copyWith cho phép thay đổi dữ liệu nhưng giữ nguyên các trường khác',
      () {
        final original = EmergencyContact.create(
          uid: 'user_111',
          name: 'Hoàng Văn E',
          email: 'hoangve@domain.com',
          relationship: 'Đồng nghiệp',
        );

        final updated = original.copyWith(
          name: 'Hoàng Văn Em',
          isActive: false,
        );

        expect(updated.id, equals(original.id));
        expect(updated.uid, equals(original.uid));
        expect(updated.name, equals('Hoàng Văn Em'));
        expect(updated.email, equals('hoangve@domain.com'));
        expect(updated.relationship, equals('Đồng nghiệp'));
        expect(updated.isActive, isFalse);
        expect(updated.emailVerified, isFalse);
      },
    );

    test('Cô lập danh bạ theo UID: Không bị trộn lẫn giữa 2 tài khoản', () {
      final contactUser1 = EmergencyContact.create(
        uid: 'uid_account_alpha',
        name: 'Người thân Alpha',
        email: 'alpha_relative@example.com',
        relationship: 'Bố mẹ',
      );

      final contactUser2 = EmergencyContact.create(
        uid: 'uid_account_beta',
        name: 'Người thân Beta',
        email: 'beta_relative@example.com',
        relationship: 'Bạn bè',
      );

      final contactList = [contactUser1, contactUser2];

      // Lọc theo UID của Alpha
      final alphaList = contactList
          .where((c) => c.uid == 'uid_account_alpha')
          .toList();
      expect(alphaList.length, equals(1));
      expect(alphaList.first.name, equals('Người thân Alpha'));
      expect(alphaList.any((c) => c.uid == 'uid_account_beta'), isFalse);

      // Lọc theo UID của Beta
      final betaList = contactList
          .where((c) => c.uid == 'uid_account_beta')
          .toList();
      expect(betaList.length, equals(1));
      expect(betaList.first.name, equals('Người thân Beta'));
      expect(betaList.any((c) => c.uid == 'uid_account_alpha'), isFalse);
    });

    test(
      'Hỗ trợ trạng thái ConsentStatus.revoked trong SQLite và Firestore',
      () {
        final contact = EmergencyContact.create(
          uid: 'user_revoked',
          name: 'Người Thân Thu Hồi',
          email: 'revoked@example.com',
          relationship: 'Bạn bè',
        ).copyWith(emailVerified: true, consentStatus: ConsentStatus.revoked);

        expect(contact.consentStatus, equals(ConsentStatus.revoked));
        expect(contact.emailVerified, isTrue);

        final sqliteMap = contact.toSqlite();
        expect(sqliteMap['consent_status'], equals('revoked'));
        expect(sqliteMap['email_verified'], equals(1));

        final restoredFromSqlite = EmergencyContact.fromSqlite(sqliteMap);
        expect(restoredFromSqlite.consentStatus, equals(ConsentStatus.revoked));
        expect(restoredFromSqlite.emailVerified, isTrue);

        final firestoreMap = contact.toFirestoreMap();
        expect(firestoreMap['consentStatus'], equals('revoked'));
        expect(firestoreMap['emailVerified'], isTrue);

        final restoredFromFirestore = EmergencyContact.fromMap(firestoreMap);
        expect(
          restoredFromFirestore.consentStatus,
          equals(ConsentStatus.revoked),
        );
        expect(restoredFromFirestore.emailVerified, isTrue);
      },
    );
  });
}
