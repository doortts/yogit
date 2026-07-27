import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_theme.dart';
import 'git.dart';

@immutable
class DiffAlgorithmDetails {
  const DiffAlgorithmDetails({
    required this.description,
    required this.bestFor,
    required this.example,
  });

  final String description;
  final String bestFor;
  final List<String> example;
}

const diffAlgorithmDetails = <DiffAlgorithm, DiffAlgorithmDetails>{
  DiffAlgorithm.gitSetting: DiffAlgorithmDetails(
    description: '저장소의 Git 설정을 따릅니다. 설정이 없으면 Git 기본값을 사용합니다.',
    bestFor: '팀에서 diff.algorithm 설정을 공유하는 저장소',
    example: ['설정: diff.algorithm=histogram', '결과: Histogram 방식 사용'],
  ),
  DiffAlgorithm.myers: DiffAlgorithmDetails(
    description: '일반적인 소스 변경을 빠르게 비교하는 Git 기본 알고리즘입니다.',
    bestFor: '대부분의 작은 코드 수정',
    example: ['old: setup(); run();', 'new: setup(); log(); run();'],
  ),
  DiffAlgorithm.minimal: DiffAlgorithmDetails(
    description: '계산을 더 수행해 가능한 한 작은 변경 묶음을 찾습니다.',
    bestFor: '작은 diff가 중요하고 계산 시간이 더 걸려도 괜찮은 파일',
    example: ['반복되는 줄 사이의 변경', '가장 짧은 삭제·추가 묶음 선택'],
  ),
  DiffAlgorithm.patience: DiffAlgorithmDetails(
    description: '고유한 줄을 기준으로 이동한 코드의 경계를 찾습니다.',
    bestFor: '함수 이동과 큰 코드 재배치',
    example: ['고유 함수 선언을 기준점으로 사용', '이동한 블록의 경계 보존'],
  ),
  DiffAlgorithm.histogram: DiffAlgorithmDetails(
    description: '빈도가 낮은 줄을 기준으로 반복 코드의 경계를 찾습니다.',
    bestFor: '비슷한 줄이 많이 반복되는 소스',
    example: ['반복되는 end 사이의 변경', '드물게 나오는 선언 줄을 기준점으로 사용'],
  ),
};

String diffAlgorithmDescription(DiffAlgorithm value) =>
    diffAlgorithmDetails[value]!.description;

class FullDiffAlgorithmChooser extends StatefulWidget {
  const FullDiffAlgorithmChooser({
    required this.algorithm,
    required this.onSelected,
    this.enabled = true,
    this.compact = false,
    this.dense = false,
    super.key,
  });

  final DiffAlgorithm algorithm;
  final ValueChanged<DiffAlgorithm> onSelected;
  final bool enabled;
  final bool compact;
  final bool dense;

  @override
  State<FullDiffAlgorithmChooser> createState() =>
      FullDiffAlgorithmChooserState();
}

