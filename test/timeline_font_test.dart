import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for the timeline's font, now that the choice styles every text
/// column rather than the commit message alone.
///
/// - One family choice: the system face (default), Geist, Open Sans;
/// - one base size the user can change, defaulting to each family's own;
/// - the base sizes the commit message, and the supporting columns — Branch /
///   Tag, Date, Author — sit one point under it so the hierarchy survives any
///   size the user picks. Graph initials scale with the base too.
void main() {
  Widget timeline({
    TimelineFontChoice font = TimelineFontChoice.system,
    double? fontSize,
    List<GitRef>? refs,
  }) => MaterialApp(
    home: TimelineScreen(
      repository: FakeGitRepository(
        (_, _) async => [
          commit(
            '1',
            'the subject line',
            refs: refs ?? const [GitRef(name: 'main', isHead: true)],
          ),
        ],
      ),
      controller: WindowFrameController(
        channel: const MethodChannel('test/yogit-window'),
      ),
      timelineFont: font,
      timelineFontSize: fontSize,
    ),
  );

  // Scoped to the rows: 'main' also names the toolbar's base branch, which
  // comes first in the tree and is not one of the columns under contract.
  TextStyle styleOf(WidgetTester tester, String text) => tester
      .widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('timeline-list')),
              matching: find.text(text),
            )
            .first,
      )
      .style!;

  group('settings model', () {
    test('the family choices carry their own default size', () {
      expect(const AppSettings().timelineFont, TimelineFontChoice.system);
      expect(const AppSettings().timelineFontSize, isNull);
      expect(TimelineFontChoice.system.fontFamily, isNull);
      expect(TimelineFontChoice.system.defaultFontSize, 13);
      expect(TimelineFontChoice.geist.fontFamily, 'Geist');
      expect(TimelineFontChoice.geist.defaultFontSize, 14);
      expect(TimelineFontChoice.openSans.fontFamily, 'OpenSans');
      expect(TimelineFontChoice.openSans.defaultFontSize, 12);
    });

    test('a stored size round-trips and an unusable one falls back', () {
      const chosen = AppSettings(
        timelineFont: TimelineFontChoice.geist,
        timelineFontSize: 16,
      );
      expect(AppSettings.fromJson(chosen.toJson()), chosen);
      expect(
        AppSettings.fromJson(const {'timelineFont': 'nonsense'}).timelineFont,
        TimelineFontChoice.system,
      );
      // Out of range or non-numeric means "use the family default".
      for (final stored in const [4, 99, 'big', null]) {
        expect(
          AppSettings.fromJson({'timelineFontSize': stored}).timelineFontSize,
          isNull,
          reason: '$stored',
        );
      }
    });

    test('the allowed sizes are a named, bounded range', () {
      expect(AppSettings.minTimelineFontSize, lessThan(13));
      expect(AppSettings.maxTimelineFontSize, greaterThan(14));
      expect(
        AppSettings.maxTimelineFontSize - AppSettings.minTimelineFontSize,
        greaterThanOrEqualTo(6),
      );
    });
  });

  group('the timeline row', () {
    testWidgets('every text column takes the chosen family', (tester) async {
      await tester.pumpWidget(timeline(font: TimelineFontChoice.geist));
      await tester.pumpAndSettle();

      for (final text in const ['the subject line', 'main', 'Ada Author']) {
        expect(styleOf(tester, text).fontFamily, 'Geist', reason: text);
      }
      // The graph disc's initials come from the same choice.
      // The row stacks the author over a separate committer, so take either.
      final initials = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(CommitAvatarStack),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(initials.style?.fontFamily, 'Geist');
    });

    testWidgets('the base sizes the message; supporting columns sit under it', (
      tester,
    ) async {
      await tester.pumpWidget(timeline(fontSize: 17));
      await tester.pumpAndSettle();

      expect(styleOf(tester, 'the subject line').fontSize, 17);
      expect(styleOf(tester, 'main').fontSize, 16);
      expect(styleOf(tester, 'Ada Author').fontSize, 16);
    });

    testWidgets('no stored size means the family default', (tester) async {
      await tester.pumpWidget(timeline(font: TimelineFontChoice.openSans));
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'the subject line').fontSize, 12);
      expect(styleOf(tester, 'main').fontSize, 11);
    });
  });

  testWidgets('settings picks the family and the size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    AppSettings? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: (value) => changed = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-section-appearance')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('timeline-font-geist')));
    await tester.tap(find.byKey(const Key('timeline-font-geist')));
    await tester.pumpAndSettle();
    expect(changed?.timelineFont, TimelineFontChoice.geist);

    // The size control moves off the default and back onto it.
    final slider = find.byKey(const Key('timeline-font-size'));
    await tester.ensureVisible(slider);
    expect(tester.widget<Slider>(slider).value, 14, reason: 'geist default');
    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(changed?.timelineFontSize, greaterThan(14));

    await tester.tap(find.byKey(const Key('timeline-font-size-reset')));
    await tester.pumpAndSettle();
    expect(changed?.timelineFontSize, isNull);
  });
}
