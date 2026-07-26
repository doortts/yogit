import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'git.dart';

const _background = Color(0xFF15171E);
const _surface = Color(0xFF1D2029);
const _raised = Color(0xFF252936);
const _border = Color(0xFF343946);
const _accent = Color(0xFF263246);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF8D94A8);
const _added = Color(0xFF9BE7B2);
const _addedFill = Color(0xFF8AD6A1);
const _deleted = Color(0xFFF29AB2);
const _renamed = Color(0xFFB6A0EA);

/// D2Coding is monospace *and* covers Hangul, so Korean commit messages keep
/// their columns aligned instead of falling back to a proportional face. Shared
/// with the timeline's data columns.
const cellFont = 'D2Coding';
const cellFontFallback = ['Menlo'];

enum DiffViewMode { unified, sideBySide }

typedef DiffCacheKey = ({
  String sha,
  String? parent,
  String path,
  DiffAlgorithm algorithm,
});

class DiffScreen extends StatefulWidget {
  const DiffScreen({
    required this.repository,
    required this.commits,
    required this.initialIndex,
    super.key,
  });

  final GitRepository repository;
  final List<GitCommit> commits;
  final int initialIndex;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  final _diffCache = <DiffCacheKey, Future<List<DiffLine>>>{};
  final _algorithmTooltipKey = GlobalKey<TooltipState>();
  final _algorithmFocusNode = FocusNode();
  final _diffScroll = ScrollController();

  /// Test hook: the text the user last selected on this screen.
  @visibleForTesting
  String? debugDiffSelection;

  late int _selectedIndex;
  String? _parent;
  List<GitFileChange> _files = const [];
  String? _selectedPath;
  List<DiffLine> _lines = const [];
  List<DiffPair> _pairs = const [];
  DiffViewMode _mode = DiffViewMode.unified;
  DiffAlgorithm _algorithm = DiffAlgorithm.gitSetting;
  DiffAlgorithm _displayedAlgorithm = DiffAlgorithm.gitSetting;
  bool _loadingFiles = false;
  bool _loadingDiff = false;
  Object? _error;
  int _fileRequest = 0;
  int _diffRequest = 0;

