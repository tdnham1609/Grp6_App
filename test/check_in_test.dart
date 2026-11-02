import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deadmansswitch/models/check_in.dart';

void main() {
  group('CheckIn Model', () {
    final fixedTime = DateTime(2025, 5, 20, 14, 30, 0);

    test('CheckIn.create tạo đúng giá trị mặc định', () {
      final record = CheckIn.create(uid: 'user_123', checkedInAt: fixedTime);

      expect(record.uid, equals('user_123'));
      expect(record.checkedInAt, equals(fixedTime));
      expect(record.syncStatus, equals(SyncStatus.pending));
      expect(record.isSynced, isFalse);
      expect(record.id, startsWith('checkin_'));
    });

    test('toSqlite và fromSqlite chuyển đổi chính xác', () {
      final original = CheckIn(
        id: 'test_id_1',
        uid: 'user_abc',
        checkedInAt: fixedTime,
        createdAt: fixedTime,
        syncStatus: SyncStatus.synced,
      );

      final sqliteMap = original.toSqlite();
      expect(sqliteMap['id'], equals('test_id_1'));
      expect(sqliteMap['uid'], equals('user_abc'));
      expect(sqliteMap['checked_at'], equals(fixedTime.toIso8601String()));
      expect(sqliteMap['created_at'], equals(fixedTime.toIso8601String()));
      expect(sqliteMap['sync_status'], equals(SyncStatus.synced));

      final restored = CheckIn.fromSqlite(sqliteMap);
      expect(restored.id, equals(original.id));
      expect(restored.uid, equals(original.uid));
      expect(restored.checkedInAt, equals(original.checkedInAt));
      expect(restored.syncStatus, equals(SyncStatus.synced));
      expect(restored.isSynced, isTrue);
    });

    test('toFirestoreMap chuyển đổi đúng kiểu Timestamp', () {
      final record = CheckIn(
        id: 'fire_1',
        uid: 'user_xyz',
        checkedInAt: fixedTime,
        createdAt: fixedTime,
      );

      final fireMap = record.toFirestoreMap();
      expect(fireMap['id'], equals('fire_1'));
      expect(fireMap['uid'], equals('user_xyz'));
      expect(fireMap['checkedInAt'], isA<Timestamp>());
      expect((fireMap['checkedInAt'] as Timestamp).toDate(), equals(fixedTime));
    });

    test('fromMap hỗ trợ cả Timestamp và String ISO', () {
      final mapWithTimestamp = {
        'id': 'ts_1',
        'uid': 'user_1',
        'checkedInAt': Timestamp.fromDate(fixedTime),
        'createdAt': Timestamp.fromDate(fixedTime),
        'syncStatus': SyncStatus.synced,
      };
      final fromTs = CheckIn.fromMap(mapWithTimestamp);
      expect(fromTs.checkedInAt, equals(fixedTime));
      expect(fromTs.syncStatus, equals(SyncStatus.synced));

      final mapWithString = {
        'id': 'str_1',
        'uid': 'user_2',
        'checked_at': fixedTime.toIso8601String(),
        'created_at': fixedTime.toIso8601String(),
        'sync_status': SyncStatus.pending,
      };
      final fromStr = CheckIn.fromMap(mapWithString);
      expect(fromStr.checkedInAt, equals(fixedTime));
      expect(fromStr.syncStatus, equals(SyncStatus.pending));
    });

    test('copyWith cập nhật đúng các trường được yêu cầu', () {
      final original = CheckIn(
        id: 'orig_id',
        uid: 'user_orig',
        checkedInAt: fixedTime,
        createdAt: fixedTime,
        syncStatus: SyncStatus.pending,
      );

      final updated = original.copyWith(syncStatus: SyncStatus.synced);
      expect(updated.id, equals('orig_id'));
      expect(updated.uid, equals('user_orig'));
      expect(updated.syncStatus, equals(SyncStatus.synced));
      expect(updated.isSynced, isTrue);
    });

    test('So sánh equality và Set deduplication dựa trên id', () {
      final item1 = CheckIn(
        id: 'dup_id',
        uid: 'user_1',
        checkedInAt: fixedTime,
        createdAt: fixedTime,
        syncStatus: SyncStatus.pending,
      );

      final item2 = CheckIn(
        id: 'dup_id',
        uid: 'user_1',
        checkedInAt: fixedTime,
        createdAt: fixedTime,
        syncStatus: SyncStatus.synced,
      );

      final set = <CheckIn>{item1, item2};
      // Cùng ID nên Set chỉ giữ 1 bản ghi
      expect(set.length, equals(1));
    });
  });

  group('Quy tắc an toàn dữ liệu & Đồng bộ CheckIn', () {
    test('Lọc dữ liệu theo UID - không để lộ bản ghi giữa các người dùng', () {
      final user1Records = [
        CheckIn.create(uid: 'user_A', id: 'c1'),
        CheckIn.create(uid: 'user_A', id: 'c2'),
      ];
      final user2Records = [CheckIn.create(uid: 'user_B', id: 'c3')];

      final allRecords = [...user1Records, ...user2Records];

      // Giả lập logic query theo UID
      final filteredForUserA = allRecords
          .where((r) => r.uid == 'user_A')
          .toList();
      final filteredForUserB = allRecords
          .where((r) => r.uid == 'user_B')
          .toList();

      expect(filteredForUserA.length, equals(2));
      expect(filteredForUserA.every((r) => r.uid == 'user_A'), isTrue);
      expect(filteredForUserB.length, equals(1));
      expect(filteredForUserB.first.id, equals('c3'));
    });

    test(
      'Hợp nhất dữ liệu không tạo bản ghi trùng lặp và sắp xếp mới nhất trước',
      () {
        final t1 = DateTime(2025, 5, 20, 10, 0);
        final t2 = DateTime(2025, 5, 20, 11, 0);
        final t3 = DateTime(2025, 5, 20, 12, 0);

        // Cục bộ có c1 (pending) và c2 (synced)
        final local = [
          CheckIn(
            id: 'c1',
            uid: 'u1',
            checkedInAt: t1,
            createdAt: t1,
            syncStatus: SyncStatus.pending,
          ),
          CheckIn(
            id: 'c2',
            uid: 'u1',
            checkedInAt: t2,
            createdAt: t2,
            syncStatus: SyncStatus.synced,
          ),
        ];

        // Đám mây có c2 và c3
        final remote = [
          CheckIn(
            id: 'c2',
            uid: 'u1',
            checkedInAt: t2,
            createdAt: t2,
            syncStatus: SyncStatus.synced,
          ),
          CheckIn(
            id: 'c3',
            uid: 'u1',
            checkedInAt: t3,
            createdAt: t3,
            syncStatus: SyncStatus.synced,
          ),
        ];

        // Thuật toán merge dựa trên ID map
        final mergedMap = <String, CheckIn>{};
        for (final item in local) {
          mergedMap[item.id] = item;
        }
        for (final item in remote) {
          mergedMap[item.id] = item;
        }

        final mergedList = mergedMap.values.toList()
          ..sort((a, b) => b.checkedInAt.compareTo(a.checkedInAt));

        // Kết quả phải có đúng 3 bản ghi (c1, c2, c3), không bị lặp c2
        expect(mergedList.length, equals(3));
        // Mới nhất trước: c3 -> c2 -> c1
        expect(mergedList[0].id, equals('c3'));
        expect(mergedList[1].id, equals('c2'));
        expect(mergedList[2].id, equals('c1'));
      },
    );

    test('Xử lý bản ghi offline khi chưa đăng nhập (guest)', () {
      final guestRecord = CheckIn.create(
        uid: 'guest',
        syncStatus: SyncStatus.pending,
      );

      expect(guestRecord.uid, equals('guest'));
      expect(guestRecord.isSynced, isFalse);
    });

    test('Đồng bộ thất bại: bản ghi vẫn bảo toàn trạng thái pending và dữ liệu nguyên vẹn', () {
      final offlineRecord = CheckIn.create(
        uid: 'user_live',
        id: 'check_fail_test',
        syncStatus: SyncStatus.pending,
      );

      // Giả lập hàm xử lý đồng bộ có điều kiện
      CheckIn simulateSync(CheckIn record, bool isConnected) {
        if (isConnected) {
          return record.copyWith(syncStatus: SyncStatus.synced);
        }
        return record;
      }

      final resultAfterFailure = simulateSync(offlineRecord, false);

      // Bản ghi không bị mất, vẫn giữ nguyên trạng thái pending
      expect(resultAfterFailure.id, equals('check_fail_test'));
      expect(resultAfterFailure.syncStatus, equals(SyncStatus.pending));
      expect(resultAfterFailure.isSynced, isFalse);
    });

    test('Đồng bộ thành công: cập nhật trạng thái synced', () {
      final pendingRecord = CheckIn.create(
        uid: 'user_live',
        id: 'check_success_test',
        syncStatus: SyncStatus.pending,
      );

      // Giả sử kết nối mạng thành công
      final syncedRecord = pendingRecord.copyWith(
        syncStatus: SyncStatus.synced,
      );

      expect(syncedRecord.id, equals('check_success_test'));
      expect(syncedRecord.syncStatus, equals(SyncStatus.synced));
      expect(syncedRecord.isSynced, isTrue);
    });
  });
}
