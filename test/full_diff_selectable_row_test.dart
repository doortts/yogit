import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_selectable_row.dart';
import 'package:yogit/full_diff_theme.dart';

void main() {
  Future<BoxDecoration> pumpSurface(
    WidgetTester tester, {
    required bool selected,
    required bool focused,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullDiffSelectableRowSurface(
          key: const Key('surface'),
          selected: selected,
          focused: focused,
          child: const Text('row'),
        ),
      ),
    );
    return tester
            .widget<DecoratedBox>(
              find.descendant(
                of: find.byKey(const Key('surface')),
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration
        as BoxDecoration;
  }

  testWidgets('selected focused row uses selection fill and accent border', (
    tester,
  ) async {
    final decoration = await pumpSurface(tester, selected: true, focused: true);

    expect(decoration.color, fullDiffSelection);
    expect(decoration.border?.top.width, 1);
    expect(decoration.border?.top.color, fullDiffAccent);
  });

  testWidgets('selected unfocused row keeps its fill without a border', (
    tester,
  ) async {
    final decoration = await pumpSurface(
      tester,
      selected: true,
      focused: false,
    );

    expect(decoration.color, fullDiffSelection);
    expect(decoration.border, isNull);
  });

  testWidgets('unselected row uses the canvas without a border', (
    tester,
  ) async {
    final decoration = await pumpSurface(
      tester,
      selected: false,
      focused: true,
    );

    expect(decoration.color, fullDiffCanvas);
    expect(decoration.border, isNull);
  });
}
