part of 'timeline.dart';

/// What the screen asks git for and what it keeps: pages of commits, refs,
/// remote state, the working tree, and the settings it writes back.

extension _TimelineData on _TimelineScreenState {
  void _loadNextPage() {
    if (_compareRef != null || _end || _inFlight != null) return;
    final request = _fetchNextPage();
    _inFlight = request;
    request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
  }

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    TimelineColumnWidths(
      sidebar: _sidebarWidth,
      refs: _w('refs'),
      graph: _graphWidth,
      hash: _w('hash'),
      time: _w('time'),
      name: _w('name'),
      showTime: _showTime,
      showName: _showName,
    ),
  );

  void _savePreviewSize() => widget.onPreviewSizeChanged?.call((
    width: _previewWidth,
    height: _previewHeight,
  ));

  void _savePreviewDiffExtent(PreviewPlacement placement) =>
      widget.onPreviewDiffSizeChanged?.call((
        placement: placement,
        extent:
            _storedPreviewDiffExtent(placement) ?? _visiblePreviewDiffExtent,
      ));
}

extension _TimelineDataFlows on _TimelineScreenState {
  Future<void> _refreshRemotes() async {
    final remotes = _remotesToRefresh;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if ((lifecycleState != null &&
            lifecycleState != AppLifecycleState.resumed) ||
        remotes.isEmpty ||
        _fetchingRemotes.value ||
        _cherryPickState != null) {
      return;
    }
    _fetchingRemotes.value = true;
    try {
      var updated = false;
      Object? fetchError;
      for (final remote in remotes) {
        try {
          final result = await widget.repository.fetchRemote(remote);
          updated |= result == FetchOriginResult.updated;
        } catch (error) {
          fetchError ??= error;
        }
      }
      if (!mounted) return;
      if (updated) await _loadRefs();
      if (mounted) _fetchError.value = fetchError;
    } finally {
      if (mounted) _fetchingRemotes.value = false;
    }
  }

  Future<void> _loadRefs() async {
    try {
      final refs = await widget.repository.loadRefs();
      if (!mounted) return;
      final branch = resolveBaseBranch(refs, _refsLoaded ? _baseBranch : null);
      if (!widget.preferredBranchReady) {
        _pendingBaseBranch = branch;
        _pendingBaseBranchIsUserSelection = false;
      }
      final compared = _compareRef;
      final comparisonStillExists =
          compared != null &&
          (refs.local.contains(compared) ||
              refs.remote.contains(compared) ||
              refs.tags.contains(compared));
      final comparison = _comparison;
      final baseTip = comparison == null
          ? null
          : _refTip(refs, comparison.baseRef);
      final compareTip = comparison == null
          ? null
          : _refTip(refs, comparison.compareRef);
      final comparisonTipsChanged =
          comparisonStillExists &&
          comparison != null &&
          baseTip != null &&
          compareTip != null &&
          (baseTip != comparison.baseTip ||
              compareTip != comparison.compareTip);
      final retryComparison =
          comparisonStillExists &&
          comparison == null &&
          _comparisonError != null;
      _rebuild(() {
        _refs = refs;
        _refsLoading = false;
        _refsLoadFailed = false;
        _refsLoaded = true;
        _baseBranch = branch;
        if (compared != null && !comparisonStillExists) {
          _comparisonSerial++;
          _compareRef = null;
          _comparison = null;
          _comparisonRows = [];
          _comparisonEntries = [];
          _rebaseCheck = null;
          _comparisonError = null;
        }
        _rebuildGraph();
      });
      _scheduleRatchetUpdate();
      unawaited(_resolveSelectedDeletedBranchName());
      if (comparisonTipsChanged || retryComparison) {
        unawaited(
          _selectComparison(compared, preserveCurrent: comparison != null),
        );
      }
      if (widget.preferredBranchReady &&
          branch != null &&
          branch != widget.preferredBranch) {
        widget.onPreferredBranchChanged?.call(branch);
      }
    } catch (_) {
      if (!mounted) return;
      _rebuild(() {
        _refsLoading = false;
        _refsLoadFailed = true;
        _refsLoaded = false;
      });
    }
  }

