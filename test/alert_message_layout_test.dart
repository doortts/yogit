import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/timeline_theme.dart';
import 'package:yogit/yogit_alert.dart';

void main() {
  const style = TextStyle(fontSize: 11, height: 1.45);

  testWidgets('a destructive alert colors only its default button red', (
    tester,
  ) async {
    Future<Set<Color?>> fillsFor(YogitAlertRole role) async {
      await tester.pumpWidget(
        MaterialApp(
          home: YogitAlert(
            title: '삭제할까요?',
            confirmLabel: '삭제',
            confirmKey: const Key('confirm'),
            cancelKey: const Key('cancel'),
            role: role,
          ),
        ),
      );
      // The key sits on the button shell; the fill lives on the button inside.
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
      return {fillOf(const Key('confirm')), fillOf(const Key('cancel'))};
    }

    final destructive = await fillsFor(YogitAlertRole.destructive);
    expect(destructive, contains(const Color(0xFFFF453A)));
    // The cancel button stays uncolored whichever role the alert carries.
    final normal = await fillsFor(YogitAlertRole.normal);
    expect(normal, isNot(contains(const Color(0xFFFF453A))));
    expect(normal, contains(TimelineThemePalette.systemGraphite.interactive));
  });

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
