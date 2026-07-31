import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/full_blame_view.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_side_by_side_view.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_diff_unified_view.dart';
import 'package:yogit/git.dart';
import 'package:yogit/main.dart';
import 'package:yogit/monaco_editor_screen.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/shortcut_modifier.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_theme.dart';
import 'package:yogit/typography.dart';
import 'package:yogit/window_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('commit profiles', _commitProfileTests);

  late WindowFrameController controller;

  setUp(() {
    final channel = const MethodChannel('test/yogit-window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    controller = WindowFrameController(channel: channel);
  });

  testWidgets(
    'the timeline uses System Graphite by default and a stored theme',
    (tester) async {
      final store = MemorySettingsStore();
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pumpAndSettle();

      Color toolbarColor() =>
          tester.widget<Container>(find.byKey(const Key('toolbar'))).color!;
      Color scaffoldColor() =>
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

      expect(scaffoldColor(), TimelineThemePalette.systemGraphite.background);
      expect(toolbarColor(), TimelineThemePalette.systemGraphite.surface);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        (tester
                    .widget<Container>(find.byKey(const Key('preview-surface')))
                    .decoration!
                as BoxDecoration)
            .color,
        TimelineThemePalette.systemGraphite.surface,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.setPreview(PreviewPlacement.closed);
      store.current = const AppSettings(
        timelineTheme: TimelineThemeKind.carbon,
      );
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            files: (_, _) async => const [
              GitFileChange(
                path: 'lib/a.dart',
                status: 'M',
                additions: 1,
                deletions: 1,
              ),
            ],
          ),
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(scaffoldColor(), TimelineThemePalette.carbon.background);
      expect(toolbarColor(), TimelineThemePalette.carbon.surface);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        (tester
                    .widget<Container>(find.byKey(const Key('preview-surface')))
                    .decoration!
                as BoxDecoration)
            .color,
        TimelineThemePalette.carbon.surface,
      );
      final fileRow =
          tester
                  .widget<InkWell>(
                    find.ancestor(
                      of: find.byKey(const Key('preview-state-lib/a.dart')),
                      matching: find.byType(InkWell),
                    ),
                  )
                  .child!
              as DecoratedBox;
      final fileRowDecoration = fileRow.decoration as BoxDecoration;
      expect(fileRowDecoration.color, TimelineThemePalette.carbon.neutralChip);
      expect(fileRowDecoration.border, isNull);
      expect(fileRowDecoration.borderRadius, BorderRadius.circular(6));
      expect(
        tester
            .widget<Container>(
              find.byKey(const Key('preview-state-lib/a.dart')),
            )
            .decoration,
        isNull,
      );
    },
  );

  testWidgets(
    'checked-out branch uses a HEAD badge without a selected row fill',
    (tester) async {
      for (final theme in TimelineThemeKind.values) {
        final store = MemorySettingsStore()
          ..current = AppSettings(timelineTheme: theme);
        await tester.pumpWidget(
          YogitApp(
            key: ValueKey(theme),
            repository: FakeGitRepository(
              (_, _) async => [commit('3', 'checked out commit')],
              refs: const RepoRefs(
                local: ['main', 'release'],
                current: 'main',
                tips: {'main': '3', 'release': '2'},
                localTips: {'main': '3', 'release': '2'},
              ),
            ),
            settingsStore: store,
            discoverAvatars: false,
            windowFrameController: controller,
          ),
        );
        await tester.pumpAndSettle();

        final row = tester.widget<SizedBox>(
          find.byKey(const Key('sidebar-row-main')),
        );
        expect(row.height, isNotNull);
        final badge = find.byKey(const Key('sidebar-head-main'));
        expect(badge, findsOneWidget);
        expect(
          find.descendant(of: badge, matching: find.text('HEAD')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Tooltip>(
                find.ancestor(of: badge, matching: find.byType(Tooltip)),
              )
              .message,
          '현재 체크아웃된 브랜치입니다',
        );
        expect(find.byKey(const Key('sidebar-head-release')), findsNothing);
      }
    },
  );

  final hierarchyRoleCases =
      <
        ({
          String label,
          Color Function(WidgetTester tester) actual,
          Color Function(TimelineThemePalette palette) expected,
        })
      >[
        (
          label: 'placement control',
          actual: (tester) {
            final control = tester.widget<Container>(
              find.byKey(const Key('preview-placement')),
            );
            return (control.decoration! as BoxDecoration).color!;
          },
          expected: (palette) => palette.raised,
        ),
        (
          label: 'status bar',
          actual: (tester) {
            final bar = tester.widget<Container>(
              find.ancestor(
                of: find.byKey(const Key('status-timestamp')),
                matching: find.byType(Container),
              ),
            );
            return (bar.decoration! as BoxDecoration).color!;
          },
          expected: (palette) => palette.surface,
        ),
        (
          label: 'idle keycap',
          actual: (tester) {
            final keycap = tester.widget<Container>(
              find.descendant(
                of: find.byKey(const Key('keycap-Enter')),
                matching: find.byType(Container),
              ),
            );
            return (keycap.decoration! as BoxDecoration).color!;
          },
          expected: (palette) => palette.raised,
        ),
      ];

  for (final role in hierarchyRoleCases) {
    testWidgets(
      '${role.label} uses its approved role under every timeline theme',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1400, 800);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        for (final theme in TimelineThemeKind.values) {
          final store = MemorySettingsStore()
            ..current = AppSettings(timelineTheme: theme);
          await tester.pumpWidget(
            YogitApp(
              key: ValueKey(theme),
              repository: FakeGitRepository(
                (_, _) async => [commit('3', 'checked out commit')],
                refs: const RepoRefs(
                  local: ['main'],
                  current: 'main',
                  tips: {'main': '3'},
                  localTips: {'main': '3'},
                ),
              ),
              settingsStore: store,
              discoverAvatars: false,
              windowFrameController: controller,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            role.actual(tester),
            role.expected(theme.palette),
            reason: theme.label,
          );
        }
      },
    );
  }

  testWidgets('the stored timeline theme colors the base-branch popup', (
    tester,
  ) async {
    final store = MemorySettingsStore()
      ..current = const AppSettings(timelineTheme: TimelineThemeKind.carbon);
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('tip', 'tip')],
          refs: const RepoRefs(
            local: ['main', 'release'],
            current: 'main',
            tips: {'main': 'tip', 'release': 'tip'},
          ),
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();

    final item = find.byKey(const Key('base-branch-menu-release'));
    final menuMaterials = tester.widgetList<Material>(
      find.ancestor(of: item, matching: find.byType(Material)),
    );
    expect(
      menuMaterials.map((material) => material.color),
      contains(const Color(0xFF272729)),
    );

    final text = find.descendant(of: item, matching: find.text('release'));
    expect(
      DefaultTextStyle.of(tester.element(text)).style.color,
      const Color(0xFFF5F5F7),
    );
  });

  testWidgets('keyboard and pointer control selection and preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
            commit('3', 'third commit'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('timeline-list')),
    );
    expect(TimelineScreen.rowHeight, 30);
    expect(list.itemExtent, TimelineScreen.rowHeight);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    // The preview starts hidden and only a key opens it.
    expect(find.text('Commit & Diff'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('second commit'), findsOneWidget);
    final selected = find.byKey(const Key('selected-row-2'));
    expect(selected, findsOneWidget);
    final selectedBase =
        tester.widget<GestureDetector>(selected).child! as Container;
    expect(selectedBase.color, TimelineThemePalette.systemGraphite.background);

    final band = find.byKey(const Key('selection-band-2'));
    final bandRect = tester.getRect(band);
    final graphRect = tester.getRect(find.byKey(const Key('graph-cell-1')));
    final refsRect = tester.getRect(find.byKey(const Key('refs-cell-1')));
    final graphPainter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-1')))
                .painter!
            as CommitGraphPainter;

    expect(
      bandRect.left,
      graphRect.left + graphPainter.laneX(graphPainter.row.lane),
    );
    expect(bandRect.left, greaterThan(refsRect.right));
    expect(bandRect.right, tester.getRect(selected).right);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);

    // Enter toggles: a second press closes what the first opened.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);

    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    // A click selects; it no longer opens the panel.
    await tester.tap(find.text('third commit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-3')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsNothing);

    // Space no longer opens the panel; Enter is the only toggle.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-panel')),
        matching: find.text('third commit'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);
  });

  testWidgets('selection moves rebuild only the rows that changed', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(8, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // A row that does not rebuild keeps the very same widget instances.
    Text subject(int index) => tester.widget<Text>(find.text('commit $index'));
    final before = {
      for (var index = 0; index < 8; index++) index: subject(index),
    };

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(identical(subject(0), before[0]), isFalse);
    expect(identical(subject(1), before[1]), isFalse);
    for (var index = 2; index < 8; index++) {
      expect(
        identical(subject(index), before[index]),
        isTrue,
        reason: '$index',
      );
    }
  });

  testWidgets('keyboard selection scrolls only at the viewport edges', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(60, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('timeline-list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final viewport = position.viewportDimension;

    // Moving inside the viewport leaves the list where it is.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);

    // The date heading leads the list, so the first commit sits at entry 1.
    var index = 2;
    while (position.pixels == 0 && index < 40) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      index++;
    }

    // Nothing moved until the selected row's bottom passed the viewport bottom,
    // and then only far enough to hold the row flush against that edge.
    expect(
      index * TimelineScreen.rowHeight,
      greaterThan(viewport - TimelineScreen.rowHeight),
    );
    expect(position.pixels, (index + 1) * TimelineScreen.rowHeight - viewport);
    final anchored = position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    index++;
    expect(position.pixels, anchored + TimelineScreen.rowHeight);

    // Upward is symmetric: the row stays visible without a scroll until it would
    // pass the top edge, and the walk ends with the list back at the top.
    while (index > 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      index--;
      expect(
        position.pixels,
        lessThanOrEqualTo(index * TimelineScreen.rowHeight),
      );
      expect(
        position.pixels,
        greaterThanOrEqualTo((index + 1) * TimelineScreen.rowHeight - viewport),
      );
    }
    // The walk ends with the first commit flush at the top; the date heading
    // above it stays off screen until the user scrolls there.
    expect(position.pixels, TimelineScreen.rowHeight);
    expect(find.byKey(const Key('selected-row-0')), findsOneWidget);
  });

  testWidgets('holding an arrow key keeps moving the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(6, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-0')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    // Autorepeat while the key stays held.
    for (var repeat = 2; repeat <= 4; repeat++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.byKey(Key('selected-row-$repeat')), findsOneWidget);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

    // Enter and Space ignore repeats, so a held key opens the panel once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  });

  testWidgets('graph viewport resize does not scale lane coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('3', 'merge', parents: const ['2', 'branch']),
            commit('2', 'main', parents: const ['1']),
            commit('branch', 'branch', parents: const ['1']),
            commit('1', 'root'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final beforeSize = tester.getSize(find.byKey(const Key('graph-painter-0')));
    final before =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    final beforeSpacing = before.laneX(1) - before.laneX(0);

    expect(timelineColumns.keys, [
      'refs',
      'graph',
      'hash',
      'commit',
      'time',
      'name',
    ]);
    for (final column in timelineColumns.keys) {
      expect(find.byKey(Key('$column-resizer')), findsOneWidget);
    }
    final header = tester.widget<Text>(find.text('GRAPH'));
    expect(header.style?.fontFamily, 'monospace');
    expect(header.style?.fontSize, 12);
    final commitHeader = tester.widget<Text>(find.text('COMMIT MESSAGE'));
    expect(commitHeader.style?.fontFamily, 'monospace');
    expect(commitHeader.style?.fontSize, 12);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('AUTHOR'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(48, 0),
    );
    await tester.pump();

    final afterSize = tester.getSize(find.byKey(const Key('graph-painter-0')));
    final after =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;

    // Two lanes auto-fit to 28 + 2 * 30, clamped up to the 96px minimum.
    expect(beforeSize.width, 96);
    expect(before.laneSpacing, 30);
    expect(afterSize.width, greaterThan(beforeSize.width));
    expect(after.laneSpacing, before.laneSpacing);
    expect(after.laneX(1) - after.laneX(0), beforeSpacing);
  });

  testWidgets('right to bottom preview animates through an intermediate size', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const Key('preview-panel')));
    await tester.tap(find.text('하단'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final intermediate = tester.getSize(find.byKey(const Key('preview-panel')));

    expect(intermediate.width, greaterThan(before.width));
    // Full width of the workspace beside the 150px sidebar.
    expect(intermediate.width, 650);
    expect(intermediate.height, lessThan(before.height));
    expect(intermediate.height, greaterThan(0));
    expect(intermediate.height, lessThan(280));
  });

  testWidgets('preview shows the commit message body', (tester) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('preview-body-sha', 'Subject line')],
      commitMessage: (_) async =>
          'Subject line\n\nBody line one\nBody line two\n',
      root: '/preview-message-test',
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('preview-panel'));
    expect(
      find.descendant(of: preview, matching: find.text('Subject line')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: preview,
        matching: find.text('Body line one\nBody line two'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a file click opens an adjacent diff without resizing the preview',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 700);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            files: (_, _) async => const [
              GitFileChange(
                path: 'lib/a.dart',
                status: 'M',
                additions: 1,
                deletions: 1,
              ),
            ],
            diff: (_, _, _, _, _) async => const [
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
              DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
            ],
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('preview-diff')), findsNothing);
      final previewWidth = tester
          .getSize(find.byKey(const Key('preview-panel')))
          .width;

      await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preview-diff')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('preview-panel'))).width,
        previewWidth,
      );
      expect(
        tester.getRect(find.byKey(const Key('preview-diff'))).right,
        tester.getRect(find.byKey(const Key('preview-panel'))).left,
      );

      await tester.tap(find.text('좌측'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('preview-panel'))).right,
        tester.getRect(find.byKey(const Key('preview-diff'))).left,
      );

      await tester.tap(find.text('하단'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('preview-diff'))).bottom,
        tester.getRect(find.byKey(const Key('preview-panel'))).top,
      );
    },
  );

  testWidgets('preview diff resizer shows blue line only on hover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 1,
              deletions: 1,
            ),
          ],
          diff: (_, _, _, _, _) async => const [
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
    await tester.pumpAndSettle();

    Color lineColor() => tester
        .widget<ColoredBox>(find.byKey(const Key('preview-diff-hover-line')))
        .color;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 690));
    expect(lineColor(), Colors.transparent);
    expect(
      tester.getRect(find.byKey(const Key('preview-diff-hover-line'))).left,
      tester.getRect(find.byKey(const Key('preview-diff'))).left,
    );

    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('preview-diff-resizer'))),
    );
    await tester.pump();
    expect(lineColor(), const Color(0xFF5AB0FF));

    await mouse.moveTo(const Offset(1190, 690));
    await tester.pump();
    expect(lineColor(), Colors.transparent);
  });

  testWidgets(
    'adjacent diff size defaults, persists, and reaches both endpoints',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 700);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final store = MemorySettingsStore();
      final repository = FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        files: (_, _) async => const [
          GitFileChange(
            path: 'lib/a.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
        ],
        diff: (_, _, _, _, _) async => const [
          DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
        ],
      );

      Future<void> mountAndOpen() async {
        await tester.pumpWidget(
          YogitApp(
            repository: repository,
            settingsStore: store,
            discoverAvatars: false,
            windowFrameController: controller,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
        await tester.pumpAndSettle();
      }

      await mountAndOpen();
      final previewWidth = tester
          .getSize(find.byKey(const Key('preview-panel')))
          .width;
      expect(
        tester.getSize(find.byKey(const Key('timeline-viewport'))).width,
        closeTo(100, 0.1),
      );

      final initialDiffWidth = tester
          .getSize(find.byKey(const Key('preview-diff')))
          .width;
      await tester.drag(
        find.byKey(const Key('preview-diff-resizer')),
        Offset(initialDiffWidth - 400, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('preview-diff'))).width,
        closeTo(400, 0.1),
      );
      expect(
        store.current.toJson()['previewDiffRightWidth'],
        closeTo(400, 0.1),
      );
      expect(
        tester.getSize(find.byKey(const Key('preview-panel'))).width,
        previewWidth,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await controller.setPreview(PreviewPlacement.closed);
      await mountAndOpen();
      expect(
        tester.getSize(find.byKey(const Key('preview-diff'))).width,
        closeTo(400, 0.1),
      );

      await tester.drag(
        find.byKey(const Key('preview-diff-resizer')),
        const Offset(-5000, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('timeline-viewport'))).width,
        closeTo(0, 0.1),
      );
      await tester.drag(
        find.byKey(const Key('preview-diff-resizer')),
        const Offset(5000, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('preview-diff'))).width,
        closeTo(0, 0.1),
      );
    },
  );

  testWidgets('escape closes the adjacent diff before the preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
          ],
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 1,
              deletions: 1,
            ),
          ],
          diff: (_, _, _, _, _) async => const [
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('timeline-viewport')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-diff')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-diff')), findsNothing);
    expect(find.byKey(const Key('preview-panel')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-diff-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-diff')), findsNothing);
    expect(find.byKey(const Key('preview-panel')), findsOneWidget);
  });

  testWidgets('preview loads real files before the first file diff once', (
    tester,
  ) async {
    var fileLoads = 0;
    var diffLoads = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'first commit')],
      files: (_, _) async {
        fileLoads++;
        return const [
          GitFileChange(
            path: 'lib/first.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
          GitFileChange(
            path: 'README.md',
            status: 'A',
            additions: 2,
            deletions: 0,
          ),
        ];
      },
      diff: (_, _, path, _, _) async {
        diffLoads++;
        return [
          const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          const DiffLine(
            kind: DiffLineKind.delete,
            text: 'old line',
            oldNumber: 1,
          ),
          DiffLine(kind: DiffLineKind.add, text: '$path changed', newNumber: 1),
        ];
      },
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('lib/first.dart'), findsOneWidget);
    expect(find.byKey(const Key('preview-diff')), findsNothing);
    expect(diffLoads, 0);

    await tester.tap(find.byKey(const Key('preview-state-lib/first.dart')));
    await tester.pumpAndSettle();
    expect(find.text('lib/first.dart'), findsNWidgets(2));
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('lib/first.dart changed'), findsOneWidget);
    expect(
      find.byKey(const Key('branch-preview-diff-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('branch-preview-layout-switch')),
      findsOneWidget,
    );
    expect(find.byType(UnifiedPresentationView), findsOneWidget);
    expect(find.text('+1 -1'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('preview-state-lib/first.dart')),
          )
          .decoration,
      isNull,
    );
    expect(
      tester.getRect(find.byKey(const Key('preview-diff'))).right,
      tester.getRect(find.byKey(const Key('preview-panel'))).left,
    );

    await tester.tap(
      find.byKey(const Key('branch-preview-layout-side-by-side')),
    );
    await tester.pump();
    expect(find.byType(SideBySidePresentationView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-diff')), findsNothing);
    await tester.tap(find.byKey(const Key('preview-state-lib/first.dart')));
    await tester.pumpAndSettle();
    expect(fileLoads, 1);
    expect(diffLoads, 1);
  });

  testWidgets('preview is a structural sibling and preserves timeline state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(100, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final initialTimelineSize = tester.getSize(
      find.byKey(const Key('timeline-viewport')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(360);
    await tester.pump();

    tester.view.physicalSize = const Size(1088, 600);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final rightLayout = find.byKey(const Key('preview-layout-right'));
    expect(rightLayout, findsOneWidget);
    expect(tester.widget(rightLayout), isA<Row>());
    expect(
      find.descendant(
        of: rightLayout,
        matching: find.byKey(const Key('timeline-viewport')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rightLayout,
        matching: find.byKey(const Key('preview-panel')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('preview-panel')),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('timeline-viewport'))),
      initialTimelineSize,
    );
    expect(scrollable.position.pixels, 360);

    await tester.tap(find.text('하단'));
    tester.view.physicalSize = const Size(800, 880);
    await tester.pumpAndSettle();

    final bottomLayout = find.byKey(const Key('preview-layout-bottom'));
    expect(bottomLayout, findsOneWidget);
    expect(tester.widget(bottomLayout), isA<Column>());
    expect(
      find.descendant(
        of: bottomLayout,
        matching: find.byKey(const Key('timeline-viewport')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomLayout,
        matching: find.byKey(const Key('preview-panel')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('timeline-viewport'))),
      initialTimelineSize,
    );
    expect(scrollable.position.pixels, 360);
  });

  test(
    'ref connector points at an ordinary commit with a one-pixel chevron',
    () {
      const size = Size(120, TimelineScreen.rowHeight);
      const color = Color(0xFF00E5FF);
      final row = layoutGraph([commit('tip', 'tip')]).single;
      final painter = CommitGraphPainter(
        row: row,
        selected: false,
        committerColor: color,
        refConnector: true,
      );
      const centerY = TimelineScreen.rowHeight / 2;
      const tip = Offset(13, centerY);

      expect(painter.refMarkerRadius, CommitGraphPainter.avatarRadius);
      expect(painter.refArrowTipX, tip.dx);
      expect(
        painter.refArrowheadPath(centerY).getBounds(),
        Rect.fromLTRB(6, centerY - 5, 13, centerY + 5),
      );
      expect(
        (Canvas canvas) => painter.paint(canvas, size),
        paints
          ..line(
            p1: const Offset(0, centerY),
            p2: tip,
            color: color,
            strokeWidth: 1.0,
          )
          ..path(color: color, strokeWidth: 1.0, style: PaintingStyle.stroke),
      );
    },
  );

  test('ref arrow keeps its gap for merge, working-tree, and compact rows', () {
    CommitGraphPainter painter(GraphRow row, {bool compact = false}) =>
        CommitGraphPainter(
          row: row,
          selected: false,
          committerColor: const Color(0xFF00E5FF),
          refConnector: true,
          compact: compact,
        );

    final merge = painter(
      graphRow(
        commit: commit('merge', 'merge', parents: const ['a', 'b']),
        lane: 0,
      ),
    );
    final workingTree = painter(
      graphRow(commit: workingTreeCommit('head'), lane: 0),
    );
    final compact = painter(
      graphRow(commit: commit('tip', 'tip'), lane: 3),
      compact: true,
    );

    expect(merge.refMarkerRadius, CommitGraphPainter.nodeRadius);
    expect(merge.refArrowTipX, 18.0);
    expect(workingTree.refMarkerRadius, CommitGraphPainter.wipNodeRadius);
    expect(workingTree.refArrowTipX, 16.0);
    expect(compact.laneX(compact.row.lane), CommitGraphPainter.laneInset);
    expect(compact.refMarkerRadius, CommitGraphPainter.avatarRadius);
    expect(compact.refArrowTipX, 13.0);
  });

  test('preview rail inherits the previous row dash above its node', () {
    final virtual = graphRow(
      commit: commit('virtual', 'virtual preview', parents: const ['base']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: 'virtual'},
      nextLaneShas: const {0: 'base'},
    );
    final base = graphRow(
      commit: commit('base', 'base tip'),
      lane: 0,
      activeLanes: const [0],
      activeLaneShas: const {0: 'base'},
    );
    final painter = CommitGraphPainter(
      row: base,
      previous: virtual,
      selected: false,
      committerColor: const Color(0xFF34C759),
      previousDashedLanes: const {0},
    );

    expect(painter.isDashedAbove(0), isTrue);
    expect(painter.isDashedAbove(1), isFalse);
  });

  test('the dashed merge edge points an arrowhead at the virtual commit', () {
    // The virtual merge sits in lane 0 and hands its second parent down lane 1,
    // which is the dashed line the preview draws.
    final virtual = graphRow(
      commit: commit('virtual', 'merge', parents: const ['base', 'compare']),
      lane: 0,
      parentLanes: const [0, 1],
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'virtual'},
      nextLaneShas: const {0: 'base', 1: 'compare'},
      transitions: const [(from: 0, to: 1, sha: 'compare')],
    );
    final painter = CommitGraphPainter(
      row: virtual,
      selected: false,
      committerColor: const Color(0xFF34C759),
      dashedLanes: const {1},
      previewRailColor: const Color(0xFFC69AFF),
      previewMergeArrow: true,
    );

    final head = painter.previewMergeArrowheadPath(18);
    expect(head, isNotNull);
    // The tip sits just right of the node and points back at it, so the line
    // reads as arriving rather than leaving.
    final bounds = head!.getBounds();
    expect(bounds.left, lessThan(bounds.right));
    expect(
      bounds.left,
      greaterThan(painter.laneX(0) + CommitGraphPainter.nodeRadius - 1),
    );
    expect(bounds.center.dy, closeTo(18, 0.01));

    // The head is stroked at the dashed rail's own weight, which is also the
    // ref connector arrow's, so every arrow in the graph is one size.
    expect(
      CommitGraphPainter.previewRailWidth,
      CommitGraphPainter.connectorWidth,
    );
    expect(
      painter.previewMergeArrowPaint().strokeWidth,
      CommitGraphPainter.previewRailWidth,
    );

    // Without the flag the same row draws no arrowhead.
    expect(
      CommitGraphPainter(
        row: virtual,
        selected: false,
        committerColor: const Color(0xFF34C759),
        dashedLanes: const {1},
        previewRailColor: const Color(0xFFC69AFF),
      ).previewMergeArrowheadPath(18),
      isNull,
    );
  });

  test('a virtual commit node draws its ring as dashes fitted to the circle', () {
    const fill = Color(0xFF8D6BB8);
    const ring = Color(0xFFB78BEF);
    const painter = DashedRingNodePainter(fill: fill, ring: ring, ringWidth: 3);
    const size = Size.square(CommitGraphPainter.avatarRadius * 2);
    // The ring is stroked just inside the disc (r = 11 - 1.5), and its dash
    // count is FITTED to that perimeter — whole dash+gap periods only, so the
    // pattern closes without a seam instead of clipping the last dash.
    final period = DashedRingNodePainter.dash + DashedRingNodePainter.gap;
    final perimeter = (Path()
          ..addOval(
            Rect.fromCircle(center: size.center(Offset.zero), radius: 9.5),
          ))
        .computeMetrics()
        .single
        .length;
    final fitted = (perimeter / period).round();
    PaintPattern dashes(int count) {
      final pattern = paints..circle(color: fill);
      for (var i = 0; i < count; i++) {
        pattern.path(color: ring, strokeWidth: 3);
      }
      return pattern;
    }

    void paint(Canvas canvas) => painter.paint(canvas, size);
    expect(fitted, greaterThan(1));
    expect(paint, dashes(fitted));
    expect(paint, isNot(dashes(fitted + 1)));
  });

  test(
    'compact preview keeps the virtual segment dashed above its real parent',
    () async {
      final virtual = graphRow(
        commit: commit('virtual', 'virtual', parents: const ['base']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: 'virtual'},
        nextLaneShas: const {0: 'base'},
      );
      final base = graphRow(
        commit: commit('base', 'base', parents: const ['root']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: 'base'},
        nextLaneShas: const {0: 'root'},
      );
      final painter = CommitGraphPainter(
        row: base,
        previous: virtual,
        selected: false,
        compact: true,
        committerColor: const Color(0xFF34C759),
        previousDashedLanes: const {0},
        previewRailColor: const Color(0xFFC69AFF),
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(56, 36));
      final image = await recorder.endRecording().toImage(56, 36);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      int alphaAt(int y) => bytes!.getUint8((y * 56 + 28) * 4 + 3);

      expect(alphaAt(1), greaterThan(0));
      expect(alphaAt(4), 0);
      expect(alphaAt(20), greaterThan(0));
    },
  );

  test('lane transitions turn on one 8px corner beside their node', () {
    GraphRow rowTo(int parentLane) => graphRow(
      commit: commit('1', 'first commit', parents: ['0']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: [parentLane],
      activeLaneShas: const {0: '1'},
      nextLaneShas: {parentLane: '0'},
      transitions: [(from: 0, to: parentLane, sha: '0')],
    );
    CommitGraphPainter painterTo(int parentLane) => CommitGraphPainter(
      row: rowTo(parentLane),
      selected: false,
      committerColor: const Color(0xFF7AD6E8),
    );

    const size = Size(168, 36);
    final painter = painterTo(1);
    expect(painter.laneX(0), 28);
    expect(painter.laneX(1), 58);
    expect(painter.laneX(2), 88);
    expect(CommitGraphPainter.railWidth, 2.0);
    expect(CommitGraphPainter.railOpacity, 1.0);
    // One corner radius for both kinds; the flat run carries the rest.
    expect(CommitGraphPainter.cornerRadius, 8);

    // Node center (y 18) down to the next row's center (y 54): one row height,
    // and no overshoot outside the two lanes.
    expect(painter.row.transitions, [(from: 0, to: 1, sha: '0')]);
    final path = painter.transitionPath(0, 1, 18, size, bendEarly: true);
    expect(path.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));

    final metrics = path.computeMetrics().single;
    ui.Tangent at(double fraction) =>
        metrics.getTangentForOffset(metrics.length * fraction)!;

    // A birth leaves its node sideways and enters its new column vertically.
    expect(at(0).vector.dy.abs(), lessThan(0.01));
    expect(at(0).vector.dx, greaterThan(0.99));
    expect(at(1).vector.dx.abs(), lessThan(0.01));
    expect(at(1).vector.dy, greaterThan(0.99));

    // A birth runs flat out of its source's side, corners, and is vertical in its
    // new column well before the arrival row.
    expect(_touches(path, const Offset(28, 18)), isTrue);
    expect(_touches(path, const Offset(50, 18)), isTrue);
    final samples = _samples(path);
    expect(
      samples.where((point) => point.dy > 26.5).map((point) => point.dx),
      everyElement(58),
    );
    expect(
      samples.where((point) => point.dy > 50).map((point) => point.dx),
      everyElement(58),
    );
    // Halfway along the sweep it is neither on its old level nor on the new lane.
    final middle = at(0.5).position;
    expect(middle.dx, greaterThan(28));
    expect(middle.dx, lessThan(58));
    expect(middle.dy, greaterThan(18));
    expect(middle.dy, lessThan(54));
    // The arc cuts the corner, so the path is shorter than the two straights.
    expect(metrics.length, lessThan(30 + 36));

    // A first parent that keeps the lane records no transition at all: it is a
    // straight vertical from the node to the row edge.
    final straight = CommitGraphPainter(
      row: graphRow(
        commit: commit('1', 'first commit', parents: ['0']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: '1'},
        nextLaneShas: const {0: '0'},
      ),
      selected: false,
      committerColor: const Color(0xFF7AD6E8),
    );
    expect(straight.row.transitions, isEmpty);
    expect(straight.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));

    // The arrival row paints the same path one row height higher, so the two
    // halves meet exactly on the shared row boundary.
    expect(
      painter
          .transitionPath(0, 1, 18 - size.height, size, bendEarly: true)
          .getBounds(),
      const Rect.fromLTRB(28, -18, 58, 18),
    );

    // A join mirrors it: down its own column, then one arc onto the parent's own
    // center, arriving horizontally at the dot.
    final join = painter.transitionPath(0, 1, 18, size);
    expect(join.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));
    final joinMetrics = join.computeMetrics().single;
    expect(joinMetrics.getTangentForOffset(0)!.vector.dy, greaterThan(0.99));
    expect(
      joinMetrics.getTangentForOffset(joinMetrics.length)!.vector.dx,
      greaterThan(0.99),
    );
    expect(joinMetrics.length, lessThan(30 + 36));
    final joinSamples = _samples(join);
    // It holds its lane until the corner, releases 8px along, then runs flat.
    expect(
      joinSamples.where((point) => point.dy < 45).map((point) => point.dx),
      everyElement(28),
    );
    expect(_touches(join, const Offset(36, 54)), isTrue);
    expect(
      joinSamples.where((point) => point.dx > 37).map((point) => point.dy),
      everyElement(54),
    );
    expect(_touches(join, const Offset(58, 50)), isFalse);
    expect(_touches(join, const Offset(58, 54)), isTrue);
    // No stub under the source node either: 8px down it is still on its lane.
    expect(_touches(join, const Offset(43, 26)), isFalse);

    // A distant lane cannot be spanned by one arc, so it keeps a flat run at the
    // node's own level.
    final distant = painterTo(
      2,
    ).transitionPath(0, 2, 18, size, bendEarly: true);
    expect(distant.getBounds(), const Rect.fromLTRB(28, 18, 88, 54));
    final distantRun = _samples(
      distant,
    ).where((point) => (point.dy - 18).abs() < 0.01).toList();
    expect(distantRun.first.dx, 28);
    // The run carries the lane gap the single arc cannot, handing over to it a
    // radius short of the new column.
    expect(_touches(distant, const Offset(58, 18)), isTrue);
    expect(distantRun.last.dx, greaterThanOrEqualTo(58));

    // Leftward transitions mirror, keeping the same radius.
    expect(
      painter.transitionPath(2, 0, 18, size, bendEarly: true).getBounds(),
      const Rect.fromLTRB(28, 18, 88, 54),
    );
  });

  test('a converging line holds its column, then slides in at its parent', () {
    const size = Size(168, 36);
    // Lane 1's line hands off to its first parent on lane 0: the row above the
    // parent records the convergence, and the dying branch's last node sits on
    // lane 1 right above it.
    final converging = graphRow(
      commit: commit('X', 'main commit', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'X', 1: 'P'},
      nextLaneShas: const {0: 'P'},
      parentLanes: const [0],
      transitions: const [(from: 1, to: 0, sha: 'P')],
      branch: 0,
      activeLaneBranches: const {0: 0, 1: 1},
      nextLaneBranches: const {0: 0},
    );
    final transition = converging.transitions.single;
    // Same discriminator as the color rule: this is not a birth.
    expect(CommitGraphPainter.isMergeEdge(converging, transition), isFalse);
    expect(CommitGraphPainter.transitionBranch(converging, transition), 1);

    final painter = CommitGraphPainter(
      row: converging,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    final path = painter.transitionPath(
      transition.from,
      transition.to,
      18,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(converging, transition),
    );

    // Through its own row the line stays in its column — no early horizontal.
    expect(
      _samples(path).where((point) => point.dy <= 24).map((point) => point.dx),
      everyElement(closeTo(painter.laneX(1), 0.01)),
    );
    // So no stub is left 8px under the dying branch's last node.
    expect(
      _touches(path, Offset((painter.laneX(0) + painter.laneX(1)) / 2, 18 + 8)),
      isFalse,
    );
    // One lane-wide arc onto the parent's own center, arriving horizontally at
    // the dot: no second corner, no trailing vertical on the parent's lane.
    expect(path.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));
    final metrics = path.computeMetrics().single;
    expect(metrics.getTangentForOffset(0)!.vector.dy, greaterThan(0.99));
    expect(
      metrics.getTangentForOffset(metrics.length)!.vector.dx,
      lessThan(-0.99),
    );
    expect(metrics.length, lessThan(30 + 36));
    expect(_touches(path, Offset(painter.laneX(0), 54)), isTrue);
    expect(_touches(path, Offset(painter.laneX(0) + 2, 54)), isTrue);
    // Nothing descends the parent's own lane into the dot.
    expect(_touches(path, Offset(painter.laneX(0), 50)), isFalse);

    // The arrival half shows that turn inside the parent's own row.
    final arrival = painter.transitionPath(
      transition.from,
      transition.to,
      18 - size.height,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(converging, transition),
    );
    expect(_touches(arrival, Offset(painter.laneX(0), 18)), isTrue);
    expect(_touches(arrival, Offset(painter.laneX(0) + 2, 18)), isTrue);
    // Side entry into the dot, parent's lane clear above it.
    expect(_touches(arrival, Offset(painter.laneX(0), 14)), isFalse);
  });

  test('a transition lane gets no straight rail overdrawing its curve', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // C is a merge: lane 0 keeps the first parent, lane 1 receives the second.
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      transitions: const [(from: 0, to: 1, sha: 'B')],
    );
    final child = CommitGraphPainter(
      row: merge,
      selected: false,
      committerColor: color,
    );
    // Lane 1 gets no vertical here: the curve reaches it in the row below.
    expect(child.laneVerticals(size).containsKey(1), isFalse);
    // C is the newest row, so its own lane only hands the first parent down.
    expect(child.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));

    final main = graphRow(
      commit: commit('A', 'main', parents: const ['R']),
      lane: 0,
      activeLanes: const [0, 1],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'A', 1: 'B'},
      nextLaneShas: const {0: 'R', 1: 'B'},
    );
    final arrival = CommitGraphPainter(
      row: main,
      previous: merge,
      selected: false,
      committerColor: color,
    );
    // Lane 1 was created by the merge, so its rail resumes at the row center,
    // below the arriving curve.
    expect(arrival.continuesFromAbove(1), isFalse);
    expect(arrival.laneVerticals(size)[1], (top: 18.0, bottom: 36.0));
    // Its own lane does come from above, and hands its parent down.
    expect(arrival.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));

    // B branches back into lane 0, which is already running: that lane keeps its
    // full vertical so the rail does not break where the curve joins it.
    final branch = graphRow(
      commit: commit('B', 'branch', parents: const ['R']),
      lane: 1,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'R', 1: 'B'},
      nextLaneShas: const {0: 'R'},
      transitions: const [(from: 1, to: 0, sha: 'R')],
    );
    final joining = CommitGraphPainter(
      row: branch,
      previous: main,
      selected: false,
      committerColor: color,
    );
    expect(joining.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    // Lane 1 runs down into the node and leaves on the curve.
    expect(joining.laneVerticals(size)[1], (top: 0.0, bottom: 18.0));

    final joined = CommitGraphPainter(
      row: graphRow(
        commit: commit('R', 'root'),
        lane: 0,
        activeLanes: const [0],
        activeLaneShas: const {0: 'R'},
      ),
      previous: branch,
      selected: false,
      committerColor: color,
    );
    expect(joined.continuesFromAbove(0), isTrue);
    expect(joined.laneVerticals(size)[0], (top: 0.0, bottom: 18.0));
  });

  test('a lane that starts at its row draws no rail above the node', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // B is a branch tip: lane 1 starts on its own row, nothing above it.
    final main = graphRow(
      commit: commit('A', 'main', parents: const ['R']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: 'A'},
      nextLaneShas: const {0: 'R'},
    );
    final tip = CommitGraphPainter(
      row: graphRow(
        commit: commit('B', 'branch tip', parents: const ['R']),
        lane: 1,
        activeLanes: const [0, 1],
        nextLanes: const [0],
        activeLaneShas: const {0: 'R', 1: 'B'},
        nextLaneShas: const {0: 'R'},
        transitions: const [(from: 1, to: 0, sha: 'R')],
      ),
      previous: main,
      selected: false,
      committerColor: color,
    );
    expect(tip.continuesFromAbove(1), isFalse);
    expect(tip.laneVerticals(size).containsKey(1), isFalse);

    // The working tree row leads the list, so it has no rail above it either,
    // but it does hand lane 0 to the commit underneath.
    final working = graphRow(
      commit: workingTreeCommit('1'),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: ''},
      nextLaneShas: const {0: '1'},
    );
    final wip = CommitGraphPainter(
      row: working,
      selected: false,
      committerColor: color,
    );
    expect(wip.continuesFromAbove(0), isFalse);
    expect(wip.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));
    final underWip = CommitGraphPainter(
      row: graphRow(
        commit: commit('1', 'head'),
        lane: 0,
        activeLanes: const [0],
        activeLaneShas: const {0: '1'},
      ),
      previous: working,
      selected: false,
      committerColor: color,
    );
    expect(underWip.continuesFromAbove(0), isTrue);
    expect(underWip.laneVerticals(size)[0], (top: 0.0, bottom: 18.0));
  });

  test('rails and curves take their branch line color', () {
    const size = Size(168, 36);
    const other = GitIdentity(name: 'Other', email: 'other@example.com');
    // Two branch ids whose colors are not this person's, so a per-committer
    // fallback anywhere would show up as a mismatch.
    final person = AvatarService.color(other);
    final ids = [
      for (var id = 0; id < AvatarService.defaultColors.length; id++)
        if (AvatarService.branchColor(id) != person) id,
    ];
    final (main, feature) = (ids.first, ids[1]);
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      transitions: [(from: 0, to: 1, sha: 'B')],
      branch: main,
      activeLaneBranches: {0: main},
      nextLaneBranches: {0: main, 1: feature},
    );
    final painter = CommitGraphPainter(
      row: merge,
      selected: false,
      committerColor: AvatarService.branchColor(merge.branch),
      committersBySha: const {'A': other, 'B': other},
    );

    // The rail, the merge curve and the merge dot all paint palette colors
    // picked by branch id, never a person's color.
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(color: AvatarService.branchColor(main))
        ..path(color: AvatarService.branchColor(feature))
        ..circle(color: AvatarService.branchColor(main)),
    );

    // A lane without a branch id keeps the old per-committer color.
    final legacy = CommitGraphPainter(
      row: graphRow(
        commit: commit('C', 'merge', parents: const ['A', 'B']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0, 1],
        activeLaneShas: const {0: 'C'},
        nextLaneShas: const {0: 'A', 1: 'B'},
        transitions: const [(from: 0, to: 1, sha: 'B')],
      ),
      selected: false,
      committerColor: person,
      committersBySha: const {'A': other, 'B': other},
    );
    expect(
      (Canvas canvas) => legacy.paint(canvas, size),
      paints
        ..line(color: AvatarService.color(other))
        ..path(color: AvatarService.color(other)),
    );
  });

  test('a sweep keeps the color of the line it belongs to', () {
    const size = Size(168, 36);
    // main = 0, alpha = 1, hotfix = 2, all with distinct palette colors.
    Color line(int branch) => AvatarService.branchColor(branch);
    CommitGraphPainter painter(GraphRow row, {GraphRow? previous}) =>
        CommitGraphPainter(
          row: row,
          previous: previous,
          selected: false,
          committerColor: line(row.branch),
        );

    // A foreign column converging on its first parent: main's commit sits on
    // lane 0 while hotfix's tail sweeps in from lane 2. The sweep is hotfix's.
    final converging = graphRow(
      commit: commit('M', 'main commit', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 2],
      nextLanes: const [0],
      activeLaneShas: const {0: 'M', 2: 'P'},
      nextLaneShas: const {0: 'P'},
      parentLanes: const [0],
      transitions: const [(from: 2, to: 0, sha: 'P')],
      branch: 0,
      activeLaneBranches: const {0: 0, 2: 2},
      nextLaneBranches: const {0: 0},
    );
    expect(
      CommitGraphPainter.transitionBranch(
        converging,
        converging.transitions.single,
      ),
      2,
    );
    expect(
      (Canvas canvas) => painter(converging).paint(canvas, size),
      paints..path(color: line(2)),
    );

    // A commit's own first-parent tail moving column: alpha's line, not the
    // destination's.
    final tail = graphRow(
      commit: commit('A', 'alpha commit', parents: const ['R']),
      lane: 1,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'R', 1: 'A'},
      nextLaneShas: const {0: 'R'},
      parentLanes: const [0],
      transitions: const [(from: 1, to: 0, sha: 'R')],
      branch: 1,
      activeLaneBranches: const {0: 0, 1: 1},
      nextLaneBranches: const {0: 0},
    );
    expect(
      CommitGraphPainter.transitionBranch(tail, tail.transitions.single),
      1,
    );
    expect(
      (Canvas canvas) => painter(tail).paint(canvas, size),
      paints..path(color: line(1)),
    );

    // A merge edge to a further parent keeps the destination line's color.
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      parentLanes: const [0, 1],
      transitions: const [(from: 0, to: 1, sha: 'B')],
      branch: 0,
      activeLaneBranches: const {0: 0},
      nextLaneBranches: const {0: 0, 1: 2},
    );
    expect(
      CommitGraphPainter.transitionBranch(merge, merge.transitions.single),
      2,
    );
    expect(
      (Canvas canvas) => painter(merge).paint(canvas, size),
      paints..path(color: line(2)),
    );

    // Arrival halves repeat their departure half's color, so a sweep is one
    // color across the row boundary.
    for (final departure in [converging, tail, merge]) {
      final arrival = graphRow(
        commit: commit('P', 'parent', parents: const ['R']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: 'P'},
        nextLaneShas: const {0: 'R'},
        parentLanes: const [0],
        branch: 0,
        activeLaneBranches: const {0: 0},
        nextLaneBranches: const {0: 0},
      );
      expect(
        (Canvas canvas) =>
            painter(arrival, previous: departure).paint(canvas, size),
        paints
          ..line()
          ..path(
            color: line(
              CommitGraphPainter.transitionBranch(
                departure,
                departure.transitions.single,
              )!,
            ),
          ),
      );
    }
  });

  test('a collapsing lane slides on a transition, not a straight rail', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // Lane 1 empties as C hands its first parent to lane 0, so git slides the
    // pass-through lane 2 one column left into it.
    final above = graphRow(
      commit: commit('H', 'head', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 1, 2],
      nextLanes: const [0, 1, 2],
      activeLaneShas: const {0: 'H', 1: 'C', 2: 'X'},
      nextLaneShas: const {0: 'P', 1: 'C', 2: 'X'},
    );
    final collapse = graphRow(
      commit: commit('C', 'joins main', parents: const ['P']),
      lane: 1,
      activeLanes: const [0, 1, 2],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'P', 1: 'C', 2: 'X'},
      nextLaneShas: const {0: 'P', 1: 'X'},
      transitions: const [
        (from: 1, to: 0, sha: 'P'),
        (from: 2, to: 1, sha: 'X'),
      ],
    );
    final painter = CommitGraphPainter(
      row: collapse,
      previous: above,
      selected: false,
      committerColor: color,
    );

    // The slide takes the same rounded path as a branch or merge edge.
    expect(
      painter.transitionPath(2, 1, 18, size).getBounds(),
      const Rect.fromLTRB(58, 18, 88, 54),
    );
    // Lane 2 runs down to the center and leaves on that curve.
    expect(painter.laneVerticals(size)[2], (top: 0.0, bottom: 18.0));
    // Lane 1 empties here, so nothing straight below the node either.
    expect(painter.laneVerticals(size)[1], (top: 0.0, bottom: 18.0));

    final below = CommitGraphPainter(
      row: graphRow(
        commit: commit('P', 'main', parents: const ['R']),
        lane: 0,
        activeLanes: const [0, 1],
        nextLanes: const [0, 1],
        activeLaneShas: const {0: 'P', 1: 'X'},
        nextLaneShas: const {0: 'R', 1: 'X'},
      ),
      previous: collapse,
      selected: false,
      committerColor: color,
    );
    // Lane 1's top half belongs to the arriving slide, not to a straight rail.
    expect(below.continuesFromAbove(1), isFalse);
    expect(below.laneVerticals(size)[1], (top: 18.0, bottom: 36.0));
    expect(below.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
  });

  test('the working tree ring takes its branch line color', () {
    const head = GitIdentity(name: 'Cam Committer', email: 'cam@example.com');
    final wip = graphRow(
      commit: workingTreeCommit('head'),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: ''},
      nextLaneShas: const {0: 'head'},
      branch: 3,
      activeLaneBranches: const {0: 3},
      nextLaneBranches: const {0: 3},
    );
    final painter = CommitGraphPainter(
      row: wip,
      selected: true,
      committerColor: AvatarService.branchColor(3),
      committersBySha: {'': head, 'head': head},
    );

    expect(painter.workingTreeRingColor, AvatarService.branchColor(3));
    expect(
      painter.workingTreeRingColor,
      isNot(TimelineThemePalette.systemGraphite.background),
    );
    // The fill hides the rail behind the node, so it follows the row color.
    expect(
      painter.nodeFillColor,
      TimelineThemePalette.systemGraphite.selectedRow,
    );
    expect(
      CommitGraphPainter(
        row: wip,
        selected: false,
        committerColor: AvatarService.branchColor(3),
      ).nodeFillColor,
      TimelineThemePalette.systemGraphite.background,
    );
    // Without branch ids it degrades to the old committer color.
    expect(
      CommitGraphPainter(
        row: graphRow(
          commit: workingTreeCommit('head'),
          lane: 0,
          activeLanes: const [0],
          nextLanes: const [0],
          nextLaneShas: const {0: 'head'},
        ),
        selected: false,
        committerColor: AvatarService.color(head),
        committersBySha: {'head': head},
      ).workingTreeRingColor,
      AvatarService.color(head),
    );
  });

  testWidgets('merge rows swap the avatar stack for a filled lane dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('merge', 'merge commit', parents: const ['main', 'feature']),
            commit('main', 'main commit', parents: const ['base']),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;

    expect(painterAt(0).showsMergeDot, isTrue);
    expect(painterAt(1).showsMergeDot, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('graph-cell-0')),
        matching: find.byType(CommitAvatarStack),
      ),
      findsNothing,
    );
    final stack = tester.widget<CommitAvatarStack>(
      find.descendant(
        of: find.byKey(const Key('graph-cell-1')),
        matching: find.byType(CommitAvatarStack),
      ),
    );
    expect(stack.size, 22);
    expect(stack.discColor, AvatarService.branchColor(painterAt(1).row.branch));
    // Every stack in a row — graph cell and name cell — wears its branch line.
    expect(
      tester
          .widgetList<CommitAvatarStack>(find.byType(CommitAvatarStack))
          .map((stack) => stack.discColor),
      everyElement(isNotNull),
    );
    expect(
      painterAt(0).committerColor,
      AvatarService.branchColor(painterAt(0).row.branch),
    );
  });

  testWidgets('the commit title column flexes until it is dragged', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Default is unset, so the title column takes whatever is left over.
    expect(const TimelineColumnWidths().commit, isNull);
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    // 1400 - 150 sidebar - 288 preview - (156 + 96 + 78 + 116 + 150) fixed.
    expect(titleWidth(), 366);
    expect(nameRight(), lessThanOrEqualTo(1400 - 288));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(titleWidth(), 654);
    expect(nameRight(), lessThanOrEqualTo(1400));

    // Every column stays visible at the default window size with the preview
    // open, which is the whole point of flexing.
    tester.view.physicalSize = const Size(1280, 760);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(titleWidth(), 246);
    expect(nameRight(), lessThanOrEqualTo(1280 - 288));

    // Dragging narrower pins the width: it is saved and stops following the
    // viewport. The drag starts from the width on screen (246).
    await tester.drag(
      find.byKey(const Key('commit-resizer')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    final pinned = titleWidth();
    expect(pinned, lessThan(246));
    expect(saved?.commit, pinned);

    // A narrow window compresses even a pinned title to the 100px minimum, and
    // widening restores it up to the pinned width — never past it.
    tester.view.physicalSize = const Size(800, 760);
    await tester.pumpAndSettle();
    expect(titleWidth(), 100);
    tester.view.physicalSize = const Size(1400, 760);
    await tester.pumpAndSettle();
    expect(titleWidth(), pinned);
  });

  testWidgets('the six columns fill the timeline viewport with no dead strip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1538, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    Widget screen(GitRepository repository) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(repository),
        repository: repository,
        controller: controller,
      ),
    );
    await tester.pumpWidget(
      screen(FakeGitRepository((_, _) async => [commit('1', 'first commit')])),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    Rect viewport() =>
        tester.getRect(find.byKey(const Key('timeline-viewport')));
    double columnWidth(String column) =>
        tester.getSize(find.byKey(Key('$column-header'))).width;

    // 1538 - 150 sidebar - 288 preview.
    expect(viewport().width, 1100);
    expect(columnWidth('graph'), 96);
    expect(columnWidth('commit'), 1100 - (156 + 96 + 78 + 116 + 150));
    expect(
      tester.getRect(find.byKey(const Key('name-header'))).right,
      viewport().right,
    );

    // A deeper graph widens its own column, and the title gives back exactly
    // that much — the right edge stays flush.
    await tester.pumpWidget(
      screen(
        FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(columnWidth('graph'), 102);
    expect(columnWidth('commit'), 1100 - (156 + 102 + 78 + 116 + 150));
    expect(
      tester.getRect(find.byKey(const Key('name-header'))).right,
      viewport().right,
    );
  });

  testWidgets('the graph column fits the deepest lane until it is dragged', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    // Keyed per repository so the second pump reloads instead of reusing state.
    Widget screen(GitRepository repository) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(repository),
        repository: repository,
        controller: controller,
        onColumnWidthsChanged: (value) => saved = value,
      ),
    );

    // One lane wants 28 + 30, so the 96px minimum wins.
    await tester.pumpWidget(
      screen(FakeGitRepository((_, _) async => [commit('1', 'first commit')])),
    );
    await tester.pumpAndSettle();
    expect(const TimelineColumnWidths().graph, isNull);
    expect(graphWidth(), 96);

    // Three lanes want 28 + 2 * 30 + 14 of content, which clears the minimum.
    await tester.pumpWidget(
      screen(
        FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), 102);

    // Dragging pins it, and the pinned width is what gets saved.
    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    final pinned = graphWidth();
    expect(pinned, greaterThan(102));
    expect(saved?.graph, pinned);
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.laneX(1) - painter.laneX(0), 30);
  });

  testWidgets('graph auto-fit leaves three pixels before the hash rail', (
    tester,
  ) async {
    const identity = GitIdentity(name: 'Ada Author', email: 'ada@example.com');
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'M',
                'octopus',
                parents: const ['a', 'b', 'c'],
                committer: identity,
              ),
              commit('a', 'a', parents: const ['P'], committer: identity),
              commit('b', 'b', parents: const ['P'], committer: identity),
              commit('c', 'c', parents: const ['P'], committer: identity),
              commit('P', 'parent', committer: identity),
            ],
          ),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = find.descendant(
      of: find.byKey(const Key('graph-cell-3')),
      matching: find.byType(CommitAvatarStack),
    );
    final hashRail = find.byKey(const Key('hash-rule-3'));

    expect(node, findsOneWidget);
    expect(hashRail, findsOneWidget);
    expect(tester.getRect(hashRail).left - tester.getRect(node).right, 3);
  });

  testWidgets('the title column absorbs the window shrink down to 100px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    Rect viewport() =>
        tester.getRect(find.byKey(const Key('timeline-viewport')));
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    // 1250 - 150 sidebar, preview closed.
    expect(timelineColumns['commit']!.min, 100);
    expect(viewport().width, 1100);
    expect(titleWidth(), 1100 - 596);
    expect(nameRight(), viewport().right);

    // The title takes the whole 350px shrink; the other five hold their widths.
    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();
    expect(viewport().width, 750);
    expect(titleWidth(), 750 - 596);
    expect(nameRight(), viewport().right);

    // Past the 100px floor the row overflows instead, so the right clips. (The
    // native window stops at 960 wide, so the toolbar never gets narrower.)
    tester.view.physicalSize = const Size(790, 800);
    await tester.pumpAndSettle();
    expect(titleWidth(), 100);
    expect(nameRight(), greaterThan(viewport().right));

    final title = tester.widget<Text>(find.text('first commit'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  test('graph lane spacing compresses in stages', () {
    // Lanes hold their coordinates while the cell still shows the last node,
    // which is all the width the content needs.
    expect(CommitGraphPainter.contentWidth(2), 102);
    expect(CommitGraphPainter.contentWidth(0), 42);
    expect(CommitGraphPainter.spacingFor(260, 2), 30);
    expect(CommitGraphPainter.spacingFor(118, 2), 30);
    expect(CommitGraphPainter.spacingFor(102, 2), 30);
    expect(CommitGraphPainter.spacingFor(58, 0), 30);
    // Below that the lanes squeeze so the last node stays just inside.
    expect(CommitGraphPainter.spacingFor(101, 2), 29.5);
    expect(CommitGraphPainter.spacingFor(100, 2), 29);
    expect(CommitGraphPainter.spacingFor(70, 2), 14);
    expect(CommitGraphPainter.spacingFor(40, 2), 12);
    expect(CommitGraphPainter.compactWidth, 56);
    expect(timelineColumns['graph']!.min, 40);
  });

  testWidgets('a narrow graph column compresses lanes, then collapses them', (
    tester,
  ) async {
    Widget screen(double graph) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(graph),
        repository: FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
        controller: controller,
        columnWidths: TimelineColumnWidths(graph: graph),
      ),
    );
    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;
    double avatarSize(int index) => tester
        .widget<CommitAvatarStack>(
          find.descendant(
            of: find.byKey(Key('graph-cell-$index')),
            matching: find.byType(CommitAvatarStack),
          ),
        )
        .size;

    // Stage 1: 118px is wider than the 102px content, so nothing moves.
    await tester.pumpWidget(screen(118));
    await tester.pumpAndSettle();
    expect(painterAt(0).compact, isFalse);
    expect(painterAt(0).laneSpacing, 30);
    expect(painterAt(1).laneX(1) - painterAt(1).laneX(0), 30);
    expect(avatarSize(1), 22);

    // Stage 2: the lanes squeeze together and the node avatar shrinks with them.
    await tester.pumpWidget(screen(70));
    await tester.pumpAndSettle();
    expect(painterAt(0).compact, isFalse);
    expect(painterAt(0).laneSpacing, 14);
    expect(painterAt(1).laneX(0), CommitGraphPainter.laneInset);
    expect(painterAt(1).laneX(1) - painterAt(1).laneX(0), 14);
    expect(
      painterAt(0).transitionPath(0, 2, 18, const Size(70, 36)).getBounds(),
      const Rect.fromLTRB(28, 18, 56, 54),
    );
    // Nodes keep their full size at every width; the overhang just clips.
    expect(avatarSize(1), 22);

    // Stage 3: every lane collapses onto the inset and the curves are dropped.
    await tester.pumpWidget(screen(56));
    await tester.pumpAndSettle();
    final compact = painterAt(0);
    expect(compact.compact, isTrue);
    expect(compact.laneX(2), CommitGraphPainter.laneInset);
    expect(compact.laneX(2), compact.laneX(0));
    expect(compact.row.transitions, isNotEmpty);
    // The octopus row hands rails down, so its single rail runs to the edge.
    expect(compact.compactRail(const Size(56, 36)), (top: 18.0, bottom: 36.0));
    // The last row ends the history, so its rail stops at the node.
    expect(painterAt(3).compactRail(const Size(56, 36)), (
      top: 0.0,
      bottom: 18.0,
    ));
    expect(avatarSize(1), 22);
  });

  testWidgets('column resizers move by 8px on arrow keys and clamp', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = tester
        .widget<Focus>(find.byKey(const Key('time-resizer-focus')))
        .focusNode!;
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(saved?.time, 124);
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 124);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(saved?.time, 132);
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 132);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(saved?.time, 124);
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 124);

    for (var press = 0; press < 13; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(saved?.time, 20);
    expect(saved?.name, 150);
  });

  testWidgets('Date and Author columns hide and restore their last widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(time: 80, name: 70),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(timelineColumns['time']!.min, 20);
    expect(timelineColumns['name']!.min, 20);
    expect(find.text('AUTHOR'), findsOneWidget);
    expect(find.text('Ada Author'), findsOneWidget);

    tester
        .widget<Focus>(find.byKey(const Key('time-resizer-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    for (var press = 0; press < 8; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('time-header')), findsNothing);
    expect(find.byKey(const Key('show-time-column')), findsOneWidget);
    expect(saved?.showTime, isFalse);
    expect(saved?.time, 20);

    await tester.tap(find.byKey(const Key('show-time-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 20);
    expect(saved?.showTime, isTrue);

    tester
        .widget<Focus>(find.byKey(const Key('name-resizer-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    for (var press = 0; press < 7; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(tester.getSize(find.byKey(const Key('name-header'))).width, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-header')), findsNothing);
    expect(find.text('Ada Author'), findsNothing);
    expect(find.byKey(const Key('show-name-column')), findsOneWidget);
    expect(saved?.showName, isFalse);
    expect(saved?.name, 20);

    await tester.tap(find.byKey(const Key('show-name-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('name-header'))).width, 20);
    expect(find.text('Ada Author'), findsOneWidget);
    expect(saved?.showName, isTrue);
  });

  testWidgets('Date and Author headers hide and restore their clicked widths', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(time: 80, name: 70),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('time-header')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('time-header')), findsNothing);
    expect(saved?.showTime, isFalse);
    expect(saved?.time, 80);

    await tester.tap(find.byKey(const Key('show-time-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 80);

    await tester.tap(find.byKey(const Key('name-header')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-header')), findsNothing);
    expect(saved?.showName, isFalse);
    expect(saved?.name, 70);

    await tester.tap(find.byKey(const Key('show-name-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('name-header'))).width, 70);
  });

  testWidgets('hideable headers brighten and show immediate restore hints', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    Color colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;
    Tooltip tooltipOf(String label) => tester.widget<Tooltip>(
      find.ancestor(of: find.text(label), matching: find.byType(Tooltip)),
    );
    final initialDateColor = colorOf('DATE');
    final initialAuthorColor = colorOf('AUTHOR');
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);

    await pointer.moveTo(tester.getCenter(find.text('DATE')));
    await tester.pump();
    expect(
      colorOf('DATE').computeLuminance(),
      greaterThan(initialDateColor.computeLuminance()),
    );
    expect(tooltipOf('DATE').message, "Hide Date. Click 'D' to restore");
    expect(tooltipOf('DATE').waitDuration, Duration.zero);
    expect(find.text("Hide Date. Click 'D' to restore"), findsOneWidget);

    await pointer.moveTo(tester.getCenter(find.text('AUTHOR')));
    await tester.pump();
    expect(colorOf('DATE'), initialDateColor);
    expect(
      colorOf('AUTHOR').computeLuminance(),
      greaterThan(initialAuthorColor.computeLuminance()),
    );
    expect(tooltipOf('AUTHOR').message, "Hide Author. Click 'A' to restore");
    expect(tooltipOf('AUTHOR').waitDuration, Duration.zero);
    expect(find.text("Hide Author. Click 'A' to restore"), findsOneWidget);
  });

  testWidgets('column drags restore Date and Author to drag-start widths', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(time: 80, name: 70),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> hideWithOneDrag(String column) async {
      final header = find.byKey(Key('$column-header'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(Key('$column-resizer'))),
      );
      for (var move = 0; move < 8 && header.evaluate().isNotEmpty; move++) {
        await gesture.moveBy(const Offset(-16, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(header, findsNothing);
    }

    await hideWithOneDrag('time');
    expect(saved?.time, 80);
    await tester.tap(find.byKey(const Key('show-time-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 80);

    await hideWithOneDrag('name');
    expect(saved?.name, 70);
    await tester.tap(find.byKey(const Key('show-name-column')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('name-header'))).width, 70);
  });

  testWidgets(
    'commit drag collapses Date then Author from their start widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      TimelineColumnWidths? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (_, _) async => [commit('1', 'first commit')],
            ),
            controller: controller,
            columnWidths: const TimelineColumnWidths(time: 80, name: 70),
            onColumnWidthsChanged: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      double width(String column) =>
          tester.getSize(find.byKey(Key('$column-header'))).width;
      expect(width('time'), 80);
      expect(width('name'), 70);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('commit-resizer'))),
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(width('time'), lessThan(80));
      expect(width('name'), 70);

      for (
        var move = 0;
        move < 12 && find.byKey(const Key('time-header')).evaluate().isNotEmpty;
        move++
      ) {
        await gesture.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      expect(find.byKey(const Key('time-header')), findsNothing);
      expect(width('name'), 70);
      expect(saved?.time, 80);

      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(width('name'), lessThan(70));

      for (
        var move = 0;
        move < 12 && find.byKey(const Key('name-header')).evaluate().isNotEmpty;
        move++
      ) {
        await gesture.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('name-header')), findsNothing);
      expect(saved?.name, 70);

      await tester.tap(find.byKey(const Key('show-time-column')));
      await tester.tap(find.byKey(const Key('show-name-column')));
      await tester.pumpAndSettle();
      expect(width('time'), 80);
      expect(width('name'), 70);
    },
  );

  testWidgets('sidebar search stays subdued until focus', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(local: ['main'], current: 'main'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final decoration = tester
        .widget<TextField>(find.byKey(const Key('ref-filter')))
        .decoration!;
    final palette = TimelineThemePalette.systemGraphite;

    expect(decoration.enabledBorder, isA<OutlineInputBorder>());
    expect(decoration.focusedBorder, isA<OutlineInputBorder>());
    expect(
      (decoration.enabledBorder as OutlineInputBorder).borderSide.color,
      palette.border,
    );
    expect(
      (decoration.focusedBorder as OutlineInputBorder).borderSide.color,
      palette.interactive,
    );
  });

  testWidgets('an outside branch change offers a refresh and reloads on yes', (
    tester,
  ) async {
    var signature = 'HEAD aaa\nrefs/heads/main aaa';
    var historyLoads = 0;
    final repository = FakeGitRepository(
      (_, _) async {
        historyLoads++;
        return [commit('1', 'first commit')];
      },
      refs: const RepoRefs(local: ['main'], current: 'main'),
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          arguments.first == 'for-each-ref'
          ? ProcessResult(1, 0, signature, '')
          : ProcessResult(1, 0, '', ''),
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    final loadsBefore = historyLoads;

    // Widget tests cannot raise real FSEvents, so these drive the safety-net
    // timer instead. Nothing changed yet, so it stays silent.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-change-refresh')), findsNothing);

    // Someone checks out another branch behind the app's back.
    signature = 'HEAD bbb\nrefs/heads/main aaa\nrefs/heads/work bbb';
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-change-refresh')), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-change-refresh')));
    await tester.pumpAndSettle();

    expect(historyLoads, greaterThan(loadsBefore));
  });

  testWidgets('declining the refresh stops the prompt from returning', (
    tester,
  ) async {
    var signature = 'HEAD aaa';
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'first commit')],
      refs: const RepoRefs(local: ['main'], current: 'main'),
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          arguments.first == 'for-each-ref'
          ? ProcessResult(1, 0, signature, '')
          : ProcessResult(1, 0, '', ''),
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    signature = 'HEAD bbb';
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local-change-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-change-refresh')), findsNothing);

    // The same state must not ask again.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-change-refresh')), findsNothing);

    // A further change is a new question, so it asks once more.
    signature = 'HEAD ccc';
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-change-refresh')), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-change-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets('the ref filter shows a magnifier instead of a hint sentence', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(local: ['main'], current: 'main'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final decoration = tester
        .widget<TextField>(find.byKey(const Key('ref-filter')))
        .decoration!;
    expect(decoration.hintText, isNull);
    expect(find.byKey(const Key('ref-filter-search-icon')), findsOneWidget);
    // The wording survives for anyone reading the field by name.
    expect(
      find.ancestor(
        of: find.byKey(const Key('ref-filter-search-icon')),
        matching: find.byTooltip('브랜치와 태그 찾기'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the ref filter matches loosely typed queries', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main', 'notes-split-pane', 'monaco-outline'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ref-filter')), 'notsp');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sidebar-ref-notes-split-pane')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sidebar-ref-monaco-outline')), findsNothing);
    expect(find.byKey(const Key('sidebar-ref-main')), findsNothing);
  });

  testWidgets('sidebar category headers use thin raised section bars', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(local: ['main'], current: 'main'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final band = tester.widget<Container>(
      find.byKey(const Key('sidebar-section-band-local')),
    );
    final decoration = band.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    final palette = TimelineThemePalette.systemGraphite;

    expect(decoration.color, palette.raised.withValues(alpha: 0.7));
    expect(border.top.color, palette.border.withValues(alpha: 0.7));
    expect(border.bottom, border.top);
  });

  testWidgets(
    'sidebar lists refs as collapsible trees, filters them, and moves the selection',
    (tester) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [
              commit('1', 'first commit'),
              commit(
                '2',
                'second commit',
                refs: const [GitRef(name: 'feature/login')],
              ),
            ],
            refs: const RepoRefs(
              local: ['main', 'feature/login', 'feature/payments/api'],
              remote: ['origin/main', 'origin/hotfix/urgent'],
              tags: ['release/v1.0.0'],
              current: 'main',
            ),
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      for (final (section, heading, count) in [
        ('local', 'LOCAL', '3'),
        ('remote', 'REMOTE', '2'),
        ('tags', 'TAGS', '1'),
      ]) {
        expect(find.text(heading), findsOneWidget);
        expect(find.byKey(Key('sidebar-section-$section')), findsOneWidget);
        expect(
          find.byKey(Key('sidebar-section-icon-$section')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(Key('sidebar-section-count-$section')),
            matching: find.text(count),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const Key('sidebar-folder-local-feature')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sidebar-folder-local-feature/payments')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sidebar-folder-remote-origin')),
        findsOneWidget,
      );
      final sectionIcon = tester.getRect(
        find.byKey(const Key('sidebar-section-icon-local')),
      );
      final folderChevron = tester.getRect(
        find.byKey(const Key('sidebar-folder-local-feature')),
      );
      expect(folderChevron.left, sectionIcon.left);

      final topLevelBranchName = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('sidebar-ref-main')),
          matching: find.text('main'),
        ),
      );
      final folderName = tester.getRect(find.text('feature'));
      final childBranchName = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('sidebar-ref-feature/login')),
          matching: find.text('login'),
        ),
      );
      expect(folderName.left - topLevelBranchName.left, 18);
      expect(childBranchName.left - folderName.left, 16);

      expect(
        find.byKey(const Key('sidebar-ref-feature/payments/api')),
        findsOneWidget,
      );
      expect(find.text('api'), findsOneWidget);
      // The checked-out branch leads LOCAL.
      expect(
        tester.getTopLeft(find.byKey(const Key('sidebar-ref-main'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('sidebar-ref-feature/login')))
              .dy,
        ),
      );

      final current = tester.widget<SizedBox>(
        find.byKey(const Key('sidebar-row-main')),
      );
      expect(current.height, isNotNull);
      expect(find.byKey(const Key('sidebar-head-main')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ref-filter')));
      expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
      var typed = '';
      for (final (key, character) in [
        (LogicalKeyboardKey.keyH, 'h'),
        (LogicalKeyboardKey.keyJ, 'j'),
        (LogicalKeyboardKey.keyK, 'k'),
        (LogicalKeyboardKey.keyL, 'l'),
      ]) {
        // Widget tests deliver hardware and platform text-editing messages
        // separately. The timeline must leave the hardware event unhandled before
        // the engine can insert its character into the focused editable.
        expect(await tester.sendKeyEvent(key), isFalse);
        typed += character;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ref-filter')))
            .controller!
            .text,
        'hjkl',
      );

      await tester.enterText(find.byKey(const Key('ref-filter')), '');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sidebar-folder-local-feature')));
      await tester.pump();
      expect(find.byKey(const Key('sidebar-ref-feature/login')), findsNothing);
      expect(
        find.byKey(const Key('sidebar-ref-feature/payments/api')),
        findsNothing,
      );

      await tester.enterText(find.byKey(const Key('ref-filter')), 'login');
      await tester.pump();
      expect(find.byKey(const Key('sidebar-ref-main')), findsNothing);
      expect(find.byKey(const Key('sidebar-ref-origin/main')), findsNothing);
      expect(
        find.byKey(const Key('sidebar-ref-feature/login')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const Key('sidebar-folder-local-feature')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        Icons.expand_more,
      );

      await tester.enterText(find.byKey(const Key('ref-filter')), '');
      await tester.pump();
      expect(find.byKey(const Key('sidebar-ref-feature/login')), findsNothing);

      await tester.tap(find.byKey(const Key('sidebar-folder-local-feature')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sidebar-section-remote')));
      await tester.pump();
      expect(find.byKey(const Key('sidebar-ref-origin/main')), findsNothing);
      await tester.tap(find.byKey(const Key('sidebar-section-remote')));
      await tester.pump();
      expect(find.byKey(const Key('sidebar-ref-origin/main')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sidebar-ref-feature/login')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    },
  );

  testWidgets('empty ref trees keep their section headers', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    for (final section in ['local', 'remote', 'tags']) {
      expect(find.byKey(Key('sidebar-section-$section')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(Key('sidebar-section-count-$section')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'selected local branch shows only its nonzero upstream behind count',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (_, _) async => [commit('1', 'first commit')],
              refs: const RepoRefs(
                local: ['main', 'release', 'local-only'],
                current: 'main',
                upstreams: {
                  'main': 'origin/main',
                  'release': 'company/release',
                },
                upstreamRemotes: {'main': 'origin', 'release': 'company'},
                aheadBehind: {
                  'main': BranchAheadBehind(ahead: 2, behind: 4),
                  'release': BranchAheadBehind(ahead: 0, behind: 3),
                },
              ),
            ),
            preferredBranch: 'release',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-menu-release')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sidebar-ahead-main')), findsNothing);
      expect(find.byKey(const Key('sidebar-behind-main')), findsNothing);
      final badge = find.byKey(const Key('sidebar-behind-release'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(of: badge, matching: find.byType(Tooltip)),
            )
            .message,
        '원격보다 3개 커밋 뒤처져 있습니다',
      );
      expect(find.byKey(const Key('sidebar-ahead-local-only')), findsNothing);
      expect(find.byKey(const Key('sidebar-behind-local-only')), findsNothing);
      expect(
        tester
            .widget<Text>(find.descendant(of: badge, matching: find.text('3')))
            .style
            ?.color,
        const Color(0xFFFF453A),
      );
      final label = find.descendant(
        of: find.byKey(const Key('sidebar-ref-release')),
        matching: find.text('release'),
      );
      expect(
        tester.getRect(badge).left - tester.getRect(label).right,
        lessThanOrEqualTo(4),
      );
    },
  );

  testWidgets(
    'remote branches show divergence from same-named local branches',
    (tester) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(
              local: ['main', 'release'],
              remote: ['origin/main', 'company/release', 'origin/remote-only'],
              current: 'main',
              remoteAheadBehind: {
                'origin/main': BranchAheadBehind(ahead: 2, behind: 1),
                'company/release': BranchAheadBehind(ahead: 0, behind: 0),
              },
            ),
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+2 −1', findRichText: true), findsOneWidget);
      expect(
        find.byKey(const Key('sidebar-remote-divergence-origin/main')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sidebar-remote-divergence-company/release')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('sidebar-remote-divergence-origin/remote-only')),
        findsNothing,
      );
    },
  );

  group('remote branch pull menu', () {
    const pullRefs = RepoRefs(
      local: ['main', 'lane', 'split'],
      remote: ['origin/lane', 'origin/new-lane', 'origin/split'],
      remoteNames: ['origin'],
      current: 'main',
      tips: {'main': '1', 'lane': '1', 'split': '1'},
      remoteAheadBehind: {
        'origin/lane': BranchAheadBehind(ahead: 3, behind: 0),
        'origin/split': BranchAheadBehind(ahead: 2, behind: 3),
      },
    );

    Future<TestGesture> hoverRow(WidgetTester tester, String name) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(
        tester.getCenter(find.byKey(Key('sidebar-ref-$name'))),
      );
      await tester.pump();
      return pointer;
    }

    testWidgets('the pull affordance appears on hover and lists actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository((_, _) async => [commit('1', 'c')], refs: pullRefs),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sidebar-pull-origin/lane')), findsNothing);
      await hoverRow(tester, 'origin/lane');
      expect(find.byKey(const Key('sidebar-pull-origin/lane')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sidebar-pull-origin/lane')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote-pull-header')), findsOneWidget);
      expect(find.text('로컬 lane보다 3개 앞'), findsOneWidget);
      expect(find.text('Pull — 3개 커밋'), findsOneWidget);
      expect(find.text('체크아웃 전환 없이 로컬만 전진'), findsOneWidget);
      expect(find.text('체크아웃'), findsOneWidget);
      expect(find.text('lane으로 전환 후 pull'), findsOneWidget);
      expect(find.text('브랜치 diff로 비교'), findsOneWidget);
    });

    testWidgets('pull fast-forwards without checkout and reports it', (
      tester,
    ) async {
      final calls = <List<String>>[];
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'c')],
            refs: pullRefs,
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  // The status bar chip and the local-change watcher both
                  // read on load; this test is about the pull commands.
                  if (!const {
                    'config',
                    'for-each-ref',
                    'rev-parse',
                  }.contains(arguments.first)) {
                    calls.add(arguments);
                  }
                  return ProcessResult(1, 0, '', '');
                },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      await hoverRow(tester, 'origin/lane');
      await tester.tap(find.byKey(const Key('sidebar-pull-origin/lane')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remote-pull-pull')));
      await tester.pumpAndSettle();

      expect(calls, [
        ['-c', 'credential.interactive=never', 'fetch', 'origin', 'lane:lane'],
      ]);
      expect(find.text('lane ← origin/lane · 3개 커밋'), findsOneWidget);
    });

    testWidgets('a diverged remote leads with compare and disables pull', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository((_, _) async => [commit('1', 'c')], refs: pullRefs),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      await hoverRow(tester, 'origin/split');
      await tester.tap(find.byKey(const Key('sidebar-pull-origin/split')));
      await tester.pumpAndSettle();

      expect(find.text('브랜치 diff로 비교'), findsOneWidget);
      expect(find.text('merge / rebase는 미리보기에서 결정'), findsOneWidget);
      expect(find.text('fast-forward 불가'), findsOneWidget);
      final pull = tester.widget<MenuItemButton>(
        find.byKey(const Key('remote-pull-pull')),
      );
      expect(pull.onPressed, isNull);
    });

    testWidgets(
      'a remote without a local branch checks out a tracking branch',
      (tester) async {
        final calls = <List<String>>[];
        await tester.pumpWidget(
          app(
            FakeGitRepository(
              (_, _) async => [commit('1', 'c')],
              refs: pullRefs,
              runner:
                  (
                    executable,
                    arguments, {
                    workingDirectory,
                    environment,
                  }) async {
                    // The status bar chip and the local-change watcher both
                    // read on load; this test is about the pull commands.
                    if (!const {
                      'config',
                      'for-each-ref',
                      'rev-parse',
                    }.contains(arguments.first)) {
                      calls.add(arguments);
                    }
                    return ProcessResult(1, 0, '', '');
                  },
            ),
            controller,
          ),
        );
        await tester.pumpAndSettle();

        await hoverRow(tester, 'origin/new-lane');
        await tester.tap(find.byKey(const Key('sidebar-pull-origin/new-lane')));
        await tester.pumpAndSettle();
        expect(find.text('추적 브랜치 new-lane 생성'), findsOneWidget);
        expect(find.byKey(const Key('remote-pull-pull')), findsNothing);

        await tester.tap(find.byKey(const Key('remote-pull-checkout')));
        await tester.pumpAndSettle();

        expect(calls, [
          ['switch', '-c', 'new-lane', '--track', 'origin/new-lane'],
        ]);
      },
    );

    testWidgets('double-clicking a fast-forward row asks before pulling', (
      tester,
    ) async {
      final calls = <List<String>>[];
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'c')],
            refs: pullRefs,
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  // The status bar chip and the local-change watcher both
                  // read on load; this test is about the pull commands.
                  if (!const {
                    'config',
                    'for-each-ref',
                    'rev-parse',
                  }.contains(arguments.first)) {
                    calls.add(arguments);
                  }
                  return ProcessResult(1, 0, '', '');
                },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('sidebar-ref-origin/lane'));
      await tester.tap(row);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(row);
      await tester.pumpAndSettle();

      // The state comes first; nothing has run yet.
      // One paragraph now, laid out one sentence per line.
      expect(find.textContaining('로컬 lane보다 3개 커밋 앞서 있습니다.'), findsOneWidget);
      expect(find.textContaining('fast-forward로 받아올 수 있습니다.'), findsOneWidget);
      expect(calls, isEmpty);

      // Cancelling leaves the repository untouched.
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      // Confirming pulls.
      await tester.tap(row);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remote-pull-confirm')));
      await tester.pumpAndSettle();

      expect(calls, [
        ['-c', 'credential.interactive=never', 'fetch', 'origin', 'lane:lane'],
      ]);
    });

    testWidgets('double-clicking any other state only opens the menu', (
      tester,
    ) async {
      final calls = <List<String>>[];
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'c')],
            refs: pullRefs,
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  // The status bar chip and the local-change watcher both
                  // read on load; this test is about the pull commands.
                  if (!const {
                    'config',
                    'for-each-ref',
                    'rev-parse',
                  }.contains(arguments.first)) {
                    calls.add(arguments);
                  }
                  return ProcessResult(1, 0, '', '');
                },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('sidebar-ref-origin/split'));
      await tester.tap(row);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote-pull-header')), findsOneWidget);
      expect(find.text('fast-forward 불가'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('the row shows a spinner while the pull runs', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'c')],
            refs: pullRefs,
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  await gate.future;
                  return ProcessResult(1, 0, '', '');
                },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      await hoverRow(tester, 'origin/lane');
      await tester.tap(find.byKey(const Key('sidebar-pull-origin/lane')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remote-pull-pull')));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('sidebar-pull-busy-origin/lane')),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sidebar-pull-busy-origin/lane')),
        findsNothing,
      );
    });

    testWidgets('a failed pull surfaces the git error', (tester) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'c')],
            refs: pullRefs,
            runner:
                (
                  executable,
                  arguments, {
                  workingDirectory,
                  environment,
                }) async =>
                    ProcessResult(1, 128, '', 'fatal: unable to access remote'),
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      await hoverRow(tester, 'origin/lane');
      await tester.tap(find.byKey(const Key('sidebar-pull-origin/lane')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remote-pull-pull')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('fatal: unable to access remote'),
        findsOneWidget,
      );

      // Let the notice expire so its timer does not outlive the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  testWidgets(
    'matching remotes refresh once every three minutes while active',
    (tester) async {
      final remotes = <String>[];
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(
              local: ['main', 'release'],
              remote: [
                'origin/main',
                'origin/release',
                'company/release',
                'company/remote-only',
                'foo/bar/main',
              ],
              remoteNames: ['origin', 'company', 'foo', 'foo/bar'],
              current: 'main',
            ),
            fetchRemoteCallback: (remote) async {
              remotes.add(remote);
              return FetchOriginResult.noOrigin;
            },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(remotes, ['company', 'foo/bar', 'origin']);

      await tester.pump(const Duration(minutes: 3));
      await tester.pump();
      expect(remotes, [
        'company',
        'foo/bar',
        'origin',
        'company',
        'foo/bar',
        'origin',
      ]);
    },
  );

  testWidgets(
    'selected upstream refresh runs every three minutes while active',
    (tester) async {
      final remotes = <String>[];
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              upstreams: {'main': 'company/main'},
              upstreamRemotes: {'main': 'company'},
            ),
            fetchRemoteCallback: (remote) async {
              remotes.add(remote);
              return FetchOriginResult.noOrigin;
            },
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();
      expect(remotes, ['company']);

      await tester.pump(const Duration(minutes: 2, seconds: 59));
      expect(remotes, ['company']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(remotes, ['company', 'company']);
    },
  );

  testWidgets('selected upstream refresh skips an overlapping request', (
    tester,
  ) async {
    final pending = Completer<FetchOriginResult>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main'],
            current: 'main',
            upstreams: {'main': 'origin/main'},
            upstreamRemotes: {'main': 'origin'},
          ),
          fetchRemoteCallback: (_) {
            calls++;
            return pending.future;
          },
        ),
        controller,
      ),
    );
    await tester.pump();
    expect(calls, 1);

    await tester.pump(const Duration(minutes: 10));
    expect(calls, 1);

    pending.complete(FetchOriginResult.noOrigin);
    await tester.pump();
  });

  testWidgets('selected upstream refresh pauses with the app', (tester) async {
    final remotes = <String>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main'],
            current: 'main',
            upstreams: {'main': 'origin/main'},
            upstreamRemotes: {'main': 'origin'},
          ),
          fetchRemoteCallback: (remote) async {
            remotes.add(remote);
            return FetchOriginResult.noOrigin;
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(remotes, ['origin']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();
    expect(remotes, ['origin']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();
    expect(remotes, ['origin', 'origin']);
  });

  testWidgets('changing the base branch refreshes its upstream remote', (
    tester,
  ) async {
    final remotes = <String>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main', 'release'],
            current: 'main',
            upstreams: {'main': 'origin/main', 'release': 'company/release'},
            upstreamRemotes: {'main': 'origin', 'release': 'company'},
          ),
          fetchRemoteCallback: (remote) async {
            remotes.add(remote);
            return FetchOriginResult.noOrigin;
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(remotes, ['origin']);

    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-branch-menu-release')));
    await tester.pumpAndSettle();
    expect(remotes, ['origin', 'company']);
  });

  testWidgets('remote refresh failure keeps the selected branch count', (
    tester,
  ) async {
    var fetches = 0;
    var refLoads = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'first commit')],
      refsLoader: () async {
        refLoads++;
        return RepoRefs(
          local: const ['main'],
          remote: const ['origin/main'],
          current: 'main',
          upstreams: const {'main': 'origin/main'},
          upstreamRemotes: const {'main': 'origin'},
          aheadBehind: {'main': BranchAheadBehind(ahead: 0, behind: refLoads)},
        );
      },
      fetchRemoteCallback: (_) async {
        fetches++;
        if (fetches == 1) throw StateError('offline');
        return FetchOriginResult.updated;
      },
    );

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    expect(find.text('원격 갱신 실패'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-behind-main')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('retry-origin-fetch')));
    await tester.pumpAndSettle();

    expect(fetches, 2);
    expect(find.text('원격 갱신 실패'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-behind-main')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unchanged remote refresh does not reload refs', (tester) async {
    var fetches = 0;
    var refLoads = 0;
    const refs = RepoRefs(
      local: ['main'],
      remote: ['origin/main'],
      remoteNames: ['origin'],
      current: 'main',
      tips: {'main': 'main-tip', 'origin/main': 'remote-tip'},
      localTips: {'main': 'main-tip'},
      upstreams: {'main': 'origin/main'},
      upstreamRemotes: {'main': 'origin'},
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refsLoader: () async {
            refLoads++;
            return refs;
          },
          fetchRemoteCallback: (_) async {
            fetches++;
            return FetchOriginResult.unchanged;
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(refLoads, 1);
    expect(fetches, 1);

    await tester.pump(const Duration(minutes: 3));
    await tester.pump();

    expect(refLoads, 1);
    expect(fetches, 2);
  });

  testWidgets('unchanged comparison tips do not recompute branch preview', (
    tester,
  ) async {
    var remoteChanged = false;
    var compareCalls = 0;
    const refs = RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/main'],
      remoteNames: ['origin'],
      current: 'main',
      tips: {
        'main': 'main-tip',
        'feature': 'feature-tip',
        'origin/main': 'remote-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'feature-tip'},
      upstreams: {'main': 'origin/main'},
      upstreamRemotes: {'main': 'origin'},
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refsLoader: () async => refs,
          fetchRemoteCallback: (_) async => remoteChanged
              ? FetchOriginResult.updated
              : FetchOriginResult.unchanged,
          compareBranchesCallback: (_, _) async {
            compareCalls++;
            return branchComparison();
          },
          simulateRebaseCallback:
              ({required baseRef, required compareRef}) async =>
                  const RebaseCheckResult(status: RebaseCheckStatus.clean),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    expect(compareCalls, 1);
    expect(find.text('feature only'), findsOneWidget);

    remoteChanged = true;
    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();

    expect(compareCalls, 1);
    expect(find.text('feature only'), findsOneWidget);
  });

  testWidgets('changed comparison tips replace branch preview atomically', (
    tester,
  ) async {
    var remoteChanged = false;
    var refs = const RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/main'],
      remoteNames: ['origin'],
      current: 'main',
      tips: {
        'main': 'main-tip',
        'feature': 'feature-tip',
        'origin/main': 'remote-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'feature-tip'},
      upstreams: {'main': 'origin/main'},
      upstreamRemotes: {'main': 'origin'},
    );
    final replacement = Completer<BranchComparisonResult>();
    var compareCalls = 0;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refsLoader: () async => refs,
          fetchRemoteCallback: (_) async => remoteChanged
              ? FetchOriginResult.updated
              : FetchOriginResult.unchanged,
          compareBranchesCallback: (_, _) {
            compareCalls++;
            if (compareCalls == 1) {
              return Future.value(
                branchComparison(compareSubject: 'old feature'),
              );
            }
            return replacement.future;
          },
          simulateRebaseCallback:
              ({required baseRef, required compareRef}) async =>
                  const RebaseCheckResult(status: RebaseCheckStatus.clean),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    expect(find.text('old feature'), findsOneWidget);

    refs = const RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/main'],
      remoteNames: ['origin'],
      current: 'main',
      tips: {
        'main': 'main-tip',
        'feature': 'feature-next',
        'origin/main': 'remote-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'feature-next'},
      upstreams: {'main': 'origin/main'},
      upstreamRemotes: {'main': 'origin'},
    );
    remoteChanged = true;
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();

    expect(compareCalls, 2);
    expect(find.text('old feature'), findsOneWidget);
    expect(find.text('normal history'), findsNothing);

    replacement.complete(
      branchComparison(
        compareTip: 'feature-next',
        compareSubject: 'new feature',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('new feature'), findsOneWidget);
    expect(find.text('old feature'), findsNothing);
  });

  testWidgets('remote ref reload keeps a selected tag comparison', (
    tester,
  ) async {
    var fetches = 0;
    const refs = RepoRefs(
      local: ['main'],
      remote: ['origin/main'],
      tags: ['v1.0.0'],
      current: 'main',
      upstreams: {'main': 'origin/main'},
      upstreamRemotes: {'main': 'origin'},
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: refs,
          refsLoader: () async => refs,
          fetchRemoteCallback: (_) async {
            fetches++;
            if (fetches == 1) throw StateError('offline');
            return FetchOriginResult.updated;
          },
          compareBranchesCallback: (_, compare) async =>
              branchComparison(compareRef: compare),
          simulateRebaseCallback:
              ({required baseRef, required compareRef}) async =>
                  const RebaseCheckResult(status: RebaseCheckStatus.clean),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-v1.0.0')));
    await tester.pumpAndSettle();
    expect(find.text('v1.0.0'), findsWidgets);

    await tester.tap(find.byKey(const Key('retry-origin-fetch')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('branch-diff-selector')),
        matching: find.text('v1.0.0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('branch comparison keeps only two branch lanes', (tester) async {
    final result = branchComparison();
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            remote: ['origin/main'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => result,
          simulateRebaseCallback: ({required baseRef, required compareRef}) =>
              Future.value(
                const RebaseCheckResult(status: RebaseCheckStatus.clean),
              ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    expect(find.text('normal history'), findsNothing);
    expect(find.text('main only'), findsOneWidget);
    expect(find.text('feature only'), findsOneWidget);
    expect(find.text('shared commit'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('virtual-preview-chip')),
        matching: find.text('main · 가상'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ref-chip-main-tip-main')), findsOneWidget);
    expect(
      find.byKey(const Key('ref-chip-feature-tip-feature · 원본')),
      findsOneWidget,
    );
    expect(find.text('공통'), findsOneWidget);
    expect(find.text('가상 커밋 1'), findsOneWidget);
    expect(find.text('두 부모'), findsNothing);
    expect(find.text('충돌 없음'), findsOneWidget);
    expect(find.text('commit'), findsOneWidget);
    expect(find.byKey(const Key('status-timestamp')), findsOneWidget);
    expect(find.byKey(const Key('comparison-status')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('branch-preview-summary')),
        matching: find.text('Merge 미리보기'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('branch-preview-success-icon')),
      findsOneWidget,
    );
    final painters = tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is CommitGraphPainter,
          ),
        )
        .map((paint) => paint.painter! as CommitGraphPainter);
    expect(
      painters.map((painter) => painter.row.maxLane),
      everyElement(lessThanOrEqualTo(1)),
    );
    expect(
      painters.map((painter) => painter.refConnector),
      everyElement(isFalse),
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('ref-chip-connector-');
      }),
      findsNothing,
    );
    expect(
      painters
          .singleWhere((painter) => painter.row.commit.sha == 'root')
          .committerColor,
      TimelineThemePalette.systemGraphite.muted,
    );
  });

  testWidgets('merge preview spacing ignores deeper normal history lanes', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [
        commit(
          'octopus',
          'deep normal history',
          parents: const ['a', 'b', 'c', 'd', 'e', 'f'],
        ),
        for (final sha in const ['a', 'b', 'c', 'd', 'e', 'f'])
          commit(sha, sha),
      ],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'octopus', 'feature': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => branchComparison(),
      simulateRebaseCallback: ({required baseRef, required compareRef}) =>
          Future.value(
            const RebaseCheckResult(status: RebaseCheckStatus.clean),
          ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: controller,
          columnWidths: const TimelineColumnWidths(graph: 96),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterFor(String sha) => tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is CommitGraphPainter,
          ),
        )
        .map((paint) => paint.painter! as CommitGraphPainter)
        .firstWhere((painter) => painter.row.commit.sha == sha);

    final normalPainter = painterFor('octopus');
    expect(normalPainter.laneSpacing, CommitGraphPainter.minLaneSpacing);

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    final previewPainter = tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is CommitGraphPainter,
          ),
        )
        .map((paint) => paint.painter! as CommitGraphPainter)
        .firstWhere((painter) => painter.row.commit.shortSha == 'VM');
    expect(previewPainter.laneX(1) - previewPainter.laneX(0), 49);
    // The dashed second-parent edge ends in an arrowhead at the virtual commit.
    expect(previewPainter.previewMergeArrow, isTrue);
    expect(previewPainter.previewMergeArrowheadPath(15), isNotNull);
  });

  testWidgets('choosing a comparison opens the preview pane by itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => branchComparison(),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    // The pane starts closed; nothing has asked for it yet.
    expect(controller.previewPlacement, PreviewPlacement.closed);

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    // A merge preview is worth seeing the moment it exists.
    expect(controller.previewPlacement, PreviewPlacement.right);

    // Switching to rebase keeps it open rather than reopening it elsewhere.
    await tester.tap(find.byKey(const Key('branch-preview-rebase-button')));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.right);
  });

  testWidgets('virtual merge row hides borrowed date and author', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => branchComparison(),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('virtual-preview-row'));
    expect(
      find.descendant(of: row, matching: find.text('Ada Author')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text('—')),
      findsNWidgets(2),
    );
  });

  testWidgets('branch comparison failure is shown in the preview summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async =>
              throw StateError('compare failed'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('branch-preview-summary')),
        matching: find.text('브랜치 비교 실패'),
      ),
      findsOneWidget,
    );
    expect(find.text('Merge 검사 중'), findsNothing);
  });

  testWidgets('branch preview controls switch the summary above the timeline', (
    tester,
  ) async {
    BranchPreviewMode? changedMode;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => branchComparison(),
          simulateRebaseCallback: ({required baseRef, required compareRef}) =>
              Future.value(
                const RebaseCheckResult(status: RebaseCheckStatus.clean),
              ),
        ),
        controller,
        onBranchPreviewModeChanged: (mode) => changedMode = mode,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial timeline');
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'branch selector');
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'merge preview');

    expect(find.byKey(const Key('branch-preview-segmented')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('branch-preview-segmented'))),
      const Size(200, 38),
    );
    final segmented = tester.widget<Container>(
      find.byKey(const Key('branch-preview-segmented')),
    );
    expect(segmented.padding, const EdgeInsets.all(3));
    expect(
      (segmented.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(8),
    );
    final mergeButton = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('branch-preview-merge-button')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (mergeButton.decoration! as BoxDecoration).color,
      const Color(0xFF4388EE),
    );
    expect(
      (mergeButton.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );
    expect(find.byKey(const Key('branch-preview-merge')), findsOneWidget);
    expect(find.byKey(const Key('branch-preview-rebase')), findsOneWidget);
    expect(find.text('Merge 미리보기'), findsWidgets);
    expect(find.text('Merge 성공'), findsNothing);
    expect(find.byKey(const Key('virtual-merge-node')), findsOneWidget);
    // 아직 없는 커밋이니 링이 점선이다. 실제 커밋 노드는 아바타 그대로라 점선 링
    // 페인터를 쓰는 노드는 이 가상 커밋 하나뿐이다.
    expect(
      tester
          .widget<CustomPaint>(find.byKey(const Key('virtual-merge-node')))
          .painter,
      isA<DashedRingNodePainter>(),
    );
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((paint) => paint.painter is DashedRingNodePainter),
      hasLength(1),
    );
    expect(find.byKey(const Key('virtual-preview-row')), findsOneWidget);
    expect(find.byKey(const Key('virtual-preview-chip')), findsOneWidget);
    expect(find.text('가상'), findsOneWidget);
    await tester.tap(find.byKey(const Key('virtual-preview-row')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('virtual-preview-row')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'selection-band-',
              ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('branch-preview-success-icon')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('branch-preview-summary'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('graph-header'))).dy),
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('branch-preview-summary')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    final summaryRect = tester.getRect(
      find.byKey(const Key('branch-preview-summary')),
    );
    final timelineRect = tester.getRect(
      find.byKey(const Key('timeline-viewport')),
    );
    expect(summaryRect.left, timelineRect.left);
    expect(summaryRect.right, timelineRect.right);

    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'rebase preview');
    expect(changedMode, BranchPreviewMode.rebase);
    final rebaseButton = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('branch-preview-rebase-button')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (rebaseButton.decoration! as BoxDecoration).color,
      const Color(0xFF4388EE),
    );
    expect(find.text('Rebase 미리보기'), findsWidgets);
    expect(find.text('Rebase 성공'), findsNothing);
  });

  testWidgets('branch preview summary describes the selected operation', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => branchComparison(),
          simulateRebaseCallback: ({required baseRef, required compareRef}) =>
              Future.value(
                const RebaseCheckResult(status: RebaseCheckStatus.clean),
              ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    void expectSuccess() {
      expect(
        tester
            .widget<Icon>(find.byKey(const Key('branch-preview-success-icon')))
            .color,
        const Color(0xFF34C759),
      );
    }

    expectSuccess();
    expect(find.text('가상 커밋 1'), findsOneWidget);
    expect(find.text('두 부모'), findsNothing);
    expect(find.text('충돌 없음'), findsOneWidget);
    expect(find.text('main ← feature'), findsOneWidget);

    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pumpAndSettle();
    expectSuccess();
    expect(find.text('점선 이동 경로'), findsOneWidget);
    expect(find.text('실제 브랜치 변경 없음'), findsOneWidget);
    expect(find.text('feature → main'), findsOneWidget);
  });

  testWidgets('comparison preview follows the focused real commit', (
    tester,
  ) async {
    final rangeCalls = <({String from, String to, String path})>[];
    final commitCalls = <({String sha, String path})>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => branchComparison(),
          simulateRebaseCallback: ({required baseRef, required compareRef}) =>
              Future.value(
                const RebaseCheckResult(status: RebaseCheckStatus.clean),
              ),
          files: (commit, _) async => [
            GitFileChange(
              path: '${commit.sha}.dart',
              status: 'M',
              additions: 1,
              deletions: 0,
            ),
          ],
          diff: (commit, _, path, _, _) async {
            commitCalls.add((sha: commit.sha, path: path));
            return const [
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(kind: DiffLineKind.add, text: 'focused', newNumber: 1),
            ];
          },
          diffBetween: (from, to, file) async {
            rangeCalls.add((from: from, to: to, path: file.path));
            return const [
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
            ];
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(find.text('lib/shared.dart'), findsWidgets);
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    expect(rangeCalls, [
      (from: 'main-tip', to: 'feature-tip', path: 'lib/shared.dart'),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('선택한 커밋의 diff'), findsOneWidget);
    expect(find.text('main-tip.dart'), findsWidgets);
    expect(commitCalls, [(sha: 'main-tip', path: 'main-tip.dart')]);
    expect(rangeCalls, hasLength(1));
  });

  testWidgets('branch preview diff switches between both full diff layouts', (
    tester,
  ) async {
    final comparison = BranchComparisonResult(
      baseRef: 'main',
      compareRef: 'feature',
      baseTip: 'main-tip',
      compareTip: 'feature-tip',
      baseParent: 'root',
      compareParent: 'root',
      mergeBases: const ['root'],
      commits: branchComparison().commits,
      files: const [],
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
        resultFiles: [
          GitFileChange(
            path: 'feature.txt',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
          GitFileChange(
            path: 'other.txt',
            status: 'A',
            additions: 1,
            deletions: 0,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          diffBetween: (_, _, _) async => const [
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
            DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(find.byKey(const Key('branch-preview-file-list')), findsOneWidget);
    expect(find.text('브랜치 Diff'), findsNothing);
    expect(find.byKey(const Key('preview-shortcut-hint')), findsNothing);
    expect(find.byKey(const Key('preview-full-diff')), findsNothing);
    expect(find.text('가상 병합 커밋'), findsOneWidget);
    expect(find.text('feature.txt'), findsWidgets);
    await tester.tap(find.byKey(const Key('preview-state-feature.txt')));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedPresentationView), findsOneWidget);
    final fileList = find.byKey(const Key('branch-preview-file-list'));
    expect(
      find.descendant(of: fileList, matching: find.text('+1 -1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fileList, matching: find.text('+1')),
      findsOneWidget,
    );
    final selectedFileText = find.descendant(
      of: fileList,
      matching: find.text('feature.txt'),
    );
    expect(tester.widget<Text>(selectedFileText).style?.fontFamily, isNull);
    final selectedFileBox = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: selectedFileText,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  (widget.decoration as BoxDecoration).color != null,
            ),
          )
          .first,
    );
    expect(
      (selectedFileBox.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('branch-preview-layout-unified')))
          .height,
      22,
    );
    final layoutSwitch = find.byKey(const Key('branch-preview-layout-switch'));
    expect(layoutSwitch, findsOneWidget);
    final switchBox = tester.widget<Container>(layoutSwitch);
    expect(switchBox.padding, const EdgeInsets.all(2));
    expect(
      (switchBox.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );
    final unifiedButton = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('branch-preview-layout-unified')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (unifiedButton.decoration! as BoxDecoration).color,
      TimelineThemePalette.systemGraphite.neutralChip,
    );
    expect(
      (unifiedButton.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(4),
    );

    await tester.tap(
      find.byKey(const Key('branch-preview-layout-side-by-side')),
    );
    await tester.pump();
    expect(find.byType(SideBySidePresentationView), findsOneWidget);
    final sideBySideButton = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('branch-preview-layout-side-by-side')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (sideBySideButton.decoration! as BoxDecoration).color,
      TimelineThemePalette.systemGraphite.neutralChip,
    );

    await tester.ensureVisible(find.text('other.txt').last);
    await tester.tap(find.text('other.txt').last);
    await tester.pump();
    expect(find.byType(SideBySidePresentationView), findsOneWidget);
  });

  testWidgets('branch preview diff names both sides of a merge conflict', (
    tester,
  ) async {
    final comparison = branchComparison(
      baseSubject: 'main change',
      compareSubject: 'feature change',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.conflicts,
        files: ['lib/shared.dart'],
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          diffBetween: (_, _, _) async => const [
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    expect(find.text('Merge 충돌'), findsOneWidget);
    expect(find.text('Merge 충돌 해결'), findsOneWidget);
    expect(find.text('임시 공간에서 해결 중'), findsOneWidget);
    expect(find.text('자동 준비됨'), findsOneWidget);
    expect(find.text('임시 공간 사용 중'), findsOneWidget);
    expect(find.text('가상 Merge 커밋을 만들 수 없습니다'), findsOneWidget);
    expect(find.text('충돌 파일 1개'), findsOneWidget);
    expect(
      find.byKey(const Key('virtual-merge-conflict-node')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.text('! 병합 충돌'),
      ),
      findsOneWidget,
    );
    expect(find.text('중단'), findsOneWidget);
    expect(find.text('충돌'), findsWidgets);
    expect(find.text('lib/shared.dart'), findsWidgets);
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    expect(
      find.text('main · main change ← feature · feature change'),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'^[0-9a-f]{7} 사용$')), findsNothing);
  });

  testWidgets('temporary preview resolves merge conflicts and can be dropped', (
    tester,
  ) async {
    final apply = Completer<BranchApplyResult>();
    final comparison = branchComparison(
      compareRef: 'fix/docs',
      baseSubject: 'main change',
      compareSubject: 'docs change',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.conflicts,
        files: ['lib/shared.dart'],
      ),
    );
    late FakeGitRepository repository;
    late FakeMergePreviewSession session;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'fix/docs'],
        current: 'main',
        tips: {'main': 'main-tip', 'fix/docs': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openMergePreviewCallback:
          ({required baseRef, required compareRef}) async => session,
      applyMergePreviewCallback: ({required comparison, required treeSha}) =>
          apply.future,
      filesBetween: (_, _) async => const [
        GitFileChange(
          path: 'lib/shared.dart',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diffBetween: (_, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
        DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
      ],
    );
    session = FakeMergePreviewSession(
      repository,
      const MergePreviewResult(
        status: MergePreviewStatus.conflict,
        baseTip: 'main-tip',
        compareTip: 'feature-tip',
        conflictFiles: ['lib/shared.dart'],
      ),
      finishResult: const MergePreviewResult(
        status: MergePreviewStatus.clean,
        baseTip: 'main-tip',
        compareTip: 'feature-tip',
        treeSha: 'resolved-tree',
        resultFiles: [
          GitFileChange(
            path: 'lib/shared.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
        ],
      ),
      conflictDiff: const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'main side', oldNumber: 1),
        DiffLine(kind: DiffLineKind.add, text: 'docs side', newNumber: 1),
      ],
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-fix/docs')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '충돌 해결 과정은 임시 공간에서만 진행합니다. '
        '기준 브랜치 main과 대상 브랜치 fix/docs를 직접 변경하지 않습니다.',
      ),
      findsOneWidget,
    );
    expect(find.text('두 브랜치 변경 없음'), findsOneWidget);
    expect(find.text('현재 작업 트리 변경 없음'), findsOneWidget);
    expect(find.text('종료 시 자동 삭제'), findsOneWidget);
    expect(find.text('임시 작업 공간 시작'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('preview-state-lib/shared.dart')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('preview-content-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    expect(find.text('main side'), findsOneWidget);
    expect(find.text('docs side'), findsOneWidget);
    expect(
      find.byKey(const Key('branch-preview-diff-toolbar')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('branch-preview-diff-toolbar')))
          .height,
      34,
    );
    expect(find.text('병합 충돌 1개 · fix/docs → main'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('branch-preview-layout-side-by-side')),
    );
    await tester.pump();
    expect(find.byKey(const Key('branch-preview-side-titles')), findsOneWidget);
    expect(find.text('main · main change'), findsOneWidget);
    expect(find.text('fix/docs · docs change'), findsOneWidget);
    final sideTitles = find.byKey(const Key('branch-preview-side-titles'));
    expect(
      find.descendant(of: sideTitles, matching: find.text('기준 브랜치')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sideTitles, matching: find.text('비교 브랜치')),
      findsOneWidget,
    );
    expect(
      find.text('lib/shared.dart · lines 1 · change 1 of 1'),
      findsNothing,
    );
    final conflictActions = find.byKey(
      const Key('branch-preview-conflict-actions'),
    );
    expect(conflictActions, findsOneWidget);
    expect(
      find.descendant(of: conflictActions, matching: find.text('main 사용')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: conflictActions, matching: find.text('fix/docs 사용')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: conflictActions, matching: find.text('둘 다 사용')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('branch-preview-layout-unified')));
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('merge-conflict-use-base')),
    );
    await tester.tap(find.byKey(const Key('merge-conflict-use-base')));
    await tester.pumpAndSettle();
    expect(session.resolvedChoices, [
      ('lib/shared.dart', MergeConflictChoice.base),
    ]);
    await tester.ensureVisible(
      find.byKey(const Key('merge-conflict-continue')),
    );
    await tester.tap(find.byKey(const Key('merge-conflict-continue')));
    await tester.pumpAndSettle();

    expect(find.text('충돌 해결을 마쳤습니다'), findsOneWidget);
    expect(find.text('Merge 가능'), findsOneWidget);
    expect(find.text('Drop'), findsOneWidget);
    expect(
      find.byKey(const Key('branch-preview-resolution-complete')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('branch-preview-apply-card')), findsNothing);
    expect(find.byKey(const Key('branch-preview-apply')), findsOneWidget);
    expect(find.byType(UnifiedPresentationView), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('branch-preview-layout-side-by-side')),
    );
    await tester.pump();
    expect(find.byType(SideBySidePresentationView), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('branch-preview-drop')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(const Key('branch-preview-toolbar-lock')),
          )
          .absorbing,
      isTrue,
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('branch-preview-merge-button')))
          .onTap,
      isNull,
    );
    apply.completeError(StateError('stop test apply'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('branch-preview-drop')));
    await tester.tap(find.byKey(const Key('branch-preview-drop')));
    await tester.pumpAndSettle();
    expect(session.disposed, isTrue);
    expect(find.text('임시 결과를 Drop했습니다'), findsOneWidget);
    expect(find.text('변경 없음'), findsOneWidget);
  });

  testWidgets('rebase preview adds rewritten commits to the timeline', (
    tester,
  ) async {
    final shortComparison = branchComparison();
    final first = commit(
      'feature-one',
      'docs: add merge documentation',
      parents: const ['shared'],
    );
    final second = commit(
      'feature-two',
      'docs: update API examples',
      parents: const ['feature-one'],
    );
    final third = commit(
      'feature-three',
      'docs: publish API guide',
      parents: const ['feature-two'],
    );
    final comparison = BranchComparisonResult(
      baseRef: shortComparison.baseRef,
      compareRef: shortComparison.compareRef,
      baseTip: shortComparison.baseTip,
      compareTip: third.sha,
      baseParent: shortComparison.baseParent,
      compareParent: second.sha,
      mergeBases: shortComparison.mergeBases,
      commits: [
        shortComparison.commits.first,
        for (var index = 0; index < 25; index++)
          BranchComparisonCommit(
            commit: commit('main-$index', 'main history $index'),
            side: BranchCommitSide.baseOnly,
          ),
        BranchComparisonCommit(
          commit: third,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: second,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: first,
          side: BranchCommitSide.compareOnly,
        ),
        shortComparison.commits.last,
      ],
      files: shortComparison.files,
      merge: shortComparison.merge,
    );
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [
        for (var index = 0; index < 30; index++)
          commit('normal-$index', 'normal history $index'),
      ],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-three'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      simulateRebaseCallback: ({required baseRef, required compareRef}) =>
          Future.value(
            const RebaseCheckResult(status: RebaseCheckStatus.clean),
          ),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                RebasePreviewResult(
                  status: RebasePreviewStatus.clean,
                  baseTip: 'main-tip',
                  compareTip: 'feature-three',
                  rewritten: [
                    (
                      original: first,
                      rewrittenSha: '1111111111111111111111111111111111111111',
                    ),
                    (
                      original: second,
                      rewrittenSha: '2222222222222222222222222222222222222222',
                    ),
                    (
                      original: third,
                      rewrittenSha: '3333333333333333333333333333333333333333',
                    ),
                  ],
                  completed: 3,
                  total: 3,
                  virtualTip: '3333333333333333333333333333333333333333',
                ),
              ),
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    // The preview pane covers the timeline once it opens with the
    // comparison, so close it before dragging the list.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('timeline-list')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('new SHA'), findsNWidgets(3));
    expect(find.text('VR'), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.text('feature · 가상'),
      ),
      findsNWidgets(3),
    );
    final virtualChip = find.byKey(
      const Key(
        'ref-chip-3333333333333333333333333333333333333333-feature · 가상',
      ),
    );
    final virtualCell = find.ancestor(
      of: virtualChip,
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('refs-cell-');
      }),
    );
    expect(virtualChip, findsOneWidget);
    expect(virtualCell, findsOneWidget);
    expect(
      tester.getTopLeft(virtualChip).dx - tester.getTopLeft(virtualCell).dx,
      14,
    );
    expect(
      find.byKey(
        const Key(
          'ref-chip-connector-3333333333333333333333333333333333333333',
        ),
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(virtualChip).dy,
      tester
          .getCenter(
            find.byKey(
              const Key(
                'virtual-rebase-node-3333333333333333333333333333333333333333',
              ),
            ),
          )
          .dy,
    );
    expect(find.text('재작성 1/3'), findsOneWidget);
    expect(find.text('재작성 2/3'), findsOneWidget);
    expect(find.text('재작성 3/3'), findsOneWidget);
    expect(find.text('Rebase 성공'), findsNothing);
    expect(find.text('가상 커밋 3개'), findsOneWidget);
    final previewPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CommitGraphPainter>()
        .where((painter) => painter.dashedLanes.isNotEmpty);
    expect(
      previewPainters.every(
        (painter) => painter.previewRailColor == const Color(0xFFC69AFF),
      ),
      isTrue,
    );
    final timelinePainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CommitGraphPainter>();
    expect(
      timelinePainters.map((painter) => painter.refConnector),
      everyElement(isFalse),
    );
    // 'Rebase만'이면 재배치 체인은 현행 그림대로 기준 브랜치 레인 위에 인라인으로
    // 이어지고, 뿌리의 점선이 기준 브랜치 HEAD 노드까지 닿는다.
    CommitGraphPainter painterFor(String sha) => timelinePainters.singleWhere(
      (painter) => painter.row.commit.sha == sha,
    );
    expect(painterFor('3333333333333333333333333333333333333333').row.lane, 0);
    final rootPainter = painterFor('1111111111111111111111111111111111111111');
    expect(rootPainter.row.lane, 0);
    expect(rootPainter.row.transitions, isEmpty);
    expect(CommitGraphPainter.railsBelow(rootPainter.row), {0});
    expect(painterFor('main-tip').continuesFromAbove(0), isTrue);
    expect(painterFor('main-tip').previousDashedLanes, {0});
    expect(painterFor('main-tip').dashedLanes, isEmpty);
    final mappingPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RebaseMappingPainter>()
        .first;
    final mappings = mappingPainter.mappings;
    expect(mappings, hasLength(3));
    expect(mappings.map((mapping) => mapping.color).toSet(), hasLength(3));
    // 아직 없는 커밋이라 링은 점선이다. 색과 굵기는 매핑 색 그대로.
    final virtualRing =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const Key(
                      'virtual-rebase-node-3333333333333333333333333333333333333333',
                    ),
                  ),
                )
                .painter!
            as DashedRingNodePainter;
    expect(virtualRing.ringWidth, 3);
    expect(
      virtualRing.ring,
      mappings
          .singleWhere(
            (mapping) =>
                mapping.rewrittenSha ==
                '3333333333333333333333333333333333333333',
          )
          .color,
    );

    // The preview pane covers the timeline once it opens with the
    // comparison, so close it before dragging the list.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('timeline-list')),
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    expect(find.text('feature · 원본'), findsNWidgets(3));
    final originalAvatar = find.byKey(
      const ValueKey('author-avatar-feature-one'),
    );
    final mappedRing = find.ancestor(
      of: originalAvatar,
      matching: find.byWidgetPredicate((widget) {
        if (widget case Container(decoration: final BoxDecoration decoration)) {
          return decoration.shape == BoxShape.circle &&
              decoration.border != null;
        }
        return false;
      }),
    );
    expect(mappedRing, findsOneWidget);
    expect(
      tester.getSize(mappedRing),
      const Size.square(CommitGraphPainter.avatarDiameter),
    );
    final mappedContainer = tester
        .widgetList<Container>(
          find.ancestor(of: originalAvatar, matching: find.byType(Container)),
        )
        .singleWhere((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle &&
              decoration.border != null;
        });
    final originalBorder = mappedContainer.decoration! as BoxDecoration;
    expect((originalBorder.border! as Border).top.width, 3);
    expect(
      (originalBorder.border! as Border).top.color,
      mappings
          .singleWhere((mapping) => mapping.originalSha == 'feature-one')
          .color,
    );
  });

  testWidgets('branch preview applies merge and restores its exact tips', (
    tester,
  ) async {
    final comparison = branchComparison(
      compareRef: 'fix/docs',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    final applied = BranchApplyResult(
      mode: BranchApplyMode.merge,
      baseBranch: 'main',
      compareBranch: 'fix/docs',
      baseBefore: comparison.baseTip,
      baseAfter: 'merge-commit',
      compareBefore: comparison.compareTip,
      compareAfter: comparison.compareTip,
      workingTreeUpdated: true,
    );
    BranchApplyResult? restored;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'fix/docs'],
            current: 'main',
            tips: {'main': 'main-tip', 'fix/docs': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          applyMergePreviewCallback:
              ({required comparison, required treeSha}) async {
                expect(treeSha, 'merge-tree');
                return applied;
              },
          restoreBranchApplyCallback: (result) async => restored = result,
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-fix/docs')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(find.text('fix/docs를 main에 Merge 실제 적용'), findsOneWidget);
    expect(find.text('Merge 미리보기 성공'), findsOneWidget);
    expect(find.text('가상 커밋'), findsOneWidget);
    expect(find.text('부모 커밋'), findsOneWidget);
    expect(find.text('충돌'), findsOneWidget);
    expect(find.byKey(const Key('branch-preview-progress')), findsOneWidget);
    expect(find.text('main과 fix/docs 유지'), findsNothing);
    final applyButton = tester.widget<FilledButton>(
      find.byKey(const Key('branch-preview-apply')),
    );
    final applyShape =
        applyButton.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(applyShape.borderRadius, BorderRadius.circular(6));
    expect(
      applyButton.style!.backgroundColor!.resolve({}),
      const Color(0xFF594576),
    );
    expect(
      applyButton.style!.side!.resolve({})!.color,
      const Color(0xFF9D79D0),
    );
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    // 머지 커밋을 만드는 적용은 확인 창 대신 커밋 메시지 창으로 확인받는다.
    expect(find.text('main ← fix/docs · 머지 커밋 1개 생성'), findsOneWidget);
    expect(find.text('커밋 메시지'), findsOneWidget);
    expect(
      find.textContaining("Merge branch 'fix/docs' into main"),
      findsWidgets,
    );
    expect(find.text('Merge를 실제로 적용할까요?'), findsNothing);
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Merge 이전 시점으로 되돌리기'), findsOneWidget);
    expect(find.textContaining('merge-commit'), findsOneWidget);
    expect(
      find.textContaining('main 체크아웃 · 작업 트리가 Merge 결과입니다'),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const Key('preview-content-scroll')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('branch-preview-rollback')),
    );
    await tester.tap(find.byKey(const Key('branch-preview-rollback')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('되돌린 뒤에도 main에 체크아웃된 상태로 남고 작업 트리도 이전 상태로 돌아갑니다.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('branch-rollback-confirm')));
    await tester.pumpAndSettle();

    expect(restored, same(applied));
    expect(find.text('SHA 일치 확인'), findsOneWidget);
  });

  /// Applies a merge that moved main's ref only, with main checked out wherever
  /// [current] says, and leaves the preview showing the applied state.
  Future<void> applyRefOnlyMerge(WidgetTester tester, String? current) async {
    final comparison = branchComparison(
      compareRef: 'fix/docs',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    final applied = BranchApplyResult(
      mode: BranchApplyMode.merge,
      baseBranch: 'main',
      compareBranch: 'fix/docs',
      baseBefore: comparison.baseTip,
      baseAfter: 'merge-commit',
      compareBefore: comparison.compareTip,
      compareAfter: comparison.compareTip,
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: RepoRefs(
            local: const ['main', 'fix/docs'],
            current: current,
            tips: const {'main': 'main-tip', 'fix/docs': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          // The apply moved main's ref only, leaving the working tree alone.
          applyMergePreviewCallback:
              ({required comparison, required treeSha}) async => applied,
          restoreBranchApplyCallback: (result) async {},
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-fix/docs')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pumpAndSettle();
  }

  Future<void> openBranchRollbackDialog(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const Key('preview-content-scroll')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('branch-preview-rollback')),
    );
    await tester.tap(find.byKey(const Key('branch-preview-rollback')));
    await tester.pumpAndSettle();
  }

  /// Opens a clean merge preview and presses 실제 적용하기, so the commit message
  /// dialog is on screen. [userName] is what this repository commits as.
  Future<FakeGitRepository> openMergeMessageDialog(
    WidgetTester tester, {
    String userName = '채수원',
    List<CommitProfile> profiles = const [],
    String template = AppSettings.defaultMergeMessageTemplate,
  }) async {
    final comparison = branchComparison(
      compareRef: 'fix/docs',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    final repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'fix/docs'],
        current: 'main',
        tips: {'main': 'main-tip', 'fix/docs': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      applyMergePreviewCallback:
          ({required comparison, required treeSha}) async => BranchApplyResult(
            mode: BranchApplyMode.merge,
            baseBranch: 'main',
            compareBranch: 'fix/docs',
            baseBefore: comparison.baseTip,
            baseAfter: 'merge-commit',
            compareBefore: comparison.compareTip,
            compareAfter: comparison.compareTip,
          ),
      // The repository's own identity, which is where {profile} comes from.
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          arguments.length >= 3 && arguments.first == 'config'
          ? ProcessResult(
              1,
              0,
              arguments.last == 'user.name'
                  ? '$userName\n'
                  : 'sw.chae@navercorp.com\n',
              '',
            )
          : ProcessResult(1, 0, '', ''),
    );
    await tester.pumpWidget(
      app(
        repository,
        controller,
        commitProfiles: profiles,
        mergeMessageTemplate: template,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-fix/docs')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    return repository;
  }

  String messageFieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('branch-apply-message')))
      .controller!
      .text;

  VoidCallback? applyButtonPress(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('branch-apply-confirm')))
      .onPressed;

  testWidgets('the merge apply writes the message the user confirmed', (
    tester,
  ) async {
    final repository = await openMergeMessageDialog(
      tester,
      profiles: const [
        CommitProfile(label: '회사', name: '채수원', email: 'sw.chae@navercorp.com'),
      ],
    );
    final field = find.byKey(const Key('branch-apply-message'));

    expect(find.text('실제 적용하기'), findsOneWidget);
    expect(find.text('main ← fix/docs · 머지 커밋 1개 생성'), findsOneWidget);
    expect(find.text('커밋 메시지'), findsOneWidget);
    expect(
      messageFieldText(tester),
      "Merge branch 'fix/docs' into main\n\nReviewed-by: 채수원",
    );
    expect(find.textContaining('설정의 기본 메시지 템플릿으로 채워졌습니다'), findsOneWidget);

    // Esc도 취소도 메시지가 아니라 적용 자체를 중단한다.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(repository.appliedMessage, isNull);

    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-apply-cancel')));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(repository.appliedMessage, isNull);
    expect(find.byKey(const Key('branch-preview-rollback')), findsNothing);

    // 다시 열어 비우면 적용이 잠기고, 왜 잠겼는지 말한다.
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    expect(applyButtonPress(tester), isNotNull);
    await tester.enterText(field, '   \n');
    await tester.pumpAndSettle();
    expect(applyButtonPress(tester), isNull);
    expect(find.textContaining('비워서 적용할 수는 없습니다'), findsOneWidget);

    // 고친 그대로가 머지 커밋 메시지가 된다.
    const edited =
        "Merge branch 'fix/docs' into main\n"
        '\n'
        '리뷰 끝났습니다.\n'
        'Reviewed-by: 채수원';
    await tester.enterText(field, edited);
    await tester.pumpAndSettle();
    expect(applyButtonPress(tester), isNotNull);
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pumpAndSettle();

    expect(repository.appliedMessage, edited);
    expect(find.text('Merge 이전 시점으로 되돌리기'), findsOneWidget);
  });

  testWidgets('an emptied template prefills git\'s own message', (
    tester,
  ) async {
    await openMergeMessageDialog(tester, template: '');

    expect(messageFieldText(tester), "Merge branch 'fix/docs' into main");
    // 채운 쪽을 그대로 말한다: 템플릿을 비웠으니 템플릿이 채웠다고 하지 않는다.
    expect(find.textContaining('git 표준 메시지로 채워졌습니다'), findsOneWidget);
    expect(find.textContaining('설정의 기본 메시지 템플릿'), findsNothing);
  });

  testWidgets('a repository with no name to give drops the Reviewed-by line', (
    tester,
  ) async {
    await openMergeMessageDialog(tester, userName: '');

    // 줄만이 아니라 그 위에 남을 빈 줄까지 사라진다.
    expect(messageFieldText(tester), "Merge branch 'fix/docs' into main");
    // 없는 줄을 설명하지 않는다.
    expect(find.textContaining('Reviewed-by는'), findsNothing);
  });

  /// A clean rebase preview on screen, with 'Rebase만' selected as it starts.
  Future<FakeGitRepository> openRebasePreview(WidgetTester tester) async {
    // 선택 카드가 붙은 적용 카드는 기본 창보다 길어서 버튼이 창 밖으로 나간다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    const compareRef = 'fix/docs';
    final comparison = branchComparison(compareRef: compareRef);
    final original = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: original, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    );
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', compareRef],
        current: 'main',
        tips: {'main': 'main-tip', compareRef: 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(repository, preview),
      applyRebasePreviewCallback:
          ({required comparison, required virtualTip}) async =>
              BranchApplyResult(
                mode: BranchApplyMode.rebase,
                baseBranch: 'main',
                compareBranch: compareRef,
                baseBefore: comparison.baseTip,
                baseAfter: comparison.baseTip,
                compareBefore: comparison.compareTip,
                compareAfter: 'rewritten-feature',
              ),
      applyRebaseThenMergeCallback:
          ({required comparison, required virtualTip}) async =>
              BranchApplyResult(
                mode: BranchApplyMode.rebaseMerge,
                baseBranch: 'main',
                compareBranch: compareRef,
                baseBefore: comparison.baseTip,
                baseAfter: 'merge-commit',
                compareBefore: comparison.compareTip,
                compareAfter: 'rewritten-feature',
                workingTreeUpdated: true,
              ),
      filesBetween: (_, _) async => const [],
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          arguments.length >= 3 && arguments.first == 'config'
          ? ProcessResult(
              1,
              0,
              arguments.last == 'user.name' ? '채수원\n' : '',
              '',
            )
          : ProcessResult(1, 0, '', ''),
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-$compareRef')));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('a plain rebase has no message to write and keeps its confirm', (
    tester,
  ) async {
    await openRebasePreview(tester);

    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Rebase를 실제로 적용할까요?'), findsOneWidget);
    expect(find.byKey(const Key('branch-apply-message')), findsNothing);
    expect(find.text('실제 적용하기'), findsOneWidget); // 카드의 버튼뿐, 창 제목이 아니다.
  });

  testWidgets('a rebase-merge apply writes the message the user confirmed', (
    tester,
  ) async {
    final repository = await openRebasePreview(tester);
    final optionMerge = find.byKey(
      const Key('branch-preview-option-rebase-merge'),
    );
    await tester.ensureVisible(optionMerge);
    await tester.tap(optionMerge);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();

    expect(find.text('fix/docs 재배치 → 머지 커밋 1개로 main 이동'), findsOneWidget);
    expect(find.text('Rebase 후 Merge를 실제로 적용할까요?'), findsNothing);
    expect(
      messageFieldText(tester),
      "Merge branch 'fix/docs' into main\n\nReviewed-by: 채수원",
    );

    const edited = "Merge branch 'fix/docs' into main\n\n재배치한 뒤 병합했습니다.";
    await tester.enterText(
      find.byKey(const Key('branch-apply-message')),
      edited,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(repository.appliedMessage, edited);
    expect(find.text('Rebase 후 Merge 이전 시점으로 되돌리기'), findsOneWidget);
  });

  testWidgets('a merge applied to a branch checked out nowhere says so', (
    tester,
  ) async {
    await applyRefOnlyMerge(tester, null);

    expect(find.textContaining('main 체크아웃'), findsNothing);
    expect(
      find.textContaining('main 브랜치는 새 커밋을 가리키고 작업 트리는 그대로입니다'),
      findsOneWidget,
    );
    expect(
      find.textContaining('main 브랜치를 체크아웃하면 결과가 작업 트리에 반영됩니다'),
      findsOneWidget,
    );
    await openBranchRollbackDialog(tester);

    // Nothing was on disk to undo, and the dialog may not claim otherwise.
    expect(find.textContaining('되돌릴 때도 작업 트리는 건드리지 않습니다.'), findsOneWidget);
    expect(find.textContaining('체크아웃된 상태로 남'), findsNothing);
  });

  testWidgets('rolling back onto the branch checked out now warns about it', (
    tester,
  ) async {
    // 적용은 ref만 옮겼지만 지금은 main이 체크아웃돼 있으니 되돌리기가 작업 트리까지
    // 바꿉니다. 되돌리기는 그 시점의 체크아웃을 다시 확인하기 때문입니다.
    await applyRefOnlyMerge(tester, 'main');
    await openBranchRollbackDialog(tester);

    expect(
      find.textContaining('되돌린 뒤에도 main에 체크아웃된 상태로 남고 작업 트리도 이전 상태로 돌아갑니다.'),
      findsOneWidget,
    );
    expect(find.textContaining('되돌릴 때도 작업 트리는 건드리지 않습니다'), findsNothing);
  });

  Future<void> openCleanMergePreview(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
  }

  testWidgets('the clean merge file list says where each change came from', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
        resultFiles: [
          GitFileChange(
            path: 'lib/shared.dart',
            status: 'M',
            additions: 2,
            deletions: 1,
          ),
          GitFileChange(
            path: 'lib/renamed.dart',
            oldPath: 'lib/old.dart',
            status: 'R100',
            additions: 0,
            deletions: 0,
          ),
          GitFileChange(
            path: 'lib/gone.dart',
            status: 'D',
            additions: 0,
            deletions: 3,
          ),
          GitFileChange(
            path: 'lib/added.dart',
            status: 'A',
            additions: 4,
            deletions: 0,
          ),
        ],
        baseChangedFiles: {'lib/shared.dart', 'lib/old.dart'},
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    String labelOf(String path) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(Key('preview-provenance-$path')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(labelOf('lib/shared.dart'), '양쪽 수정');
    // The rename's old path is ours, so this file is a both-sides candidate too.
    expect(labelOf('lib/renamed.dart'), '양쪽 수정');
    expect(labelOf('lib/gone.dart'), '브랜치에서 삭제');
    expect(labelOf('lib/added.dart'), '브랜치에서 추가');
  });

  testWidgets('a comparison without a merge base carries no source labels', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
        resultFiles: [
          GitFileChange(
            path: 'lib/shared.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    expect(find.byKey(const Key('branch-preview-file-list')), findsOneWidget);
    expect(find.textContaining('양쪽'), findsNothing);
    expect(find.textContaining('브랜치에서'), findsNothing);
  });

  testWidgets('proximity regions sit under the file both sides edited', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
        resultFiles: [
          GitFileChange(
            path: 'lib/settings.dart',
            status: 'M',
            additions: 4,
            deletions: 2,
          ),
          GitFileChange(
            path: 'lib/timeline.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
        ],
        baseChangedFiles: {'lib/settings.dart', 'lib/timeline.dart'},
        proximity: {
          'lib/settings.dart': [
            (startLine: 556, endLine: 568),
            (startLine: 1412, endLine: 1420),
          ],
        },
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          diffBetween: (_, _, file) async => [
            const DiffLine(
              kind: DiffLineKind.hunk,
              text: '@@ -556,1 +556,2 @@',
            ),
            const DiffLine(
              kind: DiffLineKind.add,
              text: 'both sides here',
              newNumber: 556,
            ),
          ],
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    String labelOf(String path) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(Key('preview-provenance-$path')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(labelOf('lib/settings.dart'), '양쪽 수정 · 근접 2곳');
    // 근접 구역이 없는 파일은 지금 그대로다.
    expect(labelOf('lib/timeline.dart'), '양쪽 수정');
    expect(
      find.byKey(const Key('preview-proximity-lib/settings.dart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('preview-proximity-lib/timeline.dart')),
      findsNothing,
    );
    expect(find.text('양쪽 편집이 10줄 안에서 겹침'), findsOneWidget);
    expect(find.text('556~568줄'), findsOneWidget);
    expect(find.text('1,412~1,420줄'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('preview-proximity-lib/settings.dart-556')),
    );
    await tester.pumpAndSettle();

    // 파일 줄 클릭과 같은 경로로 그 파일의 결과 diff가 열리고, 스크롤 목표가 구역
    // 첫 줄에 놓인다.
    expect(
      find.byKey(const Key('branch-preview-diff-toolbar')),
      findsOneWidget,
    );
    final view = tester.widget<UnifiedPresentationView>(
      find.byType(UnifiedPresentationView),
    );
    expect(view.path, 'lib/settings.dart');
    expect(view.scrollTarget, (oldLine: null, newLine: 556));
  });

  testWidgets('a region the result diff never shows still scrolls', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
        resultFiles: [
          GitFileChange(
            path: 'lib/settings.dart',
            status: 'M',
            additions: 1,
            deletions: 0,
          ),
        ],
        baseChangedFiles: {'lib/settings.dart'},
        // 구역 첫 줄은 기준 쪽 편집이라 결과 diff에 그 줄이 없다.
        proximity: {
          'lib/settings.dart': [(startLine: 400, endLine: 405)],
        },
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          // 한 화면에 안 들어가는 diff라 목표 줄은 게으른 목록 밖에서 시작한다.
          diffBetween: (_, _, file) async => [
            const DiffLine(
              kind: DiffLineKind.hunk,
              text: '@@ -1,300 +1,300 @@',
            ),
            for (var at = 1; at <= 300; at++)
              DiffLine(
                kind: at == 300 ? DiffLineKind.add : DiffLineKind.context,
                text: 'line $at',
                oldNumber: at == 300 ? null : at,
                newNumber: at,
              ),
          ],
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    await tester.tap(
      find.byKey(const Key('preview-proximity-lib/settings.dart-400')),
    );
    await tester.pumpAndSettle();

    final view = tester.widget<UnifiedPresentationView>(
      find.byType(UnifiedPresentationView),
    );
    // 없는 줄 대신 실제로 그려진 가장 가까운 줄을 노린다.
    expect(view.scrollTarget, (oldLine: null, newLine: 300));
    // 그 줄이 첫 화면 밖이어도 한 화면씩 내려가며 데려다준다.
    expect(view.controller!.offset, greaterThan(0));
  });

  testWidgets('the recommendation chip opens its measured reasons', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    RebaseCheckResult? passedCheck;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          simulateRebaseCallback:
              ({required baseRef, required compareRef}) async =>
                  const RebaseCheckResult(status: RebaseCheckStatus.clean),
          recommendationCallback: (_, check) async {
            passedCheck = check;
            return const BranchRecommendation(
              verdict: BranchIntegrationVerdict.rebaseThenMerge,
              summary: '근거 3',
              reasons: [
                '브랜치가 로컬 전용이라 히스토리를 다시 써도 아무도 안 다칩니다',
                'Rebase 미리보기 6개 커밋 전부 충돌 없이 재생됐습니다',
                '최근 main 커밋 50개 중 21개가 머지 커밋 — 이 저장소의 관례입니다',
              ],
            );
          },
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    // 이미 돌린 재배치 실측을 넘겨받아 두 번 계산하지 않는다.
    expect(passedCheck?.status, RebaseCheckStatus.clean);
    expect(find.text('추천: Rebase 후 Merge'), findsOneWidget);
    expect(find.text('근거 3'), findsOneWidget);
    expect(
      find.byKey(const Key('branch-preview-recommendation-reasons')),
      findsNothing,
    );

    // 요약 바는 가로로 스크롤되니 칩을 화면 안으로 들인 뒤 누른다.
    await tester.ensureVisible(
      find.byKey(const Key('branch-preview-recommendation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-preview-recommendation')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('branch-preview-recommendation-reasons')),
      findsOneWidget,
    );
    expect(find.text('왜 Rebase 후 Merge인가'), findsOneWidget);
    expect(find.text('브랜치가 로컬 전용이라 히스토리를 다시 써도 아무도 안 다칩니다'), findsOneWidget);
    expect(
      find.text('최근 main 커밋 50개 중 21개가 머지 커밋 — 이 저장소의 관례입니다'),
      findsOneWidget,
    );
  });

  testWidgets('signals too weak for a verdict show no chip', (tester) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          simulateRebaseCallback:
              ({required baseRef, required compareRef}) async =>
                  const RebaseCheckResult(status: RebaseCheckStatus.clean),
          recommendationCallback: (_, _) async => null,
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    expect(
      find.byKey(const Key('branch-preview-recommendation')),
      findsNothing,
    );
    expect(find.textContaining('추천:'), findsNothing);
  });

  testWidgets('branch preview applies rebase with a focused commit', (
    tester,
  ) async {
    // 선택 카드가 붙은 적용 카드는 기본 창보다 길어서 버튼이 창 밖으로 나간다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    const compareRef =
        'codex/remote-behind-badge-with-an-extra-long-branch-name';
    final comparison = branchComparison(compareRef: compareRef);
    final original = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: original, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    );
    final applied = BranchApplyResult(
      mode: BranchApplyMode.rebase,
      baseBranch: 'main',
      compareBranch: 'fix/docs',
      baseBefore: comparison.baseTip,
      baseAfter: comparison.baseTip,
      compareBefore: comparison.compareTip,
      compareAfter: 'rewritten-feature',
    );
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', compareRef],
        current: 'main',
        tips: {'main': 'main-tip', compareRef: 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(repository, preview),
      applyRebasePreviewCallback:
          ({required comparison, required virtualTip}) async {
            expect(virtualTip, 'rewritten-feature');
            return applied;
          },
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-$compareRef')));
    await tester.pumpAndSettle();
    // The comparison opens the preview pane itself now.
    await tester.pumpAndSettle();

    expect(find.text('실제 적용하기'), findsOneWidget);
    expect(find.text('Rebase 미리보기 성공'), findsOneWidget);
    expect(find.text('가상 커밋'), findsOneWidget);
    expect(find.text('원본 커밋'), findsOneWidget);
    expect(find.text('점선 결과를 실제 브랜치에 적용할 수 있습니다.'), findsNothing);
    final applyLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('branch-preview-apply')),
        matching: find.byType(Text),
      ),
    );
    expect(applyLabel.maxLines, 2);
    expect(applyLabel.overflow, TextOverflow.ellipsis);
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pump();

    expect(find.byKey(const Key('rebase-apply-current-row')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(find.text('Rebase 이전 시점으로 되돌리기'), findsOneWidget);
  });

  testWidgets('the selected rebase landing is the one applied', (tester) async {
    const compareRef = 'fix/docs';
    final comparison = branchComparison(compareRef: compareRef);
    final original = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: original, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    );
    final applied = BranchApplyResult(
      mode: BranchApplyMode.rebaseMerge,
      baseBranch: 'main',
      compareBranch: compareRef,
      baseBefore: comparison.baseTip,
      baseAfter: 'merge-commit',
      compareBefore: comparison.compareTip,
      compareAfter: 'rewritten-feature',
      workingTreeUpdated: true,
    );
    BranchApplyResult? restored;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', compareRef],
        current: 'main',
        tips: {'main': 'main-tip', compareRef: 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(repository, preview),
      applyRebaseThenMergeCallback:
          ({required comparison, required virtualTip}) async {
            expect(virtualTip, 'rewritten-feature');
            return applied;
          },
      restoreBranchApplyCallback: (result) async => restored = result,
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-$compareRef')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('branch-preview-rebase-merge-graph')),
      findsOneWidget,
    );
    RebaseMergeResultPainter graphPainter() =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(
                      const Key('branch-preview-rebase-merge-graph'),
                    ),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as RebaseMergeResultPainter;
    expect(graphPainter().commitCount, 1);
    expect(graphPainter().baseLabel, 'main');
    // 기본 선택은 'Rebase만' — 같은 선 위로 이어 그리고, 머지 노드는 없다.
    expect(graphPainter().mergeCommit, isFalse);
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsNothing);
    expect(find.text('머지 커밋 1개'), findsNothing);
    // 기준 브랜치 칩은 아직 실제 tip 줄에 있다.
    final baseTipChip = find.byKey(const Key('ref-chip-main-tip-main'));
    expect(
      find.descendant(of: baseTipChip, matching: find.text('✓')),
      findsOneWidget,
    );
    final optionRebase = find.byKey(const Key('branch-preview-option-rebase'));
    final optionMerge = find.byKey(
      const Key('branch-preview-option-rebase-merge'),
    );
    expect(
      tester.widget<Text>(find.text('Rebase만')).style!.color,
      const Color(0xFFE8DCFF),
    );
    // 카드 자체의 Container가 첫 번째, 그 안의 라디오가 두 번째다.
    Decoration cardDecoration(Finder option) => tester
        .widget<Container>(
          find.descendant(of: option, matching: find.byType(Container)).first,
        )
        .decoration!;
    expect(
      cardDecoration(optionRebase),
      isA<BoxDecoration>()
          .having(
            (decoration) => (decoration.border! as Border).top.color,
            'border',
            const Color(0xFF9D79D0),
          )
          .having(
            (decoration) => decoration.color,
            'fill',
            const Color(0xFFC69AFF).withValues(alpha: 0.08),
          ),
    );
    expect(
      cardDecoration(optionMerge),
      isA<BoxDecoration>()
          .having(
            (decoration) => (decoration.border! as Border).top.color,
            'border',
            const Color(0xFF4A4157),
          )
          .having((decoration) => decoration.color, 'fill', Colors.transparent),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('branch-preview-rebase-merge-caption')),
          )
          .data,
      '재배치한 커밋 위에 머지 커밋 하나를 만들어 main을 옮깁니다. '
      'main이 체크아웃돼 있지 않으면 포인터만 이동합니다.',
    );
    expect(
      find.text('$compareRef를 main 위로 재배치합니다. main은 움직이지 않습니다.'),
      findsOneWidget,
    );

    await tester.ensureVisible(optionMerge);
    await tester.tap(optionMerge);
    await tester.pumpAndSettle();

    // 선택이 곧 미리보기: pane 그래프와 타임라인 가상 경로가 같이 바뀐다.
    expect(graphPainter().mergeCommit, isTrue);
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsOneWidget);
    expect(find.byKey(const Key('virtual-rebase-merge-node')), findsOneWidget);
    expect(find.text('가상 머지'), findsOneWidget);
    expect(find.text("Merge branch '$compareRef' into main"), findsOneWidget);
    expect(find.text('머지 커밋 1개'), findsOneWidget);
    final vmChip = find.byKey(const Key('virtual-rebase-merge-chip'));
    expect(
      find.descendant(of: vmChip, matching: find.text('main')),
      findsOneWidget,
    );
    // 기준 브랜치 칩이 가상 머지 줄로 올라가면서 실제 tip 줄에는 체크가 남지 않는다.
    expect(
      find.descendant(of: vmChip, matching: find.text('✓')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: baseTipChip, matching: find.text('✓')),
      findsNothing,
    );
    expect(find.text('재작성 1/1'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    // Rebase 후 Merge도 머지 커밋을 만드니 메시지 창이 확인 창을 대신한다.
    expect(find.text('$compareRef 재배치 → 머지 커밋 1개로 main 이동'), findsOneWidget);
    expect(find.text('Rebase 후 Merge를 실제로 적용할까요?'), findsNothing);
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Rebase 후 Merge 적용 완료'), findsOneWidget);
    expect(
      find.textContaining('$compareRef: feature-tip → rewritten-feature'),
      findsOneWidget,
    );
    expect(
      find.textContaining('main: main-tip → merge-commit'),
      findsOneWidget,
    );
    expect(find.textContaining('main 체크아웃 · 작업 트리가 병합 결과입니다'), findsOneWidget);
    expect(find.text('Rebase 후 Merge 이전 시점으로 되돌리기'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('branch-preview-rollback')),
    );
    await tester.tap(find.byKey(const Key('branch-preview-rollback')));
    await tester.pumpAndSettle();

    expect(find.text('Rebase 후 Merge 이전 시점으로 되돌릴까요?'), findsOneWidget);
    expect(find.textContaining('로컬 main을 main-tip으로 되돌립니다.'), findsOneWidget);
    expect(
      find.textContaining('로컬 $compareRef를 feature-tip으로 되돌립니다.'),
      findsOneWidget,
    );
    expect(find.textContaining('되돌린 뒤에도 main에 체크아웃된 상태로 남고'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-rollback-confirm')));
    await tester.pumpAndSettle();

    expect(restored, same(applied));
  });

  testWidgets('the rebase landing selection never outlives its preview', (
    tester,
  ) async {
    // 비교 대상을 두 번 고르니 툴바 선택기가 잘리지 않을 만큼 넓은 창을 쓴다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final comparisons = {
      'feature': branchComparison(),
      'other': branchComparison(compareRef: 'other', compareTip: 'other-tip'),
    };
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature', 'other'],
        current: 'main',
        tips: {
          'main': 'main-tip',
          'feature': 'feature-tip',
          'other': 'other-tip',
        },
      ),
      compareBranchesCallback: (_, compare) async => comparisons[compare]!,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async {
            final comparison = comparisons[compareRef]!;
            final original = comparison.commits
                .singleWhere(
                  (entry) => entry.side == BranchCommitSide.compareOnly,
                )
                .commit;
            return FakeRebasePreviewSession(
              repository,
              RebasePreviewResult(
                status: RebasePreviewStatus.clean,
                baseTip: comparison.baseTip,
                compareTip: comparison.compareTip,
                rewritten: [
                  (original: original, rewrittenSha: 'rewritten-$compareRef'),
                ],
                completed: 1,
                total: 1,
                virtualTip: 'rewritten-$compareRef',
              ),
            );
          },
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    Future<void> compareWith(String ref) async {
      await tester.tap(find.byKey(const Key('branch-diff-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('branch-diff-menu-$ref')));
      await tester.pumpAndSettle();
    }

    // 좁은 pane에서는 두 카드가 한 화면에 다 들어오지 않으니 선택 배선만 부른다.
    // 실제 탭 경로는 위 테스트가 덮는다.
    Future<void> pick(Key option) async {
      tester.widget<InkWell>(find.byKey(option)).onTap!();
      await tester.pumpAndSettle();
    }

    bool mergeCommitDrawn() =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byKey(
                          const Key('branch-preview-rebase-merge-graph'),
                        ),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as RebaseMergeResultPainter)
            .mergeCommit;
    const merged = Key('branch-preview-option-rebase-merge');
    const plain = Key('branch-preview-option-rebase');

    await compareWith('feature');
    await pick(merged);
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsOneWidget);
    expect(find.text('머지 커밋 1개'), findsOneWidget);
    expect(mergeCommitDrawn(), isTrue);

    // 다시 'Rebase만'을 고르면 현행 그림으로 돌아온다.
    await pick(plain);
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsNothing);
    expect(find.text('머지 커밋 1개'), findsNothing);
    expect(mergeCommitDrawn(), isFalse);
    expect(
      find.byKey(const Key('virtual-rebase-row-rewritten-feature')),
      findsOneWidget,
    );

    // 비교 대상이 바뀌면 선택도 기본값으로 돌아간다.
    await pick(merged);
    await compareWith('other');
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsNothing);
    expect(find.text('머지 커밋 1개'), findsNothing);
    expect(mergeCommitDrawn(), isFalse);

    // 미리보기 모드를 오갈 때도 마찬가지다.
    await pick(merged);
    await tester.tap(find.byKey(const Key('branch-preview-merge-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-preview-rebase-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('virtual-rebase-merge-row')), findsNothing);
    expect(find.text('머지 커밋 1개'), findsNothing);
    expect(mergeCommitDrawn(), isFalse);
  });

  testWidgets('a rebase preview with nothing to replay hides the option', (
    tester,
  ) async {
    const compareRef = 'fix/docs';
    final comparison = branchComparison(compareRef: compareRef);
    // 옮길 커밋이 없으면 그 위에 얹을 머지 커밋도 없다.
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: const [],
      completed: 0,
      total: 0,
      virtualTip: comparison.baseTip,
    );
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', compareRef],
        current: 'main',
        tips: {'main': 'main-tip', compareRef: 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(repository, preview),
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-$compareRef')));
    await tester.pumpAndSettle();

    // 재배치할 커밋이 없으면 가상 노드가 없어 결과 패널도, 그 안의 두 번째 선택지도
    // 뜨지 않는다 — 만들 머지 커밋이 없는 적용을 제안하지 않는다.
    expect(find.byKey(const Key('branch-preview-apply-card')), findsNothing);
    expect(
      find.byKey(const Key('branch-preview-option-rebase-merge')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('branch-preview-rebase-merge-caption')),
      findsNothing,
    );
  });

  testWidgets('the merge preview keeps the rebase-then-merge option away', (
    tester,
  ) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
        ),
        controller,
      ),
    );
    await openCleanMergePreview(tester);

    expect(find.byKey(const Key('branch-preview-apply-card')), findsOneWidget);
    expect(find.byKey(const Key('branch-preview-option-rebase')), findsNothing);
    expect(
      find.byKey(const Key('branch-preview-option-rebase-merge')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('branch-preview-rebase-merge-graph')),
      findsNothing,
    );
    expect(find.textContaining('머지 커밋 하나를 만들어'), findsNothing);
    // Merge 모드 버튼 문구는 그대로다.
    expect(find.text('feature를 main에 Merge 실제 적용'), findsOneWidget);
  });

  testWidgets('stale merge preview tips are discarded', (tester) async {
    final comparison = branchComparison(
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.conflicts,
        files: ['lib/shared.dart'],
      ),
    );
    late FakeGitRepository repository;
    late FakeMergePreviewSession session;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openMergePreviewCallback:
          ({required baseRef, required compareRef}) async => session,
    );
    session = FakeMergePreviewSession(
      repository,
      const MergePreviewResult(
        status: MergePreviewStatus.conflict,
        baseTip: 'old-main',
        compareTip: 'feature-tip',
        conflictFiles: ['lib/shared.dart'],
      ),
      finishResult: const MergePreviewResult(
        status: MergePreviewStatus.failed,
        baseTip: 'old-main',
        compareTip: 'feature-tip',
      ),
    );

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(session.disposed, isTrue);
    expect(find.text('Merge 검사 실패'), findsOneWidget);
    expect(find.text('브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.'), findsWidgets);
  });

  testWidgets('stale rebase preview tips are discarded', (tester) async {
    final comparison = branchComparison();
    late FakeGitRepository repository;
    late FakeRebasePreviewSession session;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async => session,
    );
    session = FakeRebasePreviewSession(
      repository,
      const RebasePreviewResult(
        status: RebasePreviewStatus.clean,
        baseTip: 'old-main',
        compareTip: 'feature-tip',
        virtualTip: 'rewritten-feature',
      ),
    );

    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(session.disposed, isTrue);
    expect(find.text('Rebase 검사 실패'), findsOneWidget);
    expect(find.text('브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.'), findsWidgets);
  });

  testWidgets('late rebase conflict state cannot replace merge mode', (
    tester,
  ) async {
    final comparison = branchComparison();
    final current = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final operation = Completer<bool>();
    var operationChecks = 0;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: comparison.baseTip,
                  compareTip: comparison.compareTip,
                  currentCommit: current,
                  total: 1,
                  conflictFiles: const ['lib/shared.dart'],
                ),
              ),
      operationInProgressCallback: () =>
          operationChecks++ == 0 ? operation.future : Future.value(false),
    );

    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('branch-preview-merge')));
    await tester.pump();
    operation.complete(true);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('branch-preview-summary')),
        matching: find.text('Merge 미리보기'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('branch-preview-success-icon')),
      findsOneWidget,
    );
    expect(find.text('Rebase 충돌'), findsNothing);

    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pumpAndSettle();
    expect(find.text('Rebase 충돌'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('preview-state-lib/shared.dart')),
    );
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('rebase-conflict-use-base')))
          .onTap,
      isNotNull,
    );
  });

  testWidgets('remote merge preview applies to the local base only', (
    tester,
  ) async {
    final comparison = branchComparison(
      compareRef: 'origin/feature',
      merge: const MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    var applied = false;
    var restored = false;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main'],
            remote: ['origin/feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'origin/feature': 'feature-tip'},
            localTips: {'main': 'main-tip'},
          ),
          compareBranchesCallback: (_, _) async => comparison,
          applyMergePreviewCallback:
              ({required comparison, required treeSha}) async {
                applied = true;
                return const BranchApplyResult(
                  mode: BranchApplyMode.merge,
                  baseBranch: 'main',
                  compareBranch: 'origin/feature',
                  baseBefore: 'main-tip',
                  baseAfter: 'merge-tip',
                  compareBefore: 'feature-tip',
                  compareAfter: 'feature-tip',
                );
              },
          restoreBranchApplyCallback: (_) async => restored = true,
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-origin/feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(
      find.text('origin/feature는 입력으로만 사용합니다. 실제 변경은 로컬 main에 적용됩니다.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('branch-preview-apply')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('origin/feature를 main에 Merge 실제 적용'), findsOneWidget);

    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    expect(find.text('main ← origin/feature · 머지 커밋 1개 생성'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pumpAndSettle();

    expect(applied, isTrue);
    expect(find.textContaining('main: main-tip → merge-tip'), findsOneWidget);
    expect(find.textContaining('origin/feature: 변경 없음'), findsOneWidget);

    await tester.tap(find.byKey(const Key('branch-preview-rollback')));
    await tester.pumpAndSettle();
    expect(find.textContaining('로컬 main을 main-tip으로 되돌립니다'), findsOneWidget);
    expect(find.textContaining('origin/feature는 변경하지 않습니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-rollback-confirm')));
    await tester.pumpAndSettle();
    expect(restored, isTrue);
  });

  testWidgets('remote rebase preview creates a local branch before apply', (
    tester,
  ) async {
    // 선택 카드가 붙은 적용 카드는 기본 창보다 길어서 버튼이 창 밖으로 나간다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final comparison = branchComparison(compareRef: 'origin/feature');
    final original = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: original, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    );
    var applied = false;
    var restored = false;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main'],
        remote: ['origin/feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'origin/feature': 'feature-tip'},
        localTips: {'main': 'main-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(repository, preview),
      applyRebasePreviewCallback:
          ({required comparison, required virtualTip}) async {
            applied = true;
            return const BranchApplyResult(
              mode: BranchApplyMode.rebase,
              baseBranch: 'main',
              compareBranch: 'feature',
              baseBefore: 'main-tip',
              baseAfter: 'main-tip',
              compareBefore: 'feature-tip',
              compareAfter: 'rewritten-feature',
              compareBranchCreated: true,
            );
          },
      restoreBranchApplyCallback: (_) async => restored = true,
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-origin/feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(
      find.text('로컬 feature를 origin/feature에서 만든 뒤 결과를 적용합니다.'),
      findsOneWidget,
    );
    expect(find.text('실제 적용하기'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('branch-preview-apply')))
          .onPressed,
      isNotNull,
    );

    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('로컬 feature 브랜치만 변경합니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-apply-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
    expect(
      find.textContaining('feature: 새 브랜치 → rewritten-feature'),
      findsOneWidget,
    );
    expect(find.textContaining('origin/feature: 변경 없음'), findsOneWidget);

    await tester.tap(find.byKey(const Key('branch-preview-rollback')));
    await tester.pumpAndSettle();
    expect(find.textContaining('적용 과정에서 만든 로컬 feature를 삭제합니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branch-rollback-confirm')));
    await tester.pumpAndSettle();
    expect(restored, isTrue);
  });

  testWidgets('divergent local rebase target recalculates before apply', (
    tester,
  ) async {
    // 선택 카드가 붙은 적용 카드는 기본 창보다 길어서 버튼이 창 밖으로 나간다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final comparisons = <String>[];
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        remote: ['origin/feature'],
        current: 'main',
        tips: {
          'main': 'main-tip',
          'feature': 'local-tip',
          'origin/feature': 'feature-tip',
        },
        localTips: {'main': 'main-tip', 'feature': 'local-tip'},
      ),
      compareBranchesCallback: (base, compare) async {
        comparisons.add(compare);
        return branchComparison(
          compareRef: compare,
          compareTip: compare == 'feature' ? 'local-tip' : 'feature-tip',
        );
      },
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async {
            final compareTip = compareRef == 'feature'
                ? 'local-tip'
                : 'feature-tip';
            final original = commit(
              compareTip,
              'feature only',
              parents: const ['root'],
            );
            return FakeRebasePreviewSession(
              repository,
              RebasePreviewResult(
                status: RebasePreviewStatus.clean,
                baseTip: 'main-tip',
                compareTip: compareTip,
                rewritten: [
                  (original: original, rewrittenSha: 'rewritten-$compareTip'),
                ],
                completed: 1,
                total: 1,
                virtualTip: 'rewritten-$compareTip',
              ),
            );
          },
      filesBetween: (_, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-origin/feature')));
    await tester.pumpAndSettle();
    // The preview pane opens with the comparison now, so Enter would close it.

    expect(find.text('로컬 feature 기준으로 다시 계산'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('branch-preview-apply')));
    await tester.tap(find.byKey(const Key('branch-preview-apply')));
    await tester.pumpAndSettle();

    expect(comparisons, ['origin/feature', 'feature']);
    expect(find.text('기존 로컬 feature 기준으로 미리보기를 다시 계산했습니다.'), findsOneWidget);
  });

  testWidgets('rebase conflict focuses the actual commit row', (tester) async {
    final comparison = branchComparison();
    final current = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      simulateRebaseCallback: ({required baseRef, required compareRef}) =>
          Future.value(
            const RebaseCheckResult(status: RebaseCheckStatus.conflicts),
          ),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'main-tip',
                  compareTip: 'feature-tip',
                  currentCommit: current,
                  completed: 0,
                  total: 1,
                  conflictFiles: const ['lib/shared.dart'],
                ),
              ),
      operationInProgressCallback: () async => true,
      diffBetween: (_, _, _) async => const [],
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('rebase-conflict-current-row')),
      findsOneWidget,
    );
    expect(find.text('Rebase 충돌'), findsOneWidget);
    expect(find.text('Rebase 상태 및 결정'), findsOneWidget);
    expect(find.text('진행 1/1'), findsOneWidget);
    expect(find.text('리베이스 진행 1/1'), findsOneWidget);
    expect(find.text('main · HEAD'), findsOneWidget);
    expect(find.text('main HEAD 위 예상 위치'), findsOneWidget);
    final targetPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CommitGraphPainter>()
        .firstWhere((painter) => painter.dashedLanes.isNotEmpty);
    expect(targetPainter.previewRailColor, const Color(0xFFC69AFF));
    expect(
      find.descendant(
        of: find.byKey(const Key('rebase-conflict-current-row')),
        matching: find.text('feature · 현재 충돌'),
      ),
      findsOneWidget,
    );
    expect(find.text('충돌 해결 중'), findsOneWidget);
    expect(find.text('현재 적용 중'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('rebase-preview-applied-count')))
          .data,
      '0',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('rebase-preview-conflict-count')))
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('rebase-preview-pending-count')))
          .data,
      '0',
    );
    await tester.ensureVisible(
      find.byKey(const Key('preview-state-lib/shared.dart')),
    );
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    expect(find.text('현재 Git 작업을 마친 뒤 해결할 수 있습니다'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('rebase-conflict-continue')),
          )
          .onPressed,
      isNull,
    );
    expect(controller.previewPlacement, PreviewPlacement.right);
  });

  testWidgets('rebase conflict preview advances to the next conflict', (
    tester,
  ) async {
    final first = commit(
      'feature-one',
      'docs: update examples',
      parents: const ['root'],
    );
    final second = commit(
      'feature-two',
      'docs: publish guide',
      parents: const ['feature-one'],
    );
    final comparison = BranchComparisonResult(
      baseRef: 'main',
      compareRef: 'feature',
      baseTip: 'main-tip',
      compareTip: 'feature-two',
      baseParent: 'root',
      compareParent: 'feature-one',
      mergeBases: const ['root'],
      commits: [
        BranchComparisonCommit(
          commit: commit('main-tip', 'main only', parents: const ['root']),
          side: BranchCommitSide.baseOnly,
        ),
        BranchComparisonCommit(
          commit: second,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: first,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: commit('root', 'shared commit'),
          side: BranchCommitSide.commonBoundary,
        ),
      ],
      files: const [],
      merge: const MergeConflictCheck(status: MergeConflictStatus.clean),
    );
    late FakeGitRepository repository;
    late FakeRebasePreviewSession session;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'feature-two'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async {
            session = FakeRebasePreviewSession(
              repository,
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: 'main-tip',
                compareTip: 'feature-two',
                currentCommit: first,
                completed: 0,
                total: 2,
                conflictFiles: const ['lib/shared.dart'],
              ),
              continuations: [
                RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'main-tip',
                  compareTip: 'feature-two',
                  currentCommit: second,
                  completed: 1,
                  total: 2,
                  conflictFiles: const ['lib/guide.dart'],
                ),
                RebasePreviewResult(
                  status: RebasePreviewStatus.clean,
                  baseTip: 'main-tip',
                  compareTip: 'feature-two',
                  rewritten: [
                    (
                      original: first,
                      rewrittenSha: '1111111111111111111111111111111111111111',
                    ),
                    (
                      original: second,
                      rewrittenSha: '2222222222222222222222222222222222222222',
                    ),
                  ],
                  completed: 2,
                  total: 2,
                  virtualTip: '2222222222222222222222222222222222222222',
                ),
              ],
            );
            return session;
          },
      diffBetween: (_, _, _) async => const [],
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-preview-rebase')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.byKey(const Key('preview-state-lib/shared.dart')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('preview-content-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('preview-state-lib/shared.dart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rebase-conflict-use-compare')));
    await tester.pump();
    expect(session.resolvedChoices, [
      ('lib/shared.dart', RebaseConflictChoice.commit),
    ]);

    final continueButton = find.byKey(const Key('rebase-conflict-continue'));
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('진행 2/2'), findsOneWidget);
    expect(find.text('리베이스 진행 2/2'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('rebase-preview-applied-count')))
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('rebase-preview-pending-count')))
          .data,
      '0',
    );
    expect(find.text('docs: publish guide'), findsWidgets);
    expect(
      find.byKey(const Key('rebase-conflict-current-row')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('preview-content-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rebase-conflict-use-compare')));
    await tester.pump();
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('충돌 해결을 마쳤습니다'), findsOneWidget);
    expect(find.text('Rebase 가능'), findsOneWidget);
    expect(find.byKey(const Key('branch-preview-apply-card')), findsNothing);
    expect(find.byKey(const Key('branch-preview-apply')), findsOneWidget);
    expect(find.byKey(const Key('branch-preview-drop')), findsOneWidget);
  });

  testWidgets('a stale branch comparison cannot replace a newer selection', (
    tester,
  ) async {
    final first = Completer<BranchComparisonResult>();
    final second = Completer<BranchComparisonResult>();
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('normal', 'normal history')],
          refs: const RepoRefs(
            local: ['main', 'feature/a', 'feature/b'],
            current: 'main',
          ),
          compareBranchesCallback: (_, compare) => switch (compare) {
            'feature/a' => first.future,
            _ => second.future,
          },
          simulateRebaseCallback: ({required baseRef, required compareRef}) =>
              Future.value(
                const RebaseCheckResult(status: RebaseCheckStatus.clean),
              ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature/a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature/b')));
    await tester.pump();

    second.complete(
      branchComparison(
        compareRef: 'feature/b',
        compareTip: 'feature-b-tip',
        compareSubject: 'newer comparison',
      ),
    );
    await tester.pumpAndSettle();
    first.complete(
      branchComparison(
        compareRef: 'feature/a',
        compareTip: 'feature-a-tip',
        compareSubject: 'stale comparison',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('newer comparison'), findsOneWidget);
    expect(find.text('stale comparison'), findsNothing);
  });

  testWidgets('commit menu and drag open the same cherry-pick confirmation', (
    tester,
  ) async {
    final picked = <String>[];
    final repository = FakeGitRepository(
      (_, _) async => [
        commit(
          'main-tip',
          'main commit',
          parents: const ['root'],
          refs: const [GitRef(name: 'main', isHead: true)],
        ),
        commit(
          'source-tip',
          'source commit',
          parents: const ['root'],
          refs: const [GitRef(name: 'feature')],
        ),
        commit('root', 'root'),
      ],
      refs: const RepoRefs(
        local: ['main', 'feature'],
        current: 'main',
        tips: {'main': 'main-tip', 'feature': 'source-tip'},
      ),
      cherryPickCallback: (sha) async {
        picked.add(sha);
        return const CherryPickResult(
          outcome: CherryPickOutcome.applied,
          headSha: 'picked-head',
        );
      },
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('source commit'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 브랜치로 체리픽'));
    await tester.pumpAndSettle();
    expect(find.text('source-tip'), findsWidgets);
    expect(find.text('source commit'), findsWidgets);
    expect(find.text('main'), findsWidgets);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    final source = tester.getCenter(find.text('source commit'));
    final target = tester.getCenter(find.byKey(const Key('sidebar-row-main')));
    await tester.dragFrom(source, target - source);
    await tester.pumpAndSettle();
    expect(find.text('source-tip'), findsWidgets);
    expect(find.text('source commit'), findsWidgets);
    expect(find.text('main'), findsWidgets);
    await tester.tap(find.text('체리픽'));
    await tester.pumpAndSettle();
    expect(picked, ['source-tip']);
  });

  testWidgets('cherry-pick conflict panel restores and gates continue', (
    tester,
  ) async {
    var state = const CherryPickState(
      commitSha: 'source-tip',
      conflicts: ['lib/a.dart', 'lib/b.dart'],
    );
    var continued = false;
    var aborted = false;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('main-tip', 'main commit')],
          refs: const RepoRefs(local: ['main'], current: 'main'),
          loadCherryPickStateCallback: () async => state,
          continueCherryPickCallback: () async {
            continued = true;
            return const CherryPickResult(
              outcome: CherryPickOutcome.applied,
              headSha: 'continued-head',
            );
          },
          abortCherryPickCallback: () async => aborted = true,
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/b.dart'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cherry-pick-continue')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('cherry-pick-abort')));
    await tester.pumpAndSettle();
    expect(find.text('체리픽을 중단할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(aborted, isFalse);

    state = const CherryPickState(commitSha: 'source-tip', conflicts: []);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cherry-pick-continue')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('cherry-pick-continue')));
    await tester.pumpAndSettle();
    expect(continued, isTrue);
  });

  testWidgets('internal editor saves and stages only the resolved conflict', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('yogit_conflict_editor_');
    addTearDown(() => root.deleteSync(recursive: true));
    final login = File('${root.path}/lib/login_form.dart');
    login.createSync(recursive: true);
    login.writeAsStringSync('resolved\n');
    File(
      '${root.path}/lib/session_banner.dart',
    ).writeAsStringSync('still unresolved\n');
    late final WorkingTreeTextDocument document;
    await tester.runAsync(() async {
      document = await WorkingTreeTextDocument.load(
        repositoryRoot: root.path,
        relativePath: 'lib/login_form.dart',
      );
    });
    var state = const CherryPickState(
      commitSha: 'source-tip',
      conflicts: ['lib/login_form.dart', 'lib/session_banner.dart'],
    );
    final staged = <String>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('main-tip', 'main commit')],
      root: root.path,
      refs: const RepoRefs(local: ['main'], current: 'main'),
      loadCherryPickStateCallback: () async => state,
      stageResolvedFileCallback: (path) async {
        staged.add(path);
        state = const CherryPickState(
          commitSha: 'source-tip',
          conflicts: ['lib/session_banner.dart'],
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: controller,
          editorForTesting: const SizedBox.expand(),
          documentLoaderForTesting: (_) async => document,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cherry-pick-open-editor')));
    await tester.pumpAndSettle();
    expect(find.text('내장 에디터'), findsOneWidget);
    expect(find.text('외부 에디터'), findsOneWidget);
    await tester.tap(find.text('내장 에디터'));
    await tester.pumpAndSettle();
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '저장'),
    );
    await tester.runAsync(() async {
      save.onPressed!();
      for (var attempt = 0; attempt < 50 && staged.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(staged, ['lib/login_form.dart']);
    expect(staged, isNot(contains('lib/session_banner.dart')));
    expect(find.text('1개 충돌 파일'), findsOneWidget);
    expect(find.text('lib/session_banner.dart'), findsOneWidget);
  });

  testWidgets('a saved conflict with markers stays unresolved', (tester) async {
    final root = Directory.systemTemp.createTempSync('yogit_conflict_markers_');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/lib/login_form.dart');
    file.createSync(recursive: true);
    file.writeAsStringSync('<<<<<<< HEAD\nmain\n=======\nsource\n>>>>>>>\n');
    late final WorkingTreeTextDocument document;
    await tester.runAsync(() async {
      document = await WorkingTreeTextDocument.load(
        repositoryRoot: root.path,
        relativePath: 'lib/login_form.dart',
      );
    });
    final attempted = <String>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('main-tip', 'main commit')],
      root: root.path,
      refs: const RepoRefs(local: ['main'], current: 'main'),
      loadCherryPickStateCallback: () async => const CherryPickState(
        commitSha: 'source-tip',
        conflicts: ['lib/login_form.dart'],
      ),
      stageResolvedFileCallback: (path) async {
        attempted.add(path);
        throw GitRepositoryException(path, '충돌 표시가 남아 있습니다.');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: controller,
          editorForTesting: const SizedBox.expand(),
          documentLoaderForTesting: (_) async => document,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cherry-pick-open-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내장 에디터'));
    await tester.pumpAndSettle();
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '저장'),
    );
    await tester.runAsync(() async {
      save.onPressed!();
      for (var attempt = 0; attempt < 50 && attempted.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(attempted, ['lib/login_form.dart']);
    expect(find.textContaining('충돌 표시가 남아 있습니다'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('해결 필요'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cherry-pick-continue')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('tags show the newest ten and filtering reveals hidden matches', (
    tester,
  ) async {
    final tags = [for (var index = 1; index <= 12; index++) 'release/v$index'];
    final tagCreatorTimes = {
      for (var index = 1; index <= 12; index++) 'release/v$index': index * 100,
    };
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: RepoRefs(tags: tags, tagCreatorTimes: tagCreatorTimes),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar-ref-release/v12')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-ref-release/v3')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-ref-release/v2')), findsNothing);
    expect(find.byKey(const Key('sidebar-ref-release/v1')), findsNothing);
    expect(find.text('나머지 2개'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-tags-overflow')));
    await tester.pump();
    final sidebarList = find.descendant(
      of: find.byKey(const Key('sidebar')),
      matching: find.byType(ListView),
    );
    final sidebarScrollable = find.descendant(
      of: sidebarList,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('sidebar-ref-release/v1')),
      80,
      scrollable: sidebarScrollable,
    );
    expect(find.byKey(const Key('sidebar-ref-release/v1')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sidebar-tags-overflow')),
      80,
      scrollable: sidebarScrollable,
    );
    expect(find.text('태그 접기'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-tags-overflow')));
    await tester.pump();
    expect(find.byKey(const Key('sidebar-ref-release/v1')), findsNothing);

    await tester.enterText(find.byKey(const Key('ref-filter')), 'v1');
    await tester.pump();
    for (final index in [1, 10, 11, 12]) {
      expect(find.byKey(Key('sidebar-ref-release/v$index')), findsOneWidget);
    }
    expect(find.byKey(const Key('sidebar-tags-overflow')), findsNothing);

    await tester.enterText(find.byKey(const Key('ref-filter')), '');
    await tester.pump();
    expect(find.byKey(const Key('sidebar-ref-release/v1')), findsNothing);
    expect(find.text('나머지 2개'), findsOneWidget);
  });

  testWidgets(
    'selected row keeps normal ref chip styling and marks HEAD and tags',
    (tester) async {
      await tester.pumpWidget(
        app(
          FakeGitRepository(
            (_, _) async => [
              commit('3', 'head commit'),
              commit(
                'tagged',
                'tagged commit',
                refs: const [GitRef(name: 'v1.0', isTag: true)],
              ),
            ],
          ),
          controller,
        ),
      );
      await tester.pumpAndSettle();

      Color chipColor(Key key) =>
          (tester.widget<Container>(find.byKey(key)).decoration!
                  as BoxDecoration)
              .color!;

      const mainKey = Key('ref-chip-3-main');
      const tagKey = Key('ref-chip-tagged-v1.0');
      final mainWhileSelected = chipColor(mainKey);
      final tagWhileUnselected = chipColor(tagKey);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(chipColor(mainKey), mainWhileSelected);
      expect(chipColor(tagKey), tagWhileUnselected);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('◇'), findsOneWidget);
    },
  );

  testWidgets('ref chip and graph use the same palette text color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'tip')],
            refs: const RepoRefs(
              local: ['d'],
              current: 'd',
              tips: {'d': 'tip'},
            ),
          ),
          controller: controller,
          refPalette: AppSettings.defaultRefPalette,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final decoration =
        tester
                .widget<Container>(find.byKey(const Key('ref-chip-tip-d')))
                .decoration!
            as BoxDecoration;
    expect(decoration.color, const Color(0xFF1D76DB).withValues(alpha: .18));
    expect(
      decoration.border!.top.color,
      const Color(0xFF68A7EA).withValues(alpha: .30),
    );
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.committerColor, const Color(0xFF68A7EA));
  });

  testWidgets('preview describes the working tree row and counts files', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 3,
              deletions: 1,
            ),
            GitFileChange(
              path: 'lib/b.dart',
              status: 'A',
              additions: 5,
              deletions: 0,
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The status bar legend carries the other 'WIP' label.
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-panel')),
        matching: find.text('WIP'),
      ),
      findsOneWidget,
    );
    expect(find.text('Working tree changes'), findsOneWidget);
    expect(find.text('Not committed'), findsOneWidget);
    expect(find.text('No commit object or committer'), findsOneWidget);
    expect(find.text('2 files changed'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);

    BoxDecoration? chip(String path) =>
        tester
                .widget<Container>(find.byKey(Key('preview-state-$path')))
                .decoration
            as BoxDecoration?;
    expect(chip('lib/a.dart'), isNull);
    expect(chip('lib/b.dart'), isNull);
    expect(
      fileStateChipColor('D').background,
      const Color(0xFFF29AB2).withValues(alpha: 0.2),
    );
    expect(fileStateChipColor('R100').letter, const Color(0xFFB6A0EA));
  });

  testWidgets('preview diff uses compact full diff rows without git headers', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 1,
              deletions: 1,
            ),
          ],
          diff: (_, _, _, _, _) async => const [
            DiffLine(kind: DiffLineKind.header, text: 'diff --git a/x b/x'),
            DiffLine(kind: DiffLineKind.header, text: 'index 1234567..89abcde'),
            DiffLine(kind: DiffLineKind.header, text: '--- a/lib/a.dart'),
            DiffLine(kind: DiffLineKind.header, text: '+++ b/lib/a.dart'),
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.delete, text: 'old line', oldNumber: 1),
            DiffLine(kind: DiffLineKind.add, text: 'new line', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // 'N file changed' is singular for one file.
    expect(find.text('1 file changed'), findsOneWidget);
    expect(find.text('1 files changed'), findsNothing);

    await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
    await tester.pumpAndSettle();
    final diff = find.byKey(const Key('preview-diff'));
    expect(find.byType(UnifiedPresentationView), findsOneWidget);
    expect(find.byKey(const Key('unified-line-0-0')), findsOneWidget);
    expect(find.byKey(const Key('unified-line-0-1')), findsOneWidget);
    expect(
      find.descendant(of: diff, matching: find.text('@@ -1 +1 @@')),
      findsNothing,
    );
    expect(
      find.descendant(of: diff, matching: find.text('old line')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: diff, matching: find.text('new line')),
      findsOneWidget,
    );
    for (final header in [
      'diff --git a/x b/x',
      'index 1234567..89abcde',
      '--- a/lib/a.dart',
      '+++ b/lib/a.dart',
    ]) {
      expect(find.textContaining(header), findsNothing);
    }
  });

  testWidgets('an open preview follows the keyboard selection', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('preview-panel'));
    expect(
      find.descendant(of: preview, matching: find.text('first commit')),
      findsOneWidget,
    );
    // The person block grew with every other avatar.
    expect(
      tester
          .widgetList<IdentityAvatar>(
            find.descendant(of: preview, matching: find.byType(IdentityAvatar)),
          )
          .map((avatar) => avatar.size),
      contains(42.0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: preview, matching: find.text('second commit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text('first commit')),
      findsNothing,
    );
  });

  test('lane colors round-trip, and a damaged palette falls back', () {
    expect(AvatarService.defaultColors, hasLength(8));
    expect(AvatarService.defaultColors.first, const Color(0xFFFF2D95));
    expect(AvatarService.defaultColors.last, const Color(0xFFFF3131));
    expect(AppSettings.defaultLaneColors.first, '#FF2D95');
    expect(parseHexColor('#39C5CF'), const Color(0xFF39C5CF));
    expect(parseHexColor('39c5cf'), const Color(0xFF39C5CF));
    expect(parseHexColor('#39C5C'), isNull);
    expect(parseHexColor('teal'), isNull);

    const custom = AppSettings(
      baseBranchColor: '#112233',
      laneColors: ['#445566', '#778899'],
    );
    final decoded = AppSettings.fromJson(custom.toJson());
    expect(decoded, custom);
    expect(decoded.baseBranchColorValue, const Color(0xFF112233));
    expect(decoded.laneColorValues, const [
      Color(0xFF445566),
      Color(0xFF778899),
    ]);
    expect(
      AppSettings.fromJson(const {'baseBranchColor': 'bad'}).baseBranchColor,
      AppSettings.defaultBaseBranchColor,
    );
    expect(
      AppSettings.fromJson(const {}).baseBranchColor,
      AppSettings.defaultBaseBranchColor,
    );

    // One bad entry drops the whole palette back to GitHub dark.
    for (final stored in [
      <String>['#112233', 'oops'],
      <String>[],
      'red',
    ]) {
      expect(
        AppSettings.fromJson(<String, dynamic>{
          'laneColors': stored,
        }).laneColors,
        AppSettings.defaultLaneColors,
        reason: '$stored',
      );
    }
    expect(
      const AppSettings(laneColors: ['bad']).laneColorValues,
      AvatarService.defaultColors,
    );

    // A settings file still carrying the previous default never chose it, so it
    // migrates to the new one — case does not matter.
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'laneColors': [
          '#f85149',
          '#db6d28',
          '#d29922',
          '#3fb950',
          '#39c5cf',
          '#58a6ff',
          '#bc8cff',
          '#f778ba',
        ],
      }).laneColors,
      AppSettings.defaultLaneColors,
    );
    // An edited palette is preserved, even when it reuses an old color.
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'laneColors': ['#F85149', '#00FF00'],
      }).laneColors,
      ['#F85149', '#00FF00'],
    );
    expect(
      AppSettings.fromJson(<String, dynamic>{}).laneColors,
      AppSettings.defaultLaneColors,
    );
  });

  test('branch tag palette round-trips and rejects damaged records', () {
    expect(AppSettings.refPaletteNumbers, const [1, 3, 4, 5, 6, 7, 8, 9]);
    expect(AppSettings.defaultRefPalette, const [
      (base: '#0E8A16', text: '#18E022'),
      (base: '#C5DEF5', text: '#C2DDF4'),
      (base: '#1D76DB', text: '#68A7EA'),
      (base: '#5319E7', text: '#DACFFA'),
      (base: '#B51D68', text: '#FF2D95'),
      (base: '#008FA3', text: '#00E5FF'),
      (base: '#B89B00', text: '#FFF01F'),
      (base: '#C94E10', text: '#FF6E27'),
    ]);
    expect(AppSettings.defaultRefPaletteAssignments, const [
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

    const custom = AppSettings(
      refPalette: [
        (base: '#010203', text: '#A0B0C0'),
        (base: '#111213', text: '#D0E0F0'),
        (base: '#212223', text: '#102030'),
        (base: '#313233', text: '#405060'),
        (base: '#414243', text: '#708090'),
        (base: '#515253', text: '#8090A0'),
        (base: '#616263', text: '#90A0B0'),
        (base: '#717273', text: '#A0B0C0'),
      ],
      refPaletteAssignments: [1, 2, 0, 4, 0, 0, 0, 9],
    );
    expect(AppSettings.fromJson(custom.toJson()), custom);
    expect(custom.refPaletteColorValues.first, (
      base: const Color(0xFF010203),
      text: const Color(0xFFA0B0C0),
    ));

    for (final stored in [
      <Object>[],
      [
        const {'base': '#112233', 'text': 'bad'},
      ],
      [
        const {'base': '#112233', 'text': '#445566'},
        const {'base': '#112233', 'text': '#445566'},
        const {'base': '#112233', 'text': '#445566'},
        const {'base': '#112233', 'text': '#445566'},
      ],
    ]) {
      expect(
        AppSettings.fromJson({'refPalette': stored}).refPalette,
        AppSettings.defaultRefPalette,
      );
    }

    expect(
      AppSettings.fromJson({
        'refPaletteAssignments': [1, 2, 2, 0, 0, 0, 0, 0],
      }).refPaletteAssignments,
      AppSettings.defaultRefPaletteAssignments,
    );

    const legacy = [
      {'base': '#010101', 'text': '#111111'},
      {'base': '#020202', 'text': '#222222'},
      {'base': '#030303', 'text': '#333333'},
      {'base': '#040404', 'text': '#444444'},
      {'base': '#050505', 'text': '#555555'},
    ];
    final migrated = AppSettings.fromJson({'refPalette': legacy});
    expect(migrated.refPalette, [
      const (base: '#040404', text: '#444444'),
      const (base: '#030303', text: '#333333'),
      const (base: '#010101', text: '#111111'),
      const (base: '#050505', text: '#555555'),
      ...AppSettings.defaultRefPalette.skip(4),
    ]);
    expect(
      migrated.refPaletteAssignments,
      AppSettings.defaultRefPaletteAssignments,
    );
  });

  test('base branches round-trip per repository', () {
    const settings = AppSettings(
      baseBranches: {'/repos/one': 'main', '/repos/two': 'release'},
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(AppSettings.fromJson(const {}).baseBranches, isEmpty);
    expect(
      AppSettings.fromJson({
        'baseBranches': {'/repos/one': 'main', '/repos/bad': 42},
      }).baseBranches,
      {'/repos/one': 'main'},
    );
  });

  test('a settings file with retired keys still loads', () {
    // Settings files written before a feature was removed keep its key, so an
    // unknown key is ignored rather than fatal.
    expect(
      AppSettings.fromJson({
        'verificationCommands': {'/repos/a': 'make check'},
        'baseBranches': {'/repos/one': 'main'},
      }),
      const AppSettings(baseBranches: {'/repos/one': 'main'}),
    );
  });

  test('commit message templates fill their variables in', () {
    expect(
      renderCommitMessageTemplate(
        AppSettings.defaultMergeMessageTemplate,
        source: 'fix/docs',
        target: 'main',
        profile: '채수원',
      ),
      "Merge branch 'fix/docs' into main\n\nReviewed-by: 채수원",
    );
    // 이름이 없으면 그 줄과 위의 빈 줄까지 사라진다 — 'Reviewed-by:'만 남는 편이 나쁘다.
    expect(
      renderCommitMessageTemplate(
        AppSettings.defaultMergeMessageTemplate,
        source: 'fix/docs',
        target: 'main',
      ),
      "Merge branch 'fix/docs' into main",
    );
    // 비운 템플릿은 git 표준 메시지다.
    expect(
      renderCommitMessageTemplate(
        '   \n',
        source: 'fix/docs',
        target: 'main',
        profile: '채수원',
      ),
      "Merge branch 'fix/docs' into main",
    );
    // 모르는 변수는 손대지 않는다.
    expect(
      renderCommitMessageTemplate(
        '{source} → {target} ({ticket})',
        source: 'fix/docs',
        target: 'main',
      ),
      'fix/docs → main ({ticket})',
    );
    // 본문 가운데서 사라진 줄도 빈 줄을 겹쳐 남기지 않는다.
    final middle = renderCommitMessageTemplate(
      'Subject\n\nReviewed-by: {profile}\n\nCo-authored-by: 이수린',
      source: 'fix/docs',
      target: 'main',
    );
    expect(middle, 'Subject\n\nCo-authored-by: 이수린');
    expect(middle, isNot(contains('\n\n\n')));
  });

  test('commit message templates round-trip, empty one included', () {
    const settings = AppSettings(
      mergeMessageTemplate: "Merge '{source}'\n\nReviewed-by: {profile}",
      rebaseMergeMessageTemplate: '',
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSettings.fromJson(const {}).mergeMessageTemplate,
      AppSettings.defaultMergeMessageTemplate,
    );
    expect(
      AppSettings.fromJson(const {
        'rebaseMergeMessageTemplate': 42,
      }).rebaseMergeMessageTemplate,
      AppSettings.defaultMergeMessageTemplate,
    );
  });

  test('recent repositories round-trip newest first, capped and deduped', () {
    const settings = AppSettings(
      recentRepositories: ['/repos/one', '/repos/two'],
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(AppSettings.fromJson(const {}).recentRepositories, isEmpty);
    expect(
      AppSettings.fromJson({
        'recentRepositories': ['/repos/one', 42, '  ', '/repos/one'],
      }).recentRepositories,
      ['/repos/one'],
    );

    // Reopening moves an entry back to the head instead of duplicating it.
    expect(settings.withRecentRepository('/repos/two').recentRepositories, [
      '/repos/two',
      '/repos/one',
    ]);
    expect(settings.withoutRecentRepository('/repos/one').recentRepositories, [
      '/repos/two',
    ]);
    expect(settings.withRecentRepository('  '), same(settings));

    var capped = const AppSettings();
    for (var i = 0; i <= AppSettings.maxRecentRepositories; i++) {
      capped = capped.withRecentRepository('/repos/$i');
    }
    expect(
      capped.recentRepositories,
      hasLength(AppSettings.maxRecentRepositories),
    );
    expect(capped.recentRepositories.first, '/repos/10');
    expect(capped.recentRepositories, isNot(contains('/repos/0')));
  });

  test('deleted branch names round-trip per repository', () {
    const settings = AppSettings(
      deletedBranchNames: {
        '/repos/one': {'tip-a': 'feature/one'},
        '/repos/two': {'tip-b': 'fix/two'},
      },
    );

    expect(AppSettings.fromJson(settings.toJson()), settings);
  });

  test('deleted branch names ignore malformed nested entries', () {
    expect(
      AppSettings.fromJson({
        'deletedBranchNames': {
          '/repos/one': {'tip-a': 'feature/one', 'bad': 42},
          '/repos/bad': 'not-a-map',
        },
      }).deletedBranchNames,
      {
        '/repos/one': {'tip-a': 'feature/one'},
      },
    );
  });

  test('timeline theme settings round-trip and reject unknown values', () {
    const settings = AppSettings(timelineTheme: TimelineThemeKind.carbon);
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(settings.toJson()['timelineTheme'], 'carbon');
    expect(
      AppSettings.fromJson(const {}).timelineTheme,
      TimelineThemeKind.systemGraphite,
    );
    expect(
      AppSettings.fromJson(const {'timelineTheme': 'sepia'}).timelineTheme,
      TimelineThemeKind.systemGraphite,
    );

    final changed = settings.copyWith(
      timelineTheme: TimelineThemeKind.warmGraphite,
    );
    expect(changed.timelineTheme, TimelineThemeKind.warmGraphite);
    expect(changed.copyWith(), changed);
  });

  test('branch preview mode defaults to merge and restores rebase', () {
    expect(const AppSettings().branchPreviewMode, BranchPreviewMode.merge);
    const settings = AppSettings(branchPreviewMode: BranchPreviewMode.rebase);
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSettings.fromJson(const {
        'branchPreviewMode': 'unknown',
      }).branchPreviewMode,
      BranchPreviewMode.merge,
    );
  });

  test('rebase mapping colors keep the compare hue and step darker', () {
    const branchColor = Color(0xFF16CBE7);
    final colors = rebaseMappingColors(branchColor);
    final source = HSLColor.fromColor(branchColor);
    final hsl = colors.map(HSLColor.fromColor).toList();

    expect(colors, hasLength(5));
    expect(
      hsl.map((color) => color.hue),
      everyElement(closeTo(source.hue, 0.5)),
    );
    expect(hsl.first.saturation, lessThan(source.saturation));
    expect(hsl.first.lightness, greaterThan(source.lightness));
    for (var index = 1; index < hsl.length; index++) {
      expect(hsl[index].saturation, lessThan(hsl[index - 1].saturation));
      expect(hsl[index].lightness, lessThan(hsl[index - 1].lightness));
    }
  });

  test('rebase mapping lines are one pixel with no outline or gaps', () async {
    final rows = [
      for (var index = 0; index < 3; index++)
        graphRow(
          commit: commit('row-$index', 'row $index'),
          lane: 0,
          activeLanes: const [0],
          nextLanes: const [0],
        ),
    ];
    const mappingColor = Color(0xFF547C68);
    final painter = RebaseMappingPainter(
      rows: rows,
      mappings: const [
        (
          originalSha: 'row-2',
          rewrittenSha: 'row-0',
          originalRow: 2,
          rewrittenRow: 0,
          routeLane: 0,
          color: mappingColor,
        ),
      ],
      rowIndex: 1,
      laneSpacing: 30.5,
      compact: false,
    );
    const width = 100;
    const height = 36;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(100, 36));
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    int alphaAt(int x, int y) => bytes!.getUint8((y * width + x) * 4 + 3);

    // routeX is 58.5: the 1px stroke occupies x=58 only.
    expect(alphaAt(57, height ~/ 2), 0);
    expect(alphaAt(58, 0), greaterThan(0));
    expect(alphaAt(58, height - 1), greaterThan(0));
  });

  test('rebase mapping routes use half the commit lane spacing', () async {
    final rows = [
      for (var index = 0; index < 3; index++)
        graphRow(
          commit: commit('row-$index', 'row $index'),
          lane: 0,
          activeLanes: const [0],
          nextLanes: const [0],
        ),
    ];
    final painter = RebaseMappingPainter(
      rows: rows,
      mappings: const [
        (
          originalSha: 'row-2',
          rewrittenSha: 'row-0',
          originalRow: 2,
          rewrittenRow: 0,
          routeLane: 0,
          color: Color(0xFFFF0000),
        ),
        (
          originalSha: 'row-2',
          rewrittenSha: 'row-0',
          originalRow: 2,
          rewrittenRow: 0,
          routeLane: 1,
          color: Color(0xFF00FF00),
        ),
      ],
      rowIndex: 1,
      laneSpacing: 30.5,
      compact: false,
    );
    const width = 100;
    const height = 36;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(100, 36));
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    int alphaAt(int x) => bytes!.getUint8(((height ~/ 2) * width + x) * 4 + 3);

    expect(alphaAt(58), greaterThan(0));
    expect(alphaAt(73), greaterThan(0));
    expect(alphaAt(89), 0);
  });

  test(
    'narrow rebase mapping paints only the focused route inside its width',
    () async {
      final rows = [
        for (var index = 0; index < 6; index++)
          graphRow(
            commit: commit('row-$index', 'row $index'),
            lane: 0,
            activeLanes: const [0],
            nextLanes: const [0],
          ),
      ];
      final selectedIndex = ValueNotifier(1);
      final painter = RebaseMappingPainter(
        rows: rows,
        entries: [
          for (var index = 0; index < rows.length; index++)
            (rowIndex: index, label: null, row: rows[index]),
        ],
        selectedIndex: selectedIndex,
        mappings: const [
          (
            originalSha: 'row-5',
            rewrittenSha: 'row-0',
            originalRow: 5,
            rewrittenRow: 0,
            routeLane: 0,
            color: Color(0xFFFF0000),
          ),
          (
            originalSha: 'row-4',
            rewrittenSha: 'row-1',
            originalRow: 4,
            rewrittenRow: 1,
            routeLane: 1,
            color: Color(0xFF00FF00),
          ),
          (
            originalSha: 'row-3',
            rewrittenSha: 'row-2',
            originalRow: 3,
            rewrittenRow: 2,
            routeLane: 2,
            color: Color(0xFF0000FF),
          ),
        ],
        rowIndex: 2,
        laneSpacing: 30.5,
        compact: false,
      );
      const imageWidth = 100;
      const paintWidth = 70;
      const height = 36;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(70, 36));
      final image = await recorder.endRecording().toImage(imageWidth, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      int channelAt(int x, int channel) =>
          bytes!.getUint8(((height ~/ 2) * imageWidth + x) * 4 + channel);

      expect(channelAt(58, 1), greaterThan(channelAt(58, 0)));
      for (var x = paintWidth; x < imageWidth; x++) {
        expect(channelAt(x, 3), 0);
      }
    },
  );

  test('rebase mapping repaints when the focused commit changes', () {
    final rows = [
      graphRow(
        commit: commit('row-0', 'row 0'),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
      ),
    ];
    final selectedIndex = ValueNotifier(0);
    final painter = RebaseMappingPainter(
      rows: rows,
      entries: [(rowIndex: 0, label: null, row: rows.single)],
      selectedIndex: selectedIndex,
      mappings: const [],
      rowIndex: 0,
      laneSpacing: 30.5,
      compact: false,
    );
    var repaints = 0;
    void listener() => repaints++;
    painter.addListener(listener);

    selectedIndex.value = 1;

    expect(repaints, 1);
    painter.removeListener(listener);
  });

  test('rebase mapping arrowhead is an open one-pixel chevron', () async {
    final rows = [
      for (var index = 0; index < 3; index++)
        graphRow(
          commit: commit('row-$index', 'row $index'),
          lane: 0,
          activeLanes: const [0],
          nextLanes: const [0],
        ),
    ];
    final painter = RebaseMappingPainter(
      rows: rows,
      mappings: const [
        (
          originalSha: 'row-2',
          rewrittenSha: 'row-0',
          originalRow: 2,
          rewrittenRow: 0,
          routeLane: 0,
          color: Color(0xFF547C68),
        ),
      ],
      rowIndex: 0,
      laneSpacing: 30.5,
      compact: false,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(100, 36));
    final image = await recorder.endRecording().toImage(100, 36);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    int alphaAt(int x, int y) => bytes!.getUint8((y * 100 + x) * 4 + 3);

    expect(alphaAt(42, 15), greaterThan(0));
    expect(alphaAt(43, 16), 0);
    expect(alphaAt(42, 21), greaterThan(0));
  });

  test(
    'comparison target branch bends at the common parent in its own color',
    () {
      final rows = layoutBranchComparison(branchComparison().commits);
      final target = rows.singleWhere((row) => row.commit.sha == 'feature-tip');
      final transition = target.transitions.single;

      expect(target.parentLanes, [0]);
      expect(CommitGraphPainter.isMergeEdge(target, transition), isFalse);
      expect(CommitGraphPainter.transitionBranch(target, transition), 1);
    },
  );

  test('common parent keeps the base rail when the other branch joins', () {
    final comparison = branchComparison();
    final olderBase = commit(
      'older-main',
      'older main commit',
      parents: const ['root'],
    );
    final rows = layoutBranchComparison([
      comparison.commits.first,
      comparison.commits[1],
      BranchComparisonCommit(
        commit: olderBase,
        side: BranchCommitSide.baseOnly,
      ),
      comparison.commits.last,
    ]);
    final olderBaseRow = rows.singleWhere(
      (row) => row.commit.sha == olderBase.sha,
    );
    final commonRow = rows.singleWhere((row) => row.commit.sha == 'root');
    final commonPainter = CommitGraphPainter(
      row: commonRow,
      previous: olderBaseRow,
      selected: false,
      committerColor: const Color(0xFF7AD6E8),
    );

    expect(CommitGraphPainter.railsBelow(olderBaseRow), contains(0));
    expect(commonPainter.laneVerticals(const Size(168, 36))[0]!.top, 0);
  });

  test('merge preview keeps each parent edge dashed until its parent node', () {
    final graph = layoutMergePreviewGraph(branchComparison());
    final targetIndex = graph.rows.indexWhere(
      (row) => row.commit.sha == 'feature-tip',
    );
    final targetLane = graph.rows[targetIndex].lane;

    for (var index = 0; index < targetIndex; index++) {
      expect(graph.dashedLanes[index], contains(targetLane));
    }
    expect(graph.dashedLanes[targetIndex], isNot(contains(targetLane)));
  });

  test('preview graph adds virtual merge and rewritten rebase commits', () {
    final comparison = branchComparison();
    final merge = layoutMergePreviewGraph(comparison);
    expect(
      merge.kinds[merge.rows.first.commit.sha],
      PreviewGraphNodeKind.virtualMerge,
    );
    expect(merge.rows.first.commit.parents, ['main-tip', 'feature-tip']);
    expect(merge.dashedLanes.values.expand((lanes) => lanes), isNotEmpty);

    final feature = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final compareRow = layoutBranchComparison(
      comparison.commits,
    ).singleWhere((row) => row.commit.sha == comparison.compareTip);
    final colors = rebaseMappingColors(
      AvatarService.branchColor(compareRow.branch),
    );
    final rebase = layoutRebasePreviewGraph(
      comparison,
      RebasePreviewResult(
        status: RebasePreviewStatus.clean,
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
        rewritten: [(original: feature, rewrittenSha: 'rewritten-feature')],
        completed: 1,
        total: 1,
        virtualTip: 'rewritten-feature',
      ),
    );
    expect(
      rebase.kinds['rewritten-feature'],
      PreviewGraphNodeKind.virtualRebase,
    );
    expect(rebase.mappings.single.originalSha, feature.sha);
    expect(rebase.mappings.single.rewrittenSha, 'rewritten-feature');
    expect(rebase.mappings.single.color, colors.first);
    expect(rebase.mappings.single.routeLane, 0);

    final baseTipIndex = rebase.rows.indexWhere(
      (row) => row.commit.sha == comparison.baseTip,
    );
    final originalIndex = rebase.rows.indexWhere(
      (row) => row.commit.sha == feature.sha,
    );
    final originalLane = rebase.rows[originalIndex].lane;
    final originalPainter = CommitGraphPainter(
      row: rebase.rows[originalIndex],
      previous: rebase.rows[originalIndex - 1],
      selected: false,
      committerColor: AvatarService.branchColor(originalLane),
    );
    expect(rebase.rows[baseTipIndex].nextLanes, isNot(contains(originalLane)));
    expect(originalPainter.continuesFromAbove(originalLane), isFalse);

    final olderBase = commit(
      'older-main',
      'older main commit',
      parents: const ['root'],
    );
    final interleavedComparison = BranchComparisonResult(
      baseRef: comparison.baseRef,
      compareRef: comparison.compareRef,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      baseParent: olderBase.sha,
      compareParent: comparison.compareParent,
      mergeBases: comparison.mergeBases,
      commits: [
        comparison.commits.first,
        comparison.commits[1],
        BranchComparisonCommit(
          commit: olderBase,
          side: BranchCommitSide.baseOnly,
        ),
        comparison.commits.last,
      ],
      files: comparison.files,
      merge: comparison.merge,
    );
    final interleaved = layoutRebasePreviewGraph(
      interleavedComparison,
      RebasePreviewResult(
        status: RebasePreviewStatus.clean,
        baseTip: interleavedComparison.baseTip,
        compareTip: interleavedComparison.compareTip,
        rewritten: [(original: feature, rewrittenSha: 'interleaved-rewrite')],
        completed: 1,
        total: 1,
        virtualTip: 'interleaved-rewrite',
      ),
    );
    final olderBaseRow = interleaved.rows.singleWhere(
      (row) => row.commit.sha == olderBase.sha,
    );
    expect(olderBaseRow.activeLanes, contains(originalLane));
  });

  test('rebase conflict keeps only a virtual target above the base tip', () {
    final comparison = branchComparison();
    final feature = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final graph = layoutRebasePreviewGraph(
      comparison,
      RebasePreviewResult(
        status: RebasePreviewStatus.conflict,
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
        currentCommit: feature,
        rewritten: [(original: feature, rewrittenSha: 'completed-rewrite')],
        completed: 1,
        total: 2,
        conflictFiles: const ['lib/shared.dart'],
      ),
    );

    expect(graph.rows, hasLength(comparison.commits.length + 1));
    expect(
      graph.kinds[graph.rows.first.commit.sha],
      PreviewGraphNodeKind.conflictTarget,
    );
    expect(graph.rows.first.lane, graph.rows[1].lane);
    expect(graph.rows.first.commit.subject, 'main HEAD 위 예상 위치');
    expect(graph.dashedLanes[0], contains(graph.rows.first.lane));
    expect(
      graph.kinds.values,
      isNot(contains(PreviewGraphNodeKind.virtualRebase)),
    );
    expect(graph.mappings, isEmpty);
  });

  test('the rebase preview graph adds the merge commit only when selected', () {
    final comparison = branchComparison();
    final feature = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: feature, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    );
    final plain = layoutRebasePreviewGraph(comparison, preview);
    expect(
      plain.kinds.values,
      isNot(contains(PreviewGraphNodeKind.virtualRebaseMerge)),
    );

    final landed = layoutRebasePreviewGraph(
      comparison,
      preview,
      mergeCommit: true,
    );
    final merge = landed.rows.first;
    expect(landed.rows, hasLength(plain.rows.length + 1));
    expect(
      landed.kinds[merge.commit.sha],
      PreviewGraphNodeKind.virtualRebaseMerge,
    );
    // 가상 머지는 기준 브랜치 레인 맨 위에 앉고, 재배치된 커밋은 그 옆 레인이다.
    final rebased = landed.rows[1];
    final baseLane = landed.rows[2].lane;
    expect(merge.lane, baseLane);
    expect(rebased.commit.sha, 'rewritten-feature');
    expect(rebased.lane, baseLane + 1);
    expect(landed.rows[2].commit.sha, comparison.baseTip);
    expect(merge.commit.parents, [comparison.baseTip, 'rewritten-feature']);
    expect(merge.commit.subject, "Merge branch 'feature' into main");
    expect(merge.commit.shortSha, 'new SHA');
    // 첫 부모는 기준 브랜치 레인을 따라 HEAD까지 곧게, 두 번째 부모는 옆 레인의
    // 재배치 tip으로 꺾어 나간다.
    expect(merge.parentLanes, [baseLane, rebased.lane]);
    expect(merge.nextLaneShas[baseLane], comparison.baseTip);
    expect(merge.nextLaneShas[rebased.lane], 'rewritten-feature');
    expect(merge.transitions, [
      (from: baseLane, to: rebased.lane, sha: 'rewritten-feature'),
    ]);
    expect(CommitGraphPainter.railsBelow(merge), contains(baseLane));
    // 체인의 뿌리는 기준 브랜치 HEAD 노드로 들어간다: 옆 레인을 타고 내려와
    // HEAD 줄에서 옆으로 꺾이는 곡선이라 출발점에서 꺾이지 않는다.
    final root = (from: rebased.lane, to: baseLane, sha: comparison.baseTip);
    expect(rebased.transitions, [root]);
    expect(rebased.parentLanes, [baseLane]);
    expect(CommitGraphPainter.isMergeEdge(rebased, root), isFalse);
    // 점선은 가상 머지 줄까지 이어지고 매핑 행 번호도 한 칸씩 밀린다.
    expect(landed.dashedLanes[0], {baseLane, rebased.lane});
    expect(landed.dashedLanes[1], {baseLane, rebased.lane});
    expect(landed.dashedLanes[2], isNull);
    expect(
      landed.mappings.single.originalRow,
      plain.mappings.single.originalRow + 1,
    );
    expect(
      landed.mappings.single.rewrittenRow,
      plain.mappings.single.rewrittenRow + 1,
    );

    // 'Rebase만'은 현행 그림대로 기준 브랜치 레인 위에 인라인으로 이어지고, 그 레인의
    // 점선이 그대로 HEAD 노드로 내려간다 — 꺾을 것이 없으니 뿌리 전환도 없다.
    final plainRebased = plain.rows.first;
    expect(plainRebased.commit.sha, 'rewritten-feature');
    expect(plainRebased.lane, baseLane);
    expect(plainRebased.transitions, isEmpty);
    expect(plainRebased.activeLanes, [baseLane]);
    expect(plainRebased.nextLanes, [baseLane]);
    expect(plainRebased.nextLaneShas[baseLane], comparison.baseTip);
    expect(plain.dashedLanes[0], {baseLane});
    expect(plain.dashedLanes[1], isNull);
    expect(plain.rows[1].commit.sha, comparison.baseTip);
    expect(
      CommitGraphPainter(
        row: plain.rows[1],
        previous: plainRebased,
        selected: false,
        committerColor: const Color(0xFF7AD6E8),
      ).continuesFromAbove(baseLane),
      isTrue,
    );
  });

  test(
    'a rebase chain crossing original rows still lands on the base HEAD',
    () {
      // 원본 커밋이 기준 브랜치 HEAD보다 위에 남는 배치. 체인은 그 줄들을 한 칸
      // 비켜 지나가고 HEAD 바로 윗줄에서 꺾인다.
      final base = commit('main-tip', 'main only', parents: const ['root']);
      final newer = commit(
        'feature-new',
        'newer feature',
        parents: const ['1'],
      );
      final older = commit(
        'feature-old',
        'older feature',
        parents: const ['root'],
      );
      final comparison = BranchComparisonResult(
        baseRef: 'main',
        compareRef: 'feature',
        baseTip: base.sha,
        compareTip: newer.sha,
        baseParent: 'root',
        compareParent: older.sha,
        mergeBases: const ['root'],
        commits: [
          BranchComparisonCommit(
            commit: newer,
            side: BranchCommitSide.compareOnly,
          ),
          BranchComparisonCommit(commit: base, side: BranchCommitSide.baseOnly),
          BranchComparisonCommit(
            commit: older,
            side: BranchCommitSide.compareOnly,
          ),
          BranchComparisonCommit(
            commit: commit('root', 'shared commit'),
            side: BranchCommitSide.commonBoundary,
          ),
        ],
        files: const [],
        merge: const MergeConflictCheck(status: MergeConflictStatus.clean),
      );
      final graph = layoutRebasePreviewGraph(
        comparison,
        RebasePreviewResult(
          status: RebasePreviewStatus.clean,
          baseTip: base.sha,
          compareTip: newer.sha,
          rewritten: [(original: newer, rewrittenSha: 'rewritten-new')],
          completed: 1,
          total: 1,
          virtualTip: 'rewritten-new',
        ),
        mergeCommit: true,
      );

      // 줄 순서: 가상 머지, 재배치 커밋, 원본 newer, 기준 브랜치 HEAD, …
      expect(graph.rows[1].commit.sha, 'rewritten-new');
      expect(graph.rows[2].commit.sha, newer.sha);
      expect(graph.rows[3].commit.sha, base.sha);
      // 원본 줄이 레인 1을 쓰고 있으니 체인은 레인 2로 비켜 앉는다.
      final chainLane = graph.rows[1].lane;
      expect(chainLane, 2);
      expect(graph.rows[2].lane, 1);
      expect(graph.rows[1].nextLanes, contains(chainLane));
      expect(graph.rows[1].transitions, isEmpty);
      // 뿌리는 HEAD 바로 윗줄에서 꺾인다.
      final crossed = graph.rows[2];
      expect(crossed.activeLanes, contains(chainLane));
      expect(crossed.nextLanes, isNot(contains(chainLane)));
      expect(
        crossed.transitions,
        contains((from: chainLane, to: 0, sha: base.sha)),
      );
      expect(graph.dashedLanes[2], contains(chainLane));
      expect(graph.dashedLanes[3], isNull);
    },
  );

  test('a rebase preview onto an unchanged base reaches the HEAD node', () {
    // 기준 브랜치가 분기 뒤로 그대로인 흔한 배치: 기준 브랜치 HEAD가 곧 머지 베이스라
    // 원본 커밋이 전부 그 위에 남고, HEAD 위로는 기준 브랜치 선이 없다.
    final baseTip = commit('main-tip', 'shared commit');
    final older = commit('feature-old', 'older feature', parents: ['main-tip']);
    final newer = commit(
      'feature-new',
      'newer feature',
      parents: ['feature-old'],
    );
    final comparison = BranchComparisonResult(
      baseRef: 'main',
      compareRef: 'feature',
      baseTip: baseTip.sha,
      compareTip: newer.sha,
      baseParent: 'root',
      compareParent: older.sha,
      mergeBases: [baseTip.sha],
      commits: [
        BranchComparisonCommit(
          commit: newer,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: older,
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: baseTip,
          side: BranchCommitSide.commonBoundary,
        ),
      ],
      files: const [],
      merge: const MergeConflictCheck(status: MergeConflictStatus.clean),
    );
    final preview = RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: baseTip.sha,
      compareTip: newer.sha,
      rewritten: [
        (original: older, rewrittenSha: 'rewritten-old'),
        (original: newer, rewrittenSha: 'rewritten-new'),
      ],
      completed: 2,
      total: 2,
      virtualTip: 'rewritten-new',
    );
    CommitGraphPainter painter(BranchPreviewGraph graph, int index) =>
        CommitGraphPainter(
          row: graph.rows[index],
          previous: index > 0 ? graph.rows[index - 1] : null,
          selected: false,
          committerColor: const Color(0xFF7AD6E8),
          dashedLanes: graph.dashedLanes[index] ?? const {},
          previousDashedLanes: index > 0
              ? graph.dashedLanes[index - 1] ?? const {}
              : const {},
        );

    final landed = layoutRebasePreviewGraph(
      comparison,
      preview,
      mergeCommit: true,
    );
    final headIndex = landed.rows.indexWhere(
      (row) => row.commit.sha == baseTip.sha,
    );
    expect(headIndex, landed.rows.length - 1);
    // 가상 머지의 첫 부모 선은 남은 원본 줄들을 지나 HEAD 노드까지 끊기지 않는다.
    const baseLane = 0;
    for (var index = 0; index < headIndex; index++) {
      expect(landed.rows[index].activeLanes, contains(baseLane));
      expect(
        CommitGraphPainter.railsBelow(landed.rows[index]),
        contains(baseLane),
      );
      expect(landed.dashedLanes[index], contains(baseLane));
    }
    expect(painter(landed, headIndex).continuesFromAbove(baseLane), isTrue);
    // 원본 브랜치가 HEAD로 합쳐지는 실제 선은 점선 레인에 닿아도 실선으로 남고,
    // 체인의 뿌리만 점선으로 꺾인다.
    final converging = landed.rows[headIndex - 1];
    final real = (from: 1, to: baseLane, sha: baseTip.sha);
    final chainRoot = (
      from: landed.rows[1].lane,
      to: baseLane,
      sha: baseTip.sha,
    );
    expect(converging.transitions, [real, chainRoot]);
    expect(painter(landed, headIndex - 1).isDashedTransition(real), isFalse);
    expect(
      painter(landed, headIndex - 1).isDashedTransition(chainRoot),
      isTrue,
    );
    expect(
      painter(landed, headIndex).isDashedTransition(real, above: true),
      isFalse,
    );
    expect(
      painter(landed, headIndex).isDashedTransition(chainRoot, above: true),
      isTrue,
    );

    // 'Rebase만'도 같은 원본 줄들을 지나 HEAD 노드까지 닿는다 — 인라인이라 레인 하나로.
    final plain = layoutRebasePreviewGraph(comparison, preview);
    final plainHead = plain.rows.length - 1;
    for (var index = 0; index < plainHead; index++) {
      expect(plain.rows[index].activeLanes, contains(baseLane));
      expect(plain.dashedLanes[index], {baseLane});
    }
    expect(painter(plain, plainHead).continuesFromAbove(baseLane), isTrue);
    expect(plain.dashedLanes[plainHead], isNull);
    expect(painter(plain, plainHead - 1).isDashedTransition(real), isFalse);
  });

  test('preview graphs preserve existing comparison commits', () {
    final comparison = branchComparison();
    final existing = layoutBranchComparison(comparison.commits);
    final merge = layoutMergePreviewGraph(comparison);
    void expectExistingRows(
      List<GraphRow> rows,
      int offset, {
      bool preserveRails = true,
    }) {
      for (var index = 0; index < existing.length; index++) {
        final actual = rows[index + offset];
        final expected = existing[index];
        expect(actual.commit, same(expected.commit));
        expect(actual.lane, expected.lane);
        expect(actual.parentLanes, expected.parentLanes);
        if (preserveRails) {
          expect(actual.activeLanes, expected.activeLanes);
          expect(actual.nextLanes, expected.nextLanes);
          expect(actual.activeLaneShas, expected.activeLaneShas);
          expect(actual.nextLaneShas, expected.nextLaneShas);
          expect(actual.activeLaneBranches, expected.activeLaneBranches);
          expect(actual.nextLaneBranches, expected.nextLaneBranches);
        }
        expect(actual.transitions, expected.transitions);
        expect(actual.branch, expected.branch);
      }
    }

    expectExistingRows(merge.rows, 1);

    final feature = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    final rebase = layoutRebasePreviewGraph(
      comparison,
      RebasePreviewResult(
        status: RebasePreviewStatus.clean,
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
        rewritten: [(original: feature, rewrittenSha: 'rewritten-feature')],
        completed: 1,
        total: 1,
        virtualTip: 'rewritten-feature',
      ),
    );

    expectExistingRows(rebase.rows, 1, preserveRails: false);
  });

  testWidgets('the app passes branch preview mode changes to settings', (
    tester,
  ) async {
    final store = MemorySettingsStore()
      ..current = const AppSettings(
        branchPreviewMode: BranchPreviewMode.rebase,
      );
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final timeline = tester.widget<TimelineScreen>(find.byType(TimelineScreen));
    expect(timeline.branchPreviewMode, BranchPreviewMode.rebase);
    timeline.onBranchPreviewModeChanged!(BranchPreviewMode.merge);
    await tester.pumpAndSettle();
    expect(store.current.branchPreviewMode, BranchPreviewMode.merge);
  });

  test(
    'copyWith replaces the base branch map without losing other settings',
    () {
      const settings = AppSettings(showAvatars: false);
      final changed = settings.copyWith(
        baseBranches: {'/repos/one': 'develop'},
      );
      expect(changed.showAvatars, isFalse);
      expect(changed.baseBranches, {'/repos/one': 'develop'});
    },
  );

  testWidgets('the initials avatar is a filled disc with contrasting ink', (
    tester,
  ) async {
    const ada = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: IdentityAvatar(identity: ada)),
      ),
    );

    final fill =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    // Opaque identity color, no transparent center, and no outline at all.
    expect(fill.color, AvatarService.color(ada));
    expect(fill.color!.a, 1.0);
    expect(fill.border, isNull);
    expect(tester.widget<IdentityAvatar>(find.byType(IdentityAvatar)).size, 22);

    // In a row the disc wears the branch line instead, ink following suit.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IdentityAvatar(
            identity: ada,
            discColor: AvatarService.branchColor(2),
          ),
        ),
      ),
    );
    final branchFill =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    expect(branchFill.color, AvatarService.branchColor(2));
    expect(
      tester.widget<Text>(find.text('AL')).style?.color,
      AvatarService.onColor(AvatarService.branchColor(2)),
    );
    expect(
      tester.widget<Text>(find.text('AL')).style?.color,
      AvatarService.onColor(AvatarService.color(ada)),
    );
    expect(AvatarService.onColor(const Color(0xFFD29922)), isNot(Colors.white));
    expect(AvatarService.onColor(const Color(0xFF1D2029)), Colors.white);
  });

  test('the committer color follows the active palette', () {
    const ada = GitIdentity(name: 'Ada', email: 'ada@example.com');
    addTearDown(() => AvatarService.palette = AvatarService.defaultColors);

    expect(AvatarService.defaultColors, contains(AvatarService.color(ada)));
    AvatarService.palette = const [Color(0xFF010203)];
    expect(AvatarService.color(ada), const Color(0xFF010203));
    // An empty palette is never painted with.
    AvatarService.palette = const [];
    expect(AvatarService.defaultColors, contains(AvatarService.color(ada)));
  });

  testWidgets('Appearance selects one of three timeline theme previews', (
    tester,
  ) async {
    final saved = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: saved.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-section-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('timeline-theme-card-carbon')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-section-appearance')));
    await tester.pumpAndSettle();

    for (final theme in TimelineThemeKind.values) {
      expect(
        find.byKey(Key('timeline-theme-card-${theme.storageValue}')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .getSemantics(
            find.byKey(const Key('timeline-theme-card-systemGraphite')),
          )
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );

    await tester.tap(find.byKey(const Key('timeline-theme-card-warmGraphite')));
    await tester.pump();
    final saveCountAfterTap = saved.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(saved.last.timelineTheme, TimelineThemeKind.warmGraphite);
    expect(saved.length, saveCountAfterTap + 1);

    final saveCountAfterEnter = saved.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(saved.last.timelineTheme, TimelineThemeKind.warmGraphite);
    expect(saved.length, saveCountAfterEnter + 1);

    await tester.tap(find.byKey(const Key('timeline-theme-card-carbon')));
    await tester.pumpAndSettle();

    expect(saved.last.timelineTheme, TimelineThemeKind.carbon);
    expect(
      tester
          .getSemantics(find.byKey(const Key('timeline-theme-card-carbon')))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('the commit message section edits both templates', (
    tester,
  ) async {
    final saved = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: saved.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-section-commit-messages')));
    await tester.pumpAndSettle();

    expect(find.text('Merge 커밋 메시지'), findsOneWidget);
    expect(find.text('Rebase 후 Merge 커밋 메시지'), findsOneWidget);
    expect(find.textContaining('{profile} 이 저장소의 커밋 프로필 이름'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('merge-message-template')))
          .controller
          ?.text,
      AppSettings.defaultMergeMessageTemplate,
    );

    await tester.enterText(
      find.byKey(const Key('merge-message-template')),
      "Merge '{source}'\n\nReviewed-by: {profile}",
    );
    await tester.pumpAndSettle();
    expect(
      saved.last.mergeMessageTemplate,
      "Merge '{source}'\n\nReviewed-by: {profile}",
    );

    // 비우는 것도 선택이다: git 표준 메시지만 쓰겠다는 뜻이다.
    await tester.enterText(
      find.byKey(const Key('rebase-merge-message-template')),
      '',
    );
    await tester.pumpAndSettle();
    expect(saved.last.rebaseMergeMessageTemplate, isEmpty);
    expect(AppSettings.fromJson(saved.last.toJson()), saved.last);
  });

  testWidgets('timeline colors only shows the unified palette editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(settings: const AppSettings(), onChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Timeline colors'), findsOneWidget);
    expect(find.text('Branch / Tag & graph palette'), findsOneWidget);
    expect(find.text('Base branch and lane fallback'), findsNothing);
    expect(find.byKey(const Key('base-branch-color')), findsNothing);
    expect(find.byKey(const Key('lane-color-0')), findsNothing);
    expect(find.text('Base branch'), findsOneWidget);
    expect(find.text('Color 2'), findsNothing);
    expect(find.text('Color 9'), findsOneWidget);
  });

  testWidgets('branch tag palette editor applies Base and Text and resets', (
    tester,
  ) async {
    final saved = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: saved.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final preview = tester.widget<Container>(
      find.byKey(const Key('ref-palette-chip-0')),
    );
    final decoration = preview.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF0E8A16).withValues(alpha: .18));
    expect(
      decoration.border!.top.color,
      const Color(0xFF18E022).withValues(alpha: .30),
    );
    expect(find.byKey(const Key('ref-palette-assignment-0')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('ref-palette-assignment-1')),
    );
    await tester.tap(find.byKey(const Key('ref-palette-assignment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lane 2').last);
    await tester.pumpAndSettle();
    expect(saved.last.refPaletteAssignments[1], 2);

    await tester.ensureVisible(
      find.byKey(const Key('ref-palette-assignment-2')),
    );
    await tester.tap(find.byKey(const Key('ref-palette-assignment-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lane 2').last);
    await tester.pumpAndSettle();
    expect(saved.last.refPaletteAssignments[1], 0);
    expect(saved.last.refPaletteAssignments[2], 2);

    await tester.enterText(
      find.byKey(const Key('ref-palette-base-0')),
      '#010203',
    );
    await tester.enterText(
      find.byKey(const Key('ref-palette-text-0')),
      '#A0B0C0',
    );
    await tester.pump();
    expect(saved.last.refPalette.first, (base: '#010203', text: '#A0B0C0'));

    await tester.enterText(find.byKey(const Key('ref-palette-base-0')), '#01');
    await tester.pump();
    expect(saved.last.refPalette.first.base, '#010203');

    await tester.tap(find.byKey(const Key('reset-ref-palette')));
    await tester.pump();
    expect(saved.last.refPalette, AppSettings.defaultRefPalette);
    expect(
      saved.last.refPaletteAssignments,
      AppSettings.defaultRefPaletteAssignments,
    );
  });

  testWidgets('stored timeline colors reach the base and fallback rails', (
    tester,
  ) async {
    addTearDown(() {
      AvatarService.baseBranchColor = AvatarService.defaultBaseBranchColor;
      AvatarService.palette = AvatarService.defaultColors;
      AvatarService.branchAssignments = const {};
    });
    final store = MemorySettingsStore()
      ..current = const AppSettings(
        baseBranchColor: '#0C8599',
        laneColors: ['#0B7285'],
      );
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(AvatarService.baseBranchColor, const Color(0xFF0C8599));
    expect(AvatarService.palette, const [Color(0xFF0B7285)]);
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.row.branch, 0);
    expect(painter.committerColor, const Color(0xFF0C8599));
  });

  testWidgets('stored ref palette reaches timeline chips', (tester) async {
    final store = MemorySettingsStore()
      ..current = const AppSettings(
        refPalette: [
          (base: '#010203', text: '#A0B0C0'),
          (base: '#E99695', text: '#E89292'),
          (base: '#C5DEF5', text: '#C2DDF4'),
          (base: '#0E8A16', text: '#18E022'),
          (base: '#5319E7', text: '#DACFFA'),
        ],
      );
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('tip', 'tip')],
          refs: const RepoRefs(local: ['d'], current: 'd', tips: {'d': 'tip'}),
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    final decoration =
        tester
                .widget<Container>(find.byKey(const Key('ref-chip-tip-d')))
                .decoration!
            as BoxDecoration;
    expect(decoration.color, const Color(0xFF010203).withValues(alpha: .18));
  });

  test('social time counts calendar days, like the date headings', () {
    final now = DateTime(2026, 7, 26, 10);
    String label(DateTime time) => socialTimeLabel(time, now);

    // Same day keeps the fine-grained strings.
    expect(label(DateTime(2026, 7, 26, 9, 59, 30)), 'just now');
    expect(label(DateTime(2026, 7, 26, 9, 59)), '1 minute ago');
    expect(label(DateTime(2026, 7, 26, 9, 1)), '59 minutes ago');
    expect(label(DateTime(2026, 7, 26, 9)), '1 hour ago');
    expect(label(DateTime(2026, 7, 26, 0, 1)), '9 hours ago');

    // The first two days read in hours, however the calendar falls.
    expect(label(DateTime(2026, 7, 24, 23, 19)), '34 hours ago');
    expect(label(DateTime(2026, 7, 25, 2)), '32 hours ago');
    expect(label(DateTime(2026, 7, 24, 11)), '47 hours ago');
    expect(
      socialTimeLabel(DateTime(2026, 7, 25, 23), DateTime(2026, 7, 26, 0, 30)),
      '1 hour ago',
    );
    // Past 48 hours the calendar buckets take over, and 'yesterday' is retired.
    expect(label(DateTime(2026, 7, 24, 10)), '2 days ago');
    expect(label(DateTime(2026, 7, 24, 9)), '2 days ago');
    expect(label(DateTime(2026, 7, 23, 9)), '3 days ago');
    expect(label(DateTime(2026, 6, 27)), '29 days ago');
    expect(label(DateTime(2026, 6, 26)), '1 month ago');
    expect(label(DateTime(2025, 7, 27)), '12 months ago');
    expect(label(DateTime(2025, 7, 26)), '1 year ago');
    expect(label(DateTime(2024, 5, 20)), '2 years ago');
  });

  testWidgets('every Date cell agrees with the heading above it', (
    tester,
  ) async {
    final now = DateTime.now();
    int stamp(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
    // Late-evening commits are where elapsed hours and calendar days disagree.
    final times = [
      now.subtract(const Duration(hours: 2)),
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(minutes: 41)),
      DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 23, minutes: 19)),
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 4)).add(const Duration(hours: 22)),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            for (var index = 0; index < times.length; index++)
              commit('$index', 'commit $index', timestamp: stamp(times[index])),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    for (final time in times) {
      final social = socialTimeLabel(time, now);
      final heading = dateGroupLabel(time, now);
      // A row saying 'yesterday' belongs under Yesterday, 'N days ago' under a
      // dated heading, and today's hours under Today.
      // Under two days the row reads in hours and may sit under any heading;
      // past that its day bucket must match a dated heading.
      if (now.difference(time).inHours < 48) {
        expect(social, endsWith('ago'), reason: '$social / $heading');
        expect(social, isNot(contains('days')), reason: '$social / $heading');
      } else {
        expect(social, endsWith('days ago'), reason: '$social / $heading');
        expect(
          heading,
          isNot(anyOf('Today', 'Yesterday')),
          reason: '$social / $heading',
        );
      }
      expect(find.text(social), findsWidgets, reason: social);
      expect(find.text(heading), findsWidgets, reason: heading);
    }
  });

  test(
    'column widths round-trip time and name and clamp to the design range',
    () {
      const widths = TimelineColumnWidths(
        time: 130,
        name: 120,
        commit: 500,
        showTime: false,
        showName: false,
      );
      final decoded = TimelineColumnWidths.fromJson(widths.toJson());
      expect(decoded, widths);
      expect(decoded.time, 130);
      expect(decoded.name, 120);
      expect(decoded.commit, 500);
      expect(decoded.showTime, isFalse);
      expect(decoded.showName, isFalse);
      expect(const TimelineColumnWidths().refs, 156);
      expect(const TimelineColumnWidths().hash, 78);
      expect(const TimelineColumnWidths().showTime, isTrue);
      expect(const TimelineColumnWidths().showName, isTrue);

      // An unset graph or title width is omitted and comes back unset, so both
      // columns keep sizing themselves across restarts.
      const flexing = TimelineColumnWidths();
      expect(flexing.commit, isNull);
      expect(flexing.graph, isNull);
      expect(flexing.toJson().containsKey('commit'), isFalse);
      expect(flexing.toJson().containsKey('graph'), isFalse);
      expect(TimelineColumnWidths.fromJson(flexing.toJson()).commit, isNull);
      expect(TimelineColumnWidths.fromJson(flexing.toJson()).graph, isNull);
      expect(
        TimelineColumnWidths.fromJson(<String, dynamic>{
          'commit': 'wide',
          'graph': 'wide',
        }).graph,
        isNull,
      );
      expect(
        TimelineColumnWidths.fromJson(
          const TimelineColumnWidths(graph: 180).toJson(),
        ).graph,
        180,
      );

      final clamped = TimelineColumnWidths.fromJson(<String, dynamic>{
        'time': 400,
        'name': 10,
        'refs': 999,
        'commit': 4000,
        'graph': 10,
      });
      expect(clamped.time, 170);
      expect(clamped.name, 50);
      expect(clamped.refs, 240);
      expect(clamped.commit, 620);
      expect(clamped.graph, 40);
    },
  );

  test('repository graph widths round-trip and discard damaged entries', () {
    final restored = AppSettings.fromJson({
      'repositoryGraphWidths': {
        '/repo/a': 188,
        '/repo/narrow': 1,
        '/repo/wide': 999,
        '/repo/bad': 'wide',
        '': 120,
      },
    });

    expect(restored.repositoryGraphWidths, {
      '/repo/a': 188,
      '/repo/narrow': 40,
      '/repo/wide': 260,
    });
    expect(
      AppSettings.fromJson(restored.toJson()).repositoryGraphWidths,
      restored.repositoryGraphWidths,
    );
  });

  test(
    'repository graph widths stay independent and migrate legacy width once',
    () {
      const base = AppSettings(
        columnWidths: TimelineColumnWidths(graph: 176, hash: 90),
      );
      final migrated = base.migrateLegacyGraphWidth('/repo/a');

      expect(migrated.columnWidths.graph, isNull);
      expect(migrated.repositoryGraphWidths, {'/repo/a': 176});
      expect(migrated.columnWidthsForRepository('/repo/a').graph, 176);
      expect(migrated.columnWidthsForRepository('/repo/b').graph, isNull);
      expect(migrated.columnWidthsForRepository('/repo/b').hash, 90);

      final changed = migrated.withRepositoryColumnWidths(
        '/repo/b',
        migrated.columnWidthsForRepository('/repo/b').withGraph(204),
      );
      expect(changed.repositoryGraphWidths, {'/repo/a': 176, '/repo/b': 204});
      expect(changed.columnWidths.graph, isNull);

      final mixed = AppSettings(
        columnWidths: const TimelineColumnWidths(graph: 150),
        repositoryGraphWidths: const {'/repo/existing': 190},
      ).migrateLegacyGraphWidth('/repo/new');
      expect(mixed.columnWidths.graph, isNull);
      expect(mixed.repositoryGraphWidths, {'/repo/existing': 190});
    },
  );

  test('full diff column widths round-trip and clamp damaged settings', () {
    const widths = FullDiffColumnWidths(history: 240, files: 330);
    final decoded = AppSettings.fromJson(
      const AppSettings(fullDiffColumnWidths: widths).toJson(),
    );

    expect(decoded.fullDiffColumnWidths, widths);
    expect(
      AppSettings.fromJson({
        'fullDiffColumnWidths': {'history': 1, 'files': 9999},
      }).fullDiffColumnWidths,
      const FullDiffColumnWidths(history: 180, files: 520),
    );
    expect(
      FullDiffColumnWidths.fromJson(
        const FullDiffColumnWidths(history: 180, files: 158).toJson(),
      ),
      const FullDiffColumnWidths(history: 180, files: 158),
    );
  });

  test('side-by-side ratio round-trips and clamps damaged settings', () {
    const widths = FullDiffColumnWidths(
      history: 240,
      files: 330,
      sideBySideRatio: 0.65,
    );
    expect(FullDiffColumnWidths.fromJson(widths.toJson()), widths);

    expect(
      FullDiffColumnWidths.fromJson({'sideBySideRatio': 0.05}).sideBySideRatio,
      0.2,
    );
    expect(
      FullDiffColumnWidths.fromJson({'sideBySideRatio': 1.5}).sideBySideRatio,
      0.8,
    );
    expect(FullDiffColumnWidths.fromJson(const {}).sideBySideRatio, 0.5);
  });

  test('legacy full diff commits width migrates to history width', () {
    final widths = FullDiffColumnWidths.fromJson({
      'commits': 244,
      'files': 318,
    });

    expect(widths.history, 244);
    expect(widths.files, 318);
    expect(widths.toJson(), {
      'history': 244.0,
      'files': 318.0,
      'sideBySideRatio': 0.5,
    });
  });

  test('legacy full diff initial view is ignored', () {
    final settings = AppSettings.fromJson(const {
      'fullDiffInitialView': 'fullFile',
    });

    expect(settings.fullDiffPreferences, const FullDiffPreferences());
    expect(settings.toJson(), isNot(contains('fullDiffInitialView')));
  });

  test('legacy hunk and missing initial views keep default preferences', () {
    expect(
      AppSettings.fromJson(const {
        'fullDiffInitialView': 'hunk',
      }).fullDiffPreferences,
      const FullDiffPreferences(),
    );
    expect(
      AppSettings.fromJson(const {}).fullDiffPreferences,
      const FullDiffPreferences(),
    );
  });

  test('explicit full diff preferences take precedence over legacy view', () {
    final settings = AppSettings.fromJson(const {
      'fullDiffInitialView': 'fullFile',
      'fullDiffPreferences': {
        'view': 'history',
        'layout': 'sideBySide',
        'scope': 'hunks',
        'algorithm': 'patience',
        'ignoreWhitespace': true,
        'wrapLines': false,
      },
    });

    expect(
      settings.fullDiffPreferences,
      const FullDiffPreferences(
        view: FullDiffView.history,
        layout: DiffLayout.sideBySide,
        algorithm: DiffAlgorithm.patience,
        ignoreWhitespace: true,
        wrapLines: false,
      ),
    );
  });

  test('full diff preferences survive settings JSON', () {
    const preferences = FullDiffPreferences(
      view: FullDiffView.history,
      historySelected: true,
      layout: DiffLayout.sideBySide,
      scope: DiffScope.fullFile,
      algorithm: DiffAlgorithm.patience,
      ignoreWhitespace: true,
      wrapLines: false,
    );

    final restored = AppSettings.fromJson(
      const AppSettings(fullDiffPreferences: preferences).toJson(),
    );

    expect(restored.fullDiffPreferences, preferences);
    expect(
      (const AppSettings(
            fullDiffPreferences: preferences,
          ).toJson()['fullDiffPreferences']
          as Map<String, Object>),
      const {
        'view': 'history',
        'historySelected': true,
        'layout': 'sideBySide',
        'scope': 'fullFile',
        'algorithm': 'patience',
        'ignoreWhitespace': true,
        'wrapLines': false,
      },
    );
  });

  test('full diff preferences preserve History behind Blame', () {
    const preferences = FullDiffPreferences(
      view: FullDiffView.blame,
      historySelected: true,
      layout: DiffLayout.sideBySide,
    );

    final json = preferences.toJson();
    final restored = FullDiffPreferences.fromJson(json);

    expect(restored, preferences);
    expect(json['view'], 'blame');
    expect(json['historySelected'], isTrue);
  });

  test('legacy History view migrates to selected History', () {
    final restored = FullDiffPreferences.fromJson({
      'view': 'history',
      'layout': 'unified',
    });

    expect(restored.view, FullDiffView.history);
    expect(restored.historySelected, isTrue);
  });

  test('legacy Diff and Blame views migrate with History off', () {
    expect(
      FullDiffPreferences.fromJson({'view': 'diff'}).historySelected,
      isFalse,
    );
    expect(
      FullDiffPreferences.fromJson({'view': 'blame'}).historySelected,
      isFalse,
    );
  });

  test('removed and malformed full diff options fall back safely', () {
    final preferences = AppSettings.fromJson({
      'fullDiffPreferences': {
        'view': 'file',
        'layout': 'unknown',
        'scope': 'unknown',
        'algorithm': 'unknown',
        'ignoreWhitespace': 'yes',
        'wrapLines': 1,
      },
    }).fullDiffPreferences;

    expect(preferences, const FullDiffPreferences());
  });

  testWidgets('settings removes legacy full diff starting views', (
    tester,
  ) async {
    final saved = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: saved.add,
        ),
      ),
    );
    expect(find.text('Hunk'), findsNothing);
    expect(find.text('Full file focused on first change'), findsNothing);
    expect(saved, isEmpty);
  });

  testWidgets('stored full diff preferences apply when opening a new screen', (
    tester,
  ) async {
    const preferences = FullDiffPreferences(
      layout: DiffLayout.sideBySide,
      scope: DiffScope.fullFile,
    );
    final store = MemorySettingsStore()
      ..current = const AppSettings(fullDiffPreferences: preferences);
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'commit')],
          files: (_, _) async => const [],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DiffScreen>(find.byType(DiffScreen)).initialPreferences,
      preferences,
    );
  });

  testWidgets('timeline themes do not recolor Settings or Full Diff', (
    tester,
  ) async {
    final store = MemorySettingsStore()
      ..current = const AppSettings(timelineTheme: TimelineThemeKind.carbon);
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'commit')],
          files: (_, _) async => const [],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
      const Color(0xFF15171E),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();
    final diffContext = tester.element(find.byType(DiffScreen));
    expect(Theme.of(diffContext).extension<TimelineThemePalette>(), isNull);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
      fullDiffCanvas,
    );
  });

  testWidgets('reopening full diff restores the last successful options', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [
        GitFileChange(
          path: 'lib/example.dart',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
        DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
      ],
      content: (_, _, _) async => Uint8List.fromList(utf8.encode('new\n')),
      history: (_, file) async => [
        GitFileHistoryRecord(
          commit: commit('1', 'commit'),
          path: file.path,
          oldPath: null,
          status: 'M',
        ),
      ],
    );

    Future<void> pumpApp() async {
      await tester.pumpWidget(
        YogitApp(
          repository: repository,
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();
    }

    await pumpApp();
    await tester.tap(find.text('History'));
    await tester.tap(find.text('Side-by-side'));
    await tester.tap(find.text('Hunk'));
    await tester.tap(find.byKey(const Key('ignore-whitespace')));
    await tester.tap(find.byKey(const Key('wrap-lines')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('full-diff-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('History'))
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Side-by-side'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      store.current.fullDiffPreferences,
      const FullDiffPreferences(
        view: FullDiffView.history,
        layout: DiffLayout.sideBySide,
        scope: DiffScope.fullFile,
        algorithm: DiffAlgorithm.gitSetting,
        ignoreWhitespace: true,
        wrapLines: false,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpApp();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('History'))
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Side-by-side'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(find.byKey(const Key('hunk-toggle-off')), findsOneWidget);
  });

  testWidgets('settings write failure keeps the applied full diff session', (
    tester,
  ) async {
    final store = FailingSettingsStore();
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'commit')],
          files: (_, _) async => const [],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side-by-side'));
    await tester.pump();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Side-by-side'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings feedback keeps the live full diff selection and scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 500);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final store = FailingSettingsStore();
      const firstFile = GitFileChange(
        path: 'lib/first.dart',
        status: 'M',
        additions: 1,
        deletions: 0,
      );
      const secondFile = GitFileChange(
        path: 'lib/second.dart',
        status: 'M',
        additions: 1,
        deletions: 0,
      );
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'commit')],
            files: (_, _) async => const [firstFile, secondFile],
            diff: (_, _, path, _, _) async => [
              const DiffLine(
                kind: DiffLineKind.hunk,
                text: '@@ -1,80 +1,80 @@',
              ),
              for (var line = 1; line <= 80; line++)
                DiffLine(
                  kind: DiffLineKind.context,
                  text: '$path line $line',
                  oldNumber: line,
                  newNumber: line,
                ),
            ],
            content: (_, file, _) async =>
                Uint8List.fromList(utf8.encode('${file.path}\n')),
          ),
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();
      tester
          .widget<Focus>(find.byKey(const Key('changed-files-focus')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('selected-file-lib/second.dart')),
        findsOneWidget,
      );

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('content-scrollable')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(100));
      scrollable.position.jumpTo(100);
      await tester.pump();

      await tester.tap(find.text('Side-by-side'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('selected-file-lib/second.dart')),
        findsOneWidget,
      );
      expect(scrollable.position.pixels, 100);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full diff changes before settings load persist without another change',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final store = DelayedMemorySettingsStore();
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'commit')],
            files: (_, _) async => const [],
          ),
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Side-by-side'));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('details-files-column-resizer')),
        const Offset(20, 0),
      );
      await tester.pump();
      expect(store.saveCount, 0);

      store.completeLoad();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('full-diff-back')));
      await tester.pumpAndSettle();
      expect(store.saveCount, 3);
      expect(store.current.baseBranches, {'.': 'main'});
      expect(
        store.current.fullDiffPreferences,
        const FullDiffPreferences(layout: DiffLayout.sideBySide),
      );
      expect(store.current.fullDiffColumnWidths.files, 310);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'commit')],
            files: (_, _) async => const [],
          ),
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Side-by-side'))
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSize(find.byKey(const Key('details-files-column'))).width,
        310,
      );

      final staleCallback = tester
          .widget<DiffScreen>(find.byType(DiffScreen))
          .onPreferencesChanged!;
      final savedBeforeDispose = store.saveCount;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      staleCallback(const FullDiffPreferences());
      expect(store.saveCount, savedBeforeDispose);
    },
  );

  testWidgets(
    'closing full diff before settings load keeps its pending changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final store = DelayedMemorySettingsStore();
      final repository = FakeGitRepository(
        (_, _) async => [commit('1', 'commit')],
        files: (_, _) async => const [],
      );
      await tester.pumpWidget(
        YogitApp(
          repository: repository,
          settingsStore: store,
          discoverAvatars: false,
          windowFrameController: controller,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Side-by-side'));
      await tester.drag(
        find.byKey(const Key('details-files-column-resizer')),
        const Offset(20, 0),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('full-diff-back')));
      await tester.pumpAndSettle();
      expect(store.saveCount, 0);

      store.completeLoad();
      await tester.pumpAndSettle();

      expect(store.saveCount, 3);
      expect(store.current.baseBranches, {'.': 'main'});
      expect(
        store.current.fullDiffPreferences,
        const FullDiffPreferences(layout: DiffLayout.sideBySide),
      );
      expect(store.current.fullDiffColumnWidths.files, 310);

      await tester.tap(find.byKey(const Key('toolbar-full-diff')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Side-by-side'))
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSize(find.byKey(const Key('details-files-column'))).width,
        310,
      );
    },
  );

  testWidgets('uncommitted changes lead the timeline as a working tree row', (
    tester,
  ) async {
    final skips = <int>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository((skip, _) async {
          skips.add(skip);
          return skip == 0 ? [commit('1', 'first commit')] : [];
        }, workingTree: () async => workingTreeCommit('1')),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Timeline row plus the opened preview title.
    expect(find.text('Uncommitted changes'), findsNWidgets(2));
    expect(find.text('working tree'), findsOneWidget);
    // No date group above the working tree row: it belongs to no day.
    expect(
      tester.getRect(find.byKey(const Key('date-row-1'))).top,
      greaterThan(tester.getRect(find.text('working tree')).top),
    );
    expect(find.text('·······'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(skips, [0]);

    final hash = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.text('1'),
      ),
    );
    expect(hash.style?.color, const Color(0xFFEF6C63));

    final wipRow =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(wipRow.row.commit.isWorkingTree, isTrue);
    expect(wipRow.showsMergeDot, isFalse);
    expect(CommitGraphPainter.wipNodeRadius, 8);
    expect(CommitGraphPainter.wipNodeDash, 2.5);
    expect(
      find.descendant(
        of: find.byKey(const Key('graph-cell-0')),
        matching: find.byType(CommitAvatarStack),
      ),
      findsNothing,
    );
  });

  testWidgets('left preview keeps the panel ahead of the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('좌측'));
    await tester.pumpAndSettle();

    expect(controller.previewPlacement, PreviewPlacement.left);
    final leftLayout = find.byKey(const Key('preview-layout-left'));
    expect(leftLayout, findsOneWidget);
    expect(tester.widget(leftLayout), isA<Row>());
    expect(
      tester.getTopLeft(find.byKey(const Key('preview-panel'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('timeline-viewport'))).dx,
      ),
    );
  });

  testWidgets('a multi-ref row shares its cell between chips, no avatars', (
    tester,
  ) async {
    const refs = [
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'main', isHead: true),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('multi', 'multi ref commit', refs: refs),
            commit('plain', 'plain commit', refs: const []),
          ],
          refs: const RepoRefs(
            local: ['main'],
            remote: ['origin/main'],
            tags: ['v1.0'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Every ref that fits gets an equal share of the cell; no badge at all.
    final cell = tester.getRect(find.byKey(const Key('refs-cell-0')));
    final chip = tester.getRect(find.byKey(const Key('ref-chip-multi-main')));
    for (final ref in refs) {
      expect(find.byKey(Key('ref-chip-multi-${ref.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('ref-more-multi')), findsNothing);
    expect(chip.left - cell.left, 14);
    expect(chip.center.dy, cell.center.dy);
    expect(
      tester
          .getRect(find.byKey(const Key('ref-chip-connector-multi')))
          .center
          .dy,
      cell.center.dy,
    );
    expect(
      cell.right -
          tester.getRect(find.byKey(const Key('ref-chip-multi-v1.0'))).right,
      14,
    );

    // Chips carry no avatars at all any more, and the cell has no hairline.
    expect(
      find.descendant(
        of: find.byKey(const Key('refs-cell-0')),
        matching: find.byType(IdentityAvatar),
      ),
      findsNothing,
    );
    // Nothing in this cell paints the row hairline any more; the rules start at
    // the hash column.
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('refs-cell-0')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).border)
          .whereType<Border>()
          .map((border) => border.bottom.color),
      everyElement(isNot(const Color(0xFF343946))),
    );
    // The remaining run to the node is the graph cell's own connector.
    expect(
      tester.getRect(find.byKey(const Key('graph-cell-0'))).left,
      cell.right,
    );
  });

  testWidgets('the selected multi-ref row lists its refs in a floating modal', (
    tester,
  ) async {
    const refs = [
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'main', isHead: true),
      GitRef(name: 'd'),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            for (var index = 0; index < 10; index++)
              commit(
                '$index',
                'commit $index',
                // Row 5 sits with room on both sides of it.
                refs: index == 5 ? refs : const [],
              ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    final modal = find.byKey(const Key('refs-modal'));
    expect(modal, findsNothing);

    // Arriving from above puts the box over the row, clear of it.
    for (var press = 0; press < 5; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(modal, findsOneWidget);
    for (final ref in refs) {
      expect(
        find.descendant(of: modal, matching: find.text(ref.name)),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<Container>(find.byKey(const Key('modal-accent-main')))
          .color,
      const Color(0xFFE89292),
    );
    expect(
      tester.widget<Container>(find.byKey(const Key('modal-accent-d'))).color,
      const Color(0xFF68A7EA),
    );
    final row = tester.getRect(find.byKey(const Key('refs-cell-5')));
    expect(tester.getRect(modal).bottom, lessThanOrEqualTo(row.top));

    // Arriving from below flips it under the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.getRect(modal).top, greaterThanOrEqualTo(row.bottom));

    // Leaving the row hides it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
  });

  testWidgets('avatar lookup is limited to rows in the short viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 180);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final requested = <int>[];
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async {
        requested.add(int.parse(arguments.last.split('/').last));
        return ProcessResult(1, 1, '', 'offline');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => List.generate(
              100,
              (index) => commit('$index', 'commit $index'),
            ),
          ),
          controller: controller,
          avatarService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, isNotEmpty);
    expect(requested, everyElement(lessThan(12)));
  });

  testWidgets('timeline passes avatar settings into full diff blame', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    var requests = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async {
        requests++;
        return ProcessResult(1, 1, '', 'offline');
      },
    );
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('40aff6d1', 'aligned blame', parents: const ['parent']),
      ],
      refs: const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': '40aff6d1'},
        localTips: {'main': '40aff6d1'},
      ),
      files: (_, _) async => const [
        GitFileChange(
          path: 'lib/aligned.dart',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old line', oldNumber: 1),
        DiffLine(kind: DiffLineKind.add, text: 'new line', newNumber: 1),
      ],
      content: (_, _, _) async => Uint8List.fromList('new line\n'.codeUnits),
      blame: (_, _, _, _) async => const [
        GitBlameLine(
          lineNumber: 1,
          sha: '40aff6d1',
          author: 'Suwon Chae',
          authorEmail: 'suwon@example.com',
          authorTimestamp: 1704067200,
          summary: 'Align blame metadata',
          uncommitted: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: controller,
          avatarService: service,
          showRemoteAvatars: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-full-diff')));
    await tester.pumpAndSettle();

    final diffScreen = tester.widget<DiffScreen>(find.byType(DiffScreen));
    expect(diffScreen.avatarService, same(service));
    expect(diffScreen.showRemoteAvatars, isFalse);

    await tester.tap(find.text('Blame').last);
    await tester.pumpAndSettle();

    final blameView = tester.widget<FullBlameView>(find.byType(FullBlameView));
    expect(blameView.avatarService, same(service));
    expect(blameView.showRemoteAvatars, isFalse);
    final avatar = tester.widget<IdentityAvatar>(
      find.byKey(const Key('blame-avatar-1')),
    );
    expect(avatar.identity.name, 'Suwon Chae');
    expect(avatar.identity.email, 'suwon@example.com');
    expect(find.text('SC'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('paging keeps one request in flight and shows end state', (
    tester,
  ) async {
    final secondPage = Completer<List<GitCommit>>();
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) {
      calls++;
      if (skip == 0) {
        return Future.value(
          List.generate(500, (index) => commit('$index', 'commit $index')),
        );
      }
      return secondPage.future;
    });

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.drag(
      // Dragged by viewport: the list is wider than the visible columns.
      find.byKey(const Key('timeline-viewport')),
      const Offset(0, -20000),
    );
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Loading more…'), findsOneWidget);

    secondPage.complete([commit('500', 'last commit')]);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('End of history'), findsOneWidget);
  });

  testWidgets('paging starts at twelve remaining rows, not thirteen', (
    tester,
  ) async {
    final nextPage = Completer<List<GitCommit>>();
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) {
      calls++;
      if (skip == 0) {
        return Future.value(
          List.generate(500, (index) => commit('$index', 'commit $index')),
        );
      }
      return nextPage.future;
    });
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );

    scrollable.position.jumpTo(
      scrollable.position.maxScrollExtent - 13 * TimelineScreen.rowHeight,
    );
    await tester.pump();
    expect(calls, 1);

    scrollable.position.jumpTo(
      scrollable.position.maxScrollExtent - 12 * TimelineScreen.rowHeight,
    );
    await tester.pump();
    expect(calls, 2);

    nextPage.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('paging error retries the same page', (tester) async {
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) async {
      calls++;
      if (calls == 1) throw StateError('temporary failure');
      return [commit('1', 'recovered commit')];
    });

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    expect(find.text('Could not load history'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Timeline row plus the opened preview title.
    expect(find.text('recovered commit'), findsNWidgets(2));
    expect(find.text('End of history'), findsOneWidget);
  });

  testWidgets('empty history shows its end state without a load error', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => const []), controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('No commits'), findsOneWidget);
    expect(find.text('Could not load history'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the full diff and preserves timeline state on escape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final histogram = Completer<List<DiffLine>>();
    final calls =
        <
          ({String sha, String? parent, String path, DiffAlgorithm algorithm})
        >[];
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('merge', 'merge commit', parents: const ['main', 'feature']),
        commit('main', 'main commit', parents: const ['base']),
        commit('feature', 'feature commit', parents: const ['base']),
      ],
      files: (commit, parent) async => [
        const GitFileChange(
          path: 'lib/a.dart',
          status: 'M',
          additions: 2,
          deletions: 1,
        ),
        const GitFileChange(
          path: 'lib/b.dart',
          status: 'A',
          additions: 1,
          deletions: 0,
        ),
      ],
      diff: (commit, parent, path, algorithm, _) {
        calls.add((
          sha: commit.sha,
          parent: parent,
          path: path,
          algorithm: algorithm,
        ));
        if (algorithm == DiffAlgorithm.histogram) return histogram.future;
        return Future.value([
          const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          const DiffLine(
            kind: DiffLineKind.delete,
            text: 'old line',
            oldNumber: 1,
          ),
          const DiffLine(
            kind: DiffLineKind.add,
            text: 'new line',
            newNumber: 1,
          ),
        ]);
      },
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('preview-full-diff')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
    expect(find.byKey(const Key('nearby-column-resizer')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      290,
    );
    expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
    expect(find.byKey(const Key('changed-files-list')), findsOneWidget);
    expect(find.byKey(const Key('unified-list')), findsOneWidget);
    expect(find.textContaining('change 1 of 1'), findsOneWidget);
    expect(find.text('1 / 1'), findsWidgets);
    expect(find.text('Unified'), findsOneWidget);
    expect(find.text('Side-by-side'), findsOneWidget);
    expect(find.text('Hunk'), findsOneWidget);
    expect(find.text('diff 알고리즘'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm-value')),
        matching: find.text('Myers'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('changed-files-list'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('unified-list'))).dx),
    );
    expect(find.byKey(const Key('merge-parent-chooser')), findsOneWidget);

    await tester.tap(find.byKey(const Key('merge-parent-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Parent 2').last);
    await tester.pumpAndSettle();
    expect(calls.last.parent, 'feature');

    await tester.tap(find.text('lib/b.dart'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-file-lib/b.dart')), findsOneWidget);

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    final histogramItem = find.byKey(const Key('algorithm-option-histogram'));
    await tester.ensureVisible(histogramItem);
    await tester.pump();
    await tester.tap(histogramItem);
    await tester.pump();
    expect(find.text('old line'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(calls.last.algorithm, DiffAlgorithm.histogram);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm-value')),
        matching: find.text('Myers'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('selected-file-lib/b.dart')), findsOneWidget);

    histogram.complete([
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      const DiffLine(
        kind: DiffLineKind.add,
        text: 'histogram line',
        newNumber: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('histogram line'), findsOneWidget);
    expect(calls.last.algorithm, DiffAlgorithm.histogram);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm-value')),
        matching: find.text('Histogram'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('full-diff-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-merge')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview-full-diff')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('code-row-source-text')).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
  });

  testWidgets('full diff starts with saved column widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
          columnWidths: const FullDiffColumnWidths(history: 240, files: 330),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      330,
    );
  });

  testWidgets('full diff restores and saves exact minimum column widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [],
    );
    final restored = AppSettings.fromJson({
      'fullDiffColumnWidths': {'commits': 126, 'files': 158},
    }).fullDiffColumnWidths;
    FullDiffColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
          columnWidths: restored,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      158,
    );

    await tester.drag(
      find.byKey(const Key('details-files-column-resizer')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();

    expect(saved, const FullDiffColumnWidths(history: 180, files: 158));
  });

  testWidgets('focus mode hides navigation and restores saved widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [],
    );
    FullDiffColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
          columnWidths: const FullDiffColumnWidths(history: 240, files: 330),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby-column')), findsNothing);
    await tester.tap(find.byKey(const Key('focus-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(find.byKey(const Key('details-files-column')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('diff-column'))).width, 1200);
    expect(saved, isNull);

    await tester.tap(find.byKey(const Key('focus-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      330,
    );
    expect(saved, isNull);
  });

  testWidgets(
    'full diff resizes files and preserves the stored History width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final repository = FakeGitRepository(
        (_, _) async => [commit('1', 'commit')],
        files: (_, _) async => const [],
      );
      FullDiffColumnWidths? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: DiffScreen(
            repository: repository,
            commits: [commit('1', 'commit')],
            initialIndex: 0,
            onColumnWidthsChanged: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('details-files-column-resizer')),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('details-files-column'))).width,
        330,
      );
      expect(saved, const FullDiffColumnWidths(history: 280, files: 330));
    },
  );

  testWidgets('narrow full diff uses exact pane thresholds without saving', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [],
    );
    FullDiffColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
          columnWidths: const FullDiffColumnWidths(history: 240, files: 330),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1070, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
    expect(find.byKey(const Key('nearby-column-resizer')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsOneWidget);
    expect(saved, isNull);

    tester.view.physicalSize = const Size(650, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsOneWidget);
    expect(saved, isNull);

    tester.view.physicalSize = const Size(481, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsOneWidget);
    expect(saved, isNull);

    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);
    expect(saved, isNull);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      330,
    );
    expect(saved, isNull);
  });

  testWidgets('full diff widths load from and save to app settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final store = MemorySettingsStore()
      ..current = const AppSettings(
        fullDiffColumnWidths: FullDiffColumnWidths(history: 240, files: 330),
      );
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'commit')],
          files: (_, _) async => const [],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      330,
    );

    await tester.drag(
      find.byKey(const Key('details-files-column-resizer')),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expect(
      store.current.fullDiffColumnWidths,
      const FullDiffColumnWidths(history: 240, files: 360),
    );
  });

  testWidgets('failed algorithm keeps the displayed algorithm and lines', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('1', 'commit', parents: const ['0']),
      ],
      files: (_, _) async => [
        const GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, algorithm, _) => algorithm == DiffAlgorithm.minimal
          ? Future.error(StateError('minimal failed'))
          : Future.value([
              const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              const DiffLine(
                kind: DiffLineKind.context,
                text: 'displayed line',
                oldNumber: 1,
                newNumber: 1,
              ),
            ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [
            commit('1', 'commit', parents: const ['0']),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    final minimalItem = find.byKey(const Key('algorithm-option-minimal'));
    await tester.ensureVisible(minimalItem);
    await tester.tap(minimalItem);
    await tester.pumpAndSettle();

    expect(find.text('displayed line'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm-value')),
        matching: find.text('Myers'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('minimal failed'), findsOneWidget);
  });

  testWidgets('initial file loading has a distinct pending state', (
    tester,
  ) async {
    final files = Completer<List<GitFileChange>>();
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) => files.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('diff-pending-files')), findsOneWidget);
    expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsNothing);

    files.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('initial diff loading has a distinct pending state', (
    tester,
  ) async {
    final diff = Completer<List<DiffLine>>();
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [
        GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 0,
          deletions: 0,
        ),
      ],
      diff: (_, _, _, _, _) => diff.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('diff-pending-first-diff')), findsOneWidget);
    expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsNothing);

    diff.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('an initial diff failure does not look like an empty diff', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [
        GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 0,
          deletions: 0,
        ),
      ],
      diff: (_, _, _, _, _) => Future.error(StateError('initial failed')),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('diff-error-without-document')),
      findsOneWidget,
    );
    expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsNothing);
    expect(find.textContaining('initial failed'), findsWidgets);
  });

  testWidgets('a successfully loaded empty document says no changes', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [
        GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 0,
          deletions: 0,
        ),
      ],
      diff: (_, _, _, _, _) async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 옵션으로 표시할 변경이 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('diff-pending-files')), findsNothing);
    expect(find.byKey(const Key('diff-pending-first-diff')), findsNothing);
    expect(find.byKey(const Key('diff-error-without-document')), findsNothing);
  });

  testWidgets('unified rows mark additions and deletions', (tester) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => [
        const GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        const DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
        const DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deletion = find.byKey(const Key('unified-line-0-0'));
    final addition = find.byKey(const Key('unified-line-0-1'));
    expect(
      find.descendant(of: deletion, matching: find.text('−')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: addition, matching: find.text('+')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(of: deletion, matching: find.byType(ColoredBox))
                .first,
          )
          .color,
      fullDiffDeletedSource,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(of: addition, matching: find.byType(ColoredBox))
                .first,
          )
          .color,
      fullDiffAddedSource,
    );
  });

  testWidgets('merge parent labels reserve technical font for the SHA', (
    tester,
  ) async {
    const firstParent = '1111111111111111111111111111111111111111';
    const secondParent = '2222222222222222222222222222222222222222';
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('merge', 'merge', parents: const [firstParent, secondParent]),
      ],
      files: (_, _) async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [
            commit(
              'merge',
              'merge',
              parents: const [firstParent, secondParent],
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.textContaining('Parent 1').first);
    final spans = (label.textSpan as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, 'Parent 1 · ');
    expect(spans.first.style?.fontFamily, isNull);
    expect(spans.last.text, '1111111');
    expect(spans.last.style?.fontFamily, technicalFontFamily);
    expect(spans.last.style?.fontFamilyFallback, technicalFontFallback);
  });

  testWidgets('an injected full diff controller stays externally owned', (
    tester,
  ) async {
    var fileLoads = 0;
    final commits = [
      commit('1', 'commit', parents: const ['0']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async {
        fileLoads++;
        return const [
          GitFileChange(
            path: 'file.txt',
            status: 'M',
            additions: 1,
            deletions: 0,
          ),
        ];
      },
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1 @@'),
        DiffLine(kind: DiffLineKind.add, text: 'line', newNumber: 1),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fileLoads, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    session.setWrapLines(false);

    expect(session.state.wrapLines, isFalse);
    expect(fileLoads, 1);
  });

  testWidgets('full diff replaces its owned session when inputs change', (
    tester,
  ) async {
    final oldCommits = [
      commit('old', 'old commit', parents: const ['base']),
    ];
    final newCommits = [
      commit('new', 'new commit', parents: const ['base']),
    ];
    final oldRepository = FakeGitRepository(
      (_, _) async => oldCommits,
      files: (_, _) async => const [
        GitFileChange(path: 'old.txt', status: 'M', additions: 1, deletions: 0),
      ],
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1 @@'),
        DiffLine(kind: DiffLineKind.add, text: 'old body', newNumber: 1),
      ],
    );
    final newRepository = FakeGitRepository(
      (_, _) async => newCommits,
      files: (_, _) async => const [
        GitFileChange(path: 'new.txt', status: 'M', additions: 1, deletions: 0),
      ],
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1 @@'),
        DiffLine(kind: DiffLineKind.add, text: 'new body', newNumber: 1),
      ],
    );

    Widget screen(
      FullDiffRepository repository,
      List<GitCommit> screenCommits,
      FullDiffPreferences preferences,
    ) => MaterialApp(
      home: DiffScreen(
        repository: repository,
        commits: screenCommits,
        initialIndex: 0,
        initialPreferences: preferences,
      ),
    );

    await tester.pumpWidget(
      screen(oldRepository, oldCommits, const FullDiffPreferences()),
    );
    await tester.pumpAndSettle();
    expect(find.text('old body'), findsOneWidget);

    await tester.pumpWidget(
      screen(
        newRepository,
        newCommits,
        const FullDiffPreferences(layout: DiffLayout.sideBySide),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('new body'), findsOneWidget);
    expect(find.text('old body'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Side-by-side'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('initial preferences do not reset a live owned session', (
    tester,
  ) async {
    final commits = [
      commit('one', 'commit', parents: const ['base']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async => const [
        GitFileChange(
          path: 'first.txt',
          status: 'M',
          additions: 1,
          deletions: 0,
        ),
        GitFileChange(
          path: 'second.txt',
          status: 'M',
          additions: 1,
          deletions: 0,
        ),
      ],
      diff: (_, _, path, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1 @@'),
        DiffLine(kind: DiffLineKind.add, text: path, newNumber: 1),
      ],
    );

    Widget screen(FullDiffPreferences preferences) => MaterialApp(
      home: DiffScreen(
        repository: repository,
        commits: commits,
        initialIndex: 0,
        initialPreferences: preferences,
      ),
    );

    await tester.pumpWidget(screen(const FullDiffPreferences()));
    await tester.pumpAndSettle();
    tester
        .widget<Focus>(find.byKey(const Key('changed-files-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-file-second.txt')), findsOneWidget);

    await tester.pumpWidget(
      screen(const FullDiffPreferences(layout: DiffLayout.sideBySide)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-file-second.txt')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Unified'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
  });

  testWidgets('file and parent changes reset the hunk list to the top', (
    tester,
  ) async {
    List<DiffLine> longDocument(String path) => [
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,80 +1,80 @@'),
      for (var index = 1; index <= 80; index++)
        DiffLine(
          kind: DiffLineKind.context,
          text: '$path line $index',
          oldNumber: index,
          newNumber: index,
        ),
    ];
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('merge', 'merge', parents: const ['main', 'feature']),
      ],
      files: (_, _) async => const [
        GitFileChange(path: 'one.txt', status: 'M', additions: 0, deletions: 0),
        GitFileChange(path: 'two.txt', status: 'M', additions: 0, deletions: 0),
      ],
      diff: (_, _, path, _, _) async => longDocument(path),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [
            commit('merge', 'merge', parents: const ['main', 'feature']),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    ScrollPosition contentPosition() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    Future<void> scrollDown() async {
      await tester.drag(
        find
            .descendant(
              of: find.byKey(const Key('content-scrollable')),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(contentPosition().pixels, greaterThan(0));
    }

    await scrollDown();
    await tester.tap(find.text('two.txt'));
    await tester.pumpAndSettle();
    expect(contentPosition().pixels, 0);

    await scrollDown();
    await tester.tap(find.byKey(const Key('merge-parent-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Parent 2').last);
    await tester.pumpAndSettle();
    expect(contentPosition().pixels, 0);
  });

  test(
    'the folder picker returns the native path, or null with no plugin',
    () async {
      final calls = <String>[];
      const picker = MethodChannel('test/yogit-picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            calls.add(call.method);
            return '/Users/ada/repo';
          });

      expect(
        await WindowFrameController(channel: picker).pickRepository(),
        '/Users/ada/repo',
      );
      expect(calls, ['pickRepository']);
      // No native side, so the timeline keeps the repository it has.
      expect(
        await WindowFrameController(
          channel: const MethodChannel('test/yogit-no-plugin'),
        ).pickRepository(),
        isNull,
      );
    },
  );

  testWidgets(
    'bootstrap can recover from a non-repository with the folder picker',
    (tester) async {
      const picker = MethodChannel('test/yogit-bootstrap-picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            picker,
            (call) async =>
                call.method == 'pickRepository' ? '/Users/ada/repo' : null,
          );
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async {
        if (arguments.contains('--show-toplevel')) {
          final path = arguments[1];
          return path == '/Users/ada/plain'
              ? ProcessResult(1, 128, '', 'not a git repository')
              : ProcessResult(1, 0, '/Users/ada/repo\n', '');
        }
        return ProcessResult(1, 0, '', '');
      }

      await tester.pumpWidget(
        YogitBootstrap(
          requestedPath: '/Users/ada/plain',
          gitExecutable: '/usr/bin/git',
          runner: runner,
          windowFrameController: WindowFrameController(channel: picker),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('저장소 열기'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bootstrap-pick-repository')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('timeline-screen-/Users/ada/repo')),
        findsOneWidget,
      );
    },
  );

  testWidgets('bootstrap full-file diff uses the bounded raw runner', (
    tester,
  ) async {
    var textDiffCalls = 0;
    var rawDiffCalls = 0;
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async {
      if (arguments.contains('--show-toplevel')) {
        return ProcessResult(1, 0, '/Users/ada/repo\n', '');
      }
      if (arguments.firstOrNull == 'diff') textDiffCalls++;
      return ProcessResult(1, 0, '', '');
    }

    await tester.pumpWidget(
      YogitBootstrap(
        requestedPath: '/Users/ada/repo',
        gitExecutable: '/usr/bin/git',
        runner: runner,
        rawRunner: (executable, arguments, {workingDirectory}) async {
          if (arguments.firstOrNull == 'diff') rawDiffCalls++;
          return ProcessResult(
            1,
            0,
            utf8.encode(
              'diff --git a/sample.txt b/sample.txt\n'
              '--- a/sample.txt\n'
              '+++ b/sample.txt\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+new\n',
            ),
            '',
          );
        },
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    final repository = tester
        .widget<TimelineScreen>(find.byType(TimelineScreen))
        .repository;

    final lines = await repository.loadDiff(
      commit('target', 'target', parents: const ['base']),
      const GitFileChange(
        path: 'sample.txt',
        status: 'M',
        additions: 1,
        deletions: 1,
      ),
      scope: DiffScope.fullFile,
    );

    expect(rawDiffCalls, 1);
    expect(textDiffCalls, 0);
    expect(lines.where((line) => line.kind == DiffLineKind.add), hasLength(1));
  });

  testWidgets('the folder button opens a picked repository, or says why not', (
    tester,
  ) async {
    final picks = <String>['/Users/ada/next', '/Users/ada/plain'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('test/yogit-window'),
          (call) async =>
              call.method == 'pickRepository' ? picks.removeAt(0) : null,
        );
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async => arguments.contains('/Users/ada/next')
        ? ProcessResult(1, 0, '/Users/ada/next\n', '')
        : ProcessResult(1, 128, '', 'not a git repository');

    final opened = <String>[];
    final store = MemorySettingsStore();
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/Users/ada/first',
          runner: runner,
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
        repositoryFactory: (root) {
          opened.add(root);
          return FakeGitRepository(
            (_, _) async => [commit('2', 'next repo commit')],
            root: root,
            runner: runner,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();

    expect(opened, ['/Users/ada/next']);
    expect(find.text('next'), findsOneWidget);
    // Switching away is what commits the repository being left to the list.
    expect(store.current.recentRepositories, [
      '/Users/ada/next',
      '/Users/ada/first',
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Timeline row plus the preview title, and the old history is gone.
    expect(find.text('next repo commit'), findsNWidgets(2));
    expect(find.text('first commit'), findsNothing);

    // A plain directory is reported inline and changes nothing.
    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();
    expect(find.text('Git 저장소가 아닙니다: /Users/ada/plain'), findsOneWidget);
    expect(opened, ['/Users/ada/next']);
    expect(find.text('next'), findsOneWidget);
    expect(find.text('next repo commit'), findsNWidgets(2));

    // Let the notice expire so its timer does not outlive the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('repository switch ignores stale avatar discovery', (
    tester,
  ) async {
    final firstOrigin = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('test/yogit-window'),
          (call) async =>
              call.method == 'pickRepository' ? '/repo/second' : null,
        );
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async => ProcessResult(1, 0, '/repo/second\n', '');

    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('first', 'first')],
          root: '/repo/first',
          runner: runner,
          originUrlCallback: () => firstOrigin.future,
        ),
        repositoryFactory: (root) => FakeGitRepository(
          (_, _) async => [commit('second', 'second')],
          root: root,
          runner: runner,
          originUrlCallback: () async => 'https://github.com/team/second.git',
        ),
        settingsStore: MemorySettingsStore(),
        ghExecutable: 'gh',
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimelineScreen>(find.byType(TimelineScreen))
          .avatarService
          ?.remote
          .repository,
      'second',
    );

    firstOrigin.complete('https://github.com/team/first.git');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimelineScreen>(find.byType(TimelineScreen))
          .avatarService
          ?.remote
          .repository,
      'second',
    );
  });

  test('native close clamps the saved frame to a current visible screen', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    // The folder picker rides the same channel as the frame calls.
    for (final line in [
      'case "pickRepository":',
      'panel.canChooseDirectories = true',
      'panel.canChooseFiles = false',
      'panel.allowsMultipleSelection = false',
      'panel.prompt = "Open"',
      'return panel.runModal() == .OK ? panel.url?.path : nil',
    ]) {
      expect(source, contains(line));
    }
    expect(
      source,
      contains(
        'setFrame(clamped(baseFrame, to: visibleFrame), display: true, animate: true)',
      ),
    );
    expect(
      source,
      contains(
        'private func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect',
      ),
    );
    expect(source, isNot(contains('baseFrame.intersection(visibleFrame)')));
  });

  test('settings persist only the supported fields', () async {
    final directory = await Directory.systemTemp.createTemp('yogit_settings_');
    addTearDown(() => directory.delete(recursive: true));
    final store = SettingsStore(File('${directory.path}/nested/settings.json'));

    expect(await store.load(), const AppSettings());
    const saved = AppSettings(
      showAvatars: false,
      timelineTheme: TimelineThemeKind.warmGraphite,
      previewPlacement: PreviewPlacement.bottom,
      columnWidths: TimelineColumnWidths(graph: 220),
      baseBranches: {'/repos/one': 'main', '/repos/two': 'release'},
    );
    await store.save(saved);

    final restored = await store.load();
    expect(restored.showAvatars, isFalse);
    expect(restored.timelineTheme, TimelineThemeKind.warmGraphite);
    expect(restored.previewPlacement, PreviewPlacement.bottom);
    expect(restored.columnWidths.graph, isNull);
    final json = jsonDecode(await store.file.readAsString());
    expect(json['showAvatars'], isFalse);
    expect(json['timelineTheme'], 'warmGraphite');
    expect(json['columnWidths'], isNot(contains('graph')));
    expect(json, isNot(contains('token')));

    await store.save(
      const AppSettings(previewPlacement: PreviewPlacement.left),
    );
    expect((await store.load()).previewPlacement, PreviewPlacement.left);
  });

  test('the settings path never comes from the working directory', () {
    expect(
      SettingsStore.pathForHome('/Users/tester'),
      '/Users/tester/Library/Application Support/yogit/settings.json',
    );
    // With no HOME the fallback stays out of the working directory: inside the
    // opened repository it would let the repository set the command we run. It
    // is a fresh directory every time, so no other local user can plant the
    // file we would read at a path they can guess.
    final fallbacks = <String>{};
    for (final home in [null, '']) {
      final path = SettingsStore.pathForHome(home);
      addTearDown(() => File(path).parent.delete(recursive: true));
      expect(path, startsWith(Directory.systemTemp.path));
      expect(path, isNot(contains(Directory.current.path)));
      expect(fallbacks.add(path), isTrue);
    }
  });

  test('repository argument and executable lookup avoid a shell', () async {
    final directory = await Directory.systemTemp.createTemp('yogit_exec_');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/git');
    await executable.writeAsString('');

    expect(repositoryPathFromArgs(['--repo', '/tmp/project']), '/tmp/project');
    expect(
      () => repositoryPathFromArgs(['--repo']),
      throwsA(isA<FormatException>()),
    );
    expect(
      resolveExecutable(
        'git',
        environment: {'PATH': directory.path},
        exists: (path) => path == executable.path,
      ),
      executable.path,
    );
    final launch = launchOptionsFromArgs([
      '--repo',
      '/tmp/project',
      '--git',
      '/usr/bin/git',
      '--gh',
      '/usr/bin/true',
    ]);
    expect(launch.repositoryPath, '/tmp/project');
    expect(launch.gitExecutable, '/usr/bin/git');
    expect(launch.ghExecutable, '/usr/bin/true');
    expect(
      () => launchOptionsFromArgs(['--git', 'git']),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => launchOptionsFromArgs(['--git', '/does/not/exist/git']),
      throwsA(isA<FormatException>()),
    );

    final calls = <List<String>>[];
    final root = await resolveRepositoryRoot(
      '/tmp/project',
      gitExecutable: executable.path,
      runner: (command, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        return ProcessResult(1, 0, '/tmp/project\n', '');
      },
    );
    expect(root, '/tmp/project');
    expect(calls.single, [
      '-C',
      '/tmp/project',
      'rev-parse',
      '--show-toplevel',
    ]);

    await expectLater(
      resolveRepositoryRoot(
        '/tmp/not-a-repository',
        runner: (command, arguments, {workingDirectory, environment}) async =>
            ProcessResult(1, 128, '', 'not a git repository'),
      ),
      throwsA(isA<GitRepositoryException>()),
    );
  });

  testWidgets(
    'YogitApp starts from checkout and persists later base selection',
    (tester) async {
      final store = MemorySettingsStore()
        ..current = const AppSettings(
          baseBranches: {'/repos/one': 'release', '/repos/two': 'main'},
        );
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'tip')],
            root: '/repos/one',
            refs: const RepoRefs(
              local: ['main', 'release'],
              current: 'main',
              tips: {'main': 'tip', 'release': 'tip'},
            ),
          ),
          settingsStore: store,
          discoverAvatars: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('base-branch-selector')),
          matching: find.text('main'),
        ),
        findsOneWidget,
      );
      expect(store.current.baseBranches, {
        '/repos/one': 'main',
        '/repos/two': 'main',
      });

      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-menu-release')));
      await tester.pumpAndSettle();

      expect(store.current.baseBranches, {
        '/repos/one': 'release',
        '/repos/two': 'main',
      });
    },
  );

  testWidgets('base branch survives ref reload during the session', (
    tester,
  ) async {
    var refLoads = 0;
    final fetched = <String>[];
    const refs = RepoRefs(
      local: ['main', 'release'],
      current: 'main',
      tips: {'main': 'main-tip', 'release': 'release-tip'},
      localTips: {'main': 'main-tip', 'release': 'release-tip'},
      upstreams: {'release': 'company/release'},
      upstreamRemotes: {'release': 'company'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('release-tip', 'release'),
              commit('main-tip', 'main'),
            ],
            refsLoader: () async {
              refLoads++;
              return refs;
            },
            fetchRemoteCallback: (remote) async {
              fetched.add(remote);
              return FetchOriginResult.updated;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-branch-menu-release')));
    await tester.pumpAndSettle();

    expect(refLoads, 2);
    expect(fetched, ['company']);
    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-selector')),
        matching: find.text('release'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('recent ref choices lead each branch selector group', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'tip')],
            refs: const RepoRefs(
              local: ['old', 'new'],
              remote: ['origin/old', 'origin/new'],
              tags: ['v1.0.0', 'v2.0.0'],
              current: 'old',
              tips: {
                'old': 'tip',
                'new': 'tip',
                'origin/old': 'tip',
                'origin/new': 'tip',
                'v1.0.0': 'tip',
                'v2.0.0': 'tip',
              },
              branchActivityTimes: {
                'old': 100,
                'new': 300,
                'origin/old': 200,
                'origin/new': 400,
              },
              birthTimes: {'old': 150, 'new': 250},
              tagCreatorTimes: {'v1.0.0': 500, 'v2.0.0': 600},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('base-branch-menu-new'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('base-branch-menu-old'))).dy,
      ),
    );
    await tester.tap(find.byKey(const Key('base-branch-menu-new')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const Key('branch-diff-menu-origin/new')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('branch-diff-menu-origin/old')))
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('branch-diff-menu-v2.0.0'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('branch-diff-menu-v1.0.0'))).dy,
      ),
    );
  });

  testWidgets(
    'YogitApp persists a fallback resolved before settings finish loading',
    (tester) async {
      final store = DelayedMemorySettingsStore();
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'tip')],
            root: '/repos/one',
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'tip'},
            ),
          ),
          settingsStore: store,
          discoverAvatars: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main'), findsWidgets);
      expect(store.saveCount, 0);

      store.completeLoad();
      await tester.pumpAndSettle();

      expect(store.current.baseBranches, {'/repos/one': 'main'});
      expect(store.saveCount, 1);
    },
  );

  testWidgets(
    'YogitApp keeps a base branch selected before settings finish loading',
    (tester) async {
      final store = DelayedMemorySettingsStore()
        ..current = const AppSettings(baseBranches: {'/repos/one': 'main'});
      await tester.pumpWidget(
        YogitApp(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'tip')],
            root: '/repos/one',
            refs: const RepoRefs(
              local: ['main', 'release'],
              current: 'main',
              tips: {'main': 'tip', 'release': 'tip'},
            ),
          ),
          settingsStore: store,
          discoverAvatars: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-menu-release')));
      await tester.pumpAndSettle();

      expect(find.text('release'), findsWidgets);
      expect(store.saveCount, 0);

      store.completeLoad();
      await tester.pumpAndSettle();

      expect(find.text('release'), findsWidgets);
      expect(store.current.baseBranches, {'/repos/one': 'release'});
      expect(store.saveCount, 1);
    },
  );

  testWidgets('a failed settings write keeps the selected base branch', (
    tester,
  ) async {
    final store = FailingSettingsStore()
      ..current = const AppSettings(baseBranches: {'/repos/one': 'main'});
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('tip', 'tip')],
          root: '/repos/one',
          refs: const RepoRefs(
            local: ['main', 'release'],
            current: 'main',
            tips: {'main': 'tip', 'release': 'tip'},
          ),
        ),
        settingsStore: store,
        discoverAvatars: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-branch-menu-release')));
    await tester.pumpAndSettle();

    expect(find.text('release'), findsWidgets);
    expect(find.byType(TimelineScreen), findsOneWidget);
  });

  test('yo launcher builds once and passes the resolved repository path', () {
    final file = File('bin/yo');
    final source = file.readAsStringSync();

    expect(FileStat.statSync(file.path).mode & 0x40, isNot(0));
    expect(source, contains(r'git_bin=$(command -v git)'));
    expect(source, contains('flutter build macos'));
    expect(source, contains(r'set -- --repo "$root" --git "$git_bin"'));
    expect(source, contains(r'set -- "$@" --gh "$gh_bin"'));
    expect(source, contains('/usr/bin/open'));
    expect(source, contains(r'-n "$app" --args "$@"'));
    expect(File('README.md').readAsStringSync(), contains('Flutter 3.41.8'));
  });

  test('parses GitHub and GHE remotes without accepting non-network URLs', () {
    expect(
      RemoteRepository.tryParse('git@github.com:example/project.git'),
      const RemoteRepository(
        host: 'github.com',
        owner: 'example',
        repository: 'project',
      ),
    );
    expect(
      RemoteRepository.tryParse('https://git.example.com/team/yogit.git'),
      const RemoteRepository(
        host: 'git.example.com',
        owner: 'team',
        repository: 'yogit',
      ),
    );
    expect(RemoteRepository.tryParse('/tmp/local.git'), isNull);
  });

  test('avatar lookup uses gh once per SHA and never requests Gravatar', () async {
    final requests = <List<String>>[];
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      ghExecutable: '/usr/bin/gh',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        requests.add(arguments);
        return ProcessResult(
          1,
          0,
          '{"author":{"login":"ada","avatar_url":"https://avatars.example/ada"},'
              '"committer":{"login":"cam","avatar_url":"https://avatars.example/cam"}}',
          '',
        );
      },
    );

    final first = service.resolve('abc1234');
    final second = service.resolve('abc1234');
    final avatars = await first;

    expect(identical(first, second), isTrue);
    expect(avatars.author?.login, 'ada');
    expect(avatars.committer?.login, 'cam');
    expect(requests, hasLength(1));
    expect(requests.single, [
      'api',
      '--hostname',
      'github.com',
      'repos/team/yogit/commits/abc1234',
    ]);
    expect(
      requests
          .expand((request) => request)
          .any((argument) => argument.toLowerCase().contains('gravatar')),
      isFalse,
    );
  });

  test(
    'deleted branch PR lookup prefers an exact head sha over a newer merge',
    () async {
      final requests = <List<String>>[];
      final service = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        ghExecutable: '/usr/bin/gh',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          requests.add(arguments);
          return ProcessResult(1, 0, '''
[
  {"number":2,"state":"closed","merged_at":"2026-07-28T12:00:00Z","head":{"sha":"other","ref":"newer"}},
  {"number":1,"state":"closed","merged_at":"2026-07-27T12:00:00Z","head":{"sha":"tip","ref":"exact"}}
]
''', '');
        },
      );

      expect(await service.resolveMergedBranchName('tip'), 'exact');
      expect(requests.single, [
        'api',
        '--hostname',
        'github.com',
        'repos/team/yogit/commits/tip/pulls',
      ]);
    },
  );

  test(
    'deleted branch PR lookup uses the newest merge when no head matches',
    () async {
      final service = AvatarService(
        remote: const RemoteRepository(
          host: 'git.example.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(1, 0, '''
[
  {"number":1,"state":"closed","merged_at":"2026-07-27T12:00:00Z","head":{"sha":"first","ref":"older"}},
  {"number":2,"state":"closed","merged_at":"2026-07-28T12:00:00Z","head":{"sha":"second","ref":"newer"}}
]
''', ''),
      );

      expect(await service.resolveMergedBranchName('tip'), 'newer');
    },
  );

  test('deleted branch PR lookup ignores unusable responses', () async {
    for (final response in [
      ProcessResult(1, 1, '', 'offline'),
      ProcessResult(1, 0, 'not json', ''),
      ProcessResult(
        1,
        0,
        '[{"merged_at":null,"head":{"sha":"tip","ref":"open"}}]',
        '',
      ),
      ProcessResult(
        1,
        0,
        '[{"merged_at":"not-a-date","head":{"sha":"tip","ref":"bad"}}]',
        '',
      ),
    ]) {
      final service = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                response,
      );

      expect(await service.resolveMergedBranchName('tip'), isNull);
    }
  });

  test('deleted branch PR lookup handles a missing gh executable', () async {
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async {
        throw ProcessException(executable, arguments, 'missing');
      },
    );

    expect(await service.resolveMergedBranchName('tip'), isNull);
  });

  test('drops Gravatar avatar URLs returned by GitHub and GHE', () async {
    for (final entry in {
      'github.com': 'https://gravatar.com/avatar/ada',
      'git.example.com': 'https://cdn.gravatar.com/avatar/ada',
    }.entries) {
      final service = AvatarService(
        remote: RemoteRepository(
          host: entry.key,
          owner: 'team',
          repository: 'yogit',
        ),
        runner:
            (
              executable,
              arguments, {
              workingDirectory,
              environment,
            }) async => ProcessResult(
              1,
              0,
              '{"author":{"login":"ada","avatar_url":"${entry.value}"},'
                  '"committer":{"login":"cam","avatar_url":"https://notgravatar.com/cam"}}',
              '',
            ),
      );

      final avatars = await service.resolve(entry.key);

      expect(avatars.author, isNull, reason: entry.key);
      expect(avatars.committer?.login, 'cam', reason: entry.key);
    }
  });

  test('GHE token headers stay on the selected remote host', () async {
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'git.example.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async {
        if (arguments.take(2).join(' ') == 'auth token') {
          return ProcessResult(1, 0, 'secret-token\n', '');
        }
        return ProcessResult(
          1,
          0,
          '{"author":{"login":"ada","avatar_url":"https://cdn.example/ada"},'
              '"committer":{"login":"cam","avatar_url":"https://git.example.com/cam"}}',
          '',
        );
      },
    );

    final avatars = await service.resolve('abc1234');

    expect(avatars.author?.headers, isEmpty);
    expect(avatars.committer?.headers['Authorization'], 'Bearer secret-token');
  });

  test('avatar lookup runs at most four gh requests concurrently', () async {
    final gates = List.generate(5, (_) => Completer<ProcessResult>());
    var active = 0;
    var peak = 0;
    var started = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) {
        final gate = gates[started++];
        active++;
        peak = active > peak ? active : peak;
        return gate.future.whenComplete(() => active--);
      },
    );

    final futures = List.generate(5, (index) => service.resolve('$index'));
    await Future<void>.delayed(Duration.zero);
    expect(started, 4);
    expect(peak, 4);

    gates.first.complete(ProcessResult(1, 1, '', 'offline'));
    await Future<void>.delayed(Duration.zero);
    expect(started, 5);
    for (final gate in gates.skip(1)) {
      gate.complete(ProcessResult(1, 1, '', 'offline'));
    }
    await Future.wait(futures);
  });

  test(
    'avatar queue and SHA cache stay bounded under heavy scrolling',
    () async {
      final gates = List.generate(36, (_) => Completer<ProcessResult>());
      var started = 0;
      final service = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner: (executable, arguments, {workingDirectory, environment}) =>
            gates[started++].future,
      );

      final futures = List.generate(400, (index) => service.resolve('$index'));
      await Future<void>.delayed(Duration.zero);

      expect(started, 4);
      expect(service.debugActiveRequestCount, 4);
      expect(service.debugQueuedRequestCount, 32);
      expect(service.debugCachedRequestCount, lessThanOrEqualTo(256));
      expect(
        identical(service.resolve('saturated'), service.resolve('saturated')),
        isTrue,
      );

      for (var index = 0; index < gates.length; index++) {
        gates[index].complete(ProcessResult(1, 1, '', 'offline'));
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(started, 36);
      expect(service.debugActiveRequestCount, 0);
      expect(service.debugQueuedRequestCount, 0);

      var sequentialStarts = 0;
      final lru = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner: (executable, arguments, {workingDirectory, environment}) async {
          sequentialStarts++;
          return ProcessResult(1, 1, '', 'offline');
        },
      );
      for (var index = 0; index < 300; index++) {
        await lru.resolve('$index');
      }
      expect(sequentialStarts, 300);
      expect(lru.debugCachedRequestCount, 256);
      expect(identical(lru.resolve('299'), lru.resolve('299')), isTrue);
    },
  );

  testWidgets('YogitApp restores manual graph width only for its repository', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    GitRepository repository(String root) =>
        FakeGitRepository((_, _) async => [commit('1', root)], root: root);
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    await tester.pumpWidget(
      YogitApp(
        repository: repository('/repo/a'),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(44, 0),
    );
    await tester.pumpAndSettle();
    final savedA = graphWidth();
    expect(store.current.repositoryGraphWidths['/repo/a'], savedA);

    await tester.pumpWidget(
      YogitApp(
        key: const Key('restart-a'),
        repository: repository('/repo/a'),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), savedA);

    await tester.pumpWidget(
      YogitApp(
        key: const Key('open-b'),
        repository: repository('/repo/b'),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), 96);
  });

  testWidgets('YogitApp migrates legacy graph width to the first repository', (
    tester,
  ) async {
    final store = MemorySettingsStore()
      ..current = const AppSettings(
        columnWidths: TimelineColumnWidths(graph: 180),
      );

    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first')],
          root: '/repo/first',
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(store.current.columnWidths.graph, isNull);
    expect(store.current.repositoryGraphWidths, {'/repo/first': 180});
    expect(tester.getSize(find.byKey(const Key('graph-header'))).width, 180);
  });

  testWidgets('changing the timeline theme preserves selection and scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 500);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final store = MemorySettingsStore();
    final commits = [
      for (var index = 0; index < 30; index++)
        commit('$index', 'message $index'),
    ];
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository((_, _) async => commits),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final preview = find.byKey(const Key('preview-surface'));
    final previewSubject = find.descendant(
      of: preview,
      matching: find.text('message 12'),
    );
    expect(preview, findsOneWidget);
    expect(previewSubject, findsOneWidget);
    final before = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('timeline-list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-section-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-theme-card-carbon')));
    await tester.pumpAndSettle();
    expect(store.current.timelineTheme, TimelineThemeKind.carbon);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-row-12')), findsOneWidget);
    expect(preview, findsOneWidget);
    expect(previewSubject, findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const Key('timeline-list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels,
      before,
    );
    expect(
      tester.widget<Container>(find.byKey(const Key('toolbar'))).color,
      TimelineThemePalette.carbon.surface,
    );
  });

  testWidgets('settings toggle preserves timeline state and graph geometry', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 1, '', 'offline'),
    );
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('1', 'first commit'),
        commit('2', 'second commit'),
      ],
    );

    await tester.pumpWidget(
      YogitApp(
        repository: repository,
        settingsStore: store,
        avatarService: service,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final graphSize = tester.getSize(find.byKey(const Key('graph-painter-0')));

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Git integrations'), findsWidgets);
    await tester.tap(find.byKey(const Key('show-avatars-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    expect(
      tester
          .widgetList<CommitAvatarStack>(find.byType(CommitAvatarStack))
          .every((avatar) => !avatar.showRemoteAvatars),
      isTrue,
    );
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))), graphSize);
    expect(store.current.showAvatars, isFalse);
  });

  testWidgets('persisted avatar opt-out wins before remote lookup starts', (
    tester,
  ) async {
    final loaded = Completer<AppSettings>();
    final store = DelayedSettingsStore(loaded.future);
    var requests = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) async {
        requests++;
        return ProcessResult(1, 1, '', 'offline');
      },
    );

    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main'],
            current: 'main',
            tips: {'main': '1'},
            localTips: {'main': '1'},
          ),
        ),
        settingsStore: store,
        avatarService: service,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pump();
    expect(requests, 0);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('open-settings')))
          .onPressed,
      isNull,
    );

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(30, 0),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.right);
    expect(store.saveCount, 0);

    loaded.complete(
      const AppSettings(
        showAvatars: false,
        previewPlacement: PreviewPlacement.bottom,
        columnWidths: TimelineColumnWidths(graph: 220),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))).width, 220);
    expect(store.saveCount, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
  });

  testWidgets('preferred preview placement and column widths are applied', (
    tester,
  ) async {
    TimelineColumnWidths? savedWidths;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          preferredPreviewPlacement: PreviewPlacement.bottom,
          columnWidths: const TimelineColumnWidths(graph: 210),
          onColumnWidthsChanged: (value) => savedWidths = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))).width, 210);

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(30, 0),
    );
    await tester.pump();
    expect(savedWidths?.graph, greaterThan(210));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
  });
  // ------------------------------------------------------------------ §17.1
  test('date group labels read Today, Yesterday, then dates', () {
    final now = DateTime(2026, 7, 26, 10);
    String label(DateTime day) => dateGroupLabel(day, now);

    expect(label(DateTime(2026, 7, 26)), 'Today');
    expect(label(DateTime(2026, 7, 25)), 'Yesterday');
    expect(label(DateTime(2026, 7, 24)), '07.24 Fri');
    expect(label(DateTime(2026, 1, 1)), '01.01 Thu');
    expect(label(DateTime(2025, 12, 31)), '25.12.31 Wed');
    expect(label(DateTime(2024, 2, 29)), '24.02.29 Thu');
  });

  test('date separators head every day and the working tree leads them', () {
    final now = DateTime(2026, 7, 26, 12);
    int at(int day, int hour) =>
        DateTime(2026, 7, day, hour).millisecondsSinceEpoch ~/ 1000;
    final rows = layoutGraph([
      workingTreeCommit('a'),
      commit('a', 'today late', timestamp: at(26, 9)),
      commit('a2', 'today early', parents: const ['b'], timestamp: at(26, 1)),
      commit('b', 'yesterday', timestamp: at(25, 23)),
    ]);

    final entries = timelineEntries(rows, now);

    expect(entries.map((entry) => entry.label).toList(), [
      null,
      'Today',
      null,
      null,
      'Yesterday',
      null,
    ]);
    // The working tree row belongs to no day, so it leads the list.
    expect(entries.first.row.commit.isWorkingTree, isTrue);
    expect(entries.first.rowIndex, 0);
    expect(entries[2].rowIndex, 1);
    // A separator is a pass-through row carrying the lanes of the row above it.
    final separator = entries[4];
    expect(separator.rowIndex, -1);
    expect(separator.row.activeLanes, rows[2].nextLanes);
    expect(separator.row.nextLanes, rows[2].nextLanes);
    expect(separator.row.activeLaneShas, rows[2].nextLaneShas);
    expect(separator.row.activeLaneBranches, rows[2].nextLaneBranches);
    expect(separator.row.nextLaneBranches, rows[2].nextLaneBranches);
    expect(separator.row.transitions, isEmpty);
  });

  test('a date separator carries the rails and the sweep across itself', () {
    const size = Size(168, 36);
    final now = DateTime(2026, 7, 26, 12);
    int at(int day) =>
        DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
    // A merge on the older day: its second-parent sweep must finish over the
    // separator, and the merge must not stamp a node on the separator row.
    final rows = layoutGraph([
      commit('M', 'merge', parents: const ['P', 'F'], timestamp: at(26)),
      commit('P', 'parent', parents: const ['R'], timestamp: at(25)),
      commit('F', 'feature', parents: const ['R'], timestamp: at(25)),
      commit('R', 'root', timestamp: at(25)),
    ]);
    final entries = timelineEntries(rows, now);
    final separator = entries[2];
    expect(separator.label, 'Yesterday');

    final painter = CommitGraphPainter(
      row: separator.row,
      previous: rows[0],
      selected: true,
      committerColor: const Color(0xFF5CB270),
      passThrough: true,
    );

    // Lane 0 runs the full height and the arriving sweep completes here.
    expect(painter.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(p1: const Offset(28, 0), p2: const Offset(28, 18))
        ..line(p1: const Offset(28, 18), p2: const Offset(28, 36))
        ..path(),
    );
    // No node, no selected band, no ref connector on a pass-through row.
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      isNot(paints..circle()),
    );
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      isNot(paints..rect()),
    );
  });

  test('a parent-side join bends at its parent after a date heading', () {
    const size = Size(168, 36);
    final now = DateTime(2026, 7, 26, 12);
    int at(int day) =>
        DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
    final rows = layoutGraph([
      commit('M', 'merge', parents: const ['P', 'B'], timestamp: at(26)),
      commit('B', 'branch tail', parents: const ['P'], timestamp: at(26)),
      commit('P', 'parent', timestamp: at(25)),
    ]);
    final originalJoin = rows[1].transitions.single;
    expect(originalJoin, (from: 1, to: 0, sha: 'P'));

    final entries = timelineEntries(rows, now);
    final headingIndex = entries.indexWhere(
      (entry) => entry.label == 'Yesterday',
    );
    final above = entries[headingIndex - 1];
    final heading = entries[headingIndex];
    final parent = entries[headingIndex + 1];

    expect(above.row.commit.sha, 'B');
    expect(above.row.transitions, isEmpty);
    expect(above.row.nextLaneShas[1], 'P');
    expect(heading.row.transitions, [originalJoin]);
    expect(heading.row.activeLaneShas[1], 'P');
    expect(heading.row.nextLaneShas, rows[1].nextLaneShas);
    expect(parent.row.commit.sha, 'P');

    final headingPainter = CommitGraphPainter(
      row: heading.row,
      previous: above.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    final headingPath = headingPainter.transitionPath(
      originalJoin.from,
      originalJoin.to,
      size.height / 2,
      size,
    );
    expect(
      _samples(
        headingPath,
      ).where((point) => point.dy <= size.height).map((point) => point.dx),
      everyElement(58),
    );

    final parentPainter = CommitGraphPainter(
      row: parent.row,
      previous: heading.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    final arrivalPath = parentPainter.transitionPath(
      originalJoin.from,
      originalJoin.to,
      size.height / 2 - size.height,
      size,
    );
    expect(arrivalPath.getBounds(), const Rect.fromLTRB(28, -18, 58, 18));
    expect(_touches(arrivalPath, const Offset(28, 18)), isTrue);
    final metric = arrivalPath.computeMetrics().single;
    expect(
      metric.getTangentForOffset(metric.length)!.vector.dx,
      lessThan(-0.99),
    );
  });

  testWidgets('date rows head their group, boxed at the hash column', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int stampOn(DateTime day, {int minute = 0}) =>
        day.add(Duration(minutes: minute)).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('a', 'today commit', timestamp: stampOn(today)),
            commit(
              'b',
              'older commit',
              timestamp: stampOn(today.subtract(const Duration(days: 2))),
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(const Key('date-row-0')), findsOneWidget);
    expect(find.byKey(const Key('date-row-2')), findsOneWidget);
    // Rounded, transparent, blue-bordered box with blue 12px w600 text.
    final box =
        tester
                .widget<Container>(find.byKey(const Key('date-box-0')))
                .decoration!
            as BoxDecoration;
    expect(box.color, isNull);
    expect((box.border! as Border).top.color, const Color(0xFF5AB0FF));
    expect((box.border! as Border).top.width, 1);
    expect(box.borderRadius, BorderRadius.circular(7));
    final label = tester.widget<Text>(find.text('Today'));
    expect(label.style?.color, const Color(0xFF5AB0FF));
    expect(label.style?.fontSize, 12);
    expect(label.style?.fontWeight, FontWeight.w600);
    // The box sits 5px left of the hash text it heads.
    expect(
      tester.getRect(find.byKey(const Key('date-box-0'))).left,
      tester.getRect(find.text('a')).left - 5,
    );
    // The date row is a row of the list, as tall as the rest.
    final rowRect = tester.getRect(find.byKey(const Key('date-row-0')));
    final boxRect = tester.getRect(find.byKey(const Key('date-box-0')));
    expect(rowRect.height, TimelineScreen.rowHeight);
    // The box hangs below centre and still fits the row uncut.
    final centred = (TimelineScreen.rowHeight - boxRect.height) / 2;
    expect(boxRect.top - rowRect.top, greaterThan(centred));
    expect(boxRect.top, greaterThanOrEqualTo(rowRect.top));
    expect(boxRect.bottom, lessThanOrEqualTo(rowRect.bottom));
    expect(boxRect.height, greaterThanOrEqualTo(20));

    // Underlines are gone from commit rows too.
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('selected-row-a')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).border)
          .whereType<Border>()
          .map((border) => border.bottom.color),
      everyElement(isNot(const Color(0xFF343946))),
    );
  });

  testWidgets('only the first date heading takes the selection', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int stampOn(DateTime day, {int minute = 0}) =>
        day.add(Duration(minutes: minute)).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('a', 'today commit', timestamp: stampOn(today)),
            commit(
              'b',
              'older commit',
              timestamp: stampOn(today.subtract(const Duration(days: 2))),
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Entries: heading 0, commit a, heading 2, commit b. Only heading 0 selects.
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsNothing);
    final band = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byKey(const Key('date-row-0')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(band.color, TimelineThemePalette.systemGraphite.selectedRow);

    // It has no commit, so the preview falls back to its empty state.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('No commit selected'), findsOneWidget);
    expect(find.byKey(const Key('refs-modal')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Down from it lands on the commit, not on the next heading.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);

    // The later heading is skipped in both directions.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-b')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);

    // And clicking it changes nothing.
    await tester.tap(find.byKey(const Key('date-row-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);

    // Clicking the first heading still selects it.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsNothing);
    expect(find.byKey(const Key('selected-row-b')), findsNothing);
  });

  // ------------------------------------------------------------------ §17.2
  test('ref palette mapping is stable and covers all five records', () {
    expect(
      [
        for (final name in ['d', 'e', 'a', 'b', 'c'])
          stableRefPaletteIndex(name, 5),
      ],
      [0, 1, 2, 3, 4],
    );
    expect(refPaletteColorsForName('d', AppSettings.defaultRefPalette), (
      base: const Color(0xFF1D76DB),
      text: const Color(0xFF68A7EA),
    ));
  });

  test('timeline refs prefer HEAD, local, remote, tag, then decoration', () {
    final value = timelineRefsForCommit(
      commit('tip', 'tip', refs: const [GitRef(name: 'log-only')]),
      const RepoRefs(
        local: ['local'],
        remote: ['origin/remote'],
        tags: ['v1'],
        current: 'head',
        tips: {
          'head': 'tip',
          'local': 'tip',
          'origin/remote': 'tip',
          'v1': 'tip',
        },
      ),
    );
    expect(
      [for (final ref in value) ref.name],
      ['head', 'local', 'origin/remote', 'v1', 'log-only'],
    );
    expect(value.first.isHead, isTrue);
    expect(value[3].isTag, isTrue);
  });

  test('named branch lines use the representative ref text color', () {
    final rows = layoutGraph([
      commit('tip', 'tip', refs: const [GitRef(name: 'd', isHead: true)]),
    ]);
    final names = branchRefNames(
      rows,
      const RepoRefs(local: ['d'], current: 'd', tips: {'d': 'tip'}),
    );
    expect(
      assignBranchColors(
        rows,
        42,
        branchNames: names,
        refPalette: AppSettings.defaultRefPalette,
      )[rows.single.branch],
      const Color(0xFF68A7EA),
    );
  });

  test('branch lines choose the best ref across every row', () {
    final rows = [
      graphRow(
        commit: commit('old', 'old', refs: const [GitRef(name: 'log-only')]),
        lane: 0,
        branch: 0,
      ),
      graphRow(
        commit: commit(
          'newer-local',
          'newer local',
          refs: const [GitRef(name: 'z-local')],
        ),
        lane: 0,
        branch: 0,
      ),
      graphRow(
        commit: commit(
          'later-local',
          'later local',
          refs: const [GitRef(name: 'a-local')],
        ),
        lane: 0,
        branch: 0,
      ),
    ];

    expect(
      branchRefNames(rows, const RepoRefs(local: ['a-local', 'z-local'])),
      const {0: 'a-local'},
    );
  });

  test('branch colors take fixed roles, then a non-colliding pool', () {
    GraphRow born(int id, Map<int, int> active) => graphRow(
      commit: commit('$id', 'line $id'),
      lane: 0,
      activeLanes: active.keys.toList(),
      nextLanes: active.keys.toList(),
      branch: id,
      activeLaneBranches: active,
      nextLaneBranches: active,
    );
    // main, then a second line, then three lines each born while the earlier
    // ones are still running, then one more with the pool exhausted.
    final rows = [
      born(0, const {0: 0}),
      born(1, const {0: 0, 1: 1}),
      born(2, const {0: 0, 1: 1, 2: 2}),
      born(3, const {0: 0, 2: 2, 3: 3}),
      born(4, const {0: 0, 2: 2, 3: 3, 4: 4}),
      born(5, const {2: 2, 3: 3, 4: 4, 5: 5}),
    ];

    final colors = assignBranchColors(rows, 7);

    expect(colors[0], const Color(0xFF5CB270));
    expect(colors[1], anyOf(const Color(0xFF00E5FF), const Color(0xFFFF3131)));
    // Pool order, skipping colors already on screen at birth.
    expect(colors[2], const Color(0xFF3B82F6));
    expect(colors[3], const Color(0xFFFFF01F));
    expect(colors[4], const Color(0xFFB026FF));
    // Pool exhausted: a seeded pick from the rest of the palette.
    expect(colors[5], isNot(const Color(0xFF3B82F6)));
    expect(colors[5], isNot(const Color(0xFFFFF01F)));
    expect(colors[5], isNot(const Color(0xFFB026FF)));
    expect(colors[5], isNot(const Color(0xFF5CB270)));
    expect(colors[5], isNotNull);

    // Deterministic per seed, and stable as rows are appended.
    expect(assignBranchColors(rows, 7), colors);
    expect(assignBranchColors(rows, 8)[0], colors[0]);
    for (var length = 1; length <= rows.length; length++) {
      final prefix = assignBranchColors(rows.sublist(0, length), 7);
      for (final entry in prefix.entries) {
        expect(entry.value, colors[entry.key], reason: 'id ${entry.key}');
      }
    }
    // Both second-line colors are reachable across seeds.
    expect(
      {for (var seed = 0; seed < 8; seed++) assignBranchColors(rows, seed)[1]},
      {const Color(0xFF00E5FF), const Color(0xFFFF3131)},
    );
  });

  test('the selected base branch owns the configurable branch-zero color', () {
    addTearDown(() {
      AvatarService.baseBranchColor = AvatarService.defaultBaseBranchColor;
      AvatarService.branchAssignments = const {};
    });
    AvatarService.baseBranchColor = const Color(0xFF123456);
    final rows = layoutGraph([
      commit('other-tip', 'other', parents: const ['root']),
      commit('base-tip', 'base', parents: const ['root']),
      commit('root', 'root'),
    ], preferredTip: 'base-tip');

    final assignments = assignBranchColors(rows, 7);
    expect(rows.singleWhere((row) => row.commit.sha == 'base-tip').branch, 0);
    expect(assignments[0], const Color(0xFF123456));

    final comparison = branchComparison();
    final comparisonRows = layoutBranchComparison(comparison.commits);
    final baseSha = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.baseOnly)
        .commit
        .sha;
    expect(
      comparisonRows.singleWhere((row) => row.commit.sha == baseSha).branch,
      0,
    );
  });

  test('configured assignments win over branch color fallbacks', () {
    addTearDown(() {
      AvatarService.baseBranchColor = AvatarService.defaultBaseBranchColor;
      AvatarService.branchAssignments = const {};
      AvatarService.palette = AvatarService.defaultColors;
    });

    AvatarService.branchAssignments = const {
      0: Color(0xFF010203),
      1: Color(0xFF040506),
    };
    AvatarService.baseBranchColor = const Color(0xFFAABBCC);

    expect(AvatarService.branchColor(0), const Color(0xFF010203));
    expect(AvatarService.branchColor(1), const Color(0xFF040506));
  });

  test('painted branch-zero rails and curves use the assigned ref color', () {
    addTearDown(() {
      AvatarService.baseBranchColor = AvatarService.defaultBaseBranchColor;
      AvatarService.branchAssignments = const {};
    });
    const assigned = Color(0xFF68A7EA);
    AvatarService.baseBranchColor = const Color(0xFFAABBCC);
    AvatarService.branchAssignments = const {0: assigned};

    final railPainter = CommitGraphPainter(
      row: graphRow(
        commit: commit('side', 'side'),
        lane: 1,
        activeLanes: const [0, 1],
        nextLanes: const [0, 1],
        activeLaneShas: const {0: 'base', 1: 'side'},
        nextLaneShas: const {0: 'base', 1: 'side'},
        branch: 1,
        activeLaneBranches: const {0: 0, 1: 1},
        nextLaneBranches: const {0: 0, 1: 1},
      ),
      selected: false,
      committerColor: const Color(0xFF040506),
    );
    final curvePainter = CommitGraphPainter(
      row: graphRow(
        commit: commit('base', 'base', parents: const ['root']),
        lane: 1,
        activeLanes: const [1],
        nextLanes: const [0],
        activeLaneShas: const {1: 'base'},
        nextLaneShas: const {0: 'root'},
        transitions: const [(from: 1, to: 0, sha: 'root')],
        parentLanes: const [0],
        branch: 0,
        activeLaneBranches: const {1: 0},
        nextLaneBranches: const {0: 0},
      ),
      selected: false,
      committerColor: assigned,
    );

    expect(
      (Canvas canvas) => railPainter.paint(canvas, const Size(168, 36)),
      paints..line(color: assigned),
    );
    expect(
      (Canvas canvas) => curvePainter.paint(canvas, const Size(168, 36)),
      paints..path(color: assigned),
    );
  });

  test(
    'a side-branch painter repaints its passing base rail after an edit',
    () {
      addTearDown(
        () => AvatarService.baseBranchColor =
            AvatarService.defaultBaseBranchColor,
      );
      final row = graphRow(
        commit: commit('feature', 'feature'),
        lane: 1,
        activeLanes: const [0, 1],
        nextLanes: const [0, 1],
        branch: 1,
        activeLaneBranches: const {0: 0, 1: 1},
        nextLaneBranches: const {0: 0, 1: 1},
      );

      AvatarService.baseBranchColor = const Color(0xFF112233);
      final before = CommitGraphPainter(
        row: row,
        selected: false,
        committerColor: const Color(0xFF445566),
      );
      AvatarService.baseBranchColor = const Color(0xFF778899);
      final after = CommitGraphPainter(
        row: row,
        selected: false,
        committerColor: const Color(0xFF445566),
      );

      expect(after.shouldRepaint(before), isTrue);
      expect(
        (Canvas canvas) => before.paint(canvas, const Size(168, 36)),
        paints..line(color: const Color(0xFF112233)),
      );
      expect(
        (Canvas canvas) => after.paint(canvas, const Size(168, 36)),
        paints..line(color: const Color(0xFF778899)),
      );
    },
  );

  testWidgets('the timeline colors the graph with its assigned lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('merge', 'merge commit', parents: const ['main', 'feature']),
            commit('main', 'main commit', parents: const ['base']),
            commit('feature', 'feature commit', parents: const ['base']),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.row.branch, 0);
    expect(painter.committerColor, const Color(0xFF5CB270));
    expect(AvatarService.branchAssignments[0], const Color(0xFF5CB270));
    expect(
      AvatarService.branchAssignments[1],
      anyOf(const Color(0xFF00E5FF), const Color(0xFFFF3131)),
    );
  });

  // ------------------------------------------------------------------ §17.3
  testWidgets('ref chips split the cell width and drop what will not fit', (
    tester,
  ) async {
    const many = [
      GitRef(name: 'main', isHead: true),
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'feature/one'),
      GitRef(name: 'feature/two'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('three', 'three refs', refs: many.take(3).toList()),
              commit('five', 'five refs', refs: many),
            ],
            refs: const RepoRefs(
              local: ['main'],
              remote: ['origin/main'],
              tags: ['v1.0'],
              current: 'main',
            ),
          ),
          controller: controller,
          // 150px of chips: floor(150 / 40) = 3 chips at 50px each.
          columnWidths: const TimelineColumnWidths(refs: 150),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect chip(String sha, String name) =>
        tester.getRect(find.byKey(Key('ref-chip-$sha-$name')));
    for (final ref in many.take(3)) {
      expect(chip('three', ref.name).width, greaterThanOrEqualTo(40));
    }
    // Equal shares, in order, inside the cell.
    expect(
      chip('three', 'main').left,
      lessThan(chip('three', 'origin/main').left),
    );
    expect(
      chip('three', 'origin/main').left,
      lessThan(chip('three', 'v1.0').left),
    );
    expect(
      chip('three', 'main').width,
      closeTo(chip('three', 'origin/main').width, 0.5),
    );

    // Five refs in the same cell: three chips, the rest silently dropped, and
    // no badge anywhere.
    for (final ref in many.take(3)) {
      expect(find.byKey(Key('ref-chip-five-${ref.name}')), findsOneWidget);
    }
    for (final ref in many.skip(3)) {
      expect(find.byKey(Key('ref-chip-five-${ref.name}')), findsNothing);
    }
    expect(find.byKey(const Key('ref-more-five')), findsNothing);
    expect(find.textContaining('+'), findsNothing);

    // The modal still lists every ref, each behind a square 2px accent bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final modal = find.byKey(const Key('refs-modal'));
    for (final ref in many) {
      expect(
        find.descendant(of: modal, matching: find.text(ref.name)),
        findsOneWidget,
      );
    }
    final accent = find.byKey(const Key('modal-accent-main'));
    expect(tester.getSize(accent).width, 2);
    expect(tester.getSize(accent).height, 20);
    expect(tester.widget<Container>(accent).decoration, isNull);
  });

  // ------------------------------------------------------------------ §17.4
  testWidgets('the graph column ratchets to the lanes it has shown', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    // A straight run on lane 0, then an octopus far below the fold opening
    // lanes 1..3.
    final repository = FakeGitRepository(
      (_, _) async => [
        for (var index = 0; index < 20; index++)
          commit('$index', 'commit $index', parents: ['${index + 1}']),
        commit('20', 'octopus', parents: const ['a', 'b', 'c', 'd']),
        commit('a', 'a'),
        commit('b', 'b'),
        commit('c', 'c'),
        commit('d', 'd'),
      ],
    );
    Widget screen(GitRepository repository, Key key) => MaterialApp(
      home: TimelineScreen(
        key: key,
        repository: repository,
        controller: controller,
      ),
    );
    await tester.pumpWidget(screen(repository, const Key('first')));
    await tester.pumpAndSettle();
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    // Only lane 0 is on screen, so the column stays at its floor.
    expect(graphWidth(), 96);

    // Scrolling the octopus into view widens it once: 28 + 3 * 30 + 14.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(graphWidth(), 132);

    // Scrolling back never shrinks it inside a session.
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(graphWidth(), 132);

    // A different repository starts over.
    await tester.pumpWidget(
      screen(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        const Key('second'),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), 96);
  });

  testWidgets('async base branch relayout ratchets to newly visible lanes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final refs = Completer<RepoRefs>();
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'merge',
                'four-parent merge',
                parents: const ['a', 'b', 'c', 'd'],
              ),
              commit('a', 'a'),
              commit('b', 'b'),
              commit('c', 'c'),
              commit('d', 'd'),
            ],
            refsLoader: () => refs.future,
          ),
          preferredBranch: 'main',
        ),
      ),
    );
    await tester.pumpAndSettle();
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    // The unpreferred merge exposes lanes 0..3.
    expect(graphWidth(), 132);

    // This unloaded tip reserves lane 0, shifting the visible merge to lanes
    // 1..4 after the asynchronous refs result arrives.
    refs.complete(
      const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': 'unloaded-preferred'},
      ),
    );
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter
            as CommitGraphPainter;
    expect(painter.row.nextLanes, contains(4));
    expect(graphWidth(), 162);
  });

  // ------------------------------------------------------------------ §18.1
  test('a date heading carries a non-main lane through, not just lane 0', () {
    const size = Size(168, 36);
    final now = DateTime(2026, 7, 26, 12);
    int at(int day) =>
        DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
    // A lane-1 chain straddling a day change, with lane 0 running beside it.
    final rows = layoutGraph([
      commit('M', 'merge', parents: const ['P', 'F1'], timestamp: at(26)),
      commit('F1', 'feature today', parents: const ['F2'], timestamp: at(26)),
      commit(
        'F2',
        'feature yesterday',
        parents: const ['P'],
        timestamp: at(25),
      ),
      commit('P', 'parent', timestamp: at(25)),
    ]);
    final entries = timelineEntries(rows, now);
    final heading = entries.firstWhere((entry) => entry.label == 'Yesterday');
    final above = entries[entries.indexOf(heading) - 1];
    expect(above.row.commit.sha, 'F1');
    expect(above.row.lane, 1);

    final painter = CommitGraphPainter(
      row: heading.row,
      previous: above.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
      passThrough: true,
    );

    // Both lanes hand their rail straight through the heading row.
    expect(painter.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    expect(painter.laneVerticals(size)[1], (top: 0.0, bottom: 36.0));
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(p1: const Offset(28, 0), p2: const Offset(28, 18))
        ..line(p1: const Offset(28, 18), p2: const Offset(28, 36))
        ..line(p1: const Offset(58, 0), p2: const Offset(58, 18))
        ..line(p1: const Offset(58, 18), p2: const Offset(58, 36)),
    );

    // The commit below the heading resumes lane 1 from the top of its row.
    final below = entries[entries.indexOf(heading) + 1];
    expect(below.row.commit.sha, 'F2');
    final resumed = CommitGraphPainter(
      row: below.row,
      previous: heading.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    expect(resumed.continuesFromAbove(1), isTrue);
    expect(resumed.laneVerticals(size)[1]?.top, 0.0);
  });

  testWidgets('the date heading row paints its rails at full row size', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int stampOn(DateTime day, {int minute = 0}) =>
        day.add(Duration(minutes: minute)).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'M',
                'merge',
                parents: const ['P', 'F'],
                timestamp: stampOn(today, minute: 2),
              ),
              commit(
                'F',
                'feature today',
                parents: const ['P'],
                timestamp: stampOn(today, minute: 1),
              ),
              commit(
                'P',
                'parent',
                timestamp: stampOn(today.subtract(const Duration(days: 2))),
              ),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(graph: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The heading's graph cell is a full row, so its rails actually paint.
    final painter = find.byKey(const Key('date-painter-3'));
    expect(painter, findsOneWidget);
    expect(tester.getSize(painter), const Size(120, TimelineScreen.rowHeight));
    expect(
      tester.getRect(painter).left,
      tester.getRect(find.byKey(const Key('graph-cell-0'))).left,
    );
  });

  // ------------------------------------------------------------------ §18.2
  testWidgets('nodes sit above every rail and inside their own lane', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('o', 'octopus', parents: const ['a', 'b', 'c', 'd', 'e']),
              commit('a', 'a', parents: const ['z']),
              commit('b', 'b', parents: const ['z']),
              commit('c', 'c', parents: const ['z']),
              commit('d', 'd', parents: const ['z']),
              commit('e', 'e', parents: const ['z']),
              commit('z', 'root'),
            ],
          ),
          controller: controller,
          // Five lanes squeezed into a cell far below their content width.
          columnWidths: const TimelineColumnWidths(graph: 110),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;
    expect(painterAt(0).laneSpacing, lessThan(30));

    for (var index = 1; index <= 5; index++) {
      final painter = painterAt(index);
      final cell = tester.getRect(find.byKey(Key('graph-cell-$index')));
      final stack = find.descendant(
        of: find.byKey(Key('graph-cell-$index')),
        matching: find.byType(CommitAvatarStack),
      );
      final avatar = tester.widget<CommitAvatarStack>(stack);
      final rect = tester.getRect(stack);

      // The node sits on its lane's effective x, centred on it.
      expect(
        rect.left - cell.left,
        closeTo(painter.laneX(painter.row.lane) - avatar.size / 2, 0.01),
      );
      // And it stops short of the next lane's rail.
      expect(
        rect.right - cell.left,
        lessThanOrEqualTo(
          painter.laneX(painter.row.lane) +
              painter.laneSpacing -
              CommitGraphPainter.railWidth,
        ),
      );

      // Rails paint below the node: the painter comes first in the row's stack.
      final children = tester
          .widget<Stack>(
            find
                .descendant(
                  of: find.byKey(Key('graph-cell-$index')),
                  matching: find.byType(Stack),
                )
                .first,
          )
          .children;
      expect(children.length, 2);
      expect(
        find
            .descendant(
              of: find.byWidget(children.first),
              matching: find.byType(CustomPaint),
            )
            .evaluate(),
        isNotEmpty,
      );
      expect(
        find
            .descendant(
              of: find.byWidget(children.last),
              matching: find.byType(CommitAvatarStack),
            )
            .evaluate(),
        isNotEmpty,
      );
    }
  });
  // ------------------------------------------------------------------ §18.3
  testWidgets('the toolbar reads half again bigger', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/Users/ada/project',
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // The selector shows the last segment and keeps the full path in a tooltip.
    expect(find.text('저장소'), findsOneWidget);
    expect(find.text('기준 브랜치'), findsOneWidget);
    expect(find.text('project'), findsOneWidget);
    expect(find.text('/Users/ada/project'), findsNothing);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.text('project'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      '/Users/ada/project',
    );
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
    // A root with no last segment keeps the whole string.
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/',
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('/'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
    expect(find.byKey(const Key('base-branch-selector')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('toolbar'))).height, 56);
  });

  testWidgets('the toolbar right cluster reads bigger and still fits 960', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    // The native window stops here, so this is the tightest the cluster gets.
    tester.view.physicalSize = const Size(960, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/Users/ada/some/deep/project/path/that/keeps/going',
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    double sizeOf(String label) =>
        tester.widget<Text>(find.text(label)).style!.fontSize!;
    expect(sizeOf('미리보기'), 14);
    // The caption sits outside the bordered box, to its left.
    final box = tester.getRect(find.byKey(const Key('preview-placement')));
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-placement')),
        matching: find.text('미리보기'),
      ),
      findsNothing,
    );
    expect(
      tester.getRect(find.text('미리보기')).right,
      lessThanOrEqualTo(box.left),
    );
    expect(sizeOf('하단'), 14);
    expect(sizeOf('Enter'), 13);
    expect(find.text('↑'), findsNothing);
    expect(find.text('↓'), findsNothing);
    expect(find.text(' 이동 · '), findsNothing);
    // The keycap group carries no box of its own — only the chips do.
    expect(
      tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text('상세'),
              matching: find.byType(Container),
            ),
          )
          .whereType<Container>()
          .any((box) => (box.decoration as BoxDecoration?)?.border != null),
      isFalse,
    );
    expect(
      tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text('Enter'),
              matching: find.byType(Container),
            ),
          )
          .any((box) => (box.decoration as BoxDecoration?)?.border != null),
      isTrue,
    );
    // Label first, then the chip.
    expect(
      tester.getRect(find.text('상세')).left,
      lessThan(tester.getRect(find.byKey(const Key('keycap-Enter'))).left),
    );
    // Right cluster order: keycaps, caption, placement box, Full Diff, gear.
    final lefts = [
      tester.getRect(find.byKey(const Key('shortcut-hint'))).left,
      tester.getRect(find.text('미리보기')).left,
      box.left,
      tester.getRect(find.byKey(const Key('toolbar-full-diff'))).left,
      tester.getRect(find.byIcon(Icons.settings_outlined)).left,
    ];
    expect(lefts, orderedEquals(([...lefts]..sort())));
    expect(tester.widget<Icon>(find.byIcon(Icons.settings_outlined)).size, 22);
    // Rendering at all is the fit assertion: an overflow would have thrown.
    expect(tester.getSize(find.byKey(const Key('toolbar'))).width, 960);
    expect(
      tester.getRect(find.byIcon(Icons.settings_outlined)).right,
      lessThanOrEqualTo(960),
    );
    // The Enter chip is the same toggle the key runs, by mouse.
    await tester.tap(find.byKey(const Key('keycap-Enter')));
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keycap-Enter')));
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);

    // The placement buttons grew but still respond.
    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
  });

  // ------------------------------------------------------------------ §18.4
  testWidgets('the sidebar resizes, persists, and clamps', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(local: ['main'], current: 'main'),
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    double sidebarWidth() =>
        tester.getSize(find.byKey(const Key('sidebar'))).width;
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    expect(const TimelineColumnWidths().sidebar, 150);
    expect(sidebarWidth(), 150);
    final title = titleWidth();

    // Dragging the right edge widens it, and the timeline gives up exactly that
    // much so no dead strip opens.
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 220);
    expect(saved?.sidebar, 220);
    expect(titleWidth(), title - 70);
    expect(nameRight(), 1400);

    // It clamps at both ends of the design range.
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 320);
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 150);
    expect(saved?.sidebar, 150);

    // Round-trips like every other width, clamped on the way in.
    expect(
      TimelineColumnWidths.fromJson(
        const TimelineColumnWidths(sidebar: 240).toJson(),
      ).sidebar,
      240,
    );
    expect(
      TimelineColumnWidths.fromJson(<String, dynamic>{'sidebar': 40}).sidebar,
      150,
    );
    expect(
      TimelineColumnWidths.fromJson(<String, dynamic>{'sidebar': 900}).sidebar,
      320,
    );
  });

  testWidgets('the sidebar collapses to group icons and restores its width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(
              local: ['main'],
              remote: ['origin/main'],
              tags: ['v1.0'],
              current: 'main',
            ),
          ),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 150);
    expect(find.byKey(const Key('sidebar-collapse-button')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('sidebar-collapse-icon'))),
      const Size(14.4, 14.4),
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const Key('sidebar-collapse-button')),
              matching: find.byType(Tooltip),
            ),
          )
          .waitDuration,
      Duration.zero,
    );

    await tester.tap(find.byKey(const Key('sidebar-collapse-button')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 52);
    expect(find.byKey(const Key('ref-filter')), findsNothing);
    for (final section in ['local', 'remote', 'tags']) {
      expect(
        find.byKey(Key('sidebar-compact-section-$section')),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-compact-section-local')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('sidebar-expand-icon'))),
      const Size(14.4, 14.4),
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const Key('sidebar-expand-button')),
              matching: find.byType(Tooltip),
            ),
          )
          .waitDuration,
      Duration.zero,
    );

    await tester.tap(find.byKey(const Key('sidebar-expand-button')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 150);
    expect(find.byKey(const Key('ref-filter')), findsOneWidget);
  });

  testWidgets('holding the command modifier labels the sidebar toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(local: ['main'], current: 'main'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final hint = find.byKey(const Key('sidebar-toggle-shortcut'));
    expect(hint, findsNothing);

    final modifier = usesMetaModifier
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.pumpAndSettle();

    expect(hint, findsOneWidget);
    expect(
      find.descendant(of: hint, matching: find.text(shortcutLabel('1'))),
      findsOneWidget,
    );
    // The badge hangs under the button instead of displacing it.
    expect(
      tester.getRect(hint).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('sidebar-collapse-icon'))).bottom,
      ),
    );

    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
  });

  testWidgets('sidebar hover extends left without moving branch content', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            tags: ['v1.0'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);

    for (final name in ['feature', 'v1.0']) {
      final row = find.byKey(Key('sidebar-row-$name'));
      final hover = find.byKey(Key('sidebar-ref-hover-$name'));
      final content = find.byKey(Key('sidebar-ref-$name'));
      final icon = find.descendant(
        of: row,
        matching: find.byIcon(
          name == 'v1.0' ? Icons.sell_outlined : Icons.call_split,
        ),
      );
      final iconBefore = tester.getRect(icon);
      final contentBefore = tester.getRect(content);
      final hoverBefore = tester.getRect(hover);

      await pointer.moveTo(tester.getCenter(content));
      await tester.pump();

      expect(tester.getRect(icon), iconBefore, reason: name);
      expect(tester.getRect(content), contentBefore, reason: name);
      expect(tester.getRect(hover), hoverBefore, reason: name);

      final background = find.byKey(Key('sidebar-ref-hover-background-$name'));
      expect(background, findsOneWidget, reason: name);
      final backgroundRect = tester.getRect(background);
      expect(backgroundRect.left, hoverBefore.left - 5, reason: name);
      expect(backgroundRect.right, hoverBefore.right, reason: name);

      final decoration =
          tester.widget<DecoratedBox>(background).decoration as BoxDecoration;
      final border = decoration.border! as Border;
      expect(decoration.borderRadius, isNull, reason: name);
      // A plain hover paints like the timeline's hover chip; the colored
      // left border is reserved for the keyboard cursor's selection.
      expect(
        decoration.color,
        TimelineThemePalette.systemGraphite.neutralChip.withValues(alpha: 0.48),
        reason: name,
      );
      expect(border.left.width, 0, reason: name);
      expect(border.top.width, 0, reason: name);
      expect(border.right.width, 0, reason: name);
      expect(border.bottom.width, 0, reason: name);

      await pointer.moveTo(Offset.zero);
      await tester.pump();
    }
  });

  testWidgets('toolbar controls expose their approved hover feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
        onOpenSettings: () {},
      ),
    );
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);

    await pointer.moveTo(
      tester.getCenter(
        find.byKey(const Key('placement-PreviewPlacement.left')),
      ),
    );
    await tester.pump();
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(
                      const Key('placement-hover-PreviewPlacement.left'),
                    ),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      TimelineThemePalette.systemGraphite.selectedRow,
    );

    final diffButton = find.byKey(const Key('toolbar-full-diff'));
    await pointer.moveTo(tester.getCenter(diffButton));
    await tester.pump();
    expect(
      (tester
                  .widget<Container>(
                    find.descendant(
                      of: diffButton,
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      const Color(0xFF3FB950),
    );

    await pointer.moveTo(
      tester.getCenter(find.byKey(const Key('open-settings'))),
    );
    await tester.pump();
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(const Key('settings-hover-surface')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      TimelineThemePalette.systemGraphite.selectedRow,
    );
    expect(
      tester
          .widget<AnimatedRotation>(
            find.byKey(const Key('settings-hover-turn')),
          )
          .turns,
      closeTo(0.05, 0.0001),
    );
  });

  testWidgets('the sidebar reads a size up', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main'],
            tags: ['v1.0'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('sidebar-ref-main')),
              matching: find.text('main'),
            ),
          )
          .style
          ?.fontSize,
      13,
    );
    expect(tester.widget<Text>(find.text('LOCAL')).style?.fontSize, 11);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ref-filter')))
          .style
          ?.fontSize,
      13,
    );
  });
  // ------------------------------------------------------------------ §18.2b
  testWidgets('a newborn branch line leaves the source node center', (
    tester,
  ) async {
    final now = DateTime.now();
    int stamp(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            // A merge whose second parent opens a new column, with the day
            // change landing right under it.
            (_, _) async => [
              commit(
                'M',
                'merge',
                parents: const ['P', 'F'],
                timestamp: stamp(const Duration(hours: 1)),
              ),
              commit(
                'P',
                'parent',
                parents: const ['R'],
                timestamp: stamp(const Duration(days: 2)),
              ),
              commit(
                'F',
                'feature',
                parents: const ['R'],
                timestamp: stamp(const Duration(days: 2)),
              ),
              commit('R', 'root', timestamp: stamp(const Duration(days: 3))),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(graph: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(Key key) =>
        tester.widget<CustomPaint>(find.byKey(key)).painter!
            as CommitGraphPainter;
    const size = Size(120, 36);
    final merge = painterAt(const Key('graph-painter-0'));
    final edge = merge.row.transitions.single;
    expect(edge.from, merge.row.lane);
    expect(edge.to, 1);

    // A birth: the same discriminator the color rule uses puts its bend beside
    // the departure node.
    expect(CommitGraphPainter.isMergeEdge(merge.row, edge), isTrue);
    Path departure() => merge.transitionPath(
      edge.from,
      edge.to,
      18,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(merge.row, edge),
    );

    // The birth leaves the node sideways on one arc into its own column, instead
    // of running down the parent's rail into the next row.
    expect(_touches(departure(), const Offset(28, 18)), isTrue);
    expect(departure().getBounds(), Rect.fromLTRB(28, 18, merge.laneX(1), 54));
    final sweep = _samples(departure());
    // Everything past the sweep sits in the new column, still inside this row.
    expect(
      sweep.where((point) => point.dy > 50).map((point) => point.dx),
      everyElement(closeTo(merge.laneX(1), 0.01)),
    );
    expect(
      sweep
          .where((point) => point.dx > 29)
          .map((point) => point.dy)
          .reduce((a, b) => a < b ? a : b),
      lessThan(36),
    );

    // The date heading right below completes the sweep into the new column.
    final heading = painterAt(const Key('date-painter-2'));
    expect(heading.passThrough, isTrue);
    final arrival = heading.transitionPath(
      edge.from,
      edge.to,
      18 - 36,
      size,
      // Classified against the row that started it, so the halves match.
      bendEarly: CommitGraphPainter.isMergeEdge(merge.row, edge),
    );
    expect(_touches(arrival, Offset(heading.laneX(1), 18)), isTrue);
    // The sweep finishes inside the heading row and runs straight from there.
    expect(
      _samples(
        arrival,
      ).where((point) => point.dy >= 12).map((point) => point.dx),
      everyElement(closeTo(heading.laneX(1), 0.01)),
    );
  });
  // ------------------------------------------------------------------ §18.4b
  testWidgets('the ref modal shows long names in full', (tester) async {
    const long = 'feature/very-long-branch-name-for-testing-full-width';
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('first', 'first commit'),
              commit(
                'many',
                'many refs',
                refs: const [
                  GitRef(name: 'main', isHead: true),
                  GitRef(name: long),
                ],
              ),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(refs: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final modal = find.byKey(const Key('refs-modal'));
    expect(modal, findsOneWidget);
    // The full name renders, and nothing inside the modal ellipsizes.
    final name = find.descendant(of: modal, matching: find.text(long));
    expect(name, findsOneWidget);
    expect(tester.widget<Text>(name).overflow, TextOverflow.visible);
    expect(tester.getSize(name).width, greaterThan(120));
    // The box grew past the refs column to fit it, and stays in the viewport.
    final width = tester.getSize(modal).width;
    expect(width, greaterThan(120));
    expect(
      width,
      lessThanOrEqualTo(
        tester.getSize(find.byKey(const Key('timeline-viewport'))).width,
      ),
    );
  });
  test('the exact commit time pads every field and drops this year', () {
    int stamp(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
    final now = DateTime(2026, 8, 4, 3, 0, 0);

    // This year needs no year: the month and day are enough.
    expect(
      exactCommitTime(stamp(DateTime(2026, 7, 26, 14, 5, 9)), now: now),
      '07-26 14:05:09',
    );
    // Single digits everywhere, and midnight stays 00 rather than 24 or 12.
    expect(
      exactCommitTime(stamp(DateTime(2026, 1, 2, 0, 0, 0)), now: now),
      '01-02 00:00:00',
    );
    // Any other year keeps it, so the two never read as the same day.
    expect(
      exactCommitTime(stamp(DateTime(2025, 12, 31, 23, 59, 59)), now: now),
      '2025-12-31 23:59:59',
    );
    expect(
      exactCommitTime(stamp(DateTime(2027, 3, 4, 9, 8, 7)), now: now),
      '2027-03-04 09:08:07',
    );
  });

  testWidgets('the status bar never truncates the profile address', (
    tester,
  ) async {
    // Narrow enough that the chip and the stamp compete for the row.
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const email = 'a-rather-long-address@example.navercorp.com';
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          runner:
              (executable, arguments, {workingDirectory, environment}) async =>
                  ProcessResult(
                    1,
                    0,
                    arguments.contains('--symbolic-full-name')
                        ? 'aaa\nrefs/heads/main\n'
                        : arguments.first == 'config'
                        ? (arguments.last == 'user.email' ? email : '채수원')
                        : '',
                    '',
                  ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // The whole address is laid out, not an ellipsis of it.
    final rendered = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('commit-profile-chip')),
        matching: find.byType(Text),
      ),
    );
    expect(rendered.map((text) => text.data), contains(email));
    for (final text in rendered) {
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      expect(
        painter.didExceedMaxLines,
        isFalse,
        reason: 'the chip must not clip ${text.data}',
      );
    }
    final chipRect = tester.getRect(
      find.byKey(const Key('commit-profile-chip')),
    );
    expect(
      tester.getRect(find.byKey(const Key('status-timestamp'))).right,
      lessThanOrEqualTo(chipRect.left),
    );
  });

  testWidgets('exact commit times ride the Date cell and the person block', (
    tester,
  ) async {
    final moment = DateTime.now().subtract(const Duration(hours: 3));
    final stamp = moment.millisecondsSinceEpoch ~/ 1000;
    final exact = exactCommitTime(stamp);
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit', timestamp: stamp)],
          workingTree: () async => workingTreeCommit('1'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    String? tooltipOn(String label) => tester
        .widgetList<Tooltip>(
          find.ancestor(of: find.text(label), matching: find.byType(Tooltip)),
        )
        .map((tooltip) => tooltip.message)
        .firstOrNull;

    // The commit row's Date cell carries the exact moment; the WIP row does not.
    expect(tooltipOn('3 hours ago'), exact);
    expect(tooltipOn('working tree'), isNull);
    // Nor does a date heading.
    expect(tooltipOn('Today'), isNull);

    // The preview person block spells it out under the social line. The working
    // tree leads the list, so the commit is two rows down.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final preview = find.byKey(const Key('preview-panel'));
    expect(
      find.descendant(of: preview, matching: find.text(exact)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: preview, matching: find.text(exact)),
          )
          .style
          ?.fontFamily,
      'monospace',
    );

    // The working tree row has no commit, so its preview shows no timestamp.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('No commit object or committer'), findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.text(exact)),
      findsNothing,
    );
  });
  // ------------------------------------------------------------------ A1
  testWidgets('the hash rule is an inset 2px strip', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    for (final index in [0, 1]) {
      final rule = find.byKey(Key('hash-rule-$index'));
      expect(rule, findsOneWidget, reason: 'row $index');
      final rect = tester.getRect(rule);
      expect(rect.width, 2);
      expect(rect.height, TimelineScreen.rowHeight - 2);
      // A 22px node still centres cleanly in the shorter row.
      final cell = tester.getRect(find.byKey(Key('graph-cell-$index')));
      final node = find.descendant(
        of: find.byKey(Key('graph-cell-$index')),
        matching: find.byType(CommitAvatarStack),
      );
      if (node.evaluate().isNotEmpty) {
        expect(tester.getRect(node).height, 22);
        expect(
          tester.getRect(node).top - cell.top,
          (TimelineScreen.rowHeight - 22) / 2,
        );
      }
      // 1px shy of the row at both ends.
      final row = tester.getRect(find.byKey(Key('graph-cell-$index')));
      expect(rect.top - row.top, 1);
      expect(row.bottom - rect.bottom, 1);
      expect(
        (tester.widget<ColoredBox>(
          find.descendant(of: rule, matching: find.byType(ColoredBox)),
        )).color,
        AvatarService.branchColor(0),
      );
    }
    // A date heading has no rule of its own.
    expect(find.byKey(const Key('hash-rule--1')), findsNothing);
  });

  // ------------------------------------------------------------------ A2
  testWidgets('each modal ref copies its full name', (tester) async {
    const long = 'feature/copy-me-in-full';
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('first', 'first commit'),
            commit(
              'many',
              'many refs',
              refs: const [
                GitRef(name: 'main', isHead: true),
                GitRef(name: long),
              ],
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // The modal takes the tap itself, so the row underneath keeps its selection.
    await tester.tap(find.byKey(Key('copy-ref-$long')));
    await tester.pumpAndSettle();
    expect(copied, [long]);
    expect(find.byKey(const Key('selected-row-many')), findsOneWidget);
    // It answers with a check, then goes back to the copy glyph.
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(Key('copy-ref-$long')),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.check,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(Key('copy-ref-$long')),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.copy_outlined,
    );
  });

  // ------------------------------------------------------------------ A3/A5
  testWidgets('the preview is selectable, clickable, and reads bigger', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 1,
              deletions: 1,
            ),
            GitFileChange(
              path: 'lib/b.dart',
              status: 'A',
              additions: 2,
              deletions: 0,
            ),
          ],
          diff: (_, _, path, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1 @@'),
            DiffLine(kind: DiffLineKind.add, text: '$path body', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('preview-panel'));
    // Every preview text sits under one SelectionArea.
    expect(
      find.ancestor(
        of: find.descendant(of: preview, matching: find.text('first commit')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
    double sizeOf(String label) {
      final finder = find.descendant(of: preview, matching: find.text(label));
      final text = tester.widgetList<Text>(finder).first;
      return text.style?.fontSize ??
          DefaultTextStyle.of(tester.element(finder.first)).style.fontSize!;
    }

    expect(sizeOf('Commit & Diff'), 12);
    expect(sizeOf('first commit'), 14);
    expect(sizeOf('commit 1'), 12);
    expect(sizeOf('Ada Author'), 14);
    expect(sizeOf('Cam Committer'), 14);
    expect(sizeOf('Committer · cam@example.com'), 12);
    expect(sizeOf('2 files changed'), 12);
    expect(sizeOf('lib/a.dart'), 12);

    expect(find.text('lib/a.dart body'), findsNothing);
    await tester.tap(
      find.descendant(of: preview, matching: find.text('lib/a.dart')),
    );
    await tester.pumpAndSettle();
    final firstBody = find.descendant(
      of: find.byKey(const Key('preview-diff')),
      matching: find.text('lib/a.dart body'),
    );
    final firstBodyText = tester.widget<Text>(firstBody);
    expect(
      firstBodyText.style?.fontSize ??
          DefaultTextStyle.of(tester.element(firstBody)).style.fontSize,
      14,
    );

    // A file row still switches the diff despite the selection layer.
    await tester.tap(
      find.descendant(of: preview, matching: find.text('lib/b.dart')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-diff')),
        matching: find.text('lib/b.dart body'),
      ),
      findsOneWidget,
    );
  });

  // ------------------------------------------------------------------ A4
  testWidgets('the preview panel resizes, persists, and clamps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    ({double width, double height})? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onPreviewSizeChanged: (size) => saved = size,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    double previewWidth() =>
        tester.getSize(find.byKey(const Key('preview-panel'))).width;
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    expect(previewWidth(), 288);
    final title = titleWidth();

    // Dragging the inner edge left widens the panel; the timeline gives back
    // exactly that much.
    await tester.drag(
      find.byKey(const Key('preview-resizer')),
      const Offset(-60, 0),
    );
    await tester.pumpAndSettle();
    expect(previewWidth(), 348);
    expect(saved?.width, 348);
    expect(titleWidth(), title - 60);

    // The horizontal maximum follows 75% of the whole app window.
    await tester.drag(
      find.byKey(const Key('preview-resizer')),
      const Offset(-1400, 0),
    );
    await tester.pumpAndSettle();
    expect(previewWidth(), 1200);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(previewWidth(), 900);

    await tester.drag(
      find.byKey(const Key('preview-resizer')),
      const Offset(1200, 0),
    );
    await tester.pumpAndSettle();
    expect(previewWidth(), 240);
    expect(saved?.width, 240);

    // The bottom panel can grow to the column headers, regardless of the old
    // fixed 480px ceiling.
    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('preview-resizer')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    final previewRect = tester.getRect(find.byKey(const Key('preview-panel')));
    final headerRect = tester.getRect(find.byKey(const Key('refs-header')));
    expect(previewRect.height, greaterThan(480));
    expect(previewRect.top, closeTo(headerRect.bottom, 0.01));
    expect(saved?.height, previewRect.height);

    // Round-trips with the rest of the settings, clamped on the way in.
    expect(const AppSettings().previewWidth, 288);
    expect(const AppSettings().previewHeight, 280);
    expect(
      AppSettings.fromJson(
        const AppSettings(previewWidth: 400, previewHeight: 300).toJson(),
      ).previewWidth,
      400,
    );
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'previewWidth': 40,
        'previewHeight': 4000,
      }).previewWidth,
      240,
    );
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'previewWidth': 40,
        'previewHeight': 4000,
      }).previewHeight,
      4000,
    );
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'previewWidth': 1400,
      }).previewWidth,
      1400,
    );
    const diffSizes = AppSettings(
      previewDiffLeftWidth: 240,
      previewDiffRightWidth: 360,
      previewDiffBottomHeight: 420,
    );
    expect(AppSettings.fromJson(diffSizes.toJson()), diffSizes);
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'previewDiffLeftWidth': -1,
      }).previewDiffLeftWidth,
      0,
    );
  });

  // ------------------------------------------------------------------ A6
  testWidgets('local branches follow their tips down the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('newest', 'newest commit'),
            commit('middle', 'middle commit'),
            commit('oldest', 'oldest commit'),
          ],
          refs: const RepoRefs(
            local: ['main', 'zeta', 'alpha', 'gone'],
            current: 'main',
            tips: {
              'main': 'middle',
              'zeta': 'newest',
              'alpha': 'oldest',
              'gone': 'unloaded',
            },
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    double top(String name) =>
        tester.getRect(find.byKey(Key('sidebar-ref-$name'))).top;
    // Checked-out first, then by tip position, then the unloaded tip.
    expect(top('main'), lessThan(top('zeta')));
    expect(top('zeta'), lessThan(top('alpha')));
    expect(top('alpha'), lessThan(top('gone')));
  });

  test('deleted branch line tip ignores the synthetic working tree row', () {
    final rows = [
      graphRow(commit: workingTreeCommit('tip'), lane: 0, branch: 3),
      graphRow(commit: commit('tip', 'tip'), lane: 0, branch: 3),
      graphRow(commit: commit('older', 'older'), lane: 0, branch: 3),
    ];

    expect(branchLineTipSha(rows, 3), 'tip');
    expect(branchLineTipSha(rows, 4), isNull);
  });

  testWidgets(
    'deleted branch selection shows loading then a recovered name badge',
    (tester) async {
      final resolver = Completer<String?>();
      final commits = [
        commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
        commit('main-parent', 'main parent', parents: const ['base']),
        commit('side-tip', 'side commit', parents: const ['base']),
        commit('base', 'base'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (skip, _) async => skip == 0 ? commits : const [],
              refs: const RepoRefs(),
              deletedBranchNameCallback: (tipSha, _) =>
                  tipSha == 'side-tip' ? resolver.future : Future.value(null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('side commit'));
      await tester.pump();
      expect(
        find.byKey(const Key('deleted-branch-loading-side-tip')),
        findsOneWidget,
      );
      expect(find.text('브랜치 이름 찾는 중…'), findsOneWidget);

      resolver.complete('feature/gone');
      await tester.pumpAndSettle();

      final badge = tester.widget<Container>(
        find.byKey(const Key('deleted-branch-badge-side-tip')),
      );
      final badgeColor = (badge.decoration! as BoxDecoration).color!;
      expect(badgeColor.r, greaterThan(badgeColor.g));
      expect(badgeColor.a, lessThan(1));
      expect(find.text('삭제됨'), findsOneWidget);
      expect(find.text('feature/gone'), findsOneWidget);

      await tester.tap(find.text('main parent'));
      await tester.pump();
      expect(
        find.byKey(const Key('deleted-branch-badge-side-tip')),
        findsNothing,
      );
      expect(find.text('feature/gone'), findsNothing);
    },
  );

  testWidgets('deleted branch cache renders without another lookup', (
    tester,
  ) async {
    var lookups = 0;
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge'},
              localTips: {'main': 'merge'},
            ),
            deletedBranchNameCallback: (_, _) async {
              lookups++;
              return 'feature/looked-up';
            },
          ),
          deletedBranchNames: const {'side-tip': 'feature/cached'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pump();

    expect(find.text('feature/cached'), findsOneWidget);
    expect(
      find.byKey(const Key('deleted-branch-loading-side-tip')),
      findsNothing,
    );
    expect(lookups, 0);
  });

  testWidgets('deleted branch recovery persists per repository', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (skip, _) async => skip == 0 ? commits : const [],
          root: '/repo',
          refs: const RepoRefs(
            local: ['main'],
            current: 'main',
            tips: {'main': 'merge'},
            localTips: {'main': 'merge'},
          ),
          deletedBranchNameCallback: (_, _) async => 'feature/gone',
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pumpAndSettle();

    expect(store.current.deletedBranchNames, {
      '/repo': {'side-tip': 'feature/gone'},
    });
  });

  testWidgets('deleted branch lookup skips a lane tip with a live ref', (
    tester,
  ) async {
    var localLookups = 0;
    var remoteLookups = 0;
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit(
        'side-tip',
        'side commit',
        parents: const ['base'],
        refs: const [GitRef(name: 'feature/live')],
      ),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge'},
              localTips: {'main': 'merge'},
            ),
            deletedBranchNameCallback: (_, _) async {
              localLookups++;
              return null;
            },
          ),
          avatarService: AvatarService(
            remote: const RemoteRepository(
              host: 'github.com',
              owner: 'team',
              repository: 'yogit',
            ),
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  remoteLookups++;
                  return ProcessResult(1, 1, '', 'offline');
                },
          ),
          showRemoteAvatars: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pumpAndSettle();

    expect(find.text('feature/live'), findsWidgets);
    expect(find.text('삭제됨'), findsNothing);
    expect(localLookups, 0);
    expect(remoteLookups, 0);
  });

  testWidgets('deleted branch lookup failure clears loading and stays usable', (
    tester,
  ) async {
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge'},
              localTips: {'main': 'merge'},
            ),
            deletedBranchNameCallback: (_, _) => Future.error('missing'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('deleted-branch-loading-side-tip')),
      findsNothing,
    );

    await tester.tap(find.text('main parent'));
    await tester.pump();
    expect(find.text('main parent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted branch stale result never labels the new selection', (
    tester,
  ) async {
    final resolver = Completer<String?>();
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge'},
              localTips: {'main': 'merge'},
            ),
            deletedBranchNameCallback: (_, _) => resolver.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pump();
    await tester.tap(find.text('main parent'));
    resolver.complete('feature/gone');
    await tester.pumpAndSettle();

    expect(find.text('feature/gone'), findsNothing);
    expect(find.text('삭제됨'), findsNothing);
  });

  testWidgets('deleted branch lookup ignores a stale avatar service result', (
    tester,
  ) async {
    final oldResult = Completer<ProcessResult>();
    late StateSetter update;
    var service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'old',
      ),
      runner: (executable, arguments, {workingDirectory, environment}) =>
          oldResult.future,
    );
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    final repository = FakeGitRepository(
      (skip, _) async => skip == 0 ? commits : const [],
      refs: const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': 'merge'},
        localTips: {'main': 'merge'},
      ),
      deletedBranchNameCallback: (_, _) async => null,
    );
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            home: TimelineScreen(
              repository: repository,
              avatarService: service,
              showRemoteAvatars: false,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pump();
    update(() {
      service = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'new',
        ),
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(
                  1,
                  0,
                  jsonEncode([
                    {
                      'merged_at': '2026-07-29T00:00:00Z',
                      'head': {'sha': 'side-tip', 'ref': 'feature/new'},
                    },
                  ]),
                  '',
                ),
      );
    });
    await tester.pump();
    oldResult.complete(
      ProcessResult(
        1,
        0,
        jsonEncode([
          {
            'merged_at': '2026-07-28T00:00:00Z',
            'head': {'sha': 'side-tip', 'ref': 'feature/old'},
          },
        ]),
        '',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feature/old'), findsNothing);
    expect(find.text('feature/new'), findsOneWidget);
  });

  testWidgets('deleted branch concurrent lookups keep each loading state', (
    tester,
  ) async {
    final sideA = Completer<String?>();
    final sideB = Completer<String?>();
    final commits = [
      commit('merge-a', 'merge a', parents: const ['merge-b', 'side-a']),
      commit('merge-b', 'merge b', parents: const ['base', 'side-b']),
      commit('side-a', 'side a', parents: const ['base']),
      commit('side-b', 'side b', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge-a'},
              localTips: {'main': 'merge-a'},
            ),
            deletedBranchNameCallback: (tipSha, _) => switch (tipSha) {
              'side-a' => sideA.future,
              'side-b' => sideB.future,
              _ => Future.value(null),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side a'));
    await tester.pump();
    await tester.tap(find.text('side b'));
    await tester.pump();
    await tester.tap(find.text('side a'));
    await tester.pump();

    expect(
      find.byKey(const Key('deleted-branch-loading-side-a')),
      findsOneWidget,
    );

    sideA.complete(null);
    sideB.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('deleted branch remote failure is attempted once per run', (
    tester,
  ) async {
    var localLookups = 0;
    var remoteLookups = 0;
    final commits = [
      commit('merge', 'merge', parents: const ['main-parent', 'side-tip']),
      commit('main-parent', 'main parent', parents: const ['base']),
      commit('side-tip', 'side commit', parents: const ['base']),
      commit('base', 'base'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (skip, _) async => skip == 0 ? commits : const [],
            refs: const RepoRefs(
              local: ['main'],
              current: 'main',
              tips: {'main': 'merge'},
              localTips: {'main': 'merge'},
            ),
            deletedBranchNameCallback: (_, _) async {
              localLookups++;
              return null;
            },
          ),
          avatarService: AvatarService(
            remote: const RemoteRepository(
              host: 'github.com',
              owner: 'team',
              repository: 'yogit',
            ),
            runner:
                (executable, arguments, {workingDirectory, environment}) async {
                  remoteLookups++;
                  return ProcessResult(1, 1, '', 'offline');
                },
          ),
          showRemoteAvatars: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('side commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('main parent'));
    await tester.tap(find.text('side commit'));
    await tester.pumpAndSettle();

    expect(localLookups, 1);
    expect(remoteLookups, 1);
  });

  testWidgets(
    'preferred local branch ignores a same-named tag at another commit',
    (tester) async {
      late Directory root;
      late String localRelease;
      late String tagRelease;
      late RepoRefs refs;
      late List<GitCommit> commits;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp(
          'yogit_local_tag_collision_',
        );
        Future<String> git(List<String> arguments) async {
          final result = await Process.run(
            'git',
            arguments,
            workingDirectory: root.path,
          );
          expect(result.exitCode, 0, reason: result.stderr.toString());
          return result.stdout.toString().trim();
        }

        await git(['init', '-b', 'main']);
        await git(['config', 'user.name', 'Test User']);
        await git(['config', 'user.email', 'test@example.com']);
        await File('${root.path}/history.txt').writeAsString('local release\n');
        await git(['add', 'history.txt']);
        await git(['commit', '-m', 'local release tip']);
        localRelease = await git(['rev-parse', 'HEAD']);
        await git(['branch', 'release']);
        await File(
          '${root.path}/history.txt',
        ).writeAsString('same-named tag\n');
        await git(['commit', '-am', 'same-named tag tip']);
        tagRelease = await git(['rev-parse', 'HEAD']);
        await git(['tag', 'release']);
        final repository = GitRepository(root.path);
        refs = await repository.loadRefs();
        commits = await repository.loadHistory();
      });
      addTearDown(() => root.delete(recursive: true));

      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (_, _) async => commits,
              root: root.path,
              refs: refs,
            ),
            preferredBranch: 'release',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-menu-release')));
      await tester.pumpAndSettle();

      final rows = {
        for (final paint in tester.widgetList<CustomPaint>(
          find.byType(CustomPaint),
        ))
          if (paint.painter case final CommitGraphPainter painter)
            painter.row.commit.sha: painter.row.lane,
      };
      expect(rows[localRelease], 0);
      expect(rows[tagRelease], greaterThanOrEqualTo(1));
    },
  );

  // ------------------------------------------------------------------ C1/C2
  testWidgets('preview file list and diff scroll independently', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          files: (_, _) async => [
            for (var index = 0; index < 3; index++)
              GitFileChange(
                path: 'lib/file$index.dart',
                status: 'M',
                additions: 1,
                deletions: 1,
              ),
          ],
          diff: (_, _, _, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1,80 @@'),
            for (var index = 0; index < 80; index++)
              DiffLine(
                kind: DiffLineKind.add,
                text: 'line $index',
                newNumber: index + 1,
              ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final filesScrollable = find.byKey(const Key('preview-files-scroll'));
    await tester.tap(find.byKey(const Key('preview-state-lib/file0.dart')));
    await tester.pumpAndSettle();
    final diffScrollable = find.byKey(const Key('preview-diff-scroll'));
    expect(filesScrollable, findsOneWidget);
    expect(diffScrollable, findsOneWidget);

    final firstFile = find.byKey(const Key('preview-state-lib/file0.dart'));
    final before = tester.getTopLeft(firstFile).dy;
    await tester.drag(diffScrollable, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstFile).dy, closeTo(before, 0.1));
  });

  testWidgets('preview page shortcut prioritizes a scrollable adjacent diff', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'scroll targets')],
          files: (_, _) async => [
            for (var index = 0; index < 20; index++)
              GitFileChange(
                path: 'lib/file$index.dart',
                status: 'M',
                additions: 1,
                deletions: 0,
              ),
          ],
          diff: (_, _, path, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1,80 @@'),
            for (var index = 0; index < 80; index++)
              DiffLine(
                kind: DiffLineKind.add,
                text: '$path line $index',
                newNumber: index + 1,
              ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-state-lib/file0.dart')));
    await tester.pumpAndSettle();

    final previewPosition = tester
        .widget<NestedScrollView>(
          find.byKey(const Key('preview-content-scroll')),
        )
        .controller!
        .position;
    final diffPosition = tester
        .widget<ListView>(find.byKey(const Key('unified-list')))
        .controller!
        .position;

    Future<void> page(LogicalKeyboardKey arrow) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(arrow);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    expect(previewPosition.maxScrollExtent, greaterThan(0));
    expect(diffPosition.maxScrollExtent, greaterThan(0));
    await page(LogicalKeyboardKey.arrowDown);
    expect(diffPosition.pixels, greaterThan(0));
    expect(previewPosition.pixels, 0);

    for (
      var attempt = 0;
      attempt < 10 && diffPosition.extentAfter > 0;
      attempt++
    ) {
      diffPosition.jumpTo(diffPosition.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(diffPosition.extentAfter, 0);
    await page(LogicalKeyboardKey.arrowDown);
    expect(
      previewPosition.pixels,
      greaterThan(0),
      reason:
          'diff=${diffPosition.pixels}/${diffPosition.maxScrollExtent} '
          'after=${diffPosition.extentAfter} '
          'previewAfter=${previewPosition.extentAfter}',
    );

    previewPosition.jumpTo(previewPosition.maxScrollExtent);
    await tester.pump();
    final previewEnd = previewPosition.pixels;
    final diffEnd = diffPosition.pixels;
    await page(LogicalKeyboardKey.arrowDown);
    expect(previewPosition.pixels, previewEnd);
    expect(diffPosition.pixels, diffEnd);
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    await page(LogicalKeyboardKey.arrowUp);
    expect(diffPosition.pixels, lessThan(diffEnd));
    expect(previewPosition.pixels, previewEnd);
  });

  // ------------------------------------------------------------------ C3/H2
  testWidgets('the preview header carries the compact green Full Diff', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onOpenFullDiff: (commit) => opened.add(commit.sha),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The full-width blue CTA is gone.
    expect(find.byKey(const Key('open-full-diff')), findsNothing);
    expect(find.text('Open full diff'), findsNothing);

    // A compact green twin of the toolbar's button sits at the header's right.
    final button = find.byKey(const Key('preview-full-diff'));
    final header = tester.getRect(find.text('Commit & Diff'));
    final rect = tester.getRect(button);
    expect(rect.height, 28);
    expect(rect.left, greaterThan(header.right));
    expect(
      find.descendant(of: button, matching: find.text('Full Diff')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.text('⌘D')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('preview-hash')), findsNothing);
    expect(
      (tester
                  .widget<Container>(
                    find.descendant(
                      of: button,
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      const Color(0xFF2EA043),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: button, matching: find.text('Full Diff')),
          )
          .style
          ?.fontSize,
      11,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, ['1']);
  });

  // ------------------------------------------------------------------ C5/C6
  testWidgets('the commit stamp gives way to the profile instead of hiding', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    // Narrow enough that the DATE column sits where the profile chip is.
    tester.view.physicalSize = const Size(760, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final stamp =
        DateTime.now()
            .subtract(const Duration(hours: 5))
            .millisecondsSinceEpoch ~/
        1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit', timestamp: stamp)],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final stampRect = tester.getRect(find.byKey(const Key('status-timestamp')));
    final chipRect = tester.getRect(
      find.byKey(const Key('commit-profile-chip')),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('status-timestamp'))).data,
      exactCommitTime(stamp),
    );
    // The stamp ends before the chip starts, so nothing covers the date.
    expect(stampRect.right, lessThanOrEqualTo(chipRect.left));
    expect(stampRect.left, greaterThanOrEqualTo(0));
  });

  testWidgets('the status bar stamps the focused commit under HASH', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final stamp =
        DateTime.now()
            .subtract(const Duration(hours: 5))
            .millisecondsSinceEpoch ~/
        1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1234567', 'first commit', timestamp: stamp)],
          workingTree: () async => workingTreeCommit('1234567'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    Text status() =>
        tester.widget<Text>(find.byKey(const Key('status-timestamp')));
    double statusLeft() =>
        tester.getRect(find.byKey(const Key('status-timestamp'))).left;
    double shaLeft() => tester.getRect(find.text('1234567')).left;
    double chipLeft() =>
        tester.getRect(find.byKey(const Key('commit-profile-chip'))).left;
    // The stamp lines up with the sha it belongs to, and never ends up beneath
    // the chip.
    void expectStampPlacedForHash() {
      expect(statusLeft(), moreOrLessEquals(shaLeft(), epsilon: 0.5));
      expect(
        tester.getRect(find.byKey(const Key('status-timestamp'))).right,
        lessThanOrEqualTo(chipLeft()),
      );
    }

    // The working tree leads the list, so nothing to stamp yet.
    expect(status().data, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // A date heading has no commit either.
    expect(status().data, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(status().data, exactCommitTime(stamp));
    expectStampPlacedForHash();

    // Resizing the columns keeps that relationship: HASH does not move when it
    // widens, so the stamp holds its column.
    await tester.drag(
      find.byKey(const Key('hash-resizer')),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expectStampPlacedForHash();

    // The old right-hand rail label is gone.
    expect(find.textContaining('2px rail'), findsNothing);
    expect(find.text('commit'), findsOneWidget);
  });
  // ------------------------------------------------------------------ D1
  testWidgets('the toolbar full-diff button and Cmd+D open the same screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('a', 'today commit'),
              commit(
                'b',
                'older commit',
                timestamp:
                    DateTime.now()
                        .subtract(const Duration(days: 3))
                        .millisecondsSinceEpoch ~/
                    1000,
              ),
            ],
          ),
          controller: controller,
          onOpenFullDiff: (commit) => opened.add(commit.sha),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('toolbar-full-diff'));
    expect(button, findsOneWidget);
    // The name with its shortcut underneath, on green.
    expect(
      find.descendant(of: button, matching: find.text('Full Diff')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.text('⌘D')),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(find.descendant(of: button, matching: find.text('⌘D')))
          .top,
      greaterThan(
        tester
            .getRect(
              find.descendant(of: button, matching: find.text('Full Diff')),
            )
            .top,
      ),
    );
    Color background() =>
        (tester
                    .widget<Container>(
                      find.descendant(
                        of: button,
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(background(), const Color(0xFF2EA043));
    // Right of the preview control and left of the gear.
    expect(
      tester.getRect(button).left,
      greaterThan(tester.getRect(find.text('하단')).left),
    );
    expect(
      tester.getRect(button).right,
      lessThan(tester.getRect(find.byIcon(Icons.settings_outlined)).left),
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, ['a']);

    // Cmd+D does the same for the selected commit.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(opened, ['a', 'a']);

    // The first date heading has no commit: the button dims and the shortcut
    // does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsNothing);
    expect(background(), TimelineThemePalette.systemGraphite.raised);
    expect(
      tester
          .widget<GestureDetector>(
            find.descendant(of: button, matching: find.byType(GestureDetector)),
          )
          .onTap,
      isNull,
    );
    await tester.tap(button);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(opened, ['a', 'a']);
  });

  // ------------------------------------------------------------------ D2
  testWidgets('technical data uses mono while prose uses the system font', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              '1',
              '한글 커밋 메시지도 정렬됩니다',
              timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final hash = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('selected-row-1')),
        matching: find.text('1'),
      ),
    );
    expect(hash.style?.fontFamily, technicalFontFamily);
    expect(hash.style?.fontFamilyFallback, technicalFontFallback);

    for (final label in ['한글 커밋 메시지도 정렬됩니다', 'just now', 'Ada Author']) {
      expect(
        tester.widget<Text>(find.text(label).first).style?.fontFamily,
        isNull,
        reason: label,
      );
    }
  });
  // ------------------------------------------------------------------ E2
  testWidgets('local branches show when they were cut, when the reflog knows', (
    tester,
  ) async {
    final born = DateTime.now().subtract(const Duration(days: 5));
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: RepoRefs(
            local: const ['main', 'feature/dated', 'feature/unknown'],
            current: 'main',
            birthTimes: {'feature/dated': born.millisecondsSinceEpoch ~/ 1000},
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // The dated branch grows a second line in the Date column's own words.
    final dated = find.byKey(const Key('sidebar-ref-feature/dated'));
    expect(tester.getSize(dated).height, 40);
    final label = socialTimeLabel(born, DateTime.now());
    expect(label, '5 days ago');
    expect(
      find.descendant(of: dated, matching: find.text(label)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.descendant(of: dated, matching: find.text(label)))
          .style
          ?.fontSize,
      11,
    );

    // No reflog entry, no second line.
    final unknown = find.byKey(const Key('sidebar-ref-feature/unknown'));
    expect(tester.getSize(unknown).height, 28);
    expect(
      find.descendant(of: unknown, matching: find.byType(Text)),
      findsOneWidget,
    );
    // The checked-out branch keeps its highlight around whatever it holds.
    expect(
      tester.getSize(find.byKey(const Key('sidebar-ref-main'))).height,
      28,
    );
  });

  // ------------------------------------------------------------------ E3
  testWidgets('the status bar names and copies the focused row ref', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    const long = 'release/2026-07-a-very-long-branch-name-indeed';
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              'tip',
              'line tip',
              parents: const ['middle'],
              refs: const [
                GitRef(name: long),
                GitRef(name: 'v1.0', isTag: true),
              ],
            ),
            // No chip of its own: it inherits its line's name.
            commit('middle', 'mid-line commit', parents: const ['root']),
            commit('root', 'root commit'),
          ],
          workingTree: () async => workingTreeCommit('tip'),
          refs: const RepoRefs(local: ['main', long], current: 'main'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // The working tree leads the list and names the checked-out branch.
    final status = find.byKey(const Key('status-ref'));
    expect(
      find.descendant(of: status, matching: find.text('main')),
      findsOneWidget,
    );

    // A mid-line commit with no chip of its own still names its line's tip.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-middle')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('refs-cell-2')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    // Aligned with the BRANCH / TAG column, showing that line's name.
    expect(
      tester.getRect(status).left,
      tester.getRect(find.byKey(const Key('refs-header'))).left,
    );
    expect(
      find.descendant(of: status, matching: find.text(long)),
      findsOneWidget,
    );
    // Truncated before the DATE stamp it shares the bar with.
    expect(
      tester.getRect(status).right,
      lessThan(tester.getRect(find.byKey(const Key('status-timestamp'))).left),
    );

    await tester.tap(find.byKey(const Key('status-copy-$long')));
    await tester.pumpAndSettle();
    expect(copied, [long]);
    await tester.pump(const Duration(seconds: 1));

    // The row below is on the same line, so it keeps the same name.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-root')), findsOneWidget);
    expect(
      find.descendant(of: status, matching: find.text(long)),
      findsOneWidget,
    );

    // A date heading names nothing.
    for (var press = 0; press < 3; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-tip')), findsNothing);
    expect(
      find.descendant(of: status, matching: find.byType(Text)),
      findsNothing,
    );

    // And a line whose tip carries no ref at all stays blank. Keyed, so the
    // screen remounts and reloads instead of reusing the old history.
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          key: const Key('unnamed'),
          repository: FakeGitRepository(
            (_, _) async => [
              commit('a', 'unnamed line', parents: const ['b']),
              commit('b', 'unnamed root'),
            ],
            refs: const RepoRefs(),
          ),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);
    expect(
      find.descendant(of: status, matching: find.byType(Text)),
      findsNothing,
    );
  });
  testWidgets('base branch restores a valid choice and falls back to current', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('feature-tip', 'feature'),
              commit('main-tip', 'main'),
            ],
            refs: const RepoRefs(
              local: ['main', 'feature'],
              current: 'main',
              tips: {'main': 'main-tip', 'feature': 'feature-tip'},
            ),
          ),
          preferredBranch: 'deleted',
          onPreferredBranchChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main'), findsWidgets);
    expect(changes, ['main']);
    final featurePainter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter
            as CommitGraphPainter;
    expect(featurePainter.row.lane, 1);
  });

  testWidgets('base branch refs failure keeps timeline history visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('tip', 'timeline survives')],
            refsLoader: () => Future<RepoRefs>.error(StateError('refs failed')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('불러오기 실패'), findsOneWidget);
    expect(find.text('timeline survives'), findsOneWidget);
  });

  testWidgets(
    'base branch applies a delayed setting without losing selection or scroll',
    (tester) async {
      final repository = FakeGitRepository(
        (_, _) async => [
          commit('feature-tip', 'feature'),
          commit('main-tip', 'main'),
          for (var index = 0; index < 40; index++)
            commit('older-$index', 'older $index'),
        ],
        refs: const RepoRefs(
          local: ['main', 'feature'],
          current: 'main',
          tips: {'main': 'main-tip', 'feature': 'feature-tip'},
        ),
      );
      String? preferredBranch;
      late StateSetter updateHarness;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHarness = setState;
              return TimelineScreen(
                repository: repository,
                preferredBranch: preferredBranch,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(find.byKey(const Key('selected-row-main-tip')), findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('timeline-list')),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(TimelineScreen.rowHeight);
      await tester.pump();
      final before = scrollable.position.pixels;

      updateHarness(() => preferredBranch = 'feature');
      await tester.pump();

      expect(find.byKey(const Key('selected-row-main-tip')), findsOneWidget);
      expect(scrollable.position.pixels, before);
      expect(find.text('feature'), findsWidgets);
      final featurePainter =
          tester
                  .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                  .painter
              as CommitGraphPainter;
      expect(featurePainter.row.lane, 0);
    },
  );

  testWidgets(
    'base branch selector relayout preserves preview and loaded history pages',
    (tester) async {
      final historyCalls = <int>[];
      final firstPage = [
        for (var index = 0; index < 500; index++)
          commit('$index', 'commit $index'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (skip, _) async {
                historyCalls.add(skip);
                return skip == 0 ? firstPage : [commit('500', 'commit 500')];
              },
              refs: const RepoRefs(
                local: ['main', 'feature'],
                current: 'main',
                tips: {'main': '499', 'feature': '0'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('timeline-list')),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(historyCalls, [0, 500]);
      await tester.tap(find.text('commit 500'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-row-500')), findsOneWidget);
      expect(find.text('Commit & Diff'), findsOneWidget);
      final before = scrollable.position.pixels;

      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-branch-menu-feature')));
      await tester.pumpAndSettle();

      expect(historyCalls, [0, 500]);
      expect(find.byKey(const Key('selected-row-500')), findsOneWidget);
      expect(find.text('Commit & Diff'), findsOneWidget);
      expect(scrollable.position.pixels, before);
      expect(find.text('feature'), findsWidgets);
    },
  );

  // ------------------------------------------------------------------ F3
  testWidgets('full diff steps hunks and toggles focus from the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final commits = [
      commit('1', 'commit', parents: const ['0']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async => const [
        GitFileChange(
          path: 'lib/a.dart',
          status: 'M',
          additions: 3,
          deletions: 3,
        ),
      ],
      diff: (_, _, _, _, _) async => const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old one', oldNumber: 1),
        DiffLine(kind: DiffLineKind.add, text: 'new one', newNumber: 1),
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -10 +10 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old two', oldNumber: 10),
        DiffLine(kind: DiffLineKind.add, text: 'new two', newNumber: 10),
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -20 +20 @@'),
        DiffLine(kind: DiffLineKind.delete, text: 'old three', oldNumber: 20),
        DiffLine(kind: DiffLineKind.add, text: 'new three', newNumber: 20),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(session.state.activeAnchor?.hunkIndex, 1);
    final target = find.byKey(const Key('unified-hunk-1'));
    final viewport = tester.getRect(find.byKey(const Key('unified-list')));
    final targetRect = tester.getRect(target);
    expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
    expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(session.state.activeAnchor?.hunkIndex, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(session.state.focusMode, isTrue);
    expect(find.byKey(const Key('nearby-column')), findsNothing);
    expect(find.byKey(const Key('details-files-column')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(session.state.focusMode, isFalse);
  });

  testWidgets('option-down reveals a hunk beyond the lazy list cache', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final commits = [
      commit('1', 'commit', parents: const ['0']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async => const [
        GitFileChange(
          path: 'lib/a.dart',
          status: 'M',
          additions: 1,
          deletions: 0,
        ),
      ],
      diff: (_, _, _, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,120 +1,120 @@'),
        for (var index = 1; index <= 120; index++)
          DiffLine(
            kind: DiffLineKind.context,
            text: 'first hunk line $index',
            oldNumber: index,
            newNumber: index,
          ),
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -500,0 +500 @@'),
        const DiffLine(
          kind: DiffLineKind.add,
          text: 'second destination',
          newNumber: 500,
        ),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    const targetKey = Key('unified-hunk-1');
    expect(find.byKey(targetKey), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(session.state.activeAnchor?.hunkIndex, 1);
    final target = find.byKey(targetKey);
    expect(target, findsOneWidget);
    final viewport = tester.getRect(find.byKey(const Key('unified-list')));
    final targetRect = tester.getRect(target);
    expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
    expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));

    final scroll = tester
        .widget<ListView>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(ListView),
              )
              .first,
        )
        .controller!;
    final offset = scroll.offset;
    final serial = session.state.navigationSerial;
    session.syncAnchorFromScroll(session.state.patch.data!.hunks.first.anchor);
    await tester.pumpAndSettle();

    expect(session.state.navigationSerial, serial);
    expect(scroll.offset, offset);
  });

  testWidgets('full diff shares preview page scrolling', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final commits = [
      commit('newer', 'newer commit', parents: const ['older']),
      commit('older', 'older commit', parents: const ['root']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (commit, _) async => [
        for (final name in ['one', 'two'])
          GitFileChange(
            path: '${commit.sha}/$name.dart',
            status: 'M',
            additions: 0,
            deletions: 0,
          ),
      ],
      diff: (_, _, path, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,80 +1,80 @@'),
        for (var index = 1; index <= 80; index++)
          DiffLine(
            kind: DiffLineKind.context,
            text: '$path line $index',
            oldNumber: index,
            newNumber: index,
          ),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();
    session.setLayout(DiffLayout.unified);
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<ListView>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(ListView),
              )
              .first,
        )
        .controller!;
    final selectedCommit = session.state.selectedCommit;
    final selectedFile = session.state.selectedFile;
    final pageDistance = scroll.position.viewportDimension * 0.5;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scroll.offset, pageDistance);
    expect(session.state.selectedCommit, selectedCommit);
    expect(session.state.selectedFile, selectedFile);

    scroll.jumpTo(0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final beforeRepeat = scroll.offset;
    expect(beforeRepeat, pageDistance);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    expect(
      scroll.offset,
      closeTo(
        (beforeRepeat + pageDistance).clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        ),
        0.001,
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(session.state.selectedCommit, selectedCommit);
    expect(session.state.selectedFile, selectedFile);

    scroll.jumpTo(0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    final maximum = scroll.position.maxScrollExtent;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(scroll.offset, lessThanOrEqualTo(maximum));
  });

  testWidgets('history page scrolling targets the detail diff, not its list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final commits = [
      commit('current', 'current commit', parents: const ['previous']),
    ];
    final historyCommits = [
      commits.single,
      for (var index = 1; index <= 30; index++)
        commit(
          'history-$index',
          'history commit $index',
          parents: ['history-${index + 1}'],
        ),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async => const [
        GitFileChange(
          path: 'lib/a.dart',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, path, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,80 +1,80 @@'),
        for (var index = 1; index <= 80; index++)
          DiffLine(
            kind: DiffLineKind.context,
            text: '$path line $index',
            oldNumber: index,
            newNumber: index,
          ),
      ],
      history: (_, file) async => [
        for (final historyCommit in historyCommits)
          GitFileHistoryRecord(
            commit: historyCommit,
            path: file.path,
            oldPath: null,
            status: 'M',
          ),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();
    session
      ..setView(FullDiffView.history)
      ..setLayout(DiffLayout.unified);
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final historyScroll = tester
        .widget<ListView>(find.byKey(const Key('history-list')))
        .controller!;
    final detailScroll = tester
        .widget<ListView>(
          find
              .descendant(
                of: find.byKey(const Key('history-detail-pane')),
                matching: find.byType(ListView),
              )
              .first,
        )
        .controller!;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(detailScroll.offset, detailScroll.position.viewportDimension * 0.5);
    expect(historyScroll.offset, 0);
  });

  testWidgets('full diff popup handles arrows before screen shortcuts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final commits = [
      commit('1', 'commit', parents: const ['0']),
    ];
    final repository = FakeGitRepository(
      (_, _) async => commits,
      files: (_, _) async => const [
        GitFileChange(
          path: 'one.dart',
          status: 'M',
          additions: 0,
          deletions: 0,
        ),
        GitFileChange(
          path: 'two.dart',
          status: 'M',
          additions: 0,
          deletions: 0,
        ),
      ],
      diff: (_, _, path, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,40 +1,40 @@'),
        for (var index = 1; index <= 40; index++)
          DiffLine(
            kind: DiffLineKind.context,
            text: '$path line $index',
            oldNumber: index,
            newNumber: index,
          ),
      ],
    );
    final session = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    addTearDown(session.dispose);
    await session.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: commits,
          initialIndex: 0,
          controller: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<ListView>(find.byKey(const Key('unified-list')))
        .controller!;
    final selectedCommit = session.state.selectedCommit;
    final selectedFile = session.state.selectedFile;
    final activeAnchor = session.state.activeAnchor;
    final offset = scroll.offset;

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    expect(find.text('Minimal'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(session.state.selectedCommit, selectedCommit);
    expect(session.state.selectedFile, selectedFile);
    expect(session.state.activeAnchor, activeAnchor);
    expect(scroll.offset, offset);
    expect(find.byKey(const Key('algorithm-details-minimal')), findsOneWidget);
  });

  testWidgets('the diff screen walks files from the keyboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('newer', 'newer commit', parents: const ['older']),
        commit('older', 'older commit', parents: const ['root']),
      ],
      files: (commit, _) async => [
        for (final name in ['one', 'two', 'three'])
          GitFileChange(
            path: '${commit.sha}/$name.dart',
            status: 'M',
            additions: 1,
            deletions: 1,
          ),
      ],
      diff: (commit, _, path, _, _) async => [
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
        DiffLine(kind: DiffLineKind.add, text: 'body of $path', newNumber: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [
            commit('newer', 'newer commit', parents: const ['older']),
            commit('older', 'older commit', parents: const ['root']),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<Focus>(find.byKey(const Key('changed-files-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();

    // It opens on the first file of the first commit.
    expect(find.text('body of newer/one.dart'), findsOneWidget);
    expect(
      find.byKey(const Key('selected-file-newer/one.dart')),
      findsOneWidget,
    );

    // Down walks the file list, loading each diff as it goes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/two.dart'), findsOneWidget);
    expect(
      find.byKey(const Key('selected-file-newer/two.dart')),
      findsOneWidget,
    );
    // Autorepeat keeps walking.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/three.dart'), findsOneWidget);
    // And it stops at the end rather than wrapping.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/three.dart'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/two.dart'), findsOneWidget);

    // Cmd+Down walks the same file list from any focused child.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/three.dart'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/two.dart'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('body of newer/one.dart'), findsOneWidget);

    final source = tester.widget<Text>(
      find.text('body of newer/one.dart').first,
    );
    expect(source.textSpan?.style?.fontFamily, technicalFontFamily);
    expect(source.textSpan?.style?.fontFamilyFallback, technicalFontFallback);

    final path = tester.widget<Text>(find.text('newer/one.dart').first);
    expect(path.style?.fontFamily, technicalFontFamily);
    expect(path.style?.fontFamilyFallback, technicalFontFallback);

    expect(find.text('newer commit'), findsNothing);
    expect(find.byKey(const Key('nearby-column')), findsNothing);
  });
  // ------------------------------------------------------------------ G1/G2
  testWidgets('the narrow full diff composes the hunk workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    // The native window stops at 960, so this is the tightest the row gets.
    tester.view.physicalSize = const Size(960, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'commit')],
            files: (_, _) async => [
              const GitFileChange(
                path: 'lib/a.dart',
                status: 'M',
                additions: 1,
                deletions: 1,
              ),
            ],
            diff: (_, _, _, _, _) async => const [
              DiffLine(kind: DiffLineKind.header, text: 'diff --git a/x b/x'),
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
              DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
            ],
          ),
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib/a.dart'), findsWidgets);
    expect(find.text('diff 알고리즘'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm-value')),
        matching: find.text('Myers'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('unified-list')), findsOneWidget);
    expect(find.textContaining('change 1 of 1'), findsOneWidget);
    expect(find.text('diff --git a/x b/x'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  // ------------------------------------------------------------------ H1
  testWidgets('the diff pane selects across lines without losing the arrows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'commit')],
            files: (_, _) async => [
              for (final name in ['one', 'two'])
                GitFileChange(
                  path: 'lib/$name.dart',
                  status: 'M',
                  additions: 1,
                  deletions: 0,
                ),
            ],
            diff: (_, _, path, _, _) async => [
              const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1,2 @@'),
              DiffLine(
                kind: DiffLineKind.add,
                text: 'alpha $path',
                newNumber: 1,
              ),
              DiffLine(
                kind: DiffLineKind.add,
                text: 'beta $path',
                newNumber: 2,
              ),
            ],
          ),
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = find.text('alpha lib/one.dart');
    final second = find.text('beta lib/one.dart');
    final firstParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: first, matching: find.byType(RichText)),
    );
    final secondParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: second, matching: find.byType(RichText)),
    );

    Future<void> dragSelection(
      RenderParagraph startParagraph,
      int startOffset,
      RenderParagraph endParagraph,
      int endOffset,
    ) async {
      final start = startParagraph.localToGlobal(
        startParagraph.getOffsetForCaret(
              TextPosition(offset: startOffset),
              Rect.zero,
            ) +
            const Offset(1, 6),
      );
      final end = endParagraph.localToGlobal(
        endParagraph.getOffsetForCaret(
              TextPosition(offset: endOffset),
              Rect.zero,
            ) +
            const Offset(-1, 6),
      );
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragSelection(firstParagraph, 2, firstParagraph, 7);
    Actions.invoke(tester.element(first), CopySelectionTextIntent.copy);
    await tester.pump();
    expect(copied, ['pha l']);

    final selectionArea = find.ancestor(
      of: first,
      matching: find.byType(SelectionArea),
    );
    tester
        .state<SelectionAreaState>(selectionArea)
        .selectableRegion
        .clearSelection();
    await tester.pump();

    await dragSelection(
      firstParagraph,
      0,
      secondParagraph,
      'beta lib/one.dart'.length,
    );

    Actions.invoke(tester.element(first), CopySelectionTextIntent.copy);
    await tester.pump();
    expect(copied, ['pha l', 'alpha lib/one.dart\nbeta lib/one.dart']);

    // The Hunk card keeps selection local, and the global file shortcut still
    // drives the screen after copying the drag selection.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('alpha lib/two.dart'), findsOneWidget);
    expect(find.byKey(const Key('selected-file-lib/two.dart')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('alpha lib/one.dart'), findsOneWidget);
  });

  testWidgets('preview shortcuts scroll and distinguish identities', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'different identities'),
            commit(
              '2',
              'same identity',
              committer: const GitIdentity(
                name: 'Ada Author',
                email: 'ada@example.com',
              ),
            ),
          ],
          files: (_, _) async => [
            for (final name in ['one', 'two'])
              GitFileChange(
                path: 'lib/$name.dart',
                status: 'M',
                additions: 1,
                deletions: 0,
              ),
          ],
          diff: (_, _, path, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1,60 @@'),
            for (var index = 0; index < 60; index++)
              DiffLine(
                kind: DiffLineKind.add,
                text: '$path line $index',
                newNumber: index + 1,
              ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('preview-panel'));
    expect(
      find.descendant(
        of: preview,
        matching: find.text('파일 이동 ⌘↑/↓ · 화면 스크롤 ⇧⌘↑/↓'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('preview-hash')), findsNothing);
    final shortcut = tester.widget<Text>(
      find.text('파일 이동 ⌘↑/↓ · 화면 스크롤 ⇧⌘↑/↓'),
    );
    expect(shortcut.style?.fontFamily, technicalFontFamily);
    expect(shortcut.style?.fontFamilyFallback, technicalFontFallback);
    final author = find.byKey(const Key('preview-author'));
    final committer = find.byKey(const Key('preview-committer'));
    final authorAvatar = find.descendant(
      of: author,
      matching: find.byKey(const ValueKey('author-avatar-1')),
    );
    final committerAvatar = find.descendant(
      of: committer,
      matching: find.byKey(const ValueKey('committer-avatar-1')),
    );
    expect(
      find.descendant(of: author, matching: find.text('Ada Author')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: author, matching: find.text('Ada Author')),
          )
          .style
          ?.fontFamily,
      isNull,
    );
    expect(
      find.descendant(
        of: author,
        matching: find.text('Author · ada@example.com'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: author,
        matching: find.text(exactCommitTime(1700000000)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: committer, matching: find.text('Cam Committer')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: committer,
        matching: find.text('Committer · cam@example.com'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: committer,
        matching: find.text(exactCommitTime(1700000120)),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(authorAvatar).overlaps(tester.getRect(committerAvatar)),
      isFalse,
    );
    expect(find.text('Committer · Cam Committer'), findsNothing);

    final scrollable = tester
        .widget<NestedScrollView>(
          find.byKey(const Key('preview-content-scroll')),
        )
        .controller!
        .position;
    expect(scrollable.pixels, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    final beforeRepeat = scrollable.pixels;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    expect(
      scrollable.pixels,
      moreOrLessEquals(
        (beforeRepeat + scrollable.viewportDimension * 0.5).clamp(
          scrollable.minScrollExtent,
          scrollable.maxScrollExtent,
        ),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scrollable.pixels, greaterThan(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scrollable.pixels, 0);
    expect(find.byKey(const Key('preview-state-lib/one.dart')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-author')), findsOneWidget);
    expect(find.byKey(const Key('preview-committer')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-author')),
        matching: find.text('Author · ada@example.com'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('preview omits an empty identity email', (tester) async {
    const identity = GitIdentity(name: 'Ada Author', email: '   ');
    final blankEmailCommit = GitCommit(
      sha: 'blank-email',
      shortSha: 'blank',
      parents: const [],
      author: identity,
      authorTimestamp: 1700000000,
      committer: identity,
      committerTimestamp: 1700000120,
      refs: const [],
      subject: 'blank email',
    );
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => [blankEmailCommit]), controller),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final author = find.byKey(const Key('preview-author'));
    expect(
      find.descendant(of: author, matching: find.text('Author')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: author, matching: find.textContaining('Author ·')),
      findsNothing,
    );
  });

  // ------------------------------------------------------------------ H3
  testWidgets('meta arrows walk the open preview through its files', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
          ],
          files: (_, _) async => [
            for (final name in ['one', 'two', 'three'])
              GitFileChange(
                path: 'lib/$name.dart',
                status: 'M',
                additions: 1,
                deletions: 0,
              ),
          ],
          diff: (_, _, path, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1 @@'),
            DiffLine(
              kind: DiffLineKind.add,
              text: 'body of $path',
              newNumber: 1,
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    Future<void> metaArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    // Closed panel: the combination has nothing to walk and changes nothing.
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
    await metaArrow(LogicalKeyboardKey.arrowDown);
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-diff')), findsNothing);

    // Down walks the files, up walks back, and both ends clamp.
    await metaArrow(LogicalKeyboardKey.arrowDown);
    final diff = find.byKey(const Key('preview-diff'));
    expect(
      find.descendant(of: diff, matching: find.text('body of lib/two.dart')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<NestedScrollView>(
            find.byKey(const Key('preview-content-scroll')),
          )
          .controller
          ?.offset,
      0,
    );
    expect(find.byKey(const Key('preview-state-lib/two.dart')), findsOneWidget);
    await metaArrow(LogicalKeyboardKey.arrowDown);
    await metaArrow(LogicalKeyboardKey.arrowDown);
    expect(
      find.descendant(of: diff, matching: find.text('body of lib/three.dart')),
      findsOneWidget,
    );
    await metaArrow(LogicalKeyboardKey.arrowUp);
    expect(
      find.descendant(of: diff, matching: find.text('body of lib/two.dart')),
      findsOneWidget,
    );
    await metaArrow(LogicalKeyboardKey.arrowUp);
    await metaArrow(LogicalKeyboardKey.arrowUp);
    expect(
      find.descendant(of: diff, matching: find.text('body of lib/one.dart')),
      findsOneWidget,
    );
    // The commit selection never moved while walking files.
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    // Bare arrows still move the commit selection, with its own first file.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
  });

  testWidgets('preview keyboard file walking keeps the selected row visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'many changed files')],
          files: (_, _) async => [
            for (var index = 0; index < 20; index++)
              GitFileChange(
                path: 'lib/file$index.dart',
                status: 'M',
                additions: 1,
                deletions: 0,
              ),
          ],
          diff: (_, _, path, _, _) async => [
            const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1 @@'),
            DiffLine(
              kind: DiffLineKind.add,
              text: 'body of $path',
              newNumber: 1,
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final filesViewport = find.byKey(const Key('preview-content-scroll'));
    final filesPosition = tester
        .widget<NestedScrollView>(filesViewport)
        .controller!
        .position;

    Future<void> metaArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    Finder fileRow(String path) => find.ancestor(
      of: find.byKey(Key('preview-state-$path')),
      matching: find.byType(InkWell),
    );

    void expectRowVisible(String path) {
      final viewportRect = tester.getRect(filesViewport);
      final rowRect = tester.getRect(fileRow(path));
      expect(rowRect.top, greaterThanOrEqualTo(viewportRect.top - 0.5));
      expect(rowRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 0.5));
    }

    for (var index = 0; index < 15; index++) {
      await metaArrow(LogicalKeyboardKey.arrowDown);
    }
    expect(filesPosition.pixels, greaterThan(0));
    expectRowVisible('lib/file15.dart');

    final downOffset = filesPosition.pixels;
    await metaArrow(LogicalKeyboardKey.arrowUp);
    expect(filesPosition.pixels, moreOrLessEquals(downOffset));
    expectRowVisible('lib/file14.dart');

    for (var index = 0; index < 14; index++) {
      await metaArrow(LogicalKeyboardKey.arrowUp);
    }
    expect(filesPosition.pixels, lessThan(downOffset));
    expectRowVisible('lib/file0.dart');

    final pointerOffset = filesPosition.pixels;
    await tester.tap(find.byKey(const Key('preview-state-lib/file1.dart')));
    await tester.pumpAndSettle();
    expect(filesPosition.pixels, moreOrLessEquals(pointerOffset));
    await tester.drag(filesViewport, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('body of lib/file1.dart'), findsOneWidget);
  });

  // ------------------------------------------------------------------ J2
  test('the window controls speak to the native window', () async {
    final calls = <String>[];
    const channel = MethodChannel('test/yogit-window-controls');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final frame = WindowFrameController(channel: channel);

    await frame.closeWindow();
    await frame.minimizeWindow();
    await frame.toggleZoom();
    await frame.startDrag();
    expect(calls, ['closeWindow', 'minimizeWindow', 'toggleZoom', 'startDrag']);

    // No native side, no crash.
    final orphan = WindowFrameController(
      channel: const MethodChannel('test/yogit-window-none'),
    );
    await orphan.closeWindow();
    await orphan.startDrag();
  });

  test('the native window hides its own chrome and answers the toolbar', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    for (final line in [
      'titlebarAppearsTransparent = true',
      'titleVisibility = .hidden',
      'styleMask.insert(.fullSizeContentView)',
      'standardWindowButton(button)?.isHidden = true',
      'case "closeWindow":',
      'case "minimizeWindow":',
      'case "toggleZoom":',
      'case "startDrag":',
      'performDrag(with: event)',
    ]) {
      expect(source, contains(line), reason: line);
    }
    // The window keeps its own handles: resizing and the menu bar still work.
    expect(source, isNot(contains('styleMask.remove(.resizable)')));
    expect(source, contains('case "setPreview":'));
    expect(source, contains('case "pickRepository":'));
  });

  testWidgets('the toolbar drags the window and keeps its buttons tappable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('test/yogit-window'), (
          call,
        ) async {
          calls.add(call.method);
          return null;
        });
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Three lights, in macOS order, at the left edge.
    final close = tester.getRect(find.byKey(const Key('window-close')));
    final minimize = tester.getRect(find.byKey(const Key('window-minimize')));
    final zoom = tester.getRect(find.byKey(const Key('window-zoom')));
    expect(close.width, 12);
    expect(close.right, lessThan(minimize.left));
    expect(minimize.right, lessThan(zoom.left));
    expect(zoom.right, lessThan(tester.getRect(find.text('.')).left));

    calls.clear();
    await tester.tap(find.byKey(const Key('window-close')));
    await tester.tap(find.byKey(const Key('window-minimize')));
    await tester.tap(find.byKey(const Key('window-zoom')));
    await tester.pumpAndSettle();
    expect(calls, ['closeWindow', 'minimizeWindow', 'toggleZoom']);

    // Dragging the bar moves the window; double-tapping zooms it.
    calls.clear();
    await tester.drag(
      find.byKey(const Key('toolbar-drag')),
      const Offset(40, 10),
    );
    await tester.pumpAndSettle();
    expect(calls, ['startDrag']);
    calls.clear();
    await tester.tap(find.byKey(const Key('toolbar-drag')));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.byKey(const Key('toolbar-drag')));
    await tester.pumpAndSettle();
    expect(calls, ['toggleZoom']);

    // The controls on top of the drag region still take their own taps.
    calls.clear();
    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
    await tester.tap(find.byKey(const Key('toolbar-full-diff')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
    expect(find.byKey(const Key('changed-files-list')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('repository-selector')))
          .onTap,
      isNotNull,
    );
  });

  // ------------------------------------------------------------------ J3
  testWidgets('the Yogit wordmark sits centered in the toolbar', (
    tester,
  ) async {
    const root = '/Users/ada/repos/yogit-480bbcc5-8064-43d5-976e-5e5ec891eba5';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1660, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: root,
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final mark = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('wordmark')),
        matching: find.byType(Text),
      ),
    );
    expect(mark.style?.fontFamily, 'DancingScript');
    expect(mark.style?.fontSize, 26);
    expect(mark.style?.fontWeight, FontWeight.w700);
    // One pastel per letter, in order.
    final spans = (mark.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['Y', 'o', 'g', 'i', 't']);
    expect(spans.map((span) => span.style?.color), const [
      Color(0xFFFFB3BA),
      Color(0xFFFFDFBA),
      Color(0xFFFFFFB3),
      Color(0xFFBAFFC9),
      Color(0xFFBAE1FF),
    ]);
    // The cloud badge floats beside the Y, inside the same IgnorePointer.
    final cloud = find.byKey(const Key('wordmark-cloud'));
    expect(
      find.descendant(of: find.byKey(const Key('wordmark')), matching: cloud),
      findsOneWidget,
    );
    final badge = tester.getRect(cloud);
    final glyphs = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('wordmark')),
        matching: find.byType(Text),
      ),
    );
    // Beside the Y, inside the text's own box, high above its middle.
    expect(badge.left, greaterThan(glyphs.left));
    expect(badge.right, lessThan(glyphs.right));
    expect(badge.top, lessThan(glyphs.center.dy));
    // Sized off the font, so the 20px variant stays proportional.
    expect(
      tester.widget<CustomPaint>(cloud).size.width,
      closeTo(26 * 0.92, 0.1),
    );

    // It never eats a pointer.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.byKey(const Key('wordmark')),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((box) => box.ignoring),
      isTrue,
    );
    // Nothing may run under it: the path ellipsizes before the wordmark, and the
    // right cluster starts after it.
    final slot = tester.getRect(find.byKey(const Key('wordmark')));
    expect(
      tester
          .getRect(find.text('yogit-480bbcc5-8064-43d5-976e-5e5ec891eba5'))
          .right,
      lessThanOrEqualTo(slot.left - 8),
    );
    expect(
      tester.getRect(find.byKey(const Key('preview-placement'))).left,
      greaterThanOrEqualTo(slot.right + 8),
    );
    // The drag handle keeps a usable stretch of bar.
    expect(
      tester.getRect(find.byKey(const Key('toolbar-drag'))).width,
      greaterThanOrEqualTo(200),
    );

    // The user's own window size: still there, still clear of both sides.
    tester.view.physicalSize = const Size(1548, 800);
    await tester.pumpAndSettle();
    final narrow = tester.getRect(find.byKey(const Key('wordmark')));
    final path = tester.getRect(find.byKey(const Key('toolbar-drag')));
    expect(path.width, greaterThanOrEqualTo(200));
    expect(
      tester
          .getRect(find.text('yogit-480bbcc5-8064-43d5-976e-5e5ec891eba5'))
          .right,
      lessThanOrEqualTo(narrow.left - 8),
    );
    expect(
      narrow.right + 8,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('shortcut-hint'))).left,
      ),
    );

    // Too narrow for even the small size: the wordmark goes, the path stays, and
    // rendering at all is the no-overflow assertion.
    tester.view.physicalSize = const Size(960, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wordmark')), findsNothing);
    expect(find.byKey(const Key('toolbar-drag')), findsOneWidget);
  });
}

/// Points along [path], for probing where a rail actually runs.
List<Offset> _samples(Path path) => path
    .computeMetrics()
    .expand(
      (metric) => [
        for (var step = 0; step <= 400; step++)
          metric.getTangentForOffset(metric.length * step / 400)!.position,
      ],
    )
    .toList();

/// Whether [path] passes within a hair of [point].
bool _touches(Path path, Offset point) =>
    _samples(path).any((sample) => (sample - point).distance < 0.5);

Widget app(
  GitRepository repository,
  WindowFrameController controller, {
  BranchPreviewMode branchPreviewMode = BranchPreviewMode.merge,
  ValueChanged<BranchPreviewMode>? onBranchPreviewModeChanged,
  VoidCallback? onOpenSettings,
  List<CommitProfile> commitProfiles = const [],
  String mergeMessageTemplate = AppSettings.defaultMergeMessageTemplate,
  String rebaseMergeMessageTemplate = AppSettings.defaultMergeMessageTemplate,
}) => MaterialApp(
  home: TimelineScreen(
    repository: repository,
    controller: controller,
    branchPreviewMode: branchPreviewMode,
    onBranchPreviewModeChanged: onBranchPreviewModeChanged,
    onOpenSettings: onOpenSettings,
    commitProfiles: commitProfiles,
    mergeMessageTemplate: mergeMessageTemplate,
    rebaseMergeMessageTemplate: rebaseMergeMessageTemplate,
  ),
);

class FakeGitRepository extends GitRepository {
  FakeGitRepository(
    this.loader, {
    this.files,
    this.diff,
    this.content,
    this.blame,
    this.history,
    this.workingTree,
    this.refs = const RepoRefs(local: ['main'], current: 'main'),
    this.gitDiffAlgorithmSetting = const GitDiffAlgorithmSetting.gitDefault(),
    this.refsLoader,
    this.fetchRemoteCallback,
    this.originUrlCallback,
    this.compareBranchesCallback,
    this.simulateRebaseCallback,
    this.openMergePreviewCallback,
    this.openRebasePreviewCallback,
    this.applyMergePreviewCallback,
    this.applyRebasePreviewCallback,
    this.applyRebaseThenMergeCallback,
    this.recommendationCallback,
    this.restoreBranchApplyCallback,
    this.operationInProgressCallback,
    this.filesBetween,
    this.diffBetween,
    this.loadCherryPickStateCallback,
    this.cherryPickCallback,
    this.continueCherryPickCallback,
    this.abortCherryPickCallback,
    this.stageResolvedFileCallback,
    this.commitMessage,
    this.deletedBranchNameCallback,
    String root = '.',
    CommandRunner runner = runProcess,
  }) : super(root, runner: runner);

  final RepoRefs refs;
  final GitDiffAlgorithmSetting gitDiffAlgorithmSetting;
  final Future<RepoRefs> Function()? refsLoader;
  final Future<FetchOriginResult> Function(String remote)? fetchRemoteCallback;
  final Future<String?> Function()? originUrlCallback;
  final Future<BranchComparisonResult> Function(String base, String compare)?
  compareBranchesCallback;
  final Future<RebaseCheckResult> Function({
    required String baseRef,
    required String compareRef,
  })?
  simulateRebaseCallback;
  final Future<MergePreviewSession> Function({
    required String baseRef,
    required String compareRef,
  })?
  openMergePreviewCallback;
  final Future<RebasePreviewSession> Function({
    required String baseRef,
    required String compareRef,
  })?
  openRebasePreviewCallback;
  final Future<BranchApplyResult> Function({
    required BranchComparisonResult comparison,
    required String treeSha,
  })?
  applyMergePreviewCallback;
  final Future<BranchApplyResult> Function({
    required BranchComparisonResult comparison,
    required String virtualTip,
  })?
  applyRebasePreviewCallback;
  final Future<BranchApplyResult> Function({
    required BranchComparisonResult comparison,
    required String virtualTip,
  })?
  applyRebaseThenMergeCallback;

  /// Recommendations stay off unless a test asks for one: the engine would
  /// otherwise measure whatever repository the test happens to run in.
  final Future<BranchRecommendation?> Function(
    BranchComparisonResult comparison,
    RebaseCheckResult? rebaseCheck,
  )?
  recommendationCallback;
  final Future<void> Function(BranchApplyResult result)?
  restoreBranchApplyCallback;
  final Future<bool> Function()? operationInProgressCallback;
  final Future<List<GitFileChange>> Function(String from, String to)?
  filesBetween;
  final Future<List<DiffLine>> Function(
    String from,
    String to,
    GitFileChange file,
  )?
  diffBetween;
  final Future<CherryPickState?> Function()? loadCherryPickStateCallback;
  final Future<CherryPickResult> Function(String sha)? cherryPickCallback;
  final Future<CherryPickResult> Function()? continueCherryPickCallback;
  final Future<void> Function()? abortCherryPickCallback;
  final Future<void> Function(String path)? stageResolvedFileCallback;
  final Future<String> Function(String sha)? commitMessage;
  final Future<String?> Function(String tipSha, Iterable<GitCommit> commits)?
  deletedBranchNameCallback;
  final Future<List<GitCommit>> Function(int skip, int limit) loader;
  final Future<GitCommit?> Function()? workingTree;
  final Future<List<GitFileChange>> Function(GitCommit commit, String? parent)?
  files;
  final Future<List<DiffLine>> Function(
    GitCommit commit,
    String? parent,
    String path,
    DiffAlgorithm algorithm,
    bool ignoreWhitespace,
  )?
  diff;
  final Future<Uint8List> Function(
    GitCommit commit,
    GitFileChange file,
    String? parent,
  )?
  content;
  final Future<List<GitBlameLine>> Function(
    GitCommit commit,
    GitFileChange file,
    String? parent,
    Uint8List? workingTreeBytes,
  )?
  blame;
  final Future<List<GitFileHistoryRecord>> Function(
    GitCommit commit,
    GitFileChange file,
  )?
  history;

  @override
  Future<List<GitCommit>> loadHistory({int limit = 500, int skip = 0}) =>
      loader(skip, limit);

  @override
  Future<String?> loadOriginUrl() =>
      originUrlCallback?.call() ?? super.loadOriginUrl();

  @override
  Future<String?> loadLocalDeletedBranchName(
    String tipSha,
    Iterable<GitCommit> commits,
  ) => deletedBranchNameCallback?.call(tipSha, commits) ?? Future.value(null);

  @override
  Future<String> loadCommitMessage(String sha) =>
      commitMessage?.call(sha) ?? Future.value(sha);

  @override
  Future<RepoRefs> loadRefs() =>
      refsLoader?.call() ?? Future<RepoRefs>.value(refs);

  @override
  Future<FetchOriginResult> fetchRemote(String remote) =>
      fetchRemoteCallback?.call(remote) ??
      Future.value(FetchOriginResult.noOrigin);

  @override
  Future<BranchComparisonResult> compareBranches(
    String baseRef,
    String compareRef,
  ) =>
      compareBranchesCallback?.call(baseRef, compareRef) ??
      super.compareBranches(baseRef, compareRef);

  @override
  Future<RebaseCheckResult> simulateRebase({
    required String baseRef,
    required String compareRef,
  }) =>
      simulateRebaseCallback?.call(baseRef: baseRef, compareRef: compareRef) ??
      super.simulateRebase(baseRef: baseRef, compareRef: compareRef);

  @override
  Future<RebasePreviewSession> openRebasePreview({
    required String baseRef,
    required String compareRef,
  }) async {
    if (openRebasePreviewCallback != null) {
      return openRebasePreviewCallback!(
        baseRef: baseRef,
        compareRef: compareRef,
      );
    }
    if (simulateRebaseCallback != null) {
      final check = await simulateRebaseCallback!(
        baseRef: baseRef,
        compareRef: compareRef,
      );
      return FakeRebasePreviewSession(
        this,
        RebasePreviewResult(
          status: switch (check.status) {
            RebaseCheckStatus.clean => RebasePreviewStatus.clean,
            RebaseCheckStatus.conflicts => RebasePreviewStatus.conflict,
            RebaseCheckStatus.failed => RebasePreviewStatus.failed,
          },
          baseTip: refs.localTips[baseRef] ?? refs.tips[baseRef] ?? baseRef,
          compareTip:
              refs.localTips[compareRef] ?? refs.tips[compareRef] ?? compareRef,
          conflictFiles: check.files,
          error: check.error,
        ),
      );
    }
    return super.openRebasePreview(baseRef: baseRef, compareRef: compareRef);
  }

  @override
  Future<MergePreviewSession> openMergePreview({
    required String baseRef,
    required String compareRef,
  }) async {
    if (openMergePreviewCallback != null) {
      return openMergePreviewCallback!(
        baseRef: baseRef,
        compareRef: compareRef,
      );
    }
    final comparison = await compareBranchesCallback!(baseRef, compareRef);
    final result = MergePreviewResult(
      status: switch (comparison.merge.status) {
        MergeConflictStatus.clean => MergePreviewStatus.clean,
        MergeConflictStatus.conflicts => MergePreviewStatus.conflict,
        MergeConflictStatus.failed => MergePreviewStatus.failed,
      },
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      treeSha: comparison.merge.treeSha,
      resultFiles: comparison.merge.resultFiles,
      conflictFiles: comparison.merge.files,
      error: comparison.merge.error,
    );
    return FakeMergePreviewSession(this, result, finishResult: result);
  }

  /// The commit message the last apply was handed, so a test can assert what
  /// the message dialog passed through.
  String? appliedMessage;

  @override
  Future<BranchApplyResult> applyMergePreview({
    required BranchComparisonResult comparison,
    required String treeSha,
    String? message,
  }) {
    appliedMessage = message;
    return applyMergePreviewCallback?.call(
          comparison: comparison,
          treeSha: treeSha,
        ) ??
        super.applyMergePreview(
          comparison: comparison,
          treeSha: treeSha,
          message: message,
        );
  }

  @override
  Future<BranchApplyResult> applyRebasePreview({
    required BranchComparisonResult comparison,
    required String virtualTip,
  }) =>
      applyRebasePreviewCallback?.call(
        comparison: comparison,
        virtualTip: virtualTip,
      ) ??
      super.applyRebasePreview(comparison: comparison, virtualTip: virtualTip);

  @override
  Future<BranchApplyResult> applyRebaseThenMerge({
    required BranchComparisonResult comparison,
    required String virtualTip,
    String? message,
  }) {
    appliedMessage = message;
    return applyRebaseThenMergeCallback?.call(
          comparison: comparison,
          virtualTip: virtualTip,
        ) ??
        super.applyRebaseThenMerge(
          comparison: comparison,
          virtualTip: virtualTip,
          message: message,
        );
  }

  @override
  Future<BranchRecommendation?> recommendBranchIntegration({
    required BranchComparisonResult comparison,
    RebaseCheckResult? rebaseCheck,
  }) =>
      recommendationCallback?.call(comparison, rebaseCheck) ??
      Future.value(null);

  @override
  Future<void> restoreBranchApply(BranchApplyResult result) =>
      restoreBranchApplyCallback?.call(result) ??
      super.restoreBranchApply(result);

  @override
  Future<bool> operationInProgress() async =>
      await operationInProgressCallback?.call() ?? false;

  @override
  Future<void> cleanupStalePreviewWorktrees() async {}

  @override
  Future<CherryPickState?> loadCherryPickState() =>
      loadCherryPickStateCallback?.call() ?? Future.value();

  @override
  Future<CherryPickResult> cherryPick(String sha) =>
      cherryPickCallback?.call(sha) ?? super.cherryPick(sha);

  @override
  Future<CherryPickResult> continueCherryPick() =>
      continueCherryPickCallback?.call() ?? super.continueCherryPick();

  @override
  Future<void> abortCherryPick() =>
      abortCherryPickCallback?.call() ?? Future.value();

  @override
  Future<void> stageResolvedFile(String relativePath) =>
      stageResolvedFileCallback?.call(relativePath) ??
      super.stageResolvedFile(relativePath);

  @override
  Future<List<DiffLine>> loadDiffBetween(
    String fromRef,
    String toRef,
    GitFileChange file, {
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
    DiffScope scope = DiffScope.hunks,
  }) =>
      diffBetween?.call(fromRef, toRef, file) ??
      super.loadDiffBetween(
        fromRef,
        toRef,
        file,
        algorithm: algorithm,
        ignoreWhitespace: ignoreWhitespace,
        scope: scope,
      );

  @override
  Future<List<GitFileChange>> loadFilesBetween(String fromRef, String toRef) =>
      filesBetween?.call(fromRef, toRef) ??
      super.loadFilesBetween(fromRef, toRef);

  @override
  Future<GitCommit?> loadWorkingTree() =>
      workingTree?.call() ?? Future.value(null);

  @override
  Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting() =>
      Future.value(gitDiffAlgorithmSetting);

  @override
  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent}) =>
      files?.call(commit, parent) ?? Future.value(const []);

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
    DiffScope scope = DiffScope.hunks,
  }) =>
      diff?.call(commit, parent, file.path, algorithm, ignoreWhitespace) ??
      Future.value(const []);

  @override
  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  ) => history?.call(commit, file) ?? Future.value(const []);

  @override
  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  }) => content?.call(commit, file, parent) ?? Future.value(Uint8List(0));

  @override
  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  }) =>
      blame?.call(commit, file, parent, workingTreeBytes) ??
      Future.value(const []);
}

class FakeMergePreviewSession extends MergePreviewSession {
  FakeMergePreviewSession(
    GitRepository repository,
    this.result, {
    required this.finishResult,
    this.conflictDiff = const [],
  }) : super(
         repository: repository,
         baseTip: result.baseTip,
         compareTip: result.compareTip,
       );

  final MergePreviewResult result;
  final MergePreviewResult finishResult;
  final List<DiffLine> conflictDiff;
  final resolvedChoices = <(String, MergeConflictChoice)>[];
  var disposed = false;

  @override
  Future<MergePreviewResult> start() async => result;

  @override
  Future<void> resolveFile(
    String relativePath,
    MergeConflictChoice choice,
  ) async {
    resolvedChoices.add((relativePath, choice));
  }

  @override
  Future<void> markResolved(String relativePath) async {}

  @override
  Future<List<DiffLine>> loadConflictDiff(String relativePath) async =>
      conflictDiff;

  @override
  Future<MergePreviewResult> finish() async => finishResult;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeRebasePreviewSession extends RebasePreviewSession {
  FakeRebasePreviewSession(
    GitRepository repository,
    this.result, {
    List<RebasePreviewResult> continuations = const [],
    this.conflictDiff = const [],
  }) : _continuations = List.of(continuations),
       super(
         repository: repository,
         baseTip: result.baseTip,
         compareTip: result.compareTip,
         originalCommits: const [],
       );

  final RebasePreviewResult result;
  final List<RebasePreviewResult> _continuations;
  final List<DiffLine> conflictDiff;
  final resolvedChoices = <(String, RebaseConflictChoice)>[];
  var disposed = false;

  @override
  Future<RebasePreviewResult> start() async => result;

  @override
  Future<void> resolveFile(
    String relativePath,
    RebaseConflictChoice choice,
  ) async {
    resolvedChoices.add((relativePath, choice));
  }

  @override
  Future<void> markResolved(String relativePath) async {}

  @override
  Future<List<DiffLine>> loadConflictDiff(String relativePath) async =>
      conflictDiff;

  @override
  Future<RebasePreviewResult> continueAfterResolving() async =>
      _continuations.removeAt(0);

  @override
  Future<void> dispose() async => disposed = true;
}

class DelayedSettingsStore extends SettingsStore {
  DelayedSettingsStore(this.settings) : super(File('/tmp/yogit-unused.json'));

  final Future<AppSettings> settings;
  var saveCount = 0;

  @override
  Future<AppSettings> load() => settings;

  @override
  Future<void> save(AppSettings settings) async => saveCount++;
}

class MemorySettingsStore extends SettingsStore {
  MemorySettingsStore() : super(File('/tmp/yogit-unused.json'));

  AppSettings current = const AppSettings();

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async => current = settings;
}

class FailingSettingsStore extends MemorySettingsStore {
  @override
  Future<void> save(AppSettings settings) async {
    throw const FileSystemException('settings write failed');
  }
}

class DelayedMemorySettingsStore extends MemorySettingsStore {
  final _load = Completer<AppSettings>();
  var _loadCompleted = false;
  var saveCount = 0;

  void completeLoad() {
    _loadCompleted = true;
    _load.complete(current);
  }

  @override
  Future<AppSettings> load() =>
      _loadCompleted ? Future<AppSettings>.value(current) : _load.future;

  @override
  Future<void> save(AppSettings settings) async {
    saveCount++;
    await super.save(settings);
  }
}

/// A row built for the painter directly: it reads lanes and [transitions], so
/// these tests stay independent of how layoutGraph assigns them.
GraphRow graphRow({
  required GitCommit commit,
  required int lane,
  List<int> activeLanes = const [],
  List<int> nextLanes = const [],
  Map<int, String> activeLaneShas = const {},
  Map<int, String> nextLaneShas = const {},
  List<LaneTransition> transitions = const [],
  List<int> parentLanes = const [],
  int branch = 0,
  Map<int, int> activeLaneBranches = const {},
  Map<int, int> nextLaneBranches = const {},
}) => GraphRow(
  commit: commit,
  lane: lane,
  parentLanes: parentLanes,
  activeLanes: activeLanes,
  nextLanes: nextLanes,
  activeLaneShas: activeLaneShas,
  nextLaneShas: nextLaneShas,
  transitions: transitions,
  branch: branch,
  activeLaneBranches: activeLaneBranches,
  nextLaneBranches: nextLaneBranches,
);

GitCommit workingTreeCommit(String head) => GitCommit(
  sha: '',
  shortSha: '',
  parents: [head],
  author: const GitIdentity(name: '', email: ''),
  authorTimestamp: 0,
  committer: const GitIdentity(name: '', email: ''),
  committerTimestamp: 0,
  refs: const [],
  subject: 'Uncommitted changes',
);

GitCommit commit(
  String sha,
  String subject, {
  List<String> parents = const [],
  List<GitRef>? refs,
  int timestamp = 1700000120,
  GitIdentity committer = const GitIdentity(
    name: 'Cam Committer',
    email: 'cam@example.com',
  ),
}) => GitCommit(
  sha: sha,
  shortSha: sha,
  parents: parents,
  author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
  authorTimestamp: 1700000000,
  committer: committer,
  committerTimestamp: timestamp,
  refs:
      refs ??
      (sha == '3' ? const [GitRef(name: 'main', isHead: true)] : const []),
  subject: subject,
);

BranchComparisonResult branchComparison({
  String compareRef = 'feature',
  String compareTip = 'feature-tip',
  String baseSubject = 'main only',
  String compareSubject = 'feature only',
  MergeConflictCheck merge = const MergeConflictCheck(
    status: MergeConflictStatus.clean,
  ),
}) => BranchComparisonResult(
  baseRef: 'main',
  compareRef: compareRef,
  baseTip: 'main-tip',
  compareTip: compareTip,
  baseParent: 'root',
  compareParent: 'root',
  mergeBases: const ['root'],
  commits: [
    BranchComparisonCommit(
      commit: commit('main-tip', baseSubject, parents: const ['root']),
      side: BranchCommitSide.baseOnly,
    ),
    BranchComparisonCommit(
      commit: commit(compareTip, compareSubject, parents: const ['root']),
      side: BranchCommitSide.compareOnly,
    ),
    BranchComparisonCommit(
      commit: commit('root', 'shared commit'),
      side: BranchCommitSide.commonBoundary,
    ),
  ],
  files: const [
    GitFileChange(
      path: 'lib/shared.dart',
      status: 'M',
      additions: 1,
      deletions: 1,
    ),
  ],
  merge: merge,
);

void _commitProfileTests() {
  const profiles = [
    CommitProfile(
      label: '회사',
      name: '채수원',
      email: 'sw.chae@navercorp.com',
      color: '#7C5CD6',
    ),
    CommitProfile(
      label: '개인',
      name: 'doortts',
      email: 'doortts@gmail.com',
      color: '#2EA043',
    ),
  ];

  /// A repository whose config reports [name]/[email] and records writes.
  FakeGitRepository profileRepository({
    required String name,
    required String email,
    List<List<String>>? calls,
  }) => FakeGitRepository(
    (_, _) async => [commit('1', 'first commit')],
    runner: (executable, arguments, {workingDirectory, environment}) async {
      calls?.add(arguments);
      if (arguments.length >= 3 && arguments.first == 'config') {
        final key = arguments.last;
        return ProcessResult(
          1,
          0,
          key == 'user.name'
              ? '$name\n'
              : key == 'user.email'
              ? '$email\n'
              : '',
          '',
        );
      }
      return ProcessResult(1, 0, '', '');
    },
  );

  Widget profileApp(
    GitRepository repository,
    WindowFrameController controller, {
    List<CommitProfile> registered = profiles,
    ValueChanged<List<CommitProfile>>? onChanged,
  }) => MaterialApp(
    home: TimelineScreen(
      repository: repository,
      controller: controller,
      commitProfiles: registered,
      onCommitProfilesChanged: onChanged,
    ),
  );

  testWidgets('the status bar names the matching profile', (tester) async {
    // Wide enough that the chip keeps the address beside the label.
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      profileApp(
        profileRepository(name: '채수원', email: 'sw.chae@navercorp.com'),
        WindowFrameController(),
      ),
    );
    await tester.pumpAndSettle();

    final chip = find.byKey(const Key('commit-profile-chip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('회사')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chip, matching: find.text('sw.chae@navercorp.com')),
      findsOneWidget,
    );
    // A known profile carries no warning dot.
    expect(find.byKey(const Key('commit-profile-warning')), findsNothing);
  });

  testWidgets('an identity set outside the app warns and can be saved', (
    tester,
  ) async {
    List<CommitProfile>? saved;
    await tester.pumpWidget(
      profileApp(
        profileRepository(name: 'Suwon Chae', email: 'other@company.com'),
        WindowFrameController(),
        onChanged: (value) => saved = value,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commit-profile-warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('commit-profile-chip')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('commit-profile-current-custom')),
      findsOneWidget,
    );
    expect(find.text('커스텀 (앱 밖에서 설정됨)'), findsOneWidget);
    expect(find.textContaining('.git/config에 저장'), findsOneWidget);

    await tester.tap(find.byKey(const Key('commit-profile-register')));
    await tester.pumpAndSettle();

    expect(saved?.length, 3);
    expect(saved?.last.email, 'other@company.com');
  });

  testWidgets('picking a profile writes the repository config', (tester) async {
    final calls = <List<String>>[];
    await tester.pumpWidget(
      profileApp(
        profileRepository(
          name: '채수원',
          email: 'sw.chae@navercorp.com',
          calls: calls,
        ),
        WindowFrameController(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('commit-profile-chip')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('commit-profile-option-doortts@gmail.com')),
    );
    await tester.pumpAndSettle();

    // Joined so the matcher compares contents rather than list identity.
    final joined = [for (final call in calls) call.join(' ')];
    expect(joined, contains('config --local user.name doortts'));
    expect(joined, contains('config --local user.email doortts@gmail.com'));
  });
}
