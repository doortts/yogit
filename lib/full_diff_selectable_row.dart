import 'package:flutter/material.dart';

import 'full_diff_theme.dart';

class FullDiffSelectableRowSurface extends StatelessWidget {
  const FullDiffSelectableRowSurface({
    required this.selected,
    required this.focused,
    required this.child,
    super.key,
  });

  final bool selected;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: selected ? fullDiffSelection : fullDiffCanvas,
      border: selected && focused ? Border.all(color: fullDiffAccent) : null,
    ),
    child: child,
  );
}
