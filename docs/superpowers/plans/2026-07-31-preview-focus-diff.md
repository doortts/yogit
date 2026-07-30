# Merge/Rebase Preview Focus Diff Implementation Plan

**Goal:** Keep aggregate preview diffs on virtual commits, show the focused real commit's own diff, and give focused virtual rows the normal selection band.

**Architecture:** Reuse the existing preview graph kind map as the single distinction between virtual and real commits. Route only virtual commits through the existing aggregate preview range; real commits continue through the normal commit file and diff loaders.

**Tech Stack:** Flutter, Dart, widget tests

---

### Task 1: Focused real commits use their own diff

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

1. Change the existing comparison-preview widget test to expect the aggregate diff for the virtual commit and the selected real commit's files and diff after keyboard navigation.
2. Run that widget test and confirm it fails with the current aggregate-preview behavior.
3. Make `_previewKey`, `_previewFilesFor`, and `_previewDiff` use the aggregate range only when the selected commit is virtual.
4. Run the widget test and confirm it passes.

### Task 2: Focused virtual commits show the normal selection band

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

1. Add a widget assertion that a selected virtual preview row contains its `selection-band-*` widget.
2. Run the assertion and confirm it fails.
3. Allow the existing selection band to render for virtual rows while preserving their preview colors and node styling.
4. Run the focused tests, `flutter analyze`, and the full Flutter test suite.
5. Commit the branch and launch the macOS app from this worktree for manual testing.
