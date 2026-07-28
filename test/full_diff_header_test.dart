import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';
import 'package:yogit/typography.dart';

import 'support/full_diff_fixtures.dart';

const _sizedFile = GitFileChange(
  path: 'src/drlua.pas',
  status: 'M',
  additions: 12,
  deletions: 4,
  sizeBytes: 1536,
);

void main() {
  test('formats file sizes with compact binary units', () {
    expect(formatByteSize(null), '—');
    expect(formatByteSize(0), '0 B');
    expect(formatByteSize(1023), '1023 B');
    expect(formatByteSize(1536), '1.5 KB');
    expect(formatByteSize(10 * 1024), '10 KB');
    expect(formatByteSize(3 * 1024 * 1024), '3 MB');
  });

  testWidgets('file bar leads with an accessible return button', (
    tester,
  ) async {
    var calls = 0;
    await pumpHeaders(tester, onBack: () => calls++);

    expect(find.byKey(const Key('full-diff-back')), findsOneWidget);
    expect(find.semantics.byLabel('타임라인으로 돌아가기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('full-diff-back')));
    expect(calls, 1);
  });

  testWidgets('Diff controls use two exclusive connected groups', (
    tester,
  ) async {
    await pumpHeaders(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('main-view-controls')),
        matching: find.text('History'),
      ),
      findsNothing,
    );
    final diff = tester.getRect(find.text('Diff'));
    final blame = tester.getRect(find.text('Blame'));
    expect((diff.right - blame.left).abs(), lessThanOrEqualTo(1));

    final unified = tester.getRect(find.text('Unified'));
    final sideBySide = tester.getRect(find.text('Side-by-side'));
    expect((unified.right - sideBySide.left).abs(), lessThanOrEqualTo(1));
    expect(
      tester.getCenter(find.byKey(const Key('focus-mode'))).dx,
      lessThan(tester.getCenter(find.byKey(const Key('open-editor'))).dx),
    );
    expect(
      tester.getCenter(find.byKey(const Key('open-editor'))).dx,
      lessThan(tester.getCenter(find.text('Diff')).dx),
    );
  });

  testWidgets('History follows Hunk and only Diff tools hide in Blame', (
    tester,
  ) async {
    await pumpHeaders(tester, historySelected: true);

    expect(
      tester.getCenter(find.text('Hunk')).dx,
      lessThan(tester.getCenter(find.text('History')).dx),
    );

    await pumpHeaders(tester, view: FullDiffView.blame, historySelected: true);

    for (final label in ['Unified', 'Side-by-side', 'Hunk', 'History']) {
      expect(find.text(label), findsNothing);
    }
    for (final label in ['diff 알고리즘', 'Histogram', '공백 무시', '줄바꿈']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('History view selects Diff and its own toggle', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHeaders(
      tester,
      view: FullDiffView.history,
      historySelected: true,
    );

    expect(
      find.semantics
          .byLabel('Diff')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      find.semantics
          .byLabel('History')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('algorithm chooser marks only its applied value as selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    DiffAlgorithm? selected;
    await pumpHeaders(tester, onAlgorithmSelected: (value) => selected = value);
    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pump();

    final selectedOptions = <DiffAlgorithm>[];
    for (final algorithm in DiffAlgorithm.values) {
      final option = find.byKey(Key('algorithm-option-${algorithm.name}'));
      expect(option, findsOneWidget);
      final data = tester.getSemantics(option).getSemanticsData();
      if (data.flagsCollection.isSelected == ui.Tristate.isTrue) {
        selectedOptions.add(algorithm);
      }
    }
    expect(selectedOptions, [DiffAlgorithm.histogram]);
    expect(find.semantics.byLabel('Myers'), findsOneWidget);

    await tester.tap(find.byKey(const Key('algorithm-option-histogram')));
    await tester.pumpAndSettle();
    expect(selected, DiffAlgorithm.histogram);
    expect(find.text('Histogram'), findsOneWidget);
    expect(find.byKey(const Key('diff-algorithm-value')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('algorithm chooser previews immediately and applies on enter', (
    tester,
  ) async {
    DiffAlgorithm? selected;
    await pumpHeaders(
      tester,
      algorithm: DiffAlgorithm.histogram,
      onAlgorithmSelected: (value) => selected = value,
    );

    expect(find.text('diff 알고리즘'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm')),
        matching: find.text('Histogram'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pump();
    expect(
      find.byKey(const Key('algorithm-details-histogram')),
      findsOneWidget,
    );

    final patience = find.byKey(const Key('algorithm-option-patience'));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(patience));
    await tester.pump();

    expect(find.byKey(const Key('algorithm-details-patience')), findsOneWidget);
    expect(selected, isNull);

    await tester.tap(patience);
    await tester.pumpAndSettle();
    expect(selected, DiffAlgorithm.patience);
  });

  testWidgets(
    'algorithm label and selected value remain separate and ordered',
    (tester) async {
      await pumpHeaders(tester, algorithm: DiffAlgorithm.gitSetting);

      final label = find.byKey(const Key('diff-algorithm-label'));
      final value = find.byKey(const Key('diff-algorithm-value'));
      expect(label, findsOneWidget);
      expect(find.text('diff 알고리즘'), findsOneWidget);
      expect(value, findsOneWidget);
      expect(find.text('Git setting'), findsOneWidget);
      expect(
        tester.getTopRight(label).dx,
        lessThan(tester.getTopLeft(value).dx),
      );
    },
  );

  testWidgets(
    'algorithm semantics explain the setting and open the menu on semantic tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHeaders(tester);

      final algorithm = find.semantics.byLabel('diff 알고리즘: Histogram');
      expect(algorithm, findsOneWidget);
      final data = algorithm.evaluate().single.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(
        data.hint,
        'Git이 변경 구간을 나누는 방식을 정합니다. '
        '빈도가 낮은 줄을 기준으로 반복 코드의 경계를 찾습니다. '
        '단축키 Command Shift A',
      );
      expect(data.value, isEmpty);
      expect(data.tooltip, isEmpty);
      expect(
        find.semantics.byPredicate((node) {
          final related = node.getSemanticsData();
          return related.value.contains('Histogram') ||
              related.hint.contains('Git이 변경 구간을 나누는 방식을 정합니다') ||
              related.tooltip.contains('Git이 변경 구간을 나누는 방식을 정합니다');
        }),
        findsOneWidget,
      );

      tester.semantics.tap(algorithm);
      await tester.pumpAndSettle();

      expect(find.text('Minimal'), findsOneWidget);
      semantics.dispose();
    },
  );

  test('describes every supported diff algorithm', () {
    expect(
      diffAlgorithmDescription(DiffAlgorithm.gitSetting),
      '저장소의 Git 설정을 따릅니다. 설정이 없으면 Git 기본값을 사용합니다.',
    );
    expect(
      diffAlgorithmDescription(DiffAlgorithm.myers),
      '일반적인 소스 변경을 빠르게 비교하는 Git 기본 알고리즘입니다.',
    );
    expect(
      diffAlgorithmDescription(DiffAlgorithm.minimal),
      '계산을 더 수행해 가능한 한 작은 변경 묶음을 찾습니다.',
    );
    expect(
      diffAlgorithmDescription(DiffAlgorithm.patience),
      '고유한 줄을 기준으로 이동한 코드의 경계를 찾습니다.',
    );
    expect(
      diffAlgorithmDescription(DiffAlgorithm.histogram),
      '빈도가 낮은 줄을 기준으로 반복 코드의 경계를 찾습니다.',
    );
  });

  testWidgets(
    'history keeps navigation slots disabled and focus mode renames',
    (tester) async {
      await pumpHeaders(tester, view: FullDiffView.history);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('previous-hunk')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('next-hunk'))).onPressed,
        isNull,
      );
      expect(find.byKey(const Key('change-counter')), findsOneWidget);

      await pumpHeaders(tester, focusMode: true);
      expect(find.text('탐색 패널'), findsOneWidget);
      expect(find.text('집중 모드'), findsNothing);
    },
  );

  testWidgets('history view explains its purpose after the hover delay', (
    tester,
  ) async {
    await pumpHeaders(tester);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('History')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('파일의 변경 이력을 보여줍니다'), findsOneWidget);
  });

  testWidgets('global bars expose selected enabled and toggled semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHeaders(tester, ignoreWhitespace: true);

    expect(find.semantics.byLabel('이전 변경 구간'), findsOneWidget);
    expect(find.semantics.byLabel('다음 변경 구간'), findsOneWidget);
    expect(find.semantics.byLabel('주 화면'), findsOneWidget);
    expect(find.semantics.byLabel('Diff 표시 방식'), findsOneWidget);
    expect(
      find.semantics
          .byLabel('Diff')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      find.semantics
          .byLabel('공백 무시')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    expect(
      find.semantics
          .byLabel('줄바꿈')
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      ui.Tristate.isFalse,
    );
    semantics.dispose();
  });

  testWidgets('approved controls keep their height radius and path typeface', (
    tester,
  ) async {
    await pumpHeaders(tester);

    expect(
      tester.getSize(find.byKey(const Key('file-path-chip'))).height,
      fullDiffControlHeight,
    );
    final pathDecoration =
        tester
                .widget<Container>(find.byKey(const Key('file-path-chip')))
                .decoration
            as BoxDecoration;
    expect(
      pathDecoration.borderRadius,
      BorderRadius.circular(fullDiffChipRadius),
    );
    final path = tester.widget<Text>(find.text(fileA.path));
    expect(path.maxLines, 1);
    expect(path.overflow, TextOverflow.ellipsis);
    expect(path.style?.fontFamily, technicalFontFamily);
    expect(path.style?.fontSize, 11);

    for (final key in [
      'open-editor',
      'focus-mode',
      'diff-algorithm',
      'ignore-whitespace',
      'wrap-lines',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        fullDiffControlHeight,
      );
    }
  });

  testWidgets('active views and toggles use the approved selected colors', (
    tester,
  ) async {
    await pumpHeaders(tester, focusMode: true, ignoreWhitespace: true);

    for (final label in ['Diff', 'Hunk', '탐색 패널', '공백 무시']) {
      final decoration =
          _headerControl(tester, label).decoration as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(tester.widget<Text>(find.text(label)).style?.color, Colors.black);
    }
  });

  testWidgets('inactive controls use the approved dark outline', (
    tester,
  ) async {
    await pumpHeaders(tester);

    final openEditorDecoration =
        _headerControl(tester, '편집기로 열기').decoration as BoxDecoration;
    expect(openEditorDecoration.border?.top.color, const Color(0x1A000000));

    final algorithmDecoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byKey(const Key('diff-algorithm')),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(algorithmDecoration.border?.top.color, const Color(0x1A000000));
  });

  testWidgets('file summary and encoding badges keep a complete pill shape', (
    tester,
  ) async {
    await pumpHeaders(tester);

    for (final label in ['M · +12 −4 · 1.5 KB', 'UTF-8']) {
      final decoration =
          tester
                  .widget<Container>(
                    find.ancestor(
                      of: find.text(label),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(9999));
    }
  });

  testWidgets(
    'encoding appears after file details and never in view controls',
    (tester) async {
      await pumpHeaders(tester);

      final fileInfo = find.byKey(const Key('file-info-controls'));
      final actions = find.byKey(const Key('file-actions-controls'));
      final summary = find.byKey(const Key('file-summary-badge'));
      final encoding = find.byKey(const Key('encoding-badge'));

      expect(find.descendant(of: fileInfo, matching: summary), findsOneWidget);
      expect(find.descendant(of: fileInfo, matching: encoding), findsOneWidget);
      expect(
        tester.getTopRight(summary).dx,
        lessThan(tester.getTopLeft(encoding).dx),
      );
      expect(
        find.descendant(
          of: actions,
          matching: find.byKey(const Key('focus-mode')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: actions,
          matching: find.byKey(const Key('open-editor')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: actions,
          matching: find.byKey(const Key('main-view-controls')),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: actions, matching: encoding), findsNothing);
    },
  );

  testWidgets('encoding badge stays hidden until a value is available', (
    tester,
  ) async {
    await pumpHeaders(tester, encodingLabel: '');

    expect(find.byKey(const Key('encoding-badge')), findsNothing);
    expect(find.text('Loading'), findsNothing);
  });

  testWidgets('toggle semantics explicitly expose their enabled state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHeaders(tester, ignoreWhitespace: true);

    for (final label in ['집중 모드', '공백 무시', '줄바꿈']) {
      final data = find.semantics
          .byLabel(label)
          .evaluate()
          .single
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    }
    semantics.dispose();
  });

  testWidgets('shortcut hints overlay controls without moving them', (
    tester,
  ) async {
    await pumpHeaders(tester);
    final before = tester.getRect(find.text('Unified'));
    expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);

    await pumpHeaders(tester, showShortcutHints: true);

    expect(find.text('⌘1'), findsOneWidget);
    expect(find.text('⌘2'), findsOneWidget);
    expect(find.text('⌘3'), findsOneWidget);
    expect(find.text('⌘U'), findsOneWidget);
    expect(tester.widget<Text>(find.text('⌘1')).style?.fontSize, 11);
    expect(tester.widget<Text>(find.text('⌘U')).style?.fontSize, 11);
    expect(tester.getRect(find.text('Unified')), before);

    await pumpHeaders(tester);
    expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);
  });
}

Future<void> pumpHeaders(
  WidgetTester tester, {
  FullDiffView view = FullDiffView.diff,
  bool? historySelected,
  bool focusMode = false,
  bool ignoreWhitespace = false,
  DiffAlgorithm algorithm = DiffAlgorithm.histogram,
  String encodingLabel = 'UTF-8',
  bool showShortcutHints = false,
  VoidCallback? onBack,
  ValueChanged<DiffAlgorithm>? onAlgorithmSelected,
}) => tester.pumpWidget(
  qaApp(
    Column(
      children: [
        GlobalFileBar(
          file: _sizedFile,
          path: _sizedFile.path,
          view: view,
          encodingLabel: encodingLabel,
          canOpenEditor: true,
          focusMode: focusMode,
          showShortcutHints: showShortcutHints,
          onBack: onBack ?? () {},
          onOpenEditor: () {},
          onViewSelected: (_) {},
          onFocusModeChanged: (_) {},
        ),
        GlobalDiffToolbar(
          view: view,
          layout: DiffLayout.unified,
          hunkEnabled: true,
          activeIndex: 1,
          anchorCount: 7,
          algorithm: algorithm,
          ignoreWhitespace: ignoreWhitespace,
          wrapLines: false,
          loadingPatch: false,
          historySelected: historySelected ?? view == FullDiffView.history,
          showShortcutHints: showShortcutHints,
          onLayoutSelected: (_) {},
          onHunkChanged: (_) {},
          onHistoryChanged: (_) {},
          onPrevious: () {},
          onNext: () {},
          onAlgorithmSelected: onAlgorithmSelected ?? (_) {},
          onIgnoreWhitespaceChanged: (_) {},
          onWrapLinesChanged: (_) {},
        ),
      ],
    ),
  ),
);

Container _headerControl(WidgetTester tester, String label) => tester
    .widgetList<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)),
    )
    .singleWhere(
      (container) =>
          container.constraints?.minHeight == fullDiffControlHeight &&
          container.constraints?.maxHeight == fullDiffControlHeight &&
          container.decoration is BoxDecoration,
    );
