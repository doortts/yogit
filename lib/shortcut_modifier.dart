import 'dart:io';

import 'package:flutter/services.dart';

/// The platform's command modifier: ⌘ on Apple keyboards, Ctrl elsewhere.
/// One place decides it, so the key handlers, the labels, and the on-screen
/// hints can never disagree. Read from the host OS rather than
/// `defaultTargetPlatform`, which reports Android under `flutter test` and
/// would make a macOS build's tests disagree with the macOS build.
bool get usesMetaModifier => Platform.isMacOS;

bool isShortcutModifierKey(LogicalKeyboardKey key) => usesMetaModifier
    ? key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight
    : key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight;

bool get shortcutModifierHeld => usesMetaModifier
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// `'D'` reads as `⌘D` on macOS and `Ctrl+D` on Windows and Linux.
String shortcutLabel(String key) => usesMetaModifier ? '⌘$key' : 'Ctrl+$key';
