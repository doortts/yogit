# Font Size Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independently persisted 80%–140% font scaling for Interface, Lists & Content, and Code & Diff, with 5% controls and app-wide `⌘−` / `⌘+` shortcuts.

**Architecture:** Keep every existing `TextStyle.fontSize` as the 100% baseline. A reusable `FontScaleScope` replaces the active `MediaQuery.textScaler` for one category while retaining the system text scaler; nested category scopes always start from that system baseline instead of multiplying each other. `AppSettings` owns three integer percentages, and the existing settings save path persists both direct controls and shortcut changes.

**Tech Stack:** Flutter 3.44, Dart 3.12, Material widgets, `flutter_test`; no new dependency.

## Global Constraints

- Each category accepts 80% through 140% inclusive in 5 percentage-point steps.
- Existing settings files default all three categories to 100%.
- Increasing above 100% expands fixed text rows that would otherwise clip; decreasing below 100% does not shrink existing click targets.
- `⌘−` decreases all three values by 5 percentage points; `⌘+`, `⌘=`, and `⇧⌘=` increase them by 5 percentage points.
- Whole-app controls change the three stored values directly. There is no fourth multiplier.
- Preserve system text scaling, existing font families, current color themes, column widths, and user-owned untracked files.

---

### Task 1: Font scale model and scope

**Files:**
- Create: `lib/font_scale.dart`
- Modify: `lib/settings.dart`
- Create: `test/font_scale_test.dart`

**Interfaces:**
- Produces: `normalizeFontScalePercent(Object? value) -> int`
- Produces: `adjustFontScalePercent(int value, int delta) -> int`
- Produces: `scaledFixedExtent(double base, int percent) -> double`
- Produces: `FontScaleScope({required int percent, required Widget child})`
- Produces: `AppSettings.interfaceFontScalePercent`, `contentFontScalePercent`, `codeFontScalePercent`
- Produces: `AppSettings.adjustAllFontScales(int delta) -> AppSettings`

- [ ] **Step 1: Write failing model and scope tests**

Create `test/font_scale_test.dart` with literal expectations:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/font_scale.dart';
import 'package:yogit/settings.dart';

