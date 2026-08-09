part of 'timeline.dart';

/// The ref sidebar: the search field, the three sections, the tree of names,
/// the keyboard cursor that walks them, and the menus a name offers.

extension _TimelineSidebar on _TimelineScreenState {
  KeyEventResult _onSidebarKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _rebuild(() => _sidebarCursor = null);
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final key = normalizeNavigationKey(
      event.logicalKey,
      hasModifier:
          keyboard.isMetaPressed ||
          keyboard.isAltPressed ||
          keyboard.isShiftPressed ||
          keyboard.isControlPressed,
    );
    // → (or l) hands the keyboard back to the timeline; the cursor stays so
    // the gray selection marks where the sidebar left off.
    if (key == LogicalKeyboardKey.arrowRight && event is KeyDownEvent) {
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    _moveSidebarCursor(step);
    return KeyEventResult.handled;
  }

  /// The strip under the search field: what the cursor's ref can do, with
  /// impossible actions disabled in place so the layout never jumps.
  Widget _sidebarActionStrip() {
    final cursor = _sidebarCursor;
    final section = cursor?.$1;
    final name = cursor?.$2;
    final isLocal = section == _RefSection.local && name != null;
    final isRemote = section == _RefSection.remote && name != null;
    final current = isLocal && name == _refs.current;
    final pullState = isRemote ? remotePullState(_refs, name) : null;
    final busy = _pullingRemote != null || _branchApplyBusy;

    Widget button({
      required Key key,
      required IconData icon,
      required String tooltip,
      VoidCallback? onPressed,
      Color? color,
    }) => IconButton(
      key: key,
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      style: IconButton.styleFrom(
        foregroundColor: color ?? _palette.text,
        disabledForegroundColor: _palette.muted.withValues(alpha: 0.4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Container(
        key: const Key('sidebar-action-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _palette.raised,
          border: Border.all(color: _palette.border),
          borderRadius: BorderRadius.circular(6),
        ),
        // Focus stays on the list: the buttons act without taking the
        // keyboard, so the cursor keeps moving from where it was.
        child: ExcludeFocus(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(
                    key: const Key('sidebar-action-base'),
                    icon: Icons.anchor,
                    tooltip: '기준 브랜치로',
                    onPressed: isLocal && name != _baseBranch
                        ? () => _selectBaseBranch(name)
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-compare'),
                    icon: Icons.compare_arrows,
                    tooltip: '브랜치 diff로 비교',
                    onPressed: name != null && name != _baseBranch && !busy
                        ? () => unawaited(_selectComparison(name))
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-pull'),
                    icon: Icons.arrow_downward,
                    tooltip: 'Pull',
                    onPressed:
                        pullState?.kind == RemotePullKind.fastForward && !busy
                        ? () => unawaited(_confirmRemotePull(name!, pullState!))
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-checkout'),
                    icon: Icons.logout,
                    tooltip: '체크아웃',
                    onPressed: busy
                        ? null
                        : isLocal && !current
                        ? () => unawaited(_runLocalCheckout(name))
                        : pullState != null && !pullState.checkedOut
                        ? () => unawaited(_runRemoteCheckout(name!, pullState))
                        : null,
                  ),
                  SizedBox(
                    height: 16,
                    child: VerticalDivider(width: 9, color: _palette.border),
                  ),
                  button(
                    key: const Key('sidebar-action-delete'),
                    icon: Icons.delete_outline,
                    tooltip: '브랜치 삭제',
                    color: remoteBehindRed,
                    onPressed: isLocal && !current && !busy
                        ? () => unawaited(_confirmDeleteBranch(name))
                        : null,
                  ),
                ],
              );
              // 26px per button plus the divider; below that plus a readable
              // name, the name yields and the buttons scale to the pane.
              const buttonsWidth = 26.0 * 5 + 9;
              if (constraints.maxWidth < buttonsWidth + 48) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: buttons,
                );
              }
              return Row(
                children: [
                  // Nothing selected leaves the slot empty; the disabled
                  // buttons already say the strip is waiting.
                  Expanded(
                    child: Text(
                      name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: _palette.text),
                    ),
                  ),
                  buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Moves the cursor and mirrors it on the timeline, like clicking the row.
  void _moveSidebarCursor(int step) {
    final rows = _visibleRefRows();
    if (rows.isEmpty) return;
    final cursor = _sidebarCursor;
    final index = cursor == null ? -1 : rows.indexOf(cursor);
    final next = index < 0
        ? (step > 0 ? 0 : rows.length - 1)
        : (index + step).clamp(0, rows.length - 1);
    final (section, name) = rows[next];
    _rebuild(() => _sidebarCursor = rows[next]);
    _selectRef(
      name,
      remote: section == _RefSection.remote,
      focusTimeline: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _sidebarRowKeys['${section.name}:$name']?.currentContext;
      if (context != null) {
        unawaited(Scrollable.ensureVisible(context, alignment: 0.5));
      }
    });
  }

  /// The first click jumps the timeline like any ref row; a second click on
  /// the same row within the double-click window runs the default pull action.
  void _tapRemoteRow(String name) {
    _selectRef(name, remote: true, focusTimeline: false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRemoteRowTap == name &&
        now - _lastRemoteRowTapMs <= kDoubleTapTimeout.inMilliseconds) {
      _lastRemoteRowTap = null;
      _runRemotePullDefault(name);
      return;
    }
    _lastRemoteRowTap = name;
    _lastRemoteRowTapMs = now;
  }

  /// The sidebar, with a drag handle on its right edge. The timeline sits in the
  /// leftover width, so its own flex math follows along for free.
  Widget _sidebar() {
    final width = _sidebarCollapsed
        ? _TimelineScreenState._collapsedSidebarWidth
        : _sidebarWidth;
    return SizedBox(
      key: const Key('sidebar'),
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: _sidebarCollapsed ? _collapsedSidebarBody() : _sidebarBody(),
          ),
          if (!_sidebarCollapsed)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  key: const Key('sidebar-resizer'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => _rebuild(
                    () => _sidebarWidth = (_sidebarWidth + details.delta.dx)
                        .clamp(
                          _TimelineScreenState._sidebarRange.min,
                          _TimelineScreenState._sidebarRange.max,
                        ),
                  ),
                  onHorizontalDragEnd: (_) => _saveColumnWidths(),
                  onHorizontalDragCancel: _saveColumnWidths,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sidebarBody() => Container(
    decoration: BoxDecoration(
      color: _palette.panel,
      border: Border(right: BorderSide(color: _palette.border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '브랜치와 태그 찾기',
                  textField: true,
                  child: TextField(
                    key: const Key('ref-filter'),
                    controller: _filterController,
                    onChanged: (value) => _rebuild(() => _filter = value),
                    style: TextStyle(color: _palette.text, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      // The magnifier replaces the hint sentence; the wording
                      // lives on in the semantics label and the tooltip.
                      prefixIcon: Tooltip(
                        message: '브랜치와 태그 찾기',
                        child: Center(
                          widthFactor: 1,
                          child: SearchIcon(
                            key: const Key('ref-filter-search-icon'),
                            color: _palette.muted,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      filled: true,
                      fillColor: _palette.raised,
                      contentPadding: const EdgeInsets.only(
                        right: 8,
                        top: 7,
                        bottom: 7,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.interactive),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _sidebarToggleButton(opens: false),
            ],
          ),
        ),
        _sidebarActionStrip(),
        Expanded(
          child: Focus(
            focusNode: _sidebarFocusNode,
            onKeyEvent: _onSidebarKeyEvent,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // The checked-out branch leads the local list.
                ..._refSection(_RefSection.local, _localBranches),
                ..._refSection(_RefSection.remote, _refs.remote),
                ..._refSection(_RefSection.tags, _refs.tags),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _collapsedSidebarBody() => Container(
    decoration: BoxDecoration(
      color: _palette.panel,
      border: Border(right: BorderSide(color: _palette.border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: _sidebarToggleButton(opens: true),
        ),
        _compactSidebarSection(_RefSection.local, _localBranches.length),
        _compactSidebarSection(_RefSection.remote, _refs.remote.length),
        _compactSidebarSection(_RefSection.tags, _refs.tags.length),
      ],
    ),
  );

  Widget _sidebarToggleButton({required bool opens}) => _shortcutBadge(
    label: shortcutLabel('1'),
    hintKey: const Key('sidebar-toggle-shortcut'),
    child: Tooltip(
      message: opens ? '왼쪽 패널 열기' : '왼쪽 패널 닫기',
      waitDuration: Duration.zero,
      child: SizedBox(
        width: 28,
        height: 28,
        child: IconButton(
          key: Key(opens ? 'sidebar-expand-button' : 'sidebar-collapse-button'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: () => _rebuild(() => _sidebarCollapsed = !opens),
          icon: CustomPaint(
            key: Key(opens ? 'sidebar-expand-icon' : 'sidebar-collapse-icon'),
            size: const Size(14.4, 14.4),
            painter: PaneToggleIconPainter(opens: opens, color: _palette.muted),
          ),
        ),
      ),
    ),
  );

  Widget _compactSidebarSection(_RefSection section, int count) => Semantics(
    label: '${section.label} $count',
    child: Container(
      key: Key('sidebar-compact-section-${section.name}'),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _palette.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(section.icon, size: 14, color: _palette.muted),
          const SizedBox(height: 3),
          Text(
            '$count',
            style: TextStyle(
              color: _palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );

  /// Every ref under [node], so a folder's eye governs its whole subtree.
  List<String> _refNamesUnder(RefTreeNode node) => [
    ?node.fullName,
    for (final child in node.children) ..._refNamesUnder(child),
  ];

  /// The eye that takes a ref — or a whole folder — off the graph. It stands in
  /// for the row's own icon rather than sitting beside it, so nothing shifts
  /// sideways on hover, and it stays put once closed because a hidden row has
  /// to keep saying it is hidden.
  ///
  /// [partial] is a folder with only some of its refs hidden.
  Widget _hideEye({
    required Key key,
    required bool hidden,
    required bool partial,
    required bool hovered,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    if (!hovered && !hidden && !partial) return icon;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Tooltip(
        message: hidden ? '그래프에 다시 표시' : '그래프에서 숨기기',
        child: Icon(
          hidden || partial
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 13,
          color: partial && !hidden
              ? _palette.muted.withValues(alpha: 0.5)
              : _palette.muted,
        ),
      ),
    );
  }

  /// A sidebar row's name, with a tooltip only when the row is too narrow to
  /// hold it. A tooltip over a name already fully on screen is just in the way.
  Widget _refLabel(
    String segment, {
    required String whole,
    required TextStyle style,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      // Measure the style the row actually paints with: a bare TextStyle
      // resolves to a different font than the inherited one and mismeasures.
      final resolved = DefaultTextStyle.of(context).style.merge(style);
      final label = Text(
        segment,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: resolved,
      );
      return _textWidth(segment, resolved) <= constraints.maxWidth
          ? label
          : Tooltip(message: whole, child: label);
    },
  );

  /// How far a ref sits from the one it tracks: what only it has in green,
  /// what only the other has in red. [against] names the other side.
  ///
  /// The box shrinks to its numbers so they sit against the name rather than
  /// floating a stop away from it, and the [FittedBox] scales a three-digit
  /// pair down rather than clipping it.
  Widget _divergenceBadge({
    required Key key,
    required int ahead,
    required int behind,
    required String against,
  }) => Flexible(
    child: Tooltip(
      message: [
        if (ahead > 0) '$against보다 $ahead개 커밋 앞서 있습니다',
        if (behind > 0) '$against보다 $behind개 커밋 뒤처져 있습니다',
      ].join(' · '),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 36),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text.rich(
            key: key,
            TextSpan(
              children: [
                if (ahead > 0)
                  TextSpan(
                    text: '+$ahead',
                    style: const TextStyle(color: successGreen),
                  ),
                if (ahead > 0 && behind > 0) const TextSpan(text: ' '),
                if (behind > 0)
                  TextSpan(
                    text: '−$behind',
                    style: const TextStyle(color: remoteBehindRed),
                  ),
              ],
            ),
            maxLines: 1,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    ),
  );

  Widget _refTreeRow(
    _RefSection section,
    RefTreeNode node,
    String path,
    int depth,
  ) {
    final name = node.fullName;
    final hasChildren = node.children.isNotEmpty;
    final folderKey = '${section.name}:$path';
    final folderCollapsed =
        _filter.trim().isEmpty && _collapsedRefFolders.contains(folderKey);
    // When the ref last moved, in the Date column's own words. A local branch
    // reports its birth (its reflog knows it); a remote branch and a tag report
    // their tip's own time, which the same for-each-ref already read — no extra
    // git call buys this line.
    final birth = name == null
        ? null
        : switch (section) {
            _RefSection.local => _refs.birthTimes[name],
            _RefSection.remote => _refs.branchActivityTimes[name],
            _RefSection.tags => _refs.tagCreatorTimes[name],
          };
    final current =
        section == _RefSection.local && name != null && name == _refs.current;
    final icon = name == null
        ? Icons.folder_outlined
        : section == _RefSection.tags
        ? Icons.sell_outlined
        : Icons.call_split;
    final iconColor = name != null && section != _RefSection.tags
        ? _refTipColor(name)
        : _palette.muted;
    // Both maps hold the difference from their own ref's point of view — the
    // remote side is flipped when it is loaded — so one badge reads either.
    final difference = name == null
        ? null
        : switch (section) {
            _RefSection.local => _refs.aheadBehind[name],
            _RefSection.remote => _refs.remoteAheadBehind[name],
            _RefSection.tags => null,
          };
    final ahead = difference?.ahead ?? 0;
    final behind = difference?.behind ?? 0;
    final pullState = section == _RefSection.remote && name != null
        ? remotePullState(_refs, name)
        : null;
    final inFolderTree = name == null || depth > 0;
    // Tags name no branch line, and the checked-out branch is a starting point
    // through HEAD whatever the eye says — neither offers one.
    final governed = section == _RefSection.tags || current
        ? const <String>[]
        : _refNamesUnder(node);
    final allHidden =
        governed.isNotEmpty && governed.every(_hiddenRefs.contains);
    final someHidden = governed.any(_hiddenRefs.contains);

    void toggleFolder() => _rebuild(() {
      if (!_collapsedRefFolders.remove(folderKey)) {
        _collapsedRefFolders.add(folderKey);
      }
    });

    Widget buildContent(bool hovered) => Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _refLabel(
                  node.segment,
                  // A ref says its whole path; a folder has nothing beyond the
                  // segment the row already draws.
                  whole: name ?? node.segment,
                  style: TextStyle(
                    color: current || hovered ? _palette.text : _palette.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              if (current) const SizedBox(width: 2),
              if (current)
                Tooltip(
                  message: '현재 체크아웃된 브랜치입니다',
                  child: Container(
                    key: Key('sidebar-head-$name'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.8),
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'HEAD',
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                      ),
                    ),
                  ),
                ),
              if (ahead > 0 || behind > 0) ...[
                const SizedBox(width: 4),
                // On a row too narrow for the name, the HEAD chip and the
                // badge together, the badge gives ground rather than letting
                // the row overflow — its FittedBox scales the pair down.
                _divergenceBadge(
                  key: Key('sidebar-${section.name}-divergence-$name'),
                  ahead: ahead,
                  behind: behind,
                  // Each side names the other: a local row is measured against
                  // its remote, a remote row against its local.
                  against: section == _RefSection.local ? '원격' : '로컬',
                ),
              ],
            ],
          ),
          // When the branch was cut, in the Date column's own words.
          if (birth != null)
            Text(
              socialTimeLabel(
                DateTime.fromMillisecondsSinceEpoch(birth * 1000),
                DateTime.now(),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hovered
                    ? _palette.text.withValues(alpha: 0.72)
                    : _palette.muted,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );

    Widget buildRow() => SizedBox(
      key: name == null ? null : Key('sidebar-row-$name'),
      height: birth == null ? 28 : 40,
      // One hover for the whole row. The eye sits at the row's own left edge,
      // clear of the tree indentation, so every eye lines up down the pane
      // however deep its ref is nested.
      child: HoverBuilder(
        builder: (rowHovered) => Row(
          children: [
            SizedBox(
              width: 22,
              height: double.infinity,
              child: governed.isEmpty || !(rowHovered || someHidden)
                  ? null
                  : Center(
                      child: _hideEye(
                        key: name == null
                            ? Key('sidebar-hide-folder-${section.name}-$path')
                            : Key('sidebar-hide-$name'),
                        hidden: allHidden,
                        partial: someHidden && !allHidden,
                        hovered: true,
                        icon: const SizedBox.shrink(),
                        onPressed: () => unawaited(
                          _toggleHiddenRefs(governed, hide: !allHidden),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: (inFolderTree ? 18 : 0) + depth * 16.0,
                  right: 4,
                ),
                child: Row(
                  children: [
                    if (hasChildren)
                      GestureDetector(
                        key: Key('sidebar-folder-${section.name}-$path'),
                        behavior: HitTestBehavior.opaque,
                        onTap: toggleFolder,
                        child: SizedBox(
                          width: 18,
                          height: double.infinity,
                          child: Icon(
                            folderCollapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 16,
                            color: _palette.muted,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 18),
                    if (name == null) ...[
                      Icon(icon, size: 13, color: iconColor),
                      const SizedBox(width: 7),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: toggleFolder,
                          child: Opacity(
                            opacity: allHidden ? 0.5 : 1,
                            child: buildContent(rowHovered),
                          ),
                        ),
                      ),
                    ] else
                      Expanded(
                        child: HoverBuilder(
                          // The row keeps its hover look while its context menu is
                          // open or the keyboard cursor sits on it, so the highlight
                          // doesn't die under the popup or between key presses.
                          builder: (pointerHovered) {
                            final pointerActive =
                                pointerHovered || _contextMenuRef == name;
                            final cursorHere =
                                _sidebarCursor == (section, name);
                            final hovered = pointerActive || cursorHere;
                            // The cursor keeps its shape but drains to gray while the
                            // keyboard lives in the timeline, so only one pane's
                            // selection carries color at a time.
                            final sidebarFocused = _sidebarFocusNode.hasFocus;
                            final cursorFill = sidebarFocused
                                ? _palette.selectedRow
                                : _restingSelection;
                            final cursorEdge = sidebarFocused
                                ? iconColor
                                : _TimelineScreenState._achromatic(iconColor);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // Double-clicks are detected by hand: an onDoubleTap
                              // recognizer would hold the gesture arena and delay every
                              // single click on the row and its pull button by 300 ms.
                              onTap: () {
                                // A click moves the keyboard cursor here too, so the
                                // arrows continue from the clicked row.
                                _rebuild(
                                  () => _sidebarCursor = (section, name),
                                );
                                _sidebarFocusNode.requestFocus();
                                if (pullState == null) {
                                  _selectRef(
                                    name,
                                    remote: section == _RefSection.remote,
                                    focusTimeline: false,
                                  );
                                } else {
                                  _tapRemoteRow(name);
                                }
                              },
                              // HEAD is excluded: git refuses to delete the checked-out
                              // branch, so the menu never offers it.
                              onSecondaryTapDown:
                                  section == _RefSection.local && !current
                                  ? (details) => unawaited(
                                      _showLocalBranchMenu(
                                        details.globalPosition,
                                        name,
                                      ),
                                    )
                                  : null,
                              child: Stack(
                                key: Key('sidebar-ref-hover-$name'),
                                clipBehavior: Clip.none,
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    left: -5,
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: DecoratedBox(
                                      key: Key(
                                        'sidebar-ref-hover-background-$name',
                                      ),
                                      decoration: BoxDecoration(
                                        // Selection paints like the timeline's
                                        // selected row, a plain hover like the
                                        // timeline's hover chip.
                                        color: cursorHere
                                            ? cursorFill
                                            : pointerActive
                                            ? _palette.neutralChip.withValues(
                                                alpha: 0.48,
                                              )
                                            : Colors.transparent,
                                        border: Border(
                                          left: BorderSide(
                                            color: cursorHere
                                                ? cursorEdge
                                                : Colors.transparent,
                                            width: cursorHere ? 2 : 0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Icon(icon, size: 13, color: iconColor),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Opacity(
                                          opacity: allHidden ? 0.5 : 1,
                                          child: KeyedSubtree(
                                            key: Key('sidebar-ref-$name'),
                                            child: buildContent(hovered),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // A pull started from the action strip or a
                                  // double-click says so here; nothing else sits on
                                  // the row's right edge, so the counts keep it.
                                  if (_pullingRemote == name)
                                    Positioned(
                                      right: 2,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: SizedBox(
                                          key: Key('sidebar-pull-busy-$name'),
                                          width: 22,
                                          height: 22,
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _palette.interactive,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Named rows carry a GlobalKey so the keyboard cursor can scroll to them.
    final row = name == null
        ? buildRow()
        : KeyedSubtree(
            key: _sidebarRowKeys['${section.name}:$name'] ??= GlobalKey(),
            child: buildRow(),
          );
    if (!current) return row;
    return DragTarget<GitCommit>(
      onWillAcceptWithDetails: (details) => _canCherryPick(details.data),
      onAcceptWithDetails: (details) =>
          unawaited(_confirmCherryPick(details.data)),
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border.all(color: mainAccent, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
        child: row,
      ),
    );
  }
}

extension _TimelineSidebarFlows on _TimelineScreenState {
  /// The named rows currently on screen, in paint order: sections top-down,
  /// minus collapsed sections, collapsed folders, and filtered-out names.
  List<(_RefSection, String)> _visibleRefRows() {
    final filtering = _filter.trim().isNotEmpty;
    final rows = <(_RefSection, String)>[];
    void walk(_RefSection section, List<RefTreeNode> nodes, String parentPath) {
      for (final node in nodes) {
        final path = parentPath.isEmpty
            ? node.segment
            : '$parentPath/${node.segment}';
        if (node.fullName case final name?) rows.add((section, name));
        final collapsed =
            !filtering &&
            _collapsedRefFolders.contains('${section.name}:$path');
        if (node.children.isNotEmpty && !collapsed) {
          walk(section, node.children, path);
        }
      }
    }

    for (final (section, names) in [
      (_RefSection.local, _localBranches),
      (_RefSection.remote, _refs.remote),
      (_RefSection.tags, _refs.tags),
    ]) {
      if (!filtering && _collapsedRefSections.contains(section)) continue;
      walk(section, buildRefTree(_visibleSectionNames(section, names)), '');
    }
    return rows;
  }

  /// Right-click on a local branch row: the delete menu at the pointer.
  Future<void> _showLocalBranchMenu(Offset position, String branch) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    _rebuild(() => _contextMenuRef = branch);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          key: Key('sidebar-delete-branch-$branch'),
          value: 'delete',
          height: 34,
          child: const Text('브랜치 삭제', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
    if (mounted) {
      _rebuild(() => _contextMenuRef = null);
    } else {
      _contextMenuRef = null;
    }
    if (action == 'delete' && mounted) await _confirmDeleteBranch(branch);
  }

  Iterable<Widget> _refSection(_RefSection section, List<String> names) sync* {
    final filtering = _filter.trim().isNotEmpty;
    final collapsed = !filtering && _collapsedRefSections.contains(section);
    final headerColor = _palette.text.withValues(alpha: 0.82);
    yield GestureDetector(
      key: Key('sidebar-section-${section.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _rebuild(() {
        if (!_collapsedRefSections.remove(section)) {
          _collapsedRefSections.add(section);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5),
        child: Container(
          key: Key('sidebar-section-band-${section.name}'),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _palette.raised.withValues(alpha: 0.7),
            border: Border.symmetric(
              horizontal: BorderSide(
                color: _palette.border.withValues(alpha: 0.7),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: headerColor,
              ),
              const SizedBox(width: 2),
              Icon(
                section.icon,
                key: Key('sidebar-section-icon-${section.name}'),
                size: 14,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              SizedBox(
                key: Key('sidebar-section-count-${section.name}'),
                child: Text(
                  '${names.length}',
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (collapsed) return;

    final hiddenTagCount = section == _RefSection.tags
        ? math.max(0, names.length - _TimelineScreenState._collapsedTagLimit)
        : 0;
    yield* _refTreeRows(
      section,
      buildRefTree(_visibleSectionNames(section, names)),
    );
    if (section == _RefSection.tags && !filtering && hiddenTagCount > 0) {
      yield _tagOverflowRow(hiddenTagCount);
    }
  }

  /// The names a section shows, after tag ordering/projection and the filter.
  /// Shared with [_visibleRefRows] so keyboard navigation walks exactly the
  /// rows on screen.
  List<String> _visibleSectionNames(_RefSection section, List<String> names) {
    final query = _filter.trim().toLowerCase();
    final filtering = query.isNotEmpty;
    final orderedNames = section == _RefSection.tags
        ? sortRefsNewestFirst(names, _refs.tagCreatorTimes)
        : names;
    final projectedNames =
        section == _RefSection.tags && !filtering && !_showAllTags
        ? orderedNames.take(_TimelineScreenState._collapsedTagLimit).toList()
        : orderedNames;
    return filtering
        ? orderedNames.where((name) => fuzzyMatch(name, query)).toList()
        : projectedNames;
  }

  Widget _tagOverflowRow(int hiddenTagCount) => GestureDetector(
    key: const Key('sidebar-tags-overflow'),
    behavior: HitTestBehavior.opaque,
    onTap: () => _rebuild(() => _showAllTags = !_showAllTags),
    child: SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              _showAllTags ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: _palette.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _showAllTags ? '태그 접기' : '나머지 $hiddenTagCount개',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _palette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Iterable<Widget> _refTreeRows(
    _RefSection section,
    List<RefTreeNode> nodes, {
    int depth = 0,
    String parentPath = '',
  }) sync* {
    final filtering = _filter.trim().isNotEmpty;
    for (final node in nodes) {
      final path = parentPath.isEmpty
          ? node.segment
          : '$parentPath/${node.segment}';
      yield _refTreeRow(section, node, path, depth);
      final folderKey = '${section.name}:$path';
      final collapsed = !filtering && _collapsedRefFolders.contains(folderKey);
      if (node.children.isNotEmpty && !collapsed) {
        yield* _refTreeRows(
          section,
          node.children,
          depth: depth + 1,
          parentPath: path,
        );
      }
    }
  }

  Widget _refChip(
    GitCommit commit,
    GitRef ref,
    Color color, {
    int? paletteIndex,
  }) {
    final colors = paletteIndex == null
        ? refPaletteColorsForName(
            ref.name,
            widget.refPalette,
            refPaletteAssignments: widget.refPaletteAssignments,
          )
        : refPaletteColorsAt(paletteIndex, widget.refPalette);
    final background = _comparison == null
        ? colors.base.withValues(alpha: .18)
        : color.withValues(alpha: .14);
    final border = _comparison == null
        ? colors.text.withValues(alpha: .30)
        : color.withValues(alpha: .55);
    final foreground = _comparison == null ? colors.text : color;
    return Container(
      key: Key('ref-chip-${commit.sha}-${ref.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          _refGlyph(ref, foreground, false),
          _refName(ref, foreground, false),
        ],
      ),
    );
  }
}
