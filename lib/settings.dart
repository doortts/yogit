import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'commit_profile_chip.dart' show ProfileAvatar;
import 'full_diff_model.dart';
import 'git.dart';
import 'github_api.dart';
import 'github_auth.dart';
import 'github_oauth.dart';
import 'timeline_theme.dart';
import 'window_frame.dart';
import 'yogit_alert.dart';
import 'typography.dart';

enum BranchPreviewMode {
  merge,
  rebase;

  static BranchPreviewMode parse(Object? value) =>
      value == 'rebase' ? rebase : merge;
}

typedef RefPaletteEntry = ({String base, String text});
typedef RefPaletteColors = ({Color base, Color text});

class TimelineColumnWidths {
  const TimelineColumnWidths({
    this.sidebar = 150,
    this.refs = 156,
    this.graph,
    this.hash = 78,
    this.commit,
    this.time = 116,
    this.name = 150,
    this.showTime = true,
    this.showName = true,
  });

  final double sidebar;
  final double refs;

  /// Null until the user drags the graph column: the timeline then fits it to
  /// the deepest loaded lane instead of pinning it.
  final double? graph;
  final double hash;

  /// Kept so a settings file written before the title column stopped storing a
  /// width still parses. The title column absorbs whatever the other five leave
  /// and its divider moves by resizing Date and Author, so nothing reads this
  /// and nothing writes it any more.
  final double? commit;
  final double time;
  final double name;
  final bool showTime;
  final bool showName;

  /// [graph] only widens: pass a value to pin the column, and use
  /// `TimelineColumnWidths(...)` directly to clear it back to auto.
  TimelineColumnWidths copyWith({
    double? sidebar,
    double? refs,
    double? graph,
    double? hash,
    double? commit,
    double? time,
    double? name,
    bool? showTime,
    bool? showName,
  }) => TimelineColumnWidths(
    sidebar: sidebar ?? this.sidebar,
    refs: refs ?? this.refs,
    graph: graph ?? this.graph,
    hash: hash ?? this.hash,
    commit: commit ?? this.commit,
    time: time ?? this.time,
    name: name ?? this.name,
    showTime: showTime ?? this.showTime,
    showName: showName ?? this.showName,
  );

  TimelineColumnWidths withGraph(double? value) => TimelineColumnWidths(
    sidebar: sidebar,
    refs: refs,
    graph: value,
    hash: hash,
    commit: commit,
    time: time,
    name: name,
    showTime: showTime,
    showName: showName,
  );

  factory TimelineColumnWidths.fromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    double width(String key, double fallback, double min, double max) =>
        (json[key] is num ? (json[key] as num).toDouble() : fallback).clamp(
          min,
          max,
        );
    return TimelineColumnWidths(
      sidebar: width('sidebar', 150, 150, 320),
      refs: width('refs', 156, 110, 240),
      graph: json['graph'] is num ? width('graph', 142, 40, 260) : null,
      hash: width('hash', 78, 64, 120),
      commit: json['commit'] is num ? width('commit', 380, 100, 620) : null,
      time: width('time', 116, 56, 170),
      name: width('name', 150, 50, 240),
      showTime: json['showTime'] is bool ? json['showTime'] as bool : true,
      showName: json['showName'] is bool ? json['showName'] as bool : true,
    );
  }

  Map<String, Object> toJson() => {
    'sidebar': sidebar,
    'refs': refs,
    'graph': ?graph,
    'hash': hash,
    'commit': ?commit,
    'time': time,
    'name': name,
    'showTime': showTime,
    'showName': showName,
  };

  @override
  bool operator ==(Object other) =>
      other is TimelineColumnWidths &&
      sidebar == other.sidebar &&
      refs == other.refs &&
      graph == other.graph &&
      hash == other.hash &&
      commit == other.commit &&
      time == other.time &&
      name == other.name &&
      showTime == other.showTime &&
      showName == other.showName;

  @override
  int get hashCode => Object.hash(
    sidebar,
    refs,
    graph,
    hash,
    commit,
    time,
    name,
    showTime,
    showName,
  );
}

/// The two widths the diff still keeps: its History pane, and the split
/// between the two sides. The file column left with the file pane.
class FullDiffColumnWidths {
  const FullDiffColumnWidths({this.history = 280, this.sideBySideRatio = 0.5});

  static const minHistory = 180.0;
  static const maxHistory = 420.0;
  static const minSideBySideRatio = 0.2;
  static const maxSideBySideRatio = 0.8;

  final double history;
  final double sideBySideRatio;

  factory FullDiffColumnWidths.fromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    double width(String key, double fallback, double min, double max) =>
        (json[key] is num ? (json[key] as num).toDouble() : fallback).clamp(
          min,
          max,
        );
    return FullDiffColumnWidths(
      history: width(
        json.containsKey('history') ? 'history' : 'commits',
        280,
        minHistory,
        maxHistory,
      ),
      sideBySideRatio: width(
        'sideBySideRatio',
        0.5,
        minSideBySideRatio,
        maxSideBySideRatio,
      ),
    );
  }

  Map<String, Object> toJson() => {
    'history': history,
    'sideBySideRatio': sideBySideRatio,
  };

  @override
  bool operator ==(Object other) =>
      other is FullDiffColumnWidths &&
      history == other.history &&
      sideBySideRatio == other.sideBySideRatio;

  @override
  int get hashCode => Object.hash(history, sideBySideRatio);
}

/// `#RRGGBB` (or bare `RRGGBB`) to a color, or null when malformed.
Color? parseHexColor(String value) {
  final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
  return match == null
      ? null
      : Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

double _clamped(Object? value, double fallback, double min, double max) =>
    (value is num ? value.toDouble() : fallback).clamp(min, max);

double? _optionalExtent(Object? value) {
  if (value is! num || !value.toDouble().isFinite) return null;
  return value.toDouble().clamp(0, double.infinity).toDouble();
}

String formatHexColor(String value) =>
    '#${value.trim().replaceFirst('#', '').toUpperCase()}';

Map<String, double> _parseRepositoryGraphWidths(Object? value) {
  if (value is! Map) return const {};
  final result = <String, double>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! num) continue;
    final root = (entry.key as String).trim();
    if (root.isEmpty) continue;
    result[root] = (entry.value as num)
        .toDouble()
        .clamp(40.0, 260.0)
        .toDouble();
  }
  return result;
}

Map<String, Map<String, String>> _parseNestedStringMap(Object? value) => {
  if (value is Map)
    for (final repository in value.entries)
      if (repository.key is String && repository.value is Map)
        repository.key as String: {
          for (final entry in (repository.value as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        },
};

bool _nestedStringMapEquals(
  Map<String, Map<String, String>> left,
  Map<String, Map<String, String>> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!mapEquals(entry.value, right[entry.key])) return false;
  }
  return true;
}

Map<String, List<String>> _parseHiddenRefs(Object? value) => {
  if (value is Map)
    for (final repository in value.entries)
      if (repository.key is String && repository.value is List)
        repository.key as String: [
          for (final ref in repository.value as List)
            if (ref is String) ref,
        ],
};

bool _hiddenRefsEqual(
  Map<String, List<String>> left,
  Map<String, List<String>> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!listEquals(entry.value, right[entry.key])) return false;
  }
  return true;
}

/// A commit identity the status bar can switch a repository to: the name and
/// email Git will sign commits with, under a label the user recognizes.
class CommitProfile {
  const CommitProfile({
    required this.label,
    required this.name,
    required this.email,
    this.color = defaultColor,
  });

  static const defaultColor = '#7C5CD6';

  /// The palette new profiles cycle through, so two identities never look
  /// alike in the chip without the user picking colors by hand.
  static const paletteColors = [
    '#7C5CD6',
    '#2EA043',
    '#D98032',
    '#3B82C4',
    '#C2528B',
  ];

  final String label;
  final String name;
  final String email;
  final String color;

  Color get colorValue => parseHexColor(color) ?? const Color(0xFF7C5CD6);

  /// `채수원` reads as `채`, `Suwon Chae` as `SC`: at most two glyphs for the
  /// avatar circle. Taken from the committer name, so the circle identifies
  /// the person rather than repeating the label beside it.
  String get initials {
    final source = name.trim().isEmpty ? label.trim() : name.trim();
    if (source.isEmpty) return '?';
    final words = source.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length >= 2) {
      return '${words.first.characters.first}'
              '${words.elementAt(1).characters.first}'
          .toUpperCase();
    }
    final characters = source.characters;
    // Latin initials read better doubled up; CJK is dense enough at one.
    return characters.first.codeUnitAt(0) < 0x80
        ? characters.take(2).toString().toUpperCase()
        : characters.first;
  }

  bool matches(GitIdentity identity) =>
      identity.name == name && identity.email == email;

  CommitProfile copyWith({
    String? label,
    String? name,
    String? email,
    String? color,
  }) => CommitProfile(
    label: label ?? this.label,
    name: name ?? this.name,
    email: email ?? this.email,
    color: color ?? this.color,
  );

  factory CommitProfile.fromJson(Object? value) {
    final map = value is Map ? value : const {};
    final color = formatHexColor('${map['color'] ?? ''}');
    return CommitProfile(
      label: '${map['label'] ?? ''}',
      name: '${map['name'] ?? ''}',
      email: '${map['email'] ?? ''}',
      color: parseHexColor(color) == null ? defaultColor : color,
    );
  }

  Map<String, Object> toJson() => {
    'label': label,
    'name': name,
    'email': email,
    'color': color,
  };

  @override
  bool operator ==(Object other) =>
      other is CommitProfile &&
      label == other.label &&
      name == other.name &&
      email == other.email &&
      color == other.color;

  @override
  int get hashCode => Object.hash(label, name, email, color);
}

