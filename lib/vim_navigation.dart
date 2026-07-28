import 'package:flutter/services.dart';

LogicalKeyboardKey normalizeNavigationKey(
  LogicalKeyboardKey key, {
  required bool hasModifier,
}) {
  if (hasModifier) return key;
  return switch (key) {
    LogicalKeyboardKey.keyH => LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyJ => LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyK => LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyL => LogicalKeyboardKey.arrowRight,
    _ => key,
  };
}
