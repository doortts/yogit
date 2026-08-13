import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/working_tree_status.dart';

/// `git status --porcelain=v2 --untracked-files=all -z` output: every record is
/// NUL-terminated, and a rename record's original path is a record of its own.
String status(List<String> records) => records.map((r) => '$r\x00').join();

/// A git patch: every line ends in a newline, as git writes it.
String patch(List<String> lines) => lines.map((line) => '$line\n').join();

const _modified = '1 MM N... 100644 100644 100644 aaaaaaa bbbbbbb';
const _binaryCounts = (additions: null, deletions: null, isBinary: true);

const _fileHeader = [
  'diff --git a/lib/git.dart b/lib/git.dart',
  'index 1111111..2222222 100644',
  '--- a/lib/git.dart',
  '+++ b/lib/git.dart',
];

const _firstHunk = [
  '@@ -1,5 +1,5 @@',
  ' one',
  ' two',
  '-three',
  '+THREE',
  ' four',
  ' five',
];

const _middleHunk = [
  '@@ -20,6 +20,7 @@ class Foo {',
  ' alpha',
  ' beta',
  '+gamma',
  ' delta',
  ' epsilon',
  ' zeta',
  ' eta',
];

const _lastHunk = [
  '@@ -40,4 +41,4 @@',
  ' last one',
  '-last two',
  '+LAST TWO',
  ' last three',
  ' last four',
];

const _firstRange = (oldStart: 1, oldCount: 5, newStart: 1, newCount: 5);
const _middleRange = (oldStart: 20, oldCount: 6, newStart: 20, newCount: 7);
const _lastRange = (oldStart: 40, oldCount: 4, newStart: 41, newCount: 4);

