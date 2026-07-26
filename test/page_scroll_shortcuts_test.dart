import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/page_scroll_shortcuts.dart';

void main() {
  const down = KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.arrowDown,
    logicalKey: LogicalKeyboardKey.arrowDown,
    timeStamp: Duration.zero,
  );
  const repeatUp = KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.arrowUp,
    logicalKey: LogicalKeyboardKey.arrowUp,
    timeStamp: Duration.zero,
  );

  test('recognizes only command shift vertical arrow downs and repeats', () {
    expect(
      pageScrollIntentFor(
        down,
        metaPressed: true,
        shiftPressed: true,
      )?.direction,
      1,
    );
    expect(
      pageScrollIntentFor(
        repeatUp,
        metaPressed: true,
        shiftPressed: true,
      )?.direction,
      -1,
    );
    expect(
      pageScrollIntentFor(down, metaPressed: true, shiftPressed: false),
      isNull,
    );
    expect(
      pageScrollIntentFor(down, metaPressed: false, shiftPressed: true),
      isNull,
    );
    expect(
      pageScrollIntentFor(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
        metaPressed: true,
        shiftPressed: true,
      ),
      isNull,
    );
    expect(
      pageScrollIntentFor(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
        metaPressed: true,
        shiftPressed: true,
      ),
      isNull,
    );
  });

  testWidgets('scrolls 48 pixels, clamps, and jumps repeats immediately', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 100,
            child: SingleChildScrollView(
              controller: controller,
              child: const SizedBox(height: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    applyPageScroll(controller, direction: 1, animate: false);
    expect(controller.position.pixels, 48);

    for (var index = 0; index < 10; index++) {
      applyPageScroll(controller, direction: 1, animate: false);
    }
    expect(controller.position.pixels, 200);

    for (var index = 0; index < 10; index++) {
      applyPageScroll(controller, direction: -1, animate: false);
    }
    expect(controller.position.pixels, 0);

    applyPageScroll(controller, direction: 1, animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final animatedPixels = controller.position.pixels;
    expect(animatedPixels, greaterThan(0));

    applyPageScroll(controller, direction: 1, animate: false);
    expect(controller.position.pixels, animatedPixels + 48);
  });
}
