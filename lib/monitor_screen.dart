import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'avatars.dart';
import 'git.dart';
import 'pr_monitor.dart';
import 'timeline_theme.dart';
import 'window_frame.dart';

/// `open`'s argument list for launching the monitor as its own app instance.
List<String> monitorLaunchArguments({
  required String bundlePath,
  required String root,
  required String gitExecutable,
  required String? ghExecutable,
  required String branch,
}) => [
  '-n',
  bundlePath,
  '--args',
  '--repo',
  root,
  '--git',
  gitExecutable,
  if (ghExecutable != null) ...['--gh', ghExecutable],
  '--monitor',
  branch,
];

/// The monitor's window shell. macOS draws no titlebar for yogit, so every
/// state this window can reach — loading, a notice, the graph — needs its own
/// controls: traffic lights, a drag region, and esc. Wrapping the whole route
/// is what keeps a notice from becoming a window with no way out.
class MonitorWindow extends StatefulWidget {
  const MonitorWindow({
    required this.controller,
    required this.child,
    this.zoomOnEntry = true,
    super.key,
  });

  final WindowFrameController controller;
  final Widget child;

  /// The graph wants the whole screen; a short notice does not.
  final bool zoomOnEntry;

  /// The strip the traffic lights and drag region occupy. Content that would
  /// sit under them insets by this much.
  static const titleBarHeight = 44.0;
  static const controlsWidth = 66.0;

  @override
  State<MonitorWindow> createState() => _MonitorWindowState();
}

class _MonitorWindowState extends State<MonitorWindow> {
  @override
  void initState() {
    super.initState();
    if (widget.zoomOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(widget.controller.toggleZoom()),
      );
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(widget.controller.closeWindow()),
    },
    child: Focus(
      autofocus: true,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          // The drag region sits above the child but below the buttons, so a
          // drag anywhere on the empty title strip moves the window.
          Positioned(
            left: MonitorWindow.controlsWidth,
            right: 0,
            top: 0,
            height: MonitorWindow.titleBarHeight,
            child: GestureDetector(
              key: const Key('monitor-drag'),
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => unawaited(widget.controller.startDrag()),
              onDoubleTap: () => unawaited(widget.controller.toggleZoom()),
            ),
          ),
          Positioned(
            left: 14,
            top: (MonitorWindow.titleBarHeight - 12) / 2,
            child: WindowButtons(controller: widget.controller),
          ),
        ],
      ),
    ),
  );
}

const _ready = Color(0xFF34C759);
const _review = Color(0xFF64D2FF);
const _warn = Color(0xFFFFD60A);
const _conflict = Color(0xFFFF6B6B);
const _draft = Color(0xFFBF8CFF);
const _merged = Color(0xFFA371F7);

Color _stateColor(PrMonitorState state) => switch (state) {
  PrMonitorState.readyToMerge => _ready,
  PrMonitorState.readyToReview => _review,
  PrMonitorState.changesRequested => _warn,
  PrMonitorState.ciFailing => _warn,
  PrMonitorState.conflict => _conflict,
  PrMonitorState.draft => _draft,
};

String _stateLabel(PrMonitorState state) => switch (state) {
  PrMonitorState.readyToMerge => 'Ready to merge',
  PrMonitorState.readyToReview => '리뷰 중',
  PrMonitorState.changesRequested => '변경 요청',
  PrMonitorState.ciFailing => 'CI 실패',
  PrMonitorState.conflict => '충돌',
  PrMonitorState.draft => 'Draft',
};

String _ghostLabel(int index, PrMonitorState state) => index == 0
    ? '머지 예정 — 다음 차례'
    : switch (state) {
        PrMonitorState.readyToMerge => '머지 예정',
        PrMonitorState.readyToReview => '머지 예정 — 리뷰 통과 후',
        PrMonitorState.changesRequested => '머지 예정 — 변경 반영 후',
        PrMonitorState.ciFailing => '머지 예정 — CI 통과 후',
        PrMonitorState.conflict => '머지 예정 — 충돌 해소 후',
        PrMonitorState.draft => '머지 예정 — Draft 해제 후',
      };

