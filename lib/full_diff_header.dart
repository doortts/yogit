import 'package:flutter/material.dart';

import 'full_diff_algorithm_chooser.dart';
import 'full_diff_model.dart';
import 'full_diff_shortcut_hint.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'shortcut_modifier.dart';
import 'typography.dart';

export 'full_diff_algorithm_chooser.dart'
    show DiffAlgorithmDetails, diffAlgorithmDescription;

const _fullDiffInputBorder = Color(0x1A000000);

String formatByteSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value < 10 && value != value.roundToDouble() ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String fileSummary(GitFileChange file) =>
    '${file.status.characters.first} · '
    '+${file.additions ?? '—'} −${file.deletions ?? '—'} · '
    '${formatByteSize(file.sizeBytes)}';

class GlobalFileBar extends StatelessWidget {
  const GlobalFileBar({
    required this.file,
    required this.path,
    required this.view,
    required this.encodingLabel,
    required this.canOpenEditor,
    required this.focusMode,
    required this.onBack,
    required this.onOpenEditor,
    required this.onViewSelected,
    required this.onFocusModeChanged,
    this.showShortcutHints = false,
    this.editorError,
    super.key,
  });

  final GitFileChange? file;
  final String? path;
  final FullDiffView view;
  final String encodingLabel;
  final bool canOpenEditor;
  final bool focusMode;
  final VoidCallback onBack;
  final VoidCallback onOpenEditor;
  final ValueChanged<FullDiffView> onViewSelected;
  final ValueChanged<bool> onFocusModeChanged;
  final bool showShortcutHints;
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
            key: const Key('file-info-controls'),
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: '타임라인으로 돌아가기',
                button: true,
                child: IconButton(
                  key: const Key('full-diff-back'),
                  tooltip: '타임라인으로 돌아가기 (Esc)',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  color: fullDiffMuted,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              if (path case final path?)
                Container(
                  key: const Key('file-path-chip'),
                  height: fullDiffControlHeight,
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: fullDiffChip,
                    borderRadius: BorderRadius.circular(fullDiffChipRadius),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: technicalTextStyle.copyWith(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              if (file case final file?)
                _HeaderBadge(
                  controlKey: const Key('file-summary-badge'),
                  label: fileSummary(file),
                  foreground: fullDiffAccent,
                  background: fullDiffSelection,
                ),
              if (encodingLabel.isNotEmpty)
                _HeaderBadge(
                  controlKey: const Key('encoding-badge'),
                  label: encodingLabel,
                  foreground: fullDiffAccent,
                  background: fullDiffSelection,
                ),
            ],
          ),
          Wrap(
            key: const Key('file-actions-controls'),
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FullDiffShortcutHint(
                visible: showShortcutHints,
                label: shortcutLabel('⇧F'),
                child: _HeaderToggle(
                  controlKey: const Key('focus-mode'),
                  label: focusMode ? '탐색 패널' : '집중 모드',
                  value: focusMode,
                  icon: focusMode
                      ? Icons.view_sidebar_outlined
                      : Icons.vertical_split_outlined,
                  onChanged: onFocusModeChanged,
                  semanticsHint: '집중 모드 켜기 또는 끄기, 단축키 Command Shift F',
                ),
              ),
              Tooltip(
                message: editorError ?? '내장 또는 외부 에디터로 엽니다',
                child: _HeaderButton(
                  controlKey: const Key('open-editor'),
                  label: '편집기로 열기',
                  icon: Icons.open_in_new,
                  enabled: canOpenEditor,
                  onPressed: onOpenEditor,
                ),
              ),
              FullDiffSegmentedControl<FullDiffView>(
                key: const Key('main-view-controls'),
                groupLabel: '주 화면',
                values: const [FullDiffView.diff, FullDiffView.blame],
                selected: view == FullDiffView.blame
                    ? FullDiffView.blame
                    : FullDiffView.diff,
                labelFor: _viewLabel,
                onSelected: onViewSelected,
                showShortcutHints: showShortcutHints,
                shortcutLabelFor: (value) => switch (value) {
                  FullDiffView.diff => shortcutLabel('1'),
                  FullDiffView.blame => shortcutLabel('2'),
                  FullDiffView.history => null,
                },
                semanticsHintFor: (value) =>
                    '${_viewLabel(value)} 화면으로 전환, 단축키 Command ${value.index + 1}',
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
    required this.layout,
    required this.hunkEnabled,
    required this.historySelected,
    required this.activeIndex,
    required this.anchorCount,
    required this.algorithm,
    required this.ignoreWhitespace,
    required this.wrapLines,
    required this.loadingPatch,
    required this.onLayoutSelected,
    required this.onHunkChanged,
    required this.onHistoryChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onAlgorithmSelected,
    required this.onIgnoreWhitespaceChanged,
    required this.onWrapLinesChanged,
    this.algorithmChooserKey,
    this.algorithmEnabled = true,
    this.gitDiffAlgorithmSetting = const GitDiffAlgorithmSetting.gitDefault(),
    this.showLeadingControls = true,
    this.showShortcutHints = false,
    super.key,
  });

  final FullDiffView view;
  final DiffLayout layout;
  final bool hunkEnabled;
  final bool historySelected;
  final int activeIndex;
  final int anchorCount;
  final DiffAlgorithm algorithm;
  final GitDiffAlgorithmSetting? gitDiffAlgorithmSetting;
  final bool ignoreWhitespace;
  final bool wrapLines;
  final bool loadingPatch;
  final ValueChanged<DiffLayout> onLayoutSelected;
  final ValueChanged<bool> onHunkChanged;
  final ValueChanged<bool> onHistoryChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DiffAlgorithm> onAlgorithmSelected;
  final ValueChanged<bool> onIgnoreWhitespaceChanged;
  final ValueChanged<bool> onWrapLinesChanged;
  final GlobalKey<FullDiffAlgorithmChooserState>? algorithmChooserKey;
  final bool algorithmEnabled;
  final bool showLeadingControls;
  final bool showShortcutHints;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= 480;
    final dense = width <= 782;
    final navigationEnabled = view != FullDiffView.history && anchorCount > 0;
    final displayedIndex = anchorCount == 0
        ? 0
        : activeIndex.clamp(0, anchorCount - 1) + 1;
    final canGoPrevious = navigationEnabled && activeIndex > 0;
    final canGoNext =
        navigationEnabled && activeIndex >= 0 && activeIndex < anchorCount - 1;
    final algorithmControls = Wrap(
      spacing: compact ? 3 : (dense ? 0 : 6),
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('diff 알고리즘', key: Key('diff-algorithm-label')),
        FullDiffShortcutHint(
          visible: showShortcutHints,
          label: shortcutLabel('⇧A'),
          child: FullDiffAlgorithmChooser(
            key: algorithmChooserKey,
            algorithm: algorithm,
            gitDiffAlgorithmSetting: gitDiffAlgorithmSetting,
            enabled: algorithmEnabled,
            onSelected: onAlgorithmSelected,
            compact: compact,
            dense: dense,
          ),
        ),
        FullDiffShortcutHint(
          visible: showShortcutHints,
          label: shortcutLabel('⇧Space'),
          child: _HeaderToggle(
            controlKey: const Key('ignore-whitespace'),
            label: '공백 무시',
            value: ignoreWhitespace,
            icon: Icons.space_bar,
            onChanged: onIgnoreWhitespaceChanged,
            compact: compact || dense,
            semanticsHint: '공백 무시 켜기 또는 끄기, 단축키 Command Shift Space',
          ),
        ),
        FullDiffShortcutHint(
          visible: showShortcutHints,
          label: shortcutLabel('⇧L'),
          child: _HeaderToggle(
            controlKey: const Key('wrap-lines'),
            label: '줄바꿈',
            value: wrapLines,
            icon: Icons.wrap_text,
            onChanged: onWrapLinesChanged,
            compact: compact || dense,
            semanticsHint: '줄바꿈 켜기 또는 끄기, 단축키 Command Shift L',
          ),
        ),
      ],
    );
    final navigationControls = Wrap(
      spacing: compact ? 3 : (dense ? 0 : 6),
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _NavigationButton(
          controlKey: const Key('previous-hunk'),
          label: '이전 변경 구간',
          icon: Icons.arrow_upward,
          onPressed: canGoPrevious ? onPrevious : null,
          compact: compact || dense,
        ),
        Semantics(
          enabled: navigationEnabled,
          child: SizedBox(
            key: const Key('change-counter'),
            height: fullDiffControlHeight,
            child: Center(
              widthFactor: 1,
              child: Text(
                '$displayedIndex / $anchorCount',
                style: technicalTextStyle.copyWith(
                  color: navigationEnabled
                      ? fullDiffMuted
                      : fullDiffMuted.withValues(alpha: 0.5),
                  fontSize: compact ? 12 : 13,
                ),
              ),
            ),
          ),
        ),
        _NavigationButton(
          controlKey: const Key('next-hunk'),
          label: '다음 변경 구간',
          icon: Icons.arrow_downward,
          onPressed: canGoNext ? onNext : null,
          compact: compact || dense,
        ),
        if (loadingPatch)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
    final layoutControls = FullDiffSegmentedControl<DiffLayout>(
      groupLabel: 'Diff 표시 방식',
      values: DiffLayout.values,
      selected: layout,
      labelFor: _layoutLabel,
      onSelected: onLayoutSelected,
      groupHint: 'Unified와 Side-by-side 전환, 단축키 Command U',
    );
    final layoutHint = FullDiffShortcutHint(
      visible: showShortcutHints,
      label: shortcutLabel('U'),
      hintKey: const Key('shortcut-hint-layout'),
      child: layoutControls,
    );
    final hunkControl = FullDiffShortcutHint(
      visible: showShortcutHints,
      label: shortcutLabel('⇧H'),
      child: _HeaderToggle(
        controlKey: Key(hunkEnabled ? 'hunk-toggle-on' : 'hunk-toggle-off'),
        label: 'Hunk',
        value: hunkEnabled,
        icon: Icons.segment,
        onChanged: onHunkChanged,
        compact: compact,
        semanticsHint: 'Hunk 켜기 또는 끄기, 단축키 Command Shift H',
      ),
    );
    final historyControl = FullDiffShortcutHint(
      visible: showShortcutHints,
      label: shortcutLabel('3'),
      child: Tooltip(
        message: '파일의 변경 이력을 보여줍니다',
        waitDuration: const Duration(milliseconds: 500),
        child: _HeaderToggle(
          controlKey: const Key('history-toggle'),
          label: 'History',
          value: historySelected,
          icon: Icons.history,
          onChanged: onHistoryChanged,
          compact: compact,
          semanticsHint: 'History 켜기 또는 끄기, 단축키 Command 3',
        ),
      ),
    );

    return _HeaderBar(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 8,
        spacing: width <= 782 ? 0 : 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (compact)
            SizedBox(width: double.infinity, child: algorithmControls)
          else
            algorithmControls,
          navigationControls,
          if (showLeadingControls && view != FullDiffView.blame)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [layoutHint, hunkControl, historyControl],
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
    this.tooltipFor,
    this.showShortcutHints = false,
    this.shortcutLabelFor,
    this.semanticsHintFor,
    this.groupHint,
    super.key,
  });

