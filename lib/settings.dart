import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'commit_profile_chip.dart' show ProfileAvatar;
import 'full_diff_model.dart';
import 'git.dart';
import 'timeline_theme.dart';
import 'window_frame.dart';
import 'yogit_alert.dart';

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

  /// Null until the user drags the title column: the timeline then lets it
  /// absorb the leftover viewport width instead of pinning it.
  final double? commit;
  final double time;
  final double name;
  final bool showTime;
  final bool showName;

  /// [graph] and [commit] only widen: pass a value to pin the column, and use
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

class FullDiffColumnWidths {
  const FullDiffColumnWidths({
    this.history = 280,
    this.files = 290,
    this.sideBySideRatio = 0.5,
  });

  static const minHistory = 180.0;
  static const maxHistory = 420.0;
  static const minFiles = 158.0;
  static const maxFiles = 520.0;
  static const minSideBySideRatio = 0.2;
  static const maxSideBySideRatio = 0.8;

  final double history;
  final double files;
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
      files: width('files', 290, minFiles, maxFiles),
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
    'files': files,
    'sideBySideRatio': sideBySideRatio,
  };

  @override
  bool operator ==(Object other) =>
      other is FullDiffColumnWidths &&
      history == other.history &&
      files == other.files &&
      sideBySideRatio == other.sideBySideRatio;

  @override
  int get hashCode => Object.hash(history, files, sideBySideRatio);
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

class AppSettings {
  const AppSettings({
    this.showAvatars = true,
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
    this.recentRepositories = const [],
    this.commitProfiles = const [],
    this.mergeMessageTemplate = defaultMergeMessageTemplate,
    this.rebaseMergeMessageTemplate = defaultMergeMessageTemplate,
  });

  /// How many repositories the picker remembers before the oldest drops off.
  static const maxRecentRepositories = 10;

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

  /// Repository roots, most recently opened first.
  final List<String> recentRepositories;

  /// The commit identities the status bar offers, in display order.
  final List<CommitProfile> commitProfiles;

