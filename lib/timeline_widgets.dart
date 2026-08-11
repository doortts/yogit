import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'timeline_graph_painters.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';

/// The small pieces the timeline builds itself from: its wordmark, the hover
/// and keycap wrappers, the copy button, the row-state scope, the legend dot
/// and the merge-message dialog. None of them knows anything about commits.

class Wordmark extends StatelessWidget {
  const Wordmark({required this.fontSize, super.key});

  final double fontSize;

  static const letters = <(String, Color)>[
    ('Y', Color(0xFFFFB3BA)),
    ('o', Color(0xFFFFDFBA)),
    ('g', Color(0xFFFFFFB3)),
    ('i', Color(0xFFBAFFC9)),
    ('t', Color(0xFFBAE1FF)),
  ];

  TextStyle get _style => TextStyle(
    fontFamily: 'DancingScript',
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
  );

  /// Where the 'Y' ends, so the badge can float in the space the lowercase
  /// letters leave above them.
  double get _afterY => (TextPainter(
    text: TextSpan(text: letters.first.$1, style: _style),
    textDirection: TextDirection.ltr,
  )..layout()).width;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Text.rich(
        TextSpan(
          children: [
            for (final (glyph, color) in letters)
              TextSpan(
                text: glyph,
                style: TextStyle(color: color),
              ),
          ],
        ),
        style: _style,
      ),
      Positioned(
        left: _afterY + fontSize * 0.03,
        // Above the x-height, below the Y's cap: the lowercase tops stay clear.
        top: fontSize * 0.06,
        child: CustomPaint(
          key: const Key('wordmark-cloud'),
          size: Size(fontSize * 0.92, fontSize * 0.54),
          painter: const _CloudBadgePainter(),
        ),
      ),
    ],
  );
}

/// The little blue cloud with wind streaks that rides the wordmark. Drawn at a
/// nominal 24x14 and scaled by whatever size the wordmark asks for.
class _CloudBadgePainter extends CustomPainter {
  const _CloudBadgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    Offset at(double x, double y) => Offset(x * unit, y * unit);

    final cloud = Path()
      ..addOval(Rect.fromCircle(center: at(5, 9), radius: 3.2 * unit))
      ..addOval(Rect.fromCircle(center: at(9, 6.6), radius: 4.4 * unit))
      ..addOval(Rect.fromCircle(center: at(13, 8.6), radius: 3.4 * unit))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2 * unit, 8.4 * unit, 12.4 * unit, 3.6 * unit),
          Radius.circular(1.8 * unit),
        ),
      );
    canvas.drawPath(
      cloud,
      Paint()
        ..isAntiAlias = true
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCFE8FF), Color(0xFF8EC9FF)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final wind = Paint()
      ..color = const Color(0xFFBAE1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(at(16.6, 4.8), at(19.8, 4.8), wind);
    canvas.drawLine(at(16.8, 10.6), at(19.2, 10.6), wind);
    // The long middle streak curls up at the tail.
    canvas.drawPath(
      Path()
        ..moveTo(17 * unit, 7.7 * unit)
        ..lineTo(21.4 * unit, 7.7 * unit)
        ..quadraticBezierTo(23.2 * unit, 7.7 * unit, 22.4 * unit, 5.9 * unit),
      wind,
    );
  }

  @override
  bool shouldRepaint(_CloudBadgePainter oldDelegate) => false;
}

class HoverBuilder extends StatefulWidget {
  const HoverBuilder({required this.builder, this.enabled = true, super.key});

  final Widget Function(bool hovered) builder;
  final bool enabled;

  @override
  State<HoverBuilder> createState() => HoverBuilderState();
}

class HoverBuilderState extends State<HoverBuilder> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
    onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
    child: widget.builder(_hovered),
  );
}

