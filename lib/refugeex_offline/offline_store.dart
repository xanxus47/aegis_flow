import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/evacuation_center_model.dart';
import '../models/profile_model.dart';
import 'offline_queue_action.dart';

/// Central cache + queue store for offline operations.
class OfflineStore {
  OfflineStore._internal();

  static final OfflineStore instance = OfflineStore._internal();

  late Box _profilesBox;
  late Box _centersBox;
  late Box _queueBox;
  late Box _activeCheckinsBox;
  late Box _metaBox;

  bool _initialized = false;
  final ValueNotifier<int> _pendingActionCount = ValueNotifier<int>(0);

  final StreamController<void> _queueChanged = StreamController.broadcast();

  ValueListenable<int> get pendingActionCount => _pendingActionCount;
  Stream<void> get queueChanged => _queueChanged.stream;

  Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter('refugeex_offline');
    _profilesBox = await Hive.openBox('offline_profiles');
    _centersBox = await Hive.openBox('offline_centers');
    _queueBox = await Hive.openBox('offline_queue');
    _activeCheckinsBox = await Hive.openBox('offline_active_checkins');
    _metaBox = await Hive.openBox('offline_meta');

    _initialized = true;
    _refreshPendingCount();
  }

  void _refreshPendingCount() {
    final pending = _queueBox.values
        .whereType<Map>()
        .map((value) => OfflineQueueAction.fromJson(
            Map<String, dynamic>.from(value)))
        .where((action) => action.status == QueueActionStatus.pending || action.status == QueueActionStatus.failed)
        .length;
    _pendingActionCount.value = pending;
    _queueChanged.add(null);
  }

  Future<void> cacheProfile(Profile profile) async {
    await _profilesBox.put(profile.id, profile.toJson());
  }

  Profile? getCachedProfile(String profileId) {
    final data = _profilesBox.get(profileId);
    if (data is Map) {
      return Profile.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<void> cacheEvacuationCenters(List<EvacuationCenter> centers) async {
    final serialized = centers.map(_centerToMap).toList();
    await _centersBox.put('all', serialized);
    await _metaBox.put('centers_cached_at', DateTime.now().toIso8601String());
  }

  List<EvacuationCenter> getCachedCenters() {
    final dynamic stored = _centersBox.get('all');
    if (stored is! List) return const [];
    return stored
        .whereType<Map>()
        .map((entry) => EvacuationCenter.fromJson(
            Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<OfflineQueueAction> enqueueCheckIn(Map<String, dynamic> payload) async {
    final action = OfflineQueueAction(
      id: const Uuid().v4(),
      type: QueueActionType.checkIn,
      status: QueueActionStatus.pending,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _queueBox.put(action.id, action.toJson());
    _refreshPendingCount();
    return action;
  }

  Future<OfflineQueueAction> enqueueCheckOut(Map<String, dynamic> payload) async {
    final action = OfflineQueueAction(
      id: const Uuid().v4(),
      type: QueueActionType.checkOut,
      status: QueueActionStatus.pending,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _queueBox.put(action.id, action.toJson());
    _refreshPendingCount();
    return action;
  }

  List<OfflineQueueAction> getQueuedActions({List<QueueActionStatus>? statuses}) {
    final allowed = statuses ??
        const [QueueActionStatus.pending, QueueActionStatus.failed];
    return _queueBox.values
        .map((value) => OfflineQueueAction.fromJson(
            Map<String, dynamic>.from(value as Map)))
        .where((action) => allowed.contains(action.status))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> updateAction(OfflineQueueAction action) async {
    await _queueBox.put(action.id, action.toJson());
    _refreshPendingCount();
  }

  Future<void> deleteAction(String actionId) async {
    await _queueBox.delete(actionId);
    _refreshPendingCount();
  }

  Future<void> markActionStatus(
    String actionId,
    QueueActionStatus status, {
    String? error,
  }) async {
    final data = _queueBox.get(actionId);
    if (data is! Map) return;
    final action = OfflineQueueAction.fromJson(Map<String, dynamic>.from(data));
    final updated = action.copyWith(
      status: status,
      attempts: action.attempts + (status == QueueActionStatus.syncing ? 0 : 1),
      lastError: error,
      syncedAt: status == QueueActionStatus.synced ? DateTime.now() : action.syncedAt,
    );
    await updateAction(updated);
  }

  Future<void> persistActionPayload(String id, Map<String, dynamic> payload) async {
    final data = _queueBox.get(id);
    if (data is! Map) return;
    final action = OfflineQueueAction.fromJson(Map<String, dynamic>.from(data));
    await updateAction(action.copyWith(payload: payload));
  }

  Future<void> upsertActiveCheckIn(Map<String, dynamic> record) async {
    final profileId = record['profileId']?.toString();
    if (profileId == null) return;
    await _activeCheckinsBox.put(profileId, {
      ...record,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Map<String, dynamic>? getActiveCheckIn(String profileId) {
    final data = _activeCheckinsBox.get(profileId);
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  Future<void> removeActiveCheckIn(String profileId) async {
    await _activeCheckinsBox.delete(profileId);
  }

  Map<String, dynamic> _centerToMap(EvacuationCenter center) {
    return {
      'id': center.id,
      'name': center.name,
      'barangay': center.barangay,
      'sitio': center.sitio,
      'purok': center.purok,
      'evacuationStatus': center.evacuationStatus,
      'evacuationType': center.evacuationType,
      'accomodationArea': center.accomodationArea,
      'isActivated': center.isActivated,
      'isOperational': center.isOperational,
      'hasElectricity': center.hasElectricity,
      'hasWaterSupply': center.hasWaterSupply,
      'totalMembersCheckedIn': center.totalMembersCheckedIn,
      'totalFamilyCheckedIn': center.totalFamilyCheckedIn,
    };
  }
}
