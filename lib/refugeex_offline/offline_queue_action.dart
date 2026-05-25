import 'package:meta/meta.dart';

/// Types of work that can be queued while the device is offline.
enum QueueActionType { checkIn, checkOut }

/// Lifecycle state for a queued action.
enum QueueActionStatus { pending, syncing, failed, synced }

QueueActionType _typeFromString(String raw) {
  switch (raw) {
    case 'checkOut':
      return QueueActionType.checkOut;
    case 'checkIn':
    default:
      return QueueActionType.checkIn;
  }
}

QueueActionStatus _statusFromString(String raw) {
  switch (raw) {
    case 'syncing':
      return QueueActionStatus.syncing;
    case 'failed':
      return QueueActionStatus.failed;
    case 'synced':
      return QueueActionStatus.synced;
    case 'pending':
    default:
      return QueueActionStatus.pending;
  }
}

/// Serializable representation of a queued action (check-in/out).
@immutable
class OfflineQueueAction {
  const OfflineQueueAction({
    required this.id,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdAt,
    this.syncedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final QueueActionType type;
  final QueueActionStatus status;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int attempts;
  final String? lastError;

  bool get isComplete => status == QueueActionStatus.synced;
  bool get isPending =>
      status == QueueActionStatus.pending || status == QueueActionStatus.failed;

  OfflineQueueAction copyWith({
    QueueActionStatus? status,
    Map<String, dynamic>? payload,
    DateTime? syncedAt,
    int? attempts,
    String? lastError,
  }) {
    return OfflineQueueAction(
      id: id,
      type: type,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'attempts': attempts,
      'lastError': lastError,
    };
  }

  factory OfflineQueueAction.fromJson(Map<String, dynamic> json) {
    return OfflineQueueAction(
      id: json['id']?.toString() ?? '',
      type: _typeFromString(json['type']?.toString() ?? ''),
      status: _statusFromString(json['status']?.toString() ?? ''),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      syncedAt: json['syncedAt'] == null
          ? null
          : DateTime.tryParse(json['syncedAt'].toString()),
      attempts: json['attempts'] is int
          ? json['attempts'] as int
          : int.tryParse(json['attempts']?.toString() ?? '0') ?? 0,
      lastError: json['lastError']?.toString(),
    );
  }
}
