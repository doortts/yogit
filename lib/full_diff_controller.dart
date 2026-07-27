import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

typedef PatchCacheKey = ({
  String base,
  String target,
  String? parent,
  String? oldPath,
  String newPath,
  DiffAlgorithm algorithm,
  bool ignoreWhitespace,
  DiffScope scope,
});

typedef FileCacheKey = ({
  String revision,
  String path,
  String? parent,
  FileDocumentSide side,
});

typedef EncodingCacheKey = ({
  String repositoryRoot,
  String revision,
  String path,
  String? oldPath,
  String? parent,
  FileDocumentSide side,
});

typedef BlameCacheKey = ({String revision, String path});
typedef HistoryCacheKey = ({String startRevision, String path});

const _unset = Object();
const _cacheCapacity = 32;
const _rawCacheByteLimit = 64 * 1024 * 1024;

class FullDiffEncodingCache {
  FullDiffEncodingCache();

  static final FullDiffEncodingCache shared = FullDiffEncodingCache();

  final _entries = <EncodingCacheKey, FileContentKind>{};

  FileContentKind? read(EncodingCacheKey key) => _entries[key];

  void write(EncodingCacheKey key, FileContentKind kind) {
    _entries[key] = kind;
  }
}

@immutable
class AsyncResource<T> {
  const AsyncResource({this.data, this.loading = false, this.error});

  final T? data;
  final bool loading;
  final Object? error;

  AsyncResource<T> copyWith({
    Object? data = _unset,
    bool? loading,
    Object? error = _unset,
  }) => AsyncResource<T>(
    data: identical(data, _unset) ? this.data : data as T?,
    loading: loading ?? this.loading,
    error: identical(error, _unset) ? this.error : error,
  );
}

@immutable
class FullDiffSessionState {
  const FullDiffSessionState({
    required this.nearbyCommits,
    required this.selectedCommit,
    required this.parent,
    required this.files,
    required this.selectedFile,
    required this.view,
    required this.layout,
    required this.activeAnchor,
    required this.fullFileScrollTarget,
    required this.requestedScope,
    required this.appliedScope,
    required this.requestedAlgorithm,
    required this.appliedAlgorithm,
    required this.requestedIgnoreWhitespace,
    required this.appliedIgnoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.filesResource,
    required this.patch,
    required this.file,
    required this.cachedEncodingKind,
    required this.blame,
    required this.history,
    required this.selectedHistoryEntry,
    required this.historyContext,
    required this.selectionGeneration,
    required this.navigationSerial,
  });

  final List<GitCommit> nearbyCommits;
  final GitCommit selectedCommit;
  final String? parent;
  final List<GitFileChange> files;
  final GitFileChange? selectedFile;
  final FullDiffView view;
  final DiffLayout layout;
  final DiffAnchor? activeAnchor;
  final DiffSourceTarget? fullFileScrollTarget;
  final DiffScope requestedScope;
  final DiffScope appliedScope;
  final DiffAlgorithm requestedAlgorithm;
  final DiffAlgorithm appliedAlgorithm;
  final bool requestedIgnoreWhitespace;
  final bool appliedIgnoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final AsyncResource<List<GitFileChange>> filesResource;
  final AsyncResource<DiffDocument> patch;
  final AsyncResource<FileDocument> file;
  final FileContentKind? cachedEncodingKind;
  final AsyncResource<BlameDocument> blame;
  final AsyncResource<List<FileHistoryEntry>> history;
  final FileHistoryEntry? selectedHistoryEntry;
  final HistoryCacheKey? historyContext;
  final int selectionGeneration;
  final int navigationSerial;

  String get encodingLabel => switch (file.data?.kind ?? cachedEncodingKind) {
    FileContentKind.utf8 => 'UTF-8',
    FileContentKind.binary => 'Binary',
    FileContentKind.unsupportedEncoding => 'Unsupported encoding',
    FileContentKind.tooLarge => 'Too large',
    null => '',
  };

  bool get richRenderingEnabled {
    final document = file.data;
    return document != null && !document.disableRichRendering;
  }

  FullDiffPreferences get preferences => FullDiffPreferences(
    view: view,
    layout: layout,
    scope: appliedScope,
    algorithm: appliedAlgorithm,
    ignoreWhitespace: appliedIgnoreWhitespace,
    wrapLines: wrapLines,
  );

