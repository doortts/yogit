import 'dart:io';

import 'package:flutter/material.dart';

import 'fuzzy_match.dart';
import 'search_icon.dart';
import 'settings.dart';
import 'timeline_theme.dart';

/// `/Users/me/repos/yogit` reads as `~/repos/yogit`, so the menu can show the
/// whole path instead of ellipsizing the interesting half away.
String shortenHomePath(String path) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty || !path.startsWith('$home/')) return path;
  return '~${path.substring(home.length)}';
}

String repositoryNameOf(String path) {
  final segments = path.split(Platform.pathSeparator)
    ..removeWhere((segment) => segment.isEmpty);
  return segments.isEmpty ? path : segments.last;
}

class RepositoryBranchSelector extends StatelessWidget {
  // (동기화 캡슐이 기준 브랜치 곁에 서는 이유는 docs/upstream-sync-mockup.html.)
  const RepositoryBranchSelector({
    required this.repositoryName,
    required this.repositoryPath,
    required this.localBranches,
    this.trailing,
    this.branchTimes = const {},
    this.remoteBranches = const [],
    this.tags = const [],
    this.tagTimes = const {},
    required this.selectedBranch,
    this.comparedBranch,
    required this.refsLoading,
    required this.refsLoadFailed,
    required this.onRepositoryPressed,
    this.recentRepositories = const [],
    this.onRecentRepositorySelected,
    this.onRecentRepositoryRemoved,
    required this.onBranchSelected,
    this.onComparisonSelected,
    this.onComparisonCleared,
    super.key,
  });

  /// 기준 브랜치 선택기 바로 오른쪽 자리 — 동기화 캡슐이 선다. 이 상태는
  /// 기준 브랜치의 속성이라 그 이름 곁에서 말해야 한다.
  final Widget? trailing;

  final String repositoryName;
  final String repositoryPath;
  final List<String> localBranches;

  /// Local or remote branch name → last commit unix time, for the row
  /// subtitles.
  final Map<String, int> branchTimes;
  final List<String> remoteBranches;
  final List<String> tags;

  /// Tag name → creation unix time, for the comparison rows.
  final Map<String, int> tagTimes;
  final String? selectedBranch;
  final String? comparedBranch;
  final bool refsLoading;
  final bool refsLoadFailed;

  /// Opens the native folder picker.
  final VoidCallback onRepositoryPressed;

  /// Repository roots, most recently opened first.
  final List<String> recentRepositories;
  final ValueChanged<String>? onRecentRepositorySelected;
  final ValueChanged<String>? onRecentRepositoryRemoved;
  final ValueChanged<String> onBranchSelected;
  final ValueChanged<String>? onComparisonSelected;
  final VoidCallback? onComparisonCleared;

