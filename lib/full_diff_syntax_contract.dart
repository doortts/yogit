import 'package:flutter/material.dart';

@immutable
class CodeTokenSpan {
  const CodeTokenSpan({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final TextStyle style;
}

abstract interface class FullDiffSyntaxHighlighter {
  String? languageForPath(String path);
  List<CodeTokenSpan> highlightLine(String path, String source);
}