/// Where everything sits: the single monitored lane in the center, ghost
/// commits stacked above HEAD in merge-likelihood order, and PR cards in the
/// side margins where they can never cover the lane or its commits.
class MonitorLayout {
  MonitorLayout({
    required this.size,
    required this.commitCount,
    required List<MonitoredPullRequest> pullRequests,
  }) : orderedPullRequests = [...pullRequests]
         ..sort((left, right) {
           final priority =
               ghostPriority(left.state) - ghostPriority(right.state);
           return priority != 0 ? priority : left.number - right.number;
         });

  final Size size;
  final int commitCount;

  /// Index 0 merges first and owns the ghost closest to HEAD.
  final List<MonitoredPullRequest> orderedPullRequests;

  static const cardWidth = 260.0;
  static const cardHeight = 112.0;
  static const _ghostSpacing = 58.0;
  static const _commitSpacing = 72.0;
  static const _laneClearance = 60.0;

  double get laneX => size.width / 2;

  /// The dashed line separating the future from recorded history.
  double get boundaryY =>
      math.max(120, 36 + orderedPullRequests.length * _ghostSpacing);

  double get headY => boundaryY + 52;

  /// Ghosts hang under the boundary, closest-to-HEAD last to merge first.
  Offset ghostCenter(int index) =>
      Offset(laneX, boundaryY - 20 - (index * _ghostSpacing));

  Offset commitCenter(int index) =>
      Offset(laneX, headY + index * _commitSpacing);

  /// Cards alternate sides in merge order and center on their ghost's row,
  /// clamped into the window.
  Rect cardRect(int index) {
    final ghost = ghostCenter(index);
    final left = index.isEven
        ? laneX - _laneClearance - 96 - cardWidth
        : laneX + _laneClearance + 96;
    final top = (ghost.dy - cardHeight / 2)
        .clamp(8.0, math.max(8.0, size.height - cardHeight - 8))
        .toDouble();
    return Rect.fromLTWH(
      left.clamp(8.0, math.max(8.0, size.width - cardWidth - 8)),
      top,
      cardWidth,
      cardHeight,
    );
  }

  /// The 1px arrow: out of the card's lane-facing side edge, into the ghost
  /// circle's near edge.
  ({Offset from, Offset to}) arrow(int index) {
    final ghost = ghostCenter(index);
    final card = cardRect(index);
    return index.isEven
        ? (
            from: Offset(card.right, card.center.dy),
            to: Offset(ghost.dx - 13, ghost.dy),
          )
        : (
            from: Offset(card.left, card.center.dy),
            to: Offset(ghost.dx + 13, ghost.dy),
          );
  }
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({
    required this.repository,
    required this.branch,
    required this.repositoryName,
    required this.service,
    this.refreshInterval = const Duration(minutes: 3),
    super.key,
  });

  final GitRepository repository;
  final String branch;
  final String repositoryName;
  final PrMonitorService service;
  final Duration refreshInterval;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  List<MonitoredPullRequest> _pullRequests = const [];
  List<PrHistoryEvent> _events = const [];
  List<({String sha, String subject, String author, int time})> _commits =
      const [];
  final _closeReasons = <int, String>{};
  String? _error;
  var _loaded = false;
  var _refreshing = false;
  Timer? _timer;

