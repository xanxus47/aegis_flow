// lib/models/evacuation_center_model.dart
class EvacuationCenter {
  final String id;
  final String name;
  final String barangay;
  final String? sitio;
  final String? purok;
  final String evacuationStatus;
  final String evacuationType;
  final String? accomodationArea;
  final bool isActivated;
  final bool? isOperational;
  final bool? hasElectricity;
  final bool? hasWaterSupply;
  final Map<String, dynamic>? totalMembersCheckedIn;
  final int? totalFamilyCheckedIn;

  EvacuationCenter({
    required this.id,
    required this.name,
    required this.barangay,
    this.sitio,
    this.purok,
    required this.evacuationStatus,
    required this.evacuationType,
    this.accomodationArea,
    required this.isActivated,
    this.isOperational,
    this.hasElectricity,
    this.hasWaterSupply,
    this.totalMembersCheckedIn,
    this.totalFamilyCheckedIn,
  });

  factory EvacuationCenter.fromJson(Map<String, dynamic> json) {
    return EvacuationCenter(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Center',

      // 🔧 FIX: barangay is nested inside 'address' object
      barangay: json['address'] is Map && json['address']['barangay'] is Map
          ? json['address']['barangay']['name']?.toString() ?? 'Unknown'
          : json['barangay'] is Map
              ? json['barangay']['name']?.toString() ?? 'Unknown'
              : json['barangay']?.toString() ?? 'Unknown',

      sitio: json['address'] is Map ? json['address']['sitio']?.toString() : json['sitio']?.toString(),
      purok: json['address'] is Map ? json['address']['purok']?.toString() : json['purok']?.toString(),

      // 🔧 FIX: evacuationStatus is a nested object, extract the id
      evacuationStatus: json['evacuationStatus'] is Map
          ? json['evacuationStatus']['id']?.toString() ?? ''
          : json['evacuationStatus']?.toString() ?? '',

      // 🔧 FIX: evacuationType is a nested object, extract the id
      evacuationType: json['evacuationType'] is Map
          ? json['evacuationType']['id']?.toString() ?? ''
          : json['evacuationType']?.toString() ?? '',

      accomodationArea: json['accomodationArea']?.toString(),
      isActivated: json['isActivated'] == true,
      isOperational: json['isOperational'] == true,
      hasElectricity: json['hasElectricity'] == true,
      hasWaterSupply: json['hasWaterSupply'] == true,
      totalMembersCheckedIn: json['totalMembersCheckedIn'] is Map
          ? Map<String, dynamic>.from(json['totalMembersCheckedIn'])
          : null,
      totalFamilyCheckedIn: json['totalFamilyCheckedIn'] is int
          ? json['totalFamilyCheckedIn']
          : null,
    );
  }

  String get displayName => name;

  String get statusDescription {
    switch (evacuationStatus) {
      case '01': return 'Active';
      case '02': return 'Permanent';
      case '03': return 'Available';
      default: return 'Unknown';
    }
  }

  String get typeDescription {
    switch (evacuationType) {
      case '01': return 'Public';
      case '02': return 'School';
      case '03': return 'Church';
      case '04': return 'Private';
      default: return 'Other';
    }
  }

  bool get isAvailable => isActivated;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'barangay': barangay,
      'sitio': sitio,
      'purok': purok,
      'evacuationStatus': evacuationStatus,
      'evacuationType': evacuationType,
      'accomodationArea': accomodationArea,
      'isActivated': isActivated,
      'isOperational': isOperational,
      'hasElectricity': hasElectricity,
      'hasWaterSupply': hasWaterSupply,
      'totalMembersCheckedIn': totalMembersCheckedIn,
      'totalFamilyCheckedIn': totalFamilyCheckedIn,
    };
  }
}