import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/git.dart';

typedef FileRequest = ({String sha, String? parent});
typedef DiffRequest = ({
  String sha,
  String? parent,
  String path,
  DiffAlgorithm algorithm,
  bool ignoreWhitespace,
});

class FakeFullDiffRepository implements FullDiffRepository {
  FakeFullDiffRepository({
    this.files = const <GitFileChange>[],
    this.lines = const <DiffLine>[],
    this.onLoadFiles,
    this.onLoadDiff,
  });

  final List<GitFileChange> files;
  final List<DiffLine> lines;
  Future<List<GitFileChange>> Function(FileRequest request)? onLoadFiles;
  Future<List<DiffLine>> Function(DiffRequest request)? onLoadDiff;
  final fileRequests = <FileRequest>[];
  final diffRequests = <DiffRequest>[];

  @override
  final String root = '/repo';

  @override
  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent}) {
    final request = (sha: commit.sha, parent: parent);
    fileRequests.add(request);
    return onLoadFiles?.call(request) ?? Future.value(files);
  }

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
  }) {
    final request = (
      sha: commit.sha,
      parent: parent,
      path: file.path,
      algorithm: algorithm,
      ignoreWhitespace: ignoreWhitespace,
    );
    diffRequests.add(request);
    return onLoadDiff?.call(request) ?? Future.value(lines);
  }

  @override
  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  }) async => Uint8List(0);

  @override
  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  }) async => const [];

  @override
  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  ) async => const [];
}

GitCommit commit(String sha, {List<String> parents = const <String>[]}) =>
    GitCommit(
      sha: sha,
      shortSha: sha,
      parents: parents,
      author: const GitIdentity(name: 'Author', email: 'author@example.com'),
      authorTimestamp: 1,
      committer: const GitIdentity(
        name: 'Committer',
        email: 'committer@example.com',
      ),
      committerTimestamp: 1,
      refs: const <GitRef>[],
      subject: sha.isEmpty ? 'Working tree' : 'Commit $sha',
    );

const fileA = GitFileChange(
  path: 'lib/a.dart',
  status: 'M',
  additions: 1,
  deletions: 1,
);
const fileB = GitFileChange(
  path: 'lib/b.dart',
  status: 'M',
  additions: 1,
  deletions: 1,
);

const oneHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ main'),
  DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
  DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
];

const twoHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ first'),
  DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
  DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -5 +5 @@ second'),
  DiffLine(kind: DiffLineKind.delete, text: 'before', oldNumber: 5),
  DiffLine(kind: DiffLineKind.add, text: 'after', newNumber: 5),
];

