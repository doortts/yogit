import 'package:flutter/material.dart';

import 'command_log.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';

/// One line of a ref row's menu. A null [onPressed] keeps the line in place,
/// disabled, so the menu's shape never shifts with the ref's state.
class RefMenuAction {
  const RefMenuAction({
    required this.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onPressed,
    this.danger = false,
  });

  final Key key;

  /// Drawn in the gutter, on the title's line. Every action carries one: a line
  /// without it would start where the others' words do and read as a heading.
  final IconData icon;

  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;

  /// A destructive action: painted red, and never taken as the default.
  final bool danger;
}

/// The menu a sidebar ref row opens on double-click: a header naming the ref
/// and the state it is in, the first action that is actually possible focused
/// as the default, and impossible actions disabled in place instead of hidden.
///
/// The row draws nothing for it — the anchor is a zero-size box at the row's
/// right edge, so the menu opens there without a button pushing the row's
/// commit counts around.
class RefRowMenu extends StatefulWidget {
  const RefRowMenu({
    required this.name,
    required this.actions,
    this.status,
    this.headerKey,
    this.controller,
    super.key,
  });

  final String name;

  /// Drawn under the name: what state the ref is in, in its own words.
  final Widget? status;

  /// In paint order. A separator sets the last one off, like the design's
  /// footer row.
  final List<RefMenuAction> actions;

  final Key? headerKey;

  /// Supplied by the row so its double-click can open this menu.
  final MenuController? controller;

  @override
  State<RefRowMenu> createState() => _RefRowMenuState();
}

class _RefRowMenuState extends State<RefRowMenu> {
  late final _controller = widget.controller ?? MenuController();

  static const _menuWidth = 240.0;

  /// Closes the menu and runs the item under its own name, so the console
  /// says what was asked for before it says what git was asked to do.
  void _run(RefMenuAction action) {
    _controller.close();
    CommandLogScope.run(
      context,
      '${action.title} — ${widget.name}',
      action.onPressed!,
    );
  }

  /// The first action the ref can actually take. A destructive action never
  /// wins the default — Enter should not be the fast path to a deletion.
  RefMenuAction? get _defaultAction {
    for (final action in widget.actions) {
      if (action.onPressed != null && !action.danger) return action;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final defaultAction = _defaultAction;

    Widget item(RefMenuAction action) {
      final isDefault = action == defaultAction;
      final disabled = action.onPressed == null;
      final foreground = disabled
          ? palette.muted.withValues(alpha: 0.55)
          : isDefault
          ? Colors.white
          : action.danger
          ? remoteBehindRed
          : palette.text;
      final secondary = disabled
          ? palette.muted.withValues(alpha: 0.55)
          : isDefault
          ? Colors.white.withValues(alpha: 0.78)
          : palette.muted;
      return Padding(
        // The gap between two lines, which is what tells them apart: without
        // it the pills touch and a title reads as the line above's third row.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: MenuItemButton(
          key: action.key,
          autofocus: isDefault,
          onPressed: action.onPressed == null ? null : () => _run(action),
          style: MenuItemButton.styleFrom(
            backgroundColor: isDefault
                ? palette.interactive
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(_menuWidth - 8, 0),
            maximumSize: const Size(_menuWidth - 8, double.infinity),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A pixel down, so the glyph sits on the title's line rather than
              // on the top of its box.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(action.icon, size: 15, color: foreground),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            action.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: foreground),
                          ),
                        ),
                        if (isDefault)
                          Text(
                            '⏎',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                      ],
                    ),
                    if (action.subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget separator() =>
        Divider(height: 11, thickness: 0.5, color: palette.border);

    final items = [for (final action in widget.actions) item(action)];
    if (items.length > 1) items.insert(items.length - 1, separator());

    return MenuAnchor(
      controller: _controller,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.raised),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 5),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: palette.border),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          key: widget.headerKey,
          width: _menuWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.text),
                ),
                ?widget.status,
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
        separator(),
        ...items,
      ],
      // Nothing to see: the row opens this from its own double-click, and the
      // anchor only says where the menu comes out.
      builder: (context, controller, child) => const SizedBox.shrink(),
    );
  }
}