void main() {
  test('font scale values clamp and snap to five percent steps', () {
    expect(normalizeFontScalePercent(null), 100);
    expect(normalizeFontScalePercent('120'), 100);
    expect(normalizeFontScalePercent(77), 80);
    expect(normalizeFontScalePercent(82), 80);
    expect(normalizeFontScalePercent(83), 85);
    expect(normalizeFontScalePercent(143), 140);
    expect(adjustFontScalePercent(80, -5), 80);
    expect(adjustFontScalePercent(135, 5), 140);
  });

  test('font scale settings round-trip and adjust together', () {
    const settings = AppSettings(
      interfaceFontScalePercent: 90,
      contentFontScalePercent: 100,
      codeFontScalePercent: 110,
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);
    expect(settings.adjustAllFontScales(5), const AppSettings(
      interfaceFontScalePercent: 95,
      contentFontScalePercent: 105,
      codeFontScalePercent: 115,
    ));
    expect(AppSettings.fromJson(const {}).interfaceFontScalePercent, 100);
    expect(
      AppSettings.fromJson(const {
        'interfaceFontScalePercent': 78,
        'contentFontScalePercent': 118,
        'codeFontScalePercent': 999,
      }),
      const AppSettings(
        interfaceFontScalePercent: 80,
        contentFontScalePercent: 120,
        codeFontScalePercent: 140,
      ),
    );
  });

  testWidgets('nested font categories replace rather than multiply', (tester) async {
    late double interfaceTen;
    late double contentTen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: FontScaleScope(
          percent: 125,
          child: Builder(
            builder: (context) {
              interfaceTen = MediaQuery.textScalerOf(context).scale(10);
              return FontScaleScope(
                percent: 80,
                child: Builder(
                  builder: (context) {
                    contentTen = MediaQuery.textScalerOf(context).scale(10);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(interfaceTen, 15);
    expect(contentTen, 9.6);
  });

  test('fixed extents grow only above one hundred percent', () {
    expect(scaledFixedExtent(32, 80), 32);
    expect(scaledFixedExtent(32, 100), 32);
    expect(scaledFixedExtent(32, 140), 44.8);
  });
}
```

The production change that makes these tests pass is the new normalization, persistence fields, non-multiplying scope, and fixed-extent rule.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/font_scale_test.dart
```

Expected: compilation fails because `font_scale.dart`, the three `AppSettings` fields, and `adjustAllFontScales` do not exist.

- [ ] **Step 3: Implement the minimal scale helpers**

Create `lib/font_scale.dart`:

```dart
import 'package:flutter/material.dart';

const minFontScalePercent = 80;
const maxFontScalePercent = 140;
const fontScaleStepPercent = 5;

int normalizeFontScalePercent(Object? value) {
  if (value is! num || !value.isFinite) return 100;
  final clamped = value.clamp(
    minFontScalePercent,
    maxFontScalePercent,
  ).toDouble();
  return ((clamped / fontScaleStepPercent).round() * fontScaleStepPercent)
      .clamp(minFontScalePercent, maxFontScalePercent)
      .toInt();
}

int adjustFontScalePercent(int value, int delta) =>
    normalizeFontScalePercent(value + delta);

double scaledFixedExtent(double base, int percent) =>
    base * (percent / 100).clamp(1.0, double.infinity);

class FontScaleScope extends StatelessWidget {
  const FontScaleScope({
    required this.percent,
    required this.child,
    super.key,
  });

  final int percent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final baseline =
        _FontScaleBaseline.maybeOf(context) ??
        MediaQuery.textScalerOf(context);
    return _FontScaleBaseline(
      scaler: baseline,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: _MultipliedTextScaler(baseline, percent / 100),
        ),
        child: child,
      ),
    );
  }
}
```

In the same file, implement `_FontScaleBaseline extends InheritedWidget` with `maybeOf`, and `_MultipliedTextScaler extends TextScaler` so `scale(fontSize)` returns `baseline.scale(fontSize) * multiplier`. Implement equality, `hashCode`, and the deprecated compatibility getter as `baseline.textScaleFactor * multiplier`; do not add a public abstraction.

- [ ] **Step 4: Add the three settings fields**

Update the `AppSettings` constructor, fields, `copyWith`, `fromJson`, `toJson`, equality, and `hashCode` in `lib/settings.dart`. Use these exact keys:

```dart
'interfaceFontScalePercent'
'contentFontScalePercent'
'codeFontScalePercent'
```

Add:

```dart
AppSettings adjustAllFontScales(int delta) => copyWith(
  interfaceFontScalePercent: adjustFontScalePercent(
    interfaceFontScalePercent,
    delta,
  ),
  contentFontScalePercent: adjustFontScalePercent(
    contentFontScalePercent,
    delta,
  ),
  codeFontScalePercent: adjustFontScalePercent(
    codeFontScalePercent,
    delta,
  ),
);
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
dart format lib/font_scale.dart lib/settings.dart test/font_scale_test.dart
flutter test test/font_scale_test.dart
```

Expected: PASS with no warnings or exceptions.

- [ ] **Step 6: Commit**

```bash
git add lib/font_scale.dart lib/settings.dart test/font_scale_test.dart
git commit -m "feat: persist font scale settings"
```

---

### Task 2: Appearance controls

**Files:**
- Modify: `lib/settings.dart`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes: the three `AppSettings` percentages and `adjustAllFontScales`
- Produces: sliders and step buttons keyed by `font-scale-<category>-slider`, `font-scale-<category>-decrease`, and `font-scale-<category>-increase`
- Produces: whole-app buttons keyed by `font-scale-all-decrease` and `font-scale-all-increase`

- [ ] **Step 1: Write a failing settings widget test**

Add a test beside the existing Appearance test in `test/app_test.dart`:

```dart
testWidgets('Appearance edits category and whole-app font scales', (tester) async {
  final saved = <AppSettings>[];
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settings: const AppSettings(
          interfaceFontScalePercent: 90,
          contentFontScalePercent: 100,
          codeFontScalePercent: 110,
        ),
        onChanged: saved.add,
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('settings-section-appearance')));
  await tester.pumpAndSettle();

  expect(find.text('⌘− / ⌘+'), findsOneWidget);
  expect(find.text('90–110%'), findsOneWidget);

  await tester.tap(find.byKey(const Key('font-scale-all-increase')));
  await tester.pump();
  expect(
    saved.last,
    const AppSettings(
      interfaceFontScalePercent: 95,
      contentFontScalePercent: 105,
      codeFontScalePercent: 115,
    ),
  );

  await tester.tap(find.byKey(const Key('font-scale-interface-decrease')));
  await tester.pump();
  expect(saved.last.interfaceFontScalePercent, 90);

  tester
      .widget<Slider>(find.byKey(const Key('font-scale-code-slider')))
      .onChanged!(140);
  await tester.pump();
  expect(saved.last.codeFontScalePercent, 140);
  expect(
    tester
        .widget<IconButton>(
          find.byKey(const Key('font-scale-code-increase')),
        )
        .onPressed,
    isNull,
  );
});
```

The production change that makes the test pass is the visible three-row editor, whole-app controls, bounds, and callback wiring.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "Appearance edits category and whole-app font scales"
```

Expected: FAIL because the new keys and shortcut copy are absent.

- [ ] **Step 3: Build the Appearance editor**

In `_SettingsScreenState._appearance`, keep the theme cards and add a `Font size` section above them. Add one private `_fontScaleRow` method to avoid repeating the slider and two buttons three times.

Use:

```dart
Slider(
  key: Key('font-scale-$name-slider'),
  min: minFontScalePercent.toDouble(),
  max: maxFontScalePercent.toDouble(),
  divisions:
      (maxFontScalePercent - minFontScalePercent) ~/ fontScaleStepPercent,
  value: value.toDouble(),
  label: '$value%',
  onChanged: (next) => onChanged(next.round()),
)
```

Each `IconButton` changes exactly 5 percentage points and sets `onPressed` to `null` at its bound. Size its constraints with `scaledFixedExtent(28, _settings.interfaceFontScalePercent)`.

For `All areas`, call `_change(_settings.adjustAllFontScales(±5))`. Display one value when all values match; otherwise display `'$minimum–$maximum%'`. Put the literal `⌘− / ⌘+` in the row.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
dart format lib/settings.dart test/app_test.dart
flutter test test/app_test.dart --plain-name "Appearance edits category and whole-app font scales"
```

Expected: PASS with no overflow exception.

- [ ] **Step 5: Commit**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: add font scale controls"
```

---

### Task 3: App shortcuts and timeline scaling

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/timeline.dart`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes: `FontScaleScope`, `scaledFixedExtent`, and all three settings percentages
- Produces: root `CallbackShortcuts` bindings handled above the Navigator
- Produces: `TimelineScreen.contentFontScalePercent` and `codeFontScalePercent`, both defaulting to 100 for existing direct callers

- [ ] **Step 1: Write failing shortcut and timeline scope tests**

Add two tests in `test/app_test.dart`.

The shortcut test pumps `YogitApp` with a `MemorySettingsStore` initialized to 90/100/110, sends Meta+Equal, and expects 95/105/115:

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
await tester.pumpAndSettle();
expect(store.current.interfaceFontScalePercent, 95);
expect(store.current.contentFontScalePercent, 105);
expect(store.current.codeFontScalePercent, 115);
```

Then tap `find.byKey(const Key('open-settings'))`, wait for the Settings route, send Meta+Minus, and expect the original 90/100/110. This proves the shortcut layer stays above the Navigator.

The scope test pumps `YogitApp` with Interface 120 and Lists & Content 140. Resolve the elements containing the repository title and `LOCAL`, then assert:

```dart
final interfaceCaption = find.text('저장소');
expect(
  MediaQuery.textScalerOf(tester.element(interfaceCaption)).scale(10),
  12,
);
expect(
  MediaQuery.textScalerOf(tester.element(find.text('LOCAL'))).scale(10),
  14,
);
expect(
  tester.getSize(find.byKey(const Key('selected-row-1'))).height,
  44.8,
);
expect(tester.takeException(), isNull);
```

The production changes these tests guard are app-level shortcut persistence, independent nested scales, and the enlarged timeline row geometry.

- [ ] **Step 2: Run the two focused tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "app font shortcuts adjust every category"
flutter test test/app_test.dart --plain-name "timeline uses interface and content font scales"
```

Expected: FAIL because the root shortcuts, scope values, and scaled row height are absent.

- [ ] **Step 3: Install root Interface scaling and shortcuts**

In `YogitApp`'s `MaterialApp`, use `builder` to wrap the Navigator child in:

1. `FontScaleScope(percent: _settings.interfaceFontScalePercent)`
2. `CallbackShortcuts` for Meta+Minus, Meta+Equal, and Shift+Meta+Equal

Each callback calls `_changeSettings(_settings.adjustAllFontScales(±5))`. Keep the shortcut layer above the Navigator so the same bindings work on the timeline, Full Diff, and Settings routes. Do not add a custom Intent class.

- [ ] **Step 4: Pass scale values into the timeline**

Add defaulted fields to `TimelineScreen`:

```dart
final int contentFontScalePercent;
final int codeFontScalePercent;
```

Pass both from `lib/main.dart`. Wrap `_sidebar()`, the timeline viewport, and `_preview()` with `FontScaleScope(percent: widget.contentFontScalePercent)`. Toolbar, status bar, menus, and settings continue inheriting Interface.

Add:

```dart
double get _rowHeight => scaledFixedExtent(
  TimelineScreen.rowHeight,
  widget.contentFontScalePercent,
);
```

Replace every timeline scroll calculation, `ListView.itemExtent`, graph cell height, node centering calculation, and row visibility calculation that currently reads `TimelineScreen.rowHeight` inside `_TimelineScreenState` with `_rowHeight`. Keep `TimelineScreen.rowHeight == 32.0` as the public 100% baseline.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run:

```bash
dart format lib/main.dart lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart --plain-name "app font shortcuts adjust every category"
flutter test test/app_test.dart --plain-name "timeline uses interface and content font scales"
```

Expected: both PASS and `tester.takeException()` is null.

- [ ] **Step 6: Run timeline regression tests**

Run:

```bash
flutter test test/app_test.dart
```

Expected: PASS. Any expectation that intentionally measures a 100% row remains 32.0 because defaults stay 100%.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: scale timeline text and rows"
```

---

### Task 4: Full Diff content and source-row scaling

**Files:**
- Modify: `lib/timeline.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_diff_code_row.dart`
- Modify: `lib/full_diff_side_by_side_view.dart`
- Modify: `lib/full_blame_view.dart`
- Modify: `test/full_diff_workspace_test.dart`
- Modify: `test/full_diff_content_views_test.dart`

**Interfaces:**
- Consumes: `TimelineScreen.contentFontScalePercent`, `codeFontScalePercent`
- Produces: `DiffScreen.contentFontScalePercent` and `codeFontScalePercent`, both defaulting to 100
- Consumes: `FontScaleScope` and `scaledFixedExtent`

- [ ] **Step 1: Write failing Full Diff category tests**

In `test/full_diff_workspace_test.dart`, pump `DiffScreen` with `contentFontScalePercent: 120` and `codeFontScalePercent: 140`. After the fixture settles, assert that a changed-file path uses 120% while `code-row-source-text` uses 140%:

```dart
final changedFilePath = find.descendant(
  of: find.byKey(const Key('commit-files-pane')),
  matching: find.text('src/drlua.pas'),
);
expect(
  MediaQuery.textScalerOf(
    tester.element(changedFilePath),
  ).scale(10),
  12,
);
expect(
  MediaQuery.textScalerOf(
    tester.element(find.byKey(const Key('code-row-source-text')).first),
  ).scale(10),
  14,
);
expect(tester.takeException(), isNull);
```

In `test/full_diff_content_views_test.dart`, pump an unwrapped side-by-side row and a `BlameSourceRow` under `FontScaleScope(percent: 140)`. Assert their heights are `fullDiffSourceRowHeight * 1.4` and no exception occurs.

The production changes these tests guard are category boundaries and fixed source-row layout at 140%.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name "full diff applies content and code font scales"
flutter test test/full_diff_content_views_test.dart --plain-name "source rows grow with code font scale"
```

Expected: compilation fails because `DiffScreen` has no scale arguments and source rows still use fixed heights.

- [ ] **Step 3: Apply Full Diff category scopes**

Add defaulted `contentFontScalePercent` and `codeFontScalePercent` parameters to `DiffScreen`.

In `_openFullDiff` in `lib/timeline.dart`, pass the two values from `TimelineScreen`.

In `DiffScreen`:

- Wrap `_commitFiles(state)` with Lists & Content.
- Wrap history content with Lists & Content.
- Wrap Diff and Blame content with Code & Diff.
- Leave `GlobalFileBar`, `GlobalDiffToolbar`, dividers, and minimap controls under Interface.

Use `FontScaleScope`; do not multiply the inherited Interface value.

- [ ] **Step 4: Grow fixed code rows above 100%**

Expose one public helper from `font_scale.dart`:

```dart
double scaledFixedExtentOf(BuildContext context, double base) =>
    math.max(base, MediaQuery.textScalerOf(context).scale(base));
```

Import `dart:math` as `math`. The helper includes the active app category and system text scaling while preserving the current minimum size.

Use `scaledFixedExtentOf` for:

- `FullDiffCodeRow` minimum heights
- unwrapped `SideBySidePresentationView` row height
- `HatchedDiffCell` height
- `FullBlameView` scroll offset estimates
- `BlameSourceRow` metadata and rail heights

Keep the 21.0 and 27.0 constants as 100% baselines.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run:

```bash
dart format lib/font_scale.dart lib/timeline.dart lib/diff_screen.dart lib/full_diff_code_row.dart lib/full_diff_side_by_side_view.dart lib/full_blame_view.dart test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart
flutter test test/full_diff_workspace_test.dart --plain-name "full diff applies content and code font scales"
flutter test test/full_diff_content_views_test.dart --plain-name "source rows grow with code font scale"
```

Expected: PASS with no overflow exception.

- [ ] **Step 6: Run Full Diff regressions**

Run:

```bash
flutter test test/full_diff_workspace_test.dart
flutter test test/full_diff_content_views_test.dart
flutter test test/full_diff_widgets_test.dart
```

Expected: PASS. Default 100% keeps existing pixel expectations unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/font_scale.dart lib/timeline.dart lib/diff_screen.dart lib/full_diff_code_row.dart lib/full_diff_side_by_side_view.dart lib/full_blame_view.dart test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart
git commit -m "feat: scale full diff text and rows"
```

---

### Task 5: Final verification

**Files:**
- Modify only files required to fix a failing check caused by Tasks 1–4.

**Interfaces:**
- Consumes: all feature behavior from Tasks 1–4
- Produces: a formatted, analyzed, fully passing change

- [ ] **Step 1: Format and analyze**

Run:

```bash
dart format lib test
flutter analyze
```

Expected: no analyzer errors or warnings introduced by this change.

- [ ] **Step 2: Run the complete test suite**

Run:

```bash
flutter test
```

Expected: all tests PASS.

- [ ] **Step 3: Inspect the 80%, 100%, and 140% layouts**

Run the app and verify each category at 80%, 100%, and 140%:

```bash
flutter run -d macos
```

Check the timeline, preview, settings route, Full Diff unified view, side-by-side view, and Blame view. Confirm text is not clipped, clickable controls do not shrink below the 100% target size, and `⌘−` / `⌘+` updates and persists all three values.

- [ ] **Step 4: Check the final diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace error. The only tracked changes belong to this feature; the pre-existing untracked plan files remain untouched.

- [ ] **Step 5: Commit any verification-only correction**

If Step 1–4 required a source correction, stage only its exact files and commit:

```bash
git commit -m "fix: complete font scale layout"
```

If no correction was needed, do not create an empty commit.
