import 'package:flutter/material.dart';

import 'full_diff_model.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

String fileSummary(GitFileChange file) =>
    '${file.status.characters.first} · '
    '+${file.additions ?? '—'} −${file.deletions ?? '—'}';

class GlobalFileBar extends StatelessWidget {
  const GlobalFileBar({
    required this.file,
    required this.path,
    required this.view,
    required this.encodingLabel,
    required this.canOpenEditor,
    required this.onOpenEditor,
    required this.onViewSelected,
    this.editorError,
    super.key,
  });

  final GitFileChange? file;
  final String? path;
  final FullDiffView view;
  final String encodingLabel;
  final bool canOpenEditor;
  final VoidCallback onOpenEditor;
  final ValueChanged<FullDiffView> onViewSelected;
  final String? editorError;

  @override
  Widget build(BuildContext context) {
    return _HeaderBar(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (path != null)
                const Icon(Icons.code, size: 18, color: Colors.white),
              if (path case final path?)
                Container(
                  key: const Key('file-path-chip'),
                  height: fullDiffControlHeight,
                  constraints: const BoxConstraints(maxWidth: 260),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: fullDiffChip,
                    borderRadius: BorderRadius.circular(fullDiffChipRadius),
                  ),
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: technicalTextStyle.copyWith(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              if (file case final file?)
                _HeaderBadge(
                  label: fileSummary(file),
                  foreground: fullDiffAccent,
                  background: fullDiffSelection,
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: editorError ?? '현재 작업 디렉터리의 파일을 외부 편집기로 엽니다',
                child: _HeaderButton(
                  controlKey: const Key('open-editor'),
                  label: '편집기로 열기',
                  icon: Icons.open_in_new,
                  enabled: canOpenEditor,
                  onPressed: onOpenEditor,
                ),
              ),
              FullDiffSegmentedControl<FullDiffView>(
                groupLabel: '주 화면',
                values: FullDiffView.values,
                selected: view,
                labelFor: _viewLabel,
                onSelected: onViewSelected,
              ),
              _HeaderBadge(
                label: encodingLabel,
                foreground: fullDiffAccent,
                background: fullDiffSelection,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GlobalDiffToolbar extends StatelessWidget {
  const GlobalDiffToolbar({
    required this.view,
    required this.presentation,
    required this.activeIndex,
    required this.anchorCount,
    required this.algorithm,
    required this.ignoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.loadingPatch,
    required this.onPresentationSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onAlgorithmSelected,
    required this.onIgnoreWhitespaceChanged,
    required this.onWrapLinesChanged,
    required this.onFocusModeChanged,
    super.key,
  });

  final FullDiffView view;
  final DiffPresentation presentation;
  final int activeIndex;
  final int anchorCount;
  final DiffAlgorithm algorithm;
  final bool ignoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final bool loadingPatch;
  final ValueChanged<DiffPresentation> onPresentationSelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DiffAlgorithm> onAlgorithmSelected;
  final ValueChanged<bool> onIgnoreWhitespaceChanged;
  final ValueChanged<bool> onWrapLinesChanged;
  final ValueChanged<bool> onFocusModeChanged;

  @override
  Widget build(BuildContext context) {
    final navigationEnabled = view != FullDiffView.history && anchorCount > 0;
    final displayedIndex = anchorCount == 0
        ? 0
        : activeIndex.clamp(0, anchorCount - 1) + 1;
    final canGoPrevious = navigationEnabled && activeIndex > 0;
    final canGoNext =
        navigationEnabled && activeIndex >= 0 && activeIndex < anchorCount - 1;

    return _HeaderBar(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _HeaderToggle(
                controlKey: const Key('focus-mode'),
                label: focusMode ? '탐색 패널' : '집중 모드',
                value: focusMode,
                icon: focusMode
                    ? Icons.view_sidebar_outlined
                    : Icons.vertical_split_outlined,
                onChanged: onFocusModeChanged,
              ),
              FullDiffSegmentedControl<DiffPresentation>(
                groupLabel: 'Diff 표시 방식',
                values: DiffPresentation.values,
                selected: presentation,
                labelFor: _presentationLabel,
                onSelected: onPresentationSelected,
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _NavigationButton(
                controlKey: const Key('previous-change'),
                label: '이전 변경 구간',
                icon: Icons.arrow_upward,
                onPressed: canGoPrevious ? onPrevious : null,
              ),
              Semantics(
                enabled: navigationEnabled,
                child: SizedBox(
                  key: const Key('change-counter'),
                  height: fullDiffControlHeight,
                  child: Center(
                    child: Text(
                      '$displayedIndex / $anchorCount',
                      style: technicalTextStyle.copyWith(
                        color: navigationEnabled
                            ? fullDiffMuted
                            : fullDiffMuted.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              _NavigationButton(
                controlKey: const Key('next-change'),
                label: '다음 변경 구간',
                icon: Icons.arrow_downward,
                onPressed: canGoNext ? onNext : null,
              ),
              if (loadingPatch)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              _AlgorithmMenu(
                algorithm: algorithm,
                onSelected: onAlgorithmSelected,
              ),
              _HeaderToggle(
                controlKey: const Key('ignore-whitespace'),
                label: '공백 무시',
                value: ignoreWhitespace,
                icon: Icons.space_bar,
                onChanged: onIgnoreWhitespaceChanged,
              ),
              _HeaderToggle(
                controlKey: const Key('wrap-lines'),
                label: '줄바꿈',
                value: wrapLines,
                icon: Icons.wrap_text,
                onChanged: onWrapLinesChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FullDiffSegmentedControl<T> extends StatelessWidget {
  const FullDiffSegmentedControl({
    required this.groupLabel,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    this.isEnabled,
    super.key,
  });

  final String groupLabel;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;
  final bool Function(T value)? isEnabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: groupLabel,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final value in values)
            _SegmentButton(
              label: labelFor(value),
              selected: value == selected,
              enabled: isEnabled?.call(value) ?? true,
              onPressed: () => onSelected(value),
            ),
        ],
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: fullDiffHeader,
      border: Border(bottom: BorderSide(color: fullDiffDivider)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: child,
    ),
  );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: _HeaderButton(
          label: label,
          selected: selected,
          enabled: enabled,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.controlKey,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.black : Colors.white;
    final style = TextButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: fullDiffMuted.withValues(alpha: 0.5),
      backgroundColor: selected ? Colors.white : fullDiffControl,
      disabledBackgroundColor: fullDiffControl.withValues(alpha: 0.5),
      minimumSize: Size.zero,
      padding: EdgeInsets.only(left: icon == null ? 12 : 9, right: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 14, height: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(fullDiffControlRadius),
        side: selected
            ? BorderSide.none
            : const BorderSide(color: Color(0x29FFFFFF)),
      ),
    );
    return SizedBox(
      key: controlKey,
      height: fullDiffControlHeight,
      child: icon == null
          ? TextButton(
              onPressed: enabled ? onPressed : null,
              style: style,
              child: Text(label),
            )
          : TextButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon, size: 16, color: foreground),
              label: Text(label),
              style: style,
            ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    height: fullDiffControlHeight,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(fullDiffControlRadius),
    ),
    child: Text(
      label,
      style: technicalTextStyle.copyWith(
        color: foreground,
        fontSize: 13,
        height: 1,
      ),
    ),
  );
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.controlKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    enabled: onPressed != null,
    child: IconButton(
      key: controlKey,
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      color: fullDiffMuted,
      disabledColor: fullDiffMuted.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: fullDiffControlHeight,
        height: fullDiffControlHeight,
      ),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _AlgorithmMenu extends StatelessWidget {
  const _AlgorithmMenu({required this.algorithm, required this.onSelected});

  final DiffAlgorithm algorithm;
  final ValueChanged<DiffAlgorithm> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'diff 알고리즘',
    child: PopupMenuButton<DiffAlgorithm>(
      key: const Key('diff-algorithm'),
      tooltip: 'diff 알고리즘',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final value in DiffAlgorithm.values)
          CheckedPopupMenuItem<DiffAlgorithm>(
            value: value,
            checked: value == algorithm,
            child: Text(value.label),
          ),
      ],
      padding: EdgeInsets.zero,
      child: Container(
        height: fullDiffControlHeight,
        padding: const EdgeInsets.only(left: 12, right: 7),
        decoration: BoxDecoration(
          color: fullDiffControl,
          borderRadius: BorderRadius.circular(fullDiffControlRadius),
          border: Border.all(color: const Color(0x29FFFFFF)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('diff 알고리즘'),
            SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    ),
  );
}

class _HeaderToggle extends StatelessWidget {
  const _HeaderToggle({
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
    this.controlKey,
  });

  final String label;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    toggled: value,
    label: label,
    onTap: () => onChanged(!value),
    child: ExcludeSemantics(
      child: _HeaderButton(
        controlKey: controlKey,
        label: label,
        icon: icon,
        selected: value,
        onPressed: () => onChanged(!value),
      ),
    ),
  );
}

String _viewLabel(FullDiffView view) => switch (view) {
  FullDiffView.file => 'File',
  FullDiffView.diff => 'Diff',
  FullDiffView.blame => 'Blame',
  FullDiffView.history => 'History',
};

String _presentationLabel(DiffPresentation presentation) =>
    switch (presentation) {
      DiffPresentation.hunk => 'Hunk',
      DiffPresentation.inline => 'Inline',
      DiffPresentation.split => 'Split',
    };

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
          _DiffAlgorithmButton(
            algorithm: algorithm,
            onSelected: onAlgorithmSelected,
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

class _DiffAlgorithmButton extends StatefulWidget {
  const _DiffAlgorithmButton({
    required this.algorithm,
    required this.onSelected,
  });

  final DiffAlgorithm algorithm;
  final ValueChanged<DiffAlgorithm> onSelected;

  @override
  State<_DiffAlgorithmButton> createState() => _DiffAlgorithmButtonState();
}

class _DiffAlgorithmButtonState extends State<_DiffAlgorithmButton> {
  final _popupKey = GlobalKey<PopupMenuButtonState<DiffAlgorithm>>();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'diff 알고리즘: ${widget.algorithm.label}',
      onTap: () => _popupKey.currentState?.showButtonMenu(),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(
              key: const Key('diff-algorithm'),
              child: PopupMenuButton<DiffAlgorithm>(
                key: _popupKey,
                tooltip: 'diff 알고리즘',
                onSelected: widget.onSelected,
                itemBuilder: (context) => [
                  for (final value in DiffAlgorithm.values)
                    PopupMenuItem(value: value, child: Text(value.label)),
                ],
                child: const Text('diff 알고리즘'),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.algorithm.label,
              key: const Key('diff-algorithm-value'),
              style: technicalTextStyle,
            ),
          ],
        ),
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
