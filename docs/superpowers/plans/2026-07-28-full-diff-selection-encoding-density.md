# Full Diff Selection, Encoding, and Blame Density Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Full Diff file navigation visually consistent and keyboard-first, keep encoding labels stable across screens for the app lifetime, and render Blame at source-code density.

**Architecture:** Add one presentation-only row surface shared by file and History rows. Keep keyboard routing in `DiffScreen`, add a small app-lifetime encoding-kind cache injected into `FullDiffSessionController`, and reuse the source-row height constant in Blame metadata.

**Tech Stack:** Flutter 3.44, Dart, Material widgets, `ChangeNotifier`, Flutter widget tests

## Global Constraints

- General Diff, File, and Blame views show a 1px focus border on the selected file.
- History shows the 1px focus border only in the list that owns focus.
- Plain `↑` and `↓` move files in General Diff, File, and Blame; existing `⌘↑` and `⌘↓` remain.
- First-load encoding has no badge and never shows `Loading`.
- Encoding values are shared for the app process lifetime and refreshed in the background for working-tree files.
- Encoding cache entries contain only `FileContentKind`, never file bytes.
- Blame uses a 21px ordinary row, 20px avatar, and 3px commit rail.
- Existing History pane routing, popup keyboard priority, Blame column widths, and source syntax styling remain unchanged.
- Follow strict RED → GREEN → REFACTOR for every production change.

---

### Task 1: Shared selectable row surface

**Files:**
- Create: `lib/full_diff_selectable_row.dart`
- Create: `test/full_diff_selectable_row_test.dart`
- Modify: `lib/full_history_view.dart:181-207`
- Test: `test/full_diff_content_views_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class FullDiffSelectableRowSurface extends StatelessWidget {
    const FullDiffSelectableRowSurface({
      required this.selected,
      required this.focused,
      required this.child,
      super.key,
    });

    final bool selected;
    final bool focused;
    final Widget child;
  }
  ```
- Consumes: `fullDiffCanvas`, `fullDiffSelection`, and `fullDiffAccent` from `full_diff_theme.dart`.

- [ ] **Step 1: Write the failing component tests**

  Add `test/full_diff_selectable_row_test.dart` with three cases:

  ```dart
  testWidgets('selected focused row uses selection fill and accent border', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullDiffSelectableRowSurface(
          key: Key('surface'),
          selected: true,
          focused: true,
          child: Text('row'),
        ),
      ),
    );

    final decoration = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(const Key('surface')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .decoration as BoxDecoration;
    expect(decoration.color, fullDiffSelection);
    expect(decoration.border?.top.width, 1);
    expect(decoration.border?.top.color, fullDiffAccent);
  });
  ```

  Add equivalent assertions for selected/unfocused and unselected rows. The
  unfocused cases must have no border.

- [ ] **Step 2: Run the component test and verify RED**

  Run:

  ```bash
  flutter test test/full_diff_selectable_row_test.dart
  ```

  Expected: compilation fails because `FullDiffSelectableRowSurface` does not
  exist.

- [ ] **Step 3: Implement the presentation-only component**

  Create `lib/full_diff_selectable_row.dart`:

  ```dart
  import 'package:flutter/material.dart';

  import 'full_diff_theme.dart';

  class FullDiffSelectableRowSurface extends StatelessWidget {
    const FullDiffSelectableRowSurface({
      required this.selected,
      required this.focused,
      required this.child,
      super.key,
    });

    final bool selected;
    final bool focused;
    final Widget child;

    @override
    Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? fullDiffSelection : fullDiffCanvas,
        border: selected && focused
            ? Border.all(color: fullDiffAccent)
            : null,
      ),
      child: child,
    );
  }
  ```

- [ ] **Step 4: Replace the History row’s local decoration**

  Import `full_diff_selectable_row.dart` from `full_history_view.dart`. Replace
  only the outer `Container` and its `decoration` in `HistoryRow.build`; keep
  the existing `Padding` and its complete row contents unchanged:

  ```diff
   @override
-  Widget build(BuildContext context) => Container(
+  Widget build(BuildContext context) => FullDiffSelectableRowSurface(
     key: Key('history-row-${entry.commit.sha}'),
-    decoration: BoxDecoration(
-      color: selected ? fullDiffSelection : fullDiffCanvas,
-      border: focused ? Border.all(color: fullDiffAccent) : null,
-    ),
+    selected: selected,
+    focused: focused,
     child: Padding(
  ```

  Preserve the existing History content, keys, semantics, and padding inside
  the new surface.