  FullDiffSessionState copyWith({
    List<GitCommit>? nearbyCommits,
    GitCommit? selectedCommit,
    Object? parent = _unset,
    List<GitFileChange>? files,
    Object? selectedFile = _unset,
    FullDiffView? view,
    DiffLayout? layout,
    Object? activeAnchor = _unset,
    Object? fullFileScrollTarget = _unset,
    DiffScope? requestedScope,
    DiffScope? appliedScope,
    DiffAlgorithm? requestedAlgorithm,
    DiffAlgorithm? appliedAlgorithm,
    bool? requestedIgnoreWhitespace,
    bool? appliedIgnoreWhitespace,
    bool? wrapLines,
    bool? focusMode,
    AsyncResource<List<GitFileChange>>? filesResource,
    AsyncResource<DiffDocument>? patch,
    AsyncResource<FileDocument>? file,
    Object? cachedEncodingKind = _unset,
    AsyncResource<BlameDocument>? blame,
    AsyncResource<List<FileHistoryEntry>>? history,
    Object? selectedHistoryEntry = _unset,
    Object? historyContext = _unset,
    int? selectionGeneration,
    int? navigationSerial,
  }) => FullDiffSessionState(
    nearbyCommits: nearbyCommits ?? this.nearbyCommits,
    selectedCommit: selectedCommit ?? this.selectedCommit,
    parent: identical(parent, _unset) ? this.parent : parent as String?,
    files: files ?? this.files,
    selectedFile: identical(selectedFile, _unset)
        ? this.selectedFile
        : selectedFile as GitFileChange?,
    view: view ?? this.view,
    layout: layout ?? this.layout,
    activeAnchor: identical(activeAnchor, _unset)
        ? this.activeAnchor
        : activeAnchor as DiffAnchor?,
    fullFileScrollTarget: identical(fullFileScrollTarget, _unset)
        ? this.fullFileScrollTarget
        : fullFileScrollTarget as DiffSourceTarget?,
    requestedScope: requestedScope ?? this.requestedScope,
    appliedScope: appliedScope ?? this.appliedScope,
    requestedAlgorithm: requestedAlgorithm ?? this.requestedAlgorithm,
    appliedAlgorithm: appliedAlgorithm ?? this.appliedAlgorithm,
    requestedIgnoreWhitespace:
        requestedIgnoreWhitespace ?? this.requestedIgnoreWhitespace,
    appliedIgnoreWhitespace:
        appliedIgnoreWhitespace ?? this.appliedIgnoreWhitespace,
    wrapLines: wrapLines ?? this.wrapLines,
    focusMode: focusMode ?? this.focusMode,
    filesResource: filesResource ?? this.filesResource,
    patch: patch ?? this.patch,
    file: file ?? this.file,
    cachedEncodingKind: identical(cachedEncodingKind, _unset)
        ? this.cachedEncodingKind
        : cachedEncodingKind as FileContentKind?,
    blame: blame ?? this.blame,
    history: history ?? this.history,
    selectedHistoryEntry: identical(selectedHistoryEntry, _unset)
        ? this.selectedHistoryEntry
        : selectedHistoryEntry as FileHistoryEntry?,
    historyContext: identical(historyContext, _unset)
        ? this.historyContext
        : historyContext as HistoryCacheKey?,
    selectionGeneration: selectionGeneration ?? this.selectionGeneration,
    navigationSerial: navigationSerial ?? this.navigationSerial,
  );
}

class _CacheEntry<V> {
  _CacheEntry({required this.future, required this.tick});

  final Future<V> future;
  int tick;
  int bytes = 0;
}

class _LruFutureCache<K, V> {
  _LruFutureCache({
    required this.capacity,
    required this.sizeOf,
    required this.nextTick,
  });

  final int capacity;
  final int Function(V value) sizeOf;
  final int Function() nextTick;
  final _entries = <K, _CacheEntry<V>>{};

  int get length => _entries.length;
  int get resolvedBytes =>
      _entries.values.fold(0, (sum, entry) => sum + entry.bytes);
  int? get oldestTick => _entries.isEmpty
      ? null
      : _entries.values.map((entry) => entry.tick).reduce(math.min);

  Future<V> getOrLoad(K key, Future<V> Function() loader) {
    final cached = _entries.remove(key);
    if (cached != null) {
      cached.tick = nextTick();
      _entries[key] = cached;
      return cached.future;
    }

    final entry = _CacheEntry<V>(
      future: Future<V>.sync(loader),
      tick: nextTick(),
    );
    _entries[key] = entry;
    unawaited(
      entry.future.then<void>(
        (value) {
          if (!identical(_entries[key], entry)) return;
          entry.bytes = sizeOf(value);
          while (_entries.length > capacity) {
            _entries.remove(_entries.keys.first);
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_entries[key], entry)) _entries.remove(key);
        },
      ),
    );
    return entry.future;
  }

  void removeOldest() {
    if (_entries.isNotEmpty) _entries.remove(_entries.keys.first);
  }
}

FullDiffSessionState _initialState(
  List<GitCommit> commits,
  int initialIndex,
  FullDiffPreferences initialPreferences,
) {
  if (commits.isEmpty) {
    throw ArgumentError.value(commits, 'commits', 'must not be empty');
  }
  final nearbyCommits = List<GitCommit>.unmodifiable(commits);
  final selectedCommit =
      nearbyCommits[initialIndex.clamp(0, nearbyCommits.length - 1)];
  return FullDiffSessionState(
    nearbyCommits: nearbyCommits,
    selectedCommit: selectedCommit,
    parent: selectedCommit.parents.isEmpty
        ? null
        : selectedCommit.parents.first,
    files: const [],
    selectedFile: null,
    view: initialPreferences.view,
    layout: initialPreferences.layout,
    activeAnchor: null,
    fullFileScrollTarget: null,
    requestedScope: initialPreferences.scope,
    appliedScope: initialPreferences.scope,
    requestedAlgorithm: initialPreferences.algorithm,
    appliedAlgorithm: initialPreferences.algorithm,
    requestedIgnoreWhitespace: initialPreferences.ignoreWhitespace,
    appliedIgnoreWhitespace: initialPreferences.ignoreWhitespace,
    wrapLines: initialPreferences.wrapLines,
    focusMode: false,
    filesResource: const AsyncResource(),
    patch: const AsyncResource(),
    file: const AsyncResource(),
    cachedEncodingKind: null,
    blame: const AsyncResource(),
    history: const AsyncResource(),
    selectedHistoryEntry: null,
    historyContext: null,
    selectionGeneration: 0,
    navigationSerial: 0,
  );
}

