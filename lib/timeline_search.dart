part of 'timeline.dart';

/// Finding a commit among the rows already loaded: ⌘F opens the field, every
/// keystroke re-reads the hashes and the subjects, and Enter walks what it
/// found. Nothing is hidden — the found characters light up where they sit and
/// the selection moves onto that row, so the history around a hit stays
/// readable instead of being filtered away.
///
/// Matching is the same fuzzy match the sidebar and the repository picker use,
/// so `mrgfix` finds `fix(merge): …` and a pasted full hash finds its row even
/// though only seven characters are drawn.

extension _TimelineSearch on _TimelineScreenState {
  void _openSearch() {
    if (!_searchOpen) _rebuild(() => _searchOpen = true);
    _searchFocusNode.requestFocus();
    // ⌘F on an open field starts the next search rather than appending to the
    // last one.
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    _searchController.clear();
    _rebuild(() {
      _searchOpen = false;
      _searchQuery = '';
    });
    _focusNode.requestFocus();
  }

  /// Typing searches: the selection follows the query down to the nearest row
  /// it still finds, so the answer is on screen before Enter is pressed.
  void _searchFor(String query) {
    _rebuild(() => _searchQuery = query);
    final matches = _searchMatches;
    if (matches.isEmpty || matches.contains(_selectedIndex.value)) return;
    _goToMatch(
      matches.firstWhere(
        (index) => index > _selectedIndex.value,
        orElse: () => matches.first,
      ),
    );
  }

  /// The rows the query finds, in the order they are drawn. A row answers for
  /// its whole hash and its subject; the seven characters on screen are only
  /// how much of the hash fits.
  List<int> get _searchMatches {
    final query = _searchQuery.trim();
    if (!_searchOpen || query.isEmpty) return const [];
    final matches = <int>[];
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (entry.rowIndex < 0) continue;
      final commit = entry.row.commit;
      if (fuzzyMatch(commit.sha, query) || fuzzyMatch(commit.subject, query)) {
        matches.add(index);
      }
    }
    return matches;
  }

  /// Enter walks forward, ⇧Enter back, and both come round the ends rather
  /// than stopping there.
  void _stepSearchMatch(int delta) {
    final matches = _searchMatches;
    if (matches.isEmpty) return;
    final current = _selectedIndex.value;
    _goToMatch(
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

  void _goToMatch(int index) {
    _arrivedGoingDown = null;
    _selectedIndex.value = index;
    _scrollToSelection();
  }

  /// Where the query lands in one row's own text, or null when the search has
  /// nothing to say about it.
  List<int>? _searchPositions(String text) {
    final query = _searchQuery.trim();
    if (!_searchOpen || query.isEmpty) return null;
    return fuzzyMatchPositions(text, query);
  }

  /// A row's text with the found characters lit. Without a search — or on a
  /// row the search did not find — this is the same [Text] the row always
  /// drew.
  Widget _searchableText(
    String text, {
    required TextStyle style,
    TextOverflow overflow = TextOverflow.ellipsis,
    bool softWrap = true,
  }) {
    final positions = _searchPositions(text);
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
                    onSubmitted: (_) => _stepSearchMatch(1),
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
      _stepSearchMatch(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
