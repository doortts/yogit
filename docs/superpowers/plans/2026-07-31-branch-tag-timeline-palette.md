# Branch / Tag Timeline Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the five verified GitHub Enterprise label palettes to Branch / Tag chips and to the matching timeline graph rails, arrows, and nodes, with editable persistent settings.

**Architecture:** Store five Base/Text records in `AppSettings`. The timeline deterministically maps each ref name to one record, resolves one representative ref for each branch-line ID, and feeds that record's Text color into the existing `AvatarService.branchAssignments` path. Chip backgrounds and borders derive from the same record, so the graph painter remains the single rendering path for rails, curves, connectors, arrows, dots, and rings.

**Tech Stack:** Dart 3.12, Flutter 3.44, Flutter widget tests, existing `AppSettings`, `TimelineScreen`, `CommitGraphPainter`, and `AvatarService` code.

## Global Constraints

- Default records, in order: `#1D76DB/#68A7EA`, `#E99695/#E89292`, `#C5DEF5/#C2DDF4`, `#0E8A16/#18E022`, `#5319E7/#DACFFA`.
- Chip background uses Base at 18%; chip border uses Text at 30%; glyph, text, graph rail, curve, connector, arrow, dot, and ring use Text at 100%.
- The stable index is the positive `hash = hash * 31 + codeUnit` result modulo five; do not use `String.hashCode`.
- Representative ref priority is HEAD, local branch, remote branch, tag, then log-only decoration; equal-priority names sort lexically.
- A branch beats a tag on the same commit. Secondary ref chips still use their own name-derived records.
- Ref-less lines keep the existing base/lane fallback colors. Conflict and virtual preview colors stay unchanged.
- Do not add dependencies or split the existing large files as part of this change.
- Design reference: `docs/superpowers/specs/2026-07-31-branch-tag-timeline-palette-design.md`.

---

### Task 1: Persist and validate the five palette records

**Files:**
- Modify: `lib/settings.dart:259-520`
- Test: `test/app_test.dart:5498-5572`

**Interfaces:**
- Produces: `typedef RefPaletteEntry = ({String base, String text});`
- Produces: `AppSettings.defaultRefPalette`, `AppSettings.refPalette`, and `AppSettings.refPaletteColorValues`
- Produces JSON key: `refPalette`, encoded as a five-item list of `{base, text}` maps

- [ ] **Step 1: Write the failing settings model test**

Add this test beside the existing lane-color round-trip test:

```dart
test('branch tag palette round-trips and rejects damaged records', () {
  expect(AppSettings.defaultRefPalette, const [
    (base: '#1D76DB', text: '#68A7EA'),
    (base: '#E99695', text: '#E89292'),
    (base: '#C5DEF5', text: '#C2DDF4'),
    (base: '#0E8A16', text: '#18E022'),
    (base: '#5319E7', text: '#DACFFA'),
  ]);

  const custom = AppSettings(
    refPalette: [
      (base: '#010203', text: '#A0B0C0'),
      (base: '#111213', text: '#D0E0F0'),
      (base: '#212223', text: '#102030'),
      (base: '#313233', text: '#405060'),
      (base: '#414243', text: '#708090'),
    ],
  );
  expect(AppSettings.fromJson(custom.toJson()), custom);
  expect(custom.refPaletteColorValues.first, (
    base: const Color(0xFF010203),
    text: const Color(0xFFA0B0C0),
  ));

  for (final stored in [
    <Object>[],
    [const {'base': '#112233', 'text': 'bad'}],
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
});
```

- [ ] **Step 2: Run the focused test and confirm the missing API failure**

Run:

```bash
flutter test test/app_test.dart --plain-name "branch tag palette round-trips and rejects damaged records"
```

Expected: compile failure because `refPalette`, `defaultRefPalette`, and `refPaletteColorValues` do not exist.

- [ ] **Step 3: Add the minimal settings model**

Add the record type near the other settings value types:

```dart
typedef RefPaletteEntry = ({String base, String text});
typedef RefPaletteColors = ({Color base, Color text});
```

Add the defaults and field to `AppSettings`:

```dart
static const defaultRefPalette = <RefPaletteEntry>[
  (base: '#1D76DB', text: '#68A7EA'),
  (base: '#E99695', text: '#E89292'),
  (base: '#C5DEF5', text: '#C2DDF4'),
  (base: '#0E8A16', text: '#18E022'),
  (base: '#5319E7', text: '#DACFFA'),
];

final List<RefPaletteEntry> refPalette;

List<RefPaletteColors> get refPaletteColorValues {
  final values = [
    for (final entry in refPalette)
      (base: parseHexColor(entry.base), text: parseHexColor(entry.text)),
  ];
  if (values.length != defaultRefPalette.length ||
      values.any((entry) => entry.base == null || entry.text == null)) {
    return const AppSettings().refPaletteColorValues;
  }
  return [
    for (final entry in values)
      (base: entry.base!, text: entry.text!),
  ];
}
```

Use `this.refPalette = defaultRefPalette` in the constructor. Add `refPalette` to `copyWith`, equality, and `hashCode`. Parse only exactly five valid records in `fromJson`; otherwise use `defaultRefPalette`:

```dart
final storedRefPalette = value['refPalette'];
final refPalette = <RefPaletteEntry>[
  if (storedRefPalette is List)
    for (final entry in storedRefPalette)
      if (entry is Map)
        (
          base: formatHexColor('${entry['base'] ?? ''}'),
          text: formatHexColor('${entry['text'] ?? ''}'),
        ),
];
final validRefPalette =
    refPalette.length == defaultRefPalette.length &&
    refPalette.every(
      (entry) =>
          parseHexColor(entry.base) != null &&
          parseHexColor(entry.text) != null,
    );
```

Serialize it without a custom codec:

```dart
'refPalette': [
  for (final entry in refPalette) {'base': entry.base, 'text': entry.text},
],
```

- [ ] **Step 4: Run the focused settings test**

Run:

```bash
flutter test test/app_test.dart --plain-name "branch tag palette round-trips and rejects damaged records"
```

Expected: PASS.

- [ ] **Step 5: Commit the settings model**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: persist branch tag palette"
```

---

### Task 2: Resolve ref colors and feed the existing graph color path

**Files:**
- Modify: `lib/avatars.dart:291-304`
- Modify: `lib/timeline.dart:537-583, 1177-1184, 4645-4718`
- Test: `test/app_test.dart:9990-10120, 10335-10420`

**Interfaces:**
- Consumes: `RefPaletteEntry` and `RefPaletteColors` from Task 1
- Produces: `stableRefPaletteIndex(String name, int length) -> int`
- Produces: `refPaletteColorsForName(String name, List<RefPaletteEntry> palette) -> RefPaletteColors`
- Produces: `timelineRefsForCommit(GitCommit commit, RepoRefs refs) -> List<GitRef>`
- Produces: `branchRefNames(List<GraphRow> rows, RepoRefs refs) -> Map<int, String>`
- Extends: `assignBranchColors(..., {Map<int, String> branchNames, List<RefPaletteEntry> refPalette})`

- [ ] **Step 1: Write failing pure tests for stable mapping and ref priority**

Add these tests near the graph color tests:

```dart
test('ref palette mapping is stable and covers all five records', () {
  expect(
    [for (final name in ['d', 'e', 'a', 'b', 'c'])
      stableRefPaletteIndex(name, 5)],
    [0, 1, 2, 3, 4],
  );
  expect(
    refPaletteColorsForName('d', AppSettings.defaultRefPalette),
    (
      base: const Color(0xFF1D76DB),
      text: const Color(0xFF68A7EA),
    ),
  );
});

