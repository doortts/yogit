import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
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
  Widget build(BuildContext context) => ColoredBox(
    color: fullDiffHunkHeader,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        hunk.unifiedHeader(hunk.context.isEmpty ? path : hunk.context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: technicalFontFamily,
          fontFamilyFallback: technicalFontFallback,
          fontSize: 11,
          height: fullDiffSourceRowHeight / 11,
          color: fullDiffAccent,
        ),
      ),
    ),
  );
}
