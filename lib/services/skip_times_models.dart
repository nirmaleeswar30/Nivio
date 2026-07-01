class SkipTime {
  final Duration startTime;
  final Duration endTime;
  final String type; // 'op' (intro), 'ed' (outro), 'recap', etc.

  SkipTime({
    required this.startTime,
    required this.endTime,
    required this.type,
  });

  @override
  String toString() {
    return 'SkipTime(type: $type, startTime: $startTime, endTime: $endTime)';
  }
}