  @override
  Widget build(BuildContext context) {
    final branchLabel = refsLoadFailed
        ? '불러오기 실패'
        : refsLoading
        ? '불러오는 중'
        : localBranches.isEmpty && remoteBranches.isEmpty
        ? '브랜치 없음'
        : selectedBranch ?? localBranches.first;
    final branchEnabled =
        !refsLoading &&
        !refsLoadFailed &&
        (localBranches.isNotEmpty || remoteBranches.isNotEmpty);

    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          // 이름은 고르라고 있는 것이 아니라 지금 어디에 서 있는지 말하려고
          // 있다. 저장소와 브랜치가 몫을 더 받고, 대개 '선택' 두 글자인 브랜치
          // diff가 덜 받는다.
          Expanded(
            flex: 4,
            child: _RepositorySelector(
              repositoryName: repositoryName,
              repositoryPath: repositoryPath,
              recentRepositories: recentRepositories,
              onBrowse: onRepositoryPressed,
              onSelected: onRecentRepositorySelected,
              onRemoved: onRecentRepositoryRemoved,
            ),
          ),
          Expanded(
            flex: 4,
            child: _BaseBranchSelector(
              localBranches: localBranches,
              remoteBranches: remoteBranches,
              branchTimes: branchTimes,
              selectedBranch: selectedBranch,
              enabled: branchEnabled,
              label: branchLabel,
              onSelected: onBranchSelected,
            ),
          ),
          // 캡슐은 제 크기로 서는 것이 먼저다 — 시안의 약속은 장식이 먼저
          // 물러나는 것이지 캡슐이 먼저 쭈그러드는 것이 아니다. flex 몫을
          // 넉넉히 받되 loose라 필요한 만큼만 쓰고, 정말 좁아지면 그때
          // 줄어든다. 행이 넘치는 일은 구조적으로 없다.
          if (trailing case final capsule?)
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: capsule,
              ),
            ),
          Expanded(
            flex: 3,
            child: _ComparisonSelector(
              localBranches: localBranches,
              remoteBranches: remoteBranches,
              tags: tags,
              branchTimes: branchTimes,
              tagTimes: tagTimes,
              baseBranch: selectedBranch,
              comparedBranch: comparedBranch,
              enabled: !refsLoading && !refsLoadFailed,
              onSelected: onComparisonSelected,
              onCleared: onComparisonCleared,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepositorySelector extends StatefulWidget {
  const _RepositorySelector({
    required this.repositoryName,
    required this.repositoryPath,
    required this.recentRepositories,
    required this.onBrowse,
    required this.onSelected,
    required this.onRemoved,
  });

  final String repositoryName;
  final String repositoryPath;
  final List<String> recentRepositories;
  final VoidCallback onBrowse;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onRemoved;

  @override
  State<_RepositorySelector> createState() => _RepositorySelectorState();
}

/// The menu is sized once here so the search field, every row, and the notice
/// lines all share one edge.
const _repositoryMenuWidth = 320.0;

/// Rows carry two lines, which is taller than the Material default row but
/// shorter than that default plus a second line of text.
const _repositoryRowHeight = 44.0;

ButtonStyle _repositoryRowStyle(BuildContext context) =>
    MenuItemButton.styleFrom(
      minimumSize: const Size(_repositoryMenuWidth, _repositoryRowHeight),
      maximumSize: const Size(_repositoryMenuWidth, double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: TimelineThemePalette.of(context).text,
      // Without this the Material tap target floors every row at 48px, which
      // reads as a settings list rather than a picker.
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

MenuStyle _menuPanelStyle(TimelineThemePalette palette) => MenuStyle(
  backgroundColor: WidgetStatePropertyAll(palette.raised),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: palette.border),
    ),
  ),
);

class _MenuSearchField extends StatelessWidget {
  const _MenuSearchField({
    required this.fieldKey,
    required this.hint,
    required this.onChanged,
  });

  final Key fieldKey;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        width: _repositoryMenuWidth - 16,
        child: TextField(
          key: fieldKey,
          autofocus: true,
          style: TextStyle(fontSize: 13, color: palette.text),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.background,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: palette.muted),
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            prefixIcon: Center(
              widthFactor: 1,
              child: SearchIcon(color: palette.muted),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 30,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: palette.border),
            ),
            // The field is autofocused every time the menu opens, so a focus
            // ring here would just be a permanent blue box.
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
    );
  }
}

/// Long ref lists scroll inside the panel instead of growing it past the
/// toolbar, so the menu always opens below its anchor.
class _MenuRowsScroller extends StatefulWidget {
  const _MenuRowsScroller(this.rows);

  final List<Widget> rows;

  @override
  State<_MenuRowsScroller> createState() => _MenuRowsScrollerState();
}

