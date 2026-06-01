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
            family_id TEXT,
            head_of_family TEXT
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
        'headOfFamily': row['head_of_family'],
      };
    }
    return null;
  }

  Future<void> downloadAndSyncRoster(String authToken) async {
  final db = await database;

  // ── Step 1: Download all profiles from Lester's API (paginated) ──
  final Map<String, String> familyHeadMap = {}; // familyId → head name
  final List<Map<String, dynamic>> allProfiles = [];

  int page = 1;
  const int rows = 100;
  bool hasMore = true;

  while (hasMore) {
    final response = await http.get(
      Uri.parse('https://citrusapi-dev-svex.onrender.com/api/v1/profile?page=$page&rows=$rows'),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch profiles on page $page: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final result = data['data'];
    final List profiles = result['result'] ?? [];

    for (final p in profiles) {
      allProfiles.add(p);

      // Build familyId → head name map
      final family = p['family'];
      if (family is Map) {
        final familyId = family['id']?.toString();
        final hof = family['headOfTheFamily'];
        if (familyId != null && hof is Map) {
          final last  = hof['lastName']?.toString().trim() ?? '';
          final first = hof['firstName']?.toString().trim() ?? '';
          final mid   = hof['middleName']?.toString().trim() ?? '';
          String name = last.isNotEmpty ? '$last, $first' : first;
          if (mid.isNotEmpty) name += ' $mid';
          if (name.trim().isNotEmpty) {
            familyHeadMap[familyId] = name.trim().toUpperCase();
          }
        }
      }
    }

    final int totalPage = result['totalPage'] ?? 1;
    if (page >= totalPage || profiles.isEmpty) {
      hasMore = false;
    } else {
      page++;
    }
  }

  // ── Step 2: Write to SQLite ──
  final batch = db.batch();
  batch.delete('profiles');

  for (final p in allProfiles) {
    final String? profileId = p['id']?.toString();
    if (profileId == null) continue;

    // Parse name
    final String lastName  = p['lastName']?.toString().trim() ?? '';
    final String firstName = p['firstName']?.toString().trim() ?? '';
    final String fullName  = lastName.isNotEmpty ? '$lastName, $firstName' : firstName;

    // Parse sex
    final sexObj = p['sex'];
    final String? sex = sexObj is Map ? sexObj['name']?.toString() : null;

    // Parse gender
    final genderObj = p['gender'];
    final String? gender = genderObj is Map ? genderObj['name']?.toString() : null;

    // Parse barangay
    final address = p['address'];
    String? barangay;
    String? sitio;
    String? purok;
    if (address is Map) {
      barangay = address['barangay'] is Map ? address['barangay']['name']?.toString() : null;
      sitio    = address['sitio']    is Map ? address['sitio']['name']?.toString()    : null;
      purok    = address['purok']    is Map ? address['purok']['name']?.toString()    : null;
    }

    // Parse family/household IDs
    final familyObj    = p['family'];
    final householdObj = p['household'];
    final String? familyId    = familyObj    is Map ? familyObj['id']?.toString()    : null;
    final String? householdId = householdObj is Map ? householdObj['id']?.toString() : null;

    // Look up head of family
    final String? headOfFamily = familyId != null ? familyHeadMap[familyId] : null;

    batch.insert('profiles', {
      'id':             profileId,
      'full_name':      fullName,
      'sex':            sex,
      'gender':         gender,
      'barangay':       barangay,
      'sitio':          sitio,
      'purok':          purok,
      'birthdate':      p['birthDate']?.toString(),
      'civil_status':   null, // not in this response
      'household_id':   householdId,
      'family_id':      familyId,
      'head_of_family': headOfFamily,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  await batch.commit(noResult: true);
  print('✅ Roster synced: ${allProfiles.length} profiles, ${familyHeadMap.length} family heads mapped');
}
}