/// What the timeline's text columns are set in. The system face at 13px is the
/// approved default; Geist and Open Sans ship with the app for the people who
/// picked their look from gitru and GitKraken. Each family carries the size it
/// reads best at, which is where the user's own size starts from.
enum TimelineFontChoice {
  system(fontFamily: null, defaultFontSize: 13),
  geist(fontFamily: 'Geist', defaultFontSize: 14),
  openSans(fontFamily: 'OpenSans', defaultFontSize: 12);

  const TimelineFontChoice({
    required this.fontFamily,
    required this.defaultFontSize,
  });

  /// Null keeps the platform face.
  final String? fontFamily;
  final double defaultFontSize;

  static TimelineFontChoice parse(Object? value) => values.firstWhere(
    (choice) => choice.name == value,
    orElse: () => TimelineFontChoice.system,
  );
}

class AppSettings {
  const AppSettings({
    this.showAvatars = true,
    this.precisePush = false,
    this.timelineTheme = TimelineThemeKind.systemGraphite,
    this.previewPlacement = PreviewPlacement.right,
    this.branchPreviewMode = BranchPreviewMode.merge,
    this.columnWidths = const TimelineColumnWidths(),
    this.repositoryGraphWidths = const {},
    this.fullDiffColumnWidths = const FullDiffColumnWidths(),
    this.fullDiffPreferences = const FullDiffPreferences(),
    this.baseBranchColor = defaultBaseBranchColor,
    this.laneColors = defaultLaneColors,
    this.refPalette = defaultRefPalette,
    this.refPaletteAssignments = defaultRefPaletteAssignments,
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.previewDiffLeftWidth,
    this.previewDiffRightWidth,
    this.previewDiffBottomHeight,
    this.baseBranches = const {},
    this.deletedBranchNames = const {},
    this.hiddenRefs = const {},
    this.recentRepositories = const [],
    this.timelineFont = TimelineFontChoice.system,
    this.timelineFontSize,
    this.commitProfiles = const [],
    this.mergeMessageTemplate = defaultMergeMessageTemplate,
    this.rebaseMergeMessageTemplate = defaultMergeMessageTemplate,
    this.githubApiBaseUrl = defaultGithubApiBaseUrl,
    this.customGithubApiBaseUrls = const [],
  });

  /// How many repositories the picker remembers before the oldest drops off.
  static const maxRecentRepositories = 10;

  /// The range the timeline font size control offers. Below the floor the
  /// supporting columns stop being readable, above the ceiling a row no longer
  /// fits the 30px it is given.
  static const minTimelineFontSize = 10.0;
  static const maxTimelineFontSize = 18.0;

  /// What git itself writes for a merge, and the floor an emptied template
  /// falls back to.
  static const standardMergeMessage = "Merge branch '{source}' into {target}";

  /// The message an apply that creates a merge commit starts from.
  static const defaultMergeMessageTemplate =
      '$standardMergeMessage\n\nReviewed-by: {profile}';

  /// The selected base branch color, as stored.
  static const defaultBaseBranchColor = '#5CB270';

  /// The neon palette, as stored.
  static const defaultLaneColors = [
    '#FF2D95',
    '#00E5FF',
    '#39FF14',
    '#FFF01F',
    '#FF6E27',
    '#B026FF',
    '#04D9FF',
    '#FF3131',
  ];

  static const refPaletteNumbers = [1, 3, 4, 5, 6, 7, 8, 9];
  static const defaultRefPalette = <RefPaletteEntry>[
    (base: '#0E8A16', text: '#18E022'),
    (base: '#C5DEF5', text: '#C2DDF4'),
    (base: '#1D76DB', text: '#68A7EA'),
    (base: '#5319E7', text: '#DACFFA'),
    (base: '#B51D68', text: '#FF2D95'),
    (base: '#008FA3', text: '#00E5FF'),
    (base: '#B89B00', text: '#FFF01F'),
    (base: '#C94E10', text: '#FF6E27'),
  ];
  static const defaultRefPaletteAssignments = [1, 0, 0, 0, 0, 0, 0, 0];

  /// The palette that used to be the default. A settings file still carrying it
  /// unchanged never chose it, so it migrates to [defaultLaneColors]; an edited
  /// palette is kept as it is.
  static const _replacedLaneColors = [
    '#F85149',
    '#DB6D28',
    '#D29922',
    '#3FB950',
    '#39C5CF',
    '#58A6FF',
    '#BC8CFF',
    '#F778BA',
  ];

  final bool showAvatars;

  /// Push the exact tip the confirmation showed (`<sha>:refs/heads/main`)
  /// instead of the branch name (`main`). Off by default: the plain form is
  /// what a person types, and the difference only shows when a commit lands
  /// while the dialog is open.
  final bool precisePush;
  final TimelineThemeKind timelineTheme;
  final PreviewPlacement previewPlacement;
  final BranchPreviewMode branchPreviewMode;
  final TimelineColumnWidths columnWidths;
  final Map<String, double> repositoryGraphWidths;
  final FullDiffColumnWidths fullDiffColumnWidths;
  final FullDiffPreferences fullDiffPreferences;
  final String baseBranchColor;
  final List<String> laneColors;
  final List<RefPaletteEntry> refPalette;
  final List<int> refPaletteAssignments;
  final Map<String, String> baseBranches;
  final Map<String, Map<String, String>> deletedBranchNames;

  /// Repository root → the refs the graph leaves out of its starting points.
  final Map<String, List<String>> hiddenRefs;

  /// Repository roots, most recently opened first.
  final List<String> recentRepositories;

  /// The face every text column in the timeline is set in.
  final TimelineFontChoice timelineFont;

  /// The size the commit message column is set in, which the supporting columns
  /// size themselves against. Null means [TimelineFontChoice.defaultFontSize].
  final double? timelineFontSize;

  /// The commit identities the status bar offers, in display order.
  final List<CommitProfile> commitProfiles;

  /// What the commit message box is prefilled with when an apply creates a
  /// merge commit. Empty means git's own [standardMergeMessage] alone.
  final String mergeMessageTemplate;
  final String rebaseMergeMessageTemplate;

  /// The GitHub server the monitor and the avatars talk to. Its token lives in
  /// the Keychain, never here.
  final String githubApiBaseUrl;

  /// Servers the user typed in, offered alongside [defaultGithubApiBaseUrls].
  final List<String> customGithubApiBaseUrls;

  /// The detail panel's size, per placement axis.
  final double previewWidth;
  final double previewHeight;
  final double? previewDiffLeftWidth;
  final double? previewDiffRightWidth;
  final double? previewDiffBottomHeight;

  /// The palette to hand [AvatarService]; a damaged entry drops the whole list
  /// back to the default rather than painting one rail wrong.
  List<Color> get laneColorValues {
    final colors = [for (final value in laneColors) parseHexColor(value)];
    return colors.isEmpty || colors.contains(null)
        ? AvatarService.defaultColors
        : colors.cast<Color>();
  }

  List<RefPaletteColors> get refPaletteColorValues {
    final values = [
      for (final entry in refPalette)
        (base: parseHexColor(entry.base), text: parseHexColor(entry.text)),
    ];
    if (values.length != defaultRefPalette.length ||
        values.any((entry) => entry.base == null || entry.text == null)) {
      return const AppSettings().refPaletteColorValues;
    }
    return [for (final entry in values) (base: entry.base!, text: entry.text!)];
  }

  Color get baseBranchColorValue =>
      parseHexColor(baseBranchColor) ?? AvatarService.defaultBaseBranchColor;

  TimelineColumnWidths columnWidthsForRepository(String root) =>
      columnWidths.withGraph(repositoryGraphWidths[root]);

  AppSettings withRepositoryColumnWidths(
    String root,
    TimelineColumnWidths widths,
  ) {
    final graphWidths = {...repositoryGraphWidths};
    final graph = widths.graph;
    if (root.trim().isNotEmpty && graph != null) {
      graphWidths[root] = graph.clamp(40.0, 260.0).toDouble();
    }
    return copyWith(
      columnWidths: widths.withGraph(null),
      repositoryGraphWidths: graphWidths,
    );
  }

