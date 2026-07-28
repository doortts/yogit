# Timeline Theme Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `System Graphite` the default timeline appearance and let users choose and persist `Warm Graphite` or `Carbon` from `Settings > Appearance`.

**Architecture:** Add an immutable `ThemeExtension` dedicated to the timeline and preview so the three palettes remain local to the basic screen. Store only a stable theme identifier in `AppSettings`; `YogitApp` applies the selected extension around `TimelineScreen`, while Full Diff and Settings keep their existing themes.

**Tech Stack:** Flutter 3.41.8+, Dart, Material `ThemeExtension`, JSON settings storage, `flutter_test`

## Global Constraints

- `System Graphite` is the default for new, existing, missing, and invalid settings.
- Persist exactly `systemGraphite`, `warmGraphite`, or `carbon`.
- Apply the selected palette only to the basic timeline screen, its menus, and its attached preview.
- Do not change Full Diff or the Settings screen's own fixed palette.
- Keep syntax, additions, deletions, file states, branch lanes, macOS window buttons, and the Yogit wordmark semantic colors unchanged.
- Keep layout, sizing, animation, scrolling, selection, and keyboard behavior unchanged.
- Do not add a package dependency or an app-wide light theme.
- Preserve minimum text contrast: System Graphite 7.69:1, Warm Graphite 7.88:1, Carbon 9.48:1 for the lowest approved text/background pair.
- Follow the approved design in `docs/superpowers/specs/2026-07-28-timeline-theme-selection-design.md`.
- Implement on `codex/timeline-theme-selection` in the ignored
  `.worktrees/timeline-theme-selection` worktree, then merge the verified branch
  into `main`.

---

## File Structure

- Create `lib/timeline_theme.dart`: theme identifiers, approved palettes, `ThemeExtension`, context lookup, and timeline-local `ThemeData`.
- Create `test/timeline_theme_test.dart`: palette values, lookup fallback, interpolation, and local Material theme behavior.
- Modify `lib/settings.dart`: persist `timelineTheme` and add the `Appearance` settings section and cards.
- Modify `lib/main.dart`: wrap only `TimelineScreen` in the selected timeline theme.
- Modify `lib/timeline.dart`: replace the nine navy surface constants with semantic palette reads and pass colors into painters and pure helpers.
- Modify `test/app_test.dart`: settings JSON, Appearance interaction, timeline state preservation, stored theme application, and Full Diff isolation.

### Task 0: Create the isolated implementation branch

**Files:**
- No tracked file changes.

**Interfaces:**
- Produces branch: `codex/timeline-theme-selection`
- Produces worktree: `.worktrees/timeline-theme-selection`

- [ ] **Step 1: Load the worktree safety instructions**

Use `superpowers:using-git-worktrees` before creating the worktree.

- [ ] **Step 2: Confirm the worktree directory is ignored**

Run: `git check-ignore -q .worktrees`

Expected: exit status 0.

- [ ] **Step 3: Create the implementation worktree and branch**

Run:

```bash
git worktree add \
  .worktrees/timeline-theme-selection \
  -b codex/timeline-theme-selection \
  main
```

Expected: the branch starts from the approved design and implementation-plan
commits on `main`.

- [ ] **Step 4: Establish a clean baseline**

From `.worktrees/timeline-theme-selection`, run:

```bash
flutter pub get
flutter test test/app_test.dart --plain-name \
  'keyboard and pointer control selection and preview'
```

Expected: PASS. If the baseline fails, stop and report it before changing
product code.

### Task 1: Define the three immutable timeline palettes

**Files:**
- Create: `lib/timeline_theme.dart`
- Create: `test/timeline_theme_test.dart`

**Interfaces:**
- Produces: `enum TimelineThemeKind`
- Produces: `TimelineThemeKind.parse(Object? value) -> TimelineThemeKind`
- Produces: `TimelineThemeKind.palette -> TimelineThemePalette`
- Produces: `TimelineThemeKind.description -> String`
- Produces: `TimelineThemePalette.of(BuildContext context) -> TimelineThemePalette`
- Produces: `timelineThemeData(ThemeData base, TimelineThemeKind kind) -> ThemeData`

- [ ] **Step 1: Write failing identifier and palette tests**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/timeline_theme.dart';

