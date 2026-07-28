# Full Diff Git Algorithm Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the effective repository Git diff algorithm in Full Diff, mark that algorithm as the current Git setting without duplicating it in the chooser, and reload the displayed patch whenever the user selects an algorithm.

**Architecture:** Add a repository-level value object that resolves `diff.algorithm` to one of the four concrete Git algorithms while retaining whether the value came from Git's default. Store that result in `FullDiffSessionState`, keep `DiffAlgorithm.gitSetting` as the internal selection source, and let the chooser map four concrete visible rows back to either `gitSetting` or an explicit algorithm. Reuse the controller's existing patch reload and rollback path.

**Tech Stack:** Dart 3, Flutter Material, `flutter_test`, real temporary Git repositories

## Global Constraints

- The closed control displays only `Myers`, `Minimal`, `Patience`, or `Histogram`.
- The chooser displays exactly four algorithm rows and never a separate `Git setting` row.
- The algorithm matching `diff.algorithm` carries `현재 Git 설정` in its details pane.
- An unset or `default` setting resolves to Myers and carries `현재 Git 설정 · Git 기본값`.
- Selecting the Git-configured row omits `--diff-algorithm`; selecting another row passes its explicit Git argument.
- A failed patch reload restores the last successful document and selection.
- Do not monitor Git config changes while an existing Full Diff session remains open.
- Do not change or commit the user's unrelated files in the main checkout.

---

## File Structure

- `lib/git.dart`: own the concrete algorithm list, parsed Git setting value, repository contract, and Git command.
- `lib/full_diff_controller.dart`: load the repository setting once per session and expose effective requested/applied algorithms.
- `lib/full_diff_algorithm_chooser.dart`: render four concrete rows and translate them to internal selections.
- `lib/full_diff_header.dart`: pass the resolved Git setting from the toolbar to the chooser.
- `lib/diff_screen.dart`: connect controller state to the toolbar and unavailable-state algorithm label.
- `test/support/full_diff_fixtures.dart`: provide deterministic Git settings to controller and widget tests.
- `test/git_test.dart`: verify pure setting parsing and selection mapping.
- `test/full_diff_git_test.dart`: verify repository config resolution with real temporary repositories.
- `test/full_diff_controller_test.dart`: verify initialization normalization, effective labels, reload, and rollback.
- `test/full_diff_header_test.dart`: verify the four-row chooser, current-setting details, semantics, and callbacks.
- `test/full_diff_workspace_test.dart`: verify an algorithm choice replaces the visible patch and returning to the configured row uses Git settings.
- `test/full_diff_widgets_test.dart`, `test/app_test.dart`, `test/full_diff_visual_test.dart`: update existing expectations that currently expose `Git setting`.

---

### Task 1: Resolve the repository's effective Git diff algorithm

**Files:**
- Modify: `lib/git.dart:580-727`
- Modify: `lib/git.dart:927-957`
- Modify: `test/support/full_diff_fixtures.dart:9-105`
- Modify: `test/git_test.dart:450-470`
- Modify: `test/full_diff_git_test.dart:235-345`

**Interfaces:**
- Produces:
  - `const concreteDiffAlgorithms: List<DiffAlgorithm>`
  - `GitDiffAlgorithmSetting`
  - `parseGitDiffAlgorithmSetting(String? value)`
  - `FullDiffRepository.loadDiffAlgorithmSetting()`
- Consumes: the existing `CommandRunner`, `GitRepository.root`, and `GitRepository.gitExecutable`.

- [ ] **Step 1: Write pure parsing and selection-mapping tests**

Add focused tests in `test/git_test.dart`:

```dart
test('resolves Git diff algorithm settings to concrete choices', () {
  final unset = parseGitDiffAlgorithmSetting(null);
  expect(unset.algorithm, DiffAlgorithm.myers);
  expect(unset.usesGitDefault, isTrue);
  expect(unset.configLabel, 'diff.algorithm 미설정');

  for (final entry in {
    'default': DiffAlgorithm.myers,
    'MYERS': DiffAlgorithm.myers,
    'minimal': DiffAlgorithm.minimal,
    'patience': DiffAlgorithm.patience,
    'histogram': DiffAlgorithm.histogram,
  }.entries) {
    expect(parseGitDiffAlgorithmSetting(entry.key).algorithm, entry.value);
  }

  const histogram = GitDiffAlgorithmSetting(
    algorithm: DiffAlgorithm.histogram,
    configuredValue: 'histogram',
  );
  expect(
    histogram.normalizeSelection(DiffAlgorithm.histogram),
    DiffAlgorithm.gitSetting,
  );
  expect(
    histogram.resolveSelection(DiffAlgorithm.gitSetting),
    DiffAlgorithm.histogram,
  );
});

test('rejects unsupported Git diff algorithm settings', () {
  expect(
    () => parseGitDiffAlgorithmSetting('unknown'),
    throwsA(isA<FormatException>()),
  );
});
```

- [ ] **Step 2: Run the parsing tests and verify RED**

Run:

```bash
flutter test test/git_test.dart --plain-name 'resolves Git diff algorithm settings to concrete choices'
flutter test test/git_test.dart --plain-name 'rejects unsupported Git diff algorithm settings'
```

Expected: compilation fails because `GitDiffAlgorithmSetting` and `parseGitDiffAlgorithmSetting` do not exist.

- [ ] **Step 3: Implement the concrete setting value**

Add beside `DiffAlgorithm` in `lib/git.dart`:

```dart
const concreteDiffAlgorithms = <DiffAlgorithm>[
  DiffAlgorithm.myers,
  DiffAlgorithm.minimal,
  DiffAlgorithm.patience,
  DiffAlgorithm.histogram,
];

class GitDiffAlgorithmSetting {
  const GitDiffAlgorithmSetting({
    required this.algorithm,
    required this.configuredValue,
  });

  const GitDiffAlgorithmSetting.gitDefault()
    : algorithm = DiffAlgorithm.myers,
      configuredValue = null;

  final DiffAlgorithm algorithm;
  final String? configuredValue;

  bool get usesGitDefault =>
      configuredValue == null || configuredValue == 'default';

  String get configLabel => configuredValue == null
      ? 'diff.algorithm 미설정'
      : 'diff.algorithm=$configuredValue';

  DiffAlgorithm normalizeSelection(DiffAlgorithm selection) =>
      selection == DiffAlgorithm.gitSetting || selection == algorithm
      ? DiffAlgorithm.gitSetting
      : selection;

  DiffAlgorithm resolveSelection(DiffAlgorithm selection) =>
      selection == DiffAlgorithm.gitSetting ? algorithm : selection;
}

GitDiffAlgorithmSetting parseGitDiffAlgorithmSetting(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    null || '' => const GitDiffAlgorithmSetting.gitDefault(),
    'default' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.myers,
      configuredValue: 'default',
    ),
    'myers' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.myers,
      configuredValue: 'myers',
    ),
    'minimal' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.minimal,
      configuredValue: 'minimal',
    ),
    'patience' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.patience,
      configuredValue: 'patience',
    ),
    'histogram' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    ),
    _ => throw FormatException('Unsupported diff.algorithm: $value'),
  };
}
```

Keep `DiffAlgorithm.gitSetting` and its empty `gitArguments` so patch loading can still ask Git to honor config.

- [ ] **Step 4: Run the parsing tests and verify GREEN**

Run:

```bash
flutter test test/git_test.dart --plain-name 'resolves Git diff algorithm settings to concrete choices'
flutter test test/git_test.dart --plain-name 'rejects unsupported Git diff algorithm settings'
```

Expected: both pass.

- [ ] **Step 5: Write real-repository config tests**

Add tests in `test/full_diff_git_test.dart`:

```dart
test('reads the effective repository diff algorithm setting', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  final repository = GitRepository(root.path);

  final unset = await repository.loadDiffAlgorithmSetting();
  expect(unset.algorithm, DiffAlgorithm.myers);
  expect(unset.usesGitDefault, isTrue);

  await runGit(root, ['config', 'diff.algorithm', 'histogram']);
  final configured = await repository.loadDiffAlgorithmSetting();
  expect(configured.algorithm, DiffAlgorithm.histogram);
  expect(configured.configuredValue, 'histogram');
});

test('rejects an unsupported repository diff algorithm setting', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await runGit(root, ['config', 'diff.algorithm', 'unknown']);

  await expectLater(
    GitRepository(root.path).loadDiffAlgorithmSetting(),
    throwsA(isA<FormatException>()),
  );
});
```

- [ ] **Step 6: Run the repository tests and verify RED**

Run:

```bash
flutter test test/full_diff_git_test.dart --plain-name 'reads the effective repository diff algorithm setting'
flutter test test/full_diff_git_test.dart --plain-name 'rejects an unsupported repository diff algorithm setting'
```

Expected: compilation fails because `loadDiffAlgorithmSetting` is not defined.

- [ ] **Step 7: Add the repository contract and Git command**

Add to `FullDiffRepository`:

```dart
Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting();
```

Implement in `GitRepository` by calling the injected `runner` directly so exit code `1` can mean "unset":

```dart
@override
Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting() async {
  const args = ['config', '--get', 'diff.algorithm'];
  final result = await runner(gitExecutable, args, workingDirectory: root);
  final value = result.stdout.toString().trim();
  if (result.exitCode == 1 && value.isEmpty) {
    return const GitDiffAlgorithmSetting.gitDefault();
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      gitExecutable,
      args,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return parseGitDiffAlgorithmSetting(value);
}
```

Extend `FakeFullDiffRepository`:

```dart
GitDiffAlgorithmSetting gitDiffAlgorithmSetting =
    const GitDiffAlgorithmSetting.gitDefault();
Future<GitDiffAlgorithmSetting> Function()? diffAlgorithmSetting;
int diffAlgorithmSettingRequests = 0;

@override
Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting() {
  diffAlgorithmSettingRequests++;
  return diffAlgorithmSetting?.call() ??
      Future.value(gitDiffAlgorithmSetting);
}
```

- [ ] **Step 8: Run focused and adjacent tests**

Run:

```bash
flutter test test/git_test.dart test/full_diff_git_test.dart
```

Expected: all pass.

- [ ] **Step 9: Commit Task 1**

```bash
git add lib/git.dart test/support/full_diff_fixtures.dart test/git_test.dart test/full_diff_git_test.dart
git commit -m "feat: resolve repository diff algorithm setting"
```

---

### Task 2: Track effective algorithms and preserve patch reload behavior

**Files:**
- Modify: `lib/full_diff_controller.dart:78-235`
- Modify: `lib/full_diff_controller.dart:301-419`
- Modify: `lib/full_diff_controller.dart:665-690`
- Modify: `lib/full_diff_controller.dart:880-985`
- Modify: `test/full_diff_controller_test.dart:340-390`
- Modify: `test/full_diff_controller_test.dart:1580-1614`

**Interfaces:**
- Consumes:
  - `FullDiffRepository.loadDiffAlgorithmSetting()`
  - `GitDiffAlgorithmSetting.normalizeSelection()`
  - `GitDiffAlgorithmSetting.resolveSelection()`
- Produces:
  - `FullDiffSessionState.gitDiffAlgorithmSetting`
  - `FullDiffSessionState.requestedConcreteAlgorithm`
  - `FullDiffSessionState.appliedConcreteAlgorithm`

- [ ] **Step 1: Write controller initialization tests**

Add to `test/full_diff_controller_test.dart`:

```dart
test('initializes the effective Git algorithm and normalizes duplicates', () async {
  final repository = FakeFullDiffRepository()
    ..gitDiffAlgorithmSetting = const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    )
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, _, _) async => twoHunkLines)
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n')));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialPreferences: const FullDiffPreferences(
      algorithm: DiffAlgorithm.histogram,
    ),
  );
  addTearDown(controller.dispose);

  await controller.initialize();

  expect(repository.diffAlgorithmSettingRequests, 1);
  expect(controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
  expect(
    controller.state.appliedConcreteAlgorithm,
    DiffAlgorithm.histogram,
  );
  expect(
    repository.diffRequests.single.algorithm,
    DiffAlgorithm.gitSetting,
  );
});
```

Add the failure case:

```dart
test('reports a Git algorithm setting load failure before loading files', () async {
  final repository = FakeFullDiffRepository()
    ..diffAlgorithmSetting = (() async =>
        throw const FormatException('unsupported diff.algorithm'));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);

  await controller.initialize();

  expect(controller.state.filesResource.error, isA<FormatException>());
  expect(repository.fileRequests, isEmpty);
  expect(repository.diffRequests, isEmpty);
});
```

- [ ] **Step 2: Run the initialization tests and verify RED**

Run:

```bash
flutter test test/full_diff_controller_test.dart --plain-name 'initializes the effective Git algorithm and normalizes duplicates'
```

Expected: compilation fails because the state has no Git setting or concrete algorithm getters.

- [ ] **Step 3: Add Git setting state and initialization**

Add `gitDiffAlgorithmSetting` to `FullDiffSessionState`, its constructor, `copyWith`, and `_initialState`, using `const GitDiffAlgorithmSetting.gitDefault()` before the async lookup finishes.

Add:

```dart
DiffAlgorithm get requestedConcreteAlgorithm =>
    gitDiffAlgorithmSetting.resolveSelection(requestedAlgorithm);

DiffAlgorithm get appliedConcreteAlgorithm =>
    gitDiffAlgorithmSetting.resolveSelection(appliedAlgorithm);
```

Replace `initialize()` with:

```dart
Future<void> initialize() async {
  try {
    final setting = await repository.loadDiffAlgorithmSetting();
    if (_disposed) return;
    final normalized = setting.normalizeSelection(state.appliedAlgorithm);
    _replace(
      state.copyWith(
        gitDiffAlgorithmSetting: setting,
        requestedAlgorithm: normalized,
        appliedAlgorithm: normalized,
      ),
    );
  } catch (error) {
    if (!_disposed) {
      _replace(state.copyWith(filesResource: AsyncResource(error: error)));
    }
    return;
  }
  await _loadFiles();
}
```

The normalized selection must be set before `_loadFiles()` so the first patch request uses `gitSetting` when the saved explicit algorithm duplicates the repository setting.

- [ ] **Step 4: Run the initialization tests and verify GREEN**

Run:

```bash
flutter test test/full_diff_controller_test.dart --plain-name 'initializes the effective Git algorithm and normalizes duplicates'
flutter test test/full_diff_controller_test.dart --plain-name 'reports a Git algorithm setting load failure before loading files'
```

Expected: both pass.

- [ ] **Step 5: Write reload and rollback tests**

Add a test whose fake returns different `DiffLine` lists for `gitSetting` and `patience`:

```dart
test('algorithm selection replaces the patch and Git setting restores it', () async {
  final repository = FakeFullDiffRepository()
    ..gitDiffAlgorithmSetting = const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    )
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, algorithm, _) async => algorithm == DiffAlgorithm.patience
        ? const [
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.add, text: 'patience', newNumber: 1),
          ]
        : twoHunkLines)
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n')));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  await controller.selectAlgorithm(DiffAlgorithm.patience);
  expect(controller.state.patch.data!.rows.last.text, 'patience');
  expect(controller.state.appliedConcreteAlgorithm, DiffAlgorithm.patience);

  await controller.selectAlgorithm(DiffAlgorithm.gitSetting);
  expect(controller.state.patch.data!.hunks, hasLength(2));
  expect(repository.diffRequests.last.algorithm, DiffAlgorithm.gitSetting);
  expect(controller.state.appliedConcreteAlgorithm, DiffAlgorithm.histogram);
});
```

