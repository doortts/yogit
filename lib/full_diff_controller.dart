import 'package:flutter/foundation.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

typedef FullDiffCacheKey = ({
  String sha,
  String? parent,
  String path,
  DiffAlgorithm algorithm,
  bool ignoreWhitespace,
});

const _unset = Object();

@immutable
class FullDiffSessionState {
  const FullDiffSessionState({
    required this.commitIndex,
    required this.parent,
    required this.files,
    required this.selectedPath,
    required this.document,
    required this.activeHunkIndex,
    required this.algorithm,
    required this.displayedAlgorithm,
    required this.ignoreWhitespace,
    required this.displayedIgnoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.loadingFiles,
    required this.loadingDiff,
    required this.error,
  });

  final int commitIndex;
  final String? parent;
  final List<GitFileChange> files;
  final String? selectedPath;
  final DiffDocument? document;
  final int activeHunkIndex;
  final DiffAlgorithm algorithm;
  final DiffAlgorithm displayedAlgorithm;
  final bool ignoreWhitespace;
  final bool displayedIgnoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final bool loadingFiles;
  final bool loadingDiff;
  final Object? error;

  factory FullDiffSessionState.initial(GitCommit commit, int commitIndex) =>
      FullDiffSessionState(
        commitIndex: commitIndex,
        parent: commit.parents.isEmpty ? null : commit.parents.first,
        files: const <GitFileChange>[],
        selectedPath: null,
        document: null,
        activeHunkIndex: 0,
        algorithm: DiffAlgorithm.gitSetting,
        displayedAlgorithm: DiffAlgorithm.gitSetting,
        ignoreWhitespace: false,
        displayedIgnoreWhitespace: false,
        wrapLines: true,
        focusMode: false,
        loadingFiles: false,
        loadingDiff: false,
        error: null,
      );

  FullDiffSessionState copyWith({
    int? commitIndex,
    Object? parent = _unset,
    List<GitFileChange>? files,
    Object? selectedPath = _unset,
    Object? document = _unset,
    int? activeHunkIndex,
    DiffAlgorithm? algorithm,
    DiffAlgorithm? displayedAlgorithm,
    bool? ignoreWhitespace,
    bool? displayedIgnoreWhitespace,
    bool? wrapLines,
    bool? focusMode,
    bool? loadingFiles,
    bool? loadingDiff,
    Object? error = _unset,
  }) => FullDiffSessionState(
    commitIndex: commitIndex ?? this.commitIndex,
    parent: identical(parent, _unset) ? this.parent : parent as String?,
    files: files ?? this.files,
    selectedPath: identical(selectedPath, _unset)
        ? this.selectedPath
        : selectedPath as String?,
    document: identical(document, _unset)
        ? this.document
        : document as DiffDocument?,
    activeHunkIndex: activeHunkIndex ?? this.activeHunkIndex,
    algorithm: algorithm ?? this.algorithm,
    displayedAlgorithm: displayedAlgorithm ?? this.displayedAlgorithm,
    ignoreWhitespace: ignoreWhitespace ?? this.ignoreWhitespace,
    displayedIgnoreWhitespace:
        displayedIgnoreWhitespace ?? this.displayedIgnoreWhitespace,
    wrapLines: wrapLines ?? this.wrapLines,
    focusMode: focusMode ?? this.focusMode,
    loadingFiles: loadingFiles ?? this.loadingFiles,
    loadingDiff: loadingDiff ?? this.loadingDiff,
    error: identical(error, _unset) ? this.error : error,
  );
}

FullDiffSessionState _initialState(List<GitCommit> commits, int initialIndex) {
  if (commits.isEmpty) {
    throw ArgumentError.value(commits, 'commits', 'must not be empty');
  }
  final index = initialIndex.clamp(0, commits.length - 1);
  return FullDiffSessionState.initial(commits[index], index);
}

