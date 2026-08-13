part of 'timeline.dart';

/// Finding a commit among the rows already loaded: ⌘F opens the field, every
/// keystroke re-reads the hashes and the subjects, and Enter walks what it
/// found. Nothing is hidden — the found characters light up where they sit and
/// the selection moves onto that row, so the history around a hit stays
/// readable instead of being filtered away.
///
/// A subject is read by words: each word of the query has to sit inside some
/// word of the subject, in whatever order, so `name hover` and `hover name`
/// answer the same and letters scattered across a sentence answer nothing. A
/// hash is read differently again — it answers for the seven characters the
/// column draws, and for a longer hash pasted in whole — and one query can ask
/// both: `89d 카드` narrows by hash and by subject at once.

/// 낱말을 가르는 것: 공백도 구두점도 모두 같은 자리를 한다.
final _searchWord = RegExp(r'[\p{L}\p{N}]+', unicode: true);

extension _TimelineSearch on _TimelineScreenState {
  void _openSearch() {
    // 이 검색의 기점. ⌘F를 다시 눌러 새 질의를 시작하는 것도 새 검색이라, 그때
    // 서 있던 줄이 새 기점이 된다.
    _searchOrigin = _selectedIndex.value;
    if (!_searchOpen) _rebuild(() => _searchOpen = true);
    _searchFocusNode.requestFocus();
    // ⌘F on an open field starts the next search rather than appending to the
    // last one.
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  /// 찾기가 살아 있는지. 접혀서 줄이 보이지 않아도 질의가 남아 있으면 여전히
  /// 찾는 중이다 — 불도 흐림도 그 질의가 그리는 것이다.
  bool get _searchLive => _searchQuery.trim().isNotEmpty;

  /// Enter는 결과를 확정한다: 줄만 접히고 질의는 목록에 그대로 남아, 찾은 자리
  /// 앞뒤의 역사를 그 상태로 읽는다. 접을 결과가 없으면 접지 않는다 — 흐림만
  /// 남고 근거는 화면에서 사라질 것이다.
  void _collapseSearch() {
    if (_searchMatches.isEmpty) return;
    _rebuild(() => _searchOpen = false);
    _focusNode.requestFocus();
  }

  /// 찾은 것이 없는 검색은 읽던 자리를 빼앗지 않는다. 질의를 좁히다 결과를
  /// 놓쳤다면 선택은 마지막으로 찾았던 남의 줄에 서 있으니, 검색을 열 때 서
  /// 있던 줄로 돌려보낸다. 그 줄이 그새 사라졌다면 맨 처음 줄로 간다.
  void _closeSearch() {
    if (!_searchOpen && !_searchLive) return;
    final strayed = _searchQuery.trim().isNotEmpty && _searchMatches.isEmpty;
    final origin = _searchOrigin;
    _searchController.clear();
    _rebuild(() {
      _searchOpen = false;
      _searchQuery = '';
    });
    _searchOrigin = null;
    if (strayed && origin != null && _entries.isNotEmpty) {
      _goToRow(origin < _entries.length && _selectable(origin) ? origin : 0);
    }
    _focusNode.requestFocus();
  }

  /// Typing searches: the selection follows the query down to the nearest row
  /// it still finds, so the answer is on screen before Enter is pressed.
  void _searchFor(String query) {
    _rebuild(() => _searchQuery = query);
    final matches = _searchMatches;
    if (matches.isEmpty || matches.contains(_selectedIndex.value)) return;
    _goToRow(
      matches.firstWhere(
        (index) => index > _selectedIndex.value,
        orElse: () => matches.first,
      ),
    );
  }

  /// The words the query is made of. Spaces and punctuation both only ever
  /// separate one from the next, so `fix(merge)` asks for two. 질의가 곧 찾기라,
  /// 줄이 접혀 있어도 낱말은 그대로 산다.
  List<String> get _searchTerms => [
    for (final word in _searchWord.allMatches(_searchQuery.toLowerCase()))
      word.group(0)!,
  ];

  /// The rows the query finds, in the order they are drawn. Every word of the
  /// query has to be answered — by the subject or by the hash, in any order
  /// and not necessarily by the same one — and a row is only ever a result of
  /// something the reader can see light up on it.
  List<int> get _searchMatches {
    final terms = _searchTerms;
    if (terms.isEmpty) return const [];
    final matches = <int>[];
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (entry.rowIndex < 0) continue;
      if (_found(entry.row.commit)) matches.add(index);
    }
    return matches;
  }

