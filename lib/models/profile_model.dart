// lib/models/profile_model.dart

class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? suffix;
  final int? age;
  final String? sex;
  final String? gender;
  final String? civilStatus;
  final String? barangay;
  final String? sitio;
  final String? purok;
  final String? household;
  final String? family;
  final bool? isHouseholdHead;
  final bool? isFamilyHead;
  final bool? hasFamily;
  final bool? hasHousehold;
  final String? vulSector;
  final String? disability;
  final String? religion;
  final String? ethnicity;
  final String? education;
  final bool? isStudent;
  final bool? isOutofSchoolYouth;
  final String? natCert;
  final bool? hasMobileNumber;
  final bool? hasEmail;
  final String? employment;
  final String? classOfWorker;
  final String? occupation;
  final String? income;
  final bool? is4P;
  final bool? hasSocPen;
  final bool? isActive;
  final bool? isValid;
  final bool? isVerified;
  final String? addedBy;
  final String? modifiedBy;
  final DateTime? dateAdded;
  final DateTime? dateModified;

  Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.suffix,
    this.age,
    this.sex,
    this.gender,
    this.civilStatus,
    this.barangay,
    this.sitio,
    this.purok,
    this.household,
    this.family,
    this.isHouseholdHead,
    this.isFamilyHead,
    this.hasFamily,
    this.hasHousehold,
    this.vulSector,
    this.disability,
    this.religion,
    this.ethnicity,
    this.education,
    this.isStudent,
    this.isOutofSchoolYouth,
    this.natCert,
    this.hasMobileNumber,
    this.hasEmail,
    this.employment,
    this.classOfWorker,
    this.occupation,
    this.income,
    this.is4P,
    this.hasSocPen,
    this.isActive,
    this.isValid,
    this.isVerified,
    this.addedBy,
    this.modifiedBy,
    this.dateAdded,
    this.dateModified,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    // ----------------------------------------------------------------
    // HELPERS
    // ----------------------------------------------------------------
    dynamic _getValue(String key) {
      if (json.containsKey(key)) return json[key];
      final pascalKey = key[0].toUpperCase() + key.substring(1);
      if (json.containsKey(pascalKey)) return json[pascalKey];
      final snakeKey = _camelToSnake(key);
      if (json.containsKey(snakeKey)) return json[snakeKey];
      final lowerKey = key.toLowerCase();
      if (json.containsKey(lowerKey)) return json[lowerKey];
      return null;
    }

    // 🔧 FIX: Better nested object extraction for IDs
    String? _getString(String key) {
      final value = _getValue(key);
      if (value == null) return null;
      if (value is Map) {
        // Look for 'name' first, but if it's an ID object, look for 'id'
        return (value['name'] ?? value['id'] ?? value['description'])?.toString();
      }
      return value.toString();
    }

    bool? _getBool(String key) {
      final value = _getValue(key);
      if (value == null) return null;
      if (value is bool) return value;
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'true' || lower == '1' || lower == 'yes') return true;
        if (lower == 'false' || lower == '0' || lower == 'no') return false;
      }
      if (value is int) return value == 1;
      return null;
    }

    int? _getInt(String key) {
      final value = _getValue(key);
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      if (value is num) return value.toInt();
      return null;
    }

    DateTime? _getDateTime(String key) {
      final value = _getValue(key);
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) {
        try { return DateTime.parse(value); } catch (_) { return null; }
      }
      return null;
    }

    return Profile(
      id: _getString('id') ?? '',
      firstName: _getString('firstName') ?? _getString('first_name') ?? 'Unknown',
      lastName: _getString('lastName') ?? _getString('last_name') ?? 'Unknown',
      middleName: _getString('middleName') ?? _getString('middle_name'),
      suffix: _getString('suffix'),
      age: _getInt('age'),
      sex: _getString('sex'),
      gender: _getString('gender'),
      civilStatus: _getString('civilStatus') ?? _getString('civil_status'),
      barangay: _getString('barangay'),
      sitio: _getString('sitio'),
      purok: _getString('purok'),
      
      // 🔧 FIX: Check multiple common variations of household and family keys
      household: _getString('household') ?? _getString('householdId') ?? _getString('household_id'),
      family: _getString('family') ?? _getString('familyId') ?? _getString('family_id'),
      
      isHouseholdHead: _getBool('isHouseholdHead') ?? _getBool('is_household_head'),
      isFamilyHead: _getBool('isFamilyHead') ?? _getBool('is_family_head'),
      hasFamily: _getBool('hasFamily') ?? _getBool('has_family'),
      hasHousehold: _getBool('hasHousehold') ?? _getBool('has_household'),
      vulSector: _getString('vulSector') ?? _getString('vul_sector'),
      disability: _getString('disability'),
      religion: _getString('religion'),
      ethnicity: _getString('ethnicity'),
      education: _getString('education'),
      isStudent: _getBool('isStudent') ?? _getBool('is_student'),
      isOutofSchoolYouth: _getBool('isOutofSchoolYouth') ?? _getBool('is_out_of_school_youth'),
      natCert: _getString('natCert') ?? _getString('nat_cert'),
      hasMobileNumber: _getBool('hasMobileNumber') ?? _getBool('has_mobile_number'),
      hasEmail: _getBool('hasEmail') ?? _getBool('has_email'),
      employment: _getString('employment'),
      classOfWorker: _getString('classOfWorker') ?? _getString('class_of_worker'),
      occupation: _getString('occupation'),
      income: _getString('income'),
      is4P: _getBool('is4P') ?? _getBool('is_4p'),
      hasSocPen: _getBool('hasSocPen') ?? _getBool('has_soc_pen'),
      isActive: _getBool('isActive') ?? _getBool('is_active'),
      isValid: _getBool('isValid') ?? _getBool('is_valid'),
      isVerified: _getBool('isVerified') ?? _getBool('is_verified'),
      addedBy: _getString('addedBy') ?? _getString('added_by'),
      modifiedBy: _getString('modifiedBy') ?? _getString('modified_by'),
      dateAdded: _getDateTime('dateAdded') ?? _getDateTime('date_added'),
      dateModified: _getDateTime('dateModified') ?? _getDateTime('date_modified'),
    );
  }

  static String _camelToSnake(String input) {
    return input.replaceAllMapped(
      RegExp('([a-z])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)!.toLowerCase()}',
    );
  }

  String get fullName {
    final parts = [firstName];
    if (middleName != null && middleName!.isNotEmpty) parts.add(middleName!);
    parts.add(lastName);
    if (suffix != null && suffix!.isNotEmpty) parts.add(suffix!);
    return parts.join(' ');
  }

  String get shortName => '$firstName $lastName';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'suffix': suffix,
      'age': age,
      'sex': sex,
      'gender': gender,
      'civilStatus': civilStatus,
      'barangay': barangay,
      'sitio': sitio,
      'purok': purok,
      'household': household,
      'family': family,
      'isHouseholdHead': isHouseholdHead,
      'isFamilyHead': isFamilyHead,
      'hasFamily': hasFamily,
      'hasHousehold': hasHousehold,
      'vulSector': vulSector,
      'disability': disability,
      'religion': religion,
      'ethnicity': ethnicity,
      'education': education,
      'isStudent': isStudent,
      'isOutofSchoolYouth': isOutofSchoolYouth,
      'natCert': natCert,
      'hasMobileNumber': hasMobileNumber,
      'hasEmail': hasEmail,
      'employment': employment,
      'classOfWorker': classOfWorker,
      'occupation': occupation,
      'income': income,
      'is4P': is4P,
      'hasSocPen': hasSocPen,
      'isActive': isActive,
      'isValid': isValid,
      'isVerified': isVerified,
      'addedBy': addedBy,
      'modifiedBy': modifiedBy,
      'dateAdded': dateAdded?.toIso8601String(),
      'dateModified': dateModified?.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'Profile(id: $id, name: $fullName, barangay: $barangay, age: $age, household: $household)';
}