test('timeline refs prefer HEAD, local, remote, tag, then decoration', () {
  final value = timelineRefsForCommit(
    commit(
      'tip',
      'tip',
      refs: const [GitRef(name: 'log-only')],
    ),
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
```

- [ ] **Step 2: Write the failing graph assignment test**

```dart
test('named branch lines use the representative ref text color', () {
  final rows = layoutGraph([
    commit('tip', 'tip', refs: const [GitRef(name: 'd', isHead: true)]),
  ]);
  final names = branchRefNames(
    rows,
    const RepoRefs(
      local: ['d'],
      current: 'd',
      tips: {'d': 'tip'},
    ),
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
```

- [ ] **Step 3: Run the focused tests and confirm the missing helper failures**

Run:

```bash
flutter test test/app_test.dart --plain-name "ref palette mapping is stable and covers all five records"
flutter test test/app_test.dart --plain-name "timeline refs prefer HEAD, local, remote, tag, then decoration"
flutter test test/app_test.dart --plain-name "named branch lines use the representative ref text color"
```

Expected: compile failures for the new helper functions and parameters.

- [ ] **Step 4: Implement stable palette lookup and ordered ref merging**

Add these top-level helpers to `timeline.dart` near `assignBranchColors`:

```dart
int stableRefPaletteIndex(String name, int length) {
  var hash = 0;
  for (final codeUnit in name.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % length;
}

RefPaletteColors refPaletteColorsForName(
  String name,
  List<RefPaletteEntry> palette,
) {
  final valid = palette.length == AppSettings.defaultRefPalette.length &&
          palette.every(
            (entry) =>
                parseHexColor(entry.base) != null &&
                parseHexColor(entry.text) != null,
          )
      ? palette
      : AppSettings.defaultRefPalette;
  final entry = valid[stableRefPaletteIndex(name, valid.length)];
  return (
    base: parseHexColor(entry.base)!,
    text: parseHexColor(entry.text)!,
  );
}
```

Implement `timelineRefsForCommit` by merging log decorations with `RepoRefs.tips`, OR-ing `isHead`/`isTag` flags for duplicate names, and sorting with this priority function:

```dart
int refPriority(GitRef ref, RepoRefs refs) {
  if (ref.isHead || ref.name == refs.current) return 0;
  if (refs.local.contains(ref.name)) return 1;
  if (refs.remote.contains(ref.name)) return 2;
  if (ref.isTag || refs.tags.contains(ref.name)) return 3;
  return 4;
}
```

Use this merge and ordering implementation:

```dart
List<GitRef> timelineRefsForCommit(GitCommit commit, RepoRefs refs) {
  final byName = <String, GitRef>{};
  void add(GitRef ref) {
    final previous = byName[ref.name];
    byName[ref.name] = GitRef(
      name: ref.name,
      isHead: ref.isHead || previous?.isHead == true,
      isTag: ref.isTag || previous?.isTag == true,
    );
  }

  for (final ref in commit.refs) {
    add(ref);
  }
  if (commit.sha.isNotEmpty) {
    for (final entry in refs.tips.entries) {
      if (entry.value != commit.sha) continue;
      add(
        GitRef(
          name: entry.key,
          isHead: entry.key == refs.current,
          isTag: refs.tags.contains(entry.key),
        ),
      );
    }
  }
  final result = byName.values.toList();
  result.sort((left, right) {
    final priority = refPriority(left, refs).compareTo(
      refPriority(right, refs),
    );
    return priority != 0 ? priority : left.name.compareTo(right.name);
  });
  return result;
}

Map<int, String> branchRefNames(List<GraphRow> rows, RepoRefs refs) {
  final names = <int, String>{};
  for (final row in rows) {
    if (names.containsKey(row.branch)) continue;
    final rowRefs = timelineRefsForCommit(row.commit, refs);
    if (rowRefs.isNotEmpty) names[row.branch] = rowRefs.first.name;
  }
  return names;
}
```

Use `timelineRefsForCommit(commit, _refs)` in the normal branch of `_rowRefs`. Keep the existing comparison-preview branch unchanged.

- [ ] **Step 5: Extend branch assignment without replacing its fallback**

Add optional `branchNames` and `refPalette` parameters to `assignBranchColors`. Before the current branch-0 and pool logic, assign the named branch's Text color:

```dart
final name = branchNames[id];
if (name != null) {
  colors[id] = refPaletteColorsForName(name, refPalette).text;
  continue;
}
```

Make configured assignments win for branch 0 in `AvatarService.branchColor`:

```dart
static Color branchColor(int branch) {
  final assigned = branchAssignments[branch];
  if (assigned != null) return assigned;
  if (branch == 0) return baseBranchColor;
  final colors = palette.isEmpty ? defaultColors : palette;
  return colors[(branch.abs() - 1) % colors.length];
}
```

In `_rebuildGraph`, pass `branchRefNames(_normalRows, _refs)` and `widget.refPalette`. Add `refPalette` to `TimelineScreen`, defaulting to `AppSettings.defaultRefPalette`, and rebuild when it changes in `didUpdateWidget`.

```dart
this.refPalette = AppSettings.defaultRefPalette,

final List<RefPaletteEntry> refPalette;
```

```dart
AvatarService.branchAssignments = assignBranchColors(
  _normalRows,
  widget.repository.root.hashCode,
  branchNames: branchRefNames(_normalRows, _refs),
  refPalette: widget.refPalette,
);
```

In `didUpdateWidget`, add this independent check after the existing column and preview settings updates:

```dart
if (!listEquals(widget.refPalette, oldWidget.refPalette)) {
  _rebuildGraph();
}
```

- [ ] **Step 6: Run the focused graph tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "ref palette mapping is stable and covers all five records"
flutter test test/app_test.dart --plain-name "timeline refs prefer HEAD, local, remote, tag, then decoration"
flutter test test/app_test.dart --plain-name "named branch lines use the representative ref text color"
```

Expected: PASS.

- [ ] **Step 7: Commit deterministic graph colors**

```bash
git add lib/avatars.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: color graph lines by ref palette"
```

---

### Task 3: Render exact chips and expose the palette editor

**Files:**
- Modify: `lib/settings.dart:560-620, 819-980`
- Modify: `lib/timeline.dart:594-675, 5389-5535, 5570-5635`
- Modify: `lib/main.dart:285-345`
- Test: `test/app_test.dart:5285-5340, 6290-6375`

**Interfaces:**
- Consumes: `AppSettings.refPalette` and `refPaletteColorsForName` from Tasks 1-2
- Produces widget keys: `ref-palette-chip-N`, `ref-palette-base-N`, `ref-palette-text-N`, `reset-ref-palette`
- Preserves widget keys: `ref-chip-SHA-NAME` and `graph-painter-N`

- [ ] **Step 1: Write the failing chip/graph widget test**

```dart
testWidgets('ref chip and graph use the same palette text color', (tester) async {
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

  final decoration = tester
      .widget<Container>(find.byKey(const Key('ref-chip-tip-d')))
      .decoration! as BoxDecoration;
  expect(
    decoration.color,
    const Color(0xFF1D76DB).withValues(alpha: .18),
  );
  expect(
    decoration.border!.top.color,
    const Color(0xFF68A7EA).withValues(alpha: .30),
  );
  final painter = tester
      .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
      .painter! as CommitGraphPainter;
  expect(painter.committerColor, const Color(0xFF68A7EA));
});
```

- [ ] **Step 2: Write the failing palette editor test**

```dart
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
  expect(
    decoration.color,
    const Color(0xFF1D76DB).withValues(alpha: .18),
  );
  expect(
    decoration.border!.top.color,
    const Color(0xFF68A7EA).withValues(alpha: .30),
  );

  await tester.enterText(
    find.byKey(const Key('ref-palette-base-0')),
    '#010203',
  );
  await tester.enterText(
    find.byKey(const Key('ref-palette-text-0')),
    '#A0B0C0',
  );
  await tester.pump();
  expect(saved.last.refPalette.first, (
    base: '#010203',
    text: '#A0B0C0',
  ));

  await tester.enterText(
    find.byKey(const Key('ref-palette-base-0')),
    '#01',
  );
  await tester.pump();
  expect(saved.last.refPalette.first.base, '#010203');

  await tester.tap(find.byKey(const Key('reset-ref-palette')));
  await tester.pump();
  expect(saved.last.refPalette, AppSettings.defaultRefPalette);
});
```

- [ ] **Step 3: Run the focused widget tests and confirm failure**

Run:

```bash
flutter test test/app_test.dart --plain-name "ref chip and graph use the same palette text color"
flutter test test/app_test.dart --plain-name "branch tag palette editor applies Base and Text and resets"
```

Expected: FAIL because chips still use the old branch color treatment and the editor keys do not exist.

- [ ] **Step 4: Render normal ref chips from their Base/Text record**

In `_refChip`, use the name-derived record when `_comparison == null`:

```dart
final colors = refPaletteColorsForName(ref.name, widget.refPalette);
final background = _comparison == null
    ? colors.base.withValues(alpha: .18)
    : color.withValues(alpha: .14);
final border = _comparison == null
    ? colors.text.withValues(alpha: .30)
    : color.withValues(alpha: .55);
final foreground = _comparison == null ? colors.text : color;
```

Apply `foreground` to `_refGlyph` and `_refName`. Keep the comparison-preview branch on its existing special color. In `_refsModal`, resolve colors inside the loop so each secondary ref keeps its own Text color. Keep the connector and painter on the representative branch color from Task 2.

- [ ] **Step 5: Add the five-row settings editor**

Create one Base and one Text `TextEditingController` per palette record. Dispose all ten controllers. Add `_changeRefPalette(index, base:, text:)` that ignores invalid partial hex input and `_resetRefPalette()` that updates both settings and controller text.

```dart
late final _refPaletteFields = [
  for (final entry in _settings.refPalette)
    (
      base: TextEditingController(text: entry.base),
      text: TextEditingController(text: entry.text),
    ),
];

void _changeRefPalette(int index, {String? base, String? text}) {
  final current = _settings.refPalette[index];
  final next = (
    base: formatHexColor(base ?? current.base),
    text: formatHexColor(text ?? current.text),
  );
  if (parseHexColor(next.base) == null || parseHexColor(next.text) == null) {
    return;
  }
  final palette = [..._settings.refPalette]..[index] = next;
  _change(_settings.copyWith(refPalette: palette));
}

void _resetRefPalette() {
  _change(_settings.copyWith(refPalette: AppSettings.defaultRefPalette));
  for (var index = 0; index < _refPaletteFields.length; index++) {
    _refPaletteFields[index].base.text =
        AppSettings.defaultRefPalette[index].base;
    _refPaletteFields[index].text.text =
        AppSettings.defaultRefPalette[index].text;
  }
}
```

Dispose them with:

```dart
for (final fields in _refPaletteFields) {
  fields.base.dispose();
  fields.text.dispose();
}
```

Under `Timeline colors`, add `Branch / Tag palette`, five preview chips, Base/Text fields, and a separate reset button. Use the widget keys defined above. Build each preview with:

```dart
final colors = _settings.refPaletteColorValues[index];
BoxDecoration(
  color: colors.base.withValues(alpha: .18),
  border: Border.all(color: colors.text.withValues(alpha: .30)),
  borderRadius: BorderRadius.circular(5),
)
```

Build the two fields in the same indexed row:

```dart
for (var index = 0; index < _refPaletteFields.length; index++)
  Row(
    children: [
      Container(
        key: Key('ref-palette-chip-$index'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _settings.refPaletteColorValues[index].base
              .withValues(alpha: .18),
          border: Border.all(
            color: _settings.refPaletteColorValues[index].text
                .withValues(alpha: .30),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          'Color ${index + 1}',
          style: TextStyle(
            color: _settings.refPaletteColorValues[index].text,
            fontSize: 11,
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 100,
        child: TextField(
          key: Key('ref-palette-base-$index'),
          controller: _refPaletteFields[index].base,
          onChanged: (value) => _changeRefPalette(index, base: value),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 100,
        child: TextField(
          key: Key('ref-palette-text-$index'),
          controller: _refPaletteFields[index].text,
          onChanged: (value) => _changeRefPalette(index, text: value),
        ),
      ),
    ],
  ),
```

Use `TextButton(key: const Key('reset-ref-palette'), onPressed: _resetRefPalette, child: const Text('Reset to defaults'))` for the separate reset action. Reuse the existing dense monospace `TextField` decoration from the lane editor when applying this block; do not create a second input style.

Leave the existing Base branch and lane controls below it as the ref-less fallback editor.

- [ ] **Step 6: Pass settings through the app root**

In `YogitApp.build`, add:

```dart
refPalette: _settings.refPalette,
```

No new global mutable palette is needed; `TimelineScreen` owns the new records and continues to publish only resolved branch Text colors through `AvatarService.branchAssignments`.

- [ ] **Step 7: Run the focused widget tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "ref chip and graph use the same palette text color"
flutter test test/app_test.dart --plain-name "branch tag palette editor applies Base and Text and resets"
```

Expected: PASS.

- [ ] **Step 8: Commit rendering and settings UI**

```bash
git add lib/settings.dart lib/timeline.dart lib/main.dart test/app_test.dart
git commit -m "feat: render branch tag palette"
```

---

### Task 4: Verify source values, raster output, and regressions

**Files:**
- Modify only if verification finds a mismatch: `lib/settings.dart`, `lib/timeline.dart`, `lib/avatars.dart`, `test/app_test.dart`
- Temporary output outside the repository: `/tmp/yogit-palette-verification.png`

**Interfaces:**
- Consumes the completed feature; produces no new runtime API.

- [ ] **Step 1: Run static analysis and the complete test suite**

Run:

```bash
flutter analyze
flutter test
```

Expected: both commands exit 0 with no failures.

- [ ] **Step 2: Create a five-color sample repository without writing fixture files**

Run:

```bash
palette_repo=$(mktemp -d /tmp/yogit-palette-XXXXXX)
git -C "$palette_repo" init -b main
git -C "$palette_repo" config user.name "Palette Test"
git -C "$palette_repo" config user.email "palette@example.com"
git -C "$palette_repo" commit --allow-empty -m "base"
for branch in d e a b c; do
  git -C "$palette_repo" switch -c "$branch" main
  git -C "$palette_repo" commit --allow-empty -m "$branch palette"
done
git -C "$palette_repo" switch d
```

The one-letter names map to palette indexes 0-4 in this order: `d`, `e`, `a`, `b`, `c`.

- [ ] **Step 3: Launch the app and capture the real macOS window**

Run the app with the sample repository:

```bash
flutter run -d macos -- "$palette_repo"
```

After the window shows all five refs, capture it from another terminal command:

```bash
screencapture -x /tmp/yogit-palette-verification.png
```

Open `/tmp/yogit-palette-verification.png` with the image viewer. Confirm that every representative chip, connector, arrow, rail, and node uses one hue together and that secondary rails remain readable.

- [ ] **Step 4: Check the exact flat pixel colors against the verified CSS tokens**

With the default System Graphite row background `#1C1C1E`, run this one-off pixel scan:

```bash
python3 -c "from PIL import Image; p=Image.open('/tmp/yogit-palette-verification.png').convert('RGB'); px=list(p.getdata()); bg=(28,28,30); pairs=[('blue',(29,118,219),(104,167,234)),('red',(233,150,149),(232,146,146)),('silver',(197,222,245),(194,221,244)),('green',(14,138,22),(24,224,34)),('purple',(83,25,231),(218,207,250))]; blend=lambda c,a: tuple(round(c[i]*a+bg[i]*(1-a)) for i in range(3)); near=lambda c: sum(all(abs(v[i]-c[i])<=1 for i in range(3)) for v in px); result={n:{'base18':near(blend(b,.18)),'text30':near(blend(t,.30)),'text100':near(t)} for n,b,t in pairs}; print(result); assert all(all(count>0 for count in counts.values()) for counts in result.values()), result"
```

Expected: each of the five entries reports a positive count for `base18`, `text30`, and `text100`; the command exits 0. The ±1 channel tolerance covers raster rounding only.

- [ ] **Step 5: Correct and repeat if any value or visual relationship differs**

If the scan fails or the screenshot shows a mismatched chip/line relationship, fix the shared palette selection or opacity at its source. Re-run the two focused widget tests, `flutter analyze`, `flutter test`, the screenshot, and the pixel scan until all pass. Do not patch individual rows or painters.

- [ ] **Step 6: Commit verification corrections only when needed**

If Step 5 changed code:

```bash
git add lib/settings.dart lib/timeline.dart lib/avatars.dart test/app_test.dart
git commit -m "fix: align timeline palette rendering"
```

If no code changed, do not create an empty commit. Remove only the temporary sample repository and screenshot after recording the verification result.
