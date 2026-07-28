# 저장소별 그래프 컬럼 폭 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 그래프 자동 폭이 해시 컬러선 앞에 최소 3픽셀을 남기게 하고, 사용자가 조절한 폭은 저장소별로 저장·복원한다.

**Architecture:** `AppSettings`가 저장소 루트별 그래프 폭과 이전 설정 변환을 맡는다. `YogitApp`은 현재 저장소에 맞는 `TimelineColumnWidths`만 `TimelineScreen`에 전달하고, `TimelineScreen`은 저장 구조를 모른 채 기존 자동·수동 폭 동작을 유지한다.

**Tech Stack:** Flutter, Dart, `SettingsStore` JSON 설정, Flutter 위젯 테스트

## Global Constraints

- 저장소별 그래프 폭 키는 Git이 확인한 절대 저장소 루트 경로를 그대로 사용한다.
- 그래프 컬럼 수동 폭은 40~260픽셀로 제한한다.
- 저장소별 수동 폭이 없을 때만 자동 맞춤을 사용한다.
- 자동 맞춤은 지름 22픽셀인 가장 오른쪽 커밋 노드와 해시 컬럼 왼쪽 컬러선 사이에 최소 3픽셀을 남긴다.
- 기존 전역 그래프 폭은 업데이트 후 처음 연 저장소의 수동 폭으로 한 번 이전한다.
- 다른 타임라인 컬럼과 Full Diff 설정의 저장 방식은 바꾸지 않는다.
- 사용자가 수정한 `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md`와 `.superpowers/brainstorm/`은 건드리지 않는다.

---

## 파일 구성

- `lib/settings.dart`: 저장소별 그래프 폭의 직렬화, 범위 제한, 이전 설정 변환, 현재 저장소에 적용할 컬럼 폭 계산
- `lib/main.dart`: 현재 저장소 루트를 기준으로 폭을 적용하고 수동 변경을 저장
- `lib/timeline.dart`: 자동 폭 계산에 3픽셀 여백 반영
- `test/app_test.dart`: 설정, 이전, 저장소별 복원, 자동 폭의 화면 동작 검증

### Task 1: 저장소별 그래프 폭 설정 모델

**Files:**
- Modify: `lib/settings.dart:12-123`
- Modify: `lib/settings.dart:201-346`
- Test: `test/app_test.dart:2457-2515`

**Interfaces:**
- Produces: `TimelineColumnWidths.withGraph(double? graph)`
- Produces: `AppSettings.repositoryGraphWidths`
- Produces: `AppSettings.columnWidthsForRepository(String root)`
- Produces: `AppSettings.withRepositoryColumnWidths(String root, TimelineColumnWidths widths)`
- Produces: `AppSettings.migrateLegacyGraphWidth(String root)`

- [ ] **Step 1: 저장소별 폭 직렬화와 범위 제한 테스트 작성**

`test/app_test.dart`의 컬럼 설정 테스트 옆에 다음 테스트를 추가한다.

```dart
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/app_test.dart --plain-name "repository graph widths round-trip and discard damaged entries"
```

Expected: `AppSettings.repositoryGraphWidths`가 없어서 컴파일 실패

- [ ] **Step 3: 설정 모델과 JSON 변환 구현**

`TimelineColumnWidths`에 `graph`를 명시적으로 `null`로 바꿀 수 있는 메서드를 추가한다.

```dart
TimelineColumnWidths withGraph(double? value) => TimelineColumnWidths(
  sidebar: sidebar,
  refs: refs,
  graph: value,
  hash: hash,
  commit: commit,
  time: time,
  name: name,
  showTime: showTime,
  showName: showName,
);
```

`AppSettings` 생성자, 필드, `copyWith`, `fromJson`, `toJson`, 동등성 비교와 해시에 `repositoryGraphWidths`를 추가한다. JSON을 읽을 때는 다음 헬퍼로 손상된 항목만 제외한다.

```dart
Map<String, double> _parseRepositoryGraphWidths(Object? value) {
  if (value is! Map) return const {};
  final result = <String, double>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! num) continue;
    final root = (entry.key as String).trim();
    if (root.isEmpty) continue;
    result[root] = (entry.value as num)
        .toDouble()
        .clamp(40.0, 260.0)
        .toDouble();
  }
  return result;
}
```

새 필드는 다음 기본값과 JSON 키를 사용한다.

