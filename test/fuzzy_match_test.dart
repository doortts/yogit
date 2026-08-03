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
}