- [ ] **Step 5: Update the History integration assertion**

  In `test/full_diff_content_views_test.dart`, focus the History list and assert
  the selected `FullDiffSelectableRowSurface` has `selected == true` and
  `focused == true`. Move focus away and assert only `focused` changes.

- [ ] **Step 6: Run focused tests and verify GREEN**

  Run:

  ```bash
  flutter test test/full_diff_selectable_row_test.dart test/full_diff_content_views_test.dart
  ```

  Expected: all tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/full_diff_selectable_row.dart lib/full_history_view.dart test/full_diff_selectable_row_test.dart test/full_diff_content_views_test.dart
  git commit -m "refactor: share full diff selection surface"
  ```

---

### Task 2: File selection border and plain-arrow navigation

**Files:**
- Modify: `lib/diff_screen.dart:89-111, 450-478, 530-590, 770-835`
- Test: `test/full_diff_workspace_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `FullDiffSelectableRowSurface` from Task 1.
- Produces: private `_StepPrimaryFileIntent` for unmodified arrow shortcuts.

- [ ] **Step 1: Write failing visual-state tests**

  Update the existing “selected rows and source state are not color-only” test
  in `test/full_diff_workspace_test.dart` to find the selected
  `FullDiffSelectableRowSurface` and assert:

  ```dart
  expect(surface.selected, isTrue);
  expect(surface.focused, isTrue);
  ```

  Add a History case that focuses `_fileListFocus`, verifies the selected file
  surface has `focused == true`, moves focus to History, and verifies the file
  surface has `focused == false`.

- [ ] **Step 2: Write the failing plain-arrow navigation test**

  In `test/full_diff_workspace_test.dart`, pump two files in
  `FullDiffView.diff`, move focus to `content-scrollable`, send
  `LogicalKeyboardKey.arrowDown`, and assert the second file becomes selected.
  Send `arrowUp` and assert the first file is restored.

  Extend the existing popup test to open the algorithm menu, send `arrowDown`,
  and assert the file selection does not change.

- [ ] **Step 3: Run the workspace tests and verify RED**

  Run:

  ```bash
  flutter test test/full_diff_workspace_test.dart
  ```

  Expected: the file row is not a shared surface and the unmodified arrow from
  content does not change files.

- [ ] **Step 4: Track file-list focus and use the shared surface**

  In `_DiffScreenState`, add `_fileListHasFocus`. Register a listener on
  `_fileListFocus` during `initState`, remove it during `dispose`, and rebuild
  only when the Boolean changes:

  ```dart
  void _handleFileListFocusChanged() {
    if (!mounted || _fileListHasFocus == _fileListFocus.hasFocus) return;
    setState(() => _fileListHasFocus = _fileListFocus.hasFocus);
  }
  ```

  Wrap every changed-file row in `FullDiffSelectableRowSurface`. Pass:

  ```dart
  selected: selected,
  focused: selected &&
      (state.view != FullDiffView.history || _fileListHasFocus),
  ```

  Keep the existing `selected-file-<path>` key on the shared surface.

- [ ] **Step 5: Add plain-arrow shortcuts without changing History routing**

  Add:

  ```dart
  class _StepPrimaryFileIntent extends Intent {
    const _StepPrimaryFileIntent(this.delta);
    final int delta;
  }
  ```

  Map unmodified `arrowUp` and `arrowDown` to this intent. Its action must call
  `_stepFile` only when `state.view != FullDiffView.history`. Keep the existing
  `_StepFileIntent` for `⌘↑` and `⌘↓`, including History.

- [ ] **Step 6: Run focused tests and verify GREEN**

  Run:

  ```bash
  flutter test test/full_diff_workspace_test.dart test/app_test.dart
  ```

  Expected: file borders, plain arrows, modifier arrows, History routing, and
  popup priority all pass.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/diff_screen.dart test/full_diff_workspace_test.dart test/app_test.dart
  git commit -m "feat: align full diff file selection navigation"
  ```

---

### Task 3: App-lifetime encoding cache and header placement

**Files:**
- Modify: `lib/full_diff_controller.dart:19-27, 52-180, 293-330, 600-690, 774-833`
- Modify: `lib/full_diff_header.dart:31-171, 501-528`
- Test: `test/full_diff_controller_test.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Produces:
  ```dart
  typedef EncodingCacheKey = ({
    String repositoryRoot,
    String revision,
    String path,
    String? oldPath,
    String? parent,
    FileDocumentSide side,
  });

  class FullDiffEncodingCache {
    FullDiffEncodingCache();
    static final FullDiffEncodingCache shared = FullDiffEncodingCache();

    FileContentKind? read(EncodingCacheKey key);
    void write(EncodingCacheKey key, FileContentKind kind);
  }
  ```