```dart
this.repositoryGraphWidths = const {},

final Map<String, double> repositoryGraphWidths;

'repositoryGraphWidths': repositoryGraphWidths,
```

`toJson()`은 이전 형식의 전역 폭을 다시 기록하지 않도록 공통 컬럼을 `columnWidths.withGraph(null)`로 직렬화한다.

동등성에는 `mapEquals`, 해시에는 키 순서와 무관한 `Object.hashAllUnordered`를 사용한다.

- [ ] **Step 4: 현재 저장소 적용·저장·이전 동작 테스트 작성**

```dart
test('repository graph widths stay independent and migrate legacy width once', () {
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
  expect(changed.repositoryGraphWidths, {
    '/repo/a': 176,
    '/repo/b': 204,
  });
  expect(changed.columnWidths.graph, isNull);

  final mixed = AppSettings(
    columnWidths: const TimelineColumnWidths(graph: 150),
    repositoryGraphWidths: const {'/repo/existing': 190},
  ).migrateLegacyGraphWidth('/repo/new');
  expect(mixed.columnWidths.graph, isNull);
  expect(mixed.repositoryGraphWidths, {'/repo/existing': 190});
});
```

- [ ] **Step 5: 저장소별 설정 메서드 구현**

```dart
TimelineColumnWidths columnWidthsForRepository(String root) =>
    columnWidths.withGraph(repositoryGraphWidths[root]);

AppSettings withRepositoryColumnWidths(
  String root,
  TimelineColumnWidths widths,
) {
  final graphWidths = {...repositoryGraphWidths};
  final graph = widths.graph;
  if (root.trim().isNotEmpty && graph != null) {
    graphWidths[root] = graph.clamp(40.0, 260.0).toDouble();
  }
  return copyWith(
    columnWidths: widths.withGraph(null),
    repositoryGraphWidths: graphWidths,
  );
}

AppSettings migrateLegacyGraphWidth(String root) {
  final legacy = columnWidths.graph;
  if (legacy == null) return this;
  final graphWidths = {...repositoryGraphWidths};
  if (graphWidths.isEmpty && root.trim().isNotEmpty) {
    graphWidths[root] = legacy;
  }
  return copyWith(
    columnWidths: columnWidths.withGraph(null),
    repositoryGraphWidths: graphWidths,
  );
}
```

- [ ] **Step 6: 기존 설정 파일 저장 테스트를 새 형식에 맞게 수정**

`settings persist only the supported fields` 테스트는 `TimelineColumnWidths(graph: 220)`을 직접 저장한 뒤 전역 `graph`가 빠지는지 확인하도록 바꾼다.

```dart
await store.save(saved);
final restored = await store.load();
expect(restored.showAvatars, isFalse);
expect(restored.previewPlacement, PreviewPlacement.bottom);
expect(restored.columnWidths.graph, isNull);
expect(
  jsonDecode(await store.file.readAsString())['columnWidths'],
  isNot(contains('graph')),
);
```

- [ ] **Step 7: 설정 단위 테스트 실행**

Run:

```bash
flutter test test/app_test.dart --plain-name "repository graph widths"
flutter test test/app_test.dart --plain-name "column widths round-trip"
```

Expected: 새 테스트와 기존 컬럼 설정 테스트 모두 통과

- [ ] **Step 8: 설정 모델 변경 커밋**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: store graph widths per repository"
```

### Task 2: 앱에서 저장소별 폭 적용과 이전 설정 저장

**Files:**
- Modify: `lib/main.dart:191-317`
- Test: `test/app_test.dart:4590-4708`
- Test: `test/app_test.dart:5057-5210`

**Interfaces:**
- Consumes: `AppSettings.columnWidthsForRepository(String root)`
- Consumes: `AppSettings.withRepositoryColumnWidths(String root, TimelineColumnWidths widths)`
- Consumes: `AppSettings.migrateLegacyGraphWidth(String root)`

- [ ] **Step 1: 앱 재시작과 저장소 분리 동작을 검증하는 위젯 테스트 작성**

`MemorySettingsStore`를 재사용해 저장소 A에서 수동 폭을 저장한 뒤 앱을 다시 만들고 A와 B의 폭을 비교한다.

```dart
testWidgets('YogitApp restores manual graph width only for its repository', (
  tester,
) async {
  final store = MemorySettingsStore();
  GitRepository repository(String root) => FakeGitRepository(
    (_, _) async => [commit('1', root)],
    root: root,
  );
  double graphWidth() =>
      tester.getSize(find.byKey(const Key('graph-header'))).width;

  await tester.pumpWidget(YogitApp(
    repository: repository('/repo/a'),
    settingsStore: store,
    discoverAvatars: false,
    windowFrameController: controller,
  ));
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const Key('graph-resizer')),
    const Offset(44, 0),
  );
  await tester.pumpAndSettle();
  final savedA = graphWidth();
  expect(store.current.repositoryGraphWidths['/repo/a'], savedA);

  await tester.pumpWidget(YogitApp(
    key: const Key('restart-a'),
    repository: repository('/repo/a'),
    settingsStore: store,
    discoverAvatars: false,
    windowFrameController: controller,
  ));
  await tester.pumpAndSettle();
  expect(graphWidth(), savedA);

  await tester.pumpWidget(YogitApp(
    key: const Key('open-b'),
    repository: repository('/repo/b'),
    settingsStore: store,
    discoverAvatars: false,
    windowFrameController: controller,
  ));
  await tester.pumpAndSettle();
  expect(graphWidth(), 96);
});
```

- [ ] **Step 2: 앱 수준 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/app_test.dart --plain-name "YogitApp restores manual graph width only for its repository"
```