class FullDiffSessionController extends ChangeNotifier {
  FullDiffSessionController({
    required this.repository,
    required List<GitCommit> commits,
    required int initialIndex,
  }) : commits = List<GitCommit>.unmodifiable(commits),
       state = _initialState(commits, initialIndex);

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final Map<FullDiffCacheKey, Future<DiffDocument>> _cache =
      <FullDiffCacheKey, Future<DiffDocument>>{};
  int _fileGeneration = 0;
  int _diffGeneration = 0;
  bool _disposed = false;
  FullDiffSessionState state;

  Future<void> initialize() => _loadFiles();

  Future<void> selectCommit(int index) {
    if (_disposed) return Future<void>.value();
    final selectedIndex = index.clamp(0, commits.length - 1);
    final commit = commits[selectedIndex];
    _replace(
      state.copyWith(
        commitIndex: selectedIndex,
        parent: commit.parents.isEmpty ? null : commit.parents.first,
      ),
    );
    return _loadFiles();
  }

  Future<void> selectParent(String? parent) {
    if (_disposed) return Future<void>.value();
    _replace(state.copyWith(parent: parent));
    return _loadFiles();
  }

  Future<void> selectFile(String path) {
    if (_disposed) return Future<void>.value();
    _replace(
      state.copyWith(
        selectedPath: path,
        document: null,
        activeHunkIndex: 0,
        error: null,
      ),
    );
    return _loadDiff();
  }

  Future<void> selectAlgorithm(DiffAlgorithm algorithm) {
    if (_disposed) return Future<void>.value();
    _replace(state.copyWith(algorithm: algorithm, error: null));
    if (state.selectedPath == null) return Future<void>.value();
    return _loadDiff(retainDocumentOnFailure: true);
  }

  Future<void> setIgnoreWhitespace(bool ignoreWhitespace) {
    if (_disposed) return Future<void>.value();
    _replace(state.copyWith(ignoreWhitespace: ignoreWhitespace, error: null));
    if (state.selectedPath == null) return Future<void>.value();
    return _loadDiff(retainDocumentOnFailure: true);
  }

  void setWrapLines(bool wrapLines) {
    if (_disposed) return;
    _replace(state.copyWith(wrapLines: wrapLines));
  }

  void setFocusMode(bool focusMode) {
    if (_disposed) return;
    _replace(state.copyWith(focusMode: focusMode));
  }

  void selectHunk(int index) {
    if (_disposed) return;
    final hunkCount = state.document?.hunks.length ?? 0;
    final selectedIndex = hunkCount == 0 ? 0 : index.clamp(0, hunkCount - 1);
    _replace(state.copyWith(activeHunkIndex: selectedIndex));
  }

  void stepHunk(int delta) {
    selectHunk(state.activeHunkIndex + delta);
  }

  Future<void> _loadFiles() async {
    if (_disposed) return;
    final generation = ++_fileGeneration;
    ++_diffGeneration;
    final commitIndex = state.commitIndex;
    final commit = commits[commitIndex];
    final parent = state.parent;
    _replace(
      state.copyWith(
        files: const <GitFileChange>[],
        selectedPath: null,
        document: null,
        activeHunkIndex: 0,
        loadingFiles: true,
        loadingDiff: false,
        error: null,
      ),
    );

    late final List<GitFileChange> files;
    try {
      files = await repository.loadFiles(commit, parent: parent);
    } catch (error) {
      if (_matchesFileRequest(generation, commitIndex, commit.sha, parent)) {
        _replace(
          state.copyWith(loadingFiles: false, loadingDiff: false, error: error),
        );
      }
      return;
    }
    if (!_matchesFileRequest(generation, commitIndex, commit.sha, parent)) {
      return;
    }

    final immutableFiles = List<GitFileChange>.unmodifiable(files);
    if (immutableFiles.isEmpty) {
      _replace(
        state.copyWith(
          files: immutableFiles,
          selectedPath: null,
          document: null,
          activeHunkIndex: 0,
          loadingFiles: false,
          loadingDiff: false,
          error: null,
        ),
      );
      return;
    }

    _replace(
      state.copyWith(
        files: immutableFiles,
        selectedPath: immutableFiles.first.path,
        document: null,
        activeHunkIndex: 0,
        loadingFiles: false,
        error: null,
      ),
    );
    await _loadDiff();
  }

