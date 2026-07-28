# Full Diff Algorithm Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 실제 Git 저장소와 Full Diff 화면을 연결해 Myers, Minimal, Patience, Histogram의 출력과 화면 갱신을 한 번 검증하고 독립 실행 가능한 HTML 보고서를 남긴다.

**Architecture:** `/tmp`에 만든 샘플 저장소에서 네 알고리즘의 원본 diff를 수집한다. 임시 Flutter widget 테스트가 제품의 `GitRepository`, `FullDiffSessionController`, `DiffScreen`을 그대로 사용해 Git 출력부터 화면까지 비교하고 PNG와 JSON 증거를 만든다. 마지막에 JSON 증거를 HTML 설명 페이지로 렌더링하고 모든 임시 파일을 제거한다.

**Tech Stack:** Git CLI, Node.js 표준 라이브러리, Flutter widget test, yogit의 `GitRepository`·`FullDiffSessionController`·`DiffScreen`, Explain Diff HTML renderer

## Global Constraints

- 영구 테스트나 샘플 저장소는 남기지 않는다.
- 제품 코드는 수정하지 않는다.
- 결함이 나오면 고치지 않고 재현 절차와 실제 값을 보고서에 기록한다.
- 검증 대상은 Myers, Minimal, Patience, Histogram 네 가지다.
- 최종 보고서는 외부 자원 없이 열리는 HTML 한 파일이어야 한다.
- 임시 테스트와 중간 JSON·PNG는 결과 보고서를 만든 뒤 제거한다.

---

### Task 1: 네 알고리즘을 구분하는 샘플 저장소 만들기

**Files:**
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/find-fixture.mjs`
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/repo/`
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/baseline.json`

**Interfaces:**
- Consumes: `git diff --no-index --diff-algorithm=<name>`, Git CLI
- Produces: `baseline.json` with `repository`, `baseCommit`, `targetCommit`, `beforeSource`, `afterSource`, and one raw diff record per concrete algorithm

- [ ] **Step 1: Create a deterministic candidate generator**

Write `/tmp/yogit-full-diff-algorithm-verification/find-fixture.mjs` with these
fixed algorithms and normalized-output contract:

```js
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const algorithms = ["myers", "minimal", "patience", "histogram"];
const root = process.env.YOGIT_ALGORITHM_VERIFY_ROOT;
const candidateRoot = path.join(root, "candidates");