class _MenuRowsScrollerState extends State<_MenuRowsScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: _repositoryRowHeight * 8.5),
    child: Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        // The menu panel already owns the PrimaryScrollController; claiming
        // it here too would leave its scrollbar with two positions.
        primary: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: widget.rows),
      ),
    ),
  );
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.name,
    required this.time,
    required this.checked,
    required this.onPressed,
    super.key,
  });

  final String name;
  final int? time;
  final bool checked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    return MenuItemButton(
      style: _repositoryRowStyle(context),
      onPressed: onPressed,
      leadingIcon: SizedBox(
        width: 20,
        child: checked
            ? Icon(Icons.check, size: 16, color: palette.interactive)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.25),
          ),
          if (time case final time?)
            Text(
              relativeCommitLabel(time, DateTime.now()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.3, color: palette.muted),
            ),
        ],
      ),
    );
  }
}

Widget _menuNotice(TimelineThemePalette palette, String notice) => SizedBox(
  width: _repositoryMenuWidth,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
    child: Text(
      notice,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: palette.muted),
    ),
  ),
);

class _RepositorySelectorState extends State<_RepositorySelector> {
  final _controller = MenuController();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final query = _query.trim().toLowerCase();
    final visible = [
      for (final path in widget.recentRepositories)
        if (fuzzyMatch(path, query) ||
            fuzzyMatch(repositoryNameOf(path), query))
          path,
    ];
    final notice = visible.isNotEmpty
        ? '최대 ${AppSettings.maxRecentRepositories}개'
        : widget.recentRepositories.isEmpty
        ? '최근 저장소 없음'
        : '일치하는 저장소 없음';
    return MenuAnchor(
      controller: _controller,
      onClose: () {
        if (_query.isNotEmpty) setState(() => _query = '');
      },
      style: _menuPanelStyle(palette),
      menuChildren: [
        _MenuSearchField(
          fieldKey: const Key('repository-search'),
          hint: '저장소 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        for (final path in visible)
          _RecentRepositoryTile(
            key: Key('recent-repository-$path'),
            path: path,
            current: path == widget.repositoryPath,
            onPressed: () {
              _controller.close();
              widget.onSelected?.call(path);
            },
            onRemoved: widget.onRemoved == null
                ? null
                : () => widget.onRemoved!.call(path),
          ),
        _menuNotice(palette, notice),
        Divider(height: 9, thickness: 0.5, color: palette.border),
        MenuItemButton(
          key: const Key('pick-repository'),
          style: _repositoryRowStyle(context),
          leadingIcon: Icon(
            Icons.folder_outlined,
            size: 17,
            color: palette.muted,
          ),
          onPressed: () {
            _controller.close();
            widget.onBrowse();
          },
          child: const Text('Browse…', style: TextStyle(fontSize: 13)),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        key: const Key('repository-selector'),
        onTap: controller.open,
        child: _SelectorField(
          caption: '저장소',
          value: widget.repositoryName,
          tooltip: widget.repositoryPath,
          maxWidth: 260,
        ),
      ),
    );
  }
}

/// The remove button only shows while the row is under the pointer or holds
/// focus, so a ten-row list is not ten dismiss buttons wide.
class _RecentRepositoryTile extends StatefulWidget {
  const _RecentRepositoryTile({
    required this.path,
    required this.current,
    required this.onPressed,
    required this.onRemoved,
    super.key,
  });

  final String path;
  final bool current;
  final VoidCallback onPressed;
  final VoidCallback? onRemoved;

  @override
  State<_RecentRepositoryTile> createState() => _RecentRepositoryTileState();
}

class _RecentRepositoryTileState extends State<_RecentRepositoryTile> {
  var _highlighted = false;