Extend the existing failed-option test with:

```dart
expect(
  controller.state.appliedConcreteAlgorithm,
  DiffAlgorithm.myers,
);
```

- [ ] **Step 6: Run the reload tests and verify RED/GREEN**

Run the new test before implementation changes to confirm its new concrete-algorithm assertions fail, then run after the state getters are present:

```bash
flutter test test/full_diff_controller_test.dart --plain-name 'algorithm selection replaces the patch and Git setting restores it'
flutter test test/full_diff_controller_test.dart --plain-name 'failed options restore the last successful patch and controls'
```

Expected after implementation: both pass.

- [ ] **Step 7: Run the controller suite**

```bash
flutter test test/full_diff_controller_test.dart
```

Expected: all pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/full_diff_controller.dart test/full_diff_controller_test.dart
git commit -m "feat: track effective full diff algorithm"
```

---

### Task 3: Render four unique algorithm rows and refresh the visible diff

**Files:**
- Modify: `lib/full_diff_algorithm_chooser.dart:7-375`
- Modify: `lib/full_diff_header.dart:198-272`
- Modify: `lib/diff_screen.dart:1051-1089`
- Modify: `lib/diff_screen.dart:1550-1670`
- Modify: `test/full_diff_header_test.dart:136-240`
- Modify: `test/full_diff_header_test.dart:543-590`
- Modify: `test/full_diff_workspace_test.dart:3405-3466`
- Modify: `test/full_diff_widgets_test.dart:60-120`
- Modify: `test/app_test.dart` assertions containing `Git setting`
- Modify: `test/full_diff_visual_test.dart` algorithm chooser expectations

**Interfaces:**
- Consumes:
  - `concreteDiffAlgorithms`
  - `GitDiffAlgorithmSetting.algorithm`
  - `GitDiffAlgorithmSetting.usesGitDefault`
  - `GitDiffAlgorithmSetting.configLabel`
  - `GitDiffAlgorithmSetting.normalizeSelection()`
  - `FullDiffSessionState.appliedConcreteAlgorithm`
- Produces:
  - `FullDiffAlgorithmChooser.gitDiffAlgorithmSetting`
  - `GlobalDiffToolbar.gitDiffAlgorithmSetting`

- [ ] **Step 1: Replace chooser expectations with the four-row contract**

Update/add tests in `test/full_diff_header_test.dart`:

```dart
testWidgets('shows four concrete algorithms and marks the Git setting', (
  tester,
) async {
  await pumpHeaders(
    tester,
    algorithm: DiffAlgorithm.gitSetting,
    gitDiffAlgorithmSetting: const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    ),
  );

  expect(find.text('Histogram'), findsOneWidget);
  expect(find.text('Git setting'), findsNothing);

  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();

  for (final algorithm in concreteDiffAlgorithms) {
    expect(
      find.byKey(Key('algorithm-option-${algorithm.name}')),
      findsOneWidget,
    );
  }
  expect(find.byKey(const Key('algorithm-option-gitSetting')), findsNothing);
  expect(find.text('현재 Git 설정'), findsOneWidget);
  expect(find.text('diff.algorithm=histogram'), findsOneWidget);
});
```

Add these focused cases:

```dart
testWidgets('shows Git default details on Myers', (tester) async {
  await pumpHeaders(
    tester,
    algorithm: DiffAlgorithm.gitSetting,
    gitDiffAlgorithmSetting: const GitDiffAlgorithmSetting.gitDefault(),
  );
  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();

  expect(find.text('현재 Git 설정 · Git 기본값'), findsOneWidget);
  expect(find.text('diff.algorithm 미설정'), findsOneWidget);
});

