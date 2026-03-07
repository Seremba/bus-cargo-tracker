class SyncRunResult {
  final int pushed;
  final int pulled;
  final int applied;
  final int failed;

  const SyncRunResult({
    required this.pushed,
    required this.pulled,
    required this.applied,
    required this.failed,
  });

  const SyncRunResult.empty()
      : pushed = 0,
        pulled = 0,
        applied = 0,
        failed = 0;

  SyncRunResult copyWith({
    int? pushed,
    int? pulled,
    int? applied,
    int? failed,
  }) {
    return SyncRunResult(
      pushed: pushed ?? this.pushed,
      pulled: pulled ?? this.pulled,
      applied: applied ?? this.applied,
      failed: failed ?? this.failed,
    );
  }
}