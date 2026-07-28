import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/timeline_theme.dart';

void main() {
  test('timeline theme identifiers parse and fall back to System Graphite', () {
    expect(TimelineThemeKind.values.map((theme) => theme.storageValue), [
      'systemGraphite',
      'warmGraphite',
      'carbon',
    ]);
    expect(
      TimelineThemeKind.parse('warmGraphite'),
      TimelineThemeKind.warmGraphite,
    );
    expect(TimelineThemeKind.parse('carbon'), TimelineThemeKind.carbon);
    expect(
      TimelineThemeKind.parse('unknown'),
      TimelineThemeKind.systemGraphite,
    );
    expect(TimelineThemeKind.parse(null), TimelineThemeKind.systemGraphite);
    expect(
      TimelineThemeKind.systemGraphite.description,
      'Balanced neutral gray',
    );
  });

  test('timeline palettes use the approved surface and selection colors', () {
    expect(
      TimelineThemeKind.systemGraphite.palette,
      const TimelineThemePalette(
        background: Color(0xFF1C1C1E),
        surface: Color(0xFF242426),
        panel: Color(0xFF202022),
        raised: Color(0xFF2C2C2E),
        border: Color(0xFF38383A),
        text: Color(0xFFF2F2F7),
        muted: Color(0xFFAEAEB2),
        neutralChip: Color(0xFF2C2C2E),
        selectedRow: Color(0xFF234D72),
        interactive: Color(0xFF0A84FF),
      ),
    );
    expect(
      TimelineThemeKind.warmGraphite.palette.background,
      const Color(0xFF1D1C1B),
    );
    expect(
      TimelineThemeKind.warmGraphite.palette.selectedRow,
      const Color(0xFF44413C),
    );
    expect(
      TimelineThemeKind.warmGraphite.palette.interactive,
      const Color(0xFFFF9F0A),
    );
    expect(
      TimelineThemeKind.carbon.palette.background,
      const Color(0xFF121213),
    );
    expect(
      TimelineThemeKind.carbon.palette.selectedRow,
      const Color(0xFF38383B),
    );
    expect(
      TimelineThemeKind.carbon.palette.interactive,
      const Color(0xFF64D2FF),
    );
  });

  test('every approved text pair exceeds the minimum contrast', () {
    for (final theme in TimelineThemeKind.values) {
      final palette = theme.palette;
      expect(
        contrastRatio(palette.text, palette.background),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} primary',
      );
      expect(
        contrastRatio(palette.muted, palette.background),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} secondary',
      );
      expect(
        contrastRatio(palette.text, palette.selectedRow),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} selected',
      );
    }
  });

  testWidgets('timelineThemeData installs only the selected local palette', (
    tester,
  ) async {
    late ThemeData outside;
    late ThemeData inside;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (outerContext) {
            outside = Theme.of(outerContext);
            return Theme(
              data: timelineThemeData(
                Theme.of(outerContext),
                TimelineThemeKind.carbon,
              ),
              child: Builder(
                builder: (innerContext) {
                  inside = Theme.of(innerContext);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(outside.extension<TimelineThemePalette>(), isNull);
    expect(
      inside.extension<TimelineThemePalette>(),
      TimelineThemePalette.carbon,
    );
    expect(inside.scaffoldBackgroundColor, const Color(0xFF121213));
    expect(inside.colorScheme.surface, const Color(0xFF1C1C1E));
    expect(inside.colorScheme.primary, const Color(0xFF64D2FF));
  });
}

double contrastRatio(Color foreground, Color background) {
  double luminance(Color color) {
    double channel(double value) => value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  final first = luminance(foreground);
  final second = luminance(background);
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