  /// Moves [root] to the head of the recent list, dropping the oldest entry
  /// once the list is longer than [maxRecentRepositories].
  AppSettings withRecentRepository(String root) {
    if (root.trim().isEmpty) return this;
    final recent = [
      root,
      ...recentRepositories.where((entry) => entry != root),
    ];
    if (recent.length > maxRecentRepositories) {
      recent.removeRange(maxRecentRepositories, recent.length);
    }
    return listEquals(recent, recentRepositories)
        ? this
        : copyWith(recentRepositories: recent);
  }

  AppSettings withoutRecentRepository(String root) => copyWith(
    recentRepositories: [
      for (final entry in recentRepositories)
        if (entry != root) entry,
    ],
  );

  AppSettings migrateLegacyGraphWidth(String root) {
    final legacy = columnWidths.graph;
    if (legacy == null) return this;
    final graphWidths = {...repositoryGraphWidths};
    if (graphWidths.isEmpty && root.trim().isNotEmpty) {
      graphWidths[root] = legacy;
    }
    return copyWith(
      columnWidths: columnWidths.withGraph(null),
      repositoryGraphWidths: graphWidths,
    );
  }

  AppSettings copyWith({
    bool? showAvatars,
    bool? precisePush,
    TimelineThemeKind? timelineTheme,
    PreviewPlacement? previewPlacement,
    BranchPreviewMode? branchPreviewMode,
    TimelineColumnWidths? columnWidths,
    Map<String, double>? repositoryGraphWidths,
    FullDiffColumnWidths? fullDiffColumnWidths,
    FullDiffPreferences? fullDiffPreferences,
    String? baseBranchColor,
    List<String>? laneColors,
    List<RefPaletteEntry>? refPalette,
    List<int>? refPaletteAssignments,
    double? previewWidth,
    double? previewHeight,
    double? previewDiffLeftWidth,
    double? previewDiffRightWidth,
    double? previewDiffBottomHeight,
    Map<String, String>? baseBranches,
    Map<String, Map<String, String>>? deletedBranchNames,
    Map<String, List<String>>? hiddenRefs,
    List<String>? recentRepositories,
    TimelineFontChoice? timelineFont,
    double? timelineFontSize,
    bool clearTimelineFontSize = false,
    List<CommitProfile>? commitProfiles,
    String? mergeMessageTemplate,
    String? rebaseMergeMessageTemplate,
    String? githubApiBaseUrl,
    List<String>? customGithubApiBaseUrls,
  }) => AppSettings(
    showAvatars: showAvatars ?? this.showAvatars,
    precisePush: precisePush ?? this.precisePush,
    timelineTheme: timelineTheme ?? this.timelineTheme,
    previewPlacement: previewPlacement ?? this.previewPlacement,
    branchPreviewMode: branchPreviewMode ?? this.branchPreviewMode,
    columnWidths: columnWidths ?? this.columnWidths,
    repositoryGraphWidths: repositoryGraphWidths ?? this.repositoryGraphWidths,
    fullDiffColumnWidths: fullDiffColumnWidths ?? this.fullDiffColumnWidths,
    fullDiffPreferences: fullDiffPreferences ?? this.fullDiffPreferences,
    baseBranchColor: baseBranchColor ?? this.baseBranchColor,
    laneColors: laneColors ?? this.laneColors,
    refPalette: refPalette ?? this.refPalette,
    refPaletteAssignments: refPaletteAssignments ?? this.refPaletteAssignments,
    previewWidth: previewWidth ?? this.previewWidth,
    previewHeight: previewHeight ?? this.previewHeight,
    previewDiffLeftWidth: previewDiffLeftWidth ?? this.previewDiffLeftWidth,
    previewDiffRightWidth: previewDiffRightWidth ?? this.previewDiffRightWidth,
    previewDiffBottomHeight:
        previewDiffBottomHeight ?? this.previewDiffBottomHeight,
    baseBranches: baseBranches ?? this.baseBranches,
    deletedBranchNames: deletedBranchNames ?? this.deletedBranchNames,
    hiddenRefs: hiddenRefs ?? this.hiddenRefs,
    recentRepositories: recentRepositories ?? this.recentRepositories,
    timelineFont: timelineFont ?? this.timelineFont,
    // `??` cannot say "back to the family default", so the flag says it.
    timelineFontSize: clearTimelineFontSize
        ? null
        : timelineFontSize ?? this.timelineFontSize,
    commitProfiles: commitProfiles ?? this.commitProfiles,
    mergeMessageTemplate: mergeMessageTemplate ?? this.mergeMessageTemplate,
    rebaseMergeMessageTemplate:
        rebaseMergeMessageTemplate ?? this.rebaseMergeMessageTemplate,
    githubApiBaseUrl: githubApiBaseUrl ?? this.githubApiBaseUrl,
    customGithubApiBaseUrls:
        customGithubApiBaseUrls ?? this.customGithubApiBaseUrls,
  );

  factory AppSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const AppSettings();
    final storedBaseBranches = value['baseBranches'];
    final storedBaseBranchColor = '${value['baseBranchColor'] ?? ''}';
    final baseBranches = <String, String>{
      if (storedBaseBranches is Map)
        for (final entry in storedBaseBranches.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };
    final entries = value['laneColors'];
    final laneColors = [
      if (entries is List)
        for (final entry in entries) formatHexColor('$entry'),
    ];
    final valid =
        laneColors.isNotEmpty &&
        laneColors.every((entry) => parseHexColor(entry) != null) &&
        !listEquals(laneColors, _replacedLaneColors);
    final storedRefPalette = value['refPalette'];
    final refPalette = <RefPaletteEntry>[
      if (storedRefPalette is List)
        for (final entry in storedRefPalette)
          if (entry is Map)
            (
              base: formatHexColor('${entry['base'] ?? ''}'),
              text: formatHexColor('${entry['text'] ?? ''}'),
            ),
    ];
    final validRefPaletteEntries = refPalette.every(
      (entry) =>
          parseHexColor(entry.base) != null &&
          parseHexColor(entry.text) != null,
    );
    final validRefPalette =
        storedRefPalette is List &&
        storedRefPalette.length == defaultRefPalette.length &&
        storedRefPalette.every((entry) => entry is Map) &&
        validRefPaletteEntries;
    final migratedRefPalette =
        storedRefPalette is List &&
            storedRefPalette.length == 5 &&
            storedRefPalette.every((entry) => entry is Map) &&
            validRefPaletteEntries
        ? [
            refPalette[3],
            refPalette[2],
            refPalette[0],
            refPalette[4],
            ...defaultRefPalette.skip(4),
          ]
        : defaultRefPalette;
    final storedRefPaletteAssignments = value['refPaletteAssignments'];
    final refPaletteAssignments = [
      if (storedRefPaletteAssignments is List)
        for (final entry in storedRefPaletteAssignments)
          if (entry is int) entry,
    ];
    final pinnedAssignments = refPaletteAssignments
        .skip(1)
        .where((assignment) => assignment != 0)
        .toList();
    final validRefPaletteAssignments =
        validRefPalette &&
        storedRefPaletteAssignments is List &&
        storedRefPaletteAssignments.length == defaultRefPalette.length &&
        storedRefPaletteAssignments.every((entry) => entry is int) &&
        refPaletteAssignments.length == defaultRefPalette.length &&
        refPaletteAssignments.first == 1 &&
        refPaletteAssignments
            .skip(1)
            .every(
              (assignment) =>
                  assignment == 0 || assignment >= 2 && assignment <= 9,
            ) &&
        pinnedAssignments.toSet().length == pinnedAssignments.length;
    return AppSettings(
      showAvatars: value['showAvatars'] is bool
          ? value['showAvatars'] as bool
          : true,
      precisePush: value['precisePush'] == true,
      timelineTheme: TimelineThemeKind.parse(value['timelineTheme']),
      previewPlacement: switch (value['previewPlacement']) {
        'bottom' => PreviewPlacement.bottom,
        'left' => PreviewPlacement.left,
        _ => PreviewPlacement.right,
      },
      branchPreviewMode: BranchPreviewMode.parse(value['branchPreviewMode']),
      columnWidths: TimelineColumnWidths.fromJson(value['columnWidths']),
      repositoryGraphWidths: _parseRepositoryGraphWidths(
        value['repositoryGraphWidths'],
      ),
      fullDiffColumnWidths: FullDiffColumnWidths.fromJson(
        value['fullDiffColumnWidths'],
      ),
      fullDiffPreferences: FullDiffPreferences.fromJson(
        value['fullDiffPreferences'],
      ),
      baseBranchColor: parseHexColor(storedBaseBranchColor) == null
          ? defaultBaseBranchColor
          : formatHexColor(storedBaseBranchColor),
      laneColors: valid ? laneColors : defaultLaneColors,
      refPalette: validRefPaletteAssignments ? refPalette : migratedRefPalette,
      refPaletteAssignments: validRefPaletteAssignments
          ? refPaletteAssignments
          : defaultRefPaletteAssignments,
      previewWidth: _clamped(value['previewWidth'], 288, 240, double.infinity),
      previewHeight: _clamped(
        value['previewHeight'],
        280,
        200,
        double.maxFinite,
      ),
      previewDiffLeftWidth: _optionalExtent(value['previewDiffLeftWidth']),
      previewDiffRightWidth: _optionalExtent(value['previewDiffRightWidth']),
      previewDiffBottomHeight: _optionalExtent(
        value['previewDiffBottomHeight'],
      ),
      baseBranches: baseBranches,
      deletedBranchNames: _parseNestedStringMap(value['deletedBranchNames']),
      hiddenRefs: _parseHiddenRefs(value['hiddenRefs']),
      recentRepositories: _parseRecentRepositories(value['recentRepositories']),
      timelineFont: TimelineFontChoice.parse(value['timelineFont']),
      timelineFontSize: _parseTimelineFontSize(value['timelineFontSize']),
      commitProfiles: _parseCommitProfiles(value['commitProfiles']),
      // An empty string is a choice — git's own message — so only a missing or
      // non-string entry falls back to the default template.
      mergeMessageTemplate: value['mergeMessageTemplate'] is String
          ? value['mergeMessageTemplate'] as String
          : defaultMergeMessageTemplate,
      rebaseMergeMessageTemplate: value['rebaseMergeMessageTemplate'] is String
          ? value['rebaseMergeMessageTemplate'] as String
          : defaultMergeMessageTemplate,
      githubApiBaseUrl: _parseGithubApiBaseUrl(value['githubApiBaseUrl']),
      customGithubApiBaseUrls: _parseGithubApiBaseUrls(
        value['customGithubApiBaseUrls'],
      ),
    );
  }

