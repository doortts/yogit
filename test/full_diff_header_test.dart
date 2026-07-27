import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';
import 'package:yogit/typography.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  testWidgets('global bars keep the approved labels in exact order', (
    tester,
  ) async {
    await pumpHeaders(tester);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();

    expect(
      labels,
      containsAllInOrder([
        'src/drlua.pas',
        'M · +12 −4',
        '편집기로 열기',
        'File',
        'Diff',
        'Blame',
        'History',
        'UTF-8',
        '집중 모드',
        'Hunk',
        'Inline',
        'Split',
        '2 / 7',
        'diff 알고리즘',
        '공백 무시',
        '줄바꿈',
      ]),
    );
    expect(find.text('Histogram'), findsNothing);
  });

  testWidgets('algorithm menu shows five choices but keeps its closed label', (
    tester,
  ) async {
    DiffAlgorithm? selected;
    await pumpHeaders(tester, onAlgorithmSelected: (value) => selected = value);
    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();

    for (final label in [
      'Git setting',
      'Myers',
      'Minimal',
      'Patience',
      'Histogram',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final checked = tester
        .widgetList<CheckedPopupMenuItem<DiffAlgorithm>>(
          find.byType(CheckedPopupMenuItem<DiffAlgorithm>),
        )
        .singleWhere((item) => item.checked);
    expect(checked.value, DiffAlgorithm.histogram);

    await tester.tap(
      find.ancestor(
        of: find.text('Histogram'),
        matching: find.byType(CheckedPopupMenuItem<DiffAlgorithm>),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected, DiffAlgorithm.histogram);
    expect(find.text('diff 알고리즘'), findsOneWidget);
    expect(find.text('Histogram'), findsNothing);
  });

  testWidgets(
    'history keeps navigation slots disabled and focus mode renames',
    (tester) async {
      await pumpHeaders(tester, view: FullDiffView.history);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('previous-change')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('next-change')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('change-counter')), findsOneWidget);

      await pumpHeaders(tester, focusMode: true);
      expect(find.text('탐색 패널'), findsOneWidget);
      expect(find.text('집중 모드'), findsNothing);
    },
  );

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

    for (final label in ['M · +12 −4', 'UTF-8']) {
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
}

Future<void> pumpHeaders(
  WidgetTester tester, {
  FullDiffView view = FullDiffView.diff,
  bool focusMode = false,
  bool ignoreWhitespace = false,
  ValueChanged<DiffAlgorithm>? onAlgorithmSelected,
}) => tester.pumpWidget(
  qaApp(
    Column(
      children: [
        GlobalFileBar(
          file: fileA,
          path: fileA.path,
          view: view,
          encodingLabel: 'UTF-8',
          canOpenEditor: true,
          onOpenEditor: () {},
          onViewSelected: (_) {},
        ),
        GlobalDiffToolbar(
          view: view,
          presentation: DiffPresentation.hunk,
          activeIndex: 1,
          anchorCount: 7,
          algorithm: DiffAlgorithm.histogram,
          ignoreWhitespace: ignoreWhitespace,
          wrapLines: false,
          focusMode: focusMode,
          loadingPatch: false,
          onPresentationSelected: (_) {},
          onPrevious: () {},
          onNext: () {},
          onAlgorithmSelected: onAlgorithmSelected ?? (_) {},
          onIgnoreWhitespaceChanged: (_) {},
          onWrapLinesChanged: (_) {},
          onFocusModeChanged: (_) {},
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
