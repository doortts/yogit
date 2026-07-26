import 'package:flutter/material.dart';

import 'git.dart';
import 'typography.dart';

class DiffFileHeader extends StatelessWidget {
  const DiffFileHeader({
    required this.file,
    required this.path,
    required this.hunkSelected,
    super.key,
  });

  final GitFileChange? file;
  final String? path;
  final bool hunkSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (path != null) Text(path!, style: technicalTextStyle),
          if (file case final file?)
            Text(file.status, style: technicalTextStyle),
          if (file case final file?)
            Text(
              file.additions == null ? '+—' : '+${file.additions}',
              style: technicalTextStyle,
            ),
          if (file case final file?)
            Text(
              file.deletions == null ? '−—' : '−${file.deletions}',
              style: technicalTextStyle,
            ),
          if (hunkSelected) const Text('Hunk'),
        ],
      ),
    );
  }
}

class DiffToolbar extends StatelessWidget {
  const DiffToolbar({
    required this.activeHunkIndex,
    required this.hunkCount,
    required this.algorithm,
    required this.ignoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.loading,
    required this.onPreviousHunk,
    required this.onNextHunk,
    required this.onAlgorithmSelected,
    required this.onIgnoreWhitespaceChanged,
    required this.onWrapLinesChanged,
    required this.onFocusModeChanged,
    super.key,
  });

  final int activeHunkIndex;
  final int hunkCount;
  final DiffAlgorithm algorithm;
  final bool ignoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final bool loading;
  final VoidCallback onPreviousHunk;
  final VoidCallback onNextHunk;
  final ValueChanged<DiffAlgorithm> onAlgorithmSelected;
  final ValueChanged<bool> onIgnoreWhitespaceChanged;
  final ValueChanged<bool> onWrapLinesChanged;
  final ValueChanged<bool> onFocusModeChanged;

  @override
  Widget build(BuildContext context) {
    final displayedHunk = hunkCount == 0
        ? 0
        : activeHunkIndex.clamp(0, hunkCount - 1) + 1;
    final canGoPrevious = hunkCount != 0 && activeHunkIndex > 0;
    final canGoNext = hunkCount != 0 && activeHunkIndex < hunkCount - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            key: const Key('previous-hunk'),
            tooltip: 'Previous hunk',
            onPressed: canGoPrevious ? onPreviousHunk : null,
            icon: const Icon(Icons.arrow_back),
          ),
          Text('$displayedHunk / $hunkCount', style: technicalTextStyle),
          IconButton(
            key: const Key('next-hunk'),
            tooltip: 'Next hunk',
            onPressed: canGoNext ? onNextHunk : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          if (loading)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Semantics(
            container: true,
            button: true,
            label: 'diff 알고리즘: ${algorithm.label}',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<DiffAlgorithm>(
                    key: const Key('diff-algorithm'),
                    tooltip: 'diff 알고리즘',
                    onSelected: onAlgorithmSelected,
                    itemBuilder: (context) => [
                      for (final value in DiffAlgorithm.values)
                        PopupMenuItem(value: value, child: Text(value.label)),
                    ],
                    child: const Text('diff 알고리즘'),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    algorithm.label,
                    key: const Key('diff-algorithm-value'),
                    style: technicalTextStyle,
                  ),
                ],
              ),
            ),
          ),
          _SemanticToggle(
            key: const Key('ignore-whitespace'),
            label: 'Ignore whitespace',
            value: ignoreWhitespace,
            icon: Icons.space_bar,
            onChanged: onIgnoreWhitespaceChanged,
          ),
          _SemanticToggle(
            key: const Key('wrap-lines'),
            label: 'Wrap lines',
            value: wrapLines,
            icon: Icons.wrap_text,
            onChanged: onWrapLinesChanged,
          ),
          _SemanticToggle(
            key: const Key('focus-mode'),
            label: 'Focus mode',
            value: focusMode,
            icon: Icons.center_focus_strong,
            onChanged: onFocusModeChanged,
          ),
        ],
      ),
    );
  }
}

class _SemanticToggle extends StatelessWidget {
  const _SemanticToggle({
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      label: label,
      onTap: () => onChanged(!value),
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: label,
          isSelected: value,
          onPressed: () => onChanged(!value),
          icon: Icon(icon),
          selectedIcon: Icon(icon),
        ),
      ),
    );
  }
}