DiffAnchor? nearestAnchor(DiffDocument document, int? sourceLine) {
  if (document.hunks.isEmpty) return null;
  if (sourceLine == null) return document.hunks.first.anchor;
  return document.hunks.map((hunk) => hunk.anchor).reduce((best, candidate) {
    int distance(DiffAnchor anchor) =>
        ((anchor.newLine ?? anchor.oldLine ?? 0) - sourceLine).abs();
    return distance(candidate) < distance(best) ? candidate : best;
  });
}

class FullDiffSessionController extends ChangeNotifier {
  FullDiffSessionController({
    required this.repository,
    required List<GitCommit> commits,
    required int initialIndex,
    FullDiffPreferences initialPreferences = const FullDiffPreferences(),
    FullDiffEncodingCache? encodingCache,
  }) : _encodingCache = encodingCache ?? FullDiffEncodingCache.shared,
       state = _initialState(commits, initialIndex, initialPreferences) {
    _patchCache = _LruFutureCache(
      capacity: _cacheCapacity,
      sizeOf: _patchSize,
      nextTick: _nextCacheTick,
    );
    _fileCache = _LruFutureCache(
      capacity: _cacheCapacity,
      sizeOf: (document) => document.bytes.length,
      nextTick: _nextCacheTick,
    );
    _blameCache = _LruFutureCache(
      capacity: _cacheCapacity,
      sizeOf: (_) => 0,
      nextTick: _nextCacheTick,
    );
    _historyCache = _LruFutureCache(
      capacity: _cacheCapacity,
      sizeOf: (_) => 0,
      nextTick: _nextCacheTick,
    );
  }

  final FullDiffRepository repository;
  final FullDiffEncodingCache _encodingCache;
  late final _LruFutureCache<PatchCacheKey, DiffDocument> _patchCache;
  late final _LruFutureCache<FileCacheKey, FileDocument> _fileCache;
  late final _LruFutureCache<BlameCacheKey, BlameDocument> _blameCache;
  late final _LruFutureCache<HistoryCacheKey, List<FileHistoryEntry>>
  _historyCache;

  int _cacheClock = 0;
  int _selectionGeneration = 0;
  int _fullFileScrollGeneration = 0;
  int _filesRequest = 0;
  int _patchRequest = 0;
  int _fileRequest = 0;
  int _blameRequest = 0;
  int _historyRequest = 0;
  bool _disposed = false;

  FullDiffSessionState state;

  int get debugPatchCacheLength => _patchCache.length;
  int get debugFileCacheLength => _fileCache.length;
  int get debugRawCacheBytes =>
      _patchCache.resolvedBytes + _fileCache.resolvedBytes;

  int _nextCacheTick() => ++_cacheClock;

  Future<void> initialize() => _loadFiles();

  Future<void> retryFiles() {
    final entry = state.selectedHistoryEntry;
    if (entry != null && state.historyContext != null) {
      return selectHistoryEntry(entry);
    }
    return _loadFiles();
  }

  Future<void> retryPatch() => _loadPatch();

  Future<void> retryFile() => _loadFile();

  Future<void> retryHistorySelection() async {
    final entry = state.selectedHistoryEntry;
    if (_disposed || entry == null) return;
    await selectHistoryEntry(entry);
  }

  Future<void> selectCommit(GitCommit commit) async {
    if (_disposed || state.selectedCommit.sha == commit.sha) return;
    final commits =
        state.nearbyCommits.any((candidate) => candidate.sha == commit.sha)
        ? state.nearbyCommits
        : [commit, ...state.nearbyCommits];
    _beginSelection(
      commits: commits,
      commit: commit,
      parent: commit.parents.isEmpty ? null : commit.parents.first,
      files: const [],
      selectedFile: null,
      filesResource: const AsyncResource(),
    );
    await _loadFiles();
  }

  Future<void> selectParent(String? parent) async {
    if (_disposed || state.parent == parent) return;
    _beginSelection(
      commits: state.nearbyCommits,
      commit: state.selectedCommit,
      parent: parent,
      files: const [],
      selectedFile: null,
      filesResource: const AsyncResource(),
    );
    await _loadFiles();
  }

  Future<void> selectFile(GitFileChange file) async {
    if (_disposed || _sameFile(state.selectedFile, file)) return;
    _beginSelection(
      commits: state.nearbyCommits,
      commit: state.selectedCommit,
      parent: state.parent,
      files: state.files,
      selectedFile: file,
      filesResource: state.filesResource,
    );
    await _loadSelectedResources();
  }

