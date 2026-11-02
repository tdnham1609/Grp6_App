import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/check_in.dart';
import '../models/check_in_config.dart';
import '../models/emergency_contact.dart';
import '../models/location_data.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sinh_tu.db');

    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE check_ins (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            checked_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');

        await db.execute('''
          CREATE TABLE user_settings (
            uid TEXT PRIMARY KEY,
            interval_hours INTEGER NOT NULL DEFAULT 24,
            reminder_minutes INTEGER NOT NULL DEFAULT 120,
            is_reminder_enabled INTEGER NOT NULL DEFAULT 1,
            last_checkin_at TEXT,
            next_due_at TEXT,
            updated_at TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            accuracy REAL,
            location_timestamp TEXT,
            is_location_sharing_enabled INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE emergency_contacts (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone_number TEXT,
            relationship TEXT NOT NULL,
            email_verified INTEGER NOT NULL DEFAULT 0,
            consent_status TEXT NOT NULL DEFAULT 'pending',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migration an toàn từ version 1 sang version 2:
          final tableInfo = await db.rawQuery("PRAGMA table_info('check_ins')");
          final existingColumns = tableInfo
              .map((col) => col['name'] as String)
              .toSet();

          if (!existingColumns.contains('uid') ||
              !existingColumns.contains('sync_status')) {
            await db.execute('ALTER TABLE check_ins RENAME TO check_ins_old');

            await db.execute('''
              CREATE TABLE check_ins (
                id TEXT PRIMARY KEY,
                uid TEXT NOT NULL,
                checked_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                sync_status TEXT NOT NULL DEFAULT 'pending'
              )
            ''');

            final oldRecords = await db.query('check_ins_old');
            for (final row in oldRecords) {
              final oldId = row['id'];
              final checkedAt =
                  row['checked_at'] as String? ??
                  DateTime.now().toIso8601String();
              await db.insert('check_ins', {
                'id': 'legacy_$oldId',
                'uid': '',
                'checked_at': checkedAt,
                'created_at': checkedAt,
                'sync_status': SyncStatus.pending,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }

            await db.execute('DROP TABLE check_ins_old');
          }
        }

        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS user_settings (
              uid TEXT PRIMARY KEY,
              interval_hours INTEGER NOT NULL DEFAULT 24,
              reminder_minutes INTEGER NOT NULL DEFAULT 120,
              is_reminder_enabled INTEGER NOT NULL DEFAULT 1,
              last_checkin_at TEXT,
              next_due_at TEXT,
              updated_at TEXT NOT NULL
            )
          ''');
        }

        if (oldVersion < 4) {
          // Migration sang version 4: Tạo bảng danh bạ khẩn cấp
          await db.execute('''
            CREATE TABLE IF NOT EXISTS emergency_contacts (
              id TEXT PRIMARY KEY,
              uid TEXT NOT NULL,
              name TEXT NOT NULL,
              email TEXT NOT NULL,
              phone_number TEXT,
              relationship TEXT NOT NULL,
              email_verified INTEGER NOT NULL DEFAULT 0,
              consent_status TEXT NOT NULL DEFAULT 'pending',
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        }

        if (oldVersion < 5) {
          // Migration sang version 5: Thêm cột vị trí vào bảng user_settings
          final tableInfo = await db.rawQuery(
            "PRAGMA table_info('user_settings')",
          );
          final existingColumns = tableInfo
              .map((col) => col['name'] as String)
              .toSet();

          if (!existingColumns.contains('latitude')) {
            await db.execute(
              'ALTER TABLE user_settings ADD COLUMN latitude REAL',
            );
          }
          if (!existingColumns.contains('longitude')) {
            await db.execute(
              'ALTER TABLE user_settings ADD COLUMN longitude REAL',
            );
          }
          if (!existingColumns.contains('accuracy')) {
            await db.execute(
              'ALTER TABLE user_settings ADD COLUMN accuracy REAL',
            );
          }
          if (!existingColumns.contains('location_timestamp')) {
            await db.execute(
              'ALTER TABLE user_settings ADD COLUMN location_timestamp TEXT',
            );
          }
          if (!existingColumns.contains('is_location_sharing_enabled')) {
            await db.execute(
              'ALTER TABLE user_settings ADD COLUMN is_location_sharing_enabled INTEGER NOT NULL DEFAULT 0',
            );
          }
        }
      },
    );
  }

  // ─── CHECK-IN OPERATIONS ───────────────────────────────────────────────

  Future<int> insertCheckIn(CheckIn checkIn) async {
    final db = await database;
    return db.insert(
      'check_ins',
      checkIn.toSqlite(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCheckIns(List<CheckIn> checkIns) async {
    final db = await database;
    final batch = db.batch();
    for (final item in checkIns) {
      batch.insert(
        'check_ins',
        item.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CheckIn>> getCheckIns({required String uid}) async {
    if (uid.isEmpty) return [];

    final db = await database;
    final rows = await db.query(
      'check_ins',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'checked_at DESC',
    );

    return rows.map(CheckIn.fromSqlite).toList();
  }

  Future<List<CheckIn>> getPendingCheckIns(String uid) async {
    if (uid.isEmpty) return [];

    final db = await database;
    final rows = await db.query(
      'check_ins',
      where: 'uid = ? AND sync_status = ?',
      whereArgs: [uid, SyncStatus.pending],
      orderBy: 'checked_at ASC',
    );

    return rows.map(CheckIn.fromSqlite).toList();
  }

  Future<int> markAsSynced(String id) async {
    final db = await database;
    return db.update(
      'check_ins',
      {'sync_status': SyncStatus.synced},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<CheckIn?> getLatestCheckIn(String uid) async {
    if (uid.isEmpty) return null;

    final db = await database;
    final rows = await db.query(
      'check_ins',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'checked_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return CheckIn.fromSqlite(rows.first);
  }

  // ─── SETTINGS OPERATIONS ───────────────────────────────────────────────

  Future<int> saveCheckInConfig(String uid, CheckInConfig config) async {
    if (uid.isEmpty) return 0;

    final db = await database;
    final existingRows = await db.query(
      'user_settings',
      columns: ['uid'],
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      return db.insert('user_settings', config.toSqlite(uid));
    }
    return db.update(
      'user_settings',
      config.toSqlite(uid)..remove('uid'),
      where: 'uid = ?',
      whereArgs: [uid],
    );
  }

  Future<CheckInConfig?> getCheckInConfig(String uid) async {
    if (uid.isEmpty) return null;

    final db = await database;
    final rows = await db.query(
      'user_settings',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return CheckInConfig.fromSqlite(rows.first);
  }

  // ─── EMERGENCY CONTACTS OPERATIONS ─────────────────────────────────────

  /// Thêm hoặc ghi đè liên hệ khẩn cấp vào SQLite
  Future<int> insertEmergencyContact(EmergencyContact contact) async {
    final db = await database;
    return db.insert(
      'emergency_contacts',
      contact.toSqlite(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cập nhật liên hệ khẩn cấp
  Future<int> updateEmergencyContact(EmergencyContact contact) async {
    final db = await database;
    return db.update(
      'emergency_contacts',
      contact.toSqlite(),
      where: 'id = ? AND uid = ?',
      whereArgs: [contact.id, contact.uid],
    );
  }

  /// Xóa liên hệ khẩn cấp khỏi SQLite
  Future<int> deleteEmergencyContact(String id, String uid) async {
    final db = await database;
    return db.delete(
      'emergency_contacts',
      where: 'id = ? AND uid = ?',
      whereArgs: [id, uid],
    );
  }

  /// Lấy danh sách liên hệ khẩn cấp theo UID (cô lập tài khoản)
  Future<List<EmergencyContact>> getEmergencyContacts({
    required String uid,
  }) async {
    if (uid.isEmpty) return [];

    final db = await database;
    final rows = await db.query(
      'emergency_contacts',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'created_at DESC',
    );

    return rows.map(EmergencyContact.fromSqlite).toList();
  }

  /// Upsert hàng loạt liên hệ từ Firestore về SQLite để cache offline
  Future<void> upsertEmergencyContacts(List<EmergencyContact> contacts) async {
    final db = await database;
    final batch = db.batch();
    for (final contact in contacts) {
      batch.insert(
        'emergency_contacts',
        contact.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ─── LOCATION OPERATIONS ───────────────────────────────────────────────

  /// Lưu vị trí gần nhất vào SQLite
  /// Kiểm tra timestamp: không ghi đè dữ liệu mới bằng dữ liệu cũ hơn
  Future<bool> saveLastLocation(String uid, LocationData location) async {
    if (uid.isEmpty) return false;

    final db = await database;
    await _ensureUserSettingsRow(db, uid);

    // Kiểm tra vị trí hiện tại trong DB có mới hơn không
    final existing = await getLastLocation(uid);
    if (existing != null && !location.isNewerThan(existing)) {
      return false; // Không ghi đè dữ liệu mới bằng dữ liệu cũ
    }

    final locationMap = location.toSqlite();
    await db.update(
      'user_settings',
      locationMap,
      where: 'uid = ?',
      whereArgs: [uid],
    );

    return true;
  }

  /// Đọc vị trí gần nhất đã lưu từ SQLite
  Future<LocationData?> getLastLocation(String uid) async {
    if (uid.isEmpty) return null;

    final db = await database;
    final rows = await db.query(
      'user_settings',
      columns: ['latitude', 'longitude', 'accuracy', 'location_timestamp'],
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LocationData.fromSqlite(rows.first);
  }

  /// Lưu cài đặt chia sẻ vị trí (bật/tắt)
  Future<void> saveLocationSharingEnabled(String uid, bool enabled) async {
    if (uid.isEmpty) return;

    final db = await database;
    await _ensureUserSettingsRow(db, uid);
    await db.update(
      'user_settings',
      {'is_location_sharing_enabled': enabled ? 1 : 0},
      where: 'uid = ?',
      whereArgs: [uid],
    );
  }

  /// Đọc trạng thái chia sẻ vị trí
  Future<bool> isLocationSharingEnabled(String uid) async {
    if (uid.isEmpty) return false;

    final db = await database;
    final rows = await db.query(
      'user_settings',
      columns: ['is_location_sharing_enabled'],
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );

    if (rows.isEmpty) return false;
    return (rows.first['is_location_sharing_enabled'] as int? ?? 0) == 1;
  }

  Future<void> _ensureUserSettingsRow(Database db, String uid) async {
    final rows = await db.query(
      'user_settings',
      columns: ['uid'],
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('user_settings', {
        'uid': uid,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // ─── LEGACY COMPATIBILITY ──────────────────────────────────────────────

  Future<int> addCheckIn(DateTime checkedAt) async {
    final record = CheckIn.create(uid: '', checkedInAt: checkedAt);
    return insertCheckIn(record);
  }

  Future<List<DateTime>> getCheckInsDates() async {
    final db = await database;
    final rows = await db.query('check_ins', orderBy: 'checked_at DESC');

    return rows
        .map(
          (row) =>
              DateTime.tryParse(row['checked_at'] as String? ?? '') ??
              DateTime.now(),
        )
        .toList();
  }
}
