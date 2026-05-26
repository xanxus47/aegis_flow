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
      version: 1,
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
            family_id TEXT
          )
        ''');
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
    final res = await db.query('profiles', where: 'id = ?', whereArgs: [profileId]);
    if (res.isNotEmpty) {
      final row = res.first;
      
      // Calculate age from birthdate
      int? age;
      if (row['birthdate'] != null && row['birthdate'].toString().isNotEmpty) {
        try {
          final bdate = DateTime.parse(row['birthdate'].toString());
          final now = DateTime.now();
          age = now.year - bdate.year;
          if (now.month < bdate.month || (now.month == bdate.month && now.day < bdate.day)) {
            age--;
          }
        } catch (_) {}
      }

      // Format as the API JSON format expects
      return {
        'id': row['id'],
        'firstName': row['full_name'], // Put full name here for display
        'lastName': '',
        'sex': row['sex'],
        'gender': row['gender'],
        'barangay': row['barangay'],
        'sitio': row['sitio'],
        'purok': row['purok'],
        'birthDate': row['birthdate'],
        'age': age,
        'civilStatus': row['civil_status'],
        'householdId': row['household_id'],
        'familyId': row['family_id'],
      };
    }
    return null;
  }

  Future<void> downloadAndSyncRoster() async {
    const url = 'https://population-xanxus.aws-ap-northeast-1.turso.io/v2/pipeline';
    const token = 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3NzY5MTA0NTEsImlkIjoiMDE5ZGI3ZDMtNDIwMS03YWE2LWI0YzMtNDM0YjM1YzM5NTgyIiwicmlkIjoiZmJiMjM3OGMtODYzYy00NDQ0LWE1MWYtZDY2ZjNhNzcwZjVjIn0._NIcHRV5GdKayhavl-EQYCv96-nqlyxk-EmrpBYYmmA9782rSMfh--5LIAgINpUDd4FzCZBwZ93pA_n76cgOCg';

    final payload = {
      'requests': [
        {
          'type': 'execute',
          'stmt': {
            'sql': 'SELECT id, name, sex, gender, barangay, "sitio/proper", "purok/street", birthdate, civilstatus, householdid, familyid FROM population'
          }
        },
        {'type': 'close'}
      ]
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download roster: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List;
    final executeResult = results[0]['response']['result'];
    
    final rows = executeResult['rows'] as List;

    final db = await database;
    final batch = db.batch();

    // Clear old data
    batch.delete('profiles');

    for (var row in rows) {
      // Turso libSQL returns values like [{"type": "text", "value": "ID123"}, ...]
      String? val(int index) {
        final col = row[index];
        if (col['type'] == 'null') return null;
        return col['value']?.toString();
      }

      batch.insert('profiles', {
        'id': val(0),
        'full_name': val(1),
        'sex': val(2),
        'gender': val(3),
        'barangay': val(4),
        'sitio': val(5),
        'purok': val(6),
        'birthdate': val(7),
        'civil_status': val(8),
        'household_id': val(9),
        'family_id': val(10),
      });
    }

    await batch.commit(noResult: true);
  }
}
