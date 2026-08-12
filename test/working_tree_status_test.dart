import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/working_tree_status.dart';

/// `git status --porcelain=v2 --untracked-files=all -z` output: every record is
/// NUL-terminated, and a rename record's original path is a record of its own.
String status(List<String> records) => records.map((r) => '$r\x00').join();

const _modified = '1 MM N... 100644 100644 100644 aaaaaaa bbbbbbb';
const _binaryCounts = (additions: null, deletions: null, isBinary: true);

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

  group('areaFileChange', () {
    test('derives section letters from the section\'s own axis', () {
      final entries = mergeNumstat(
        parseStatusV2(
          status([
            '$_modified both.txt',
            '1 AM N... 000000 100644 100644 aaaaaaa bbbbbbb added.txt',
            '1 .D N... 100644 100644 000000 aaaaaaa bbbbbbb gone.txt',
          ]),
        ),
        unstaged: const {
          'both.txt': (additions: 2, deletions: 1, isBinary: false),
        },
        staged: const {
          'both.txt': (additions: 4, deletions: 3, isBinary: false),
        },
      );
      final [both, added, gone] = entries;

      expect(areaFileChange(both, WorkingTreeArea.unstaged)!.status, 'M');
      expect(areaFileChange(both, WorkingTreeArea.staged)!.status, 'M');
      expect(areaFileChange(both, WorkingTreeArea.unstaged)!.additions, 2);
      expect(areaFileChange(both, WorkingTreeArea.staged)!.additions, 4);

      expect(areaFileChange(added, WorkingTreeArea.unstaged)!.status, 'M');
      expect(areaFileChange(added, WorkingTreeArea.staged)!.status, 'A');

      expect(areaFileChange(gone, WorkingTreeArea.unstaged)!.status, 'D');
      expect(areaFileChange(gone, WorkingTreeArea.staged), isNull);
    });

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
      expect(areaFileChange(entries.single, WorkingTreeArea.staged), isNull);
      expect(
        areaFileChange(entries.single, WorkingTreeArea.unstaged)!.status,
        'U',
      );
    });
  });
}
