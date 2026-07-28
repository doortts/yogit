import 'package:flutter/material.dart';

import 'full_diff_theme.dart';
import 'typography.dart';

class FullDiffShortcutHint extends StatefulWidget {
  const FullDiffShortcutHint({
    required this.visible,
    required this.label,
    required this.child,
    this.hintKey,
    super.key,
  });

  final bool visible;
  final String label;
  final Widget child;
  final Key? hintKey;

  @override
  State<FullDiffShortcutHint> createState() => _FullDiffShortcutHintState();
}

class _FullDiffShortcutHintState extends State<FullDiffShortcutHint> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _controller.show();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => widget.visible
          ? Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                offset: const Offset(0, 4),
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: UnconstrainedBox(
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          key: widget.hintKey,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: fullDiffHeader,
                            borderRadius: BorderRadius.circular(
                              fullDiffControlRadius,
                            ),
                            border: Border.all(color: fullDiffDivider),
                          ),
                          child: Text(
                            widget.label,
                            style: technicalTextStyle.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
      child: widget.child,
    ),
  );
}
