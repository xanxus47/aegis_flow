import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import 'offline_queue_action.dart';
import 'offline_store.dart';
import 'sync_state.dart';

class SyncManager {
  SyncManager._internal();

  static final SyncManager instance = SyncManager._internal();

  final OfflineStore _store = OfflineStore.instance;
  final ProfileService _profileService = ProfileService();
  final SupabaseService _supabaseService = SupabaseService();
  final Connectivity _connectivity = Connectivity();

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  StreamSubscription? _connectivitySub;

  SyncState _state = SyncState.initial();
  bool _started = false;
  bool _isProcessing = false;

  Stream<SyncState> get stateStream => _stateController.stream;
  SyncState get state => _state;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _state = _state.copyWith(pendingActions: _store.pendingActionCount.value);
    _store.pendingActionCount.addListener(_handlePendingChange);

    // ✅ FIX 1: results is List<ConnectivityResult> in connectivity_plus v6+
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final bool online = results.any((r) => r != ConnectivityResult.none);
      _emit(_state.copyWith(isOnline: online));
      if (online) {
        processQueue();
      }
    });

    await processQueue();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _store.pendingActionCount.removeListener(_handlePendingChange);
  }

  void _handlePendingChange() {
    _emit(_state.copyWith(pendingActions: _store.pendingActionCount.value));
  }

  void _emit(SyncState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  Future<void> triggerManualSync() async {
    await processQueue(force: true);
  }

  Future<void> processQueue({bool force = false}) async {
    if (_isProcessing && !force) return;

    final online = await _hasInternet();
    _emit(_state.copyWith(isOnline: online));
    if (!online) return;

    _isProcessing = true;
    _emit(_state.copyWith(isSyncing: true));

    final actions = _store.getQueuedActions();

    // Group actions by profileId to preserve per-person order (check-in before check-out)
    final Map<String, List<OfflineQueueAction>> byProfile = {};
    for (final action in actions) {
      final key = (action.payload['profileId'] as String?) ?? action.id;
      byProfile.putIfAbsent(key, () => []).add(action);
    }

    // Process all profiles in parallel; each profile's actions run sequentially
    await Future.wait(byProfile.values.map((profileActions) async {
      for (final action in profileActions) {
        await _store.markActionStatus(action.id, QueueActionStatus.syncing);
        try {
          switch (action.type) {
            case QueueActionType.checkIn:
              await _processCheckIn(action);
              break;
            case QueueActionType.checkOut:
              await _processCheckOut(action);
              break;
          }
          await _store.markActionStatus(action.id, QueueActionStatus.synced);
          await _store.deleteAction(action.id);
          _emit(_state.copyWith(
            lastMessage: 'Last sync succeeded',
            lastSuccess: DateTime.now(),
          ));
        } catch (e) {
          await _store.markActionStatus(action.id, QueueActionStatus.failed,
              error: e.toString());
          _emit(_state.copyWith(
            lastMessage: 'Sync error: $e',
          ));
        }
      }
    }));

    _isProcessing = false;
    _emit(_state.copyWith(isSyncing: false));
  }

  Future<void> _processCheckIn(OfflineQueueAction action) async {
    final payload = Map<String, dynamic>.from(action.payload);
    final profileId = payload['profileId']?.toString();
    final centerId = payload['centerId']?.toString();
    if (profileId == null || centerId == null) {
      throw Exception('Missing profile/center information for check-in');
    }

    String? proofUrl = payload['proofUrl']?.toString();
    final String? proofPath = payload['proofPath']?.toString();

    if ((proofUrl == null || proofUrl.isEmpty) && proofPath != null) {
      final file = File(proofPath);
      if (await file.exists()) {
        final String uploadedName =
            payload['proofFileName']?.toString() ??
                'proof_${profileId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final storage = Supabase.instance.client.storage.from('checkin-proofs');
        await storage.upload(uploadedName, file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true));
        proofUrl = storage.getPublicUrl(uploadedName);
        payload['proofUrl'] = proofUrl;
        await _store.persistActionPayload(action.id, payload);
      }
    }

    final apiRes = await _profileService.checkInEvacuee(profileId, centerId);
    if (apiRes['success'] != true && apiRes['message'] != 'Already checked in!') {
      throw Exception(apiRes['message'] ?? 'Check-in API failed');
    }

    await _supabaseService.trackEvacueeCheckIn(
      profileId: profileId,
      fullName: payload['fullName']?.toString() ?? 'Unknown',
      evacuationCenterId: centerId,
      evacuationCenterName: payload['centerName']?.toString() ?? '',
      centerBarangay: payload['centerBarangay']?.toString() ?? '',
      age: payload['age']?.toString(),
      sex: payload['sex']?.toString(),
      barangay: payload['barangay']?.toString(),
      household: payload['household']?.toString(),
      headOfFamily: payload['headOfFamily']?.toString(),
      birthDate: payload['birthDate']?.toString(),
      sitio: payload['sitio']?.toString(),
      proofImage: proofUrl,
      isPregnant: payload['isPregnant'] == true,
      isLactating: payload['isLactating'] == true,
      isChildHeaded: payload['isChildHeaded'] == true,
      isSingleHeaded: payload['isSingleHeaded'] == true,
      isSoloParent: payload['isSoloParent'] == true,
      isPwd: payload['isPwd'] == true,
      isIp: payload['isIp'] == true,
      is4Ps: payload['is4Ps'] == true,
      isLgbt: payload['isLgbt'] == true,
      isOutsideEc: payload['isOutsideEc'] == true,
      latitude: payload['latitude'] as double?,
      longitude: payload['longitude'] as double?,
      checkInTimestamp: payload['checkInTimestamp'] is String
          ? DateTime.tryParse(payload['checkInTimestamp'] as String)
          : null,
      hostAddress: payload['hostAddress']?.toString(),
    );

    await _store.upsertActiveCheckIn({
      'profileId': profileId,
      'fullName': payload['fullName'],
      'centerId': centerId,
      'centerName': payload['centerName'],
      'centerBarangay': payload['centerBarangay'],
      'timestamp': payload['checkInTimestamp'],
      'synced': true,
    });
  }

  Future<void> _processCheckOut(OfflineQueueAction action) async {
    final payload = Map<String, dynamic>.from(action.payload);
    final profileId = payload['profileId']?.toString();
    final centerId = payload['centerId']?.toString();
    if (profileId == null || centerId == null) {
      throw Exception('Missing profile/center for check-out');
    }

    final apiRes = await _profileService.checkOutEvacuee(profileId, centerId);
    if (apiRes['success'] != true && !apiRes['message'].toString().contains('Already checked out')) {
      throw Exception(apiRes['message'] ?? 'Check-out API failed');
    }

    await _supabaseService.trackEvacueeCheckOut(profileId: profileId);
    await _store.removeActiveCheckIn(profileId);
  }

  // ✅ FIX 2: checkConnectivity() also returns List in v6+, ping Supabase not Google
  Future<bool> _hasInternet() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.every((r) => r == ConnectivityResult.none)) return false;

    try {
      final resp = await http
          .get(Uri.parse('https://fmcakdpeociqovseukic.supabase.co')) // 👈 replace with your actual Supabase URL
          .timeout(const Duration(seconds: 5));
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}