/// A keycap that also works as a button — the Enter chip runs the same toggle the
/// Enter key does.
class KeyCap extends StatefulWidget {
  const KeyCap({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  State<KeyCap> createState() => KeyCapState();
}

class KeyCapState extends State<KeyCap> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('keycap-${widget.label}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? palette.selectedRow : palette.raised,
            border: Border.all(
              color: _hovered ? palette.muted : palette.border,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            widget.label,
            style: TextStyle(color: palette.text, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class PaneToggleIconPainter extends CustomPainter {
  const PaneToggleIconPainter({required this.opens, required this.color});

  final bool opens;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        const Radius.circular(3.5),
      ),
      paint,
    );
    final dividerX = size.width * (opens ? 0.36 : 0.25);
    canvas.drawLine(
      Offset(dividerX, 3.5),
      Offset(dividerX, size.height - 3.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PaneToggleIconPainter oldDelegate) =>
      oldDelegate.opens != opens || oldDelegate.color != color;
}

/// Copies a ref name and answers with a check for a moment, so the click has
/// feedback without a snackbar.
class CopyButton extends StatefulWidget {
  const CopyButton({
    required this.text,
    required this.color,
    this.slot = 'copy-ref',
    super.key,
  });

  final String text;
  final Color color;

  /// Names this button apart from the other copier for the same ref: the modal's
  /// item and the status bar can both be on screen at once.
  final String slot;

  @override
  State<CopyButton> createState() => CopyButtonState();
}

class CopyButtonState extends State<CopyButton> {
  Timer? _reset;
  var _copied = false;
  var _hovered = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('${widget.slot}-${widget.text}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_copy()),
        child: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          size: 16,
          color: _copied
              ? widget.color
              : _hovered
              ? palette.text
              : palette.muted,
        ),
      ),
    );
  }
}

/// The message the merge commit an apply is about to write will carry. Prefilled
/// from the settings template; confirming pops the text exactly as edited, and
/// Escape or 취소 pops nothing at all — the apply itself is off.
///
/// Its own surface rather than [YogitAlert]'s: the mockup draws a wider card
/// with an editor in it, radius 12, and the preview's purple on 적용.
class CommitMessageDialog extends StatefulWidget {
  const CommitMessageDialog({
    required this.lead,
    required this.emphasis,
    required this.message,
    required this.templated,
    super.key,
  });

  /// The context line, split where the mockup colors it: quiet up to [lead],
  /// then [emphasis] in the preview's purple.
  final String lead;
  final String emphasis;
  final String message;

  /// Whether [message] came from the settings template or, with that emptied,
  /// from git's own wording — the helper line names whichever filled the box.
  final bool templated;

  @override
  State<CommitMessageDialog> createState() => CommitMessageDialogState();
}

class CommitMessageDialogState extends State<CommitMessageDialog> {
  late final _message = TextEditingController(text: widget.message);