class FullDiffAlgorithmChooserState extends State<FullDiffAlgorithmChooser> {
  final _buttonKey = GlobalKey();
  final _buttonFocus = FocusNode(debugLabel: 'diff algorithm chooser');
  LogicalKeyboardKey? _suppressedApplyKey;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _buttonFocus.dispose();
    super.dispose();
  }

  Future<void> show() async {
    if (_menuOpen || !widget.enabled || _suppressedApplyKey != null) return;
    final buttonContext = _buttonKey.currentContext;
    if (buttonContext == null) return;
    final button = buttonContext.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final buttonRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    final menuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      360.0,
      520.0,
    );

    _menuOpen = true;
    try {
      final selected = await showMenu<DiffAlgorithm>(
        context: context,
        position: RelativeRect.fromRect(buttonRect, Offset.zero & overlay.size),
        constraints: BoxConstraints.tightFor(width: menuWidth),
        popUpAnimationStyle: AnimationStyle.noAnimation,
        requestFocus: true,
        items: [
          _AlgorithmChooserEntry(
            appliedAlgorithm: widget.algorithm,
            onApplyKeyDown: (key) => _suppressedApplyKey = key,
          ),
        ],
      );
      if (selected != null && mounted) widget.onSelected(selected);
    } finally {
      _menuOpen = false;
      if (mounted) _buttonFocus.requestFocus();
    }
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event.logicalKey != _suppressedApplyKey) {
      return false;
    }
    if (event is KeyUpEvent) {
      _suppressedApplyKey = null;
      return false;
    }
    return event is KeyDownEvent || event is KeyRepeatEvent;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('diff-algorithm'),
      container: true,
      button: true,
      enabled: widget.enabled,
      excludeSemantics: true,
      label: 'diff 알고리즘: ${widget.algorithm.label}',
      hint:
          'Git이 변경 구간을 나누는 방식을 정합니다. '
          '${diffAlgorithmDescription(widget.algorithm)}',
      onTap: widget.enabled ? show : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: _buttonKey,
          focusNode: _buttonFocus,
          onTap: widget.enabled ? show : null,
          borderRadius: BorderRadius.circular(fullDiffControlRadius),
          child: Container(
            key: const Key('diff-algorithm-value'),
            height: fullDiffControlHeight,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact || widget.dense ? 4 : 8,
            ),
            decoration: BoxDecoration(
              color: fullDiffControl,
              borderRadius: BorderRadius.circular(fullDiffControlRadius),
              border: Border.all(color: const Color(0x1A000000)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.algorithm.label),
                SizedBox(width: widget.compact ? 2 : 4),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlgorithmChooserEntry extends PopupMenuEntry<DiffAlgorithm> {
  const _AlgorithmChooserEntry({
    required this.appliedAlgorithm,
    required this.onApplyKeyDown,
  });

  final DiffAlgorithm appliedAlgorithm;
  final ValueChanged<LogicalKeyboardKey> onApplyKeyDown;

  @override
  double get height => 304;

  @override
  bool represents(DiffAlgorithm? value) => value == appliedAlgorithm;

  @override
  State<_AlgorithmChooserEntry> createState() => _AlgorithmChooserEntryState();
}

class _AlgorithmChooserEntryState extends State<_AlgorithmChooserEntry> {
  late final Map<DiffAlgorithm, FocusNode> _focusNodes;
  late DiffAlgorithm _previewAlgorithm;
  late DiffAlgorithm _focusedAlgorithm;

  @override
  void initState() {
    super.initState();
    _previewAlgorithm = widget.appliedAlgorithm;
    _focusedAlgorithm = widget.appliedAlgorithm;
    _focusNodes = {
      for (final algorithm in DiffAlgorithm.values)
        algorithm: FocusNode(debugLabel: 'diff algorithm ${algorithm.name}'),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[widget.appliedAlgorithm]!.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _moveFocus(int delta) {
    final values = DiffAlgorithm.values;
    final nextIndex = (values.indexOf(_focusedAlgorithm) + delta).clamp(
      0,
      values.length - 1,
    );
    _focusNodes[values[nextIndex]]!.requestFocus();
  }

  void _applyFocused(LogicalKeyboardKey key) {
    widget.onApplyKeyDown(key);
    Navigator.pop(context, _focusedAlgorithm);
  }

  @override
  Widget build(BuildContext context) {
    final details = diffAlgorithmDetails[_previewAlgorithm]!;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _MoveAlgorithmFocusIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveAlgorithmFocusIntent(
          -1,
        ),
        SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
            _ApplyAlgorithmIntent(LogicalKeyboardKey.enter),
        SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false):
            _ApplyAlgorithmIntent(LogicalKeyboardKey.numpadEnter),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveAlgorithmFocusIntent: CallbackAction<_MoveAlgorithmFocusIntent>(
            onInvoke: (intent) {
              _moveFocus(intent.delta);
              return null;
            },
          ),
          _ApplyAlgorithmIntent: CallbackAction<_ApplyAlgorithmIntent>(
            onInvoke: (intent) {
              _applyFocused(intent.key);
              return null;
            },
          ),
        },
        child: SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 210,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final algorithm in DiffAlgorithm.values)
                      Semantics(
                        key: Key('algorithm-option-${algorithm.name}'),
                        excludeSemantics: true,
                        button: true,
                        inMutuallyExclusiveGroup: true,
                        selected: algorithm == widget.appliedAlgorithm,
                        focused: algorithm == _focusedAlgorithm,
                        label: algorithm.label,
                        onTap: () => Navigator.pop(context, algorithm),
                        child: InkWell(
                          focusNode: _focusNodes[algorithm],
                          onFocusChange: (focused) {
                            if (focused) {
                              setState(() {
                                _focusedAlgorithm = algorithm;
                                _previewAlgorithm = algorithm;
                              });
                            }
                          },
                          onHover: (hovering) {
                            if (hovering) {
                              setState(() => _previewAlgorithm = algorithm);
                            }
                          },
                          onTap: () => Navigator.pop(context, algorithm),
                          child: SizedBox(
                            height: 44,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    child: algorithm == widget.appliedAlgorithm
                                        ? const Icon(Icons.check, size: 16)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(algorithm.label)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    key: Key('algorithm-details-${_previewAlgorithm.name}'),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _previewAlgorithm.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(details.description),
                        const SizedBox(height: 12),
                        const Text('잘 맞는 변경'),
                        const SizedBox(height: 4),
                        Text(details.bestFor),
                        const SizedBox(height: 12),
                        const Text('예시'),
                        const SizedBox(height: 4),
                        for (final line in details.example) Text(line),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveAlgorithmFocusIntent extends Intent {
  const _MoveAlgorithmFocusIntent(this.delta);

  final int delta;
}

class _ApplyAlgorithmIntent extends Intent {
  const _ApplyAlgorithmIntent(this.key);

  final LogicalKeyboardKey key;
}
