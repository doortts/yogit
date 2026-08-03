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
    this.message,
    this.detail,
    this.body,
    this.cancelLabel = '취소',
    this.role = YogitAlertRole.normal,
    this.confirmKey,
    this.cancelKey,
    this.wide = false,
    this.onConfirm,
    super.key,
  });

  /// Apple's alert width. Long content grows downward, never sideways.
  static const width = 270.0;

  /// For alerts whose body is a block rather than a sentence.
  static const wideWidth = 340.0;

  final String title;
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
  final bool wide;

  /// Returns what the dialog should pop with, or null to pop `true`. A form
  /// uses this to hand back its value.
  final Object? Function()? onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final destructive = role == YogitAlertRole.destructive;
    final accent = destructive ? const Color(0xFFFF453A) : palette.interactive;
    final contentWidth = (wide ? wideWidth : width) - 32;
    const messageStyle = TextStyle(fontSize: 11, height: 1.45);

    return Dialog(
      backgroundColor: palette.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border, width: 0.5),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: wide ? wideWidth : width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _icon(palette, destructive),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  letterSpacing: -0.08,
                ),
              ),
              if (message case final message?) ...[
                const SizedBox(height: 5),
                Text(
                  layoutAlertMessage(
                    message,
                    style: messageStyle,
                    maxWidth: contentWidth,
                  ),
                  textAlign: TextAlign.center,
                  style: messageStyle.copyWith(
                    color: palette.text.withValues(alpha: 0.85),
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
                  textAlign: TextAlign.center,
                  style: messageStyle.copyWith(color: palette.muted),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _AlertButton(
                    key: cancelKey,
                    label: cancelLabel,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  _AlertButton(
                    key: confirmKey,
                    label: confirmLabel,
                    fill: accent,
                    autofocus: true,
                    onPressed: () =>
                        Navigator.pop(context, onConfirm?.call() ?? true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The app icon says who is asking; the badge on its shoulder says how
  /// serious the question is.
  Widget _icon(TimelineThemePalette palette, bool destructive) => SizedBox(
    height: 56,
    child: Center(
      child: SizedBox.square(
        dimension: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 56,
                height: 56,
                filterQuality: FilterQuality.medium,
              ),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.raised,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  destructive ? Icons.cancel : Icons.error,
                  size: 20,
                  color: destructive
                      ? const Color(0xFFFF453A)
                      : const Color(0xFFFF9F0A),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
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
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? fill;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final filled = fill != null;
    return DecoratedBox(
      // The focus ring sits outside the button, as the default button's does.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: autofocus && filled
              ? fill!.withValues(alpha: 0.35)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 22),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: filled ? fill : palette.border,
          foregroundColor: filled ? Colors.white : palette.text,
          textStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: filled ? FontWeight.w500 : FontWeight.w400,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: filled ? Colors.transparent : palette.border,
              width: 0.5,
            ),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Shows [alert] and answers what the user chose: the confirm value, or null
/// when they cancelled, pressed Escape, or clicked outside.
Future<T?> showYogitAlert<T>(BuildContext context, YogitAlert alert) =>
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