  TimelineThemePalette get _palette => TimelineThemePalette.of(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(widget.refreshInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final commits = widget.repository.loadRecentCommits(
        widget.branch,
        limit: 8,
      );
      final pullRequests = await widget.service.loadOpenPullRequests();
      final events = await widget.service.loadHistory();
      // Closing reasons only for the closed events on screen — a few calls.
      for (final event in events.take(6)) {
        if (event.kind == PrEventKind.closed &&
            !_closeReasons.containsKey(event.number)) {
          final reason = await widget.service.loadCloseReason(event.number);
          if (reason != null) _closeReasons[event.number] = reason;
        }
      }
      final loadedCommits = await commits;
      if (!mounted) return;
      setState(() {
        _pullRequests = pullRequests;
        _events = events;
        _commits = loadedCommits;
        _error = null;
        _loaded = true;
      });
    } on PrMonitorException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Color _loginColor(String login) {
    final palette = AvatarService.palette;
    var sum = 0;
    for (final unit in login.codeUnits) {
      sum += unit;
    }
    return palette[sum % palette.length];
  }

  Widget _avatar(String login, {double size = 20, Key? key}) => Container(
    key: key,
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _loginColor(login).withValues(alpha: 0.85),
      shape: BoxShape.circle,
      border: Border.all(color: _palette.background, width: 1.5),
    ),
    child: Text(
      login.length <= 2 ? login : login.substring(0, 2),
      style: TextStyle(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF14141A),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _palette.background,
    body: Column(
      children: [
        _topBar(),
        if (_error != null) _errorBanner(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _graph(Size(constraints.maxWidth, constraints.maxHeight)),
          ),
        ),
        _historyStrip(),
      ],
    ),
  );