  Future<void> selectHistoryEntry(FileHistoryEntry entry) async {
    if (_disposed) return;
    final commits = [
      entry.commit,
      for (final commit in state.nearbyCommits)
        if (commit.sha != entry.commit.sha) commit,
    ];
    final parent = entry.commit.parents.isEmpty
        ? null
        : entry.commit.parents.first;
    _beginSelection(
      commits: commits,
      commit: entry.commit,
      parent: parent,
      files: const [],
      selectedFile: null,
      filesResource: const AsyncResource(),
      preserveHistory: true,
      selectedHistoryEntry: entry,
    );
    final generation = _selectionGeneration;
    final request = ++_filesRequest;
    _replace(state.copyWith(filesResource: const AsyncResource(loading: true)));

    late final List<GitFileChange> files;
    try {
      files = await repository.loadFiles(entry.commit, parent: parent);
    } catch (error) {
      if (_acceptsFiles(
        generation: generation,
        request: request,
        commit: entry.commit,
        parent: parent,
      )) {
        _replace(state.copyWith(filesResource: AsyncResource(error: error)));
      }
      return;
    }
    if (!_acceptsFiles(
      generation: generation,
      request: request,
      commit: entry.commit,
      parent: parent,
    )) {
      return;
    }

    final immutableFiles = List<GitFileChange>.unmodifiable(files);
    late final GitFileChange file;
    try {
      file = immutableFiles.firstWhere(
        (candidate) =>
            candidate.path == entry.path ||
            candidate.oldPath == entry.path ||
            (entry.oldPath != null &&
                (candidate.path == entry.oldPath ||
                    candidate.oldPath == entry.oldPath)),
      );
    } catch (error) {
      _replace(
        state.copyWith(
          files: immutableFiles,
          filesResource: AsyncResource(data: immutableFiles, error: error),
        ),
      );
      return;
    }
    _replace(
      state.copyWith(
        files: immutableFiles,
        selectedFile: file,
        cachedEncodingKind: _cachedEncodingKind(entry.commit, parent, file),
        filesResource: AsyncResource(data: immutableFiles),
      ),
    );
    await _loadSelectedResources();
  }

  void replaceNearbyCommits(List<GitCommit> commits) {
    if (_disposed) return;
    final selectedSha = state.selectedCommit.sha;
    final selected = commits.where((commit) => commit.sha == selectedSha);
    _replace(
      state.copyWith(
        nearbyCommits: List.unmodifiable(
          selected.isEmpty ? [state.selectedCommit, ...commits] : commits,
        ),
        selectedCommit: selected.isEmpty
            ? state.selectedCommit
            : selected.single,
      ),
    );
  }

  void setView(FullDiffView view) {
    if (_disposed || state.view == view) return;
    _fullFileScrollGeneration++;
    _replace(state.copyWith(view: view, fullFileScrollTarget: null));
    if (view == FullDiffView.blame) unawaited(_ensureBlame());
    if (view == FullDiffView.history) unawaited(_ensureHistory());
  }

  void setLayout(DiffLayout layout) {
    if (_disposed || state.layout == layout) return;
    _replace(state.copyWith(layout: layout));
  }

  Future<void> setScope(DiffScope scope) async {
    if (_disposed || state.requestedScope == scope) return;
    final currentDocument = state.patch.data;
    final preservedTarget =
        scope == DiffScope.hunks &&
            state.appliedScope == DiffScope.fullFile &&
            currentDocument != null &&
            diffDocumentContainsSourceTarget(
              currentDocument,
              state.fullFileScrollTarget,
            )
        ? state.fullFileScrollTarget
        : null;
    final sourceTarget =
        preservedTarget ?? _anchorSourceTarget(state.activeAnchor);
    final sourceLine = _sourceLine(sourceTarget);
    final scrollTargetGeneration = ++_fullFileScrollGeneration;
    if (state.selectedFile == null) {
      _replace(
        state.copyWith(requestedScope: scope, fullFileScrollTarget: null),
      );
      return;
    }
    _replace(
      state.copyWith(
        requestedScope: scope,
        fullFileScrollTarget: null,
        patch: state.patch.copyWith(loading: true, error: null),
      ),
    );
    await _loadPatch(
      preserveDataOnFailure: true,
      sourceLine: sourceLine,
      fullFileScrollTarget: scope == DiffScope.fullFile ? sourceTarget : null,
      rollbackFullFileScrollTarget: preservedTarget,
      scrollTargetGeneration: scrollTargetGeneration,
      propagateError: true,
    );
  }

  Future<void> selectAlgorithm(DiffAlgorithm algorithm) async {
    if (_disposed || state.requestedAlgorithm == algorithm) return;
    final sourceLine = _anchorSourceLine(state.activeAnchor);
    final scrollTargetGeneration = ++_fullFileScrollGeneration;
    if (state.selectedFile == null) {
      _replace(
        state.copyWith(
          requestedAlgorithm: algorithm,
          fullFileScrollTarget: null,
        ),
      );
      return;
    }
    _replace(
      state.copyWith(
        requestedAlgorithm: algorithm,
        fullFileScrollTarget: null,
        patch: state.patch.copyWith(loading: true, error: null),
      ),
    );
    await _loadPatch(
      preserveDataOnFailure: true,
      sourceLine: sourceLine,
      scrollTargetGeneration: scrollTargetGeneration,
      propagateError: true,
    );
  }

