import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_syntax_contract.dart';
import 'package:yogit/git.dart';

class FakeFullDiffRepository implements FullDiffRepository {
  FakeFullDiffRepository({this.root = '/repo'});

  @override
  final String root;

  final fileRequests = <({String sha, String? parent})>[];
  final diffRequests =
      <
        ({
          String sha,
          String path,
          String? parent,
          DiffAlgorithm algorithm,
          bool whitespace,
        })
      >[];
  final contentRequests = <({String sha, String path, String? parent})>[];
  final blameRequests = <({String sha, String path, String? parent})>[];
  final historyRequests = <({String sha, String path})>[];

  Future<List<GitFileChange>> Function(GitCommit, String?)? files;
  Future<List<DiffLine>> Function(
    GitCommit,
    GitFileChange,
    String?,
    DiffAlgorithm,
    bool,
  )?
  diff;
  Future<Uint8List> Function(GitCommit, GitFileChange, String?)? content;
  Future<List<GitBlameLine>> Function(
    GitCommit,
    GitFileChange,
    String?,
    Uint8List?,
  )?
  blame;
  Future<List<GitFileHistoryRecord>> Function(GitCommit, GitFileChange)?
  history;

  @override
  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent}) {
    fileRequests.add((sha: commit.sha, parent: parent));
    return files?.call(commit, parent) ?? Future.value(const []);
  }

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
  }) {
    diffRequests.add((
      sha: commit.sha,
      path: file.path,
      parent: parent,
      algorithm: algorithm,
      whitespace: ignoreWhitespace,
    ));
    return diff?.call(commit, file, parent, algorithm, ignoreWhitespace) ??
        Future.value(const []);
  }

  @override
  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  }) {
    contentRequests.add((sha: commit.sha, path: file.path, parent: parent));
    return content?.call(commit, file, parent) ?? Future.value(Uint8List(0));
  }

  @override
  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  }) {
    blameRequests.add((sha: commit.sha, path: file.path, parent: parent));
    return blame?.call(commit, file, parent, workingTreeBytes) ??
        Future.value(const []);
  }

  @override
  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  ) {
    historyRequests.add((sha: commit.sha, path: file.path));
    return history?.call(commit, file) ?? Future.value(const []);
  }
}

const fixtureIdentity = GitIdentity(
  name: 'Suwon Chae',
  email: 'suwon@example.com',
);

const commitA = GitCommit(
  sha: '40aff6d',
  shortSha: '40aff6d',
  parents: ['62874a0'],
  author: fixtureIdentity,
  authorTimestamp: 1720573200,
  committer: fixtureIdentity,
  committerTimestamp: 1720573200,
  refs: [],
  subject: 'Make Retina windows pixel-aware',
);

const fileA = GitFileChange(
  path: 'src/drlua.pas',
  status: 'M',
  additions: 12,
  deletions: 4,
);

const twoHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,7 +10,7 @@ Configure'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 1',
    oldNumber: 10,
    newNumber: 10,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 2',
    oldNumber: 11,
    newNumber: 11,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 3',
    oldNumber: 12,
    newNumber: 12,
  ),
  DiffLine(kind: DiffLineKind.delete, text: 'first old', oldNumber: 13),
  DiffLine(kind: DiffLineKind.add, text: 'first new', newNumber: 13),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 1',
    oldNumber: 14,
    newNumber: 14,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 2',
    oldNumber: 15,
    newNumber: 15,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 3',
    oldNumber: 16,
    newNumber: 16,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -20,2 +20,2 @@ SetupBase'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'second context',
    oldNumber: 20,
    newNumber: 20,
  ),
  DiffLine(kind: DiffLineKind.delete, text: 'second old', oldNumber: 21),
  DiffLine(kind: DiffLineKind.add, text: 'second new', newNumber: 21),
];

final twoHunkDocument = DiffDocument.fromLines(twoHunkLines);

final addedOnlyDocument = DiffDocument.fromLines(const [
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1 @@'),
  DiffLine(kind: DiffLineKind.add, text: 'added line', newNumber: 1),
]);

final resultFile = FileDocument.fromBytes(
  revision: commitA.sha,
  path: fileA.path,
  side: FileDocumentSide.result,
  bytes: Uint8List.fromList(
    utf8.encode(
      '${List.filled(313, 'unchanged').join('\n')}\n'
      'Log(LOGINFO, BASE MODULE VERSION);\n',
    ),
  ),
  gitMarkedBinary: false,
);

final historyEntries = [
  FileHistoryEntry(
    commit: commitA,
    path: fileA.path,
    oldPath: null,
    status: 'M',
  ),
  FileHistoryEntry(
    commit: GitCommit(
      sha: '62874a0',
      shortSha: '62874a0',
      parents: const ['2db06c0'],
      author: fixtureIdentity,
      authorTimestamp: 1720486800,
      committer: fixtureIdentity,
      committerTimestamp: 1720486800,
      refs: const [],
      subject: 'Restore saved window pixel dimensions',
    ),
    path: fileA.path,
    oldPath: null,
    status: 'M',
  ),
];

class NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const NoopSyntaxHighlighter();

  @override
  String? languageForPath(String path) => null;

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];
}

const fakeHighlighter = NoopSyntaxHighlighter();

Widget qaApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: child),
);
