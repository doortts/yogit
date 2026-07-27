import 'package:flutter/material.dart';

import 'avatars.dart';
import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'full_source_hunk_map.dart';
import 'git.dart';
import 'typography.dart';

class FullBlameView extends StatelessWidget {
  const FullBlameView({
    required this.document,
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
    super.key,
  });

  final BlameDocument document;
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

  @override
  Widget build(BuildContext context) {
    final lineCount = document.file.lines.length;
    final sourceMap = FullSourceHunkMap(
      hunks: hunks,
      side: document.file.side,
      lineCount: lineCount,
      activeAnchor: activeAnchor,
    );
    final sourceLine = sourceMap.activeLine(activeAnchor);
    return LayoutBuilder(
      builder: (context, constraints) => FullDiffSelectionArea(
        child: ListView.builder(
          key: const Key('blame-list'),
          controller: controller,
          primary: controller == null,
          itemCount: lineCount,
          itemBuilder: (context, index) {
            final lineNumber = index + 1;
            final current = lineNumber == sourceLine;
            final row = KeyedSubtree(
              key: Key('blame-line-$lineNumber'),
              child: KeyedSubtree(
                key: current ? Key('blame-current-line-$lineNumber') : null,
                child: BlameSourceRow(
                  blame: document.lines[index],
                  lineNumber: lineNumber,
                  source: document.file.lines[index],
                  path: document.file.path,
                  side: document.file.side,
                  kind: sourceMap.kindForLine(lineNumber),
                  wrapLines: wrapLines,
                  highlighter: document.file.disableRichRendering
                      ? const _NoopSyntaxHighlighter()
                      : highlighter,
                  current: current,
                  viewportWidth: constraints.maxWidth,
                  avatarService: avatarService,
                  showRemoteAvatars: showRemoteAvatars,
                ),
              ),
            );
            return _probe(
              nearestHunkAnchorForSourceLine(
                hunks: hunks,
                side: document.file.side,
                lineNumber: lineNumber,
              ),
              current && activeAnchor != null
                  ? KeyedSubtree(key: _anchorKey(activeAnchor!), child: row)
                  : row,
            );
          },
        ),
      ),
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));

  Widget _probe(DiffAnchor? anchor, Widget child) => anchor == null
      ? child
      : FullDiffAnchorProbe(
          anchor: anchor,
          onAttached: onAnchorProbeAttached,
          onDetached: onAnchorProbeDetached,
          child: child,
        );
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
    required this.viewportWidth,
    this.avatarService,
    this.showRemoteAvatars = true,
    super.key,
  });

  final BlameLine blame;
  final int lineNumber;
  final String source;
  final String path;
  final FileDocumentSide side;
  final DiffLineKind kind;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final double viewportWidth;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;

  @override
  Widget build(BuildContext context) {
    final metadataWidth = viewportWidth >= 900
        ? 360.0
        : (viewportWidth * 0.38).clamp(250.0, 320.0);
    return FullDiffCodeRow(
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
            SizedBox(width: 20, child: _avatar()),
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
                  blame.summary,
                  key: Key('blame-summary-$lineNumber'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            SizedBox(
              key: Key('blame-date-$lineNumber'),
              width: 76,
              child: Text(
                _formatDate(blame.authorTimestamp),
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
              width: 3,
              height: fullDiffSourceRowHeight,
              child: ColoredBox(color: _railColor(blame.sha)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final identity = GitIdentity(name: blame.author, email: blame.authorEmail);
    Widget avatar(RemoteAvatar? remoteAvatar) => IdentityAvatar(
      key: Key('blame-avatar-$lineNumber'),
      identity: identity,
      remoteAvatar: remoteAvatar,
      size: 20,
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
