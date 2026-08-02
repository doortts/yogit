import 'package:flutter/material.dart';

import 'git.dart';
import 'settings.dart';
import 'timeline_theme.dart';

/// What the status bar chip is showing: a registered profile, an identity set
/// outside the app, or nothing at all.
enum CommitIdentityKind { profile, custom, missing }

/// The repository's current commit identity, matched against the registered
/// profiles. The repository config is the source of truth; the profile list
/// only names what it finds.
class CommitIdentityState {
  const CommitIdentityState({required this.identity, required this.profile});

  const CommitIdentityState.unknown()
    : identity = const GitIdentity(name: '', email: ''),
      profile = null;

  final GitIdentity identity;

  /// The registered profile this identity belongs to, if any.
  final CommitProfile? profile;

  CommitIdentityKind get kind => profile != null
      ? CommitIdentityKind.profile
      : identity.email.trim().isEmpty && identity.name.trim().isEmpty
      ? CommitIdentityKind.missing
      : CommitIdentityKind.custom;

  /// The chip's headline: the profile's label, or the raw name Git reports.
  String get label => switch (kind) {
    CommitIdentityKind.profile =>
      profile!.label.trim().isEmpty ? profile!.name : profile!.label,
    CommitIdentityKind.custom => '커스텀',
    CommitIdentityKind.missing => '신원 미설정',
  };
}

CommitIdentityState resolveCommitIdentity(
  GitIdentity identity,
  List<CommitProfile> profiles,
) => CommitIdentityState(
  identity: identity,
  profile: profiles.where((profile) => profile.matches(identity)).firstOrNull,
);

/// The round initials badge shared by the chip, the menu, and the settings
/// list, so one profile reads the same everywhere.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.text,
    required this.color,
    required this.size,
    this.foreground = Colors.white,
    super.key,
  });

  /// The avatar for [state]: the profile's color, or a muted circle for an
  /// identity the profile list does not know.
  factory ProfileAvatar.forIdentity(
    CommitIdentityState state, {
    required double size,
    required TimelineThemePalette palette,
    Color? warningColor,
  }) => switch (state.kind) {
    CommitIdentityKind.profile => ProfileAvatar(
      text: state.profile!.initials,
      color: state.profile!.colorValue,
      size: size,
    ),
    // A gray circle rather than a profile color: this identity has no profile
    // behind it, and the '?' has to stay legible on the chip's own fill.
    CommitIdentityKind.custom => ProfileAvatar(
      text: '?',
      color: palette.muted,
      size: size,
      foreground: palette.background,
    ),
    CommitIdentityKind.missing => ProfileAvatar(
      text: '!',
      color: palette.raised,
      size: size,
      foreground: warningColor ?? palette.text,
    ),
  };

  final String text;
  final Color color;
  final double size;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        color: foreground,
        // The mockup's 15px avatar carries 7.5px initials; every other size
        // keeps that ratio.
        fontSize: size * 0.5,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

/// The profile menu the chip opens: the identity in force, then everything the
/// user can switch to. Opens upward — the chip lives on the bottom edge.
class CommitProfileMenu extends StatelessWidget {
  const CommitProfileMenu({
    required this.repositoryName,
    required this.state,
    required this.profiles,
    required this.onSelected,
    required this.onRegisterCurrent,
    required this.onManage,
    super.key,
  });

  static const width = 268.0;

  final String repositoryName;
  final CommitIdentityState state;
  final List<CommitProfile> profiles;
  final ValueChanged<CommitProfile> onSelected;