  /// Measures the lanes the reader can actually see. Rows off screen do not
  /// count, so a shallow head of history opens at its snuggest width.
  ///
  /// Two depths come out of one measurement. [_visibleLane] is this screen and
  /// decides when squeezing the column starts pushing lanes left. The ratchet
  /// is the deepest screen so far and only ever widens, so auto-fit does not
  /// make the column boundary bob up and down as the reader scrolls.
  void _updateRatchet() {
    if (!mounted ||
        _comparison != null ||
        _entries.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final first = (position.pixels / TimelineScreen.rowHeight).floor().clamp(
      0,
      _entries.length - 1,
    );
    // The row sitting on the bottom edge is `ceil(...) - 1`; without the -1
    // this reaches one row past the fold, and one merge row there opens lanes
    // nobody can see.
    final last =
        (((position.pixels + position.viewportDimension) /
                        TimelineScreen.rowHeight)
                    .ceil() -
                1)
            .clamp(0, _entries.length - 1);
    var visible = 0;
    for (var index = first; index <= last; index++) {
      final row = _entries[index].row;
      for (final lane in [row.lane, ...row.activeLanes, ...row.nextLanes]) {
        if (lane > visible) visible = lane;
      }
    }
    final ratchet = math.max(_ratchetLane, visible);
    if (visible == _visibleLane && ratchet == _ratchetLane) return;
    _rebuild(() {
      _visibleLane = visible;
      _ratchetLane = ratchet;
    });
  }

  Future<void> _fetchNextPage() async {
    _rebuild(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // The first page fetches the working tree and the log together.
      final (working, page) = _normalCommits.isEmpty
          ? await (
              widget.repository.loadWorkingTree(),
              widget.repository.loadHistory(
                limit: _TimelineScreenState._pageSize,
              ),
            ).wait
          : (
              null,
              await widget.repository.loadHistory(
                skip: _historyCount,
                limit: _TimelineScreenState._pageSize,
              ),
            );
      if (!mounted) return;
      final keepEndVisible =
          _normalCommits.isNotEmpty &&
          page.length < _TimelineScreenState._pageSize &&
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <=
              TimelineScreen.rowHeight;
      _rebuild(() {
        if (working != null) {
          _normalCommits.add(working);
          _hasWorkingTree = true;
          // The working tree row inherits HEAD's committer color so its rail
          // matches the branch it sits on.
          if (page.isNotEmpty) _committersBySha[''] = page.first.committer;
        }
        _normalCommits.addAll(page);
        _committersBySha.addEntries(
          page.map((commit) => MapEntry(commit.sha, commit.committer)),
        );
        _rebuildGraph();
        // A heading never holds the selection across a load — including the
        // very first one, so the app opens on a commit.
        if (_entries.isNotEmpty &&
            _entries[_selectedIndex.value].rowIndex < 0) {
          _selectedIndex.value = _entries.indexWhere(
            (entry) => entry.rowIndex >= 0,
          );
        }
        _end = page.length < _TimelineScreenState._pageSize;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateRatchet());
      unawaited(_resolveSelectedDeletedBranchName());
      if (keepEndVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      _rebuild(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadCommitIdentity() async {
    try {
      final identity = await widget.repository.loadCommitIdentity();
      if (!mounted) return;
      _rebuild(
        () => _commitIdentity = resolveCommitIdentity(
          identity,
          widget.commitProfiles,
        ),
      );
    } catch (_) {
      // A repository that cannot answer keeps the chip on its last reading.
    }
  }

  String? _deletedBranchTipSha(int branch) {
    for (final row in _normalRows) {
      if (row.branch != branch || row.commit.isWorkingTree) continue;
      return _rowRefs(row.commit).isEmpty ? row.commit.sha : null;
    }
    return null;
  }

  /// Asks the engine what the git facts lean towards. Nothing waits on this: the
  /// chip shows up whenever it lands, and a comparison change drops the answer.
  Future<void> _loadRecommendation(
    BranchComparisonResult comparison,
    int serial, {
    RebaseCheckResult? rebaseCheck,
  }) async {
    final request = ++_recommendationSerial;
    try {
      final recommendation = await widget.repository.recommendBranchIntegration(
        comparison: comparison,
        rebaseCheck: rebaseCheck,
      );
      if (!mounted ||
          request != _recommendationSerial ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      _rebuild(() => _recommendation = recommendation);
    } catch (_) {
      // 추천은 부가 정보라 실패하면 칩을 띄우지 않고 넘어간다.
    }
  }

  /// P1b — patch-id가 이미 base에 있는 커밋을 행 배지로 올린다. 기다리는 것은 없고
  /// 비교가 바뀌면 답은 버려진다. 자동 skip 같은 동작은 없다.
  Future<void> _loadDuplicateCommits(
    BranchComparisonResult comparison,
    int serial,
  ) async {
    try {
      final duplicates = await widget.repository.duplicateCompareCommits(
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
      );
      if (!mounted ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      _rebuild(() => _duplicateCommits = duplicates);
    } catch (_) {
      // 배지는 부가 정보라 실패하면 붙지 않고 넘어간다.
    }
  }

  /// P2 — 커밋별 단독 재생 예고. 새 비교나 미리보기 Drop이 진행 중인 예고를
  /// 취소하고 늦게 도착한 결과는 다른 브랜치 쌍에 붙지 못한다.
  Future<void> _loadConflictForecast(
    BranchComparisonResult comparison,
    int serial,
  ) async {
    final request = ++_conflictForecastSerial;
    try {
      final forecast = await widget.repository.probeRebaseConflicts(
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
        commits: [
          for (final entry in comparison.commits)
            if (entry.side == BranchCommitSide.compareOnly) entry.commit.sha,
        ],
        cancelled: () => !mounted || request != _conflictForecastSerial,
      );
      if (!mounted ||
          request != _conflictForecastSerial ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      _rebuild(() => _conflictForecast = forecast);
    } catch (_) {
      // 예고는 부가 정보라 실패하면 배지를 띄우지 않고 넘어간다.
    }
  }

  Widget _restoreColumnButton(String column, String label) => Tooltip(
    message: 'Show ${timelineColumns[column]!.label} column',
    waitDuration: _tooltipDelay,
    child: SizedBox(
      width: 22,
      height: 22,
      child: TextButton(
        key: Key('show-$column-column'),
        onPressed: () {
          _rebuild(() {
            if (column == 'time') {
              _showTime = true;
            } else {
              _showName = true;
            }
          });
          _saveColumnWidths();
        },
        style: TextButton.styleFrom(
          foregroundColor: _palette.muted,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    ),
  );

  Widget _deletedBranchLabel(GitCommit commit, String name, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Container(
              key: Key('deleted-branch-badge-${commit.sha}'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '삭제됨',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                key: Key('deleted-branch-name-${commit.sha}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      );

  /// Options changed before the settings file finished loading have nowhere to
  /// go yet, so they wait here until a persistence callback arrives.
  void _scheduleFullDiffPersistenceFlush() {
    if (_fullDiffPersistenceFlushScheduled ||
        (_pendingFullDiffPreferences == null &&
            _pendingFullDiffColumnWidths == null) ||
        (widget.onFullDiffPreferencesChanged == null &&
            widget.onFullDiffColumnWidthsChanged == null)) {
      return;
    }
    _fullDiffPersistenceFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fullDiffPersistenceFlushScheduled = false;
      if (!mounted) return;

      final preferences = _pendingFullDiffPreferences;
      final preferencesCallback = widget.onFullDiffPreferencesChanged;
      if (preferences != null && preferencesCallback != null) {
        _pendingFullDiffPreferences = null;
        preferencesCallback(preferences);
      }

      final widths = _pendingFullDiffColumnWidths;
      final widthsCallback = widget.onFullDiffColumnWidthsChanged;
      if (widths != null && widthsCallback != null) {
        _pendingFullDiffColumnWidths = null;
        widthsCallback(widths);
      }
    });
  }
}