function git(args, cwd, accepted = [0]) {
  const result = spawnSync("git", args, {
    cwd,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (!accepted.includes(result.status)) {
    throw new Error(`git ${args.join(" ")}\n${result.stderr}`);
  }
  return result.stdout;
}

function rng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

function sourceFor(sequence) {
  return [
    "void replay() {",
    ...sequence.map((token) => `  trace('${token}');`),
    "}",
    "",
  ].join("\n");
}

function candidate(seed) {
  const random = rng(seed);
  const tokens = ["A", "B", "C", "D", "E", "F", "A", "C", "B", "E", "D", "A"];
  const before = Array.from({ length: 22 }, () =>
    tokens[Math.floor(random() * tokens.length)]
  );
  const after = [...before];
  for (let index = 0; index < 8; index += 1) {
    const from = Math.floor(random() * after.length);
    const to = Math.floor(random() * after.length);
    const [value] = after.splice(from, 1);
    after.splice(to, 0, value);
  }
  after.splice(5, 0, `UNIQUE_${seed}`);
  after.splice(17, 1, `CHANGED_${seed}`);
  return { before: sourceFor(before), after: sourceFor(after) };
}

function normalizedBody(diff) {
  return diff
    .split("\n")
    .filter((line) =>
      !line.startsWith("diff --git ") &&
      !line.startsWith("index ") &&
      !line.startsWith("--- ") &&
      !line.startsWith("+++ ")
    )
    .join("\n")
    .trim();
}

function fingerprint(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function blocksBySeed(diff) {
  const result = new Map();
  for (const block of diff.split(/(?=^diff --git )/m)) {
    const match = block.match(/sample-(\d+)\.dart/);
    if (match) result.set(Number(match[1]), block);
  }
  return result;
}

function counts(diff) {
  const lines = diff.split("\n");
  return {
    hunks: lines.filter((line) => line.startsWith("@@ ")).length,
    additions: lines.filter(
      (line) => line.startsWith("+") && !line.startsWith("+++")
    ).length,
    deletions: lines.filter(
      (line) => line.startsWith("-") && !line.startsWith("---")
    ).length,
    context: lines.filter((line) => line.startsWith(" ")).length,
  };
}

fs.rmSync(candidateRoot, { recursive: true, force: true });
const beforeDirectory = path.join(candidateRoot, "before");
const afterDirectory = path.join(candidateRoot, "after");
fs.mkdirSync(beforeDirectory, { recursive: true });
fs.mkdirSync(afterDirectory, { recursive: true });

const candidates = new Map();
for (let seed = 1; seed <= 800; seed += 1) {
  const value = candidate(seed);
  candidates.set(seed, value);
  fs.writeFileSync(path.join(beforeDirectory, `sample-${seed}.dart`), value.before);
  fs.writeFileSync(path.join(afterDirectory, `sample-${seed}.dart`), value.after);
}

const directoryDiffs = new Map();
for (const algorithm of algorithms) {
  const output = git(
    [
      "diff",
      "--no-index",
      "--no-color",
      "--unified=3",
      `--diff-algorithm=${algorithm}`,
      beforeDirectory,
      afterDirectory,
    ],
    root,
    [1]
  );
  directoryDiffs.set(algorithm, blocksBySeed(output));
}

let selectedSeed;
for (let seed = 1; seed <= 800; seed += 1) {
  const hashes = algorithms.map((algorithm) => {
    const block = directoryDiffs.get(algorithm).get(seed);
    return block ? fingerprint(normalizedBody(block)) : "";
  });
  if (hashes.every(Boolean) && new Set(hashes).size === algorithms.length) {
    selectedSeed = seed;
    break;
  }
}
if (selectedSeed === undefined) {
  throw new Error("No four-way-distinct fixture found in 800 candidates");
}

const selected = candidates.get(selectedSeed);
const repo = path.join(root, "repo");
fs.rmSync(repo, { recursive: true, force: true });
fs.mkdirSync(repo, { recursive: true });
git(["init", "-q"], repo);
git(["config", "user.name", "Yogit Verification"], repo);
git(["config", "user.email", "verification@yogit.invalid"], repo);
git(["config", "diff.algorithm", "myers"], repo);
fs.writeFileSync(path.join(repo, "sample.dart"), selected.before);
git(["add", "sample.dart"], repo);
git(["commit", "-q", "-m", "fixture: baseline repeated blocks"], repo);
const baseCommit = git(["rev-parse", "HEAD"], repo).trim();
fs.writeFileSync(path.join(repo, "sample.dart"), selected.after);
git(["add", "sample.dart"], repo);
git(["commit", "-q", "-m", "fixture: reorder repeated blocks"], repo);
const targetCommit = git(["rev-parse", "HEAD"], repo).trim();

const baseline = {
  repository: repo,
  selectedSeed,
  baseCommit,
  targetCommit,
  beforeSource: selected.before,
  afterSource: selected.after,
  gitVersion: git(["--version"], repo).trim(),
  flutterVersion: (() => {
    const result = spawnSync("flutter", ["--version", "--machine"], {
      cwd: root,
      encoding: "utf8",
      maxBuffer: 4 * 1024 * 1024,
    });
    if (result.status !== 0) {
      throw new Error(`flutter --version --machine\n${result.stderr}`);
    }
    return JSON.parse(result.stdout);
  })(),
  platform: {
    os: os.type(),
    release: os.release(),
    architecture: os.arch(),
    node: process.version,
  },
  algorithms: {},
};
for (const algorithm of algorithms) {
  const args = [
    "diff",
    "--no-ext-diff",
    "--no-textconv",
    "--no-color",
    "--find-renames=50%",
    "--unified=3",
    `--diff-algorithm=${algorithm}`,
    baseCommit,
    targetCommit,
    "--",
    "sample.dart",
  ];
  const raw = git(args, repo);
  const body = normalizedBody(raw);
  baseline.algorithms[algorithm] = {
    command: ["git", ...args],
    raw,
    hash: fingerprint(body),
    ...counts(raw),
  };
}
fs.writeFileSync(
  path.join(root, "baseline.json"),
  `${JSON.stringify(baseline, null, 2)}\n`
);
console.log(
  JSON.stringify(
    {
      selectedSeed,
      hashes: Object.fromEntries(
        algorithms.map((name) => [name, baseline.algorithms[name].hash])
      ),
    },
    null,
    2
  )
);
```

- [ ] **Step 2: Run the candidate search**

Run:

```bash
YOGIT_ALGORITHM_VERIFY_ROOT=/tmp/yogit-full-diff-algorithm-verification \
  node /tmp/yogit-full-diff-algorithm-verification/find-fixture.mjs
```

Expected: one selected seed, four distinct SHA-256 values, and the selected
before/after source printed as JSON.

- [ ] **Step 3: Create two real commits from the selected source**

The same script must initialize `repo`, configure a local test identity, write
`sample.dart`, and create exactly two commits:

```js
git(["init", "-q"], repo);
git(["config", "user.name", "Yogit Verification"], repo);
git(["config", "user.email", "verification@yogit.invalid"], repo);
git(["config", "diff.algorithm", "myers"], repo);
fs.writeFileSync(path.join(repo, "sample.dart"), selected.before);
git(["add", "sample.dart"], repo);
git(["commit", "-q", "-m", "fixture: baseline repeated blocks"], repo);
const baseCommit = git(["rev-parse", "HEAD"], repo).trim();
fs.writeFileSync(path.join(repo, "sample.dart"), selected.after);
git(["add", "sample.dart"], repo);
git(["commit", "-q", "-m", "fixture: reorder repeated blocks"], repo);
const targetCommit = git(["rev-parse", "HEAD"], repo).trim();
```

For each algorithm, run this exact command and record stdout:

```bash
git diff --no-ext-diff --no-textconv --no-color --find-renames=50% \
  --unified=3 --diff-algorithm=<algorithm> <baseCommit> <targetCommit> \
  -- sample.dart
```

Write `/tmp/yogit-full-diff-algorithm-verification/baseline.json` with the two
commit hashes, both complete source files, Git version, raw outputs, normalized
hashes, hunk counts, and add/delete/context counts.

- [ ] **Step 4: Verify the baseline artifact**

Run:

```bash
node -e "const x=require('/tmp/yogit-full-diff-algorithm-verification/baseline.json'); const h=Object.values(x.algorithms).map(v=>v.hash); if(h.length!==4||new Set(h).size!==4) process.exit(1); console.log(h)"
```

Expected: four different hashes and exit code 0.

---

### Task 2: 실제 Git 출력부터 Full Diff 화면까지 검증하기

**Files:**
- Create temporarily: `test/full_diff_algorithm_live_verification_test.dart`
- Read: `lib/git.dart`
- Read: `lib/full_diff_controller.dart`
- Read: `lib/diff_screen.dart`
- Read: `test/support/full_diff_qa_harness.dart`
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/result.json`
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/screenshots/<algorithm>.png`

**Interfaces:**
- Consumes:
  - `GitRepository(String root, {RawCommandRunner? rawRunner})`
  - `GitRepository.loadHistory(limit: 2)`
  - `FullDiffSessionController(repository:, commits:, initialIndex:)`
  - `FullDiffSessionController.selectAlgorithm(DiffAlgorithm)`
  - `DiffScreen(repository:, commits:, initialIndex:, controller:)`
  - `FullDiffQaComparisonCanvas(controller:, surfaceSize:)`
  - `FullDiffCodeRow.line`
  - `FullDiffHunkHeader.hunk`
- Produces: `result.json` containing command arguments, parsed rows, controller state, rendered sentinels, screenshots, and pass/fail checks

- [ ] **Step 1: Write the one-time diagnostic assertions**

Create `test/full_diff_algorithm_live_verification_test.dart`. Read
`YOGIT_ALGORITHM_VERIFY_ROOT`, load `baseline.json`, and wrap `runRawProcess`
so every `git diff` argument list is recorded:

```dart
final diffCalls = <List<String>>[];
final repository = GitRepository(
  repoRoot,
  rawRunner: (executable, arguments, {workingDirectory}) {
    if (arguments.isNotEmpty && arguments.first == 'diff') {
      diffCalls.add(List<String>.of(arguments));
    }
    return runRawProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
  },
);
```

Load the target commit and selected file from the real repository. For every
`DiffAlgorithm` in this exact list:

```dart
const algorithms = [
  DiffAlgorithm.myers,
  DiffAlgorithm.minimal,
  DiffAlgorithm.patience,
  DiffAlgorithm.histogram,
];
```

call `repository.loadDiff`, parse the matching raw baseline with
`parseUnifiedDiff`, and compare this stable projection:

```dart
Map<String, Object?> rowJson(DiffLine line) => {
  'kind': line.kind.name,
  'text': line.text,
  'oldNumber': line.oldNumber,
  'newNumber': line.newNumber,
};
```

Record whether each direct repository call contains its explicit
`--diff-algorithm=<name>` argument and whether every projected row equals the
raw Git baseline projection. Do not stop at the first mismatch; keep the
actual and expected projections for the report.

- [ ] **Step 2: Connect the real repository to the real screen**

Create and initialize the controller:

```dart
final commits = await repository.loadHistory(limit: 2);
final controller = FullDiffSessionController(
  repository: repository,
  commits: commits,
  initialIndex: 0,
);
addTearDown(controller.dispose);
await controller.initialize();
```

Load QA fonts in `setUpAll`, set a 1200×760 logical surface at device-pixel
ratio 1, and pump:

```dart
MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: fullDiffQaTheme(),
  home: FullDiffQaComparisonCanvas(
    controller: controller,
    surfaceSize: const Size(1200, 760),
  ),
)
```

- [ ] **Step 3: Select each algorithm through the UI**

Use the real menu keys:

```dart
await tester.tap(find.byKey(const Key('diff-algorithm')));
await tester.pump();
await tester.tap(find.byKey(Key('algorithm-option-${algorithm.name}')));
await tester.pumpAndSettle();
```

For Myers, allow the internal requested value to normalize to
`DiffAlgorithm.gitSetting` because the temporary repository explicitly sets
`diff.algorithm=myers`. Require
`controller.state.appliedConcreteAlgorithm == algorithm` for every row.

For each state, record:

- the toolbar value equals `algorithm.label`;
- the controller document projection equals the direct repository projection;
- every mounted `FullDiffCodeRow.line` has the same kind, text, and line
  numbers as the controller document row at that position;
- every mounted `FullDiffHunkHeader.hunk` has the same range and context as
  the controller document hunk at that position;
- the combined rendered row-and-hunk fingerprint equals the current
  algorithm fingerprint and differs from the preceding algorithm fingerprint;
- `patch.loading` is false and `patch.error` is null.

Repeat Myers after Histogram and require the first and last Myers document
projections to be equal.

- [ ] **Step 4: Capture each rendered state**

Find the `RenderRepaintBoundary` under
`Key('full-diff-comparison-canvas')`, call `toImage(pixelRatio: 1)`, encode PNG
with `ui.ImageByteFormat.png`, and write:

```text
/tmp/yogit-full-diff-algorithm-verification/screenshots/myers.png
/tmp/yogit-full-diff-algorithm-verification/screenshots/minimal.png
/tmp/yogit-full-diff-algorithm-verification/screenshots/patience.png
/tmp/yogit-full-diff-algorithm-verification/screenshots/histogram.png
```

The write must run inside `tester.runAsync`.

- [ ] **Step 5: Write machine-readable results**

Wrap each algorithm collection in `try/catch` and append any thrown error and
stack trace to that algorithm's result. Write `result.json` before the final
test expectation so a failed diagnostic still produces a report source.

Write `result.json` with:

```json
{
  "overallPassed": true,
  "sequence": ["myers", "minimal", "patience", "histogram", "myers"],
  "checks": {
    "fourDistinctGitOutputs": true,
    "repositoryMatchesGit": true,
    "controllerAppliedSelection": true,
    "renderedContentMatchesController": true,
    "previousContentCleared": true,
    "myersRoundTripStable": true
  },
  "algorithms": {}
}
```

Populate `algorithms` with actual hashes, counts, command arguments,
controller requested/applied values, rendered sentinel text, screenshot
paths, and captured errors. Never force `overallPassed` to true; derive it
from the six checks. After the JSON write, make one final
`expect(overallPassed, isTrue, reason: ...)` assertion.

- [ ] **Step 6: Run the diagnostic**

Run:

```bash
YOGIT_ALGORITHM_VERIFY_ROOT=/tmp/yogit-full-diff-algorithm-verification \
  flutter test test/full_diff_algorithm_live_verification_test.dart \
  --reporter expanded
```

Expected: either one passing diagnostic with `overallPassed: true`, or a
failing assertion that names the first mismatched layer. Preserve the actual
outcome for the report; do not modify production code.

---

### Task 3: 독립 실행 가능한 HTML 보고서 만들기

**Files:**
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/build-report.mjs`
- Create temporarily: `/tmp/yogit-full-diff-algorithm-verification/report-spec.json`
- Create: `docs/reports/2026-07-28-full-diff-algorithm-verification.html`

**Interfaces:**
- Consumes: `baseline.json`, `result.json`, four PNG screenshots
- Produces: Explain Diff HTML renderer JSON schema and one standalone HTML report

- [ ] **Step 1: Build the report JSON**

Write `build-report.mjs` using only `node:fs`, `node:path`, and
`node:util`. Escape source and diff text with:

```js
function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function imageData(file) {
  return `data:image/png;base64,${fs.readFileSync(file).toString("base64")}`;
}
```

Build the three section bodies from actual values:

```js
const root = process.env.YOGIT_ALGORITHM_VERIFY_ROOT;
const baseline = JSON.parse(
  fs.readFileSync(path.join(root, "baseline.json"), "utf8")
);
const result = JSON.parse(
  fs.readFileSync(path.join(root, "result.json"), "utf8")
);
const labels = {
  myers: "Myers",
  minimal: "Minimal",
  patience: "Patience",
  histogram: "Histogram",
};
const status = result.overallPassed ? "PASS" : "FAIL";

const checkRows = Object.entries(result.checks)
  .map(
    ([name, passed]) =>
      `<tr><td><code>${escapeHtml(name)}</code></td><td>${passed ? "PASS" : "FAIL"}</td></tr>`
  )
  .join("");

const algorithmRows = Object.entries(baseline.algorithms)
  .map(([name, value]) => {
    const app = result.algorithms[name] ?? {};
    return `<tr>
      <td>${labels[name]}</td>
      <td><code>${value.hash}</code></td>
      <td>${value.hunks}</td>
      <td>${value.additions} / ${value.deletions} / ${value.context}</td>
      <td>${app.repositoryMatchesGit ? "PASS" : "FAIL"}</td>
      <td>${app.renderedContentMatchesController ? "PASS" : "FAIL"}</td>
    </tr>`;
  })
  .join("");

const evidence = Object.entries(baseline.algorithms)
  .map(([name, value]) => {
    const screenshot = path.join(root, "screenshots", `${name}.png`);
    return `<h3>${labels[name]}</h3>
      <p><code>${escapeHtml(value.command.join(" "))}</code></p>
      <pre>${escapeHtml(value.raw)}</pre>
      <div class="diagram">
        <img
          alt="${labels[name]} Full Diff 화면"
          src="${imageData(screenshot)}"
          style="display:block;max-width:100%;height:auto;margin:auto"
        >
      </div>`;
  })
  .join("");

const spec = {
  title: "Full Diff 알고리즘 실제 동작 검증",
  subtitle: `실제 Git 출력부터 yogit 화면 렌더링까지 · ${status}`,
  slug: "full-diff-algorithm-verification",
  sections: [
    {
      title: "Background",
      html: `<div class="callout"><strong>최종 판정: ${status}</strong></div>
        <p>이 검증은 네 Git diff 알고리즘의 실제 출력이 yogit의
        GitRepository, DiffDocument, FullDiffSessionController를 거쳐
        Full Diff 화면까지 같은 내용으로 전달되는지 확인했다.</p>
        <table>
          <tr><th>항목</th><th>값</th></tr>
          <tr><td>Git</td><td>${escapeHtml(baseline.gitVersion)}</td></tr>
          <tr><td>Flutter</td><td>${escapeHtml(baseline.flutterVersion.frameworkVersion)}</td></tr>
          <tr><td>운영체제</td><td>${escapeHtml(`${baseline.platform.os} ${baseline.platform.release} ${baseline.platform.architecture}`)}</td></tr>
          <tr><td>기준 커밋</td><td><code>${baseline.baseCommit}</code></td></tr>
          <tr><td>변경 커밋</td><td><code>${baseline.targetCommit}</code></td></tr>
        </table>
        <h3>판정표</h3>
        <table><tr><th>검사</th><th>결과</th></tr>${checkRows}</table>`,
    },
    {
      title: "Intuition",
      html: `<p>알고리즘 이름만 바뀌는지 보는 테스트로는 충분하지 않다.
        실제 Git 옵션, 파싱된 행, 적용 상태, 렌더링된 행을 같은 증거 사슬로
        비교해야 한다.</p>
        <div class="flow">
          <div class="box">알고리즘 선택</div>
          <div class="box">GitRepository</div>
          <div class="box">git diff</div>
          <div class="box">DiffDocument</div>
          <div class="box">Controller</div>
          <div class="box">Full Diff 화면</div>
        </div>
        <div class="callout">Myers → Minimal → Patience → Histogram → Myers
        순서로 바꿔 마지막 Myers 결과가 처음과 같은지도 확인했다.</div>`,
    },
    {
      title: "Code and results",
      html: `<h3>알고리즘 비교</h3>
        <table>
          <tr><th>알고리즘</th><th>본문 SHA-256</th><th>hunk</th>
          <th>추가 / 삭제 / 문맥</th><th>Git↔앱</th><th>앱↔화면</th></tr>
          ${algorithmRows}
        </table>
        <h3>기준 코드</h3>
        <pre>${escapeHtml(baseline.beforeSource)}</pre>
        <h3>변경 코드</h3>
        <pre>${escapeHtml(baseline.afterSource)}</pre>
        <h3>알고리즘별 원본 diff와 화면</h3>
        ${evidence}
        <h3>왕복 안정성</h3>
        <p>실행 순서: <code>${result.sequence.join(" → ")}</code></p>
        <p>Myers 재선택 결과:
        <strong>${result.checks.myersRoundTripStable ? "PASS" : "FAIL"}</strong></p>
        <div class="callout"><strong>결론:</strong>
        ${escapeHtml(result.conclusion)}</div>`,
    },
  ],
  quiz: [
    {
      question: "Git 설정이 Myers일 때 UI에서 Myers를 선택하면 내부 요청값이 gitSetting일 수 있는 이유는?",
      options: [
        {
          text: "같은 알고리즘을 중복 지정하지 않고 저장소 설정을 그대로 쓰기 때문",
          correct: true,
          feedback: "맞다. 화면의 유효 알고리즘은 Myers지만 내부 선택은 Git 설정으로 정규화될 수 있다.",
        },
        {
          text: "Myers가 Git에서 지원되지 않기 때문",
          correct: false,
          feedback: "Myers는 Git이 지원하는 기본 diff 알고리즘이다.",
        },
      ],
    },
    {
      question: "원본 git diff와 GitRepository 결과를 함께 비교한 주된 이유는?",
      options: [
        {
          text: "명령 인수뿐 아니라 파싱 뒤의 행 내용과 번호도 보존되는지 확인하려고",
          correct: true,
          feedback: "맞다. 옵션 전달과 파싱 정확성을 한 번에 확인한다.",
        },
        {
          text: "Git 실행 시간을 측정하려고",
          correct: false,
          feedback: "이번 검증은 성능 측정이 아니라 내용 정확성 검증이다.",
        },
      ],
    },
    {
      question: "appliedConcreteAlgorithm을 확인하면 무엇을 알 수 있는가?",
      options: [
        {
          text: "Git 설정까지 해석한 뒤 실제 적용된 알고리즘",
          correct: true,
          feedback: "맞다. requestedAlgorithm의 내부 표현과 실제 알고리즘을 구분한다.",
        },
        {
          text: "현재 선택된 파일의 문자 인코딩",
          correct: false,
          feedback: "문자 인코딩은 별도 상태이며 알고리즘 적용값과 관계없다.",
        },
      ],
    },
    {
      question: "Histogram 뒤에 Myers를 다시 선택한 이유는?",
      options: [
        {
          text: "캐시가 다른 알고리즘 결과를 잘못 재사용하지 않는지 확인하려고",
          correct: true,
          feedback: "맞다. 처음과 마지막 Myers 문서가 같아야 한다.",
        },
        {
          text: "화면 색상 팔레트를 초기화하려고",
          correct: false,
          feedback: "알고리즘 선택은 팔레트를 바꾸지 않는다.",
        },
      ],
    },
    {
      question: "툴바의 알고리즘 이름만 확인하면 부족한 이유는?",
      options: [
        {
          text: "이름은 바뀌어도 이전 diff 문서가 화면에 남을 수 있기 때문",
          correct: true,
          feedback: "맞다. 렌더링된 hunk와 행을 현재 컨트롤러 문서와 비교해야 한다.",
        },
        {
          text: "툴바는 항상 숨겨져 있기 때문",
          correct: false,
          feedback: "툴바는 보이지만 이름만으로 본문 갱신까지 증명할 수 없다.",
        },
      ],
    },
  ],
};

fs.writeFileSync(
  path.join(root, "report-spec.json"),
  `${JSON.stringify(spec, null, 2)}\n`
);
```

- [ ] **Step 2: Add exactly five substantive quiz questions**

Validate that the five question objects above each have exactly one
`correct: true` option and non-empty feedback on every option before writing
the JSON. Throw an error naming the invalid question index if the contract is
broken.

- [ ] **Step 3: Render the report**

Run:

```bash
mkdir -p docs/reports
node /tmp/yogit-full-diff-algorithm-verification/build-report.mjs
cd docs/reports
python3 /Users/doortts/.codex/skills/explain-diff-html/scripts/render.py \
  /tmp/yogit-full-diff-algorithm-verification/report-spec.json
```

Expected output:

```text
/Users/doortts/repos/yogit/docs/reports/2026-07-28-full-diff-algorithm-verification.html
```

- [ ] **Step 4: Check report contents mechanically**

Run:

```bash
rg -n "Myers|Minimal|Patience|Histogram|overallPassed|data:image/png;base64" \
  docs/reports/2026-07-28-full-diff-algorithm-verification.html
```

Expected: all four algorithm names, the actual overall result, and four
embedded PNG data URIs.

---

### Task 4: 브라우저 검증, 정리, 결과 커밋

**Files:**
- Verify: `docs/reports/2026-07-28-full-diff-algorithm-verification.html`
- Delete: `test/full_diff_algorithm_live_verification_test.dart`
- Delete: `/tmp/yogit-full-diff-algorithm-verification/`

**Interfaces:**
- Consumes: standalone HTML report
- Produces: a browser-verified report and a clean worktree with no temporary test

- [ ] **Step 1: Inspect the report in the in-app browser**

Invoke `browser:control-in-app-browser`, open the report, and verify:

- table-of-contents links move to all three sections;
- long source and diff blocks wrap or scroll without covering adjacent content;
- all four screenshots load;
- every quiz option can receive keyboard focus;
- each question has one correct answer and useful feedback;
- a narrow viewport keeps tables and images inside the page.

- [ ] **Step 2: Remove temporary artifacts**

Delete `test/full_diff_algorithm_live_verification_test.dart` with
`apply_patch`. Confirm the exact temporary root, then remove only:

```text
/tmp/yogit-full-diff-algorithm-verification/
```

- [ ] **Step 3: Verify repository scope**

Run:

```bash
git status --short
git diff --check
git diff --stat HEAD
rg -n "full_diff_algorithm_live_verification" test
```

Expected: only the HTML report is new, `git diff --check` passes, and no
temporary verification test remains.

- [ ] **Step 4: Commit the report**

```bash
git add docs/reports/2026-07-28-full-diff-algorithm-verification.html
git commit -m "docs: report full diff algorithm verification"
```

- [ ] **Step 5: Final evidence check**

Run:

```bash
git status --short --branch
git log -3 --oneline --decorate
```

Expected: clean worktree with the design, plan, and report commits ahead of
`origin/main`. Report the actual diagnostic result and provide a clickable
link to the HTML file.