  /// 무엇이 채웠는지 그대로 말한다 — 템플릿을 비웠으면 git 표준 메시지가 채운
  /// 것이고, Reviewed-by 줄이 없으면 그 줄을 설명할 일도 없다.
  String get _prefillHelp {
    final source = widget.templated
        ? '설정의 기본 메시지 템플릿으로 채워졌습니다'
        : 'git 표준 메시지로 채워졌습니다';
    return widget.message.contains('Reviewed-by:')
        ? '$source · Reviewed-by는 이 저장소의 커밋 프로필 이름입니다'
        : source;
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    // An empty message would write a subject-less merge commit, so it is the one
    // edit the dialog refuses; the helper line says so while it is refusing.
    final blank = _message.text.trim().isEmpty;
    // 시안의 CSS 그대로: 440 너비, 16/16/14 패딩, 줄 사이 10, 편집기는 88부터.
    return Center(
      child: Material(
        color: palette.surface,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF48484A)),
        ),
        child: SizedBox(
          width: 440,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '실제 적용하기',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    text: widget.lead,
                    children: [
                      TextSpan(
                        text: widget.emphasis,
                        style: const TextStyle(
                          color: previewPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Text(
                  '커밋 메시지',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 10.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('branch-apply-message'),
                  controller: _message,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  cursorColor: previewPurple,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11.5,
                    height: 1.55,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    // 편집기는 포커스를 받아도 테두리가 변하지 않는다 — 커서가 말해 준다.
                    border: _editorBorder(palette),
                    enabledBorder: _editorBorder(palette),
                    focusedBorder: _editorBorder(palette),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  blank
                      ? '비워서 적용할 수는 없습니다 · Esc 또는 취소로 적용 자체를 중단합니다'
                      : _prefillHelp,
                  style: TextStyle(color: palette.muted, fontSize: 10),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('branch-apply-cancel'),
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.text,
                        backgroundColor: palette.raised,
                        side: const BorderSide(color: Color(0xFF48484A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('branch-apply-confirm'),
                      onPressed: blank
                          ? null
                          : () => Navigator.pop(context, _message.text),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFFFFF4FF),
                        backgroundColor: const Color(0xFF594576),
                        disabledForegroundColor: const Color(
                          0xFFFFF4FF,
                        ).withValues(alpha: 0.4),
                        disabledBackgroundColor: const Color(
                          0xFF594576,
                        ).withValues(alpha: 0.35),
                        side: const BorderSide(color: Color(0xFF9D79D0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('적용'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _editorBorder(TimelineThemePalette palette) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: palette.border),
      );
}

/// Rebuilds one row only when *its* selected or hovered state flips. Every row
/// listens, but a notification that does not change this row's pair is dropped
/// before it can rebuild the subtree.
class RowStateScope extends StatefulWidget {
  const RowStateScope({
    required this.index,
    required this.selectedIndex,
    required this.hoverIndex,
    required this.builder,
    super.key,
  });

  final int index;
  final ValueListenable<int> selectedIndex;
  final ValueListenable<int> hoverIndex;
  final Widget Function(bool selected, bool hovered) builder;

  @override
  State<RowStateScope> createState() => RowStateScopeState();
}

class RowStateScopeState extends State<RowStateScope> {
  late bool _selected = widget.selectedIndex.value == widget.index;
  late bool _hovered = widget.hoverIndex.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.selectedIndex.addListener(_sync);
    widget.hoverIndex.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant RowStateScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list recycles elements across indexes, so re-read without a rebuild.
    if (oldWidget.index != widget.index) {
      _selected = widget.selectedIndex.value == widget.index;
      _hovered = widget.hoverIndex.value == widget.index;
    }
  }

  @override
  void dispose() {
    widget.selectedIndex.removeListener(_sync);
    widget.hoverIndex.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final selected = widget.selectedIndex.value == widget.index;
    final hovered = widget.hoverIndex.value == widget.index;
    if (selected == _selected && hovered == _hovered) return;
    setState(() {
      _selected = selected;
      _hovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_selected, _hovered);
}

/// What the selected rebase landing leaves behind. Without [mergeCommit] the
/// replayed commits carry the base rail straight on, because rebasing onto the
/// base branch is that line continuing; with it they ride a dashed arc onto the
/// merge commit the base branch lands on. Drawn in a 560 wide design space and
/// stretched to whatever the pane gives it.
/// Status bar legend marker: outlined commit, filled merge, dashed WIP.
class LegendDot extends StatelessWidget {
  const LegendDot({this.filled = false, this.dashed = false, super.key});

  final bool filled;
  final bool dashed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 10,
    child: CustomPaint(painter: _LegendDotPainter(filled, dashed)),
  );
}

class _LegendDotPainter extends CustomPainter {
  const _LegendDotPainter(this.filled, this.dashed);

  final bool filled;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (filled) {
      canvas.drawCircle(center, 4, Paint()..color = mainAccent);
      return;
    }
    final stroke = Paint()
      ..color = mainAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (dashed) {
      drawDashedRing(canvas, center, 3, stroke, 2.5);
      return;
    }
    canvas.drawCircle(center, 3, stroke);
  }

  @override
  bool shouldRepaint(covariant _LegendDotPainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.dashed != dashed;
}

/// Per-state color for the 18px file chips in the preview.
({Color background, Color letter}) fileStateChipColor(
  String status, {
  TimelineThemePalette palette = TimelineThemePalette.systemGraphite,
}) => switch (status.isEmpty ? '' : status[0]) {
  'A' => (background: mainAccent.withValues(alpha: 0.2), letter: mainAccent),
  'D' => (background: deletedPink.withValues(alpha: 0.2), letter: deletedPink),
  'R' || 'C' => (
    background: renamedPurple.withValues(alpha: 0.2),
    letter: renamedPurple,
  ),
  _ => (background: palette.neutralChip, letter: palette.text),
};

/// A tooltip that opens to the RIGHT of what it labels instead of below it.
///
/// A list of clipped names is the case Flutter's own tooltip reads badly: it
/// drops under the row it belongs to and covers the next name, which is the
/// one the reader was comparing against. This one keeps to the row's own line
/// and steps aside — to the left when the right edge has no room.
class SideTooltip extends StatefulWidget {
  const SideTooltip({
    required this.message,
    required this.child,
    this.cardKey,
    super.key,
  });

  final String message;
  final Widget child;

  /// Key on the card itself, so a test can find and measure it.
  final Key? cardKey;

  @override
  State<SideTooltip> createState() => _SideTooltipState();
}

class _SideTooltipState extends State<SideTooltip> {
  final _card = OverlayPortalController();
  final _anchorKey = GlobalKey(debugLabel: 'side tooltip anchor');

  Rect? get _anchorRect {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _card.show(),
    onExit: (_) => _card.hide(),
    child: OverlayPortal(
      controller: _card,
      overlayChildBuilder: (context) {
        final anchor = _anchorRect;
        if (anchor == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomSingleChildLayout(
              delegate: _SideTooltipLayout(anchor: anchor),
              child: Container(
                key: widget.cardKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black, fontSize: 13),
                ),
              ),
            ),
          ),
        );
      },
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
    ),
  );
}

/// A chip that grows to its whole name while the mouse is on it.
///
/// The BRANCH / TAG column cuts a name from the front, and a name whose front
/// is gone cannot be read at all. Rather than answer with a tooltip in some
/// other voice, the chip itself opens to full width in its own place, keeping
/// its colour and its border, and lies over the graph column while it does.
/// The reader sees the thing they were already looking at, larger.
///
/// [whole] is drawn instead of [child] only while hovered, and only when the
/// caller says the name was cut — a chip already showing its whole name has
/// nothing to open.
class GrowingChip extends StatefulWidget {
  const GrowingChip({
    required this.whole,
    required this.wholeWidth,
    required this.height,
    required this.child,
    this.revealKey,
    this.grown = true,
    super.key,
  });

  /// The same chip, sized to its whole name.
  final Widget whole;

  /// How wide [whole] wants to be, so the opening can be paced against it. An
  /// estimate is enough — the reveal only has to arrive; the last few points
  /// are covered by opening a little past it.
  final double wholeWidth;

  /// The height both copies share, which the reveal never changes.
  final double height;

  /// Key on the window the copy is revealed through, so a test can measure
  /// what is actually on screen rather than the chip behind it.
  final Key? revealKey;

  final Widget child;

  /// Whether the name is cut at all. False leaves the chip inert.
  final bool grown;

  /// Long enough to read as the chip opening rather than swapping, short
  /// enough that a reader running down a column is never waiting on it.
  static const openDuration = Duration(milliseconds: 140);

  /// Closing is quicker than opening. A name being taken away needs no
  /// introduction, and a mouse leaving is usually already on its way
  /// somewhere else.
  static const closeDuration = Duration(milliseconds: 90);

  @override
  State<GrowingChip> createState() => _GrowingChipState();
}

class _GrowingChipState extends State<GrowingChip>
    with SingleTickerProviderStateMixin {
  final _overlay = OverlayPortalController();
  final _anchorKey = GlobalKey(debugLabel: 'growing chip anchor');

  /// Built with the state rather than on first hover: a chip whose name always
  /// fit would otherwise build its first ticker inside dispose, where the
  /// element it needs to read the ticker mode from is already gone.
  late final AnimationController _open;

  @override
  void initState() {
    super.initState();
    _open =
        AnimationController(
          vsync: this,
          duration: GrowingChip.openDuration,
          reverseDuration: GrowingChip.closeDuration,
        )..addStatusListener((status) {
          // The copy stays mounted until it has finished closing, or the name
          // would vanish mid-retreat.
          if (status == AnimationStatus.dismissed) _overlay.hide();
        });
  }

  Rect? get _anchorRect {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _show() {
    if (!_overlay.isShowing) _overlay.show();
    _open.forward();
  }

  void _hide() => _open.reverse();

  @override
  void didUpdateWidget(covariant GrowingChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A column drag can widen the cell until the name fits while the mouse is
    // still on it. The open copy would then say the same thing twice.
    if (!widget.grown && _overlay.isShowing) {
      _open.value = 0;
      _overlay.hide();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchored = KeyedSubtree(key: _anchorKey, child: widget.child);
    if (!widget.grown) return anchored;
    return MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _hide(),
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) {
          final anchor = _anchorRect;
          if (anchor == null) return const SizedBox.shrink();
          return Positioned.fill(
            // The rows underneath stay clickable: the reader is reading, not
            // aiming at this.
            child: IgnorePointer(
              child: CustomSingleChildLayout(
                delegate: _GrowingChipLayout(anchor: anchor),
                child: _reveal(anchor),
              ),
            ),
          );
        },
        child: anchored,
      ),
    );
  }

  /// The box grows rightward and the letters the column cut off arrive from
  /// the left, one after another, until the whole name is standing there.
  ///
  /// A name is cut from the front, so what the reader has been looking at is
  /// its tail. The whole chip is drawn from the first frame and held against
  /// the RIGHT edge of a window that widens from exactly the cut chip's width:
  /// the tail therefore starts on the very pixels it already occupied and the
  /// head emerges from under the left edge as room appears. Aligning the other
  /// way would put the head on screen in frame one, which is a different piece
  /// of text than the one being replaced — it reads as a swap however long it
  /// takes.
  ///
  /// Nothing reflows while it opens: every letter is already in its final
  /// place, waiting to be uncovered.
  Widget _reveal(Rect anchor) => AnimatedBuilder(
    animation: _open,
    builder: (context, child) {
      // Resting outside the window entirely: a measurement a point short would
      // otherwise leave the name sitting under its own clip forever.
      if (_open.isCompleted) return widget.whole;
      final fraction = Curves.easeOutCubic.transform(_open.value);
      return ClipRRect(
        key: widget.revealKey,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: ui.lerpDouble(anchor.width, widget.wholeWidth, fraction),
          height: widget.height,
          child: child,
        ),
      );
    },
    child: OverflowBox(
      alignment: Alignment.centerRight,
      maxWidth: double.infinity,
      child: widget.whole,
    ),
  );
}

/// The grown chip sits exactly where the cut one sat, so nothing appears to
/// move — it only gets longer. A name too long for the room left of the window
/// edge slides back just far enough to stay whole.
class _GrowingChipLayout extends SingleChildLayoutDelegate {
  const _GrowingChipLayout({required this.anchor});

  final Rect anchor;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - _margin * 2),
          math.max(0, constraints.maxHeight - _margin * 2),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    math.max(_margin, math.min(anchor.left, size.width - childSize.width - _margin)),
    anchor.center.dy - childSize.height / 2,
  );