  bool _found(GitCommit commit) {
    final terms = _searchTerms;
    if (terms.isEmpty) return false;
    return terms.every(
      (term) =>
          wordMatchPositions(commit.subject, term) != null ||
          _hashTermPositions(commit, term) != null,
    );
  }

  /// Enter walks forward, ⇧Enter back, and both come round the ends rather
  /// than stopping there.
  void _stepSearchMatch(int delta) {
    final matches = _searchMatches;
    if (matches.isEmpty) return;
    final current = _selectedIndex.value;
    _goToRow(
      delta > 0
          ? matches.firstWhere(
              (index) => index > current,
              orElse: () => matches.first,
            )
          : matches.lastWhere(
              (index) => index < current,
              orElse: () => matches.last,
            ),
    );
  }

  void _goToRow(int index) {
    _arrivedGoingDown = null;
    _selectedIndex.value = index;
    _scrollToSelection();
  }

  /// What the subject has to show for the query: every word of it the subject
  /// answered for, lit where it sits. A word the hash answered for instead is
  /// simply not here — and a row the query did not find lights nothing at all,
  /// however much of the query one of its words could have matched.
  List<int>? _subjectPositions(GitCommit commit) {
    if (!_found(commit)) return null;
    final positions = <int>{};
    for (final term in _searchTerms) {
      positions.addAll(wordMatchPositions(commit.subject, term) ?? const []);
    }
    return positions.isEmpty ? null : (positions.toList()..sort());
  }

  List<int>? _hashPositions(GitCommit commit) {
    if (!_found(commit)) return null;
    final positions = <int>{};
    for (final term in _searchTerms) {
      positions.addAll(_hashTermPositions(commit, term) ?? const []);
    }
    return positions.isEmpty ? null : (positions.toList()..sort());
  }

  /// A hash is not prose and is not read as prose: `09c` would otherwise find
  /// nearly every commit in the repository, since those three characters turn
  /// up in that order somewhere down almost any forty hex digits — and turn up
  /// where nothing is drawn, so the row would join the results with nothing on
  /// it lit. A hash answers to what the column actually shows, and to a longer
  /// hash pasted in whole, which git itself would read as a prefix.
  List<int>? _hashTermPositions(GitCommit commit, String term) {
    if (commit.isWorkingTree) return null;
    final drawn = commit.shortSha.toLowerCase();
    final at = drawn.indexOf(term);
    if (at >= 0) {
      return [for (var unit = 0; unit < term.length; unit++) at + unit];
    }
    // A pasted hash runs past the seven characters on screen; all seven of them
    // are what it found.
    if (!commit.sha.toLowerCase().startsWith(term)) return null;
    return [for (var unit = 0; unit < drawn.length; unit++) unit];
  }

  /// 검색이 도는 동안 질의가 찾지 못한 행은 뒤로 물러난다. 걸러내는 것이
  /// 아니라 흐려지는 것이라, 찾은 자리의 앞뒤 역사는 그대로 읽힌다. 선택된
  /// 행만은 흐려지지 않는다 — 아무것도 찾지 못한 질의에서도 읽는 이가 서 있는
  /// 자리는 남아야 한다.
  Widget _searchDimmed(
    GitCommit commit,
    Widget row, {
    required bool selected,
  }) => _searchTerms.isEmpty || selected || _found(commit)
      ? row
      : Opacity(opacity: 0.34, child: row);

  Widget _searchableSubject(GitCommit commit, {required TextStyle style}) =>
      _litText(commit.subject, _subjectPositions(commit), style: style);

  Widget _searchableHash(
    GitCommit commit,
    String drawn, {
    required TextStyle style,
  }) => _litText(
    drawn,
    _hashPositions(commit),
    style: style,
    // A sha never folds onto a second line inside the row. Clipped rather than
    // ellipsised: the front of a sha is the part worth reading, and '…' would
    // spend room on saying so.
    overflow: TextOverflow.clip,
    softWrap: false,
  );

  /// A row's text with the found characters lit. Without a search — or on a
  /// row the search did not find — this is the same [Text] the row always
  /// drew.
  Widget _litText(
    String text,
    List<int>? positions, {
    required TextStyle style,
    TextOverflow overflow = TextOverflow.ellipsis,
    bool softWrap = true,
  }) {
    if (positions == null) {
      return Text(
        text,
        maxLines: 1,
        softWrap: softWrap,
        overflow: overflow,
        style: style,
      );
    }
    final marked = positions.toSet();
    final highlight = TextStyle(
      color: _palette.text,
      backgroundColor: mainAccent.withValues(alpha: 0.34),
      fontWeight: FontWeight.w700,
    );
    final children = <TextSpan>[];
    final run = StringBuffer();
    var lit = false;
    void flush() {
      if (run.isEmpty) return;
      children.add(
        TextSpan(text: run.toString(), style: lit ? highlight : null),
      );
      run.clear();
    }

    for (var index = 0; index < text.length; index++) {
      if (marked.contains(index) != lit) {
        flush();
        lit = !lit;
      }
      run.write(text[index]);
    }
    flush();
    return Text.rich(
      TextSpan(children: children),
      maxLines: 1,
      softWrap: softWrap,
      overflow: overflow,
      style: style,
    );
  }

