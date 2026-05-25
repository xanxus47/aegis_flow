class SyncState {
  const SyncState({
    required this.pendingActions,
    required this.isSyncing,
    required this.isOnline,
    this.lastMessage,
    this.lastSuccess,
  });

  final int pendingActions;
  final bool isSyncing;
  final bool isOnline;
  final String? lastMessage;
  final DateTime? lastSuccess;

  SyncState copyWith({
    int? pendingActions,
    bool? isSyncing,
    bool? isOnline,
    String? lastMessage,
    DateTime? lastSuccess,
  }) {
    return SyncState(
      pendingActions: pendingActions ?? this.pendingActions,
      isSyncing: isSyncing ?? this.isSyncing,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSuccess: lastSuccess ?? this.lastSuccess,
    );
  }

  static SyncState initial() => const SyncState(
        pendingActions: 0,
        isSyncing: false,
        isOnline: true,
      );
}