  void _highlight(bool value) {
    if (_highlighted != value) setState(() => _highlighted = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final showRemove =
        _highlighted && !widget.current && widget.onRemoved != null;
    return MenuItemButton(
      onHover: _highlight,
      onFocusChange: _highlight,
      onPressed: widget.onPressed,
      style: _repositoryRowStyle(context),
      leadingIcon: SizedBox(
        width: 20,
        child: widget.current
            ? Icon(Icons.check, size: 16, color: palette.interactive)
            : null,
      ),
      trailingIcon: SizedBox(
        width: 24,
        child: showRemove
            ? IconButton(
                key: Key('forget-repository-${widget.path}'),
                icon: const Icon(Icons.close, size: 13),
                style: IconButton.styleFrom(
                  backgroundColor: palette.border,
                  foregroundColor: palette.muted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(24, 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                tooltip: '최근 목록에서 제거',
                onPressed: widget.onRemoved,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            repositoryNameOf(widget.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.25),
          ),
          Text(
            shortenHomePath(widget.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, height: 1.3, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// `1690000000` reads as `3주 전 커밋`, the second line of a branch row.
String relativeCommitLabel(int timestamp, DateTime now) {
  final elapsed = now.difference(
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
  );
  if (elapsed.inMinutes < 1) return '방금 전 커밋';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전 커밋';
  if (elapsed.inHours < 24) return '${elapsed.inHours}시간 전 커밋';
  if (elapsed.inDays < 2) return '어제 커밋';
  if (elapsed.inDays < 7) return '${elapsed.inDays}일 전 커밋';
  if (elapsed.inDays < 30) return '${elapsed.inDays ~/ 7}주 전 커밋';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 30}개월 전 커밋';
  return '${elapsed.inDays ~/ 365}년 전 커밋';
}

/// 한 메뉴 안의 브랜치 묶음: 제목 한 줄과 그 아래 행들. 기준 브랜치와 브랜치 diff가
/// 같은 모양을 쓴다.
List<Widget> _branchGroup(
  BuildContext context, {
  required String label,
  required List<String> branches,
  required Map<String, int> times,
  required String? checked,
  required String keyPrefix,
  required ValueChanged<String> onPressed,
}) => [
  if (branches.isNotEmpty)
    SizedBox(
      width: _repositoryMenuWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: TimelineThemePalette.of(context).muted,
          ),
        ),
      ),
    ),
  for (final branch in branches)
    _BranchRow(
      key: Key('$keyPrefix$branch'),
      name: branch,
      time: times[branch],
      checked: branch == checked,
      onPressed: () => onPressed(branch),
    ),
];

class _BaseBranchSelector extends StatefulWidget {
  const _BaseBranchSelector({
    required this.localBranches,
    required this.remoteBranches,
    required this.branchTimes,
    required this.selectedBranch,
    required this.enabled,
    required this.label,
    required this.onSelected,
  });

  final List<String> localBranches;
  final List<String> remoteBranches;
  final Map<String, int> branchTimes;
  final String? selectedBranch;
  final bool enabled;
  final String label;
  final ValueChanged<String> onSelected;

  @override
  State<_BaseBranchSelector> createState() => _BaseBranchSelectorState();
}

class _BaseBranchSelectorState extends State<_BaseBranchSelector> {
  final _controller = MenuController();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final query = _query.trim().toLowerCase();
    List<String> matching(List<String> branches) => [
      for (final branch in branches)
        if (fuzzyMatch(branch, query)) branch,
    ];
    final local = matching(widget.localBranches);
    // 원격 브랜치도 기준으로 고를 수 있다. 로컬 브랜치를 그 위로 재배치하는(pull
    // --rebase와 같은) 방향은 기준이 원격일 때만 나온다.
    final remote = matching(widget.remoteBranches);
    final total = local.length + remote.length;
    final notice = total == 0 ? '일치하는 브랜치 없음' : '브랜치 $total개 · 최근 커밋순';
    return MenuAnchor(
      controller: _controller,
      onClose: () {
        if (_query.isNotEmpty) setState(() => _query = '');
      },
      style: _menuPanelStyle(palette),
      menuChildren: [
        _MenuSearchField(
          fieldKey: const Key('base-branch-search'),
          hint: '브랜치 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        _MenuRowsScroller([
          for (final group in [
            (label: 'LOCAL', branches: local),
            (label: 'REMOTE', branches: remote),
          ])
            ..._branchGroup(
              context,
              label: group.label,
              branches: group.branches,
              times: widget.branchTimes,
              checked: widget.selectedBranch,
              keyPrefix: 'base-branch-menu-',
              onPressed: (branch) {
                _controller.close();
                widget.onSelected(branch);
              },
            ),
        ]),
        Divider(height: 9, thickness: 0.5, color: palette.border),
        _menuNotice(palette, notice),
      ],
      builder: (context, controller, child) => InkWell(
        key: const Key('base-branch-selector'),
        onTap: widget.enabled ? controller.open : null,
        child: _SelectorField(
          caption: '기준 브랜치',
          value: widget.label,
          tooltip: widget.selectedBranch ?? widget.label,
          maxWidth: 240,
        ),
      ),
    );
  }
}

class _ComparisonSelector extends StatefulWidget {
  const _ComparisonSelector({
    required this.localBranches,
    required this.remoteBranches,
    required this.tags,
    required this.branchTimes,
    required this.tagTimes,
    required this.baseBranch,
    required this.comparedBranch,
    required this.enabled,
    required this.onSelected,
    required this.onCleared,
  });

  final List<String> localBranches;
  final List<String> remoteBranches;
  final List<String> tags;
  final Map<String, int> branchTimes;
  final Map<String, int> tagTimes;
  final String? baseBranch;
  final String? comparedBranch;
  final bool enabled;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onCleared;

  @override
  State<_ComparisonSelector> createState() => _ComparisonSelectorState();
}

class _ComparisonSelectorState extends State<_ComparisonSelector> {
  final _controller = MenuController();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final query = _query.trim().toLowerCase();
    List<String> visible(List<String> branches) => branches
        .where((branch) => branch != widget.baseBranch)
        .where((branch) => fuzzyMatch(branch, query))
        .toList();

    final local = visible(widget.localBranches);
    final remote = visible(widget.remoteBranches);
    final tags = visible(widget.tags);
    return MenuAnchor(
      controller: _controller,
      onClose: () {
        if (_query.isNotEmpty) setState(() => _query = '');
      },
      style: _menuPanelStyle(palette),
      menuChildren: [
        _MenuSearchField(
          fieldKey: const Key('branch-diff-search'),
          hint: '브랜치 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        if (widget.comparedBranch != null)
          MenuItemButton(
            key: const Key('branch-diff-clear'),
            style: _repositoryRowStyle(context),
            leadingIcon: Icon(Icons.close, size: 16, color: palette.muted),
            onPressed: () {
              _controller.close();
              widget.onCleared?.call();
            },
            child: const Text('비교 해제', style: TextStyle(fontSize: 13)),
          ),
        _MenuRowsScroller([
          ..._group('LOCAL', local, widget.branchTimes),
          ..._group('REMOTE', remote, widget.branchTimes),
          ..._group('TAG', tags, widget.tagTimes),
        ]),
        if (local.isEmpty && remote.isEmpty && tags.isEmpty)
          _menuNotice(palette, '일치하는 브랜치 없음'),
      ],
      builder: (context, controller, child) => InkWell(
        key: const Key('branch-diff-selector'),
        onTap: widget.enabled ? controller.open : null,
        child: _SelectorField(
          caption: '브랜치 diff',
          value: widget.comparedBranch ?? '선택',
          tooltip: widget.comparedBranch ?? '비교할 브랜치 선택',
          maxWidth: 180,
        ),
      ),
    );
  }

  List<Widget> _group(
    String label,
    List<String> branches,
    Map<String, int> times,
  ) => _branchGroup(
    context,
    label: label,
    branches: branches,
    times: times,
    checked: widget.comparedBranch,
    keyPrefix: 'branch-diff-menu-',
    onPressed: (branch) {
      _controller.close();
      widget.onSelected?.call(branch);
    },
  );
}

class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.caption,
    required this.value,
    required this.tooltip,
    required this.maxWidth,
  });

  final String caption;
  final String value;
  final String tooltip;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Tooltip(
            message: tooltip,
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (constraints.maxWidth >= 32) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