  /// A size outside the control's own range, or one that is not a number at
  /// all, means the family default rather than a row the timeline cannot draw.
  static double? _parseTimelineFontSize(Object? value) =>
      value is num &&
          value >= minTimelineFontSize &&
          value <= maxTimelineFontSize
      ? value.toDouble()
      : null;

  /// A stored server is only honoured when it is still a usable https base
  /// URL — the app builds every request on top of it.
  static String _parseGithubApiBaseUrl(Object? value) {
    final urls = _parseGithubApiBaseUrls(value is String ? [value] : null);
    return urls.isEmpty ? defaultGithubApiBaseUrl : urls.first;
  }

  static List<String> _parseGithubApiBaseUrls(Object? value) => [
    if (value is List)
      for (final entry in value)
        if (entry is String)
          if (Uri.tryParse(entry.trim()) case final uri?)
            if (uri.isScheme('https') && uri.host.isNotEmpty) entry.trim(),
  ];

  /// A profile with no email could never be applied, so it is dropped rather
  /// than shown as an entry that silently does nothing.
  static List<CommitProfile> _parseCommitProfiles(Object? value) => [
    if (value is List)
      for (final entry in value)
        if (CommitProfile.fromJson(entry) case final profile)
          if (profile.email.trim().isNotEmpty) profile,
  ];

  static List<String> _parseRecentRepositories(Object? value) {
    if (value is! List) return const [];
    final seen = <String>{};
    for (final entry in value) {
      if (entry is! String || entry.trim().isEmpty) continue;
      seen.add(entry);
      if (seen.length == maxRecentRepositories) break;
    }
    return seen.toList();
  }

  Map<String, Object> toJson() => {
    'showAvatars': showAvatars,
    'precisePush': precisePush,
    'timelineTheme': timelineTheme.storageValue,
    'previewPlacement': previewPlacement.name,
    'branchPreviewMode': branchPreviewMode.name,
    'columnWidths': columnWidths.withGraph(null).toJson(),
    'repositoryGraphWidths': repositoryGraphWidths,
    'fullDiffColumnWidths': fullDiffColumnWidths.toJson(),
    'fullDiffPreferences': fullDiffPreferences.toJson(),
    'baseBranchColor': baseBranchColor,
    'laneColors': laneColors,
    'refPalette': [
      for (final entry in refPalette) {'base': entry.base, 'text': entry.text},
    ],
    'refPaletteAssignments': refPaletteAssignments,
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
    'previewDiffLeftWidth': ?previewDiffLeftWidth,
    'previewDiffRightWidth': ?previewDiffRightWidth,
    'previewDiffBottomHeight': ?previewDiffBottomHeight,
    'baseBranches': baseBranches,
    'deletedBranchNames': deletedBranchNames,
    'hiddenRefs': hiddenRefs,
    'recentRepositories': recentRepositories,
    'timelineFont': timelineFont.name,
    'timelineFontSize': ?timelineFontSize,
    'commitProfiles': [for (final profile in commitProfiles) profile.toJson()],
    'mergeMessageTemplate': mergeMessageTemplate,
    'rebaseMergeMessageTemplate': rebaseMergeMessageTemplate,
    'githubApiBaseUrl': githubApiBaseUrl,
    'customGithubApiBaseUrls': customGithubApiBaseUrls,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      showAvatars == other.showAvatars &&
      precisePush == other.precisePush &&
      timelineTheme == other.timelineTheme &&
      previewPlacement == other.previewPlacement &&
      branchPreviewMode == other.branchPreviewMode &&
      columnWidths == other.columnWidths &&
      mapEquals(repositoryGraphWidths, other.repositoryGraphWidths) &&
      fullDiffColumnWidths == other.fullDiffColumnWidths &&
      fullDiffPreferences == other.fullDiffPreferences &&
      baseBranchColor == other.baseBranchColor &&
      listEquals(laneColors, other.laneColors) &&
      listEquals(refPalette, other.refPalette) &&
      listEquals(refPaletteAssignments, other.refPaletteAssignments) &&
      previewWidth == other.previewWidth &&
      previewHeight == other.previewHeight &&
      previewDiffLeftWidth == other.previewDiffLeftWidth &&
      previewDiffRightWidth == other.previewDiffRightWidth &&
      previewDiffBottomHeight == other.previewDiffBottomHeight &&
      mapEquals(baseBranches, other.baseBranches) &&
      _nestedStringMapEquals(deletedBranchNames, other.deletedBranchNames) &&
      _hiddenRefsEqual(hiddenRefs, other.hiddenRefs) &&
      listEquals(recentRepositories, other.recentRepositories) &&
      timelineFont == other.timelineFont &&
      timelineFontSize == other.timelineFontSize &&
      listEquals(commitProfiles, other.commitProfiles) &&
      mergeMessageTemplate == other.mergeMessageTemplate &&
      rebaseMergeMessageTemplate == other.rebaseMergeMessageTemplate &&
      githubApiBaseUrl == other.githubApiBaseUrl &&
      listEquals(customGithubApiBaseUrls, other.customGithubApiBaseUrls);

  // Object.hash tops out at 20 arguments and this settled on exactly 20, so the
  // list form is what keeps taking fields.
  @override
  int get hashCode => Object.hashAll([
    showAvatars,
    precisePush,
    timelineTheme,
    previewPlacement,
    branchPreviewMode,
    columnWidths,
    Object.hashAllUnordered(
      repositoryGraphWidths.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    fullDiffColumnWidths,
    fullDiffPreferences,
    baseBranchColor,
    Object.hashAll(laneColors),
    Object.hashAll(refPalette),
    Object.hashAll(refPaletteAssignments),
    previewWidth,
    previewHeight,
    previewDiffLeftWidth,
    previewDiffRightWidth,
    previewDiffBottomHeight,
    Object.hashAllUnordered(
      baseBranches.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(
      deletedBranchNames.entries.map(
        (repository) => Object.hash(
          repository.key,
          Object.hashAllUnordered(
            repository.value.entries.map(
              (entry) => Object.hash(entry.key, entry.value),
            ),
          ),
        ),
      ),
    ),
    Object.hashAll(recentRepositories),
    timelineFont,
    timelineFontSize,
    Object.hashAll(commitProfiles),
    mergeMessageTemplate,
    rebaseMergeMessageTemplate,
    githubApiBaseUrl,
    Object.hashAll(customGithubApiBaseUrls),
  ]);
}

/// [template] with its variables filled in: `{source}` the compared branch,
/// `{target}` the base branch, `{profile}` who reviewed it. An empty template
/// means git's own message. A `{profile}` with nobody to name takes its whole
/// line with it — a dangling `Reviewed-by:` is worse than no line — and any
/// blank run left at the end goes too. Anything else in braces is left alone.
String renderCommitMessageTemplate(
  String template, {
  required String source,
  required String target,
  String? profile,
}) {
  final body = template.trim().isEmpty
      ? AppSettings.standardMergeMessage
      : template;
  final lines = <String>[];
  var dropped = false;
  for (final line in body.split('\n')) {
    if (profile == null && line.contains('{profile}')) {
      dropped = true;
      continue;
    }
    // 지운 줄이 빈 줄 사이에 있었으면 빈 줄 하나만 남긴다.
    if (dropped &&
        line.trim().isEmpty &&
        (lines.isEmpty || lines.last.trim().isEmpty)) {
      dropped = false;
      continue;
    }
    dropped = false;
    lines.add(
      line
          .replaceAll('{source}', source)
          .replaceAll('{target}', target)
          .replaceAll('{profile}', profile ?? ''),
    );
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

class SettingsStore {
  SettingsStore([File? file]) : file = file ?? File(_defaultPath());

  final File file;

  static String _defaultPath() => pathForHome(Platform.environment['HOME']);

  /// The settings file under [home]. With no HOME there is no home directory to
  /// read, and the working directory is not a substitute: it can be the opened
  /// repository, whose own settings file would then be the one yogit reads and
  /// writes — the opened repository deciding yogit's own configuration. A
  /// fixed temp path is no substitute either, since any other local user can
  /// plant that file first, so the fallback is a fresh random directory nobody
  /// can pre-create: settings simply do not persist without a home directory.
  @visibleForTesting
  static String pathForHome(String? home) => home == null || home.isEmpty
      ? '${Directory.systemTemp.createTempSync('yogit_').path}/settings.json'
      : '$home/Library/Application Support/yogit/settings.json';

  Future<AppSettings> load() async {
    try {
      return AppSettings.fromJson(
        jsonDecode(await file.readAsString()) as Object?,
      );
    } on FileSystemException {
      return const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}

enum _SettingsSection {
  gitIntegrations,
  commitProfiles,
  commitMessages,
  appearance,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.settings,
    required this.onChanged,
    this.tokenStore,
    this.githubSend,
    this.oauthLogin,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  /// Where the GitHub 서버 section keeps each server's token.
  final GithubTokenStore? tokenStore;

  /// The transport 연결 확인 uses, so a test never reaches the network.
  final HttpSend? githubSend;

  /// Browser login for one server, giving back the access token. Defaults to
  /// the real loopback flow.
  final Future<String> Function(String apiBaseUrl)? oauthLogin;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _colorFieldStyle = TextStyle(
    color: Color(0xFFE8EAF2),
    fontSize: 11,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
  );
  static const _colorFieldDecoration = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    border: OutlineInputBorder(),
  );

  static const _githubFieldStyle = TextStyle(
    color: Color(0xFFE8EAF2),
    fontSize: 11.5,
  );

  static InputDecoration _githubFieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: const Color(0xFF12141A),
    hintStyle: const TextStyle(color: Color(0xFF5A6172), fontSize: 11.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(7)),
      borderSide: BorderSide(color: Color(0xFF454B5C)),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(7)),
      borderSide: BorderSide(color: Color(0xFF454B5C)),
    ),
  );

  /// The 시안's template editor: a sunken monospace block, first line the
  /// subject and everything under the blank line the body, as in git.
  static const _templateStyle = TextStyle(
    color: Color(0xFFE5E5EA),
    fontSize: 12,
    height: 1.55,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
  );
  static const _templateDecoration = InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Color(0xFF1C1C1E),
    contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(7)),
      borderSide: BorderSide(color: Color(0xFF38383A)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(7)),
      borderSide: BorderSide(color: Color(0xFF38383A)),
    ),
  );

