import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/vim_navigation.dart';

void main() {
  test('maps unmodified vim keys to arrow keys', () {
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyH, hasModifier: false),
      LogicalKeyboardKey.arrowLeft,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyJ, hasModifier: false),
      LogicalKeyboardKey.arrowDown,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyK, hasModifier: false),
      LogicalKeyboardKey.arrowUp,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyL, hasModifier: false),
      LogicalKeyboardKey.arrowRight,
    );
  });

  test('leaves arrows, ordinary keys, and modified vim keys unchanged', () {
    expect(
      normalizeNavigationKey(
        LogicalKeyboardKey.arrowDown,
        hasModifier: false,
      ),
      LogicalKeyboardKey.arrowDown,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyA, hasModifier: false),
      LogicalKeyboardKey.keyA,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyJ, hasModifier: true),
      LogicalKeyboardKey.keyJ,
    );
  });
}