  @override
  bool shouldRelayout(_GrowingChipLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// Right of the anchor on the anchor's own line, left of it when the right
/// edge is out of room, and never past a window edge either way.
class _SideTooltipLayout extends SingleChildLayoutDelegate {
  const _SideTooltipLayout({required this.anchor});

  final Rect anchor;

  static const _gap = 6.0;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - _margin * 2),
          math.max(0, constraints.maxHeight - _margin * 2),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + _gap;
    final left = anchor.left - _gap - childSize.width;
    final x = right + childSize.width + _margin <= size.width
        ? right
        : left >= _margin
        ? left
        : math.max(_margin, size.width - childSize.width - _margin);
    final centered = anchor.center.dy - childSize.height / 2;
    return Offset(
      x,
      centered.clamp(
        _margin,
        math.max(_margin, size.height - childSize.height - _margin),
      ),
    );
  }

  @override
  bool shouldRelayout(_SideTooltipLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// One line of a [LocalChangeNotice]: a commit that changed hands.
typedef NoticeCommit = ({bool incoming, String shortSha, String subject});

/// What the timeline says when the repository changed under it — a pull in
/// another window, a rebase from a terminal.
///
/// A line that scrolls past before it is read is no better than silence, so
/// this one stays: `esc`, or a press anywhere else, takes it away. That is
/// also what lets it carry the commits themselves rather than a count alone.
class LocalChangeNotice extends StatelessWidget {
  const LocalChangeNotice({
    required this.headline,
    required this.lines,
    required this.commits,
    required this.more,
    required this.onDismiss,
    super.key,
  });

  /// The first thing that changed, said in full.
  final String headline;

  /// Everything else that changed, one line each. Empty when only one thing
  /// did, which is when [commits] gets the room instead.
  final List<String> lines;

  /// The commits that changed hands, newest first.
  final List<NoticeCommit> commits;

  /// How many more there were than the card could hold.
  final int more;

  final VoidCallback onDismiss;

  /// The list stops here. The notice stays until it is read, but a card taller
  /// than this stops being a notice and starts being a window — and the whole
  /// story is on the timeline behind it either way.
  static const maxCommits = 8;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final detail = lines.isNotEmpty || commits.isNotEmpty || more > 0;
    return TapRegion(
      // The press that dismisses is still the press the reader meant: it
      // selects the row it landed on, and the notice goes with it.
      onTapOutside: (_) => onDismiss(),
      child: Container(
        key: const Key('local-change-notice'),
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: palette.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 18,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    headline,
                    key: const Key('local-change-notice-headline'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.text, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 20),
                // A notice that will not leave on its own has to show the way
                // out.
                _EscHint(palette: palette, onPressed: onDismiss),
              ],
            ),
            if (detail) ...[
              const SizedBox(height: 9),
              Divider(height: 1, color: palette.border),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.text, fontSize: 13),
                  ),
                ),
              for (final commit in commits)
                _NoticeCommitRow(commit: commit, palette: palette),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 17, top: 3),
                  child: Text(
                    '외 $more개',
                    key: const Key('local-change-notice-more'),
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeCommitRow extends StatelessWidget {
  const _NoticeCommitRow({required this.commit, required this.palette});

  final NoticeCommit commit;
  final TimelineThemePalette palette;

  @override
  Widget build(BuildContext context) {
    // What left the branch is no longer the branch's: it reads a shade back.
    final faded = commit.incoming ? 1.0 : 0.62;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 17,
            child: Text(
              commit.incoming ? '+' : '−',
              style: TextStyle(
                color: commit.incoming ? mainAccent : deletedPink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            commit.shortSha,
            style: TextStyle(
              color: hashRed.withValues(alpha: faded),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              commit.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text.withValues(alpha: faded),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EscHint extends StatelessWidget {
  const _EscHint({required this.palette, required this.onPressed});

  final TimelineThemePalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      key: const Key('local-change-notice-dismiss'),
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: palette.background,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'esc',
              style: TextStyle(
                color: palette.muted,
                fontFamily: 'monospace',
                fontSize: 10.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('닫기', style: TextStyle(color: palette.muted, fontSize: 11)),
        ],
      ),
    ),
  );
}
