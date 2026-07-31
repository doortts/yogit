import 'package:flutter/material.dart';

class RepositoryBranchSelector extends StatelessWidget {
  const RepositoryBranchSelector({
    required this.repositoryName,
    required this.repositoryPath,
    required this.localBranches,
    this.remoteBranches = const [],
    this.tags = const [],
    required this.selectedBranch,
    this.comparedBranch,
    required this.refsLoading,
    required this.refsLoadFailed,
    required this.onRepositoryPressed,
    required this.onBranchSelected,
    this.onComparisonSelected,
    this.onComparisonCleared,
    super.key,
  });

  final String repositoryName;
  final String repositoryPath;
  final List<String> localBranches;
  final List<String> remoteBranches;
  final List<String> tags;
  final String? selectedBranch;
  final String? comparedBranch;
  final bool refsLoading;
  final bool refsLoadFailed;
  final VoidCallback onRepositoryPressed;
  final ValueChanged<String> onBranchSelected;
  final ValueChanged<String>? onComparisonSelected;
  final VoidCallback? onComparisonCleared;

  @override
  Widget build(BuildContext context) {
    final branchLabel = refsLoadFailed
        ? '불러오기 실패'
        : refsLoading
        ? '불러오는 중'
        : localBranches.isEmpty
        ? '브랜치 없음'
        : selectedBranch ?? localBranches.first;
    final branchEnabled =
        !refsLoading && !refsLoadFailed && localBranches.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('pick-repository'),
              onTap: onRepositoryPressed,
              child: _SelectorField(
                caption: '저장소',
                value: repositoryName,
                tooltip: repositoryPath,
                maxWidth: 180,
              ),
            ),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              key: const Key('base-branch-selector'),
              enabled: branchEnabled,
              initialValue: selectedBranch,
              onSelected: onBranchSelected,
              itemBuilder: (context) => [
                for (final branch in localBranches)
                  PopupMenuItem<String>(
                    key: Key('base-branch-menu-$branch'),
                    value: branch,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: branch == selectedBranch
                              ? const Icon(Icons.check, size: 16)
                              : null,
                        ),
                        Flexible(
                          child: Text(
                            branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: _SelectorField(
                caption: '기준 브랜치',
                value: branchLabel,
                tooltip: selectedBranch ?? branchLabel,
                maxWidth: 160,
              ),
            ),
          ),
          Expanded(
            child: _ComparisonSelector(
              localBranches: localBranches,
              remoteBranches: remoteBranches,
              tags: tags,
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

class _ComparisonSelector extends StatefulWidget {
  const _ComparisonSelector({
    required this.localBranches,
    required this.remoteBranches,
    required this.tags,
    required this.baseBranch,
    required this.comparedBranch,
    required this.enabled,
    required this.onSelected,
    required this.onCleared,
  });

  final List<String> localBranches;
  final List<String> remoteBranches;
  final List<String> tags;
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
    final query = _query.trim().toLowerCase();
    List<String> visible(List<String> branches) => branches
        .where((branch) => branch != widget.baseBranch)
        .where((branch) => branch.toLowerCase().contains(query))
        .toList();

    final local = visible(widget.localBranches);
    final remote = visible(widget.remoteBranches);
    final tags = visible(widget.tags);
    return MenuAnchor(
      controller: _controller,
      onClose: () {
        if (_query.isNotEmpty) setState(() => _query = '');
      },
      menuChildren: [
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              key: const Key('branch-diff-search'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '브랜치 검색',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
        ),
        if (widget.comparedBranch != null)
          MenuItemButton(
            key: const Key('branch-diff-clear'),
            onPressed: () {
              _controller.close();
              widget.onCleared?.call();
            },
            child: const Text('비교 해제'),
          ),
        ..._group('LOCAL', local),
        ..._group('REMOTE', remote),
        ..._group('TAG', tags),
        if (local.isEmpty && remote.isEmpty && tags.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('일치하는 브랜치 없음'),
          ),
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

  List<Widget> _group(String label, List<String> branches) => [
    if (branches.isNotEmpty)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    for (final branch in branches)
      MenuItemButton(
        key: Key('branch-diff-menu-$branch'),
        onPressed: () {
          _controller.close();
          widget.onSelected?.call(branch);
        },
        leadingIcon: SizedBox(
          width: 20,
          child: branch == widget.comparedBranch
              ? const Icon(Icons.check, size: 16)
              : null,
        ),
        child: Text(branch),
      ),
  ];
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
