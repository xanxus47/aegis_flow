import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ----------------------------------------------------------------
  // 1. FETCH HISTORY
  // ----------------------------------------------------------------
  Future<List<Map<String, dynamic>>> fetchEvacuees({bool? isCheckedIn}) async {
    try {
      var query = _supabase.from('evacuee_details').select('*, proof_image');

      if (isCheckedIn != null) {
        query = query.eq('is_checked_in', isCheckedIn);
      }
      final response =
          await query.order('check_in_time', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Error fetching history: $e');
      return [];
    }
  }

  // ----------------------------------------------------------------
  // 2. DELETE RECORD
  // ----------------------------------------------------------------
  Future<void> deleteEvacuee(int id) async {
    try {
      final record = await _supabase
          .from('evacuee_details')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (record == null) return;

      await _supabase.from('evacuee_details').delete().eq('id', id);

      await _updateStats(
        centerId: record['evacuation_center_id'],
        activeEvacueesDelta: record['is_checked_in'] == true ? -1 : 0,
        totalCheckinsDelta: -1,
      );
    } catch (e) {
      print("⚠️ Error deleting record: $e");
      rethrow;
    }
  }

  // ----------------------------------------------------------------
  // 3. TRACK CHECK-IN
  // ----------------------------------------------------------------
  Future<void> trackEvacueeCheckIn({
    required String profileId,
    required String fullName,
    required String evacuationCenterId,
    required String evacuationCenterName,
    required String centerBarangay,   // ← barangay of the evacuation center
    String? age,
    String? sex,
    String? barangay,
    String? proofImage,
    String? household,

    // Vulnerabilities
    required bool isPregnant,
    required bool isLactating,
    required bool isChildHeaded,
    required bool isSingleHeaded,
    required bool isSoloParent,
    required bool isPwd,
    required bool isIp,
    required bool is4Ps,
    required bool isLgbt,

    // Location flag
    required bool isOutsideEc,

    // ── NEW: GPS coordinates + explicit timestamp ──
    double? latitude,
    double? longitude,
    DateTime? checkInTimestamp,

    // ── NEW: host address for outside-EC evacuees ──
    String? hostAddress,
  }) async {
    try {
      if (household != null && household.isNotEmpty) {
        await _ensureFamilyExists(household, barangay);
      }

      final String resolvedCheckInTime =
          (checkInTimestamp ?? DateTime.now()).toUtc().toIso8601String();

      await _supabase.from('evacuee_details').insert({
        'profile_id': profileId,
        'full_name': fullName,
        'evacuation_center_id': evacuationCenterId,
        'evacuation_center_name': evacuationCenterName,
        'center_barangay': centerBarangay,   // ← center's barangay for dashboard grouping
        'age': int.tryParse(age ?? '0'),
        'sex': sex,
        'barangay': barangay,               // ← evacuee's home barangay (kept for reference)
        'household': household,
        'proof_image': proofImage,

        // Vulnerabilities
        'is_pregnant': isPregnant,
        'is_lactating': isLactating,
        'is_child_headed': isChildHeaded,
        'is_single_headed': isSingleHeaded,
        'is_solo_parent': isSoloParent,
        'is_pwd': isPwd,
        'is_ip': isIp,
        'is_4ps': is4Ps,
        'is_lgbt': isLgbt,

        // Location
        'is_outside_ec': isOutsideEc,
        'host_address': hostAddress,   // null when inside EC

        // GPS + timestamp
        'latitude': latitude,
        'longitude': longitude,
        'check_in_time': resolvedCheckInTime,

        'is_checked_in': true,
      });

      await _updateStats(
        centerId: evacuationCenterId,
        centerName: evacuationCenterName,
        barangay: barangay,
        activeEvacueesDelta: 1,
        totalCheckinsDelta: 1,
      );

      print('✅ Check-in tracked: $fullName'
          '${latitude != null ? " | 📍 $latitude, $longitude" : " | 📍 No location"}');
    } catch (e) {
      print("⚠️ Supabase Check-In Error: $e");
      rethrow;
    }
  }

  // ----------------------------------------------------------------
  // 4. TRACK CHECK-OUT
  // ----------------------------------------------------------------
  Future<void> trackEvacueeCheckOut({required String profileId}) async {
    try {
      final record = await _supabase
          .from('evacuee_details')
          .select()
          .eq('profile_id', profileId)
          .eq('is_checked_in', true)
          .maybeSingle();

      if (record == null) {
        print('⚠️ No active check-in record found for $profileId');
        return;
      }

      await _supabase
          .from('evacuee_details')
          .update({
            'is_checked_in': false,
            'check_out_time': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('profile_id', profileId)
          .eq('is_checked_in', true);

      await _updateStats(
        centerId: record['evacuation_center_id'],
        activeEvacueesDelta: -1,
        totalCheckoutsDelta: 1,
      );

      print('✅ Check-out tracked: $profileId');
    } catch (e) {
      print("⚠️ Supabase Check-Out Error: $e");
      rethrow;
    }
  }

  // ----------------------------------------------------------------
  // 5. STATS HELPER
  // ----------------------------------------------------------------
  Future<void> _updateStats({
    required String centerId,
    String? centerName,
    String? barangay,
    int activeEvacueesDelta = 0,
    int totalCheckinsDelta = 0,
    int totalCheckoutsDelta = 0,
  }) async {
    try {
      final existing = await _supabase
          .from('evacuation_stats')
          .select()
          .eq('evacuation_center_id', centerId)
          .maybeSingle();

      if (existing == null) {
        await _supabase.from('evacuation_stats').insert({
          'evacuation_center_id': centerId,
          'center_name': centerName ?? '',
          'barangay': barangay ?? '',
          'active_evacuees': activeEvacueesDelta.clamp(0, 99999),
          'total_checkins': totalCheckinsDelta.clamp(0, 99999),
          'total_checkouts': totalCheckoutsDelta.clamp(0, 99999),
          'last_updated': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        final newActive =
            ((existing['active_evacuees'] ?? 0) + activeEvacueesDelta)
                .clamp(0, 99999);
        final newCheckins =
            ((existing['total_checkins'] ?? 0) + totalCheckinsDelta)
                .clamp(0, 99999);
        final newCheckouts =
            ((existing['total_checkouts'] ?? 0) + totalCheckoutsDelta)
                .clamp(0, 99999);

        await _supabase.from('evacuation_stats').update({
          'active_evacuees': newActive,
          'total_checkins': newCheckins,
          'total_checkouts': newCheckouts,
          'last_updated': DateTime.now().toUtc().toIso8601String(),
        }).eq('evacuation_center_id', centerId);
      }
    } catch (e) {
      print('⚠️ Stats update error (non-critical): $e');
    }
  }

  // ----------------------------------------------------------------
  // 6. FAMILY HELPER
  // ----------------------------------------------------------------
  Future<void> _ensureFamilyExists(
      String householdId, String? barangay) async {
    try {
      final existingFamily = await _supabase
          .from('family')
          .select()
          .eq('household', householdId)
          .maybeSingle();

      if (existingFamily == null) {
        await _supabase.from('family').insert({
          'household': householdId,
          'barangay': barangay,
          'isActive': true,
          'memberCount': 0,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await _supabase
            .from('family')
            .update(
                {'updated_at': DateTime.now().toUtc().toIso8601String()})
            .eq('household', householdId);
      }
    } catch (e) {
      print('⚠️ Family record error (non-critical): $e');
    }
  }
}