void main() {
  group('parseStatusV2', () {
    test('parses an ordinary modified entry into both axes', () {
      final entries = parseStatusV2(status(['$_modified lib/git.dart']));
      final tree = WorkingTreeStatus(entries);

      expect(entries, hasLength(1));
      expect(entries.single.path, 'lib/git.dart');
      expect(entries.single.indexStatus, 'M');
      expect(entries.single.worktreeStatus, 'M');
      expect(entries.single.untracked, isFalse);
      expect(entries.single.conflicted, isFalse);
      expect(tree.unstaged.single, same(entries.single));
      expect(tree.staged.single, same(entries.single));
    });

    test('parses a staged-only and an unstaged-only entry into one section '
        'each', () {
      final tree = WorkingTreeStatus(
        parseStatusV2(
          status([
            '1 M. N... 100644 100644 100644 aaaaaaa bbbbbbb staged.txt',
            '1 .M N... 100644 100644 100644 aaaaaaa bbbbbbb worktree.txt',
          ]),
        ),
      );

      expect(tree.staged.map((e) => e.path), ['staged.txt']);
      expect(tree.unstaged.map((e) => e.path), ['worktree.txt']);
    });

    test('parses a -z rename record consuming the second NUL token', () {
      final entries = parseStatusV2(
        status([
          '2 R. N... 100644 100644 100644 aaaaaaa bbbbbbb R100 new name.txt',
          'old name.txt',
          '$_modified after.txt',
        ]),
      );

      expect(entries.map((e) => e.path), ['new name.txt', 'after.txt']);
      expect(entries.first.origPath, 'old name.txt');
      expect(entries.first.indexStatus, 'R');
      expect(entries.last.origPath, isNull);
    });

    test('parses untracked, conflict, submodule and symlink records', () {
      final entries = parseStatusV2(
        status([
          '? .DS_Store',
          'u UU N... 100644 100644 100644 100644 aaaaaaa bbbbbbb ccccccc '
              'conflict.txt',
          '1 .M S.M. 160000 160000 160000 aaaaaaa bbbbbbb vendor/mod',
          '1 .M N... 120000 120000 120000 aaaaaaa bbbbbbb link',
        ]),
      );
      final tree = WorkingTreeStatus(entries);
      final [untracked, conflict, submodule, symlink] = entries;

      expect(untracked.path, '.DS_Store');
      expect(untracked.untracked, isTrue);
      expect(untracked.worktreeStatus, 'A');
      expect(untracked.indexStatus, '.');

      expect(conflict.path, 'conflict.txt');
      expect(conflict.conflicted, isTrue);
      expect(conflict.indexStatus, 'U');
      expect(conflict.worktreeStatus, 'U');

      expect(submodule.path, 'vendor/mod');
      expect(submodule.submodule, isTrue);
      expect(symlink.submodule, isFalse);

      expect(symlink.path, 'link');
      expect(symlink.symlink, isTrue);
      expect(submodule.symlink, isFalse);

      expect(tree.unstaged, hasLength(4));
      expect(tree.staged, isEmpty);
    });
  });

  group('mergeNumstat', () {
    test('merges numstat pairs onto the right axis and flags binary', () {
      final merged = mergeNumstat(
        parseStatusV2(
          status([
            '$_modified text.txt',
            '1 M. N... 100644 100644 100644 aaaaaaa bbbbbbb image.png',
            '? added.txt',
          ]),
        ),
        unstaged: const {
          'text.txt': (additions: 2, deletions: 1, isBinary: false),
          'added.txt': (additions: 9, deletions: 9, isBinary: false),
        },
        staged: const {
          'text.txt': (additions: 4, deletions: 3, isBinary: false),
          'image.png': _binaryCounts,
        },
      );
      final [text, image, added] = merged;

      expect(text.unstagedAdditions, 2);
      expect(text.unstagedDeletions, 1);
      expect(text.stagedAdditions, 4);
      expect(text.stagedDeletions, 3);
      expect(text.unstagedBinary, isFalse);
      expect(text.stagedBinary, isFalse);

      expect(image.stagedBinary, isTrue);
      expect(image.stagedAdditions, isNull);
      expect(image.stagedDeletions, isNull);

      expect(added.untracked, isTrue);
      expect(added.unstagedAdditions, isNull);
      expect(added.unstagedDeletions, isNull);
    });
  });

  group('WorkingTreeStatus', () {
    test('keeps conflicted entries out of the staged section', () {
      final entries = parseStatusV2(
        status([
          'u UU N... 100644 100644 100644 100644 aaaaaaa bbbbbbb ccccccc '
              'conflict.txt',
        ]),
      );
      final tree = WorkingTreeStatus(entries);

      expect(tree.hasConflict, isTrue);
      expect(tree.unstaged.map((e) => e.path), ['conflict.txt']);
      expect(tree.staged, isEmpty);
    });
  });

  group('extractHunkPatch', () {
    test('extracts the middle hunk with the file header block intact', () {
      expect(
        extractHunkPatch(
          patch([..._fileHeader, ..._firstHunk, ..._middleHunk, ..._lastHunk]),
          1,
          expected: _middleRange,
        ),
        patch([..._fileHeader, ..._middleHunk]),
      );
    });

    test('keeps a trailing no-newline marker inside its hunk', () {
      const marker = r'\ No newline at end of file';
      final source = patch([
        ..._fileHeader,
        ..._firstHunk,
        ..._lastHunk,
        marker,
      ]);

      expect(
        extractHunkPatch(source, 1, expected: _lastRange),
        patch([..._fileHeader, ..._lastHunk, marker]),
      );
      expect(
        extractHunkPatch(source, 0, expected: _firstRange),
        patch([..._fileHeader, ..._firstHunk]),
      );
    });

    test('keeps new-file and deleted-file headers verbatim', () {
      final created = patch([
        'diff --git a/new.txt b/new.txt',
        'new file mode 100644',
        'index 0000000..3333333',
        '--- /dev/null',
        '+++ b/new.txt',
        '@@ -0,0 +1,2 @@',
        '+alpha',
        '+beta',
      ]);
      final deleted = patch([
        'diff --git a/gone.txt b/gone.txt',
        'deleted file mode 100644',
        'index 3333333..0000000',
        '--- a/gone.txt',
        '+++ /dev/null',
        '@@ -1,2 +0,0 @@',
        '-alpha',
        '-beta',
      ]);

      expect(
        extractHunkPatch(
          created,
          0,
          expected: (oldStart: 0, oldCount: 0, newStart: 1, newCount: 2),
        ),
        created,
      );
      expect(
        extractHunkPatch(
          deleted,
          0,
          expected: (oldStart: 1, oldCount: 2, newStart: 0, newCount: 0),
        ),
        deleted,
      );
    });

    test('throws HunkMovedException when the expected header numbers '
        'differ', () {
      final source = patch([..._fileHeader, ..._firstHunk, ..._middleHunk]);

      expect(
        () => extractHunkPatch(
          source,
          1,
          expected: (oldStart: 21, oldCount: 6, newStart: 20, newCount: 7),
        ),
        throwsA(isA<HunkMovedException>()),
      );
      expect(
        () => extractHunkPatch(
          source,
          1,
          expected: (oldStart: 20, oldCount: 6, newStart: 20, newCount: 6),
        ),
        throwsA(isA<HunkMovedException>()),
      );
      expect(
        () => extractHunkPatch(source, 2, expected: _lastRange),
        throwsA(isA<HunkMovedException>()),
      );
    });

    test('accepts a header that omits ,1 counts', () {
      final source = patch([
        'diff --git a/one.txt b/one.txt',
        'index 1111111..2222222 100644',
        '--- a/one.txt',
        '+++ b/one.txt',
        '@@ -3 +3 @@',
        '-old',
        '+new',
      ]);

      expect(
        extractHunkPatch(
          source,
          0,
          expected: (oldStart: 3, oldCount: 1, newStart: 3, newCount: 1),
        ),
        source,
      );
    });

    test('returns a patch ending with a newline', () {
      final source = [..._fileHeader, ..._firstHunk, ..._middleHunk].join('\n');

      expect(
        extractHunkPatch(source, 1, expected: _middleRange),
        patch([..._fileHeader, ..._middleHunk]),
      );
    });
  });
}