  Future<void> _loadDiff({bool retainDocumentOnFailure = false}) async {
    if (_disposed) return;
    final path = state.selectedPath;
    if (path == null) return;

    final generation = ++_diffGeneration;
    final commitIndex = state.commitIndex;
    final commit = commits[commitIndex];
    final parent = state.parent;
    final algorithm = state.algorithm;
    final ignoreWhitespace = state.ignoreWhitespace;
    _replace(state.copyWith(loadingDiff: true, error: null));

    late final DiffDocument document;
    try {
      document = await _loadDocument(
        commit,
        parent,
        path,
        algorithm,
        ignoreWhitespace,
      );
    } catch (error) {
      if (_matchesDiffRequest(
        generation,
        commitIndex,
        commit.sha,
        parent,
        path,
        algorithm,
        ignoreWhitespace,
      )) {
        _replace(
          state.copyWith(
            document: retainDocumentOnFailure ? state.document : null,
            algorithm: retainDocumentOnFailure
                ? state.displayedAlgorithm
                : state.algorithm,
            ignoreWhitespace: retainDocumentOnFailure
                ? state.displayedIgnoreWhitespace
                : state.ignoreWhitespace,
            loadingDiff: false,
            error: error,
          ),
        );
      }
      return;
    }
    if (!_matchesDiffRequest(
      generation,
      commitIndex,
      commit.sha,
      parent,
      path,
      algorithm,
      ignoreWhitespace,
    )) {
      return;
    }

    final activeHunkIndex = document.hunks.isEmpty
        ? 0
        : state.activeHunkIndex.clamp(0, document.hunks.length - 1);
    _replace(
      state.copyWith(
        document: document,
        activeHunkIndex: activeHunkIndex,
        displayedAlgorithm: algorithm,
        displayedIgnoreWhitespace: ignoreWhitespace,
        loadingDiff: false,
        error: null,
      ),
    );
  }

  Future<DiffDocument> _loadDocument(
    GitCommit commit,
    String? parent,
    String path,
    DiffAlgorithm algorithm,
    bool ignoreWhitespace,
  ) {
    Future<DiffDocument> read() async => DiffDocument.fromLines(
      await repository.loadDiff(
        commit,
        path,
        parent: parent,
        algorithm: algorithm,
        ignoreWhitespace: ignoreWhitespace,
      ),
    );

    if (commit.isWorkingTree) return read();
    final key = (
      sha: commit.sha,
      parent: parent,
      path: path,
      algorithm: algorithm,
      ignoreWhitespace: ignoreWhitespace,
    );
    final cached = _cache[key];
    if (cached != null) return cached;

    final future = read();
    _cache[key] = future;
    return future.onError((Object error, StackTrace stackTrace) {
      if (identical(_cache[key], future)) _cache.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  bool _matchesFileRequest(
    int generation,
    int commitIndex,
    String sha,
    String? parent,
  ) =>
      !_disposed &&
      generation == _fileGeneration &&
      state.commitIndex == commitIndex &&
      commits[state.commitIndex].sha == sha &&
      state.parent == parent;

  bool _matchesDiffRequest(
    int generation,
    int commitIndex,
    String sha,
    String? parent,
    String path,
    DiffAlgorithm algorithm,
    bool ignoreWhitespace,
  ) =>
      !_disposed &&
      generation == _diffGeneration &&
      state.commitIndex == commitIndex &&
      commits[state.commitIndex].sha == sha &&
      state.parent == parent &&
      state.selectedPath == path &&
      state.algorithm == algorithm &&
      state.ignoreWhitespace == ignoreWhitespace;

  void _replace(FullDiffSessionState nextState) {
    if (_disposed) return;
    state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fileGeneration += 1;
    _diffGeneration += 1;
    super.dispose();
  }
}