  final String groupLabel;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;
  final bool Function(T value)? isEnabled;
  final String? Function(T value)? tooltipFor;
  final bool showShortcutHints;
  final String? Function(T value)? shortcutLabelFor;
  final String? Function(T value)? semanticsHintFor;
  final String? groupHint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: groupLabel,
      hint: groupHint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < values.length; index++)
            if (shortcutLabelFor?.call(values[index]) case final shortcut?)
              FullDiffShortcutHint(
                visible: showShortcutHints,
                label: shortcut,
                child: _SegmentButton(
                  label: labelFor(values[index]),
                  selected: values[index] == selected,
                  enabled: isEnabled?.call(values[index]) ?? true,
                  first: index == 0,
                  last: index == values.length - 1,
                  onPressed: () => onSelected(values[index]),
                  tooltip: tooltipFor?.call(values[index]),
                  semanticsHint: semanticsHintFor?.call(values[index]),
                ),
              )
            else
              _SegmentButton(
                label: labelFor(values[index]),
                selected: values[index] == selected,
                enabled: isEnabled?.call(values[index]) ?? true,
                first: index == 0,
                last: index == values.length - 1,
                onPressed: () => onSelected(values[index]),
                tooltip: tooltipFor?.call(values[index]),
                semanticsHint: semanticsHintFor?.call(values[index]),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: child,
    ),
  );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.first,
    required this.last,
    required this.onPressed,
    this.tooltip,
    this.semanticsHint,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool first;
  final bool last;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.horizontal(
      left: first ? const Radius.circular(fullDiffControlRadius) : Radius.zero,
      right: last ? const Radius.circular(fullDiffControlRadius) : Radius.zero,
    );
    const side = BorderSide(color: _fullDiffInputBorder);
    final segmentBorder = Border(
      left: first ? side : BorderSide.none,
      top: side,
      right: side,
      bottom: side,
    );
    final button = Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: enabled,
      label: label,
      hint: semanticsHint,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: _HeaderButton(
          label: label,
          selected: selected,
          enabled: enabled,
          onPressed: onPressed,
          borderRadius: radius,
          border: segmentBorder,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
    final tooltipMessage = tooltip;
    return tooltipMessage == null
        ? button
        : Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 500),
            child: button,
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
    this.compact = false,
    this.borderRadius,
    this.border,
    this.padding,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final Key? controlKey;
  final bool compact;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.black : Colors.white;
    final disabledForeground = fullDiffMuted.withValues(alpha: 0.5);
    final effectiveRadius =
        borderRadius ?? BorderRadius.circular(fullDiffControlRadius);
    final effectiveBorder =
        border ?? (selected ? null : Border.all(color: _fullDiffInputBorder));
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: effectiveRadius,
          onTap: enabled ? onPressed : null,
          child: Container(
            key: controlKey,
            height: fullDiffControlHeight,
            padding:
                padding ?? EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
            decoration: BoxDecoration(
              color: enabled
                  ? (selected ? Colors.white : fullDiffControl)
                  : fullDiffControl.withValues(alpha: 0.5),
              borderRadius: effectiveRadius,
              border: effectiveBorder,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon case final icon?) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: enabled ? foreground : disabledForeground,
                  ),
                  SizedBox(width: compact ? 3 : 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? foreground : disabledForeground,
                    fontSize: 14,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.label,
    required this.foreground,
    required this.background,
    this.controlKey,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) => Container(
    key: controlKey,
    height: fullDiffControlHeight,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        label,
        style: technicalTextStyle.copyWith(
          color: foreground,
          fontSize: 11,
          height: 1,
        ),
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
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? controlKey;
  final bool compact;

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
      constraints: BoxConstraints.tightFor(
        width: compact ? 22 : fullDiffControlHeight,
        height: fullDiffControlHeight,
      ),
      visualDensity: VisualDensity.compact,
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
    this.compact = false,
    this.semanticsHint,
  });

  final String label;
  final bool value;
  final IconData icon;
  final ValueChanged<bool> onChanged;
  final Key? controlKey;
  final bool compact;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    toggled: value,
    enabled: true,
    label: label,
    hint: semanticsHint,
    onTap: () => onChanged(!value),
    child: ExcludeSemantics(
      child: _HeaderButton(
        controlKey: controlKey,
        label: label,
        icon: icon,
        selected: value,
        onPressed: () => onChanged(!value),
        compact: compact,
      ),
    ),
  );
}

String _viewLabel(FullDiffView view) => switch (view) {
  FullDiffView.diff => 'Diff',
  FullDiffView.blame => 'Blame',
  FullDiffView.history => 'History',
};

String _layoutLabel(DiffLayout layout) => switch (layout) {
  DiffLayout.unified => 'Unified',
  DiffLayout.sideBySide => 'Side-by-side',
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