  Future<void> setIgnoreWhitespace(bool ignoreWhitespace) async {
    if (_disposed || state.requestedIgnoreWhitespace == ignoreWhitespace) {
      return;
    }
    final sourceLine = _anchorSourceLine(state.activeAnchor);
    final scrollTargetGeneration = ++_fullFileScrollGeneration;
    if (state.selectedFile == null) {
      _replace(
        state.copyWith(
          requestedIgnoreWhitespace: ignoreWhitespace,
          fullFileScrollTarget: null,
        ),
      );
      return;
    }
    _replace(
      state.copyWith(
        requestedIgnoreWhitespace: ignoreWhitespace,
        fullFileScrollTarget: null,
        patch: state.patch.copyWith(loading: true, error: null),
      ),
    );
    await _loadPatch(
      preserveDataOnFailure: true,
      sourceLine: sourceLine,
      scrollTargetGeneration: scrollTargetGeneration,
      propagateError: true,
    );
  }

  void setWrapLines(bool wrapLines) {
    if (_disposed || state.wrapLines == wrapLines) return;
    _replace(state.copyWith(wrapLines: wrapLines));
  }

  void setFocusMode(bool focusMode) {
    if (_disposed || state.focusMode == focusMode) return;
    _replace(state.copyWith(focusMode: focusMode));
  }

  void selectAnchor(DiffAnchor anchor) {
    if (_disposed) return;
    final selected = _anchorInDocument(anchor);
    if (selected == null || _sameAnchor(state.activeAnchor, selected)) return;
    _fullFileScrollGeneration++;
    _replace(
      state.copyWith(
        activeAnchor: selected,
        fullFileScrollTarget: null,
        navigationSerial: state.navigationSerial + 1,
      ),
    );
  }

  void stepAnchor(int delta) {
    if (_disposed || delta == 0) return;
    final document = state.patch.data;
    if (document == null || document.hunks.isEmpty) return;
    final current = state.activeAnchor?.hunkIndex ?? 0;
    final next = (current + delta).clamp(0, document.hunks.length - 1);
    if (next == current) return;
    _fullFileScrollGeneration++;
    _replace(
      state.copyWith(
        activeAnchor: document.hunks[next].anchor,
        fullFileScrollTarget: null,
        navigationSerial: state.navigationSerial + 1,
      ),
    );
  }

  void syncAnchorFromScroll(DiffAnchor anchor) {
    if (_disposed) return;
    final selected = _anchorInDocument(anchor);
    if (selected == null || _sameAnchor(state.activeAnchor, selected)) return;
    _fullFileScrollGeneration++;
    _replace(
      state.copyWith(activeAnchor: selected, fullFileScrollTarget: null),
    );
  }

  void _beginSelection({
    required List<GitCommit> commits,
    required GitCommit commit,
    required String? parent,
    required List<GitFileChange> files,
    required GitFileChange? selectedFile,
    required AsyncResource<List<GitFileChange>> filesResource,
    bool preserveHistory = false,
    FileHistoryEntry? selectedHistoryEntry,
  }) {
    _selectionGeneration++;
    _replace(
      state.copyWith(
        nearbyCommits: List.unmodifiable(commits),
        selectedCommit: commit,
        parent: parent,
        files: files,
        selectedFile: selectedFile,
        activeAnchor: null,
        fullFileScrollTarget: null,
        filesResource: filesResource,
        patch: const AsyncResource(),
        file: const AsyncResource(),
        cachedEncodingKind: _cachedEncodingKind(commit, parent, selectedFile),
        blame: const AsyncResource(),
        history: preserveHistory ? state.history : const AsyncResource(),
        selectedHistoryEntry: preserveHistory ? selectedHistoryEntry : null,
        historyContext: preserveHistory ? state.historyContext : null,
        selectionGeneration: _selectionGeneration,
      ),
    );
  }

  Future<void> _loadFiles() async {
    if (_disposed) return;
    final generation = _selectionGeneration;
    final request = ++_filesRequest;
    final commit = state.selectedCommit;
    final parent = state.parent;
    _historyRequest++;
    _replace(
      state.copyWith(
        files: const [],
        selectedFile: null,
        activeAnchor: null,
        fullFileScrollTarget: null,
        filesResource: const AsyncResource(loading: true),
        patch: const AsyncResource(),
        file: const AsyncResource(),
        cachedEncodingKind: null,
        blame: const AsyncResource(),
        history: const AsyncResource(),
        selectedHistoryEntry: null,
        historyContext: null,
      ),
    );

    late final List<GitFileChange> files;
    try {
      files = await repository.loadFiles(commit, parent: parent);
    } catch (error) {
      if (_acceptsFiles(
        generation: generation,
        request: request,
        commit: commit,
        parent: parent,
      )) {
        _replace(state.copyWith(filesResource: AsyncResource(error: error)));
      }
      return;
    }
    if (!_acceptsFiles(
      generation: generation,
      request: request,
      commit: commit,
      parent: parent,
    )) {
      return;
    }

    final immutableFiles = List<GitFileChange>.unmodifiable(files);
    final selectedFile = immutableFiles.firstOrNull;
    _replace(
      state.copyWith(
        files: immutableFiles,
        selectedFile: selectedFile,
        cachedEncodingKind: _cachedEncodingKind(commit, parent, selectedFile),
        filesResource: AsyncResource(data: immutableFiles),
      ),
    );
    if (selectedFile == null) return;
    await _loadSelectedResources();
  }

