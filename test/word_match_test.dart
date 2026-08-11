import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/fuzzy_match.dart';

/// 낱말 단위 찾기: 질의도 대상도 낱말로 쪼개고, 질의의 낱말이 대상의 어느 낱말
/// 안에 통째로 들어 있으면 찾은 것이다. 낱말이 여럿이면 모두 찾혀야 하고, 어느
/// 낱말이 어디서 찾히든 순서는 묻지 않는다.
void main() {
  test('a word found inside a word, anywhere in it', () {
    expect(wordMatchPositions('feat: name a branch', 'name'), [6, 7, 8, 9]);
    expect(
      wordMatchPositions('feat: name a branch', 'nam'),
      [6, 7, 8],
      reason: '낱말 안 어디든 좋다',
    );
    expect(wordMatchPositions('feat: rename it', 'name'), [8, 9, 10, 11]);
  });

  test('letters scattered across the sentence are not a word', () {
    // 지금의 글자 단위 규칙이 잡던 위양성. c·a·r·d가 순서대로 있을 뿐이다.
    expect(
      wordMatchPositions(
        'feat: say what changed under the timeline, and let it be read',
        'card',
      ),
      isNull,
    );
    expect(wordMatchPositions('fix(merge): 충돌을 고친다', 'mrgfix'), isNull);
  });

  test('punctuation and underscores separate words, on both sides', () {
    expect(wordMatchPositions('fix(merge): 충돌', 'merge'), [4, 5, 6, 7, 8]);
    expect(wordMatchPositions('lib/full_diff_workspace.dart', 'diff'), [
      9,
      10,
      11,
      12,
    ]);
    expect(
      wordMatchPositions('fix(merge): 충돌', 'fix(merge)'),
      [0, 1, 2, 4, 5, 6, 7, 8],
      reason: '질의에 붙은 구두점도 낱말을 가를 뿐이다',
    );
  });

  test('every word of the query must be found, in any order', () {
    const subject = 'feat: name a clipped sidebar ref in full on hover';
    final forward = wordMatchPositions(subject, 'name hover');
    expect(forward, isNotNull);
    expect(
      wordMatchPositions(subject, 'hover name'),
      forward,
      reason: '순서를 묻지 않는다',
    );
    expect(
      wordMatchPositions(subject, 'name 없는말'),
      isNull,
      reason: '하나라도 못 찾으면 결과가 아니다',
    );
  });

  test('a word found twice lights up twice', () {
    expect(wordMatchPositions('git speaks git', 'git'), [0, 1, 2, 11, 12, 13]);
  });

  test('case is ignored, and Korean particles stay attached', () {
    expect(wordMatchPositions('feat: Name It', 'name'), [6, 7, 8, 9]);
    expect(
      wordMatchPositions('feat: 커밋을 찾는다', '커밋'),
      [6, 7],
      reason: '조사가 붙어도 낱말 안에서 찾힌다',
    );
  });

  test('a query with nothing in it finds nothing', () {
    expect(wordMatchPositions('anything', ''), isNull);
    expect(wordMatchPositions('anything', '   '), isNull);
    expect(wordMatchPositions('anything', '...'), isNull);
  });
}
