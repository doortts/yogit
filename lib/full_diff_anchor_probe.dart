import 'package:flutter/widgets.dart';

import 'full_diff_model.dart';

typedef FullDiffAnchorProbeCallback =
    void Function(DiffAnchor anchor, BuildContext context);

class FullDiffAnchorProbe extends StatefulWidget {
  const FullDiffAnchorProbe({
    required this.anchor,
    required this.child,
    this.onAttached,
    this.onDetached,
    super.key,
  });

  final DiffAnchor anchor;
  final Widget child;
  final FullDiffAnchorProbeCallback? onAttached;
  final FullDiffAnchorProbeCallback? onDetached;

  @override
  State<FullDiffAnchorProbe> createState() => _FullDiffAnchorProbeState();
}

class _FullDiffAnchorProbeState extends State<FullDiffAnchorProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onAttached?.call(widget.anchor, context);
  }

  @override
  void didUpdateWidget(covariant FullDiffAnchorProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchor.id == widget.anchor.id &&
        oldWidget.onAttached == widget.onAttached &&
        oldWidget.onDetached == widget.onDetached) {
      return;
    }
    oldWidget.onDetached?.call(oldWidget.anchor, context);
    widget.onAttached?.call(widget.anchor, context);
  }

  @override
  void dispose() {
    widget.onDetached?.call(widget.anchor, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
