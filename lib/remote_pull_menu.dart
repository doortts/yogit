import 'package:flutter/material.dart';

import 'git.dart';
import 'ref_row_menu.dart';
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

/// The state-aware menu a remote branch row opens on double-click. The chrome —
/// header, default action, disabled-in-place items — is [RefRowMenu]'s, shared
/// with the local branch and tag rows; this widget only decides which actions a
/// remote in this state can take, and in what order.
class RemotePullMenu extends StatelessWidget {
  const RemotePullMenu({
    required this.remoteBranch,
    required this.state,
    required this.onPull,
    required this.onCheckout,
    required this.onCompare,
    required this.onDelete,
    this.controller,
    super.key,
  });

  final String remoteBranch;
  final RemotePullState state;

  /// Supplied by the row so its double-click can open this menu.
  final MenuController? controller;

  final VoidCallback onPull;
  final VoidCallback onCheckout;
  final VoidCallback onCompare;

  /// `push --delete`: the ref leaves the remote itself.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);

    final pullItem = switch (state.kind) {
      RemotePullKind.fastForward => RefMenuAction(
        key: const Key('remote-pull-pull'),
        title: 'Pull — ${state.ahead}개 커밋',
        subtitle: state.checkedOut
            ? '현재 브랜치를 fast-forward'
            : '체크아웃 전환 없이 로컬만 전진',
        onPressed: onPull,
      ),
      RemotePullKind.diverged => const RefMenuAction(
        key: Key('remote-pull-pull'),
        title: 'Pull',
        subtitle: 'fast-forward 불가',
      ),
      RemotePullKind.upToDate => const RefMenuAction(
        key: Key('remote-pull-pull'),
        title: 'Pull',
        subtitle: '받을 커밋 없음',
      ),
      RemotePullKind.noLocal => null,
    };

    final checkoutItem = state.checkedOut
        ? null
        : RefMenuAction(
            key: const Key('remote-pull-checkout'),
            title: '체크아웃',
            subtitle: switch (state.kind) {
              RemotePullKind.noLocal => '추적 브랜치 ${state.localBranch} 생성',
              RemotePullKind.fastForward => '${state.localBranch}으로 전환 후 pull',
              _ => '${state.localBranch}으로 전환',
            },
            onPressed: onCheckout,
          );

    final compareItem = RefMenuAction(
      key: const Key('remote-pull-compare'),
      title: '브랜치 diff로 비교',
      subtitle: state.kind == RemotePullKind.diverged
          ? 'merge / rebase는 미리보기에서 결정'
          : null,
      onPressed: onCompare,
    );

    // The default action comes first — [RefRowMenu] takes the first action the
    // ref can actually run as its default — and the rest keep a stable order
    // below it.
    final defaultAction = remotePullDefaultAction(state);
    final ordered = [
      (RemotePullAction.pull, pullItem),
      (RemotePullAction.checkout, checkoutItem),
      (RemotePullAction.compare, compareItem),
    ];

    return RefRowMenu(
      name: remoteBranch,
      headerKey: const Key('remote-pull-header'),
      status: _headerStatus(palette),
      controller: controller,
      actions: [
        for (final entry in ordered)
          if (entry.$2 case final action?)
            if (entry.$1 == defaultAction) action,
        for (final entry in ordered)
          if (entry.$2 case final action?)
            if (entry.$1 != defaultAction) action,
        // Last, past the separator, and never the default — the deletion
        // reaches the remote itself.
        RefMenuAction(
          key: const Key('remote-pull-delete'),
          title: '원격 브랜치 삭제',
          subtitle: '${state.remote}에서 지웁니다',
          danger: true,
          onPressed: onDelete,
        ),
      ],
    );
  }

  Widget _headerStatus(TimelineThemePalette palette) {
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
