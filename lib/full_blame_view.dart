import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yogit/vim_navigation.dart';

import 'avatars.dart';
import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_commit_info_card.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'full_source_hunk_map.dart';
import 'git.dart';
import 'typography.dart';

const fullBlameAvatarWidth = 20.0;
const fullBlameRailWidth = 1.0;

double fullBlameMetadataWidth(double viewportWidth) => viewportWidth >= 900
    ? 360.0
    : (viewportWidth * 0.38).clamp(250.0, 320.0).toDouble();

class FullBlameView extends StatefulWidget {
  FullBlameView({
    required BlameDocument document,
    required this.hunks,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    this.avatarService,
    this.showRemoteAvatars = true,
    this.focusNode,
    this.onMoveToFiles,
    this.loadCommitMessage,
    super.key,
  }) : file = document.file,
       lines = document.lines;

  const FullBlameView.loading({
    required this.file,
    required this.hunks,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    this.avatarService,
    this.showRemoteAvatars = true,
    this.focusNode,
    this.onMoveToFiles,
    this.loadCommitMessage,
    super.key,
  }) : lines = null;

  final FileDocument file;
  final List<BlameLine>? lines;
  final List<DiffHunk> hunks;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final FullDiffAnchorProbeCallback? onAnchorProbeAttached;
  final FullDiffAnchorProbeCallback? onAnchorProbeDetached;
  final ScrollController? controller;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;
  final FocusNode? focusNode;
  final VoidCallback? onMoveToFiles;
  final FullDiffCommitMessageLoader? loadCommitMessage;

  @override
  FullBlameViewState createState() => FullBlameViewState();
}

class FullBlameViewState extends State<FullBlameView> {
  final _ownedFocusNode = FocusNode(debugLabel: 'full blame lines');
  final _selectedLink = LayerLink();
  final _selectedRowKey = GlobalKey(debugLabel: 'selected blame row');
  int? _selectedLine;
  int? _hoveredLine;
  int _navigationSerial = 0;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @visibleForTesting
  int get debugRetainedRowGlobalKeyCount => 1;

