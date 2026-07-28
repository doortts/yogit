import 'package:flutter/material.dart';

class RepositoryBranchSelector extends StatelessWidget {
  const RepositoryBranchSelector({
    required this.repositoryName,
    required this.repositoryPath,
    required this.localBranches,
    required this.selectedBranch,
    required this.refsLoading,
    required this.refsLoadFailed,
    required this.onRepositoryPressed,
    required this.onBranchSelected,
    super.key,
  });

  final String repositoryName;
  final String repositoryPath;
  final List<String> localBranches;
  final String? selectedBranch;
  final bool refsLoading;
  final bool refsLoadFailed;
  final VoidCallback onRepositoryPressed;
  final ValueChanged<String> onBranchSelected;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('pick-repository'),
            onTap: onRepositoryPressed,
            child: _SelectorField(
              caption: '저장소',
              value: repositoryName,
              tooltip: repositoryPath,
              maxWidth: 180,
            ),
          ),
          PopupMenuButton<String>(
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
        ],
      ),
    );
  }
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
