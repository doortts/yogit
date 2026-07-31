import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'full_diff_model.dart';
import 'git.dart';
import 'timeline_theme.dart';
import 'window_frame.dart';

enum BranchPreviewMode {
  merge,
  rebase;

  static BranchPreviewMode parse(Object? value) =>
      value == 'rebase' ? rebase : merge;
}

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
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.previewDiffLeftWidth,
    this.previewDiffRightWidth,
    this.previewDiffBottomHeight,
    this.baseBranches = const {},
    this.deletedBranchNames = const {},
  });

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
  final Map<String, String> baseBranches;
  final Map<String, Map<String, String>> deletedBranchNames;

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
    double? previewWidth,
    double? previewHeight,
    double? previewDiffLeftWidth,
    double? previewDiffRightWidth,
    double? previewDiffBottomHeight,
    Map<String, String>? baseBranches,
    Map<String, Map<String, String>>? deletedBranchNames,
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
    previewWidth: previewWidth ?? this.previewWidth,
    previewHeight: previewHeight ?? this.previewHeight,
    previewDiffLeftWidth: previewDiffLeftWidth ?? this.previewDiffLeftWidth,
    previewDiffRightWidth: previewDiffRightWidth ?? this.previewDiffRightWidth,
    previewDiffBottomHeight:
        previewDiffBottomHeight ?? this.previewDiffBottomHeight,
    baseBranches: baseBranches ?? this.baseBranches,
    deletedBranchNames: deletedBranchNames ?? this.deletedBranchNames,
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
    );
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
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
    'previewDiffLeftWidth': ?previewDiffLeftWidth,
    'previewDiffRightWidth': ?previewDiffRightWidth,
    'previewDiffBottomHeight': ?previewDiffBottomHeight,
    'baseBranches': baseBranches,
    'deletedBranchNames': deletedBranchNames,
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
      previewWidth == other.previewWidth &&
      previewHeight == other.previewHeight &&
      previewDiffLeftWidth == other.previewDiffLeftWidth &&
      previewDiffRightWidth == other.previewDiffRightWidth &&
      previewDiffBottomHeight == other.previewDiffBottomHeight &&
      mapEquals(baseBranches, other.baseBranches) &&
      _nestedStringMapEquals(deletedBranchNames, other.deletedBranchNames);

  @override
  int get hashCode => Object.hash(
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
  );
}

class SettingsStore {
  SettingsStore([File? file]) : file = file ?? File(_defaultPath());

  final File file;

  static String _defaultPath() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return '$home/Library/Application Support/yogit/settings.json';
  }

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

enum _SettingsSection { gitIntegrations, appearance }

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
  late AppSettings _settings = widget.settings;
  var _section = _SettingsSection.gitIntegrations;
  late final _baseBranchColorField = TextEditingController(
    text: _settings.baseBranchColor,
  );
  late final _laneFields = [
    for (final hex in _settings.laneColors) TextEditingController(text: hex),
  ];

  @override
  void dispose() {
    _baseBranchColorField.dispose();
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
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFF343946)),
              Expanded(
                child: switch (_section) {
                  _SettingsSection.appearance => _appearance(),
                  _SettingsSection.gitIntegrations => _gitIntegrations(),
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
      Row(
        children: [
          const Text(
            'Timeline colors',
            style: TextStyle(
              color: Color(0xFFE8EAF2),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
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
                style: const TextStyle(
                  color: Color(0xFFE8EAF2),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  border: OutlineInputBorder(),
                ),
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
                  style: const TextStyle(
                    color: Color(0xFFE8EAF2),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    border: OutlineInputBorder(),
                  ),
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
