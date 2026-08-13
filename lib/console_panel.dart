import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'command_log.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';
import 'typography.dart';

/// The console: every process the app ran, newest at the bottom, under the
/// name of whatever the user asked for.
///
/// It shows a [CommandLog] and does nothing else to it but [CommandLog.clear] —
/// what gets written down, and what is withheld, is the log's business.
class ConsolePanel extends StatefulWidget {
  const ConsolePanel({
    required this.log,
    required this.onClose,
    this.onResize,
    this.onResizeEnd,
    this.repositoryRoot,
    super.key,
  });

  final CommandLog log;
  final VoidCallback onClose;

  /// Dragging the panel's top edge, in pixels of height gained.
  final ValueChanged<double>? onResize;
  final VoidCallback? onResizeEnd;

  /// The repository the console belongs to. A command run somewhere else says
  /// where it ran; the rest would only repeat this path on every line.
  final String? repositoryRoot;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  /// The rows the user has turned around: a failure opens itself and everything
  /// else stays shut, so what is held here is the exception to that, not the
  /// state. One set, or a failure could be opened by the app and never closed
  /// by the person reading it.
  final _turned = <int>{};

  var _failedOnly = false;
  var _searchOpen = false;
  var _query = '';
  var _follow = true;

  /// Ticks only while something is running, so an elapsed time climbs on
  /// screen instead of sitting at whatever it was when the line arrived.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_onLogChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(ConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.log, widget.log)) {
      oldWidget.log.removeListener(_onLogChanged);
      widget.log.addListener(_onLogChanged);
      // The new log may already have something in flight, and the old one's
      // ticker knows nothing about it.
      _turned.clear();
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.log.removeListener(_onLogChanged);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    setState(_syncTicker);
    if (_follow) _scrollToEnd();
  }

  void _syncTicker() {
    final running = widget.log.runningCount > 0;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => setState(() {}),
      );
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// The lines the filters leave: whatever matches, plus the name of the
  /// action any surviving command was run for. Filtering to the failures and
  /// being left with a bare `git push`, with no sign of what asked for it,
  /// would answer half the question.
  List<CommandLogEntry> get _visible {
    final entries = widget.log.entries;
    final kept = entries.where(_matches).toSet();
    final named = {
      for (final entry in kept)
        if (entry.kind == CommandLogKind.command) entry.actionId,
    };
    return [
      for (final entry in entries)
        if (kept.contains(entry) || named.contains(entry.id)) entry,
    ];
  }

  bool _matches(CommandLogEntry entry) {
    if (_failedOnly && entry.state != CommandLogState.failed) return false;
    if (_query.isEmpty) return true;
    final haystack = entry.kind == CommandLogKind.action
        ? entry.label
        : entry.commandLine;
    return haystack.toLowerCase().contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final visible = _visible;
    return Column(
      children: [
        _header(palette),
        Expanded(
          child: ColoredBox(
            color: palette.background,
            child: visible.isEmpty
                ? _empty(palette)
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      key: const Key('console-list'),
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _line(palette, visible[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _empty(TimelineThemePalette palette) => Center(
    child: Text(
      widget.log.entries.isEmpty ? '아직 실행한 명령이 없습니다' : '이 조건에 맞는 줄이 없습니다',
      style: TextStyle(fontSize: 11, color: palette.muted),
    ),
  );

  Widget _header(TimelineThemePalette palette) {
    final log = widget.log;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        key: const Key('console-resizer'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) =>
            widget.onResize?.call(-details.delta.dy),
        onVerticalDragEnd: (_) => widget.onResizeEnd?.call(),
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: palette.panel,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 3,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // The counts give way before the controls do: a window narrow
              // enough to squeeze them still has to be able to close this.
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      Text(
                        '콘솔',
                        style: TextStyle(fontSize: 11, color: palette.text),
                      ),
                      const SizedBox(width: 10),
                      _count('${log.entries.length}개', palette.muted),
                      if (log.runningCount > 0)
                        _count('실행 중 ${log.runningCount}', behindOrange),
                      if (log.failedCount > 0)
                        _count('실패 ${log.failedCount}', remoteBehindRed),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _filterChip(palette, '전체', selected: !_failedOnly),
              _filterChip(palette, '실패만', selected: _failedOnly),
              // Shut, the search is one icon; the header has three controls
              // and a row of counts to fit beside it.
              if (_searchOpen)
                Flexible(
                  flex: 2,
                  child: SizedBox(width: 120, child: _search(palette)),
                )
              else
                _iconButton(
                  key: const Key('console-search-open'),
                  icon: Icons.search,
                  tooltip: '검색',
                  color: palette.muted,
                  onPressed: () => setState(() => _searchOpen = true),
                ),
              _iconButton(
                key: const Key('console-follow'),
                icon: Icons.vertical_align_bottom,
                tooltip: _follow ? '새 줄 따라가는 중' : '새 줄 따라가기',
                color: _follow ? palette.interactive : palette.muted,
                onPressed: () => setState(() {
                  _follow = !_follow;
                  if (_follow) _scrollToEnd();
                }),
              ),
              _iconButton(
                key: const Key('console-clear'),
                icon: Icons.delete_outline,
                tooltip: '지우기',
                color: palette.muted,
                onPressed: () {
                  _turned.clear();
                  widget.log.clear();
                },
              ),
              _iconButton(
                key: const Key('console-close'),
                icon: Icons.close,
                tooltip: '닫기',
                color: palette.muted,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _count(String text, Color color) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );

  Widget _filterChip(
    TimelineThemePalette palette,
    String label, {
    required bool selected,
  }) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: GestureDetector(
      key: Key('console-filter-$label'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _failedOnly = label == '실패만'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: selected ? palette.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? palette.text : palette.muted,
          ),
        ),
      ),
    ),
  );

  /// Open, it takes the keyboard; empty and dismissed, it folds back into
  /// its icon rather than sitting there holding width nobody is using.
  Widget _search(TimelineThemePalette palette) => TextField(
    key: const Key('console-search'),
    controller: _searchController,
    autofocus: true,
    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    onTapOutside: (_) => _closeSearchIfEmpty(),
    onSubmitted: (_) => _closeSearchIfEmpty(),
    style: TextStyle(fontSize: 11, color: palette.text),
    cursorColor: palette.interactive,
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      hintText: '검색',
      hintStyle: TextStyle(fontSize: 11, color: palette.muted),
      prefixIcon: Icon(Icons.search, size: 14, color: palette.muted),
      prefixIconConstraints: const BoxConstraints(minWidth: 20),
      suffixIcon: GestureDetector(
        key: const Key('console-search-close'),
        onTap: () => setState(() {
          _searchController.clear();
          _query = '';
          _searchOpen = false;
        }),
        child: Icon(Icons.close, size: 13, color: palette.muted),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 18),
      contentPadding: EdgeInsets.zero,
    ),
  );

  void _closeSearchIfEmpty() {
    if (_query.isEmpty && _searchOpen) setState(() => _searchOpen = false);
  }

  Widget _iconButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) => Tooltip(
    message: tooltip,
    child: IconButton(
      key: key,
      icon: Icon(icon, size: 14, color: color),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
      splashRadius: 12,
    ),
  );

  /// The gutter a grouped command's rule lives in, held open on every row.
  static const _ruleColumn = 8.0;

  /// Where an opened row's output starts. Left of the command text on purpose:
  /// output is not another argument, and lining the two up would read as one.
  static const _detailIndent = 42.0;

  Widget _line(TimelineThemePalette palette, CommandLogEntry entry) =>
      entry.kind == CommandLogKind.action
      ? _actionLine(palette, entry)
      : _commandLine(palette, entry);

  /// The name of what the user asked for, and a rule down the side of the
  /// commands it turned into.
  Widget _actionLine(TimelineThemePalette palette, CommandLogEntry entry) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _time(palette, entry),
            const SizedBox(width: _ruleColumn),
            Icon(Icons.play_arrow, size: 13, color: palette.interactive),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                entry.label,
                key: Key('console-action-${entry.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(palette.interactive),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      );

  Widget _commandLine(TimelineThemePalette palette, CommandLogEntry entry) {
    final failed = entry.state == CommandLogState.failed;
    final output = _output(entry);
    final note = _note(entry);
    // A failure is open unless the reader closed it; everything else is shut
    // unless the reader opened it.
    final open = output != null && _turned.contains(entry.id) != failed;
    return GestureDetector(
      key: Key('console-command-${entry.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: output == null
          ? null
          : () => setState(
              () => _turned.contains(entry.id)
                  ? _turned.remove(entry.id)
                  : _turned.add(entry.id),
            ),
      child: ColoredBox(
        color: failed ? const Color(0xFF2A1D1E) : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _time(palette, entry),
                // Reserved on every row, drawn on the grouped ones: two lists
                // of commands that start at different x would read as two
                // different columns.
                Container(
                  width: 2,
                  height: 16,
                  margin: const EdgeInsets.only(right: _ruleColumn - 2),
                  color: entry.actionId == null
                      ? Colors.transparent
                      : palette.interactive.withValues(alpha: 0.5),
                ),
                Icon(
                  output == null
                      ? Icons.remove
                      : open
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 13,
                  color: output == null ? Colors.transparent : palette.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.commandLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono(failed ? remoteBehindRed : palette.text),
                  ),
                ),
                if (entry.workingDirectory != null &&
                    entry.workingDirectory != widget.repositoryRoot)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      entry.workingDirectory!,
                      style: _mono(palette.muted),
                    ),
                  ),
                const SizedBox(width: 8),
                _elapsed(palette, entry),
                const SizedBox(width: 8),
                SizedBox(width: 18, child: _exit(palette, entry)),
              ],
            ),
            if (open) _outputBlock(palette, entry, output),
            if (note != null) _noteLine(palette, entry, note),
          ],
        ),
      ),
    );
  }

  Widget _outputBlock(
    TimelineThemePalette palette,
    CommandLogEntry entry,
    String output,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(_detailIndent, 2, 10, 8),
    // The row's own tap closes it; a tap meant for the text it holds is not
    // that tap, and swallowing it here is what lets the output be selected.
    child: GestureDetector(
      onTap: () {},
      child: SelectableText(
        output,
        key: Key('console-detail-${entry.id}'),
        style: _mono(
          entry.state == CommandLogState.failed
              ? const Color(0xFFFF9F9A)
              : palette.muted,
        ),
      ),
    ),
  );

  /// Always under the row, open or shut: what is not on the screen is not
  /// something the reader should have to open the row to find out about.
  Widget _noteLine(
    TimelineThemePalette palette,
    CommandLogEntry entry,
    String note,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(_detailIndent, 0, 10, 5),
    child: Row(
      children: [
        if (entry.redacted)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.lock_outline, size: 13, color: palette.muted),
          ),
        Flexible(
          child: Text(
            note,
            key: Key('console-note-${entry.id}'),
            style: _mono(palette.muted),
          ),
        ),
      ],
    ),
  );

  /// What the row shows when it is opened: whatever the command said, errors
  /// first. Null when there is nothing to open — it said nothing, or what it
  /// said is being withheld.
  String? _output(CommandLogEntry entry) {
    if (entry.redacted) return null;
    final parts = [
      ?entry.failure,
      if (entry.stderr.trim().isNotEmpty) entry.stderr.trimRight(),
      if (entry.stdout.trim().isNotEmpty) entry.stdout.trimRight(),
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// The standing line under a row: why its output is not here.
  String? _note(CommandLogEntry entry) {
    if (entry.redacted) return '출력 감춤 (자격 증명)';
    final dropped =
        (entry.droppedStdoutBytes ?? 0) + (entry.droppedStderrBytes ?? 0);
    if (dropped == 0) return null;
    // What the command really said is what is here plus what was thrown away,
    // both counted in bytes.
    final kept =
        utf8.encode(entry.stdout).length + utf8.encode(entry.stderr).length;
    return '출력 ${_size(kept + dropped)} — 앞 ${_size(kept)}만 보관';
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB'
      : bytes >= 1024
      ? '${(bytes / 1024).round()}KB'
      : '$bytes바이트';

  Widget _time(TimelineThemePalette palette, CommandLogEntry entry) => Padding(
    padding: const EdgeInsets.only(left: 10, right: 8),
    child: Text(_clock(entry.startedAt), style: _mono(palette.muted)),
  );

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}.'
      '${at.millisecond.toString().padLeft(3, '0')}';

  Widget _elapsed(TimelineThemePalette palette, CommandLogEntry entry) {
    final duration = entry.duration;
    if (duration == null) {
      final running = DateTime.now().difference(entry.startedAt);
      return Text('${_took(running)}…', style: _mono(behindOrange));
    }
    return Text(_took(duration), style: _mono(palette.muted));
  }

  static String _took(Duration duration) => duration.inMilliseconds >= 1000
      ? '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s'
      : '${duration.inMilliseconds}ms';

  Widget _exit(TimelineThemePalette palette, CommandLogEntry entry) =>
      switch (entry.state) {
        CommandLogState.running => Text('●', style: _mono(behindOrange)),
        CommandLogState.ok => Text(
          '${entry.exitCode ?? 0}',
          style: _mono(successGreen),
        ),
        CommandLogState.failed => Text(
          '${entry.exitCode ?? '—'}',
          style: _mono(remoteBehindRed),
        ),
      };

  static TextStyle _mono(Color color) => TextStyle(
    fontSize: 11.5,
    height: 1.65,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
    color: color,
  );
}