testWidgets('keeps applied selection separate from the current Git setting', (
  tester,
) async {
  DiffAlgorithm? selected;
  await pumpHeaders(
    tester,
    algorithm: DiffAlgorithm.patience,
    gitDiffAlgorithmSetting: const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    ),
    onAlgorithmSelected: (value) => selected = value,
  );
  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();

  expect(
    tester
        .getSemantics(find.byKey(const Key('algorithm-option-patience')))
        .getSemanticsData()
        .flagsCollection
        .isSelected,
    ui.Tristate.isTrue,
  );
  final histogram = find.byKey(const Key('algorithm-option-histogram'));
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer();
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(histogram));
  await tester.pump();
  expect(find.text('현재 Git 설정'), findsOneWidget);

  await tester.tap(histogram);
  await tester.pumpAndSettle();
  expect(selected, DiffAlgorithm.gitSetting);
});

testWidgets('returns an explicit enum for a non-configured row', (
  tester,
) async {
  DiffAlgorithm? selected;
  await pumpHeaders(
    tester,
    algorithm: DiffAlgorithm.gitSetting,
    gitDiffAlgorithmSetting: const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    ),
    onAlgorithmSelected: (value) => selected = value,
  );
  expect(
    find.semantics.byLabel('diff 알고리즘: Histogram'),
    findsOneWidget,
  );

  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('algorithm-option-patience')));
  await tester.pumpAndSettle();

  expect(selected, DiffAlgorithm.patience);
});
```

- [ ] **Step 2: Run chooser tests and verify RED**

Run:

```bash
flutter test test/full_diff_header_test.dart --plain-name 'shows four concrete algorithms and marks the Git setting'
```

Expected: the test fails because the chooser still renders five enum values and the button says `Git setting`.

- [ ] **Step 3: Refactor the chooser around concrete rows**

Change `diffAlgorithmDetails` to hold only the four concrete algorithms.

Add `gitDiffAlgorithmSetting` to `FullDiffAlgorithmChooser`. Resolve the displayed button value with:

```dart
final displayedAlgorithm = widget.gitDiffAlgorithmSetting
    .resolveSelection(widget.algorithm);
```

Pass the setting into `_AlgorithmChooserEntry`. In its state:

- build focus nodes from `concreteDiffAlgorithms`;
- initialize preview/focus to the resolved applied algorithm;
- move focus through `concreteDiffAlgorithms`;
- use concrete algorithm keys, labels, details, and selection checks;
- map a concrete row back with
  `widget.gitDiffAlgorithmSetting.normalizeSelection(algorithm)` before
  `Navigator.pop`;
- render the following above the existing description only when the preview
  matches the configured concrete algorithm:

```dart
Text(
  widget.gitDiffAlgorithmSetting.usesGitDefault
      ? '현재 Git 설정 · Git 기본값'
      : '현재 Git 설정',
  key: const Key('current-git-algorithm'),
),
const SizedBox(height: 4),
Text(widget.gitDiffAlgorithmSetting.configLabel),
const SizedBox(height: 8),
```

Use the concrete displayed algorithm for the button text, semantics label, semantics hint, and details key.

- [ ] **Step 4: Thread the setting through the toolbar and screen**

Add this field to `GlobalDiffToolbar` and pass it to the chooser:

```dart
final GitDiffAlgorithmSetting gitDiffAlgorithmSetting;
```

In `DiffScreen`, pass:

```dart
gitDiffAlgorithmSetting: state.gitDiffAlgorithmSetting,
algorithm: state.appliedAlgorithm,
```

For `FullDiffUnavailablePanel`, pass `state.requestedConcreteAlgorithm` instead
of `state.requestedAlgorithm` so the no-change status never prints the internal
`Git setting` label.

Update `pumpHeaders` with a deterministic setting parameter:

```dart
GitDiffAlgorithmSetting gitDiffAlgorithmSetting =
    const GitDiffAlgorithmSetting.gitDefault(),
