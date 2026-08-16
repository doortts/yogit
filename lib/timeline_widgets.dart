import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'timeline_graph_painters.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';
import 'typography.dart';
import 'window_frame.dart';

/// The small pieces the timeline builds itself from: its wordmark, the hover
/// wrapper, the copy button, the row-state scope, the legend dot and the
/// merge-message dialog. None of them knows anything about commits.

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

  static TextStyle _styleAt(double fontSize) => TextStyle(
    fontFamily: 'DancingScript',
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
  );

  TextStyle get _style => _styleAt(fontSize);

  /// How wide the five glyphs come out at [fontSize], letter spacing and text
  /// scale of [context] included so this answers what the [Text] below will
  /// actually paint. The toolbar asks before it decides whether the window's
  /// centre has room for the mark: a script face is far narrower than five
  /// nominal em squares, and guessing would fold the mark away on windows it
  /// fits in.
  static double widthAt(BuildContext context, double fontSize) => (TextPainter(
    text: TextSpan(
      text: letters.map((letter) => letter.$1).join(),
      style: DefaultTextStyle.of(context).style.merge(_styleAt(fontSize)),
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: TextDirection.ltr,
  )..layout()).width;

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

class PaneToggleIconPainter extends CustomPainter {
  const PaneToggleIconPainter({
    required this.opens,
    required this.color,
    this.mirrored = false,
  });

  final bool opens;
  final Color color;

  /// 오른쪽에 달린 판의 버튼은 같은 그림을 좌우로 뒤집어 쓴다 — 문이 어느 쪽에
  /// 달렸는지가 두 버튼의 유일한 차이다.
  final bool mirrored;

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
    final fraction = opens ? 0.36 : 0.25;
    final dividerX = size.width * (mirrored ? 1 - fraction : fraction);
    canvas.drawLine(
      Offset(dividerX, 3.5),
      Offset(dividerX, size.height - 3.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PaneToggleIconPainter oldDelegate) =>
      oldDelegate.opens != opens ||
      oldDelegate.color != color ||
      oldDelegate.mirrored != mirrored;
}

/// The window with the preview panel filled in, for the placement segment in
/// the preview's own header. Which edge the panel lies against is the only
/// difference between the three glyphs; the tooltip carries the word.
class PreviewPlacementIconPainter extends CustomPainter {
  const PreviewPlacementIconPainter({
    required this.placement,
    required this.color,
  });

  final PreviewPlacement placement;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(1.5)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke,
    );
    final inside = frame.deflate(1);
    // `closed` never gets a button, so it falls in with the bottom panel.
    final panel = switch (placement) {
      PreviewPlacement.left => Rect.fromLTWH(
        inside.left,
        inside.top,
        inside.width * 0.36,
        inside.height,
      ),
      PreviewPlacement.right => Rect.fromLTRB(
        inside.right - inside.width * 0.36,
        inside.top,
        inside.right,
        inside.bottom,
      ),
      _ => Rect.fromLTRB(
        inside.left,
        inside.bottom - inside.height * 0.42,
        inside.right,
        inside.bottom,
      ),
    };
    canvas.drawRect(panel, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant PreviewPlacementIconPainter oldDelegate) =>
      oldDelegate.placement != placement || oldDelegate.color != color;
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
                    fontFamily: technicalFontFamily,
                    fontFamilyFallback: technicalFontFallback,
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
    math.max(
      _margin,
      math.min(anchor.left, size.width - childSize.width - _margin),
    ),
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
///
/// 읽는 사이에 저장소가 또 바뀌면 새 읽음이 카드를 갈아치우지 않고 아래에
/// 제 영역으로 붙는다 — 읽던 줄은 제자리에 남는다.
/// docs/local-change-notice-stack-mockup.html이 계약이다.
class LocalChangeNotice extends StatelessWidget {
  const LocalChangeNotice({
    required this.readings,
    required this.onDismiss,
    super.key,
  });

  /// 밖에서 벌어진 읽음들, 오래된 것부터. 마지막이 방금 온 것이다.
  final List<LocalChangeDetails> readings;
  final VoidCallback onDismiss;

  /// 카드가 세워 두는 영역의 수. 넘긴 것은 이미 화면의 역사에 반영된 뒤라
  /// 다시 펼칠 것이 없다 — 머리 한 줄이 세기만 한다.
  static const maxReadings = 5;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final shown = readings.length <= maxReadings
        ? readings
        : readings.sublist(readings.length - maxReadings);
    final folded = readings.length - shown.length;
    return TapRegion(
      // The press that dismisses is still the press the reader meant: it
      // selects the row it landed on, and the notice goes with it.
      onTapOutside: (_) => onDismiss(),
      // The card stands over the very rows it is describing, so it lets them
      // through rather than blanking them out — the reader can see the
      // history it is being told about. The blur behind it is what keeps the
      // text readable over a list of commit subjects.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            key: const Key('local-change-notice'),
            constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.raised.withValues(alpha: 0.78),
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
                    // 머리줄도 영역이 서는 자리에서 시작한다 — 왼쪽 선이
                    // 차지한 11px 만큼.
                    const SizedBox(width: 11),
                    Text(
                      '저장소가 밖에서 바뀜',
                      style: TextStyle(color: palette.text, fontSize: 13),
                    ),
                    Text(
                      '  ·  ${readings.length}건',
                      key: const Key('local-change-notice-count'),
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                    const Spacer(),
                    const SizedBox(width: 20),
                    // A notice that will not leave on its own has to show the
                    // way out. 영역이 몇이든 나가는 문은 하나다.
                    _EscHint(palette: palette, onPressed: onDismiss),
                  ],
                ),
                const SizedBox(height: 9),
                Divider(height: 1, color: palette.border),
                // 쌓인 영역이 화면을 넘기면 영역만 구르고, 머리줄과 나가는
                // 문은 제자리에 남는다.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (folded > 0)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 11,
                              top: 4,
                              bottom: 7,
                            ),
                            child: Text(
                              '이전 $folded건',
                              key: const Key('local-change-notice-folded'),
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        for (final (index, details) in shown.indexed)
                          _NoticeReading(
                            details: details,
                            palette: palette,
                            // 하나뿐인 영역은 무엇과도 견줄 것이 없어 표시할
                            // 새것도 없다.
                            fresh:
                                shown.length > 1 && index == shown.length - 1,
                            ruled: index > 0 || folded > 0,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드 안의 한 읽음. 갓 붙은 것은 왼쪽에 가는 선이 서서 어디가 새것인지
/// 말하고, 다음 것이 오면 그 선은 새것에게 넘어간다.
class _NoticeReading extends StatelessWidget {
  const _NoticeReading({
    required this.details,
    required this.palette,
    required this.fresh,
    required this.ruled,
  });

  final LocalChangeDetails details;
  final TimelineThemePalette palette;
  final bool fresh;
  final bool ruled;

  @override
  Widget build(BuildContext context) => Container(
    // 선은 새것에만 색이 든다. 자리는 늘 잡아 두어야 영역들이 한 줄에 선다.
    decoration: BoxDecoration(
      border: Border(
        top: ruled
            ? BorderSide(color: palette.border)
            : const BorderSide(color: Colors.transparent, width: 0),
        left: BorderSide(
          color: fresh ? mainAccent : Colors.transparent,
          width: 2,
        ),
      ),
    ),
    padding: const EdgeInsets.only(left: 9, top: 7, bottom: 6),
    child: LocalChangeDetailsView(details: details),
  );
}

/// What changed, as the notice and the question both say it: a headline, the
/// other things that changed, and the commits that moved.
class LocalChangeDetails {
  const LocalChangeDetails({
    required this.headline,
    required this.lines,
    required this.commits,
    required this.more,
    this.loadRest,
  });

  /// The first thing that changed, said in full.
  final String headline;

  /// Everything else that changed, one line each. Empty when only one thing
  /// did, which is when [commits] gets the room instead.
  final List<String> lines;

  /// The commits that changed hands, newest first.
  final List<NoticeCommit> commits;

  /// How many more there were than there was room for.
  final int more;

  /// '외 N개'를 누를 때 도는 조회 — 목록 전체를, 세어 둔 순서 그대로. 없으면
  /// 그 줄은 세기만 하고 눌리지 않는다.
  final Future<List<NoticeCommit>> Function()? loadRest;

  /// The list stops here. Whether it is a notice that stays or a question
  /// waiting to be answered, taller than this stops being either — and the
  /// whole story is on the timeline behind it.
  static const maxCommits = 8;

  bool get hasDetail => lines.isNotEmpty || commits.isNotEmpty || more > 0;
}

/// Draws [LocalChangeDetails]. The card wraps it in its own panel; the
/// question that asks whether to reload puts it in the alert's body, so the
/// reader answers with the change in front of them rather than after it.
class LocalChangeDetailsView extends StatefulWidget {
  const LocalChangeDetailsView({
    required this.details,
    this.trailing,
    super.key,
  });

  final LocalChangeDetails details;

  /// Sits at the end of the headline. The card puts its way out here.
  final Widget? trailing;

  /// 펼친 목록이 자라는 한계. 넘긴 것은 제 안에서 구른다 — 카드도 물음도
  /// 화면을 넘지 않는다.
  static const openHeight = 172.0;

  @override
  State<LocalChangeDetailsView> createState() => _LocalChangeDetailsViewState();
}

class _LocalChangeDetailsViewState extends State<LocalChangeDetailsView> {
  var _open = false;
  var _loading = false;
  List<NoticeCommit>? _rest;

  /// 접힌 것을 펼치고, 펼친 것을 접는다. 나머지는 실제로 펼친 사람만 값을
  /// 치른다 — 카드를 여는 조회는 여덟 개로 가볍게 둔다.
  Future<void> _toggle() async {
    if (_open) {
      setState(() => _open = false);
      return;
    }
    if (_rest != null) {
      setState(() => _open = true);
      return;
    }
    final loader = widget.details.loadRest;
    if (loader == null) return;
    setState(() => _loading = true);
    List<NoticeCommit> rest;
    try {
      rest = await loader();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    setState(() {
      _rest = rest;
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final details = widget.details;
    final commits = _open ? _rest ?? details.commits : details.commits;
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final commit in commits)
          _NoticeCommitRow(commit: commit, palette: palette),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                details.headline,
                key: const Key('local-change-notice-headline'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.text, fontSize: 13),
              ),
            ),
            if (widget.trailing case final trailing?) ...[
              const SizedBox(width: 20),
              trailing,
            ],
          ],
        ),
        if (details.hasDetail) ...[
          const SizedBox(height: 9),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 8),
          for (final line in details.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.text, fontSize: 13),
              ),
            ),
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: LocalChangeDetailsView.openHeight,
              ),
              child: SingleChildScrollView(child: rows),
            )
          else
            rows,
          if (details.more > 0)
            MoreLink(
              key: const Key('local-change-notice-more'),
              label: _loading
                  ? '불러오는 중'
                  : _open
                  ? '접기'
                  : '외 ${details.more}개',
              // 불러올 데가 없으면 세기만 하던 그대로 — 회색으로, 눌리지 않고.
              onTap: _loading || details.loadRest == null ? null : _toggle,
            ),
        ],
      ],
    );
  }
}

/// '외 N개' / '접기' — 세기만 하던 글자가 누를 자리가 된다. Push 확인창과
/// 밖에서 바뀜 알림이 같은 글자를 쓴다.
class MoreLink extends StatelessWidget {
  const MoreLink({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 17, top: 3),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? palette.muted : previewControlBlue,
              fontSize: 12,
            ),
          ),
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
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
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
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
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
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
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
