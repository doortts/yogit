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

  test('timeline palettes match every approved role color', () {
    const approved = {
      TimelineThemeKind.systemGraphite: TimelineThemePalette(
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
      TimelineThemeKind.warmGraphite: TimelineThemePalette(
        background: Color(0xFF1D1C1B),
        surface: Color(0xFF282624),
        panel: Color(0xFF232220),
        raised: Color(0xFF302E2B),
        border: Color(0xFF403E3A),
        text: Color(0xFFF3F1EE),
        muted: Color(0xFFB4B0AA),
        neutralChip: Color(0xFF302E2B),
        selectedRow: Color(0xFF44413C),
        interactive: Color(0xFFFF9F0A),
      ),
      TimelineThemeKind.carbon: TimelineThemePalette(
        background: Color(0xFF121213),
        surface: Color(0xFF1C1C1E),
        panel: Color(0xFF181819),
        raised: Color(0xFF272729),
        border: Color(0xFF303033),
        text: Color(0xFFF5F5F7),
        muted: Color(0xFFB8B8BD),
        neutralChip: Color(0xFF272729),
        selectedRow: Color(0xFF38383B),
        interactive: Color(0xFF64D2FF),
      ),
    };

    for (final MapEntry(key: theme, value: palette) in approved.entries) {
      expect(theme.palette, palette, reason: theme.label);
    }
  });

  test('every approved text pair meets its documented contrast minimum', () {
    const minimums = {
      TimelineThemeKind.systemGraphite: (
        primary: 15.25,
        secondary: 7.69,
        selected: 7.92,
      ),
      TimelineThemeKind.warmGraphite: (
        primary: 15.09,
        secondary: 7.88,
        selected: 9.01,
      ),
      TimelineThemeKind.carbon: (
        primary: 17.19,
        secondary: 9.48,
        selected: 10.73,
      ),
    };

    for (final MapEntry(key: theme, value: minimum) in minimums.entries) {
      final palette = theme.palette;
      // The design records ratios rounded to two decimal places.
      const roundingTolerance = 0.005;
      expect(
        contrastRatio(palette.text, palette.background),
        greaterThanOrEqualTo(minimum.primary - roundingTolerance),
        reason: '${theme.label} primary',
      );
      expect(
        contrastRatio(palette.muted, palette.background),
        greaterThanOrEqualTo(minimum.secondary - roundingTolerance),
        reason: '${theme.label} secondary',
      );
      expect(
        contrastRatio(palette.text, palette.selectedRow),
        greaterThanOrEqualTo(minimum.selected - roundingTolerance),
        reason: '${theme.label} selected',
      );
    }
  });

  test('copyWith preserves omitted roles and replaces supplied roles', () {
    expect(
      TimelineThemePalette.systemGraphite.copyWith(
        background: const Color(0xFF010203),
        surface: const Color(0xFF111213),
        panel: const Color(0xFF212223),
        raised: const Color(0xFF313233),
        border: const Color(0xFF414243),
        text: const Color(0xFF515253),
        muted: const Color(0xFF616263),
        neutralChip: const Color(0xFF717273),
        selectedRow: const Color(0xFF818283),
      ),
      const TimelineThemePalette(
        background: Color(0xFF010203),
        surface: Color(0xFF111213),
        panel: Color(0xFF212223),
        raised: Color(0xFF313233),
        border: Color(0xFF414243),
        text: Color(0xFF515253),
        muted: Color(0xFF616263),
        neutralChip: Color(0xFF717273),
        selectedRow: Color(0xFF818283),
        interactive: Color(0xFF0A84FF),
      ),
    );
  });

  test('lerp returns its endpoints and hand-derived midpoint', () {
    const from = TimelineThemePalette.systemGraphite;
    const to = TimelineThemePalette.carbon;

    expect(from.lerp(to, 0), from);
    expect(from.lerp(to, 1), to);
    final midpoint = from.lerp(to, 0.5);
    expectRgb(midpoint.background, 23, 23, 24.5);
    expectRgb(midpoint.surface, 32, 32, 34);
    expectRgb(midpoint.panel, 28, 28, 29.5);
    expectRgb(midpoint.raised, 41.5, 41.5, 43.5);
    expectRgb(midpoint.border, 52, 52, 54.5);
    expectRgb(midpoint.text, 243.5, 243.5, 247);
    expectRgb(midpoint.muted, 179, 179, 183.5);
    expectRgb(midpoint.neutralChip, 41.5, 41.5, 43.5);
    expectRgb(midpoint.selectedRow, 45.5, 66.5, 86.5);
    expectRgb(midpoint.interactive, 55, 171, 255);
  });

  testWidgets('palette lookup falls back without a theme extension', (
    tester,
  ) async {
    late TimelineThemePalette palette;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            palette = TimelineThemePalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(palette, TimelineThemePalette.systemGraphite);
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
    expect(inside.colorScheme.surfaceContainer, const Color(0xFF1C1C1E));
    expect(inside.colorScheme.onSurface, const Color(0xFFF5F5F7));
    expect(inside.colorScheme.primary, const Color(0xFF64D2FF));
  });
}

void expectRgb(Color actual, double red, double green, double blue) {
  expect(actual.a, 1);
  expect(actual.r * 255, closeTo(red, 1e-9));
  expect(actual.g * 255, closeTo(green, 1e-9));
  expect(actual.b * 255, closeTo(blue, 1e-9));
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