  late AppSettings _settings = widget.settings;
  var _section = _SettingsSection.gitIntegrations;
  late final _refPaletteFields = [
    for (final entry in _settings.refPalette)
      (
        base: TextEditingController(text: entry.base),
        text: TextEditingController(text: entry.text),
      ),
  ];
  late final _mergeMessageField = TextEditingController(
    text: _settings.mergeMessageTemplate,
  );
  late final _rebaseMergeMessageField = TextEditingController(
    text: _settings.rebaseMergeMessageTemplate,
  );

  late final GithubTokenStore _tokenStore =
      widget.tokenStore ?? GithubTokenStore();
  late final HttpSend _githubSend = widget.githubSend ?? sendOverHttps;
  final _githubTokenField = TextEditingController();
  final _newServerField = TextEditingController();

  /// Whether each server has a token, by API base URL. Filled from the
  /// Keychain on entry — a local call, so it costs nothing to ask for all of
  /// them; the network is only touched when the user asks for 연결 확인.
  final _serverHasToken = <String, bool>{};
  String? _verifiedLogin;
  String? _githubError;
  String? _addServerError;
  var _addingServer = false;
  var _githubBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadServerTokens(_githubServers));
  }

  @override
  void dispose() {
    _mergeMessageField.dispose();
    _rebaseMergeMessageField.dispose();
    _githubTokenField.dispose();
    _newServerField.dispose();
    for (final fields in _refPaletteFields) {
      fields.base.dispose();
      fields.text.dispose();
    }
    super.dispose();
  }

  List<String> get _githubServers => [
    ...defaultGithubApiBaseUrls,
    ..._settings.customGithubApiBaseUrls,
  ];

  Future<void> _loadServerTokens(List<String> servers) async {
    final states = <String, bool>{};
    for (final server in servers) {
      states[server] = await _tokenStore.read(server) != null;
    }
    if (mounted) setState(() => _serverHasToken.addAll(states));
  }

  void _selectGithubServer(String server) {
    if (server == _settings.githubApiBaseUrl) return;
    setState(() {
      _verifiedLogin = null;
      _githubError = null;
      _githubTokenField.clear();
    });
    _change(_settings.copyWith(githubApiBaseUrl: server));
  }

  void _addGithubServer() {
    final url = _newServerField.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
      setState(() => _addServerError = 'https://호스트/api/v3 형식으로 입력하세요.');
      return;
    }
    final known = _githubServers.contains(url);
    setState(() {
      _addingServer = false;
      _addServerError = null;
      _newServerField.clear();
      _verifiedLogin = null;
      _githubError = null;
    });
    _change(
      _settings.copyWith(
        githubApiBaseUrl: url,
        customGithubApiBaseUrls: known
            ? _settings.customGithubApiBaseUrls
            : [..._settings.customGithubApiBaseUrls, url],
      ),
    );
    if (!known) unawaited(_loadServerTokens([url]));
  }

  /// One place for the three calls that can fail, so every failure lands as
  /// one line inside the login card instead of an unhandled exception.
  Future<void> _runGithubAction(Future<void> Function() action) async {
    setState(() {
      _githubBusy = true;
      _githubError = null;
    });
    try {
      await action();
    } on GitHubApiException catch (error) {
      if (mounted) _githubError = error.message;
    } on Exception catch (error) {
      if (mounted) _githubError = _withoutExceptionPrefix(error);
    } finally {
      if (mounted) setState(() => _githubBusy = false);
    }
  }

  static String _withoutExceptionPrefix(Exception error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> _browserLogin() => _runGithubAction(() async {
    final server = _settings.githubApiBaseUrl;
    final login =
        widget.oauthLogin ??
        (String apiBaseUrl) => GithubOAuthLogin(apiBaseUrl: apiBaseUrl).login();
    await _tokenStore.save(server, await login(server));
    await _refreshServerToken(server);
  });

  Future<void> _saveGithubToken() => _runGithubAction(() async {
    final token = _githubTokenField.text.trim();
    if (token.isEmpty) throw const GitHubApiException('토큰을 입력하세요.');
    await _tokenStore.save(_settings.githubApiBaseUrl, token);
    _githubTokenField.clear();
    await _refreshServerToken(_settings.githubApiBaseUrl);
  });

  Future<void> _verifyGithub() => _runGithubAction(() async {
    final server = _settings.githubApiBaseUrl;
    final token = await _tokenStore.read(server);
    _serverHasToken[server] = token != null;
    if (token == null) {
      throw const GitHubApiException('저장된 토큰이 없습니다. 먼저 로그인하세요.');
    }
    final user = await GitHubApi(
      apiBaseUrl: server,
      token: token,
      send: _githubSend,
    ).getJson('user');
    final login = user is Map<String, dynamic> ? user['login'] : null;
    if (login is! String || login.isEmpty) {
      throw const GitHubApiException('GitHub가 로그인 이름을 돌려주지 않았습니다.');
    }
    _verifiedLogin = login;
  });

  Future<void> _githubLogout() => _runGithubAction(() async {
    final server = _settings.githubApiBaseUrl;
    await _tokenStore.delete(server);
    _githubTokenField.clear();
    await _refreshServerToken(server);
  });

  /// Asks the Keychain again rather than assuming: a token exported in the
  /// environment survives a logout, and the chip should say so.
  Future<void> _refreshServerToken(String server) async {
    final token = await _tokenStore.read(server);
    _serverHasToken[server] = token != null;
    _verifiedLogin = null;
  }

  void _change(AppSettings value) {
    setState(() => _settings = value);
    widget.onChanged(value);
  }

  void _changeRefPalette(int index, {String? base, String? text}) {
    final current = _settings.refPalette[index];
    final next = (
      base: formatHexColor(base ?? current.base),
      text: formatHexColor(text ?? current.text),
    );
    if (parseHexColor(next.base) == null || parseHexColor(next.text) == null) {
      return;
    }
    final palette = [..._settings.refPalette]..[index] = next;
    _change(_settings.copyWith(refPalette: palette));
  }

  void _changeRefPaletteAssignment(int index, int lane) {
    final assignments = [..._settings.refPaletteAssignments];
    if (lane != 0) {
      for (var other = 1; other < assignments.length; other++) {
        if (assignments[other] == lane) assignments[other] = 0;
      }
    }
    assignments[index] = lane;
    _change(_settings.copyWith(refPaletteAssignments: assignments));
  }

  void _resetRefPalette() {
    _change(
      _settings.copyWith(
        refPalette: AppSettings.defaultRefPalette,
        refPaletteAssignments: AppSettings.defaultRefPaletteAssignments,
      ),
    );
    for (var index = 0; index < _refPaletteFields.length; index++) {
      _refPaletteFields[index].base.text =
          AppSettings.defaultRefPalette[index].base;
      _refPaletteFields[index].text.text =
          AppSettings.defaultRefPalette[index].text;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF15171E),
    body: Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF1D2029),
            border: Border(bottom: BorderSide(color: Color(0xFF343946))),
          ),
          child: Row(
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  color: Color(0xFFE8EAF2),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 190,
                color: const Color(0xFF1A1D25),
                padding: const EdgeInsets.all(10),
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    _settingsSectionRow(
                      section: _SettingsSection.appearance,
                      key: const Key('settings-section-appearance'),
                      icon: Icons.palette_outlined,
                      label: 'Appearance',
                    ),
                    const SizedBox(height: 4),
                    _settingsSectionRow(
                      section: _SettingsSection.gitIntegrations,
                      key: const Key('settings-git-integrations'),
                      icon: Icons.account_tree_outlined,
                      label: 'Git integrations',
                    ),
                    const SizedBox(height: 4),
                    _settingsSectionRow(
                      section: _SettingsSection.commitProfiles,
                      key: const Key('settings-section-commit-profiles'),
                      icon: Icons.badge_outlined,
                      label: '커밋 프로필',
                    ),
                    const SizedBox(height: 4),
                    _settingsSectionRow(
                      section: _SettingsSection.commitMessages,
                      key: const Key('settings-section-commit-messages'),
                      icon: Icons.notes_outlined,
                      label: '커밋 메시지 템플릿',
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFF343946)),
              Expanded(
                child: switch (_section) {
                  _SettingsSection.appearance => _appearance(),
                  _SettingsSection.gitIntegrations => _gitIntegrations(),
                  _SettingsSection.commitProfiles => _commitProfiles(),
                  _SettingsSection.commitMessages => _commitMessages(),
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _settingsSectionRow({
    required _SettingsSection section,
    required Key key,
    required IconData icon,
    required String label,
  }) {
    final selected = _section == section;
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _section = section),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF263246) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? const Color(0xFF7AD6E8)
                    : const Color(0xFF8D94A8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFE8EAF2)
                        : const Color(0xFF8D94A8),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appearance() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appearance',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the dark appearance used by the timeline and preview.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final theme in TimelineThemeKind.values)
                _TimelineThemeCard(
                  key: Key('timeline-theme-card-${theme.storageValue}'),
                  theme: theme,
                  selected: _settings.timelineTheme == theme,
                  onTap: () =>
                      _change(_settings.copyWith(timelineTheme: theme)),
                ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            '타임라인 폰트',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Branch / Tag 칩, 그래프 이니셜, 커밋 메시지, Date, Author에 함께 적용됩니다. '
            '커밋 메시지가 고른 크기로 서고 나머지 컬럼은 1px 작게 따라옵니다.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 8),
          RadioGroup<TimelineFontChoice>(
            groupValue: _settings.timelineFont,
            onChanged: (value) {
              if (value != null) {
                _change(_settings.copyWith(timelineFont: value));
              }
            },
            child: Column(
              children: [
                for (final (choice, label, hint) in const [
                  (TimelineFontChoice.system, '시스템 폰트', '기본 — macOS 표준 · 13px'),
                  (TimelineFontChoice.geist, 'Geist', 'gitru와 같은 얼굴 · 14px'),
                  (
                    TimelineFontChoice.openSans,
                    'Open Sans',
                    'GitKraken과 같은 얼굴 · 12px',
                  ),
                ])
                  RadioListTile<TimelineFontChoice>(
                    key: Key('timeline-font-${choice.name}'),
                    value: choice,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      label,
                      style: TextStyle(
                        color: const Color(0xFFE8EAF2),
                        fontSize: 13,
                        fontFamily: choice.fontFamily,
                      ),
                    ),
                    subtitle: Text(
                      hint,
                      style: const TextStyle(
                        color: Color(0xFF8D94A8),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _timelineFontSizeControl(),
          const SizedBox(height: 28),
          const Text(
            '커밋 아바타',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '타임라인, 미리보기, blame이 사람을 그리는 방식입니다. 사진은 GitHub·GHE에서만 '
            '받아오고 Gravatar는 조회하지 않습니다.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 8),
          RadioGroup<bool>(
            groupValue: _settings.showAvatars,
            onChanged: (value) {
              if (value != null) {
                _change(_settings.copyWith(showAvatars: value));
              }
            },
            child: Column(
              children: [
                for (final (photo, label, hint) in const [
                  (true, '프로필 사진', '사진이 없거나 받아오지 못하면 이니셜로 그립니다'),
                  (false, '이름 이니셜', '사진을 요청하지 않고 이름 첫 글자만 그립니다 — jung.min은 JM'),
                ])
                  RadioListTile<bool>(
                    key: Key('avatar-style-${photo ? 'photo' : 'initials'}'),
                    value: photo,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFE8EAF2),
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      hint,
                      style: const TextStyle(
                        color: Color(0xFF8D94A8),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// The size on screen: the stored one, or the family's own until the user
  /// moves the slider, so switching family moves the control with it.
  double get _timelineFontSize =>
      _settings.timelineFontSize ?? _settings.timelineFont.defaultFontSize;

  Widget _timelineFontSizeControl() => Row(
    children: [
      Expanded(
        child: Slider(
          key: const Key('timeline-font-size'),
          value: _timelineFontSize,
          min: AppSettings.minTimelineFontSize,
          max: AppSettings.maxTimelineFontSize,
          divisions:
              (AppSettings.maxTimelineFontSize -
                      AppSettings.minTimelineFontSize)
                  .round(),
          label: '${_timelineFontSize.round()}px',
          onChanged: (value) =>
              _change(_settings.copyWith(timelineFontSize: value)),
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '${_timelineFontSize.round()}px',
          style: const TextStyle(color: Color(0xFFE8EAF2), fontSize: 12),
        ),
      ),
      TextButton(
        key: const Key('timeline-font-size-reset'),
        // Already on the family default: resetting would only rewrite the
        // settings file to say the same thing.
        onPressed: _settings.timelineFontSize == null
            ? null
            : () => _change(_settings.copyWith(clearTimelineFontSize: true)),
        child: const Text('초기화'),
      ),
    ],
  );

  Widget _commitProfiles() {
    final profiles = _settings.commitProfiles;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '커밋 프로필',
              style: TextStyle(
                color: Color(0xFFE8EAF2),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '저장소마다 상태바에서 선택해 사용할 이름과 이메일 목록입니다. '
              '고른 프로필은 그 저장소의 .git/config에 기록됩니다.',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
            ),
            const SizedBox(height: 20),
            for (var index = 0; index < profiles.length; index++)
              _commitProfileRow(index, profiles[index]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                key: const Key('add-commit-profile'),
                borderRadius: BorderRadius.circular(7),
                onTap: _addCommitProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF343946),
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: Color(0xFF8D94A8)),
                      SizedBox(width: 6),
                      Text(
                        '프로필 추가',
                        style: TextStyle(
                          color: Color(0xFF8D94A8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commitMessages() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '커밋 메시지 템플릿',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '머지 커밋을 만드는 적용에서 커밋 메시지 창에 미리 채울 내용입니다.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 20),
          _messageTemplateField(
            label: 'Merge 커밋 메시지',
            fieldKey: const Key('merge-message-template'),
            controller: _mergeMessageField,
            onChanged: (value) =>
                _change(_settings.copyWith(mergeMessageTemplate: value)),
          ),
          const SizedBox(height: 16),
          _messageTemplateField(
            label: 'Rebase 후 Merge 커밋 메시지',
            fieldKey: const Key('rebase-merge-message-template'),
            controller: _rebaseMergeMessageField,
            onChanged: (value) =>
                _change(_settings.copyWith(rebaseMergeMessageTemplate: value)),
          ),
          const SizedBox(height: 12),
          const Text(
            '{source} 비교 브랜치 · {target} 기준 브랜치 · {profile} 이 저장소의 커밋 프로필 이름입니다. '
            '변수는 그 창을 열 때 채워집니다. '
            '템플릿을 비우면 git 표준 메시지만 씁니다.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10),
          ),
        ],
      ),
    ),
  );

  Widget _messageTemplateField({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8D94A8),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      TextField(
        key: fieldKey,
        controller: controller,
        minLines: 3,
        maxLines: 8,
        style: _templateStyle,
        decoration: _templateDecoration,
        onChanged: onChanged,
      ),
    ],
  );

  Widget _commitProfileRow(int index, CommitProfile profile) => Container(
    key: Key('commit-profile-row-$index'),
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1D25),
      border: Border.all(color: const Color(0xFF343946)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        ProfileAvatar(
          text: profile.initials,
          color: profile.colorValue,
          size: 24,
        ),
        const SizedBox(width: 10),
        Text(
          profile.label.trim().isEmpty ? profile.name : profile.label,
          style: const TextStyle(color: Color(0xFFE8EAF2), fontSize: 12.5),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${profile.name} <${profile.email}>',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8D94A8), fontSize: 11.5),
          ),
        ),
        IconButton(
          key: Key('edit-commit-profile-$index'),
          icon: const Icon(Icons.edit_outlined, size: 15),
          color: const Color(0xFF8D94A8),
          visualDensity: VisualDensity.compact,
          tooltip: '수정',
          onPressed: () => unawaited(_editCommitProfile(index)),
        ),
        IconButton(
          key: Key('delete-commit-profile-$index'),
          icon: const Icon(Icons.delete_outline, size: 15),
          color: const Color(0xFF8D94A8),
          visualDensity: VisualDensity.compact,
          tooltip: '삭제',
          onPressed: () {
            final profiles = [..._settings.commitProfiles]..removeAt(index);
            _change(_settings.copyWith(commitProfiles: profiles));
          },
        ),
      ],
    ),
  );

  void _addCommitProfile() => unawaited(_editCommitProfile(null));

  /// One dialog for both add and edit; [index] null means a new entry.
  Future<void> _editCommitProfile(int? index) async {
    final existing = index == null ? null : _settings.commitProfiles[index];
    final edited = await showYogitAlert<CommitProfile>(
      context,
      _CommitProfileDialog(
        profile:
            existing ??
            CommitProfile(
              label: '',
              name: '',
              email: '',
              color:
                  CommitProfile.paletteColors[_settings.commitProfiles.length %
                      CommitProfile.paletteColors.length],
            ),
        isNew: existing == null,
      ),
    );
    if (edited == null) return;
    final profiles = [..._settings.commitProfiles];
    if (index == null) {
      profiles.add(edited);
    } else {
      profiles[index] = edited;
    }
    _change(_settings.copyWith(commitProfiles: profiles));
  }

  Widget _gitIntegrations() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GitHub 서버',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '모니터링과 커밋 아바타가 이 연결을 사용합니다. '
            '서버마다 따로 로그인하며, 토큰은 macOS 키체인에 저장됩니다.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 14),
          _githubServerList(),
          const SizedBox(height: 14),
          _githubLoginCard(),
          const SizedBox(height: 14),
          SwitchListTile(
            key: const Key('precise-push-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '정밀 push',
              style: TextStyle(color: Color(0xFFE8EAF2), fontSize: 13),
            ),
            subtitle: const Text(
              '확인창이 보인 커밋까지만 올립니다 — git push origin '
              '<커밋>:refs/heads/<브랜치>. 끄면 git push origin <브랜치>로 '
              '올리고, 확인창이 열린 사이에 커밋이 생기면 그것도 함께 올라갑니다.',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
            ),
            value: _settings.precisePush,
            onChanged: (value) =>
                _change(_settings.copyWith(precisePush: value)),
          ),
          const SizedBox(height: 24),
          _laneColors(),
          const SizedBox(height: 24),
          const Text(
            'Avatar fallback preview',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              _AvatarPreview(label: 'Single', kind: _PreviewKind.single),
              SizedBox(width: 10),
              _AvatarPreview(
                label: 'Author + committer',
                kind: _PreviewKind.stack,
              ),
              SizedBox(width: 10),
              _AvatarPreview(
                label: 'Initials fallback',
                kind: _PreviewKind.initials,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// One palette drives both Branch / Tag chips and graph lines.
  Widget _laneColors() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Timeline colors',
        style: TextStyle(
          color: Color(0xFFE8EAF2),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Branch / Tag & graph palette',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFE8EAF2),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            key: const Key('reset-ref-palette'),
            onPressed: _resetRefPalette,
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      const Row(
        children: [
          SizedBox(width: 250),
          SizedBox(
            width: 100,
            child: Text(
              'Base',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10),
            ),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              'Text / line',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      for (var index = 0; index < _refPaletteFields.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: Row(
                  children: [
                    Container(
                      key: Key('ref-palette-chip-$index'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _settings.refPaletteColorValues[index].base
                            .withValues(alpha: .18),
                        border: Border.all(
                          color: _settings.refPaletteColorValues[index].text
                              .withValues(alpha: .30),
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Color ${AppSettings.refPaletteNumbers[index]}',
                        style: TextStyle(
                          color: _settings.refPaletteColorValues[index].text,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (index == 0)
                      const Text(
                        'Base branch',
                        style: TextStyle(
                          color: Color(0xFF8D94A8),
                          fontSize: 11,
                        ),
                      )
                    else
                      Expanded(
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF15171E),
                            border: Border.all(color: const Color(0xFF565D6E)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              key: Key('ref-palette-assignment-$index'),
                              value: _settings.refPaletteAssignments[index],
                              isExpanded: true,
                              isDense: true,
                              dropdownColor: const Color(0xFF1D2029),
                              style: const TextStyle(
                                color: Color(0xFFE8EAF2),
                                fontSize: 11,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 0,
                                  child: Text('Random'),
                                ),
                                for (var lane = 2; lane <= 9; lane++)
                                  DropdownMenuItem(
                                    value: lane,
                                    child: Text('Lane $lane'),
                                  ),
                              ],
                              onChanged: (lane) =>
                                  _changeRefPaletteAssignment(index, lane!),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: TextField(
                  key: Key('ref-palette-base-$index'),
                  controller: _refPaletteFields[index].base,
                  onChanged: (value) => _changeRefPalette(index, base: value),
                  style: _colorFieldStyle,
                  decoration: _colorFieldDecoration,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  key: Key('ref-palette-text-$index'),
                  controller: _refPaletteFields[index].text,
                  onChanged: (value) => _changeRefPalette(index, text: value),
                  style: _colorFieldStyle,
                  decoration: _colorFieldDecoration,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  /// The built-in servers plus the user's own, each wearing its login state.
  Widget _githubServerList() {
    final servers = _githubServers;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D25),
        border: Border.all(color: const Color(0xFF343946)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var index = 0; index < servers.length; index++)
            _githubServerRow(index, servers[index]),
          _addGithubServerRow(),
        ],
      ),
    );
  }

  Widget _githubServerRow(int index, String server) {
    final selected = server == _settings.githubApiBaseUrl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('github-server-select-$index'),
        onTap: () => _selectGithubServer(server),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF232734) : null,
            border: const Border(bottom: BorderSide(color: Color(0xFF343946))),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 13,
                color: selected
                    ? const Color(0xFF64D2FF)
                    : const Color(0xFF3A4152),
              ),
              const SizedBox(width: 10),
              Text(
                _githubServerName(server),
                style: TextStyle(
                  color: const Color(0xFFE8EAF2),
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _githubServerUrlLabel(server),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8D94A8),
                    fontSize: 10.5,
                    fontFamily: technicalFontFamily,
                    fontFamilyFallback: technicalFontFallback,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _githubStatusChip(server),
              if (server == defaultGithubApiBaseUrl) ...[
                const SizedBox(width: 8),
                const Text(
                  '기본',
                  style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _githubStatusChip(String server) {
    final login = server == _settings.githubApiBaseUrl ? _verifiedLogin : null;
    final connected = login != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFF12351D) : const Color(0xFF2A2A2E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connected) ...[
            ProfileAvatar(
              text: login.characters.take(2).toString().toUpperCase(),
              color: const Color(0xFF9FE1CB),
              size: 16,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            connected
                ? '연결됨 · $login'
                : (_serverHasToken[server] ?? false)
                ? '토큰 저장됨'
                : '로그인 안 함',
            style: TextStyle(
              color: connected
                  ? const Color(0xFF34C759)
                  : const Color(0xFF8D94A8),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _addGithubServerRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: _addingServer
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('github-new-server-field'),
                      controller: _newServerField,
                      autofocus: true,
                      style: _githubFieldStyle,
                      decoration: _githubFieldDecoration('https://호스트/api/v3'),
                      onSubmitted: (_) => _addGithubServer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _githubButton(
                    key: const Key('github-add-server-confirm'),
                    label: '추가',
                    onTap: _addGithubServer,
                  ),
                ],
              ),
              if (_addServerError case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 10.5,
                    ),
                  ),
                ),
            ],
          )
        : InkWell(
            key: const Key('github-add-server'),
            onTap: () => setState(() => _addingServer = true),
            child: Row(
              children: [
                const Icon(Icons.add, size: 13, color: Color(0xFF8D94A8)),
                const SizedBox(width: 6),
                const Text(
                  '서버 추가',
                  style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11.5),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '— GHE API 주소(https://호스트/api/v3)를 직접 입력. '
                    '직접 추가한 서버는 토큰으로만 로그인',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
  );

  /// Logging in to the selected server: the browser for a registered one, a
  /// personal access token for any of them.
  Widget _githubLoginCard() {
    final server = _settings.githubApiBaseUrl;
    final registered = githubOAuthCredentialsFor(server) != null;
    final webHost = webBaseUrlOf(server).replaceFirst('https://', '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_githubServerName(server)} — 로그인'
          '${registered ? '' : ' (직접 추가한 서버)'}',
          style: const TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D25),
            border: Border.all(color: const Color(0xFF343946)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (registered)
                Row(
                  children: [
                    _githubButton(
                      key: const Key('github-browser-login'),
                      label: '브라우저로 로그인',
                      icon: Icons.language,
                      primary: true,
                      onTap: () => unawaited(_browserLogin()),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '등록된 서버는 브라우저에서 GitHub 로그인만 하면 됩니다 (권장)',
                        style: TextStyle(
                          color: Color(0xFF8D94A8),
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                )
              else
                const Text(
                  '이 서버는 브라우저 로그인이 등록돼 있지 않습니다. '
                  'Personal Access Token으로 로그인하세요.',
                  style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10.5),
                ),
              if (registered) _githubTokenSeparator(),
              if (!registered) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('github-token-field'),
                      controller: _githubTokenField,
                      obscureText: true,
                      style: _githubFieldStyle,
                      decoration: _githubFieldDecoration('ghp_ …'),
                      onSubmitted: (_) => unawaited(_saveGithubToken()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _githubButton(
                    key: const Key('github-token-save'),
                    label: '저장',
                    onTap: () => unawaited(_saveGithubToken()),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Personal Access Token, 스코프 repo · read:org 필요 — ',
                    style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10.5),
                  ),
                  InkWell(
                    key: const Key('github-token-scope-link'),
                    onTap: () => unawaited(
                      runProcess('/usr/bin/open', [
                        '${webBaseUrlOf(server)}/settings/tokens',
                      ]),
                    ),
                    child: Text(
                      '$webHost/settings/tokens에서 발급 ↗',
                      style: const TextStyle(
                        color: Color(0xFF64D2FF),
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF343946))),
                ),
                child: Row(
                  children: [
                    _githubButton(
                      key: const Key('github-verify'),
                      label: '연결 확인',
                      onTap: () => unawaited(_verifyGithub()),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _githubOutcome()),
                    _githubButton(
                      key: const Key('github-logout'),
                      label: '로그아웃 (토큰 삭제)',
                      danger: true,
                      onTap: () => unawaited(_githubLogout()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _githubTokenSeparator() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(child: Divider(height: 1, color: Color(0xFF343946))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '또는 토큰 직접 입력',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 10.5),
          ),
        ),
        Expanded(child: Divider(height: 1, color: Color(0xFF343946))),
      ],
    ),
  );

  /// What 연결 확인 last said: the login it named, or the failure as the
  /// transport phrased it.
  Widget _githubOutcome() {
    if (_githubError case final error?) {
      return Text(
        '✗ $error',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 10.5),
      );
    }
    if (_verifiedLogin case final login?) {
      return Text(
        '✓ 연결됨 — $login',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF34C759), fontSize: 10.5),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _githubButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool primary = false,
    bool danger = false,
  }) {
    final foreground = danger
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFE8EAF2);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(7),
        onTap: _githubBusy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: primary ? const Color(0xFF173049) : const Color(0xFF232734),
            border: Border.all(
              color: primary
                  ? const Color(0xFF2C5E8F)
                  : danger
                  ? const Color(0xFF5A2A2A)
                  : const Color(0xFF454B5C),
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(color: foreground, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }

  static String _githubServerName(String server) =>
      defaultGithubApiBaseAliases[server] ??
      (Uri.tryParse(server)?.host.isNotEmpty ?? false
          ? Uri.parse(server).host
          : server);

  static String _githubServerUrlLabel(String server) =>
      server.replaceFirst(RegExp(r'^https?://'), '');
}

/// Add/edit one commit profile. The email is the only required field — a
/// profile without one could never be applied to a repository.
class _CommitProfileDialog extends StatefulWidget {
  const _CommitProfileDialog({required this.profile, required this.isNew});

  final CommitProfile profile;
  final bool isNew;

  @override
  State<_CommitProfileDialog> createState() => _CommitProfileDialogState();
}

class _CommitProfileDialogState extends State<_CommitProfileDialog> {
  late final _label = TextEditingController(text: widget.profile.label);
  late final _name = TextEditingController(text: widget.profile.name);
  late final _email = TextEditingController(text: widget.profile.email);
  late var _color = widget.profile.color;

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    labelStyle: const TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) => YogitAlert(
    title: widget.isNew ? '프로필을 추가할까요?' : '프로필을 수정할까요?',
    confirmLabel: '저장',
    confirmKey: const Key('commit-profile-save'),
    // The form is the alert's body, so an input dialog keeps the same shell
    // and the same button row as every confirmation.
    onConfirm: _email.text.trim().isEmpty
        ? null
        : () => CommitProfile(
            label: _label.text.trim(),
            name: _name.text.trim(),
            email: _email.text.trim(),
            color: _color,
          ),
    body: SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('commit-profile-label-field'),
            controller: _label,
            style: const TextStyle(color: Color(0xFFE8EAF2), fontSize: 13),
            decoration: _decoration('레이블 (예: 회사, 개인)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('commit-profile-name-field'),
            controller: _name,
            style: const TextStyle(color: Color(0xFFE8EAF2), fontSize: 13),
            decoration: _decoration('user.name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('commit-profile-email-field'),
            controller: _email,
            style: const TextStyle(color: Color(0xFFE8EAF2), fontSize: 13),
            decoration: _decoration('user.email'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text(
            '색',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final hex in CommitProfile.paletteColors)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    key: Key('commit-profile-color-$hex'),
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: parseHexColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == hex
                              ? const Color(0xFFE8EAF2)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TimelineThemeCard extends StatefulWidget {
  const _TimelineThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final TimelineThemeKind theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TimelineThemeCard> createState() => _TimelineThemeCardState();
}

class _TimelineThemeCardState extends State<_TimelineThemeCard> {
  late final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.theme.palette;
    final surfaces = [
      palette.background,
      palette.panel,
      palette.surface,
      palette.raised,
    ];
    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.theme.label,
      child: SizedBox(
        width: 196,
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
              color: widget.selected
                  ? palette.interactive
                  : const Color(0xFF343946),
              width: widget.selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: _focusNode,
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.theme.label,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.selected)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: palette.interactive,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.theme.description,
                    style: TextStyle(color: palette.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Row(
                            children: [
                              for (final color in surfaces)
                                Expanded(
                                  child: ColoredBox(
                                    color: color,
                                    child: const SizedBox(height: 26),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: palette.interactive,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _PreviewKind { single, stack, initials }

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.label, required this.kind});

  final String label;
  final _PreviewKind kind;

  static const _ada = GitIdentity(
    name: 'Ada Lovelace',
    email: 'ada@example.com',
  );

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 82,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2029),
        border: Border.all(color: const Color(0xFF343946)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (kind == _PreviewKind.stack)
            SizedBox(
              width: 28,
              height: 20,
              child: Stack(
                children: const [
                  Positioned(
                    left: 9,
                    child: _SampleAvatar(color: Color(0xFFF29AB2), size: 20),
                  ),
                  _SampleAvatar(color: Color(0xFF7AD6E8), size: 20),
                ],
              ),
            )
          else if (kind == _PreviewKind.single)
            const _SampleAvatar(color: Color(0xFF7AD6E8), size: 20)
          else
            IdentityAvatar(identity: _ada, size: 20),
          const SizedBox(height: 7),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8D94A8), fontSize: 9),
          ),
        ],
      ),
    ),
  );
}

class _SampleAvatar extends StatelessWidget {
  const _SampleAvatar({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.28),
      shape: BoxShape.circle,
      border: Border.all(color: color),
    ),
    child: Icon(Icons.person, size: size * 0.65, color: color),
  );
}