  @override
  void dispose() {
    _navigationSerial++;
    _ownedFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = widget.file.lines.length;
    final sourceMap = FullSourceHunkMap(
      hunks: widget.hunks,
      side: widget.file.side,
      lineCount: lineCount,
      activeAnchor: widget.activeAnchor,
    );
    final sourceLine = sourceMap.activeLine(widget.activeAnchor);
    final selectedLine = _selectedLine;
    final lines = widget.lines;
    final selectedBlame = selectedLine == null || lines == null
        ? null
        : lines[selectedLine - 1];
    return LayoutBuilder(
      builder: (context, constraints) {
        final metadataWidth = fullBlameMetadataWidth(constraints.maxWidth);
        final cardWidth =
            (metadataWidth - fullBlameAvatarWidth - fullBlameRailWidth)
                .clamp(0.0, double.infinity)
                .toDouble();
        return Focus(
          key: const Key('blame-list-focus'),
          focusNode: _focusNode,
          onFocusChange: _handleFocusChange,
          onKeyEvent: _handleKeyEvent,
          child: FullDiffSelectionArea(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                ListView.builder(
                  key: const Key('blame-list'),
                  controller: widget.controller,
                  primary: widget.controller == null,
                  itemCount: lineCount,
                  itemBuilder: (context, index) {
                    final lineNumber = index + 1;
                    final current = lineNumber == sourceLine;
                    final selected = lineNumber == _selectedLine;
                    final blame = lines?[index];
                    Widget interactive = Semantics(
                      key: Key('blame-line-$lineNumber'),
                      container: true,
                      excludeSemantics: true,
                      label: _semanticsLabel(lineNumber, blame),
                      selected: selected,
                      button: true,
                      onTap: () => _selectLine(lineNumber),
                      child: MouseRegion(
                        onEnter: (_) => _setHoveredLine(lineNumber),
                        onExit: (_) => _clearHoveredLine(lineNumber),
                        child: InkWell(
                          excludeFromSemantics: true,
                          onTap: () => _selectLine(lineNumber),
                          child: BlameSourceRow(
                            blame: blame,
                            lineNumber: lineNumber,
                            source: widget.file.lines[index],
                            path: widget.file.path,
                            side: widget.file.side,
                            kind: sourceMap.kindForLine(lineNumber),
                            wrapLines: widget.wrapLines,
                            highlighter: widget.file.disableRichRendering
                                ? const _NoopSyntaxHighlighter()
                                : widget.highlighter,
                            current: current,
                            hovered: lineNumber == _hoveredLine,
                            selected: selected,
                            viewportWidth: constraints.maxWidth,
                            avatarService: widget.avatarService,
                            showRemoteAvatars: widget.showRemoteAvatars,
                          ),
                        ),
                      ),
                    );
                    if (selected) {
                      interactive = KeyedSubtree(
                        key: _selectedRowKey,
                        child: CompositedTransformTarget(
                          link: _selectedLink,
                          child: interactive,
                        ),
                      );
                    }
                    final row = KeyedSubtree(
                      key: current
                          ? Key('blame-current-line-$lineNumber')
                          : null,
                      child: interactive,
                    );
                    return _probe(
                      nearestHunkAnchorForSourceLine(
                        hunks: widget.hunks,
                        side: widget.file.side,
                        lineNumber: lineNumber,
                      ),
                      current && widget.activeAnchor != null
                          ? KeyedSubtree(
                              key: _anchorKey(widget.activeAnchor!),
                              child: row,
                            )
                          : row,
                    );
                  },
                ),
                if (selectedLine != null && selectedBlame != null)
                  Positioned.fill(
                    child: ClipRect(
                      child: CompositedTransformFollower(
                        link: _selectedLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topLeft,
                        followerAnchor: Alignment.topLeft,
                        offset: const Offset(
                          fullBlameAvatarWidth,
                          fullDiffSourceRowHeight * 2,
                        ),
                        child: UnconstrainedBox(
                          constrainedAxis: Axis.vertical,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: cardWidth,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: FullDiffCommitInfoCard(
                                key: Key('blame-commit-details-$selectedLine'),
                                info: FullDiffCommitInfo(
                                  sha: selectedBlame.sha,
                                  shortSha: _shortSha(selectedBlame.sha),
                                  fallbackMessage: selectedBlame.summary,
                                  author: selectedBlame.author,
                                  timestamp: selectedBlame.authorTimestamp,
                                ),
                                loadMessage:
                                    _canLoadCommitMessage(selectedBlame)
                                    ? widget.loadCommitMessage
                                    : null,
                                scrollLongMessage: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _setHoveredLine(int lineNumber) {
    if (_hoveredLine == lineNumber) return;
    setState(() => _hoveredLine = lineNumber);
  }

  void _clearHoveredLine(int lineNumber) {
    if (_hoveredLine != lineNumber) return;
    setState(() => _hoveredLine = null);
  }

  void _selectLine(int lineNumber) {
    _navigationSerial++;
    if (_selectedLine != lineNumber) {
      setState(() => _selectedLine = lineNumber);
    }
    _focusNode.requestFocus();
  }

  void _handleFocusChange(bool hasFocus) {
    if (!hasFocus || _selectedLine != null || widget.file.lines.isEmpty) {
      return;
    }
    final sourceMap = FullSourceHunkMap(
      hunks: widget.hunks,
      side: widget.file.side,
      lineCount: widget.file.lines.length,
      activeAnchor: widget.activeAnchor,
    );
    final initial = sourceMap.activeLine(widget.activeAnchor) ?? 1;
    setState(() => _selectedLine = initial);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final hasModifier =
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed;
    final key = normalizeNavigationKey(
      event.logicalKey,
      hasModifier: hasModifier,
    );
    if (hasModifier) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveToFiles?.call();
      return KeyEventResult.handled;
    }
    final delta = key == LogicalKeyboardKey.arrowUp
        ? -1
        : key == LogicalKeyboardKey.arrowDown
        ? 1
        : 0;
    if (delta == 0 || widget.file.lines.isEmpty) {
      return KeyEventResult.ignored;
    }
    final current = _selectedLine;
    if (current == null) return KeyEventResult.ignored;
    final next = (current + delta).clamp(1, widget.file.lines.length);
    if (next != current) {
      final navigationSerial = ++_navigationSerial;
      setState(() => _selectedLine = next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealSelectedLine(next, delta, navigationSerial);
      });
    }
    return KeyEventResult.handled;
  }

  void _revealSelectedLine(
    int lineNumber,
    int delta,
    int navigationSerial, {
    int attempt = 0,
  }) {
    if (!mounted ||
        navigationSerial != _navigationSerial ||
        _selectedLine != lineNumber) {
      return;
    }
    final selectedContext = _selectedRowKey.currentContext;
    if (selectedContext != null) {
      Scrollable.ensureVisible(
        selectedContext,
        alignmentPolicy: delta < 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return;
    }
    if (attempt >= 2) return;

    final controller =
        widget.controller ?? PrimaryScrollController.maybeOf(context);
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final target = _estimatedOffset(position, lineNumber, delta);
    if ((position.pixels - target).abs() > 0.5) {
      controller.jumpTo(target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelectedLine(
        lineNumber,
        delta,
        navigationSerial,
        attempt: attempt + 1,
      );
    });
  }

  double _estimatedOffset(ScrollPosition position, int lineNumber, int delta) {
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (max <= min) return min;
    if (!widget.wrapLines) {
      final rowTop = (lineNumber - 1) * fullDiffSourceRowHeight;
      final alignmentOffset = delta < 0
          ? rowTop
          : rowTop - position.viewportDimension + fullDiffSourceRowHeight;
      return alignmentOffset.clamp(min, max);
    }
    final lastIndex = widget.file.lines.length - 1;
    if (lastIndex <= 0) return min;
    final fraction = (lineNumber - 1) / lastIndex;
    return (min + (max - min) * fraction).clamp(min, max);
  }

  String _semanticsLabel(int lineNumber, BlameLine? blame) {
    if (blame == null) return 'Line $lineNumber, Blame loading';
    final summary = blame.summary.trim();
    if (summary.isNotEmpty) return 'Line $lineNumber, $summary';
    return 'Line $lineNumber, ${_shortSha(blame.sha)}, ${blame.author}';
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      widget.anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));

  Widget _probe(DiffAnchor? anchor, Widget child) => anchor == null
      ? child
      : FullDiffAnchorProbe(
          anchor: anchor,
          onAttached: widget.onAnchorProbeAttached,
          onDetached: widget.onAnchorProbeDetached,
          child: child,
        );
}

bool _canLoadCommitMessage(BlameLine blame) {
  if (blame.uncommitted) return false;
  final sha = blame.sha.trim();
  return RegExp(r'^[0-9a-fA-F]{7,64}$').hasMatch(sha) &&
      !RegExp(r'^0+$').hasMatch(sha);
}

class BlameSourceRow extends StatelessWidget {
  const BlameSourceRow({
    required this.blame,
    required this.lineNumber,
    required this.source,
    required this.path,
    required this.side,
    required this.kind,
    required this.wrapLines,
    required this.highlighter,
    required this.current,
    this.hovered = false,
    this.selected = false,
    required this.viewportWidth,
    this.avatarService,
    this.showRemoteAvatars = true,
    super.key,
  });

  final BlameLine? blame;
  final int lineNumber;
  final String source;
  final String path;
  final FileDocumentSide side;
  final DiffLineKind kind;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final bool hovered;
  final bool selected;
  final double viewportWidth;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;

  @override
  Widget build(BuildContext context) {
    final blame = this.blame;
    final loading = blame == null;
    final summary = loading ? 'Blame 계산 중…' : blame.summary;
    final date = loading ? '' : _formatDate(blame.authorTimestamp);
    final railColor = loading
        ? fullDiffMuted.withValues(alpha: 0.35)
        : _railColor(blame.sha);
    final metadataWidth = fullBlameMetadataWidth(viewportWidth);
    final row = FullDiffCodeRow(
      line: DiffLine(
        kind: kind,
        text: source,
        oldNumber: side == FileDocumentSide.old ? lineNumber : null,
        newNumber: side == FileDocumentSide.result ? lineNumber : null,
      ),
      path: path,
      wrapLines: wrapLines,
      highlighter: highlighter,
      current: current,
      showGutter: false,
      leadingMetadata: SizedBox(
        key: Key('blame-metadata-$lineNumber'),
        width: metadataWidth,
        height: fullDiffSourceRowHeight,
        child: Row(
          children: [
            SizedBox(width: fullBlameAvatarWidth, child: _avatar()),
            SizedBox(
              key: Key('blame-line-number-$lineNumber'),
              width: 42,
              child: Text(
                '$lineNumber',
                maxLines: 1,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: fullDiffMuted,
                  fontFamily: technicalFontFamily,
                  fontFamilyFallback: technicalFontFallback,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  summary,
                  key: loading
                      ? Key('blame-loading-$lineNumber')
                      : Key('blame-summary-$lineNumber'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: loading ? fullDiffMuted : null,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            SizedBox(
              key: Key('blame-date-$lineNumber'),
              width: 76,
              child: Text(
                date,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: fullDiffMuted,
                  fontFamily: technicalFontFamily,
                  fontFamilyFallback: technicalFontFallback,
                  fontSize: 10,
                ),
              ),
            ),
            SizedBox(
              key: Key('blame-rail-$lineNumber'),
              width: fullBlameRailWidth,
              height: fullDiffSourceRowHeight,
              child: ColoredBox(color: railColor),
            ),
          ],
        ),
      ),
    );
    final (surfaceKey, surfaceColor) = selected
        ? (
            Key('blame-selected-$lineNumber'),
            fullDiffSelection.withValues(alpha: 0.72),
          )
        : current
        ? (
            Key('blame-active-$lineNumber'),
            fullDiffAccent.withValues(alpha: 0.10),
          )
        : hovered
        ? (Key('blame-hover-$lineNumber'), Colors.white.withValues(alpha: 0.06))
        : (null, null);
    if (surfaceColor == null) return row;
    return Stack(
      children: [
        row,
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(key: surfaceKey, color: surfaceColor),
          ),
        ),
      ],
    );
  }

  Widget _avatar() {
    final blame = this.blame;
    if (blame == null) {
      return SizedBox(key: Key('blame-avatar-$lineNumber'));
    }
    final identity = GitIdentity(name: blame.author, email: blame.authorEmail);
    Widget avatar(RemoteAvatar? remoteAvatar) => IdentityAvatar(
      key: Key('blame-avatar-$lineNumber'),
      identity: identity,
      remoteAvatar: remoteAvatar,
      size: fullBlameAvatarWidth,
    );

    final service = showRemoteAvatars && _shaBranch(blame.sha) != null
        ? avatarService
        : null;
    if (service == null) return avatar(null);
    return FutureBuilder<CommitAvatars>(
      future: service.resolve(blame.sha),
      builder: (context, snapshot) => avatar(snapshot.data?.author),
    );
  }
}

String _formatDate(int? timestamp) {
  if (timestamp == null) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp * Duration.millisecondsPerSecond,
  );
  final month = '${date.month}'.padLeft(2, '0');
  final day = '${date.day}'.padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);

Color _railColor(String sha) {
  final branch = _shaBranch(sha);
  return branch == null ? fullDiffMuted : AvatarService.branchColor(branch);
}

int? _shaBranch(String sha) {
  final normalized = sha.trim();
  if (normalized.isEmpty ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized) ||
      RegExp(r'^0+$').hasMatch(normalized)) {
    return null;
  }
  final prefix = normalized.length <= 8
      ? normalized
      : normalized.substring(0, 8);
  return int.tryParse(prefix, radix: 16);
}

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
