import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'full_diff_model.dart';
import 'git.dart';
import 'window_frame.dart';

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
      sidebar: width('sidebar', 150, 120, 320),
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
  const FullDiffColumnWidths({this.commits = 210, this.files = 290});

  static const minCommits = 126.0;
  static const maxCommits = 420.0;
  static const minFiles = 158.0;
  static const maxFiles = 520.0;

  final double commits;
  final double files;

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
      commits: width('commits', 210, minCommits, maxCommits),
      files: width('files', 290, minFiles, maxFiles),
    );
  }

  Map<String, Object> toJson() => {'commits': commits, 'files': files};

  @override
  bool operator ==(Object other) =>
      other is FullDiffColumnWidths &&
      commits == other.commits &&
      files == other.files;

  @override
  int get hashCode => Object.hash(commits, files);
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

String formatHexColor(String value) =>
    '#${value.trim().replaceFirst('#', '').toUpperCase()}';

class AppSettings {
  const AppSettings({
    this.showAvatars = true,
    this.previewPlacement = PreviewPlacement.right,
    this.columnWidths = const TimelineColumnWidths(),
    this.fullDiffColumnWidths = const FullDiffColumnWidths(),
    this.fullDiffPreferences = const FullDiffPreferences(),
    this.laneColors = defaultLaneColors,
    this.previewWidth = 288,
    this.previewHeight = 280,
  });

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
  final PreviewPlacement previewPlacement;
  final TimelineColumnWidths columnWidths;
  final FullDiffColumnWidths fullDiffColumnWidths;
  final FullDiffPreferences fullDiffPreferences;
  final List<String> laneColors;

  /// The detail panel's size, per placement axis.
  final double previewWidth;
  final double previewHeight;

  /// The palette to hand [AvatarService]; a damaged entry drops the whole list
  /// back to the default rather than painting one rail wrong.
  List<Color> get laneColorValues {
    final colors = [for (final value in laneColors) parseHexColor(value)];
    return colors.isEmpty || colors.contains(null)
        ? AvatarService.defaultColors
        : colors.cast<Color>();
  }

  AppSettings copyWith({
    bool? showAvatars,
    PreviewPlacement? previewPlacement,
    TimelineColumnWidths? columnWidths,
    FullDiffColumnWidths? fullDiffColumnWidths,
    FullDiffPreferences? fullDiffPreferences,
    List<String>? laneColors,
    double? previewWidth,
    double? previewHeight,
  }) => AppSettings(
    showAvatars: showAvatars ?? this.showAvatars,
    previewPlacement: previewPlacement ?? this.previewPlacement,
    columnWidths: columnWidths ?? this.columnWidths,
    fullDiffColumnWidths: fullDiffColumnWidths ?? this.fullDiffColumnWidths,
    fullDiffPreferences: fullDiffPreferences ?? this.fullDiffPreferences,
    laneColors: laneColors ?? this.laneColors,
    previewWidth: previewWidth ?? this.previewWidth,
    previewHeight: previewHeight ?? this.previewHeight,
  );

  factory AppSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const AppSettings();
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
      previewPlacement: switch (value['previewPlacement']) {
        'bottom' => PreviewPlacement.bottom,
        'left' => PreviewPlacement.left,
        _ => PreviewPlacement.right,
      },
      columnWidths: TimelineColumnWidths.fromJson(value['columnWidths']),
      fullDiffColumnWidths: FullDiffColumnWidths.fromJson(
        value['fullDiffColumnWidths'],
      ),
      fullDiffPreferences: FullDiffPreferences.fromJson(
        value['fullDiffPreferences'],
      ),
      laneColors: valid ? laneColors : defaultLaneColors,
      previewWidth: _clamped(value['previewWidth'], 288, 240, 560),
      previewHeight: _clamped(value['previewHeight'], 280, 200, 480),
    );
  }

  Map<String, Object> toJson() => {
    'showAvatars': showAvatars,
    'previewPlacement': previewPlacement.name,
    'columnWidths': columnWidths.toJson(),
    'fullDiffColumnWidths': fullDiffColumnWidths.toJson(),
    'fullDiffPreferences': fullDiffPreferences.toJson(),
    'laneColors': laneColors,
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      showAvatars == other.showAvatars &&
      previewPlacement == other.previewPlacement &&
      columnWidths == other.columnWidths &&
      fullDiffColumnWidths == other.fullDiffColumnWidths &&
      fullDiffPreferences == other.fullDiffPreferences &&
      listEquals(laneColors, other.laneColors) &&
      previewWidth == other.previewWidth &&
      previewHeight == other.previewHeight;

  @override
  int get hashCode => Object.hash(
    showAvatars,
    previewPlacement,
    columnWidths,
    fullDiffColumnWidths,
    fullDiffPreferences,
    Object.hashAll(laneColors),
    previewWidth,
    previewHeight,
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
  late final _laneFields = [
    for (final hex in _settings.laneColors) TextEditingController(text: hex),
  ];

  @override
  void dispose() {
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

  void _resetLaneColors() {
    _change(_settings.copyWith(laneColors: AppSettings.defaultLaneColors));
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
                child: Container(
                  key: const Key('settings-git-integrations'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF263246),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 15,
                        color: Color(0xFF7AD6E8),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Git integrations',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFE8EAF2),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFF343946)),
              Expanded(
                child: SingleChildScrollView(
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
                          style: TextStyle(
                            color: Color(0xFF8D94A8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _connection(),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          key: const Key('show-avatars-toggle'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Show commit avatars',
                            style: TextStyle(
                              color: Color(0xFFE8EAF2),
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            'GitHub and GHE only. Gravatar is never queried.',
                            style: TextStyle(
                              color: Color(0xFF8D94A8),
                              fontSize: 11,
                            ),
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
                            _AvatarPreview(
                              label: 'Single',
                              kind: _PreviewKind.single,
                            ),
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
                ),
              ),
            ],
          ),
        ),
      ],
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
      // The mainline is always white and not part of the editable palette.
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              key: const Key('lane-swatch-main'),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AvatarService.branchColor(0),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Main line (fixed)',
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
