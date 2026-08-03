import 'package:flutter/material.dart';

import 'git.dart';
import 'timeline_theme.dart';

/// What double-clicking the row (or pressing Enter in the menu) does.
enum RemotePullAction { pull, checkout, compare }

RemotePullAction remotePullDefaultAction(RemotePullState state) =>
    switch (state.kind) {
      RemotePullKind.fastForward => RemotePullAction.pull,
      RemotePullKind.noLocal => RemotePullAction.checkout,
      RemotePullKind.diverged => RemotePullAction.compare,
      RemotePullKind.upToDate =>
        state.checkedOut ? RemotePullAction.compare : RemotePullAction.checkout,
    };

/// The ↓ button on a hovered remote branch row, opening the state-aware menu
/// from the pull design: header with the divergence, the default action first
/// and focused, impossible actions disabled in place instead of hidden.
class RemotePullMenuButton extends StatefulWidget {
  const RemotePullMenuButton({
    required this.remoteBranch,
    required this.state,
    required this.visible,
    required this.onPull,
    required this.onCheckout,
    required this.onCompare,
    this.controller,
    super.key,
  });

  final String remoteBranch;
  final RemotePullState state;

  /// Supplied by the row so a double-click elsewhere can open this menu.
  final MenuController? controller;

  /// Whether the row is hovered. The anchor stays mounted either way so an
  /// open menu survives the pointer moving off the row and into the menu.
  final bool visible;
  final VoidCallback onPull;
  final VoidCallback onCheckout;
  final VoidCallback onCompare;

  @override
  State<RemotePullMenuButton> createState() => _RemotePullMenuButtonState();
}

class _RemotePullMenuButtonState extends State<RemotePullMenuButton> {
  late final _controller = widget.controller ?? MenuController();
  var _open = false;

  void _run(VoidCallback action) {
    _controller.close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final state = widget.state;
    final defaultAction = remotePullDefaultAction(state);

    Widget item({
      required Key key,
      required RemotePullAction action,
      required String title,
      String? subtitle,
      VoidCallback? onPressed,
    }) {
      final isDefault = onPressed != null && action == defaultAction;
      final disabled = onPressed == null;
      final foreground = disabled
          ? palette.muted.withValues(alpha: 0.55)
          : isDefault
          ? Colors.white
          : palette.text;
      final secondary = disabled
          ? palette.muted.withValues(alpha: 0.55)
          : isDefault
          ? Colors.white.withValues(alpha: 0.78)
          : palette.muted;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: MenuItemButton(
          key: key,
          autofocus: isDefault,
          onPressed: onPressed == null ? null : () => _run(onPressed),
          style: MenuItemButton.styleFrom(
            backgroundColor: isDefault
                ? palette.interactive
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(_menuWidth - 8, 0),
            maximumSize: const Size(_menuWidth - 8, double.infinity),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: foreground),
                    ),
                  ),
                  if (isDefault)
                    Text('⏎', style: TextStyle(fontSize: 12, color: secondary)),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: secondary),
                ),
            ],
          ),
        ),
      );
    }

    Widget separator() =>
        Divider(height: 9, thickness: 0.5, color: palette.border);

    final pullItem = switch (state.kind) {
      RemotePullKind.fastForward => item(
        key: const Key('remote-pull-pull'),
        action: RemotePullAction.pull,
        title: 'Pull — ${state.ahead}개 커밋',
        subtitle: state.checkedOut
            ? '현재 브랜치를 fast-forward'
            : '체크아웃 전환 없이 로컬만 전진',
        onPressed: widget.onPull,
      ),
      RemotePullKind.diverged => item(
        key: const Key('remote-pull-pull'),
        action: RemotePullAction.pull,
        title: 'Pull',
        subtitle: 'fast-forward 불가',
      ),
      RemotePullKind.upToDate => item(
        key: const Key('remote-pull-pull'),
        action: RemotePullAction.pull,
        title: 'Pull',
        subtitle: '받을 커밋 없음',
      ),
      RemotePullKind.noLocal => null,
    };

    final checkoutItem = state.checkedOut
        ? null
        : item(
            key: const Key('remote-pull-checkout'),
            action: RemotePullAction.checkout,
            title: '체크아웃',
            subtitle: switch (state.kind) {
              RemotePullKind.noLocal => '추적 브랜치 ${state.localBranch} 생성',
              RemotePullKind.fastForward => '${state.localBranch}으로 전환 후 pull',
              _ => '${state.localBranch}으로 전환',
            },
            onPressed: widget.onCheckout,
          );

    final compareItem = item(
      key: const Key('remote-pull-compare'),
      action: RemotePullAction.compare,
      title: '브랜치 diff로 비교',
      subtitle: state.kind == RemotePullKind.diverged
          ? 'merge / rebase는 미리보기에서 결정'
          : null,
      onPressed: widget.onCompare,
    );

    // The default action comes first; the rest keep a stable order below it,
    // and a separator sets the last item off like the design's footer row.
    final ordered = [
      (RemotePullAction.pull, pullItem),
      (RemotePullAction.checkout, checkoutItem),
      (RemotePullAction.compare, compareItem),
    ];
    final items = <Widget>[
      for (final entry in ordered)
        if (entry.$2 != null && entry.$1 == defaultAction) entry.$2!,
      for (final entry in ordered)
        if (entry.$2 != null && entry.$1 != defaultAction) entry.$2!,
    ];
    if (items.length > 1) items.insert(items.length - 1, separator());

    return MenuAnchor(
      controller: _controller,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.raised),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
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
          key: const Key('remote-pull-header'),
          width: _menuWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.remoteBranch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.text),
                ),
                _headerStatus(palette),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
        separator(),
        ...items,
      ],
      builder: (context, controller, child) => widget.visible || _open
          ? Tooltip(
              message: '로컬로 pull',
              child: InkWell(
                key: Key('sidebar-pull-${widget.remoteBranch}'),
                borderRadius: BorderRadius.circular(5),
                onTap: controller.open,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 13,
                    color: palette.text,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  static const _menuWidth = 240.0;

  Widget _headerStatus(TimelineThemePalette palette) {
    final state = widget.state;
    const green = Color(0xFF63D97C);
    const red = Color(0xFFFF6B6B);
    final muted = TextStyle(fontSize: 11, color: palette.muted);
    return switch (state.kind) {
      RemotePullKind.noLocal => Text('로컬 브랜치 없음', style: muted),
      RemotePullKind.upToDate => Text('최신 상태', style: muted),
      RemotePullKind.fastForward => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '로컬 ${state.localBranch}보다 '),
            TextSpan(
              text: '${state.ahead}개',
              style: const TextStyle(color: red),
            ),
            const TextSpan(text: ' 앞'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      ),
      RemotePullKind.diverged => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '+${state.ahead}',
              style: const TextStyle(color: green),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: '−${state.behind}',
              style: const TextStyle(color: red),
            ),
            const TextSpan(text: ' — 양쪽에 서로 없는 커밋'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      ),
    };
  }
}