  Widget _topBar() => Container(
    height: MonitorWindow.titleBarHeight,
    color: _palette.surface,
    // The window's traffic lights own the left edge of this strip.
    padding: const EdgeInsets.only(
      left: MonitorWindow.controlsWidth,
      right: 14,
    ),
    child: Row(
      children: [
        Text(
          '${widget.repositoryName} / ${widget.branch}',
          style: TextStyle(
            color: _palette.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: AvatarService.baseBranchColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '감시 중',
            style: TextStyle(
              fontSize: 11,
              color: AvatarService.baseBranchColor,
            ),
          ),
        ),
        const Spacer(),
        if (_refreshing)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _palette.interactive,
            ),
          ),
        const SizedBox(width: 8),
        Text('3분마다 갱신', style: TextStyle(fontSize: 12, color: _palette.muted)),
      ],
    ),
  );

  Widget _errorBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    color: const Color(0xFF3A2A14),
    child: Row(
      children: [
        const Text('⚠', style: TextStyle(color: _warn)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'GitHub에 연결할 수 없습니다 — $_error',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: _palette.text),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(_load()),
          child: const Text('재시도'),
        ),
      ],
    ),
  );

  Widget _graph(Size size) {
    final layout = MonitorLayout(
      size: size,
      commitCount: _commits.length,
      pullRequests: _pullRequests,
    );
    final laneColor = AvatarService.baseBranchColor;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: MonitorGraphPainter(
              layout: layout,
              laneColor: laneColor,
              futureFill: _palette.panel,
              boundaryColor: _palette.border,
              arrowColor: _palette.muted,
              ghostColors: [
                for (final entry in layout.orderedPullRequests)
                  _stateColor(entry.state),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          top: layout.boundaryY - 8,
          child: Container(
            color: _palette.panel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _pullRequests.isEmpty
                  ? '앞으로'
                  : '앞으로 — 접근 중 PR ${_pullRequests.length}',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: _palette.muted,
              ),
            ),
          ),
        ),
        if (_loaded && _pullRequests.isEmpty && _error == null)
          Positioned(
            left: 0,
            right: 0,
            top: math.max(16, layout.boundaryY - 96),
            child: Column(
              children: [
                Text(
                  '${widget.branch}로 향하는 열린 PR 없음',
                  style: TextStyle(fontSize: 13, color: _palette.muted),
                ),
                Text(
                  '새 PR이 올라오면 여기에 나타납니다',
                  style: TextStyle(
                    fontSize: 11,
                    color: _palette.muted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        // HEAD label.
        Positioned(
          left: layout.laneX + 18,
          top: layout.headY - 8,
          child: Text(
            '${widget.branch} · HEAD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: laneColor,
            ),
          ),
        ),
        // Ghost labels sit on the side opposite the card, so the card's
        // arrow never crosses its own label.
        for (var i = 0; i < layout.orderedPullRequests.length; i++)
          Positioned(
            left: i.isEven ? layout.laneX + 22 : null,
            right: i.isEven ? null : size.width - layout.laneX + 22,
            top: layout.ghostCenter(i).dy - 8,
            child: Text(
              '#${layout.orderedPullRequests[i].number} '
              '${_ghostLabel(i, layout.orderedPullRequests[i].state)}',
              style: TextStyle(
                fontSize: 11,
                color: _stateColor(layout.orderedPullRequests[i].state),
              ),
            ),
          ),
        // Commit avatars and labels.
        for (var i = 0; i < _commits.length; i++) ...[
          Positioned(
            left: layout.laneX - 9,
            top: layout.commitCenter(i).dy - 9,
            child: _avatar(_commits[i].author, size: 18),
          ),
          Positioned(
            right: size.width - layout.laneX + 24,
            top: layout.commitCenter(i).dy - 8,
            child: Text(
              '${_commits[i].sha.substring(0, math.min(7, _commits[i].sha.length))}'
              ' · ${_commits[i].subject} · ${_commits[i].author}',
              style: TextStyle(fontSize: 11, color: _palette.muted),
            ),
          ),
        ],
        for (var i = 0; i < layout.orderedPullRequests.length; i++)
          Positioned.fromRect(
            rect: layout.cardRect(i),
            child: _card(layout.orderedPullRequests[i]),
          ),
      ],
    );
  }

  Widget _card(MonitoredPullRequest entry) {
    final color = _stateColor(entry.state);
    final visibleReviewers = entry.reviewers.take(3).toList();
    final overflow = entry.reviewers.length - visibleReviewers.length;
    return Container(
      key: Key('monitor-card-${entry.number}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _palette.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.state == PrMonitorState.readyToMerge
              ? _ready.withValues(alpha: 0.45)
              : _palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _avatar(entry.author, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${entry.number} ${entry.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _palette.text,
                      ),
                    ),
                    Text(
                      '${entry.headRef} → ${entry.baseRef} · 커밋 ${entry.commitCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: _palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _stateLabel(entry.state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: switch (entry.mergeCommitPossible) {
                        true => 'M✓',
                        false => 'M✗',
                        null => 'M?',
                      },
                      style: TextStyle(
                        color: switch (entry.mergeCommitPossible) {
                          true => _ready,
                          false => _conflict,
                          null => _palette.muted,
                        },
                      ),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: switch (entry.rebasePossible) {
                        true => 'R✓',
                        false => 'R✗',
                        null => 'R?',
                      },
                      style: TextStyle(
                        color: switch (entry.rebasePossible) {
                          true => _ready,
                          false => _conflict,
                          null => _palette.muted,
                        },
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'D2Coding',
                  color: _palette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('리뷰', style: TextStyle(fontSize: 11, color: _palette.muted)),
              const SizedBox(width: 7),
              if (visibleReviewers.isEmpty)
                Text(
                  '아직 없음',
                  style: TextStyle(fontSize: 11, color: _palette.muted),
                )
              else
                for (final reviewer in visibleReviewers)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _avatar(
                      reviewer,
                      size: 17,
                      key: Key('monitor-reviewer-${entry.number}-$reviewer'),
                    ),
                  ),
              if (overflow > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '외 $overflow명',
                  style: TextStyle(fontSize: 11, color: _palette.muted),
                ),
              ],
              if (entry.approvals > 0) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '승인 ${entry.approvals} ✓',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _ready),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyStrip() {
    final visible = _events.take(4).toList();
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _palette.panel,
        border: Border(top: BorderSide(color: _palette.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '히스토리 — ${widget.branch} 밖의 일은 기록으로만',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.5,
              color: _palette.muted,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 18,
            runSpacing: 3,
            children: [
              for (final event in visible)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '● ',
                        style: TextStyle(
                          color: event.kind == PrEventKind.merged
                              ? _merged
                              : _palette.muted,
                        ),
                      ),
                      TextSpan(text: '#${event.number} ${event.actor} · '),
                      if (event.kind == PrEventKind.merged)
                        TextSpan(
                          text: event.mergeCommitSha != null
                              ? 'merge commit → ${event.targetRef}'
                              : 'rebase/squash → ${event.targetRef}',
                        )
                      else
                        TextSpan(
                          text: _closeReasons[event.number] != null
                              ? '닫음 · "${_closeReasons[event.number]}"'
                              : '닫음',
                        ),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, color: _palette.text),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lane, dashed future extension, ghost circles and the 1px card arrows —
/// everything below the widgets, in one paint pass.
class MonitorGraphPainter extends CustomPainter {
  MonitorGraphPainter({
    required this.layout,
    required this.laneColor,
    required this.futureFill,
    required this.boundaryColor,
    required this.arrowColor,
    required this.ghostColors,
  });

  final MonitorLayout layout;
  final Color laneColor;
  final Color futureFill;
  final Color boundaryColor;
  final Color arrowColor;
  final List<Color> ghostColors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, layout.boundaryY),
      Paint()..color = futureFill,
    );
    _dashedLine(
      canvas,
      Offset(0, layout.boundaryY),
      Offset(size.width, layout.boundaryY),
      Paint()
        ..color = boundaryColor
        ..strokeWidth = 1,
      dash: 6,
      gap: 5,
    );

    final lane = Paint()
      ..color = laneColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(layout.laneX, layout.headY),
      Offset(layout.laneX, size.height),
      lane,
    );
    final ghostTop = layout.orderedPullRequests.isEmpty
        ? layout.boundaryY - 30
        : layout.ghostCenter(layout.orderedPullRequests.length - 1).dy - 26;
    _dashedLine(
      canvas,
      Offset(layout.laneX, math.max(10, ghostTop)),
      Offset(layout.laneX, layout.headY),
      Paint()
        ..color = laneColor.withValues(alpha: 0.55)
        ..strokeWidth = 2,
      dash: 3,
      gap: 6,
    );

    // HEAD ring.
    canvas.drawCircle(
      Offset(layout.laneX, layout.headY),
      9,
      Paint()..color = futureFill,
    );
    canvas.drawCircle(
      Offset(layout.laneX, layout.headY),
      9,
      Paint()
        ..color = laneColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    for (var i = 0; i < layout.orderedPullRequests.length; i++) {
      final center = layout.ghostCenter(i);
      _dashedCircle(
        canvas,
        center,
        10,
        Paint()
          ..color = ghostColors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      final arrow = layout.arrow(i);
      final line = Paint()
        ..color = arrowColor
        ..strokeWidth = 1;
      canvas.drawLine(arrow.from, arrow.to, line);
      final direction = (arrow.to - arrow.from).direction;
      for (final spread in const [0.42, -0.42]) {
        canvas.drawLine(
          arrow.to,
          arrow.to - Offset.fromDirection(direction + spread, 7),
          line,
        );
      }
    }
  }

  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final total = (to - from).distance;
    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
    }
  }

  void _dashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const segments = 12;
    const sweep = math.pi * 2 / segments;
    for (var i = 0; i < segments; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MonitorGraphPainter oldDelegate) =>
      oldDelegate.layout.size != layout.size ||
      oldDelegate.layout.commitCount != layout.commitCount ||
      oldDelegate.ghostColors.length != ghostColors.length ||
      oldDelegate.laneColor != laneColor;
}