- `FullDiffSessionController` accepts optional
  `FullDiffEncodingCache? encodingCache`; production defaults to `shared`.
- `FullDiffSessionState.encodingLabel` returns `''` when neither current data
  nor cached kind exists.

- [ ] **Step 1: Write failing state and cache tests**

  In `test/full_diff_controller_test.dart`:

  1. Change the first loading assertion from `'Loading'` to `''`.
  2. Create one `FullDiffEncodingCache` and inject it into two controllers with
     the same repository root, commit, parent, and file. Finish the first load
     as UTF-8. Start the second with a pending content `Completer`; after files
     load but before content completes, assert `encodingLabel == 'UTF-8'`.
  3. Repeat with a working-tree file. Cache UTF-8, start a later load whose
     bytes contain NUL, assert UTF-8 appears first, then complete and assert
     `Binary`.
  4. Make the working-tree refresh throw and assert the cached UTF-8 label
     remains.

- [ ] **Step 2: Write failing header placement tests**

  In `test/full_diff_header_test.dart`:

  - Pump `encodingLabel: ''` and assert `encoding-badge` is absent.
  - Pump `encodingLabel: 'UTF-8'` and assert the badge exists after
    `file-summary-badge` inside the left file-info wrap.
  - Assert the right control wrap contains focus, editor, and view controls but
    not `encoding-badge`.

  Give both header badges explicit keys:

  ```dart
  const Key('file-summary-badge')
  const Key('encoding-badge')
  ```

- [ ] **Step 3: Run focused tests and verify RED**

  Run:

  ```bash
  flutter test test/full_diff_controller_test.dart test/full_diff_header_test.dart
  ```

  Expected: state still reports `Loading`, no app-lifetime encoding cache
  exists, and the badge remains in the right controls.

- [ ] **Step 4: Implement the lightweight shared cache**

  Add `FullDiffEncodingCache` and `EncodingCacheKey` to
  `full_diff_controller.dart`. Store only `FileContentKind`.

  Add `FileContentKind? cachedEncodingKind` to `FullDiffSessionState`. Resolve
  the label in this order:

  ```dart
  String get encodingLabel => switch (
    file.data?.kind ?? cachedEncodingKind
  ) {
    FileContentKind.utf8 => 'UTF-8',
    FileContentKind.binary => 'Binary',
    FileContentKind.unsupportedEncoding => 'Unsupported encoding',
    FileContentKind.tooLarge => 'Too large',
    null => '',
  };
  ```

  Build the cache key from repository root, resolved revision, current and old
  paths, parent, and side. Read it synchronously whenever a file becomes
  selected. During `_loadFile`, retain the cached kind while loading. After the
  request passes `_accepts`, write the new kind and replace state. Do not write
  from rejected late requests. On refresh error, keep `cachedEncodingKind`.

- [ ] **Step 5: Move the conditional badge into file information**

  Extend `_HeaderBadge` with `Key? controlKey` and apply it to the outer
  `Container`. Give the summary badge `file-summary-badge` and the main
  `FullDiffSegmentedControl<FullDiffView>` the key `main-view-controls`.

  Immediately after the summary badge in the left wrap, add:

  ```dart
  if (encodingLabel.isNotEmpty)
    _HeaderBadge(
      controlKey: const Key('encoding-badge'),
      label: encodingLabel,
      foreground: fullDiffAccent,
      background: fullDiffSelection,
    ),
  ```

  Remove the unconditional encoding badge from the right wrap.

- [ ] **Step 6: Add the workspace no-jitter contract**

  In `test/full_diff_workspace_test.dart`, begin with pending file content and
  record the left positions of `file-path-chip`, `file-summary-badge`,
  `focus-mode`, and `main-view-controls`. Complete UTF-8 loading and assert
  those positions are unchanged while `encoding-badge` appears after
  `file-summary-badge`.