  Future<void> _loadSelectedResources() => Future.wait([
    _loadPatch(),
    _loadFile(),
    if (state.view == FullDiffView.history) _ensureHistory(),
  ]);

  Future<void> _loadPatch({
    bool preserveDataOnFailure = false,
    int? sourceLine,
    DiffSourceTarget? fullFileScrollTarget,
    DiffSourceTarget? rollbackFullFileScrollTarget,
    int? scrollTargetGeneration,
    bool propagateError = false,
  }) async {
    if (_disposed) return;
    final file = state.selectedFile;
    if (file == null) return;
    final generation = _selectionGeneration;
    final request = ++_patchRequest;
    final acceptedScrollTargetGeneration =
        scrollTargetGeneration ?? ++_fullFileScrollGeneration;
    final commit = state.selectedCommit;
    final parent = state.parent;
    final scope = state.requestedScope;
    final algorithm = state.requestedAlgorithm;
    final ignoreWhitespace = state.requestedIgnoreWhitespace;
    final preservedDocument = state.patch.data;
    _replace(
      state.copyWith(
        fullFileScrollTarget: null,
        patch: state.patch.copyWith(
          data: preserveDataOnFailure ? state.patch.data : null,
          loading: true,
          error: null,
        ),
      ),
    );

    try {
      final document = await _loadPatchDocument(
        commit,
        parent,
        file,
        algorithm,
        ignoreWhitespace,
        scope,
      );
      _trimRawCaches();
      if (!_accepts(
        generation: generation,
        request: request,
        currentRequest: _patchRequest,
        commit: commit,
        file: file,
      )) {
        return;
      }
      _replace(
        state.copyWith(
          patch: AsyncResource(data: document),
          activeAnchor: nearestAnchor(document, sourceLine),
          fullFileScrollTarget:
              scope == DiffScope.fullFile &&
                  fullFileScrollTarget != null &&
                  acceptedScrollTargetGeneration == _fullFileScrollGeneration &&
                  diffDocumentContainsSourceTarget(
                    document,
                    fullFileScrollTarget,
                  )
              ? fullFileScrollTarget
              : null,
          appliedScope: scope,
          appliedAlgorithm: algorithm,
          appliedIgnoreWhitespace: ignoreWhitespace,
        ),
      );
    } catch (error, stackTrace) {
      if (_accepts(
        generation: generation,
        request: request,
        currentRequest: _patchRequest,
        commit: commit,
        file: file,
      )) {
        final restoredFullFileScrollTarget =
            preserveDataOnFailure &&
                state.appliedScope == DiffScope.fullFile &&
                rollbackFullFileScrollTarget != null &&
                acceptedScrollTargetGeneration == _fullFileScrollGeneration &&
                identical(state.patch.data, preservedDocument) &&
                preservedDocument != null &&
                diffDocumentContainsSourceTarget(
                  preservedDocument,
                  rollbackFullFileScrollTarget,
                )
            ? rollbackFullFileScrollTarget
            : null;
        _replace(
          state.copyWith(
            requestedScope: preserveDataOnFailure
                ? state.appliedScope
                : state.requestedScope,
            requestedAlgorithm: preserveDataOnFailure
                ? state.appliedAlgorithm
                : state.requestedAlgorithm,
            requestedIgnoreWhitespace: preserveDataOnFailure
                ? state.appliedIgnoreWhitespace
                : state.requestedIgnoreWhitespace,
            patch: AsyncResource(
              data: preserveDataOnFailure ? state.patch.data : null,
              error: error,
            ),
            fullFileScrollTarget: restoredFullFileScrollTarget,
          ),
        );
      }
      if (propagateError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  FileContentKind? _cachedEncodingKind(
    GitCommit commit,
    String? parent,
    GitFileChange? file,
  ) {
    if (file == null) return null;
    return _encodingCache.read(_encodingCacheKey(commit, parent, file));
  }

  EncodingCacheKey _encodingCacheKey(
    GitCommit commit,
    String? parent,
    GitFileChange file,
  ) {
    final deleted = file.status.startsWith('D');
    return (
      repositoryRoot: repository.root,
      revision: commit.isWorkingTree && !deleted
          ? '<working-tree>'
          : deleted
          ? parent ?? commit.parents.first
          : commit.sha,
      path: file.path,
      oldPath: file.oldPath,
      parent: parent,
      side: deleted ? FileDocumentSide.old : FileDocumentSide.result,
    );
  }

  Future<void> _loadFile() async {
    if (_disposed) return;
    final file = state.selectedFile;
    if (file == null) return;
    final generation = _selectionGeneration;
    final request = ++_fileRequest;
    final commit = state.selectedCommit;
    final parent = state.parent;
    final deleted = file.status.startsWith('D');
    final side = deleted ? FileDocumentSide.old : FileDocumentSide.result;
    final revision = commit.isWorkingTree && !deleted
        ? '<working-tree>'
        : deleted
        ? parent ?? commit.parents.first
        : commit.sha;
    final path = deleted ? file.oldPath ?? file.path : file.path;
    final encodingKey = _encodingCacheKey(commit, parent, file);
    final cachedEncodingKind =
        _encodingCache.read(encodingKey) ?? state.cachedEncodingKind;
    _replace(
      state.copyWith(
        file: const AsyncResource(loading: true),
        cachedEncodingKind: cachedEncodingKind,
      ),
    );

    try {
      final document = await _loadFileDocument(
        commit: commit,
        parent: parent,
        file: file,
        revision: revision,
        path: path,
        side: side,
      );
      _trimRawCaches();
      if (!_accepts(
        generation: generation,
        request: request,
        currentRequest: _fileRequest,
        commit: commit,
        file: file,
      )) {
        return;
      }
      final shouldEnsureBlame =
          state.blame.loading || state.view == FullDiffView.blame;
      _encodingCache.write(encodingKey, document.kind);
      _replace(
        state.copyWith(
          file: AsyncResource(data: document),
          cachedEncodingKind: document.kind,
        ),
      );
      if (shouldEnsureBlame) await _ensureBlame();
    } catch (error) {
      if (_accepts(
        generation: generation,
        request: request,
        currentRequest: _fileRequest,
        commit: commit,
        file: file,
      )) {
        _replace(
          state.copyWith(
            file: AsyncResource(error: error),
            blame: state.blame.loading || state.view == FullDiffView.blame
                ? AsyncResource(error: error)
                : state.blame,
          ),
        );
      }
    }
  }

  Future<void> _ensureBlame() async {
    if (_disposed) return;
    final file = state.selectedFile;
    final fileDocument = state.file.data;
    if (file == null) return;
    if (fileDocument == null) {
      if (state.file.error != null) {
        _replace(state.copyWith(blame: AsyncResource(error: state.file.error)));
        return;
      }
      if (state.file.loading && !state.blame.loading) {
        _replace(state.copyWith(blame: const AsyncResource(loading: true)));
      }
      return;
    }
    if (fileDocument.kind != FileContentKind.utf8) {
      _replace(state.copyWith(blame: const AsyncResource()));
      return;
    }
    if (state.blame.data?.file.fingerprint == fileDocument.fingerprint) return;

    final generation = _selectionGeneration;
    final request = ++_blameRequest;
    final commit = state.selectedCommit;
    final parent = state.parent;
    _replace(state.copyWith(blame: const AsyncResource(loading: true)));
    try {
      final document = await _loadBlameDocument(
        commit,
        parent,
        file,
        fileDocument,
      );
      if (!_accepts(
        generation: generation,
        request: request,
        currentRequest: _blameRequest,
        commit: commit,
        file: file,
      )) {
        return;
      }
      _replace(state.copyWith(blame: AsyncResource(data: document)));
    } catch (error) {
      if (_accepts(
        generation: generation,
        request: request,
        currentRequest: _blameRequest,
        commit: commit,
        file: file,
      )) {
        _replace(state.copyWith(blame: AsyncResource(error: error)));
      }
    }
  }

  Future<void> _ensureHistory() async {
    if (_disposed) return;
    final file = state.selectedFile;
    if (file == null || state.history.loading || state.history.data != null) {
      return;
    }
    final generation = _selectionGeneration;
    final request = ++_historyRequest;
    final commit = state.selectedCommit;
    final context = (startRevision: commit.sha, path: file.path);
    _replace(state.copyWith(history: const AsyncResource(loading: true)));
    try {
      final entries = await _loadHistoryEntries(commit, file);
      if (!_accepts(
        generation: generation,
        request: request,
        currentRequest: _historyRequest,
        commit: commit,
        file: file,
      )) {
        return;
      }
      _replace(
        state.copyWith(
          history: AsyncResource(data: entries),
          selectedHistoryEntry: entries
              .where((entry) => entry.commit.sha == commit.sha)
              .firstOrNull,
          historyContext: context,
        ),
      );
    } catch (error) {
      if (_accepts(
        generation: generation,
        request: request,
        currentRequest: _historyRequest,
        commit: commit,
        file: file,
      )) {
        _replace(state.copyWith(history: AsyncResource(error: error)));
      }
    }
  }

  Future<DiffDocument> _loadPatchDocument(
    GitCommit commit,
    String? parent,
    GitFileChange file,
    DiffAlgorithm algorithm,
    bool ignoreWhitespace,
    DiffScope scope,
  ) {
    Future<DiffDocument> load() async => DiffDocument.fromLines(
      await repository.loadDiff(
        commit,
        file,
        parent: parent,
        algorithm: algorithm,
        ignoreWhitespace: ignoreWhitespace,
        scope: scope,
      ),
    );
    if (commit.isWorkingTree) return load();
    final key = (
      base: _baseRevision(commit, parent),
      target: commit.sha,
      parent: parent,
      oldPath: file.oldPath,
      newPath: file.path,
      algorithm: algorithm,
      ignoreWhitespace: ignoreWhitespace,
      scope: scope,
    );
    return _patchCache.getOrLoad(key, load);
  }

  Future<FileDocument> _loadFileDocument({
    required GitCommit commit,
    required String? parent,
    required GitFileChange file,
    required String revision,
    required String path,
    required FileDocumentSide side,
  }) {
    Future<FileDocument> load() async => FileDocument.fromBytes(
      revision: revision,
      path: path,
      side: side,
      bytes: await repository.loadFileBytes(commit, file, parent: parent),
      gitMarkedBinary: file.isBinary,
    );
    if (commit.isWorkingTree) return load();
    return _fileCache.getOrLoad((
      revision: revision,
      path: path,
      parent: parent,
      side: side,
    ), load);
  }

  Future<BlameDocument> _loadBlameDocument(
    GitCommit commit,
    String? parent,
    GitFileChange file,
    FileDocument fileDocument,
  ) {
    Future<BlameDocument> load() async => BlameDocument.fromGitLines(
      fileDocument,
      await repository.loadBlame(
        commit,
        file,
        parent: parent,
        workingTreeBytes: commit.isWorkingTree ? fileDocument.bytes : null,
      ),
    );
    if (commit.isWorkingTree) return load();
    return _blameCache.getOrLoad((
      revision: fileDocument.revision,
      path: fileDocument.path,
    ), load);
  }

  Future<List<FileHistoryEntry>> _loadHistoryEntries(
    GitCommit commit,
    GitFileChange file,
  ) {
    Future<List<FileHistoryEntry>> load() async => List.unmodifiable(
      (await repository.loadFileHistory(commit, file)).map(
        (record) => FileHistoryEntry(
          commit: record.commit,
          path: record.path,
          oldPath: record.oldPath,
          status: record.status,
        ),
      ),
    );
    if (commit.isWorkingTree) return load();
    return _historyCache.getOrLoad((
      startRevision: commit.sha,
      path: file.path,
    ), load);
  }

  String _baseRevision(GitCommit commit, String? parent) =>
      parent ??
      (commit.parents.isEmpty ? '<empty-tree>' : commit.parents.first);

  void _trimRawCaches() {
    while (debugRawCacheBytes > _rawCacheByteLimit) {
      final patchTick = _patchCache.oldestTick;
      final fileTick = _fileCache.oldestTick;
      if (patchTick == null && fileTick == null) return;
      if (fileTick == null || (patchTick != null && patchTick <= fileTick)) {
        _patchCache.removeOldest();
      } else {
        _fileCache.removeOldest();
      }
    }
  }

  bool _acceptsFiles({
    required int generation,
    required int request,
    required GitCommit commit,
    required String? parent,
  }) =>
      !_disposed &&
      generation == _selectionGeneration &&
      request == _filesRequest &&
      state.selectedCommit.sha == commit.sha &&
      state.parent == parent;

  bool _accepts({
    required int generation,
    required int request,
    required int currentRequest,
    required GitCommit commit,
    required GitFileChange file,
  }) =>
      !_disposed &&
      generation == _selectionGeneration &&
      request == currentRequest &&
      state.selectedCommit.sha == commit.sha &&
      state.selectedFile?.path == file.path &&
      state.selectedFile?.oldPath == file.oldPath;

  DiffAnchor? _anchorInDocument(DiffAnchor anchor) {
    final document = state.patch.data;
    if (document == null ||
        anchor.hunkIndex < 0 ||
        anchor.hunkIndex >= document.hunks.length) {
      return null;
    }
    return document.hunks[anchor.hunkIndex].anchor;
  }

  void _replace(FullDiffSessionState nextState) {
    if (_disposed) return;
    state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _selectionGeneration++;
    _filesRequest++;
    _patchRequest++;
    _fileRequest++;
    _blameRequest++;
    _historyRequest++;
    super.dispose();
  }
}

int _patchSize(DiffDocument document) => [
  ...document.headers,
  for (final row in document.rows) row.text,
].fold(0, (bytes, text) => bytes + utf8.encode(text).length);

int? _anchorSourceLine(DiffAnchor? anchor) =>
    anchor?.newLine ?? anchor?.oldLine;

DiffSourceTarget? _anchorSourceTarget(DiffAnchor? anchor) =>
    anchor == null ? null : (oldLine: anchor.oldLine, newLine: anchor.newLine);

int? _sourceLine(DiffSourceTarget? target) =>
    target?.newLine ?? target?.oldLine;

bool _sameFile(GitFileChange? left, GitFileChange right) =>
    left?.path == right.path && left?.oldPath == right.oldPath;

bool _sameAnchor(DiffAnchor? left, DiffAnchor right) =>
    left?.hunkIndex == right.hunkIndex &&
    left?.oldLine == right.oldLine &&
    left?.newLine == right.newLine;

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
