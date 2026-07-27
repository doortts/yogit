import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PageScrollIntent extends Intent {
  const PageScrollIntent(this.direction);

  final int direction;
}

PageScrollIntent? pageScrollIntentFor(
  KeyEvent event, {
  required bool metaPressed,
  required bool shiftPressed,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  if (!metaPressed || !shiftPressed) return null;
  return switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => const PageScrollIntent(-1),
    LogicalKeyboardKey.arrowDown => const PageScrollIntent(1),
    _ => null,
  };
}

void applyPageScroll(
  ScrollController controller, {
  required int direction,
  required bool animate,
}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  final distance = position.viewportDimension * 0.5;
  final target = (position.pixels + direction * distance)
      .clamp(position.minScrollExtent, position.maxScrollExtent)
      .toDouble();
  if (target == position.pixels) return;
  if (!animate) {
    controller.jumpTo(target);
    return;
  }
  unawaited(
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    ),
  );
}
