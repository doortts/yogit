# Sidebar Section Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved thin-section-bar design to the sidebar and keep the search outline subdued until focus.

**Architecture:** Keep the change local to `TimelineScreen`. The existing timeline palette supplies every color, while widget tests inspect the rendered widget configuration before production styling is added.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Use mockup A, the thin section bar.
- Derive every color from the selected `TimelineThemePalette`.
- Preserve collapse behavior, counts, tree spacing below headers, filtering, and tag overflow behavior.
- Do not add a theme token, dependency, or reusable widget.

---

### Task 1: Style the sidebar search and category headers

**Files:**
- Modify: `lib/timeline.dart:2128-2250`
- Test: `test/app_test.dart:2208-2300`

**Interfaces:**
- Consumes: `TimelineThemePalette.border`, `TimelineThemePalette.interactive`, `TimelineThemePalette.raised`, `TimelineThemePalette.text`
- Produces: keyed category surfaces named `sidebar-section-band-<section>` and explicit search field outline states

- [ ] **Step 1: Write the failing search-outline test**

Add a widget test that pumps the real `TimelineScreen` through the existing
`app(...)` helper and inspects the `ref-filter` field:

```dart
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
```

- [ ] **Step 2: Write the failing category-band test**

Add a second widget test with one local branch and assert the local section's
real decoration:

```dart
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
  expect(
    border.top.color,
    palette.border.withValues(alpha: 0.7),
  );
  expect(border.bottom, border.top);
});
```

- [ ] **Step 3: Run both tests and verify that they fail for the missing styles**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'sidebar search stays subdued until focus'
flutter test test/app_test.dart \
  --plain-name 'sidebar category headers use thin raised section bars'
```

Expected:

- The search test fails because `enabledBorder` and `focusedBorder` are null.
- The category test fails because `sidebar-section-band-local` does not exist.

- [ ] **Step 4: Add explicit search outline states**

In the existing `InputDecoration`, preserve the current radius and add:

```dart
enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(5),
  borderSide: BorderSide(color: _palette.border),
),
focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(5),
  borderSide: BorderSide(color: _palette.interactive),
),
```

Keep the existing `border` as the fallback outline.

- [ ] **Step 5: Replace the plain category wrapper with the approved band**

At the start of `_refSection`, derive:

```dart
final headerColor = _palette.text.withValues(alpha: 0.82);
```

Keep the existing outer vertical spacing and replace the inner `SizedBox` with:

```dart
Container(
  key: Key('sidebar-section-band-${section.name}'),
  height: 20,
  padding: const EdgeInsets.symmetric(horizontal: 4),
  decoration: BoxDecoration(
    color: _palette.raised.withValues(alpha: 0.7),
    border: Border.symmetric(
      horizontal: BorderSide(
        color: _palette.border.withValues(alpha: 0.7),
      ),
    ),
  ),
  child: Row(
    // Preserve the current children and use headerColor for the chevron,
    // category icon, label, and count.
  ),
)
```

The production row must keep the existing keys, labels, counts, collapse tap
handler, and overflow behavior.

- [ ] **Step 6: Run the focused tests and the existing sidebar tree test**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'sidebar search stays subdued until focus'
flutter test test/app_test.dart \
  --plain-name 'sidebar category headers use thin raised section bars'
flutter test test/app_test.dart \
  --plain-name 'sidebar lists refs as collapsible trees, filters them, and moves the selection'
```

Expected: all three pass.

- [ ] **Step 7: Format and verify the complete project**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter analyze
flutter test
flutter build macos --debug
```

Expected: formatting makes no unwanted changes, analysis reports no issues, all
tests pass, and the macOS debug app builds.

- [ ] **Step 8: Commit the implementation**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "style: refine sidebar section hierarchy"
```
