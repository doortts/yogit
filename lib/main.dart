import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'avatars.dart';
import 'git.dart';
import 'settings.dart';
import 'timeline.dart';
import 'window_frame.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final launch = launchOptionsFromArgs(args);
    runApp(
      YogitBootstrap(
        requestedPath: launch.repositoryPath,
        gitExecutable: launch.gitExecutable,
        ghExecutable: launch.ghExecutable,
      ),
    );
  } on FormatException catch (error) {
    runApp(_RepositoryError(path: '', detail: error.message));
  }
}

class LaunchOptions {
  const LaunchOptions({
    required this.repositoryPath,
    required this.gitExecutable,
    this.ghExecutable,
  });

  final String repositoryPath;
  final String gitExecutable;
  final String? ghExecutable;
}

LaunchOptions launchOptionsFromArgs(List<String> args) {
  final suppliedGit = _optionValue(args, '--git');
  final suppliedGh = _optionValue(args, '--gh');
  return LaunchOptions(
    repositoryPath: repositoryPathFromArgs(args),
    gitExecutable: suppliedGit == null
        ? resolveExecutable('git')
        : _validatedExecutable('--git', suppliedGit),
    ghExecutable: suppliedGh == null
        ? resolveOptionalExecutable('gh')
        : _validatedExecutable('--gh', suppliedGh),
  );
}

String repositoryPathFromArgs(List<String> args) =>
    _optionValue(args, '--repo') ?? Directory.current.path;

String? _optionValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0) return null;
  if (index + 1 >= args.length || args[index + 1].trim().isEmpty) {
    throw FormatException('$flag requires a value.');
  }
  return args[index + 1];
}

String _validatedExecutable(String flag, String path) {
  final file = File(path);
  if (!file.isAbsolute || !isExecutableFile(path)) {
    throw FormatException('$flag must be an absolute executable file.');
  }
  return path;
}

class YogitBootstrap extends StatefulWidget {
  const YogitBootstrap({
    required this.requestedPath,
    required this.gitExecutable,
    this.ghExecutable,
    super.key,
  });

  final String requestedPath;
  final String gitExecutable;
  final String? ghExecutable;

  @override
  State<YogitBootstrap> createState() => _YogitBootstrapState();
}

class _YogitBootstrapState extends State<YogitBootstrap> {
  late final Future<String> _root = resolveRepositoryRoot(
    widget.requestedPath,
    gitExecutable: widget.gitExecutable,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _root,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _RepositoryError(
          path: widget.requestedPath,
          detail: snapshot.error.toString(),
        );
      }
      if (snapshot.data case final root?) {
        return YogitApp(
          repository: GitRepository(root, gitExecutable: widget.gitExecutable),
          ghExecutable: widget.ghExecutable,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: yogitTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        ),
      );
    },
  );
}

class YogitApp extends StatefulWidget {
  const YogitApp({
    required this.repository,
    this.settingsStore,
    this.avatarService,
    this.ghExecutable,
    this.discoverAvatars = true,
    this.windowFrameController,
    this.repositoryFactory,
    super.key,
  });

  final GitRepository repository;

  /// Builds the repository the folder picker switched to. Defaults to a real
  /// [GitRepository] on the same git executable.
  final GitRepository Function(String root)? repositoryFactory;
  final SettingsStore? settingsStore;
  final AvatarService? avatarService;
  final String? ghExecutable;
  final bool discoverAvatars;
  final WindowFrameController? windowFrameController;

  @override
  State<YogitApp> createState() => _YogitAppState();
}

class _YogitAppState extends State<YogitApp> {
  late final SettingsStore _store = widget.settingsStore ?? SettingsStore();
  late GitRepository _repository = widget.repository;
  late AvatarService? _avatarService = widget.avatarService;
  var _settings = const AppSettings();
  var _settingsLoaded = false;
  Future<void> _save = Future.value();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    if (_avatarService == null && widget.discoverAvatars) {
      unawaited(_discoverAvatarService());
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _store.load();
    if (mounted) {
      setState(() {
        AvatarService.palette = settings.laneColorValues;
        _settings = settings;
        _settingsLoaded = true;
      });
    }
  }

  /// The timeline subtree is keyed by root, so switching repositories remounts
  /// it and every per-repository future reloads.
  void _openRepository(String root) {
    if (root == _repository.root) return;
    setState(() {
      _repository =
          widget.repositoryFactory?.call(root) ??
          GitRepository(root, gitExecutable: widget.repository.gitExecutable);
      _avatarService = widget.avatarService;
    });
    if (widget.avatarService == null && widget.discoverAvatars) {
      unawaited(_discoverAvatarService());
    }
  }

  Future<void> _discoverAvatarService() async {
    final ghExecutable = widget.ghExecutable;
    if (ghExecutable == null) return;
    final url = await _repository.loadOriginUrl();
    final remote = url == null ? null : RemoteRepository.tryParse(url);
    if (mounted && remote != null) {
      setState(
        () => _avatarService = AvatarService(
          remote: remote,
          ghExecutable: ghExecutable,
        ),
      );
    }
  }

  void _changeSettings(AppSettings settings) {
    setState(() {
      AvatarService.palette = settings.laneColorValues;
      _settings = settings;
      _settingsLoaded = true;
    });
    _save = _save.then((_) => _store.save(settings)).catchError((_) {});
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsScreen(
          settings: _settings,
          avatarService: _avatarService,
          onChanged: _changeSettings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'yogit',
    debugShowCheckedModeBanner: false,
    theme: yogitTheme(),
    home: Builder(
      builder: (context) => TimelineScreen(
        key: Key('timeline-screen-${_repository.root}'),
        repository: _repository,
        controller: widget.windowFrameController,
        onOpenRepository: _openRepository,
        avatarService: _avatarService,
        showRemoteAvatars: _settingsLoaded && _settings.showAvatars,
        preferredPreviewPlacement: _settings.previewPlacement,
        columnWidths: _settings.columnWidths,
        onOpenSettings: _settingsLoaded ? () => _openSettings(context) : null,
        onPreviewPlacementChanged: _settingsLoaded
            ? (placement) => _changeSettings(
                _settings.copyWith(previewPlacement: placement),
              )
            : null,
        onColumnWidthsChanged: _settingsLoaded
            ? (widths) =>
                  _changeSettings(_settings.copyWith(columnWidths: widths))
            : null,
      ),
    ),
  );
}

ThemeData yogitTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF15171E),
  colorScheme: const ColorScheme.dark(
    surface: Color(0xFF1D2029),
    primary: Color(0xFF7AD6E8),
  ),
);

class _RepositoryError extends StatelessWidget {
  const _RepositoryError({required this.path, required this.detail});

  final String path;
  final String detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'yogit',
    debugShowCheckedModeBanner: false,
    theme: yogitTheme(),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFF29AB2),
                  size: 28,
                ),
                const SizedBox(height: 14),
                const Text(
                  'yo는 Git 저장소 안에서 실행해야 합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE8EAF2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (path.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    path,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8D94A8),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8D94A8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
