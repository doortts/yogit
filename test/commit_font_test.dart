import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for the commit-message font setting:
/// - default is the system font at 13px (승인된 2안);
/// - Geist 14px and Open Sans 12px are selectable in settings (3안·4안);
/// - the choice styles the commit message cell only and round-trips JSON.
void main() {
  test('the choice round-trips and defaults to the system 13px', () {
    expect(const AppSettings().commitFont, CommitFontChoice.system);
    expect(CommitFontChoice.system.fontFamily, isNull);
    expect(CommitFontChoice.system.fontSize, 13);
    expect(CommitFontChoice.geist.fontFamily, 'Geist');
    expect(CommitFontChoice.geist.fontSize, 14);
    expect(CommitFontChoice.openSans.fontFamily, 'OpenSans');
    expect(CommitFontChoice.openSans.fontSize, 12);

    const chosen = AppSettings(commitFont: CommitFontChoice.openSans);
    expect(AppSettings.fromJson(chosen.toJson()), chosen);
    expect(
      AppSettings.fromJson(const {'commitFont': 'nonsense'}).commitFont,
      CommitFontChoice.system,
    );
  });

  for (final (choice, family, size) in const [
    (CommitFontChoice.system, null, 13.0),
    (CommitFontChoice.geist, 'Geist', 14.0),
    (CommitFontChoice.openSans, 'OpenSans', 12.0),
  ]) {
    testWidgets('the timeline draws the subject in $choice', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (_, _) async => [commit('1', 'the subject line')],
            ),
            controller: WindowFrameController(
              channel: const MethodChannel('test/yogit-window'),
            ),
            commitFont: choice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final subject = tester.widget<Text>(find.text('the subject line').first);
      expect(subject.style?.fontFamily, family);
      expect(subject.style?.fontSize, size);
    });
  }

  testWidgets('settings offers the three choices and persists the pick', (
    tester,
  ) async {
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

    await tester.ensureVisible(find.byKey(const Key('commit-font-openSans')));
    await tester.tap(find.byKey(const Key('commit-font-openSans')));
    await tester.pumpAndSettle();
    expect(changed?.commitFont, CommitFontChoice.openSans);

    await tester.ensureVisible(find.byKey(const Key('commit-font-system')));
    await tester.tap(find.byKey(const Key('commit-font-system')));
    await tester.pumpAndSettle();
    expect(changed?.commitFont, CommitFontChoice.system);
  });
}
