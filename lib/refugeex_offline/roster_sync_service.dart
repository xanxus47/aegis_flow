import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:postgres/postgres.dart';

class RosterSyncService {
  static final RosterSyncService instance = RosterSyncService._internal();
  RosterSyncService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offline_roster.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE profiles (
            id TEXT PRIMARY KEY,
            full_name TEXT,
            sex TEXT,
            gender TEXT,
            barangay TEXT,
            sitio TEXT,
            purok TEXT,
            birthdate TEXT,
            civil_status TEXT,
            household_id TEXT,
            family_id TEXT,
            head_of_family TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE profiles ADD COLUMN head_of_family TEXT',
          );
        }
      },
    );
  }

  Future<int> getRosterCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM profiles'));
    return count ?? 0;
  }

  Future<Map<String, dynamic>?> getProfileLocally(String profileId) async {
    final db = await database;
    final res = await db.query('profiles',
        where: 'id = ?', whereArgs: [profileId]);
    if (res.isNotEmpty) {
      final row = res.first;

      int? age;
      if (row['birthdate'] != null &&
          row['birthdate'].toString().isNotEmpty) {
        try {
          final bdate = DateTime.parse(row['birthdate'].toString());
          final now = DateTime.now();
          age = now.year - bdate.year;
          if (now.month < bdate.month ||
              (now.month == bdate.month && now.day < bdate.day)) {
            age--;
          }
        } catch (_) {}
      }

      return {
        'id':          row['id'],
        'firstName':   row['full_name'],
        'lastName':    '',
        'sex':         row['sex'],
        'gender':      row['gender'],
        'barangay':    row['barangay'],
        'sitio':       row['sitio'],
        'purok':       row['purok'],
        'birthDate':   row['birthdate'],
        'age':         age,
        'civilStatus': row['civil_status'],
        'householdId': row['household_id'],
        'familyId':    row['family_id'],
        'headOfFamily': row['head_of_family'], // ← populated after first online scan
      };
    }
    return null;
  }

  /// Fast sync — uses PostgreSQL (NeonDB). head_of_family populated on first online scan.
  Future<void> downloadAndSyncRoster() async {
    print('📥 Fetching roster from PostgreSQL (NeonDB)...');

    // Connection configuration for NeonDB
    final endpoint = Endpoint(
      host: 'ep-withered-tooth-aolkq3ma-pooler.c-2.ap-southeast-1.aws.neon.tech',
      database: 'neondb',
      username: 'neondb_owner',
      password: 'npg_N7cTtaiUDW6O',
      port: 5432,
    );

    Connection? conn;
    try {
      conn = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.require),
      );

      final result = await conn.execute(
        'SELECT id, name, sex, gender, barangay, "sitio/proper", "purok/street", birthdate, civilstatus, householdid, familyid, relationshiptofamilyhead FROM population'
      );

      print('✅ PostgreSQL returned \${result.length} profiles, writing to SQLite...');

      // 1. Build a map of familyId -> Family Head Name
      final Map<String, String> familyHeads = {};
      for (final row in result) {
        final familyId = row[10]?.toString();
        final relation = row[11]?.toString();
        
        if (familyId != null && relation?.toLowerCase() == 'family head') {
          final name = row[1]?.toString();
          if (name != null) {
            familyHeads[familyId] = name;
          }
        }
      }

      final db = await database;
      final batch = db.batch();
      batch.delete('profiles');

      for (final row in result) {
        String? val(int index) {
          return row[index]?.toString();
        }

        final fId = val(10);
        final headName = fId != null ? familyHeads[fId] : null;

        batch.insert(
          'profiles',
          {
            'id':             val(0),
            'full_name':      val(1),
            'sex':            val(2),
            'gender':         val(3),
            'barangay':       val(4),
            'sitio':          val(5),
            'purok':          val(6),
            'birthdate':      val(7),
            'civil_status':   val(8),
            'household_id':   val(9),
            'family_id':      fId,
            'head_of_family': headName,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ Roster sync complete: ${result.length} profiles saved offline');
    } catch (e) {
      throw Exception('Failed to download roster from PostgreSQL: $e');
    } finally {
      await conn?.close();
    }
  }

  /// Called after a successful online scan to cache head_of_family into SQLite.
  /// So next offline scan of same person will have it.
  Future<void> updateProfileHeadOfFamily(
      String profileId, String? headOfFamily) async {
    if (headOfFamily == null || headOfFamily.isEmpty) return;
    final db = await database;
    await db.update(
      'profiles',
      {'head_of_family': headOfFamily},
      where: 'id = ?',
      whereArgs: [profileId],
    );
    print('✅ Cached head_of_family for $profileId: $headOfFamily');
  }
}