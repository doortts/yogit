/// The commit's own moment, local and zero-padded, for the places where "2 hours
/// ago" is not precise enough. `07-26 14:05:09` this year, and
/// `2025-12-31 23:59:59` any other — the year only earns its space when it is
/// not the obvious one.
String exactCommitTime(int timestamp, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  String pad(int value) => value.toString().padLeft(2, '0');
  final year = time.year == (now ?? DateTime.now()).year ? '' : '${time.year}-';
  return '$year${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}
