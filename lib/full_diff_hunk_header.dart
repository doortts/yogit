import 'package:flutter/material.dart';

import 'full_diff_model.dart';
import 'full_diff_theme.dart';
import 'typography.dart';

class FullDiffHunkHeader extends StatelessWidget {
  const FullDiffHunkHeader({
    required this.hunk,
    required this.path,
    required this.hunkCount,
    super.key,
  });

  final DiffHunk hunk;
  final String path;
  final int hunkCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: const BoxDecoration(
      color: fullDiffHunkHeader,
      border: Border(
        top: BorderSide(color: fullDiffDivider),
        bottom: BorderSide(color: fullDiffDivider),
      ),
    ),
    child: Text(
      '${hunk.context.isEmpty ? path : hunk.context} · '
      'lines ${hunk.displayRange} · '
      'change ${hunk.index + 1} of $hunkCount',
      style: const TextStyle(
        fontFamily: technicalFontFamily,
        fontFamilyFallback: technicalFontFallback,
        fontSize: 12,
        height: 21 / 12,
        color: fullDiffMuted,
      ),
    ),
  );
}
