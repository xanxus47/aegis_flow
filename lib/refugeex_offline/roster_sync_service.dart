import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

  /// Fast sync — uses Turso only. head_of_family populated on first online scan.
  Future<void> downloadAndSyncRoster() async {
    const tursoUrl =
        'https://population-xanxus.aws-ap-northeast-1.turso.io/v2/pipeline';
    const tursoToken =
        'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3NzY5MTA0NTEsImlkIjoiMDE5ZGI3ZDMtNDIwMS03YWE2LWI0YzMtNDM0YjM1YzM5NTgyIiwicmlkIjoiZmJiMjM3OGMtODYzYy00NDQ0LWE1MWYtZDY2ZjNhNzcwZjVjIn0._NIcHRV5GdKayhavl-EQYCv96-nqlyxk-EmrpBYYmmA9782rSMfh--5LIAgINpUDd4FzCZBwZ93pA_n76cgOCg';

    final payload = {
      'requests': [
        {
          'type': 'execute',
          'stmt': {
            'sql':
                'SELECT id, name, sex, gender, barangay, "sitio/proper", "purok/street", birthdate, civilstatus, householdid, familyid FROM population'
          }
        },
        {'type': 'close'}
      ]
    };

    print('📥 Fetching roster from Turso...');

    final tursoResponse = await http
        .post(
          Uri.parse(tursoUrl),
          headers: {
            'Authorization': 'Bearer $tursoToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    if (tursoResponse.statusCode != 200) {
      throw Exception(
          'Failed to download roster from Turso: ${tursoResponse.body}');
    }

    final tursoData = jsonDecode(tursoResponse.body);
    final results = tursoData['results'] as List;
    final executeResult = results[0]['response']['result'];
    final tursoRows = executeResult['rows'] as List;

    print('✅ Turso returned ${tursoRows.length} profiles, writing to SQLite...');

    final db = await database;
    final batch = db.batch();
    batch.delete('profiles');

    for (var row in tursoRows) {
      String? val(int index) {
        final col = row[index];
        if (col['type'] == 'null') return null;
        return col['value']?.toString();
      }

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
          'family_id':      val(10),
          'head_of_family': null, // populated on first online scan
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    print('✅ Roster sync complete: ${tursoRows.length} profiles saved offline');
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