```

- [ ] **Step 5: Run chooser tests and verify GREEN**

```bash
flutter test test/full_diff_header_test.dart
```

Expected: all pass.

- [ ] **Step 6: Write the end-to-end workspace refresh test**

Add to `test/full_diff_workspace_test.dart`:

```dart
testWidgets('algorithm rows reload the visible patch and Git row restores config', (
  tester,
) async {
  final repository = FakeFullDiffRepository()
    ..gitDiffAlgorithmSetting = const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    )
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, algorithm, _) async => [
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      DiffLine(
        kind: DiffLineKind.add,
        text: algorithm == DiffAlgorithm.patience
            ? 'patience patch'
            : 'histogram patch',
        newNumber: 1,
      ),
    ])
    ..content = ((_, _, _) async => resultFile.bytes);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  await pumpWorkspace(
    tester,
    controller: controller,
    size: const Size(1200, 800),
  );

  expect(find.text('histogram patch'), findsOneWidget);
  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('algorithm-option-patience')));
  await tester.pumpAndSettle();
  expect(find.text('patience patch'), findsOneWidget);
  expect(repository.diffRequests.last.algorithm, DiffAlgorithm.patience);

  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('algorithm-option-histogram')));
  await tester.pumpAndSettle();
  expect(find.text('histogram patch'), findsOneWidget);
  expect(repository.diffRequests.last.algorithm, DiffAlgorithm.gitSetting);
});
```

- [ ] **Step 7: Run the workspace test and verify RED/GREEN**

Run once before wiring the callback mapping to confirm the configured row
returns the wrong explicit enum, then run after Step 4:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name 'algorithm rows reload the visible patch and Git row restores config'
```

Expected after implementation: pass.

- [ ] **Step 8: Update affected assertions and run adjacent suites**

Replace visible `Git setting` expectations with the effective algorithm in:

- `test/full_diff_widgets_test.dart`;
- `test/app_test.dart`;
- `test/full_diff_visual_test.dart`;
- the existing failed-algorithm workspace test.

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_widgets_test.dart
flutter test test/full_diff_workspace_test.dart
flutter test test/app_test.dart test/full_diff_visual_test.dart
```

Expected: all pass with no `Git setting` text in production Full Diff UI.

- [ ] **Step 9: Commit Task 3**

```bash
git add lib/full_diff_algorithm_chooser.dart lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/full_diff_widgets_test.dart test/app_test.dart test/full_diff_visual_test.dart
git commit -m "feat: show effective Git diff algorithm"
```

---

### Task 4: Format, verify, and prepare the merge

**Files:**
- Verify all modified Dart files.
- Verify branch history against `main`.

**Interfaces:**
- Consumes: all behavior from Tasks 1-3.
- Produces: a clean, tested feature branch ready for merge.

- [ ] **Step 1: Format changed Dart files**

```bash
dart format lib/git.dart lib/full_diff_controller.dart lib/full_diff_algorithm_chooser.dart lib/full_diff_header.dart lib/diff_screen.dart test/support/full_diff_fixtures.dart test/git_test.dart test/full_diff_git_test.dart test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/full_diff_widgets_test.dart test/app_test.dart test/full_diff_visual_test.dart
```

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Run the complete test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Inspect the final diff and branch state**

```bash
git diff --check
git status --short
git log --oneline main..HEAD
git diff --stat main...HEAD
```

Expected: no unstaged changes, only the design, plan, implementation, and test commits for this feature.

- [ ] **Step 5: Commit formatting changes only if needed**

If formatting changed tracked files after Task 3:

```bash
git add lib test
git commit -m "style: format full diff algorithm changes"
```

If the worktree is already clean, do not create an empty commit.

- [ ] **Step 6: Merge into main from the primary checkout**

After invoking `superpowers:finishing-a-development-branch` and confirming the
feature branch is clean:

```bash
git -C /Users/doortts/repos/yogit merge --ff-only codex/full-diff-git-algorithm-display
```

Run the focused tests from the merged `main` checkout if the primary checkout's
uncommitted user files do not overlap the feature paths. Preserve those files
without staging or modifying them.