- [ ] **Step 7: Run focused tests and verify GREEN**

  Run:

  ```bash
  flutter test test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
  ```

  Expected: all encoding, placement, error, and layout contracts pass.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/full_diff_controller.dart lib/full_diff_header.dart test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
  git commit -m "feat: cache and stabilize full diff encoding"
  ```

---

### Task 4: Source-density Blame rows

**Files:**
- Modify: `lib/full_diff_code_row.dart:10-18`
- Modify: `lib/full_blame_view.dart:145-237`
- Test: `test/full_diff_content_views_test.dart`
- Test: `test/full_diff_visual_test.dart`

**Interfaces:**
- Produces:
  ```dart
  const fullDiffSourceRowHeight = 21.0;
  ```
- Consumes: `fullDiffSourceRowHeight` for source text and Blame metadata.

- [ ] **Step 1: Update tests to the approved density and verify RED**

  Change the existing Blame assertions to require:

  ```dart
  expect(tester.getSize(find.byKey(const Key('blame-line-313'))).height, 21);
  expect(tester.getSize(find.byKey(const Key('blame-avatar-313'))), const Size(20, 20));
  expect(tester.getSize(find.byKey(const Key('blame-rail-313'))).width, 3);
  ```

  Add a wrapped-line case and assert it may grow beyond 21px while ordinary
  rows remain 21px.

- [ ] **Step 2: Run Blame tests and verify RED**

  Run:

  ```bash
  flutter test test/full_diff_content_views_test.dart test/full_diff_visual_test.dart
  ```

  Expected: ordinary rows are 44px, avatars are 22px, and rails are 4px.

- [ ] **Step 3: Share the source-row height and reduce Blame metadata**

  In `full_diff_code_row.dart`:

  ```dart
  const fullDiffSourceRowHeight = 21.0;

  const fullDiffSourceTextStyle = TextStyle(
    color: Colors.white,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
    fontSize: 12,
    height: fullDiffSourceRowHeight / 12,
  );
  ```

  In `full_blame_view.dart`, set metadata and rail height to
  `fullDiffSourceRowHeight`, rail width to `3`, avatar column width to `20`,
  and `IdentityAvatar.size` to `20`. Keep all horizontal metadata widths except
  the 1px rail reduction unchanged.

- [ ] **Step 4: Run Blame tests and verify GREEN**

  Run:

  ```bash
  flutter test test/full_diff_content_views_test.dart test/full_diff_visual_test.dart
  ```

  Expected: ordinary density is 21/20/3, wrapped rows grow correctly, and
  metadata ordering and syntax highlighting remain green.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/full_diff_code_row.dart lib/full_blame_view.dart test/full_diff_content_views_test.dart test/full_diff_visual_test.dart
  git commit -m "style: tighten full diff blame rows"
  ```

---

### Task 5: Full verification and direct-test launch

**Files:**
- Verify: all files changed in Tasks 1–4

**Interfaces:**
- Consumes: all completed behavior from Tasks 1–4.
- Produces: a clean, running macOS debug app for user testing.

- [ ] **Step 1: Format and analyze**

  Run:

  ```bash
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze
  ```

  Expected: formatter changes zero files and analysis reports zero issues.

- [ ] **Step 2: Run focused Full Diff suites**

  Run:

  ```bash
  flutter test test/full_diff_selectable_row_test.dart test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/full_diff_visual_test.dart test/app_test.dart
  ```

  Expected: all focused tests pass.

- [ ] **Step 3: Run both complete test configurations**

  Run:

  ```bash
  flutter test
  flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false
  ```

  Expected: both complete suites pass.

- [ ] **Step 4: Run visual and performance gates**

  Run:

  ```bash
  flutter test test/full_diff_visual_test.dart --reporter expanded
  flutter test --concurrency=1 benchmark/full_diff_syntax_benchmark_test.dart --reporter expanded
  ```

  Expected: all visual contracts and the syntax benchmark pass.

- [ ] **Step 5: Build macOS and inspect the branch**

  Run:

  ```bash
  flutter build macos --release
  git diff --check
  git status --short --branch
  ```

  Expected: release build succeeds, diff check is clean, and the worktree has
  no uncommitted changes.

- [ ] **Step 6: Start the directly testable app**

  If the existing debug session is still attached, send `R` for a hot restart.
  Otherwise run:

  ```bash
  flutter run -d macos
  ```

  Expected: Yogit opens with the completed branch and remains running for user
  testing.
