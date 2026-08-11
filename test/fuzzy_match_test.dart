import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/fuzzy_match.dart';

void main() {
  test('matches characters in order, anywhere in the candidate', () {
    expect(fuzzyMatch('notes-split-pane', 'notsp'), isTrue);
    expect(fuzzyMatch('notes-split-pane', 'nsp'), isTrue);
    expect(fuzzyMatch('notes-split-pane', 'split'), isTrue);
    expect(fuzzyMatch('notes-split-pane', 'pans'), isFalse);
    expect(fuzzyMatch('notes-split-pane', 'xyz'), isFalse);
  });

  test('ignores case and whitespace in the query', () {
    expect(fuzzyMatch('codex/Monaco-Outline', 'MONACO'), isTrue);
    expect(fuzzyMatch('codex/monaco-outline', 'co mo'), isTrue);
  });

  test('an empty query keeps the whole list', () {
    expect(fuzzyMatch('anything', ''), isTrue);
    expect(fuzzyMatch('', ''), isTrue);
    expect(fuzzyMatch('', 'a'), isFalse);
  });

  test('walks Korean text by character', () {
    expect(fuzzyMatch('기능/알림-정리', '알정'), isTrue);
    expect(fuzzyMatch('기능/알림-정리', '정알'), isFalse);
  });

  test('says where each character of the query landed', () {
    // 검색이 불을 켤 자리다: 질의가 짚은 글자만, 짚은 순서대로.
    expect(fuzzyMatchPositions('notes-split-pane', 'nsp'), [0, 4, 7]);
    expect(fuzzyMatchPositions('기능/알림-정리', '알정'), [3, 6]);
    expect(fuzzyMatchPositions('notes-split-pane', 'xyz'), isNull);
    expect(fuzzyMatchPositions('anything', ''), isEmpty);
  });

  test('a character written as a surrogate pair keeps both halves', () {
    // 두 code unit 중 하나만 켜지면 글자가 반으로 쪼개져 그려진다.
    expect(fuzzyMatchPositions('go 🚀 now', '🚀'), [3, 4]);
  });
}