Expected: 수동 폭이 여전히 전역 `columnWidths.graph`에 저장되어 B에도 적용되므로 실패

- [ ] **Step 3: 현재 저장소에 맞는 폭을 적용하고 저장**

`YogitApp.build`에서 다음처럼 현재 루트에 맞는 폭만 전달한다.

```dart
columnWidths: _settings.columnWidthsForRepository(_repository.root),
```

수동 변경 콜백은 현재 저장소 값으로 저장한다.

```dart
onColumnWidthsChanged: _settingsLoaded
    ? (widths) => _changeSettings(
        _settings.withRepositoryColumnWidths(_repository.root, widths),
      )
    : null,
```

- [ ] **Step 4: 이전 전역 폭을 한 번 저장하는 테스트 작성**

```dart
testWidgets('YogitApp migrates legacy graph width to the first repository', (
  tester,
) async {
  final store = MemorySettingsStore()
    ..current = const AppSettings(
      columnWidths: TimelineColumnWidths(graph: 180),
    );

  await tester.pumpWidget(YogitApp(
    repository: FakeGitRepository(
      (_, _) async => [commit('1', 'first')],
      root: '/repo/first',
    ),
    settingsStore: store,
    discoverAvatars: false,
    windowFrameController: controller,
  ));
  await tester.pumpAndSettle();

  expect(store.current.columnWidths.graph, isNull);
  expect(store.current.repositoryGraphWidths, {'/repo/first': 180});
  expect(tester.getSize(find.byKey(const Key('graph-header'))).width, 180);
});
```

- [ ] **Step 5: 설정을 읽을 때 이전 형식을 변환하고 저장**

`_loadSettings`에서 설정을 화면에 적용하기 전에 변환한다.

```dart
Future<void> _loadSettings() async {
  final loaded = await _store.load();
  final settings = loaded.migrateLegacyGraphWidth(_repository.root);
  if (!mounted) return;
  setState(() {
    AvatarService.palette = settings.laneColorValues;
    _settings = settings;
    _settingsLoaded = true;
  });
  if (settings != loaded) {
    _save = _save.then((_) => _store.save(settings)).catchError((_) {});
  }
}
```

- [ ] **Step 6: 앱 수준 설정 테스트 실행**

Run:

```bash
flutter test test/app_test.dart --plain-name "YogitApp restores manual graph width only for its repository"
flutter test test/app_test.dart --plain-name "YogitApp migrates legacy graph width to the first repository"
flutter test test/app_test.dart --plain-name "persisted avatar opt-out wins before remote lookup starts"
flutter test test/app_test.dart --plain-name "the folder button opens a picked repository"
```

Expected: 네 테스트 모두 통과

- [ ] **Step 7: 앱 연결 변경 커밋**

```bash
git add lib/main.dart test/app_test.dart
git commit -m "feat: restore repository graph widths"
```

### Task 3: 자동 폭의 3픽셀 여백

**Files:**
- Modify: `lib/timeline.dart:525-532`
- Modify: `lib/timeline.dart:1970-2030`
- Modify: `lib/timeline.dart:3572-3602`
- Test: `test/app_test.dart:1320-1425`
- Test: `test/app_test.dart:5681-5744`

