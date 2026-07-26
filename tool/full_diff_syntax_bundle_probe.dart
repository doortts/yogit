import 'package:flutter/material.dart';
import 'package:yogit/full_diff_syntax.dart';

void main() {
  final highlighter = HighlightJsSyntaxHighlighter();
  final baseSpans = highlighter.highlightLine(
    'fixture.dart',
    'final answer = 42;',
  );
  final extendedSpans = highlighter.highlightLine(
    'fixture.pl',
    r'my $answer = 42;',
  );

  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${baseSpans.length}:${extendedSpans.length}'),
    ),
  );
}
