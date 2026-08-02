import 'package:flutter/material.dart';

import 'full_diff_theme.dart';
import 'typography.dart';

/// A key-combination badge that hangs under [child] while [visible]. The
/// colors default to the full-diff header's, so the timeline can pass its own
/// palette without either screen owning a second copy of the overlay.
class FullDiffShortcutHint extends StatefulWidget {
  const FullDiffShortcutHint({
    required this.visible,
    required this.label,
    required this.child,
    this.hintKey,
    this.background,
    this.borderColor,
    this.textColor,
    super.key,
  });

  final bool visible;
  final String label;
  final Widget child;
  final Key? hintKey;
  final Color? background;
  final Color? borderColor;
  final Color? textColor;

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
                offset: const Offset(0, -4),
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
                            color: widget.background ?? fullDiffHeader,
                            borderRadius: BorderRadius.circular(
                              fullDiffControlRadius,
                            ),
                            border: Border.all(
                              color: widget.borderColor ?? fullDiffDivider,
                            ),
                          ),
                          child: Text(
                            widget.label,
                            style: technicalTextStyle.copyWith(
                              color: widget.textColor ?? Colors.white,
                              fontSize: 11,
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
