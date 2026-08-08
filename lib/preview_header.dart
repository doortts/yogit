import 'dart:async';
import 'dart:convert' show LineSplitter;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'git.dart';
import 'commit_time.dart';
import 'timeline_theme.dart';
import 'typography.dart';

class PreviewParent extends StatefulWidget {
  const PreviewParent({
    required this.shas,
    required this.commitOf,
    required this.loadMessage,
    required this.hashColor,
    super.key,
  });

  final List<String> shas;
  final GitCommit? Function(String sha) commitOf;
  final Future<String> Function(String sha) loadMessage;

  /// The colour hashes wear in this app's timeline.
  final Color hashColor;

  @override
  State<PreviewParent> createState() => PreviewParentState();
}

class PreviewParentState extends State<PreviewParent> {
  final _card = OverlayPortalController();
  final _anchorKey = GlobalKey(debugLabel: 'preview parent anchor');
  String? _message;
  var _requestSerial = 0;

  /// Where the line sits on screen, so the card can be placed against it.
  Rect? get _anchorRect {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  String get _sha => widget.shas.first;

  @override
  void didUpdateWidget(covariant PreviewParent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shas.first == _sha) return;
    _message = null;
    if (_card.isShowing) unawaited(_load());
  }

  @override
  void dispose() {
    _requestSerial++;
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_requestSerial;
    final sha = _sha;
    try {
      final message = await widget.loadMessage(sha);
      if (!mounted || serial != _requestSerial) return;
      setState(() => _message = message);
    } catch (_) {
      // The card still names the commit from the row the timeline already has.
    }
  }

  /// The subject the header shows: from the loaded row when the timeline holds
  /// that commit, and otherwise the first line of the message it fetched.
  String? get _subject =>
      widget.commitOf(_sha)?.subject ??
      (_message == null || _message!.isEmpty
          ? null
          : const LineSplitter().convert(_message!).first);

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final label = TextStyle(color: palette.muted, fontSize: 10);
    final subject = _subject;
    return MouseRegion(
      onEnter: (_) {
        _card.show();
        if (_message == null) unawaited(_load());
      },
      onExit: (_) => _card.hide(),
      child: OverlayPortal(
        controller: _card,
        overlayChildBuilder: (context) {
          final anchor = _anchorRect;
          if (anchor == null) return const SizedBox.shrink();
          return Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _HoverCardLayout(anchor: anchor),
              child: _PreviewParentCard(
                key: const Key('preview-parent-card'),
                sha: _sha,
                commit: widget.commitOf(_sha),
                message: _message,
                fallbackSubject: subject,
                hashColor: widget.hashColor,
              ),
            ),
          );
        },
        // One line, not a Row: the subject trails the hashes, so a narrow pane
        // eats the subject first and nothing ever overflows its box.
        child: KeyedSubtree(
          key: _anchorKey,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '부모 ', style: label),
                TextSpan(
                  text: [
                    for (final sha in widget.shas) shortSha(sha),
                  ].join(' · '),
                  style: TextStyle(
                    fontFamily: technicalFontFamily,
                    fontFamilyFallback: technicalFontFallback,
                    fontSize: 11,
                    color: palette.muted,
                  ),
                ),
                if (subject != null)
                  TextSpan(
                    text: '  $subject',
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Places a hover card against the line that opened it and keeps it on screen:
/// below when there is room, above when there is not, and never past an edge.
class _HoverCardLayout extends SingleChildLayoutDelegate {
  const _HoverCardLayout({required this.anchor});

  final Rect anchor;

  static const _gap = 4.0;
  static const _margin = 8.0;
  static const _maxWidth = 280.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.min(_maxWidth, constraints.maxWidth - _margin * 2),
          math.max(0, constraints.maxHeight - _margin * 2),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + _gap;
    final above = anchor.top - _gap - childSize.height;
    final top = below + childSize.height + _margin <= size.height
        ? below
        : above >= _margin
        ? above
        : math.max(_margin, size.height - childSize.height - _margin);
    final rightmost = math.max(_margin, size.width - childSize.width - _margin);
    return Offset(anchor.left.clamp(_margin, rightmost), top);
  }

  @override
  bool shouldRelayout(_HoverCardLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// What the hover reveals: the parent's hash and moment on one line, then its
/// message as written.
class _PreviewParentCard extends StatelessWidget {
  const _PreviewParentCard({
    required this.sha,
    required this.commit,
    required this.message,
    required this.fallbackSubject,
    required this.hashColor,
    super.key,
  });

  final String sha;
  final GitCommit? commit;
  final String? message;
  final String? fallbackSubject;
  final Color hashColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final lines = message == null
        ? const <String>[]
        : const LineSplitter().convert(message!);
    final subject = lines.isEmpty ? fallbackSubject : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';
    final mono = TextStyle(
      fontFamily: technicalFontFamily,
      fontFamilyFallback: technicalFontFallback,
      fontSize: 10,
      color: palette.muted,
    );
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(shortSha(sha), style: mono.copyWith(color: hashColor)),
                const SizedBox(width: 8),
                if (commit case final parent?)
                  Expanded(
                    child: Text(
                      exactCommitTime(parent.committerTimestamp),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: mono,
                    ),
                  ),
              ],
            ),
            if (subject != null) ...[
              const SizedBox(height: 5),
              Text(
                subject,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            if (body.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                body,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
            if (commit case final parent?) ...[
              const SizedBox(height: 7),
              Text(
                parent.author.name,
                style: TextStyle(color: palette.muted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The seven characters git itself prints for a full hash.
String shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
