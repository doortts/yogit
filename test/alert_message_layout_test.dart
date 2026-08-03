import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/timeline_theme.dart';
import 'package:yogit/yogit_alert.dart';

void main() {
  const style = TextStyle(fontSize: 11, height: 1.45);

  String laidOut(String text, double width) =>
      layoutAlertMessage(text, style: style, maxWidth: width);

  test('splits prose into sentences, keeping their punctuation', () {
    expect(alertSentences('한 문장입니다.'), ['한 문장입니다.']);
    expect(alertSentences('앞 문장입니다. 뒤 문장입니까?'), ['앞 문장입니다.', '뒤 문장입니까?']);
    expect(alertSentences('경고! 계속할까요?'), ['경고!', '계속할까요?']);
    // A trailing fragment with no closing mark is still a sentence.
    expect(alertSentences('끝났습니다. 남은 말'), ['끝났습니다.', '남은 말']);
    expect(alertSentences('  '), <String>[]);
  });

  testWidgets('two choices sit in a row, cancel left and equal widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '저장소가 바뀌었습니다',
          cancelLabel: '나중에',
          cancelKey: Key('cancel'),
          confirmLabel: '새로고침',
          confirmKey: Key('confirm'),
        ),
      ),
    );

    // The approved mockup is the contract: a 280 alert.
    expect(YogitAlert.width, 280);
    final confirm = tester.getRect(find.byKey(const Key('confirm')));
    final cancel = tester.getRect(find.byKey(const Key('cancel')));
    // The mockup's two-choice anatomy: one row, cancel leading, same size.
    expect(cancel.top, confirm.top);
    expect(cancel.right, lessThan(confirm.left));
    expect(confirm.width, closeTo(cancel.width, 0.01));
    expect(confirm.height, 28);
    expect(cancel.height, 28);
    // 7px between the pair, 16px padding on both sides of a 280 dialog.
    expect(confirm.left - cancel.right, 7);
    expect(cancel.width + confirm.width, YogitAlert.width - 32 - 7);
    expect(
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byKey(const Key('confirm')),
              matching: find.byType(TextButton),
            ),
          )
          .style
          ?.textStyle
          ?.resolve({})
          ?.fontSize,
      13,
    );
  });

  testWidgets('a third choice turns the row into the kit stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '워크트리도 함께 삭제할까요?',
          confirmLabel: '워크트리만 정리',
          confirmKey: Key('confirm'),
          destructiveLabel: '둘 다 삭제',
          destructiveKey: Key('destructive'),
          cancelKey: Key('cancel'),
        ),
      ),
    );

    final confirm = tester.getRect(find.byKey(const Key('confirm')));
    final destructive = tester.getRect(find.byKey(const Key('destructive')));
    final cancel = tester.getRect(find.byKey(const Key('cancel')));
    // Primary on top, the destructive action between it and the way out.
    expect(confirm.bottom, lessThan(destructive.top));
    expect(destructive.bottom, lessThan(cancel.top));
    for (final rect in [confirm, destructive, cancel]) {
      expect(rect.width, YogitAlert.width - 32);
      expect(rect.height, 28);
    }
    expect(destructive.top - confirm.bottom, 7);
    expect(cancel.top - destructive.bottom, 7);
  });

  testWidgets('destructive actions carry the tint, not a solid red', (
    tester,
  ) async {
    Color? fillOf(Key key) => tester
        .widget<TextButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(TextButton),
          ),
        )
        .style
        ?.backgroundColor
        ?.resolve({});
    Color? textOf(Key key) => tester
        .widget<TextButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(TextButton),
          ),
        )
        .style
        ?.foregroundColor
        ?.resolve({});

    // A two-choice destructive alert tints its confirm button.
    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '브랜치를 삭제할까요?',
          confirmLabel: '삭제',
          confirmKey: Key('confirm'),
          cancelKey: Key('cancel'),
          role: YogitAlertRole.destructive,
        ),
      ),
    );
    expect(fillOf(const Key('confirm')), const Color(0xFF4A2528));
    expect(textOf(const Key('confirm')), const Color(0xFFFF6B6B));

    // A normal alert keeps the blue primary.
    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '적용할까요?',
          confirmLabel: '적용',
          confirmKey: Key('confirm'),
          cancelKey: Key('cancel'),
        ),
      ),
    );
    expect(
      fillOf(const Key('confirm')),
      TimelineThemePalette.systemGraphite.interactive,
    );
  });

  testWidgets('Return follows the safe default, never the destructive one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '브랜치를 삭제할까요?',
          confirmLabel: '삭제',
          confirmKey: Key('confirm'),
          role: YogitAlertRole.destructive,
        ),
      ),
    );
    bool focused(Key key) => tester
        .widget<TextButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(TextButton),
          ),
        )
        .autofocus;
    expect(focused(const Key('confirm')), isFalse);

    await tester.pumpWidget(
      const MaterialApp(
        home: YogitAlert(
          title: '적용할까요?',
          confirmLabel: '적용',
          confirmKey: Key('confirm'),
        ),
      ),
    );
    expect(focused(const Key('confirm')), isTrue);
  });

  testWidgets('a message that fits stays on one line', (tester) async {
    expect(laidOut('짧습니다. 확인할까요?', 600), '짧습니다. 확인할까요?');
  });

  double lineWidth(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  testWidgets('a wrapping message breaks between its sentences', (
    tester,
  ) async {
    const text = '앱 밖에서 HEAD나 브랜치가 변경되었습니다. 새로 읽어올까요?';
    const sentences = ['앱 밖에서 HEAD나 브랜치가 변경되었습니다.', '새로 읽어올까요?'];
    // Measured rather than guessed: wide enough for either sentence alone,
    // too narrow for both together, whatever font the test runs with.
    final width = sentences.map(lineWidth).reduce((a, b) => a > b ? a : b) + 1;
    expect(width, lessThan(lineWidth(text)));

    final broken = laidOut(text, width);
    expect(broken, sentences.join('\n'));
  });

  testWidgets('a single sentence too long to fit is left to wrap', (
    tester,
  ) async {
    const text = '이 브랜치는 아래 워크트리에 체크아웃되어 있어 지금은 삭제할 수 없습니다';
    expect(laidOut(text, 120), text);
  });

  testWidgets('sentences that still overflow on their own are left alone', (
    tester,
  ) async {
    // The second sentence cannot fit a line either, so forcing a break would
    // buy nothing and the natural wrap reads better.
    const text = '짧다. 아주 아주 아주 아주 아주 아주 아주 아주 긴 두 번째 문장이 이어집니다.';
    expect(laidOut(text, 90), text);
  });
}