**Interfaces:**
- Produces: `CommitGraphPainter.avatarDiameter`
- Produces: `CommitGraphPainter.hashRailClearance`
- Updates: `CommitGraphPainter.nodeExtent`

- [ ] **Step 1: 자동 폭 여백 테스트를 먼저 작성**

`CommitGraphPainter`의 자동 폭이 노드 오른쪽 끝 뒤에 3픽셀을 남기는지 직접 검증한다.

```dart
test('graph auto-fit leaves three pixels before the hash rail', () {
  const deepestLane = 3;
  final laneCenter =
      CommitGraphPainter.laneInset +
      deepestLane * CommitGraphPainter.defaultLaneSpacing;
  final nodeRight =
      laneCenter + CommitGraphPainter.avatarDiameter / 2;

  expect(
    CommitGraphPainter.contentWidth(deepestLane) - nodeRight,
    CommitGraphPainter.hashRailClearance,
  );
  expect(CommitGraphPainter.hashRailClearance, 3);
});
```

기존 예상 폭도 새 계산값으로 바꾼다.

```dart
expect(columnWidth('graph'), 102);
expect(graphWidth(), 102);
expect(graphWidth(), 132);
```

관련 설명의 `+ 13`도 `+ 14`로 고친다.

- [ ] **Step 2: 여백 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/app_test.dart --plain-name "graph auto-fit leaves three pixels before the hash rail"
flutter test test/app_test.dart --plain-name "the graph column fits the deepest lane until it is dragged"
flutter test test/app_test.dart --plain-name "the graph column ratchets to the lanes it has shown"
```

Expected: 새 상수가 없거나 기존 자동 폭이 1픽셀 작아서 실패

- [ ] **Step 3: 노드 크기와 여백을 한곳에서 계산**

`CommitGraphPainter`에 다음 상수를 추가하고 `nodeExtent`를 계산식으로 바꾼다.

```dart
static const avatarDiameter = 22.0;
static const hashRailClearance = 3.0;
static const nodeExtent = avatarDiameter / 2 + hashRailClearance;
```

`_rowContent`의 로컬 `avatarSize`도 같은 값을 사용한다.

```dart
const avatarSize = CommitGraphPainter.avatarDiameter;
```

자동 폭의 최소·최대 범위와 수동 폭 계산은 바꾸지 않는다.

- [ ] **Step 4: 그래프 자동·수동 폭 테스트 실행**

Run:

```bash
flutter test test/app_test.dart --plain-name "graph auto-fit leaves three pixels before the hash rail"
flutter test test/app_test.dart --plain-name "timeline columns fill the viewport"
flutter test test/app_test.dart --plain-name "the graph column fits the deepest lane until it is dragged"
flutter test test/app_test.dart --plain-name "the graph column ratchets to the lanes it has shown"
flutter test test/app_test.dart --plain-name "preferred preview placement and column widths are applied"
```

Expected: 자동 폭은 3픽셀 여백을 남기고 수동 폭은 저장값을 그대로 사용하며 모두 통과

- [ ] **Step 5: 자동 폭 변경 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: keep graph clear of hash rail"
```

### Task 4: 전체 검증과 정리

**Files:**
- Verify: `lib/settings.dart`
- Verify: `lib/main.dart`
- Verify: `lib/timeline.dart`
- Verify: `test/app_test.dart`

**Interfaces:**
- Consumes: 앞선 작업에서 완성한 설정과 그래프 폭 동작
- Produces: 분석과 전체 테스트를 통과한 통합 브랜치

- [ ] **Step 1: 변경 파일 서식 적용**

Run:

```bash
dart format lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
```

Expected: 네 파일이 Dart 표준 형식으로 정리됨

- [ ] **Step 2: 정적 분석 실행**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: 전체 테스트 실행**

Run:

```bash
flutter test
```

Expected: 모든 테스트 통과

- [ ] **Step 4: 변경 범위와 사용자 파일 보호 확인**

Run:

```bash
git diff --check
git status --short
git diff main...HEAD -- lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
```

Expected:

- 공백 오류 없음
- 기능 브랜치에는 계획에 적힌 코드와 테스트만 포함
- 사용자가 수정한 `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md`와 `.superpowers/brainstorm/`은 변경되지 않음

- [ ] **Step 5: 검증 중 필요한 수정이 있었다면 커밋**

수정이 없으면 이 단계는 건너뛴다. 수정했다면 관련 테스트와 함께 다음처럼 커밋한다.

```bash
git add lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "test: verify repository graph widths"
```
