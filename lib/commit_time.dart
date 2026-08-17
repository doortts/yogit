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

/// 밖에서 벌어진 변화를 알아챈 뒤 얼마나 지났는지. 읽는 사람이 알고 싶은 것은
/// 시계가 아니라 지난 시간이라 초는 세지 않는다: `방금`, `3분 전`, `9시간 전`.
///
/// 하루가 지나면 `27시간 전`처럼 머리로 한 번 더 셈해야 하는 숫자가 되므로 그
/// 뒤로는 시각 자체를 적는다 — `08-15(토) 09:12`. 요일까지 적는 것은 밖에서
/// 벌어진 일이 대개 어느 요일이었나로 기억되기 때문이고, 해는 그것이 올해가
/// 아닐 때만 값한다. 경계는 날짜가 아니라 지난 시간이다: 밤 11시에 알아챈 것은
/// 새벽 1시에도 `2시간 전`이다.
/// docs/local-change-notice-stack-mockup.html이 계약이다.
String noticedAgo(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final gone = current.difference(at);
  if (gone.inMinutes < 1) return '방금';
  if (gone.inMinutes < 60) return '${gone.inMinutes}분 전';
  if (gone.inHours < 24) return '${gone.inHours}시간 전';
  String pad(int value) => value.toString().padLeft(2, '0');
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final year = at.year == current.year ? '' : '${at.year}-';
  return '$year${pad(at.month)}-${pad(at.day)}'
      '(${weekdays[at.weekday - 1]}) ${pad(at.hour)}:${pad(at.minute)}';
}
