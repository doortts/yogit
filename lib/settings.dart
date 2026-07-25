import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'avatars.dart';
import 'git.dart';
import 'window_frame.dart';

class TimelineColumnWidths {
  const TimelineColumnWidths({
    this.refs = 156,
    this.graph,
    this.hash = 78,
    this.commit,
    this.time = 116,
    this.name = 100,
  });

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

  /// [graph] and [commit] only widen: pass a value to pin the column, and use
  /// `TimelineColumnWidths(...)` directly to clear it back to auto.
  TimelineColumnWidths copyWith({
    double? refs,
    double? graph,
    double? hash,
    double? commit,
    double? time,
    double? name,
  }) => TimelineColumnWidths(
    refs: refs ?? this.refs,
    graph: graph ?? this.graph,
    hash: hash ?? this.hash,
    commit: commit ?? this.commit,
    time: time ?? this.time,
    name: name ?? this.name,
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
      refs: width('refs', 156, 110, 240),
      graph: json['graph'] is num ? width('graph', 142, 96, 260) : null,
      hash: width('hash', 78, 64, 120),
      commit: json['commit'] is num ? width('commit', 380, 140, 620) : null,
      time: width('time', 116, 112, 170),
      name: width('name', 100, 88, 180),
    );
  }

  Map<String, double> toJson() => {
    'refs': refs,
    'graph': ?graph,
    'hash': hash,
    'commit': ?commit,
    'time': time,
    'name': name,
  };

  @override
  bool operator ==(Object other) =>
      other is TimelineColumnWidths &&
      refs == other.refs &&
      graph == other.graph &&
      hash == other.hash &&
      commit == other.commit &&
      time == other.time &&
      name == other.name;

  @override
  int get hashCode => Object.hash(refs, graph, hash, commit, time, name);
}

class AppSettings {
  const AppSettings({
    this.showAvatars = true,
    this.previewPlacement = PreviewPlacement.right,
    this.columnWidths = const TimelineColumnWidths(),
  });

  final bool showAvatars;
  final PreviewPlacement previewPlacement;
  final TimelineColumnWidths columnWidths;

  AppSettings copyWith({
    bool? showAvatars,
    PreviewPlacement? previewPlacement,
    TimelineColumnWidths? columnWidths,
  }) => AppSettings(
    showAvatars: showAvatars ?? this.showAvatars,
    previewPlacement: previewPlacement ?? this.previewPlacement,
    columnWidths: columnWidths ?? this.columnWidths,
  );

  factory AppSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const AppSettings();
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
    );
  }

  Map<String, Object> toJson() => {
    'showAvatars': showAvatars,
    'previewPlacement': previewPlacement.name,
    'columnWidths': columnWidths.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      showAvatars == other.showAvatars &&
      previewPlacement == other.previewPlacement &&
      columnWidths == other.columnWidths;

  @override
  int get hashCode => Object.hash(showAvatars, previewPlacement, columnWidths);
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

  void _change(AppSettings value) {
    setState(() => _settings = value);
    widget.onChanged(value);
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