  GitCommit get _commit => widget.commits[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.commits.length - 1);
    _parent = _commit.parents.isEmpty ? null : _commit.parents.first;
    _loadFiles();
  }

  @override
  void dispose() {
    _algorithmFocusNode.dispose();
    _diffScroll.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    // Arrows repeat while held, like the timeline's.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    // Meta walks the commits beside the diff; bare arrows walk this commit's
    // files, which is the move you make far more often.
    if (HardwareKeyboard.instance.isMetaPressed) {
      _stepCommit(step);
    } else {
      _stepFile(step);
    }
    return KeyEventResult.handled;
  }

  void _stepFile(int delta) {
    if (_files.isEmpty) return;
    final index = _files.indexWhere((file) => file.path == _selectedPath);
    final next = (index + delta).clamp(0, _files.length - 1);
    _selectFile(_files[next].path);
  }

  void _stepCommit(int delta) => _selectCommit(
    (_selectedIndex + delta).clamp(0, widget.commits.length - 1),
  );

  Future<void> _loadFiles() async {
    final request = ++_fileRequest;
    ++_diffRequest;
    setState(() {
      _loadingFiles = true;
      _loadingDiff = false;
      _files = const [];
      _selectedPath = null;
      _lines = const [];
      _pairs = const [];
      _error = null;
    });
    try {
      final files = await widget.repository.loadFiles(_commit, parent: _parent);
      if (!mounted || request != _fileRequest) return;
      setState(() {
        _files = files;
        _selectedPath = files.isEmpty ? null : files.first.path;
        _loadingFiles = false;
      });
      if (_selectedPath != null) await _loadDiff(keepCurrent: false);
    } catch (error) {
      if (!mounted || request != _fileRequest) return;
      setState(() {
        _loadingFiles = false;
        _error = error;
      });
    }
  }

  Future<void> _loadDiff({required bool keepCurrent}) async {
    final path = _selectedPath;
    if (path == null) return;
    final request = ++_diffRequest;
    final key = (
      sha: _commit.sha,
      parent: _parent,
      path: path,
      algorithm: _algorithm,
    );
    setState(() {
      _loadingDiff = true;
      if (!keepCurrent) {
        _lines = const [];
        _pairs = const [];
      }
      _error = null;
    });
    try {
      final lines = await _diffCache.putIfAbsent(
        key,
        () => widget.repository.loadDiff(
          _commit,
          path,
          parent: _parent,
          algorithm: _algorithm,
        ),
      );
      if (!mounted || request != _diffRequest) return;
      setState(() {
        _lines = lines;
        _pairs = pairDiff(lines);
        _displayedAlgorithm = _algorithm;
        _loadingDiff = false;
      });
    } catch (error) {
      _diffCache.remove(key);
      if (!mounted || request != _diffRequest) return;
      setState(() {
        _algorithm = _displayedAlgorithm;
        _loadingDiff = false;
        _error = error;
      });
    }
  }

  void _selectCommit(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _parent = _commit.parents.isEmpty ? null : _commit.parents.first;
    });
    _loadFiles();
  }

  void _selectFile(String path) {
    if (path == _selectedPath) return;
    setState(() => _selectedPath = path);
    // A new file reads from its first line, not from wherever the last one sat.
    if (_diffScroll.hasClients) _diffScroll.jumpTo(0);
    _loadDiff(keepCurrent: false);
  }

  void _selectAlgorithm(DiffAlgorithm? algorithm) {
    if (algorithm == null || algorithm == _algorithm) return;
    setState(() => _algorithm = algorithm);
    _loadDiff(keepCurrent: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Every word on this screen is code or a path, so the whole screen reads in
    // the same Hangul-capable monospace the timeline's columns use.
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: cellFont,
          fontFamilyFallback: cellFontFallback,
        ),
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: cellFont,
            fontFamilyFallback: cellFontFallback,
          ),
          child: Focus(
            autofocus: true,
            onKeyEvent: _handleKey,
            child: Row(
              children: [
                SizedBox(
                  key: const Key('nearby-column'),
                  width: 210,
                  child: _nearbyCommits(),
                ),
                SizedBox(
                  key: const Key('details-files-column'),
                  width: 290,
                  child: _detailsAndFiles(),
                ),
                Expanded(key: const Key('diff-column'), child: _diff()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nearbyCommits() => Material(
    color: _surface,
    shape: const Border(right: BorderSide(color: _border)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, size: 17),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Nearby commits',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectable(
            ListView.builder(
              key: const Key('nearby-commits-list'),
              itemCount: widget.commits.length,
              itemBuilder: (context, index) {
                final commit = widget.commits[index];
                final selected = index == _selectedIndex;
                return ListTile(
                  key: selected ? Key('selected-nearby-${commit.sha}') : null,
                  selected: selected,
                  dense: true,
                  title: Text(
                    commit.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(commit.shortSha),
                  onTap: () => _selectCommit(index),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _detailsAndFiles() => Material(
    color: _surface,
    shape: const Border(right: BorderSide(color: _border)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _commit.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_commit.shortSha} · ${_commit.author.name}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              if (_commit.parents.length > 1) ...[
                const SizedBox(height: 8),
                DropdownButton<String>(
                  key: const Key('merge-parent-chooser'),
                  isExpanded: true,
                  value: _parent,
                  items: [
                    for (var index = 0; index < _commit.parents.length; index++)
                      DropdownMenuItem(
                        value: _commit.parents[index],
                        child: Text(
                          'Parent ${index + 1} · '
                          '${_shortSha(_commit.parents[index])}',
                        ),
                      ),
                  ],
                  onChanged: (parent) {
                    if (parent == null || parent == _parent) return;
                    setState(() => _parent = parent);
                    _loadFiles();
                  },
                ),
              ],
            ],
          ),
        ),
        _sectionHeader(const Text('Changed files')),
        Expanded(
          child: Stack(
            children: [
              _selectable(
                ListView.builder(
                  key: const Key('changed-files-list'),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final selected = file.path == _selectedPath;
                    return ListTile(
                      key: selected ? Key('selected-file-${file.path}') : null,
                      dense: true,
                      selected: selected,
                      minLeadingWidth: 18,
                      horizontalTitleGap: 7,
                      leading: _statusChip(file.status),
                      title: Text(
                        file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: cellFont,
                          fontFamilyFallback: cellFontFallback,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Text(
                        '+${file.additions ?? '-'} −${file.deletions ?? '-'}',
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                      onTap: () => _selectFile(file.path),
                    );
                  },
                ),
              ),
              if (_loadingFiles)
                const Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// `git` reports statuses like `M`, `A`, `D`, and `R100`, so the family comes
  /// from the first letter and only that letter fits the 18px chip.
  Widget _statusChip(String status) {
    final letter = status.isEmpty ? '' : status[0];
    final tint = switch (letter) {
      'A' => _addedFill,
      'D' => _deleted,
      'R' || 'C' => _renamed,
      _ => null,
    };
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.2) ?? _accent,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          color: tint ?? _text,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _diff() => ColoredBox(
    color: _background,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const BoxDecoration(
            color: _surface,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          // Wrap, so a narrow diff column moves the picker to its own line
          // instead of overflowing — with enough spacing that the mode segments
          // never read as touching the picker beside them.
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                key: const Key('diff-mode-toggle'),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ToggleButtons(
                  constraints: const BoxConstraints(
                    minHeight: 28,
                    minWidth: 72,
                  ),
                  // Mono glyphs are wide, so the segment labels carry their own
                  // smaller size instead of pushing the picker off the row.
                  textStyle: const TextStyle(fontSize: 11),
                  isSelected: [
                    _mode == DiffViewMode.unified,
                    _mode == DiffViewMode.sideBySide,
                  ],
                  onPressed: (index) =>
                      setState(() => _mode = DiffViewMode.values[index]),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Unified'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Side-by-side'),
                    ),
                  ],
                ),
              ),
              Focus(
                key: const Key('diff-algorithm-focus'),
                focusNode: _algorithmFocusNode,
                onFocusChange: (focused) {
                  if (focused) {
                    _algorithmTooltipKey.currentState?.ensureTooltipVisible();
                  }
                },
                child: Tooltip(
                  key: _algorithmTooltipKey,
                  message: _algorithm.tooltip,
                  triggerMode: TooltipTriggerMode.manual,
                  child: DropdownButton<DiffAlgorithm>(
                    key: const Key('diff-algorithm'),
                    value: _algorithm,
                    // Dense and sized like the segments beside it, so the whole
                    // control row still fits one line at the minimum window.
                    isDense: true,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 11,
                      fontFamily: cellFont,
                      fontFamilyFallback: cellFontFallback,
                    ),
                    items: [
                      for (final algorithm in DiffAlgorithm.values)
                        DropdownMenuItem(
                          value: algorithm,
                          child: Tooltip(
                            message: algorithm.tooltip,
                            child: Text(algorithm.label),
                          ),
                        ),
                    ],
                    onChanged: _selectAlgorithm,
                  ),
                ),
              ),
              // The hint is the first thing to give up room.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  'Algorithm: ${_displayedAlgorithm.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            color: const Color(0xFF492B37),
            padding: const EdgeInsets.all(8),
            child: Text(
              _error.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _deleted, fontSize: 11),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              _mode == DiffViewMode.unified
                  ? _unifiedDiff()
                  : _sideBySideDiff(),
              if (_loadingDiff)
                const Positioned(
                  right: 10,
                  top: 10,
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// One file's diff at a time, so its rows are built eagerly inside a single
  /// scroll view: a drag can then select across lines, which a lazy list cannot.
  Widget _unifiedDiff() => _selectable(
    SingleChildScrollView(
      key: const Key('unified-diff-list'),
      controller: _diffScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final line in _lines) _unifiedLine(line)],
      ),
    ),
  );

  /// Text in here is code worth copying, and the screen's own Focus keeps the
  /// arrow keys.
  Widget _selectable(Widget child) => SelectionArea(
    onSelectionChanged: (selection) =>
        debugDiffSelection = selection?.plainText,
    child: child,
  );

  Widget _unifiedLine(DiffLine line) {
    final color = _lineColor(line.kind);
    final marker = switch (line.kind) {
      DiffLineKind.add => '+',
      DiffLineKind.delete => '−',
      _ => ' ',
    };
    return ColoredBox(
      color: _lineBackground(line.kind),
      child: Row(
        children: [
          _number(line.oldNumber),
          _number(line.newNumber),
          SizedBox(
            width: 20,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontFamily: cellFont,
                fontFamilyFallback: cellFontFallback,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                color: color,
                fontFamily: cellFont,
                fontFamilyFallback: cellFontFallback,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBySideDiff() => _selectable(
    SingleChildScrollView(
      key: const Key('side-by-side-diff-list'),
      controller: _diffScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pair in _pairs)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _sideLine(pair.left, old: true)),
                Expanded(child: _sideLine(pair.right, old: false)),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _sideLine(DiffLine? line, {required bool old}) {
    final color = line == null ? _text : _lineColor(line.kind);
    final marker = switch (line?.kind) {
      DiffLineKind.add => '+',
      DiffLineKind.delete => '-',
      _ => ' ',
    };
    return ColoredBox(
      color: _lineBackground(line?.kind),
      child: Row(
        children: [
          _number(
            line == null
                ? null
                : old
                ? line.oldNumber
                : line.newNumber,
          ),
          SizedBox(
            width: 20,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontFamily: cellFont,
                fontFamilyFallback: cellFontFallback,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              line?.text ?? '',
              style: TextStyle(
                color: color,
                fontFamily: cellFont,
                fontFamilyFallback: cellFontFallback,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The gutter tints only where it carries a number; header and hunk rows would
  /// otherwise stack into a column of pale blocks down the left edge.
  Widget _number(int? number) => Container(
    width: 42,
    padding: const EdgeInsets.only(right: 6),
    alignment: Alignment.centerRight,
    color: number == null ? null : _raised,
    child: Text(
      number?.toString() ?? '',
      style: const TextStyle(
        color: _muted,
        fontFamily: cellFont,
        fontFamilyFallback: cellFontFallback,
        fontSize: 10,
      ),
    ),
  );

  Color _lineColor(DiffLineKind kind) => switch (kind) {
    DiffLineKind.add => _added,
    DiffLineKind.delete => _deleted,
    DiffLineKind.hunk || DiffLineKind.header => _muted,
    DiffLineKind.context => _text,
  };

  /// Only add and delete rows tint; hunks stay muted text on the plain
  /// background, and context rows stay plain.
  Color _lineBackground(DiffLineKind? kind) => switch (kind) {
    DiffLineKind.add => _addedFill.withValues(alpha: 0.15),
    DiffLineKind.delete => _deleted.withValues(alpha: 0.15),
    _ => Colors.transparent,
  };

  Widget _sectionHeader(Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      color: _raised,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: _text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      child: child,
    ),
  );

  String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
}
