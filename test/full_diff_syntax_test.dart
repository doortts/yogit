import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_syntax.dart';

void main() {
  test('maps source and configuration names without guessing', () {
    final highlighter = HighlightJsSyntaxHighlighter();

    expect(highlighter.languageForPath('src/drlua.pas'), 'delphi');
    expect(highlighter.languageForPath('lib/main.dart'), 'dart');
    expect(highlighter.languageForPath('Dockerfile'), 'dockerfile');
    expect(highlighter.languageForPath('CMakeLists.txt'), 'cmake');
    expect(highlighter.languageForPath('.env.production'), 'ini');
    expect(highlighter.languageForPath('nginx.conf'), 'nginx');
    expect(highlighter.languageForPath('unknown.data'), isNull);
  });

  test('marks changed words but skips pathological lines', () {
    final ranges = changedWordRanges(
      'Scale := WindowScale;',
      'Scale := WindowPixelRatio;',
    );

    expect(ranges.oldRanges.single.text, 'WindowScale');
    expect(ranges.newRanges.single.text, 'WindowPixelRatio');
    expect(changedWordRanges('a' * 20001, 'b' * 20001).isEmpty, isTrue);
    final tooManyOld = List.generate(513, (index) => 'old$index').join(' ');
    final tooManyNew = List.generate(513, (index) => 'new$index').join(' ');
    expect(changedWordRanges(tooManyOld, tooManyNew).isEmpty, isTrue);
  });

  test('returns changed token ranges with UTF-16 offsets', () {
    final ranges = changedWordRanges(
      'const oldName = "값";',
      'const newName = "값";',
    );

    expect(ranges.oldRanges, hasLength(1));
    expect(ranges.oldRanges.single.text, 'oldName');
    expect(ranges.oldRanges.single.start, 6);
    expect(ranges.oldRanges.single.end, 13);
    expect(ranges.newRanges.single.text, 'newName');
    expect(ranges.newRanges.single.start, 6);
    expect(ranges.newRanges.single.end, 13);
    expect(changedWordRanges('same', 'same').isEmpty, isTrue);
  });

  test('maps every approved extended syntax by file extension', () {
    final highlighter = HighlightJsSyntaxHighlighter();
    const expected = <String, String>{
      'pl': 'perl',
      'r': 'r',
      'jl': 'julia',
      'scala': 'scala',
      'ex': 'elixir',
      'erl': 'erlang',
      'hs': 'haskell',
      'ml': 'ocaml',
      'fs': 'fsharp',
      'clj': 'clojure',
      'lisp': 'lisp',
      'scm': 'scheme',
      'v': 'verilog',
      'vhd': 'vhdl',
      'asm': 'x86asm',
      's': 'armasm',
      'f90': 'fortran',
      'matlab': 'matlab',
      'qml': 'qml',
      'tex': 'latex',
    };

    for (final entry in expected.entries) {
      expect(
        highlighter.languageForPath('fixture.${entry.key}'),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'highlights known syntax with source offsets and skips unknown files',
    () {
      final highlighter = HighlightJsSyntaxHighlighter();
      const source = 'final answer = "ok"; // note';

      final spans = highlighter.highlightLine('lib/example.dart', source);
      Color? colorFor(String token) {
        final start = source.indexOf(token);
        return spans
            .where(
              (span) => span.start == start && span.end == start + token.length,
            )
            .single
            .style
            .color;
      }

      expect(colorFor('final'), const Color(0xFF83C4FF));
      expect(colorFor('"ok"'), const Color(0xFFFFBFA0));
      expect(colorFor('// note'), const Color(0xFF919191));
      expect(highlighter.highlightLine('data/unknown.data', source), isEmpty);
    },
  );

  test('includes extended syntax only when the build flag enables it', () {
    const shouldHighlight = bool.fromEnvironment(
      'YOGIT_EXTENDED_SYNTAX',
      defaultValue: true,
    );
    final spans = HighlightJsSyntaxHighlighter().highlightLine(
      'script.pl',
      r'my $answer = 42;',
    );

    expect(spans.isNotEmpty, shouldHighlight);
  });
}
