import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'timeline_theme.dart';

/// Splits prose into sentences, each keeping its closing mark. A trailing
/// fragment with no mark of its own counts as a sentence, so nothing is lost.
List<String> alertSentences(String text) {
  final sentences = <String>[];
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    buffer.write(character);
    if (character == '.' || character == '?' || character == '!') {
      sentences.add(buffer.toString().trim());
      buffer.clear();
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return [
    for (final sentence in sentences)
      if (sentence.isNotEmpty) sentence,
  ];
}

/// The message text laid out the way this app writes alerts: one line while it
/// fits, and one line per sentence once it would wrap anyway. Breaking mid
/// sentence to fill a line reads worse than two lines that each say one thing.
///
/// Falls back to ordinary wrapping when even a single sentence cannot fit,
/// because a forced break would buy nothing there.
String layoutAlertMessage(
  String text, {
  required TextStyle style,
  required double maxWidth,
}) {
  bool fits(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width <= maxWidth;
  }

  if (fits(text)) return text;
  final sentences = alertSentences(text);
  if (sentences.length < 2 || !sentences.every(fits)) return text;
  return sentences.join('\n');
}

/// Trims [text] from the FRONT until it fits, so the tail survives: a remote
/// address loses its host before it loses the repository's own name. Returns
/// the text untouched when it already fits.
String truncateHead(
  String text, {
  required TextStyle style,
  required double maxWidth,
}) {
  double widthOf(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  if (widthOf(text) <= maxWidth) return text;
  // The longest tail that still fits, ellipsis included.
  var low = 0;
  var high = text.length;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (widthOf('…${text.substring(text.length - mid)}') <= maxWidth) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return '…${text.substring(text.length - low)}';
}

/// What the alert is asking for. Only the badge and the confirm button's color
/// differ; a destructive action stays on the right so the button the user
/// reaches for does not move between dialogs.
enum YogitAlertRole { normal, destructive }

/// The app's alert shell, shaped after the macOS alert in Apple's guidelines:
/// narrow, the app icon above a short bold title, secondary text a size down,
/// and buttons bottom-right with only the default one colored.
class YogitAlert extends StatelessWidget {
  const YogitAlert({
    required this.title,
    required this.confirmLabel,
    this.boxWidth = width,
    this.subtitle,
    this.message,
    this.detail,
    this.body,
    this.cancelLabel = '취소',
    this.role = YogitAlertRole.normal,
    this.confirmKey,
    this.cancelKey,
    this.destructiveLabel,
    this.destructiveKey,
    this.onDestructive,
    this.onConfirm,
    super.key,
  });

  /// The kit's destructive tint: a dark red wash under a red label, instead
  /// of a solid red that would out-shout the primary action.
  static const destructiveFill = Color(0xFF4A2528);
  static const destructiveText = Color(0xFFFF6B6B);

  /// The approved mockup's alert width. The shell builds its own surface
  /// rather than using Dialog, so this is exact and not Dialog's floor.
  static const width = 280.0;

  /// The width an alert takes when its body is a list of commits: subjects
  /// have to stay readable or the list is decoration. Shared so the repository
  /// change notice and the Pull/Push receipts stand at the same size.
  static const listWidth = 520.0;

  /// How wide this one is. Alerts are prose and stay at [width]; one carrying
  /// a list of commit subjects has to be wider or the subjects are cut to
  /// nothing. The buttons keep their own width either way — see [_actions].
  final double boxWidth;

  final String title;

  /// A quiet line directly under the title, for what the title refers to
  /// rather than what it asks — the address behind `origin`, say.
  final Widget? subtitle;

  final String? message;

  /// A quieter second paragraph — the consequence, the size, the caveat.
  final String? detail;

  /// Anything that is not prose: a path, a summary, a form.
  final Widget? body;
  final String confirmLabel;
  final String cancelLabel;
  final YogitAlertRole role;
  final Key? confirmKey;
  final Key? cancelKey;

  /// A third choice turns the two-button row into the kit's vertical stack:
  /// the primary on top, this tinted action in the middle, cancel at the
  /// bottom. Pops with [onDestructive]'s value, or `'destructive'`.
  final String? destructiveLabel;
  final Key? destructiveKey;
  final Object? Function()? onDestructive;

  /// Returns what the dialog should pop with, or null to pop `true`. A form
  /// uses this to hand back its value.
  final Object? Function()? onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    // Every number here is the approved mockup's CSS, one to one: 16px
    // padding, a 13px w700 title, 11px body on a 1.5 line height at 82%,
    // 5px under the title, 13px above the buttons.
    final contentWidth = boxWidth - 32;
    const titleStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.35,
      letterSpacing: -0.08,
    );
    const messageStyle = TextStyle(fontSize: 11, height: 1.5);

    return Center(
      child: Material(
        color: palette.raised,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.border, width: 0.5),
        ),
        child: SizedBox(
          width: boxWidth,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: titleStyle.copyWith(color: palette.text)),
                if (subtitle case final subtitle?) ...[
                  const SizedBox(height: 4),
                  subtitle,
                ],
                if (message case final message?) ...[
                  const SizedBox(height: 5),
                  Text(
                    layoutAlertMessage(
                      message,
                      style: messageStyle,
                      maxWidth: contentWidth,
                    ),
                    style: messageStyle.copyWith(
                      color: palette.text.withValues(alpha: 0.82),
                    ),
                  ),
                ],
                if (body case final body?) ...[const SizedBox(height: 8), body],
                if (detail case final detail?) ...[
                  const SizedBox(height: 8),
                  Text(
                    layoutAlertMessage(
                      detail,
                      style: messageStyle,
                      maxWidth: contentWidth,
                    ),
                    style: messageStyle.copyWith(
                      color: palette.text.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                ..._actions(context, palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Two choices sit in a row — cancel leading, primary trailing, equal
  /// widths. A third choice switches to the kit's stack: primary, then the
  /// tinted destructive action, then cancel. Return follows the safe default
  /// only; a destructive confirm is never the Return target.
  List<Widget> _actions(BuildContext context, TimelineThemePalette palette) {
    final destructive = role == YogitAlertRole.destructive;
    final confirm = _AlertButton(
      key: confirmKey,
      label: confirmLabel,
      fill: destructive ? YogitAlert.destructiveFill : palette.interactive,
      textColor: destructive ? YogitAlert.destructiveText : Colors.white,
      autofocus: !destructive,
      onPressed: () => Navigator.pop(context, onConfirm?.call() ?? true),
    );
    final cancel = _AlertButton(
      key: cancelKey,
      label: cancelLabel,
      onPressed: () => Navigator.pop(context),
    );
    if (destructiveLabel case final label?) {
      return [
        confirm,
        const SizedBox(height: 7),
        _AlertButton(
          key: destructiveKey,
          label: label,
          fill: YogitAlert.destructiveFill,
          textColor: YogitAlert.destructiveText,
          onPressed: () =>
              Navigator.pop(context, onDestructive?.call() ?? 'destructive'),
        ),
        const SizedBox(height: 7),
        cancel,
      ];
    }
    // The buttons are the same size in every alert, however wide the box is.
    // A wider box is wider because its content needs the room; stretching the
    // answers along with it makes the pair read as a bigger decision than it
    // is. They sit centred under what they are answering, not pushed to one
    // side of it.
    return [
      Align(
        child: SizedBox(
          width: YogitAlert.width - 32,
          child: Row(
            children: [
              Expanded(child: cancel),
              const SizedBox(width: 7),
              Expanded(child: confirm),
            ],
          ),
        ),
      ),
    ];
  }
}

/// The recessed panel an alert puts its non-prose parts in. [YogitAlertBlock]
/// fills it with lines of text; anything with a shape of its own goes in
/// directly.
class YogitAlertPanel extends StatelessWidget {
  const YogitAlertPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: TimelineThemePalette.of(context).background.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

/// A left-aligned block for the parts of an alert that are not prose — a path,
/// a ref summary — so centered sentences stay readable beside them.
class YogitAlertBlock extends StatelessWidget {
  const YogitAlertBlock(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                color: palette.muted,
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

/// A macOS push button: sized to its title, bordered when it is one choice
/// among several, filled only when it is the default.
class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.label,
    required this.onPressed,
    this.fill,
    this.textColor,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? fill;
  final Color? textColor;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final filled = fill != null;
    // The kit's capsule: 28px tall, colored fill for the primary and the
    // destructive tint, quiet gray for cancel. No focus ring of our own —
    // the button's focus overlay covers actual keyboard traversal.
    return TextButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(28),
        // Pinned: the theme's adaptive density is compact on macOS and would
        // quietly shave these buttons to 20px — which is exactly how the
        // shipped alert drifted below the approved mockup once already.
        visualDensity: VisualDensity.standard,
        fixedSize: const Size.fromHeight(28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: filled ? fill : palette.border,
        foregroundColor: textColor ?? (filled ? Colors.white : palette.text),
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
        ),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    );
  }
}

/// Shows [alert] — a [YogitAlert] or a widget that builds one, such as a
/// form dialog — and answers what the user chose: the confirm value, or null
/// when they cancelled, pressed Escape, or clicked outside.
Future<T?> showYogitAlert<T>(BuildContext context, Widget alert) =>
    showDialog<T>(
      context: context,
      builder: (context) => Shortcuts(
        // Escape cancels, as it does in every macOS alert.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: alert,
      ),
    );
