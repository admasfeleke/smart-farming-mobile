enum SyncState {
  synced,
  pending,
  failed,
  conflict,
}

SyncState syncStateFromString(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'pending':
      return SyncState.pending;
    case 'failed':
      return SyncState.failed;
    case 'conflict':
      return SyncState.conflict;
    case 'synced':
    default:
      return SyncState.synced;
  }
}

String syncStateToString(SyncState state) {
  switch (state) {
    case SyncState.pending:
      return 'pending';
    case SyncState.failed:
      return 'failed';
    case SyncState.conflict:
      return 'conflict';
    case SyncState.synced:
      return 'synced';
  }
}