  /// The field floats over the top of the list instead of taking a row of its
  /// own: opening a search must not move the history the reader is looking at.
  Widget _searchBar() => Positioned(
    top: _TimelineScreenState._timelineHeaderHeight + 6,
    right: 14,
    child: Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('timeline-search'),
        width: 300,
        padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
        decoration: BoxDecoration(
          color: _palette.raised,
          border: Border.all(color: _palette.border),
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SearchIcon(color: _palette.muted, size: 14),
            const SizedBox(width: 7),
            Expanded(
              child: Focus(
                onKeyEvent: _onSearchKeyEvent,
                child: Semantics(
                  label: '커밋 찾기',
                  textField: true,
                  child: TextField(
                    key: const Key('timeline-search-field'),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _searchFor,
                    onSubmitted: (_) => _collapseSearch(),
                    style: TextStyle(color: _palette.text, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '해시나 제목',
                      hintStyle: TextStyle(color: _palette.muted, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _searchCount(),
            const SizedBox(width: 4),
            _searchStep(
              const Key('timeline-search-previous'),
              Icons.keyboard_arrow_up,
              -1,
            ),
            _searchStep(
              const Key('timeline-search-next'),
              Icons.keyboard_arrow_down,
              1,
            ),
            HoverBuilder(
              builder: (hovered) => GestureDetector(
                key: const Key('timeline-search-close'),
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 3,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: hovered ? _palette.text : _palette.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// 접힌 찾기가 남기는 자리표. 찾기 줄이 앉아 있던 곳에 그대로 앉아, 흐려진
  /// 목록이 왜 흐린지 답한다. 누르면 질의를 그대로 데리고 다시 펼치고, ✕는
  /// 찾기를 끝낸다.
  Widget _searchPill() => Positioned(
    top: _TimelineScreenState._timelineHeaderHeight + 6,
    right: 14,
    child: Material(
      color: Colors.transparent,
      child: HoverBuilder(
        builder: (hovered) => GestureDetector(
          key: const Key('timeline-search-pill'),
          behavior: HitTestBehavior.opaque,
          onTap: _openSearch,
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
            decoration: BoxDecoration(
              color: _palette.raised,
              border: Border.all(
                color: hovered ? _palette.muted : _palette.border,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                SearchIcon(color: _palette.muted, size: 12),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _searchQuery.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _palette.text, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                _searchCount(),
                const SizedBox(width: 2),
                HoverBuilder(
                  builder: (closeHovered) => GestureDetector(
                    key: const Key('timeline-search-pill-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeSearch,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: closeHovered ? _palette.text : _palette.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Which of how many, counted from the row the selection sits on.
  Widget _searchCount() => ValueListenableBuilder<int>(
    valueListenable: _selectedIndex,
    builder: (context, selected, _) {
      final matches = _searchMatches;
      final position = matches.indexOf(selected) + 1;
      return Text(
        key: const Key('timeline-search-count'),
        _searchQuery.trim().isEmpty
            ? ''
            : matches.isEmpty
            ? '없음'
            : '$position/${matches.length}',
        style: TextStyle(
          color: matches.isEmpty ? _palette.muted : _palette.text,
          fontSize: 11,
        ),
      );
    },
  );

  /// A step button takes no focus of its own, so the field keeps the keyboard
  /// and the next Enter still walks the matches.
  Widget _searchStep(Key key, IconData icon, int delta) => HoverBuilder(
    builder: (hovered) => GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => _stepSearchMatch(delta),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Icon(
          icon,
          size: 16,
          color: hovered ? _palette.text : _palette.muted,
        ),
      ),
    ),
  );

  KeyEventResult _onSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Enter는 이 결과로 하겠다는 뜻이라 걷지 않는다. 결과를 훑는 손은
      // ⇧Enter와 ⌃⌄ 버튼이다.
      if (HardwareKeyboard.instance.isShiftPressed) {
        _stepSearchMatch(-1);
      } else {
        _collapseSearch();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
