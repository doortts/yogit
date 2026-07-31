# Editable Base Branch Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit the base branch color and apply it to whichever branch is currently selected as the timeline base.

**Architecture:** Store the base color separately from the existing fallback lane palette. Apply both values to `AvatarService`, where branch id `0` already represents the selected base branch in normal and comparison layouts.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Keep `#5CB270` as the default base branch color.
- Preserve the existing `laneColors` values and migration behavior.
- Reuse the existing `preferredTip` → branch id `0` layout flow.
- Add no dependency, per-repository color map, or new state service.

---

### Task 1: Persist and render the base branch color

**Files:**
- Modify: `lib/avatars.dart:285-301`
- Modify: `lib/settings.dart:259-505`
- Modify: `lib/main.dart:209-260`
- Modify: `lib/timeline.dart:526-579`
- Test: `test/app_test.dart:5457-5522`
- Test: `test/app_test.dart:6301-6327`
- Test: `test/app_test.dart:10197-10261`

**Interfaces:**
- Produces: `AppSettings.baseBranchColor: String`
- Produces: `AppSettings.baseBranchColorValue: Color`
- Produces: `AvatarService.defaultBaseBranchColor: Color`
- Produces: mutable `AvatarService.baseBranchColor: Color`

- [ ] **Step 1: Write failing settings and graph tests**

Extend the settings round-trip test with a literal base color and malformed-value fallback:

```dart
const custom = AppSettings(
  baseBranchColor: '#112233',
  laneColors: ['#445566', '#778899'],
);
final decoded = AppSettings.fromJson(custom.toJson());
expect(decoded, custom);
expect(decoded.baseBranchColorValue, const Color(0xFF112233));
expect(
  AppSettings.fromJson(const {'baseBranchColor': 'bad'}).baseBranchColor,
  AppSettings.defaultBaseBranchColor,
);
expect(
  AppSettings.fromJson(const {}).baseBranchColor,
  AppSettings.defaultBaseBranchColor,
);
```

Replace the stored-palette widget test with a base-color assertion:

```dart
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
```

Add a pure graph test proving the configured color follows the selected base:

```dart
test('the selected base branch owns the configurable branch-zero color', () {
  addTearDown(() {
    AvatarService.baseBranchColor = AvatarService.defaultBaseBranchColor;
    AvatarService.branchAssignments = const {};
  });
  AvatarService.baseBranchColor = const Color(0xFF123456);
  final rows = layoutGraph(
    [
      commit('other-tip', 'other', parents: const ['root']),
      commit('base-tip', 'base', parents: const ['root']),
      commit('root', 'root'),
    ],
    preferredTip: 'base-tip',
  );

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
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --name 'lane colors round-trip|stored timeline colors reach|selected base branch owns'
```

Expected: compilation fails because `baseBranchColor`,
`baseBranchColorValue`, and `defaultBaseBranchColor` do not exist.

- [ ] **Step 3: Add the minimal setting and color plumbing**

In `AvatarService`, replace the fixed main-line constant with a default and
mutable current value:

```dart
static const defaultBaseBranchColor = Color(0xFF5CB270);
static Color baseBranchColor = defaultBaseBranchColor;
```

Make `branchColor(0)` return `baseBranchColor`. In `assignBranchColors`, assign
branch id `0` from the same value and exclude it from the overflow palette:

```dart
if (id == 0) {
  colors[id] = AvatarService.baseBranchColor;
  continue;
}
```

Add the stored setting and parsed value to `AppSettings`:

```dart
static const defaultBaseBranchColor = '#5CB270';

this.baseBranchColor = defaultBaseBranchColor,
this.laneColors = defaultLaneColors,

final String baseBranchColor;

Color get baseBranchColorValue =>
    parseHexColor(baseBranchColor) ?? AvatarService.defaultBaseBranchColor;
```

Thread `baseBranchColor` through `copyWith`, `fromJson`, `toJson`, equality,
and `hashCode`. Normalize valid JSON values and fall back otherwise:

```dart
final storedBaseBranchColor = '${value['baseBranchColor'] ?? ''}';

baseBranchColor: parseHexColor(storedBaseBranchColor) == null
    ? defaultBaseBranchColor
    : formatHexColor(storedBaseBranchColor),
```

Apply the parsed color beside the palette in both settings entry points in
`YogitApp`:

```dart
AvatarService.baseBranchColor = settings.baseBranchColorValue;
AvatarService.palette = settings.laneColorValues;
```

Replace every remaining `mainBranchColor` reference with the new base-branch
name, including the fixed-row assertion that remains until Task 2.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
dart format lib/avatars.dart lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart --name 'lane colors round-trip|stored timeline colors reach|selected base branch owns'
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/avatars.dart lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: apply configurable base branch color"
```

---

### Task 2: Make the base branch color editable

**Files:**
- Modify: `lib/settings.dart:554-587`
- Modify: `lib/settings.dart:818-903`
- Test: `test/app_test.dart:6236-6299`

**Interfaces:**
- Consumes: `AppSettings.baseBranchColor`
- Consumes: `AppSettings.defaultBaseBranchColor`
- Produces: settings field key `base-branch-color`
- Produces: swatch key `base-branch-swatch`

- [ ] **Step 1: Write the failing editor test**

Update the existing timeline-color editor test:

```dart
expect(find.text('Base branch'), findsOneWidget);
expect(find.text('Main line (fixed)'), findsNothing);
expect(find.byKey(const Key('base-branch-color')), findsOneWidget);
expect(baseSwatch(), const Color(0xFF5CB270));

await tester.enterText(
  find.byKey(const Key('base-branch-color')),
  '#654321',
);
await tester.pumpAndSettle();
expect(saved.last.baseBranchColor, '#654321');
expect(baseSwatch(), const Color(0xFF654321));

await tester.enterText(find.byKey(const Key('base-branch-color')), '#65');
await tester.pumpAndSettle();
expect(saved.last.baseBranchColor, '#654321');
```

After tapping `reset-lane-colors`, also assert:

```dart
expect(saved.last.baseBranchColor, AppSettings.defaultBaseBranchColor);
expect(baseSwatch(), const Color(0xFF5CB270));
expect(
  tester
      .widget<TextField>(find.byKey(const Key('base-branch-color')))
      .controller
      ?.text,
  '#5CB270',
);
```

- [ ] **Step 2: Run the editor test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name 'the timeline colors editor applies hex edits and resets'
```

Expected: fails because `Base branch` and `base-branch-color` are absent.

- [ ] **Step 3: Replace the fixed row with the existing editable pattern**

Add one controller, dispose it, and validate edits with the existing parser:

```dart
late final _baseBranchColorField = TextEditingController(
  text: _settings.baseBranchColor,
);

void _changeBaseBranchColor(String value) {
  if (parseHexColor(value) == null) return;
  _change(
    _settings.copyWith(baseBranchColor: formatHexColor(value)),
  );
}
```

Update `_resetLaneColors()` to reset the base color and its controller together
with the existing palette:

```dart
_change(
  _settings.copyWith(
    baseBranchColor: AppSettings.defaultBaseBranchColor,
    laneColors: AppSettings.defaultLaneColors,
  ),
);
_baseBranchColorField.text = AppSettings.defaultBaseBranchColor;
```

Replace `Main line (fixed)` with a row containing:

```dart
Container(
  key: const Key('base-branch-swatch'),
  width: 20,
  height: 20,
  decoration: BoxDecoration(
    color:
        parseHexColor(_settings.baseBranchColor) ??
        AvatarService.defaultBaseBranchColor,
    borderRadius: BorderRadius.circular(5),
  ),
),
const SizedBox(width: 10),
SizedBox(
  width: 120,
  child: TextField(
    key: const Key('base-branch-color'),
    controller: _baseBranchColorField,
    onChanged: _changeBaseBranchColor,
    style: const TextStyle(
      color: Color(0xFFE8EAF2),
      fontSize: 11,
      fontFamily: 'monospace',
    ),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      border: OutlineInputBorder(),
    ),
  ),
),
const SizedBox(width: 10),
const Text(
  'Base branch',
  style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
),
```

Keep the existing palette rows unchanged and do not add a reusable row
component.

- [ ] **Step 4: Run the editor test and verify GREEN**

Run:

```bash
dart format lib/settings.dart test/app_test.dart
flutter test test/app_test.dart --plain-name 'the timeline colors editor applies hex edits and resets'
```

Expected: the editor test passes.

- [ ] **Step 5: Run full verification**

Run:

```bash
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass, analysis reports no issues, and the diff has no
whitespace errors.

- [ ] **Step 6: Commit**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: edit base branch color in settings"
```