void main() {
  test('loads the first file and selects the first hunk', () async {
    final repository = FakeFullDiffRepository(
      files: const <GitFileChange>[fileA],
      lines: oneHunkLines,
    );
    final controller = FullDiffSessionController(
      repository: repository,
      commits: <GitCommit>[
        commit('1', parents: const <String>['0']),
      ],
      initialIndex: 0,
    );

    await controller.initialize();

    expect(controller.state.selectedPath, 'lib/a.dart');
    expect(controller.state.document?.hunks, hasLength(1));
    expect(controller.state.activeHunkIndex, 0);
    expect(controller.state.loadingFiles, isFalse);
    expect(controller.state.loadingDiff, isFalse);
    expect(() => controller.state.files.add(fileB), throwsUnsupportedError);
  });

  test('a late file request cannot overwrite a newer commit', () async {
    final firstFiles = Completer<List<GitFileChange>>();
    final secondFiles = Completer<List<GitFileChange>>();
    final repository = FakeFullDiffRepository(
      lines: oneHunkLines,
      onLoadFiles: (request) =>
          request.sha == '1' ? firstFiles.future : secondFiles.future,
    );
    final controller = FullDiffSessionController(
      repository: repository,
      commits: <GitCommit>[
        commit('1', parents: const <String>['0']),
        commit('2', parents: const <String>['1']),
      ],
      initialIndex: 0,
    );

    final firstLoad = controller.initialize();
    final secondLoad = controller.selectCommit(1);
    secondFiles.complete(const <GitFileChange>[fileB]);
    await secondLoad;
    firstFiles.complete(const <GitFileChange>[fileA]);
    await firstLoad;

    expect(controller.state.commitIndex, 1);
    expect(controller.state.parent, '1');
    expect(controller.state.files.single.path, 'lib/b.dart');
    expect(controller.state.selectedPath, 'lib/b.dart');
  });

  test(
    'option refresh keeps the document and displays the latest request',
    () async {
      final repository = FakeFullDiffRepository(
        files: const <GitFileChange>[fileA],
        lines: oneHunkLines,
      );
      final controller = FullDiffSessionController(
        repository: repository,
        commits: <GitCommit>[
          commit('1', parents: const <String>['0']),
        ],
        initialIndex: 0,
      );
      await controller.initialize();
      final originalDocument = controller.state.document;
      final algorithmDiff = Completer<List<DiffLine>>();
      final whitespaceDiff = Completer<List<DiffLine>>();
      repository.onLoadDiff = (request) => request.ignoreWhitespace
          ? whitespaceDiff.future
          : algorithmDiff.future;

      final algorithmLoad = controller.selectAlgorithm(DiffAlgorithm.patience);

      expect(controller.state.document, same(originalDocument));
      expect(controller.state.loadingDiff, isTrue);
      expect(controller.state.displayedAlgorithm, DiffAlgorithm.gitSetting);

      final whitespaceLoad = controller.setIgnoreWhitespace(true);

      expect(controller.state.document, same(originalDocument));
      expect(controller.state.loadingDiff, isTrue);
      whitespaceDiff.complete(twoHunkLines);
      await whitespaceLoad;

      expect(controller.state.document, isNot(same(originalDocument)));
      expect(controller.state.displayedAlgorithm, DiffAlgorithm.patience);
      expect(controller.state.displayedIgnoreWhitespace, isTrue);
      algorithmDiff.complete(oneHunkLines);
      await algorithmLoad;
      expect(controller.state.displayedAlgorithm, DiffAlgorithm.patience);
      expect(controller.state.displayedIgnoreWhitespace, isTrue);
    },
  );

  test(
    'a failed option refresh restores displayed options and can retry',
    () async {
      final repository = FakeFullDiffRepository(
        files: const <GitFileChange>[fileA],
        lines: oneHunkLines,
      );
      final controller = FullDiffSessionController(
        repository: repository,
        commits: <GitCommit>[
          commit('1', parents: const <String>['0']),
        ],
        initialIndex: 0,
      );
      await controller.initialize();
      final originalDocument = controller.state.document;
      var attempts = 0;
      repository.onLoadDiff = (request) async {
        attempts += 1;
        if (attempts == 1) {
          return const <DiffLine>[
            DiffLine(kind: DiffLineKind.hunk, text: 'malformed hunk'),
          ];
        }
        return twoHunkLines;
      };

      await controller.selectAlgorithm(DiffAlgorithm.histogram);

      expect(controller.state.document, same(originalDocument));
      expect(controller.state.loadingDiff, isFalse);
      expect(controller.state.algorithm, DiffAlgorithm.gitSetting);
      expect(controller.state.displayedAlgorithm, DiffAlgorithm.gitSetting);
      expect(controller.state.error, isA<FormatException>());

      await controller.selectAlgorithm(DiffAlgorithm.histogram);

      expect(attempts, 2);
      expect(controller.state.document?.hunks, hasLength(2));
      expect(controller.state.algorithm, DiffAlgorithm.histogram);
      expect(controller.state.displayedAlgorithm, DiffAlgorithm.histogram);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'commits cache diff keys while the working tree always reloads',
    () async {
      Future<int> visitsToA(String sha) async {
        final repository = FakeFullDiffRepository(
          files: const <GitFileChange>[fileA, fileB],
          lines: oneHunkLines,
        );
        final controller = FullDiffSessionController(
          repository: repository,
          commits: <GitCommit>[commit(sha)],
          initialIndex: 0,
        );

        await controller.initialize();
        await controller.selectFile('lib/b.dart');
        await controller.selectFile('lib/a.dart');

        return repository.diffRequests
            .where((request) => request.path == 'lib/a.dart')
            .length;
      }

      expect(await visitsToA('1'), 1);
      expect(await visitsToA(''), 2);
    },
  );

  test(
    'parent and file selection reset hunks and stepping stops at both ends',
    () async {
      final repository = FakeFullDiffRepository(
        files: const <GitFileChange>[fileA, fileB],
        lines: twoHunkLines,
      );
      final controller = FullDiffSessionController(
        repository: repository,
        commits: <GitCommit>[
          commit('merge', parents: const <String>['p1', 'p2']),
        ],
        initialIndex: 0,
      );
      await controller.initialize();

      controller.stepHunk(-1);
      expect(controller.state.activeHunkIndex, 0);
      controller.selectHunk(1);
      controller.stepHunk(1);
      expect(controller.state.activeHunkIndex, 1);

      await controller.selectParent('p2');
      expect(controller.state.activeHunkIndex, 0);
      controller.selectHunk(1);

      await controller.selectFile('lib/b.dart');
      expect(controller.state.activeHunkIndex, 0);
    },
  );

  test(
    'async completion cannot mutate state or notify after disposal',
    () async {
      final files = Completer<List<GitFileChange>>();
      final repository = FakeFullDiffRepository(
        lines: oneHunkLines,
        onLoadFiles: (_) => files.future,
      );
      final controller = FullDiffSessionController(
        repository: repository,
        commits: <GitCommit>[commit('1')],
        initialIndex: 0,
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      final load = controller.initialize();
      final notificationsAtDispose = notifications;
      controller.dispose();
      files.complete(const <GitFileChange>[fileA]);
      await load;

      expect(notifications, notificationsAtDispose);
      expect(controller.state.selectedPath, isNull);
      expect(repository.diffRequests, isEmpty);
    },
  );
}