  /// What the commit message box is prefilled with when an apply creates a
  /// merge commit. Empty means git's own [standardMergeMessage] alone.
  final String mergeMessageTemplate;
  final String rebaseMergeMessageTemplate;

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
    List<String>? recentRepositories,
    List<CommitProfile>? commitProfiles,
    String? mergeMessageTemplate,
    String? rebaseMergeMessageTemplate,
  }) => AppSettings(
    showAvatars: showAvatars ?? this.showAvatars,
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
    recentRepositories: recentRepositories ?? this.recentRepositories,
    commitProfiles: commitProfiles ?? this.commitProfiles,
    mergeMessageTemplate: mergeMessageTemplate ?? this.mergeMessageTemplate,
    rebaseMergeMessageTemplate:
        rebaseMergeMessageTemplate ?? this.rebaseMergeMessageTemplate,
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
        refPalette.length == defaultRefPalette.length && validRefPaletteEntries;
    final migratedRefPalette = refPalette.length == 5 && validRefPaletteEntries
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
      refPalette: validRefPalette ? refPalette : migratedRefPalette,
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
      recentRepositories: _parseRecentRepositories(value['recentRepositories']),
      commitProfiles: _parseCommitProfiles(value['commitProfiles']),
      // An empty string is a choice — git's own message — so only a missing or
      // non-string entry falls back to the default template.
      mergeMessageTemplate: value['mergeMessageTemplate'] is String
          ? value['mergeMessageTemplate'] as String
          : defaultMergeMessageTemplate,
      rebaseMergeMessageTemplate: value['rebaseMergeMessageTemplate'] is String
          ? value['rebaseMergeMessageTemplate'] as String
          : defaultMergeMessageTemplate,
    );
  }

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
    'recentRepositories': recentRepositories,
    'commitProfiles': [for (final profile in commitProfiles) profile.toJson()],
    'mergeMessageTemplate': mergeMessageTemplate,
    'rebaseMergeMessageTemplate': rebaseMergeMessageTemplate,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      showAvatars == other.showAvatars &&
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
      listEquals(recentRepositories, other.recentRepositories) &&
      listEquals(commitProfiles, other.commitProfiles) &&
      mergeMessageTemplate == other.mergeMessageTemplate &&
      rebaseMergeMessageTemplate == other.rebaseMergeMessageTemplate;

  // Object.hash tops out at 20 arguments and this settled on exactly 20, so the
  // list form is what keeps taking fields.
  @override
  int get hashCode => Object.hashAll([
    showAvatars,
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
    Object.hashAll(commitProfiles),
    mergeMessageTemplate,
    rebaseMergeMessageTemplate,
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
    this.avatarService,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final AvatarService? avatarService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _colorFieldStyle = TextStyle(
    color: Color(0xFFE8EAF2),
    fontSize: 11,
    fontFamily: 'monospace',
  );
  static const _colorFieldDecoration = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    border: OutlineInputBorder(),
  );

  /// The 시안's template editor: a sunken monospace block, first line the
  /// subject and everything under the blank line the body, as in git.
  static const _templateStyle = TextStyle(
    color: Color(0xFFE5E5EA),
    fontSize: 12,
    height: 1.55,
    fontFamily: 'monospace',
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
  late final _baseBranchColorField = TextEditingController(
    text: _settings.baseBranchColor,
  );
  late final _refPaletteFields = [
    for (final entry in _settings.refPalette)
      (
        base: TextEditingController(text: entry.base),
        text: TextEditingController(text: entry.text),
      ),
  ];
  late final _laneFields = [
    for (final hex in _settings.laneColors) TextEditingController(text: hex),
  ];
  late final _mergeMessageField = TextEditingController(
    text: _settings.mergeMessageTemplate,
  );
  late final _rebaseMergeMessageField = TextEditingController(
    text: _settings.rebaseMergeMessageTemplate,
  );

  @override
  void dispose() {
    _baseBranchColorField.dispose();
    _mergeMessageField.dispose();
    _rebaseMergeMessageField.dispose();
    for (final fields in _refPaletteFields) {
      fields.base.dispose();
      fields.text.dispose();
    }
    for (final field in _laneFields) {
      field.dispose();
    }
    super.dispose();
  }

  void _change(AppSettings value) {
    setState(() => _settings = value);
    widget.onChanged(value);
  }

  /// Live validation: a half-typed hex leaves the timeline on the last good one.
  void _changeLaneColor(int index, String value) {
    if (parseHexColor(value) == null) return;
    final colors = [..._settings.laneColors];
    colors[index] = formatHexColor(value);
    _change(_settings.copyWith(laneColors: colors));
  }

  void _changeBaseBranchColor(String value) {
    if (parseHexColor(value) == null) return;
    _change(_settings.copyWith(baseBranchColor: formatHexColor(value)));
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

  void _resetRefPalette() {
    _change(_settings.copyWith(refPalette: AppSettings.defaultRefPalette));
    for (var index = 0; index < _refPaletteFields.length; index++) {
      _refPaletteFields[index].base.text =
          AppSettings.defaultRefPalette[index].base;
      _refPaletteFields[index].text.text =
          AppSettings.defaultRefPalette[index].text;
    }
  }

  void _resetLaneColors() {
    _change(
      _settings.copyWith(
        baseBranchColor: AppSettings.defaultBaseBranchColor,
        laneColors: AppSettings.defaultLaneColors,
      ),
    );
    _baseBranchColorField.text = AppSettings.defaultBaseBranchColor;
    for (var index = 0; index < _laneFields.length; index++) {
      _laneFields[index].text = AppSettings.defaultLaneColors[index];
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
        ],
      ),
    ),
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
            'Git integrations',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'yogit reuses your existing GitHub CLI login. '
            'There is no separate token or account to manage.',
            style: TextStyle(color: Color(0xFF8D94A8), fontSize: 12),
          ),
          const SizedBox(height: 20),
          _connection(),
          const SizedBox(height: 20),
          SwitchListTile(
            key: const Key('show-avatars-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Show commit avatars',
              style: TextStyle(color: Color(0xFFE8EAF2), fontSize: 13),
            ),
            subtitle: const Text(
              'GitHub and GHE only. Gravatar is never queried.',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
            ),
            value: _settings.showAvatars,
            onChanged: (value) =>
                _change(_settings.copyWith(showAvatars: value)),
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

  /// The lane palette: one swatch and hex field per color, plus the way back.
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
          const Text(
            'Branch / Tag palette',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            key: const Key('reset-ref-palette'),
            onPressed: _resetRefPalette,
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      for (var index = 0; index < _refPaletteFields.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                key: Key('ref-palette-chip-$index'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _settings.refPaletteColorValues[index].base.withValues(
                    alpha: .18,
                  ),
                  border: Border.all(
                    color: _settings.refPaletteColorValues[index].text
                        .withValues(alpha: .30),
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'Color ${index + 1}',
                  style: TextStyle(
                    color: _settings.refPaletteColorValues[index].text,
                    fontSize: 11,
                  ),
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
      Row(
        children: [
          const Expanded(
            child: Text(
              'Base branch and lane fallback',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
            ),
          ),
          TextButton(
            key: const Key('reset-lane-colors'),
            onPressed: _resetLaneColors,
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              key: const Key('base-branch-swatch'),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color:
                    parseHexColor(_settings.baseBranchColor) ??
                    AvatarService.defaultBaseBranchColor,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                key: const Key('base-branch-color'),
                controller: _baseBranchColorField,
                onChanged: _changeBaseBranchColor,
                style: _colorFieldStyle,
                decoration: _colorFieldDecoration,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Base branch',
              style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
            ),
          ],
        ),
      ),
      for (var index = 0; index < _laneFields.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                key: Key('lane-swatch-$index'),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color:
                      parseHexColor(_settings.laneColors[index]) ??
                      const Color(0xFF343946),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  key: Key('lane-color-$index'),
                  controller: _laneFields[index],
                  onChanged: (value) => _changeLaneColor(index, value),
                  style: _colorFieldStyle,
                  decoration: _colorFieldDecoration,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _connection() {
    final service = widget.avatarService;
    if (service == null) {
      return const Text(
        'No GitHub or GHE origin detected',
        style: TextStyle(color: Color(0xFF8D94A8), fontSize: 11),
      );
    }
    return FutureBuilder<String?>(
      future: service.accountLogin(),
      builder: (context, snapshot) {
        final connected = snapshot.data != null;
        return Row(
          children: [
            Icon(
              connected ? Icons.check_circle : Icons.cloud_off_outlined,
              size: 15,
              color: connected
                  ? const Color(0xFF8AD6A1)
                  : const Color(0xFF8D94A8),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                connected
                    ? '${service.remote.host} · ${snapshot.data}'
                    : '${service.remote.host} · gh login not detected',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC6CAD7), fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
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