void main() {
  test('timeline theme identifiers parse and fall back to System Graphite', () {
    expect(
      TimelineThemeKind.values.map((theme) => theme.storageValue),
      ['systemGraphite', 'warmGraphite', 'carbon'],
    );
    expect(
      TimelineThemeKind.parse('warmGraphite'),
      TimelineThemeKind.warmGraphite,
    );
    expect(TimelineThemeKind.parse('carbon'), TimelineThemeKind.carbon);
    expect(
      TimelineThemeKind.parse('unknown'),
      TimelineThemeKind.systemGraphite,
    );
    expect(
      TimelineThemeKind.parse(null),
      TimelineThemeKind.systemGraphite,
    );
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
}

double contrastRatio(Color foreground, Color background) {
  double luminance(Color color) {
    double channel(double value) =>
        value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  final first = luminance(foreground);
  final second = luminance(background);
  return (math.max(first, second) + 0.05) /
      (math.min(first, second) + 0.05);
}
```

- [ ] **Step 2: Run the focused test and verify that the new API is missing**

Run: `flutter test test/timeline_theme_test.dart`

Expected: FAIL because `lib/timeline_theme.dart`, `TimelineThemeKind`, and `TimelineThemePalette` do not exist.

- [ ] **Step 3: Implement the enum and approved palette constants**

Create `lib/timeline_theme.dart` with these public definitions:

```dart
import 'package:flutter/material.dart';

enum TimelineThemeKind {
  systemGraphite(
    'systemGraphite',
    'System Graphite',
    'Balanced neutral gray',
  ),
  warmGraphite(
    'warmGraphite',
    'Warm Graphite',
    'Softer, warmer graphite',
  ),
  carbon('carbon', 'Carbon', 'Deep neutral contrast');

  const TimelineThemeKind(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static TimelineThemeKind parse(Object? value) => values.firstWhere(
    (theme) => theme.storageValue == value,
    orElse: () => systemGraphite,
  );

  TimelineThemePalette get palette => switch (this) {
    systemGraphite => TimelineThemePalette.systemGraphite,
    warmGraphite => TimelineThemePalette.warmGraphite,
    carbon => TimelineThemePalette.carbon,
  };
}

@immutable
class TimelineThemePalette extends ThemeExtension<TimelineThemePalette> {
  const TimelineThemePalette({
    required this.background,
    required this.surface,
    required this.panel,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.neutralChip,
    required this.selectedRow,
    required this.interactive,
  });

  static const systemGraphite = TimelineThemePalette(
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
  );

  static const warmGraphite = TimelineThemePalette(
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
  );

  static const carbon = TimelineThemePalette(
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
  );

  final Color background;
  final Color surface;
  final Color panel;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color neutralChip;
  final Color selectedRow;
  final Color interactive;

  static TimelineThemePalette of(BuildContext context) =>
      Theme.of(context).extension<TimelineThemePalette>() ?? systemGraphite;

  @override
  TimelineThemePalette copyWith({
    Color? background,
    Color? surface,
    Color? panel,
    Color? raised,
    Color? border,
    Color? text,
    Color? muted,
    Color? neutralChip,
    Color? selectedRow,
    Color? interactive,
  }) => TimelineThemePalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    panel: panel ?? this.panel,
    raised: raised ?? this.raised,
    border: border ?? this.border,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    neutralChip: neutralChip ?? this.neutralChip,
    selectedRow: selectedRow ?? this.selectedRow,
    interactive: interactive ?? this.interactive,
  );

  @override
  TimelineThemePalette lerp(
    covariant TimelineThemePalette? other,
    double t,
  ) {
    if (other == null) return this;
    return TimelineThemePalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      neutralChip: Color.lerp(neutralChip, other.neutralChip, t)!,
      selectedRow: Color.lerp(selectedRow, other.selectedRow, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineThemePalette &&
      background == other.background &&
      surface == other.surface &&
      panel == other.panel &&
      raised == other.raised &&
      border == other.border &&
      text == other.text &&
      muted == other.muted &&
      neutralChip == other.neutralChip &&
      selectedRow == other.selectedRow &&
      interactive == other.interactive;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    panel,
    raised,
    border,
    text,
    muted,
    neutralChip,
    selectedRow,
    interactive,
  );
}

extension TimelineThemeContext on BuildContext {
  TimelineThemePalette get timelineTheme => TimelineThemePalette.of(this);
}
```

- [ ] **Step 4: Add a failing test for the local Material theme**

Append:

```dart
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
```

- [ ] **Step 5: Implement `timelineThemeData`**

```dart
ThemeData timelineThemeData(ThemeData base, TimelineThemeKind kind) {
  final palette = kind.palette;
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: base.colorScheme.copyWith(
      surface: palette.surface,
      primary: palette.interactive,
    ),
    extensions: <ThemeExtension<dynamic>>[
      ...base.extensions.values.where(
        (extension) => extension is! TimelineThemePalette,
      ),
      palette,
    ],
  );
}
```

- [ ] **Step 6: Format and run the focused tests**

Run: `dart format lib/timeline_theme.dart test/timeline_theme_test.dart`

Run: `flutter test test/timeline_theme_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the palette model**

```bash
git add lib/timeline_theme.dart test/timeline_theme_test.dart
git commit -m "feat: add timeline theme palettes"
```

### Task 2: Persist the selected theme safely

**Files:**
- Modify: `lib/settings.dart:219-438`
- Modify: `test/app_test.dart:2399-2490`
- Modify: `test/app_test.dart:5089-5116`

**Interfaces:**
- Consumes: `TimelineThemeKind` from Task 1
- Produces: `AppSettings.timelineTheme -> TimelineThemeKind`
- Produces: `AppSettings.copyWith({TimelineThemeKind? timelineTheme})`
- Produces JSON field: `timelineTheme: TimelineThemeKind.storageValue`

- [ ] **Step 1: Add failing JSON, fallback, equality, and copy tests**

Add `import 'package:yogit/timeline_theme.dart';` to `test/app_test.dart`, then add:

```dart
test('timeline theme settings round-trip and reject unknown values', () {
  const settings = AppSettings(timelineTheme: TimelineThemeKind.carbon);
  expect(AppSettings.fromJson(settings.toJson()), settings);
  expect(settings.toJson()['timelineTheme'], 'carbon');
  expect(
    AppSettings.fromJson(const {}).timelineTheme,
    TimelineThemeKind.systemGraphite,
  );
  expect(
    AppSettings.fromJson(
      const {'timelineTheme': 'sepia'},
    ).timelineTheme,
    TimelineThemeKind.systemGraphite,
  );

  final changed = settings.copyWith(
    timelineTheme: TimelineThemeKind.warmGraphite,
  );
  expect(changed.timelineTheme, TimelineThemeKind.warmGraphite);
  expect(changed.copyWith(), changed);
});
```

Extend `settings persist only the supported fields`:

```dart
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
```

- [ ] **Step 2: Run the focused tests and verify that `timelineTheme` is missing**

Run: `flutter test test/app_test.dart --plain-name 'timeline theme settings round-trip and reject unknown values'`

Expected: FAIL because `AppSettings` has no `timelineTheme`.

- [ ] **Step 3: Extend `AppSettings` without changing existing migration behavior**

Add the import:

```dart
import 'timeline_theme.dart';
```

Make these exact model changes:

```dart
class AppSettings {
  const AppSettings({
    this.showAvatars = true,
    this.timelineTheme = TimelineThemeKind.systemGraphite,
    this.previewPlacement = PreviewPlacement.right,
    this.columnWidths = const TimelineColumnWidths(),
    this.repositoryGraphWidths = const {},
    this.fullDiffColumnWidths = const FullDiffColumnWidths(),
    this.fullDiffPreferences = const FullDiffPreferences(),
    this.laneColors = defaultLaneColors,
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.baseBranches = const {},
  });

  final bool showAvatars;
  final TimelineThemeKind timelineTheme;

  AppSettings copyWith({
    bool? showAvatars,
    TimelineThemeKind? timelineTheme,
    PreviewPlacement? previewPlacement,
    TimelineColumnWidths? columnWidths,
    Map<String, double>? repositoryGraphWidths,
    FullDiffColumnWidths? fullDiffColumnWidths,
    FullDiffPreferences? fullDiffPreferences,
    List<String>? laneColors,
    double? previewWidth,
    double? previewHeight,
    Map<String, String>? baseBranches,
  }) => AppSettings(
    showAvatars: showAvatars ?? this.showAvatars,
    timelineTheme: timelineTheme ?? this.timelineTheme,
    previewPlacement: previewPlacement ?? this.previewPlacement,
    columnWidths: columnWidths ?? this.columnWidths,
    repositoryGraphWidths: repositoryGraphWidths ?? this.repositoryGraphWidths,
    fullDiffColumnWidths: fullDiffColumnWidths ?? this.fullDiffColumnWidths,
    fullDiffPreferences: fullDiffPreferences ?? this.fullDiffPreferences,
    laneColors: laneColors ?? this.laneColors,
    previewWidth: previewWidth ?? this.previewWidth,
    previewHeight: previewHeight ?? this.previewHeight,
    baseBranches: baseBranches ?? this.baseBranches,
  );
}
```

In `fromJson`, initialize with:

```dart
timelineTheme: TimelineThemeKind.parse(value['timelineTheme']),
```

In `toJson`, add:

```dart
'timelineTheme': timelineTheme.storageValue,
```

Include `timelineTheme` in `operator ==` and immediately after `showAvatars` in
`Object.hash`.

- [ ] **Step 4: Run the settings tests**

Run: `flutter test test/app_test.dart --plain-name 'timeline theme settings round-trip and reject unknown values'`

Run: `flutter test test/app_test.dart --plain-name 'settings persist only the supported fields'`

Expected: PASS.

- [ ] **Step 5: Format and commit settings persistence**

Run: `dart format lib/settings.dart test/app_test.dart`

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: persist timeline theme choice"
```

### Task 3: Apply the selected palette to the basic screen

**Files:**
- Modify: `lib/main.dart:8-9,273-345`
- Modify: `lib/timeline.dart:1-33,375-4332`
- Modify: `test/app_test.dart:1-120,1170-1200,2030-2050,2210-2310,3440-3510`

**Interfaces:**
- Consumes: `timelineThemeData(ThemeData, TimelineThemeKind)`
- Consumes: `BuildContext.timelineTheme`
- Produces key: `preview-surface`
- Changes: `CommitGraphPainter` gains `backgroundColor` and `selectedRowColor`
- Changes: `fileStateChipColor(String status, {TimelineThemePalette palette = TimelineThemePalette.systemGraphite})`

- [ ] **Step 1: Add a failing default and stored-theme surface test**

Add:

```dart
testWidgets('the timeline uses System Graphite by default and a stored theme', (
  tester,
) async {
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
                .widget<Container>(
                  find.byKey(const Key('preview-surface')),
                )
                .decoration!
            as BoxDecoration)
        .color,
    TimelineThemePalette.systemGraphite.surface,
  );

  await tester.pumpWidget(const SizedBox.shrink());
  store.current = const AppSettings(timelineTheme: TimelineThemeKind.carbon);
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

  expect(scaffoldColor(), TimelineThemePalette.carbon.background);
  expect(toolbarColor(), TimelineThemePalette.carbon.surface);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(
    (tester
                .widget<Container>(
                  find.byKey(const Key('preview-surface')),
                )
                .decoration!
            as BoxDecoration)
        .color,
    TimelineThemePalette.carbon.surface,
  );
});
```

- [ ] **Step 2: Run the surface test and verify that the old navy colors remain**

Run: `flutter test test/app_test.dart --plain-name 'the timeline uses System Graphite by default and a stored theme'`

Expected: FAIL because the scaffold is still `#15171E` and the toolbar is still
`#1D2029`.

- [ ] **Step 3: Wrap only `TimelineScreen` in the selected local theme**

Import `timeline_theme.dart` in `lib/main.dart`. Replace the `home` builder body
with:

```dart
home: Builder(
  builder: (context) => Theme(
    data: timelineThemeData(
      Theme.of(context),
      _settings.timelineTheme,
    ),
    child: TimelineScreen(
      key: Key('timeline-screen-${_repository.root}'),
      repository: _repository,
      controller: widget.windowFrameController,
      onOpenRepository: _openRepository,
      avatarService: _avatarService,
      showRemoteAvatars: _settingsLoaded && _settings.showAvatars,
      preferredPreviewPlacement: _settings.previewPlacement,
      preferredBranch: _settingsLoaded
          ? _settings.baseBranches[_repository.root]
          : null,
      preferredBranchReady: _settingsLoaded,
      columnWidths: _settings.columnWidthsForRepository(_repository.root),
      fullDiffColumnWidths: _settings.fullDiffColumnWidths,
      fullDiffPreferences: _settings.fullDiffPreferences,
      previewWidth: _settings.previewWidth,
      previewHeight: _settings.previewHeight,
      onOpenSettings: _settingsLoaded ? () => _openSettings(context) : null,
      onPreviewPlacementChanged: _settingsLoaded
          ? (placement) => _changeSettings(
              _settings.copyWith(previewPlacement: placement),
            )
          : null,
      onPreferredBranchChanged: _settingsLoaded
          ? (branch) {
              final baseBranches = Map<String, String>.of(
                _settings.baseBranches,
              )..[_repository.root] = branch;
              _changeSettings(_settings.copyWith(baseBranches: baseBranches));
            }
          : null,
      onColumnWidthsChanged: _settingsLoaded
          ? (widths) => _changeSettings(
              _settings.withRepositoryColumnWidths(_repository.root, widths),
            )
          : null,
      onFullDiffColumnWidthsChanged: _settingsLoaded
          ? (widths) => _changeSettings(
              _settings.copyWith(fullDiffColumnWidths: widths),
            )
          : null,
      onFullDiffPreferencesChanged: _settingsLoaded
          ? (preferences) => _changeSettings(
              _settings.copyWith(fullDiffPreferences: preferences),
            )
          : null,
      onPreviewSizeChanged: _settingsLoaded
          ? (size) => _changeSettings(
              _settings.copyWith(
                previewWidth: size.width,
                previewHeight: size.height,
              ),
            )
          : null,
    ),
  ),
),
```

Do not change `yogitTheme()`. `_RepositoryError`, Settings routes, and Full Diff
routes must continue to inherit the existing app theme.

- [ ] **Step 4: Replace base-screen surface constants with palette reads**

Import `timeline_theme.dart` in `lib/timeline.dart`. Remove only these constants:

```dart
_background
_surface
_panelSoft
_raised
_border
_text
_muted
_accent
_selectedRow
```

Keep `_hash`, `_deleted`, `_renamed`, `_dateGroup`, `_main`, window-button
colors, the wordmark palette, and branch colors.

Add to `_TimelineScreenState`:

```dart
TimelineThemePalette get _palette => context.timelineTheme;
```

Use this exact mapping throughout `_TimelineScreenState`:

| Removed name | Replacement |
| --- | --- |
| `_background` | `_palette.background` |
| `_surface` | `_palette.surface` |
| `_panelSoft` | `_palette.panel` |
| `_raised` | `_palette.raised` |
| `_border` | `_palette.border` |
| `_text` | `_palette.text` |
| `_muted` | `_palette.muted` |
| `_accent` | `_palette.neutralChip` |
| `_selectedRow` | `_palette.selectedRow` |

Add `key: const Key('preview-surface')` to the root `Container` returned by
`_previewFor` so the preview's themed surface has a stable test seam.

Any `const` widget or decoration that now reads `_palette` must become
non-const. Keep const constructors everywhere else.

For every helper widget outside `_TimelineScreenState` that used a removed
constant, read the extension once at the beginning of `build`. For example,
rewrite `_KeyCapState.build` as:

```dart
@override
Widget build(BuildContext context) {
  final palette = context.timelineTheme;
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      key: Key('keycap-${widget.label}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: _hovered ? palette.selectedRow : palette.panel,
          border: Border.all(
            color: _hovered ? palette.muted : palette.border,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          widget.label,
          style: TextStyle(color: palette.text, fontSize: 13),
        ),
      ),
    ),
  );
}
```

Apply the same lookup-and-mapping pattern to `_ShowDiffButton`,
`_CopyButtonState`, and other out-of-state helper widgets without changing
their widget structure or behavior.

- [ ] **Step 5: Make painters and pure helpers receive the dynamic colors**

Change `CommitGraphPainter`:

```dart
const CommitGraphPainter({
  required this.row,
  required this.selected,
  required this.committerColor,
  this.previous,
  this.committersBySha = const {},
  this.laneSpacing = defaultLaneSpacing,
  this.compact = false,
  this.refConnector = false,
  this.passThrough = false,
  this.backgroundColor = TimelineThemePalette.systemGraphite.background,
  this.selectedRowColor = TimelineThemePalette.systemGraphite.selectedRow,
});

final Color backgroundColor;
final Color selectedRowColor;

Color get nodeFillColor => selected ? selectedRowColor : backgroundColor;
```

Pass `_palette.background` and `_palette.selectedRow` at every
`CommitGraphPainter` construction. Include both fields in `shouldRepaint`.

Change the file chip helper:

```dart
({Color background, Color letter}) fileStateChipColor(
  String status, {
  TimelineThemePalette palette = TimelineThemePalette.systemGraphite,
}) => switch (status.isEmpty ? '' : status[0]) {
  'A' => (background: _main.withValues(alpha: 0.2), letter: _main),
  'D' => (background: _deleted.withValues(alpha: 0.2), letter: _deleted),
  'R' || 'C' => (
    background: _renamed.withValues(alpha: 0.2),
    letter: _renamed,
  ),
  _ => (background: palette.neutralChip, letter: palette.text),
};
```

Pass `palette: _palette` from the preview. Existing direct tests without a
palette intentionally exercise the new default.

- [ ] **Step 6: Update exact-color expectations for the new default**

Change only expectations that describe basic-screen neutral surfaces:

```dart
expect(selectedBase.color, TimelineThemePalette.systemGraphite.background);
expect(chip('lib/a.dart'), TimelineThemePalette.systemGraphite.neutralChip);
expect(
  painter.nodeFillColor,
  TimelineThemePalette.systemGraphite.selectedRow,
);
```

Do not change expectations for Full Diff constants, semantic status colors,
branch rails, the wordmark, or Settings colors.

- [ ] **Step 7: Run the timeline surface and existing color-focused tests**

Run: `flutter test test/app_test.dart --plain-name 'the timeline uses System Graphite by default and a stored theme'`

Run: `flutter test test/app_test.dart --plain-name 'preview describes the working tree row and counts files'`

Run: `flutter test test/app_test.dart --plain-name 'the working tree ring takes its branch line color'`

Expected: PASS.

- [ ] **Step 8: Format, analyze the changed files, and commit**

Run: `dart format lib/main.dart lib/timeline.dart test/app_test.dart`

Run: `flutter analyze lib/main.dart lib/timeline.dart lib/timeline_theme.dart test/app_test.dart`

Expected: no issues.

```bash
git add lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: apply graphite themes to timeline"
```

### Task 4: Add the `Appearance` settings section and theme cards

**Files:**
- Modify: `lib/settings.dart:449-866`
- Modify: `test/app_test.dart:2550-2613,3029-3044`

**Interfaces:**
- Consumes: `TimelineThemeKind.values`, `.label`, and `.palette`
- Produces key: `settings-section-appearance`
- Preserves key: `settings-git-integrations`
- Produces keys: `timeline-theme-card-systemGraphite`, `timeline-theme-card-warmGraphite`, `timeline-theme-card-carbon`
- Calls: `_change(_settings.copyWith(timelineTheme: theme))`

- [ ] **Step 1: Write a failing Appearance navigation and selection test**

```dart
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

  expect(find.byKey(const Key('settings-section-appearance')), findsOneWidget);
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
```

- [ ] **Step 2: Run the test and verify that Appearance is absent**

Run: `flutter test test/app_test.dart --plain-name 'Appearance selects one of three timeline theme previews'`

Expected: FAIL because `settings-section-appearance` does not exist.

- [ ] **Step 3: Split Settings into two local sections**

Add:

```dart
enum _SettingsSection { gitIntegrations, appearance }
```

Keep `_SettingsSection.gitIntegrations` as the initial section to preserve the
current opening behavior:

```dart
var _section = _SettingsSection.gitIntegrations;
```

Replace the single sidebar row with two `_settingsSectionRow` calls:

```dart
_settingsSectionRow(
  section: _SettingsSection.appearance,
  key: const Key('settings-section-appearance'),
  icon: Icons.palette_outlined,
  label: 'Appearance',
),
_settingsSectionRow(
  section: _SettingsSection.gitIntegrations,
  key: const Key('settings-git-integrations'),
  icon: Icons.account_tree_outlined,
  label: 'Git integrations',
),
```

Add this exact row builder:

```dart
Widget _settingsSectionRow({
  required _SettingsSection section,
  required Key key,
  required IconData icon,
  required String label,
}) {
  final selected = _section == section;
  return Material(
    key: key,
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _section = section),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF263246) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? const Color(0xFF7AD6E8)
                  : const Color(0xFF8D94A8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFE8EAF2)
                      : const Color(0xFF8D94A8),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Extract the current right-hand content into `_gitIntegrations()` without
changing its fields, keys, or copy. Choose the body with:

```dart
Expanded(
  child: switch (_section) {
    _SettingsSection.appearance => _appearance(),
    _SettingsSection.gitIntegrations => _gitIntegrations(),
  },
),
```

- [ ] **Step 4: Implement the three accessible theme cards**

Use the fixed Settings colors for the section shell. Build the cards from the
enum so labels and stored identifiers cannot drift:

```dart
Widget _appearance() => SingleChildScrollView(
  padding: const EdgeInsets.all(24),
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 660),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appearance',
          style: TextStyle(
            color: Color(0xFFE8EAF2),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the dark appearance used by the timeline and preview.',
          style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final theme in TimelineThemeKind.values)
              _TimelineThemeCard(
                key: Key('timeline-theme-card-${theme.storageValue}'),
                theme: theme,
                selected: _settings.timelineTheme == theme,
                onTap: () => _change(
                  _settings.copyWith(timelineTheme: theme),
                ),
              ),
          ],
        ),
      ],
    ),
  ),
);
```

Add the card below `SettingsScreen`. `InkWell` supplies click, Enter, and Space
activation through the same `onTap`:

```dart
class _TimelineThemeCard extends StatelessWidget {
  const _TimelineThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final TimelineThemeKind theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final surfaces = [
      palette.background,
      palette.panel,
      palette.surface,
      palette.raised,
    ];
    return Semantics(
      selected: selected,
      button: true,
      label: theme.label,
      child: SizedBox(
        width: 196,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
              color: selected
                  ? palette.interactive
                  : const Color(0xFF343946),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          theme.label,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: palette.interactive,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    theme.description,
                    style: TextStyle(color: palette.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Row(
                            children: [
                              for (final color in surfaces)
                                Expanded(
                                  child: ColoredBox(
                                    color: color,
                                    child: const SizedBox(height: 26),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: palette.interactive,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add a keyboard selection assertion**

Extend the test after opening Appearance:

```dart
await tester.tap(find.byKey(const Key('timeline-theme-card-warmGraphite')));
await tester.pump();
final saveCountAfterTap = saved.length;
await tester.sendKeyEvent(LogicalKeyboardKey.enter);
await tester.pumpAndSettle();
expect(saved.last.timelineTheme, TimelineThemeKind.warmGraphite);
expect(saved.length, saveCountAfterTap + 1);
```

The tap both selects and focuses the `InkWell`; the extra save proves that Enter
activates the focused card rather than merely observing the tap result.

- [ ] **Step 6: Run settings UI tests**

Run: `flutter test test/app_test.dart --plain-name 'Appearance selects one of three timeline theme previews'`

Run: `flutter test test/app_test.dart --plain-name 'the timeline colors editor applies hex edits and resets'`

Run: `flutter test test/app_test.dart --plain-name 'settings removes legacy full diff starting views'`

Expected: PASS. The Git integrations editor remains unchanged.

- [ ] **Step 7: Format, analyze, and commit Appearance**

Run: `dart format lib/settings.dart test/app_test.dart`

Run: `flutter analyze lib/settings.dart test/app_test.dart`

Expected: no issues.

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: choose timeline theme in settings"
```

### Task 5: Verify live switching, state preservation, and screen isolation

**Files:**
- Modify: `test/app_test.dart:3029-3074,5616-5667`

**Interfaces:**
- Consumes: all APIs from Tasks 1-4
- Verifies: theme changes rebuild colors without remounting `TimelineScreen`
- Verifies: Full Diff and Settings do not inherit the timeline extension

- [ ] **Step 1: Add a failing live-switch preservation test**

```dart
testWidgets('changing the timeline theme preserves selection and scroll', (
  tester,
) async {
  final store = MemorySettingsStore();
  final commits = [
    for (var index = 0; index < 30; index++)
      commit('$index', 'commit $index'),
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
  final before = tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('timeline-list')),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings-section-appearance')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('timeline-theme-card-carbon')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();

  expect(store.current.timelineTheme, TimelineThemeKind.carbon);
  expect(find.byKey(const Key('selected-row-12')), findsOneWidget);
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
```

- [ ] **Step 2: Run the live-switch test**

Run: `flutter test test/app_test.dart --plain-name 'changing the timeline theme preserves selection and scroll'`

Expected: PASS after Tasks 1-4. If it fails because the timeline remounts, keep
the existing repository key and move only the `Theme` above it; do not add
state restoration code.

- [ ] **Step 3: Add Full Diff and Settings isolation assertions**

Add:

```dart
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
  expect(
    tester
        .widget<Scaffold>(find.byType(Scaffold).last)
        .backgroundColor,
    fullDiffCanvas,
  );
});
```

Import `full_diff_theme.dart` in the test if it is not already imported.

- [ ] **Step 4: Run the isolation and related navigation tests**

Run: `flutter test test/app_test.dart --plain-name 'timeline themes do not recolor Settings or Full Diff'`

Run: `flutter test test/app_test.dart --plain-name 'settings toggle preserves timeline state and graph geometry'`

Run: `flutter test test/app_test.dart --plain-name 'opens the full diff and preserves timeline state on escape'`

Expected: PASS.

- [ ] **Step 5: Run all theme and app tests, then commit**

Run: `flutter test test/timeline_theme_test.dart test/app_test.dart`

Expected: PASS.

```bash
git add test/app_test.dart
git commit -m "test: verify timeline theme switching"
```

### Task 6: Complete static, full-suite, and visual verification

**Files:**
- Modify only if verification exposes a defect in files already listed above.

**Interfaces:**
- Verifies the complete approved feature.

- [ ] **Step 1: Format every changed Dart file**

Run:

```bash
dart format \
  lib/timeline_theme.dart \
  lib/settings.dart \
  lib/main.dart \
  lib/timeline.dart \
  test/timeline_theme_test.dart \
  test/app_test.dart
```

Expected: no unformatted files remain.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 4: Compare each live theme with the approved visual**

Run: `flutter run -d macos --debug`

Using `Settings > Appearance`, inspect `System Graphite`, `Warm Graphite`, and
`Carbon` in turn. For each theme confirm:

- the timeline background, toolbar, sidebar, header, controls, selection, and
  preview match the approved swatches;
- semantic Git colors do not change;
- Settings retains its existing navy palette;
- Full Diff retains `full_diff_theme.dart`;
- switching themes does not move the selected commit, list scroll, or preview.

Compare against:
`/Users/doortts/repos/yogit/.superpowers/brainstorm/99264-1785245201/theme-directions-preview.png`.

- [ ] **Step 5: Review the final diff for scope**

Run: `git diff --check`

Run: `git status --short`

Run:

```bash
git diff --stat \
  main...HEAD \
  -- \
  lib/timeline_theme.dart \
  lib/settings.dart \
  lib/main.dart \
  lib/timeline.dart \
  test/timeline_theme_test.dart \
  test/app_test.dart
```

Expected: the branch diff contains only the six planned product and test files.
If visual verification found no defect, the implementation worktree is clean;
otherwise only those planned files are dirty for Step 6. The existing user
changes in the main worktree remain untouched.

- [ ] **Step 6: Commit verification-only fixes if Step 1-5 required code changes**

If no files changed during verification, do not create an empty commit.

```bash
git add \
  lib/timeline_theme.dart \
  lib/settings.dart \
  lib/main.dart \
  lib/timeline.dart \
  test/timeline_theme_test.dart \
  test/app_test.dart
git commit -m "fix: polish timeline theme selection"
```

### Task 7: Review and merge the verified branch into `main`

**Files:**
- No additional product files.

**Interfaces:**
- Consumes branch: `codex/timeline-theme-selection`
- Updates branch: `main`

- [ ] **Step 1: Request a final code review**

Use `superpowers:requesting-code-review` against the complete
`main...codex/timeline-theme-selection` diff. Resolve every correctness or
requirements issue, then rerun Task 6 Steps 1-3.

- [ ] **Step 2: Load the branch-finishing instructions**

Use `superpowers:finishing-a-development-branch`. The approved integration
choice is a local merge into `main`; do not create a pull request.

- [ ] **Step 3: Verify the original main worktree before merging**

From `/Users/doortts/repos/yogit`, run:

```bash
git status --short --branch
git branch --show-current
```

Expected: the current branch is `main`. The pre-existing modification to
`docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md` and the
untracked `.superpowers/brainstorm/` directory may still be present; no
implementation file from this plan is dirty.

- [ ] **Step 4: Merge the implementation branch**

From `/Users/doortts/repos/yogit`, run:

```bash
git merge --no-ff codex/timeline-theme-selection
```

Expected: the merge succeeds without touching the pre-existing user changes.
If Git reports an overlap, stop and preserve both sides rather than forcing the
merge.

- [ ] **Step 5: Verify the merged result on `main`**

Run:

```bash
flutter analyze
flutter test
git status --short --branch
git log -1 --oneline
```

Expected: analysis and tests pass, `main` contains the merge commit, and only
the same pre-existing user changes remain unstaged.