  /// Promotes an identity set outside the app into a saved profile.
  final VoidCallback onRegisterCurrent;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final custom = state.kind != CommitIdentityKind.profile;
    return Material(
      color: palette.raised,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 6),
              child: Text(
                '이 저장소($repositoryName)의 커밋 신원 — .git/config에 저장',
                style: TextStyle(color: palette.muted, fontSize: 10.5),
              ),
            ),
            // An identity the app did not set leads the list, read-only, so a
            // CLI or includeIf setup is named rather than silently replaced.
            if (custom) ...[
              _row(
                context,
                key: const Key('commit-profile-current-custom'),
                avatar: ProfileAvatar.forIdentity(
                  state,
                  size: 22,
                  palette: palette,
                ),
                title: state.kind == CommitIdentityKind.missing
                    ? '신원 미설정'
                    : '커스텀 (앱 밖에서 설정됨)',
                subtitle: state.kind == CommitIdentityKind.missing
                    ? '아래에서 프로필을 고르세요'
                    : '${state.identity.name} <${state.identity.email}>',
                selected: true,
              ),
              if (state.kind == CommitIdentityKind.custom)
                _plainRow(
                  context,
                  key: const Key('commit-profile-register'),
                  label: '이 신원을 프로필로 등록…',
                  onTap: onRegisterCurrent,
                  indent: 40,
                ),
              _separator(palette),
            ],
            for (final profile in profiles)
              _row(
                context,
                key: Key('commit-profile-option-${profile.email}'),
                avatar: ProfileAvatar(
                  text: profile.initials,
                  color: profile.colorValue,
                  size: 22,
                ),
                title: profile.label.trim().isEmpty
                    ? profile.name
                    : profile.label,
                subtitle: '${profile.name} <${profile.email}>',
                selected: state.profile == profile,
                onTap: () => onSelected(profile),
              ),
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 4, 9, 6),
                child: Text(
                  '등록된 프로필이 없습니다',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ),
            _separator(palette),
            _plainRow(
              context,
              key: const Key('commit-profile-manage'),
              label: '프로필 관리…',
              onTap: onManage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _separator(TimelineThemePalette palette) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    child: Divider(height: 1, thickness: 1, color: palette.border),
  );

  Widget _row(
    BuildContext context, {
    required Key key,
    required Widget avatar,
    required String title,
    required String subtitle,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final palette = TimelineThemePalette.of(context);
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? palette.selectedRow : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : palette.text,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.78)
                          : palette.muted,
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.check, size: 14, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _plainRow(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onTap,
    double indent = 0,
  }) {
    final palette = TimelineThemePalette.of(context);
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(9 + indent, 6, 9, 6),
        child: Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: indent > 0 ? 11.5 : 12,
          ),
        ),
      ),
    );
  }
}

/// The status bar's commit-identity chip: quiet until hovered, and the anchor
/// for the profile menu. [showEmail] drops the address on a narrow window.
class CommitProfileChip extends StatefulWidget {
  const CommitProfileChip({
    required this.state,
    required this.showEmail,
    required this.onPressed,
    this.maxWidth = double.infinity,
    this.warningColor = const Color(0xFFE5B567),
    super.key,
  });

  final CommitIdentityState state;
  final bool showEmail;
  final VoidCallback onPressed;

  /// The chip never eats more than this much of the status bar; the name and
  /// address ellipsize inside it.
  final double maxWidth;
  final Color warningColor;

  @override
  State<CommitProfileChip> createState() => _CommitProfileChipState();
}

class _CommitProfileChipState extends State<CommitProfileChip> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = TimelineThemePalette.of(context);
    final state = widget.state;
    final missing = state.kind == CommitIdentityKind.missing;
    final email = state.identity.email.trim();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: const Key('commit-profile-chip'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Tooltip(
          message: missing
              ? '커밋 신원이 설정되지 않았습니다'
              : '${state.identity.name} <${state.identity.email}>',
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            height: 21,
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            padding: const EdgeInsets.only(left: 3, right: 8),
            // The pill is always drawn so the identity reads as one tappable
            // chip rather than as loose status-bar text; hover only lifts it.
            decoration: BoxDecoration(
              color: _hovered ? palette.border : palette.raised,
              border: Border.all(
                color: _hovered ? palette.muted : palette.border,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar.forIdentity(
                      state,
                      size: 15,
                      palette: palette,
                      warningColor: widget.warningColor,
                    ),
                    // The dot rides the avatar's shoulder so a mismatched
                    // identity is visible without reading the text.
                    if (state.kind != CommitIdentityKind.profile)
                      Positioned(
                        top: -1,
                        right: -2,
                        child: Container(
                          key: const Key('commit-profile-warning'),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: widget.warningColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    state.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: missing ? widget.warningColor : palette.text,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (widget.showEmail && email.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
