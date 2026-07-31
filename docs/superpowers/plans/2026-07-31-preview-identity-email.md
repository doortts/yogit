# Preview Identity Email Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each commit author's and committer's email beside their role in the preview identity cards.

**Architecture:** Reuse the existing `_previewIdentity` rendering path and `GitIdentity.email`. Build one trimmed role line per card; no new widget or model is needed.

**Tech Stack:** Flutter, Dart, `flutter_test`; no new dependency.

## Global Constraints

- Render `Author · email` or `Committer · email` when the trimmed email is non-empty.
- Render only `Author` or `Committer` when the trimmed email is empty.
- Keep the role line to one line with ellipsis.
- Preserve the working-tree copy and the existing rule that identical author and committer identities share one card.

---

### Task 1: Preview identity email

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: `GitIdentity.email`
- Produces: the role-line text in `_previewIdentity`

- [ ] **Step 1: Write the failing widget assertions**

Extend `preview shortcuts scroll and distinguish identities` in `test/app_test.dart`:

```dart
expect(
  find.descendant(
    of: author,
    matching: find.text('Author · ada@example.com'),
  ),
  findsOneWidget,
);
expect(
  find.descendant(
    of: committer,
    matching: find.text('Committer · cam@example.com'),
  ),
  findsOneWidget,
);
```

After navigating to the commit whose author and committer are identical, assert that the single Author card contains `Author · ada@example.com` and there is no Committer card.

Add this focused blank-email test:

```dart
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
    app(
      FakeGitRepository((_, _) async => [blankEmailCommit]),
      controller,
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  final author = find.byKey(const Key('preview-author'));
  expect(find.descendant(of: author, matching: find.text('Author')), findsOneWidget);
  expect(
    find.descendant(of: author, matching: find.textContaining('Author ·')),
    findsNothing,
  );
});
```

This catches an empty separator without asserting private implementation details.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "preview shortcuts scroll and distinguish identities"
flutter test test/app_test.dart --plain-name "preview omits an empty identity email"
```

Expected: the first test fails because the role lines do not include emails; the second test fails until the blank-email rendering is defined.

- [ ] **Step 3: Implement the minimal role line**

In `_previewIdentity`, derive the committed role text before the returned `Row`:

```dart
final role = committer ? 'Committer' : 'Author';
final email = identity.email.trim();
final roleLine = email.isEmpty ? role : '$role · $email';
```

Keep the working-tree branch unchanged and replace only the committed identity branch of the existing role `Text`:

```dart
Text(
  commit.isWorkingTree ? 'No commit object or committer' : roleLine,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(color: _palette.muted, fontSize: 12),
)
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart --plain-name "preview shortcuts scroll and distinguish identities"
flutter test test/app_test.dart --plain-name "preview omits an empty identity email"
```

Expected: both PASS with no overflow exception.

- [ ] **Step 5: Run the preview regression group**

Run:

```bash
flutter test test/app_test.dart --plain-name preview
```

Expected: all matching preview tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: show preview identity emails"
```
