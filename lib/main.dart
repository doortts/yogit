import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'avatars.dart';
import 'git.dart';
import 'github_api.dart';
import 'github_auth.dart';
import 'monitor_screen.dart';
import 'pr_monitor.dart';
import 'settings.dart';
import 'timeline.dart';
import 'timeline_theme.dart';
import 'window_frame.dart';
import 'typography.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final launch = launchOptionsFromArgs(args);
    if (launch.monitorBranch case final branch?) {
      runApp(
        MonitorBootstrap(
          requestedPath: launch.repositoryPath,
          branch: branch,
          gitExecutable: launch.gitExecutable,
        ),
      );
      return;
    }
    runApp(
      YogitBootstrap(
        requestedPath: launch.repositoryPath,
        gitExecutable: launch.gitExecutable,
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
    this.monitorBranch,
  });

  final String repositoryPath;
  final String gitExecutable;

  /// When set, this instance is a monitor window for the branch, not a
  /// timeline.
  final String? monitorBranch;
}

LaunchOptions launchOptionsFromArgs(List<String> args) {
  final suppliedGit = _optionValue(args, '--git');
  return LaunchOptions(
    repositoryPath: repositoryPathFromArgs(args),
    gitExecutable: suppliedGit == null
        ? resolveExecutable('git')
        : _validatedExecutable('--git', suppliedGit),
    monitorBranch: _optionValue(args, '--monitor'),
  );
}

/// The `.app` bundle this instance runs from, or null outside one — a dev run
/// or a test has no bundle to relaunch or to open.
String? appBundlePath() {
  final segments = Platform.resolvedExecutable.split('/');
  final index = segments.lastIndexWhere((segment) => segment.endsWith('.app'));
  return index < 0 ? null : segments.sublist(0, index + 1).join('/');
}

/// Which GitHub server answers for [host]: the one the user selected when the
/// remote lives on it, and the host's own endpoint otherwise. A monitored
/// repository is not always on the selected server.
String apiBaseUrlForHost(String host, AppSettings settings) {
  final derived = githubApiBaseUrl(host);
  return Uri.parse(settings.githubApiBaseUrl).host == Uri.parse(derived).host
      ? settings.githubApiBaseUrl
      : derived;
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

/// Boots a monitor window: resolve the root, find the origin remote, then
/// hand everything to [MonitorScreen]. Failures explain themselves in place —
/// this window has no timeline to fall back to.
class MonitorBootstrap extends StatefulWidget {
  const MonitorBootstrap({
    required this.requestedPath,
    required this.branch,
    required this.gitExecutable,
    this.runner = runProcess,
    this.settingsStore,
    this.windowFrameController,
    super.key,
  });

  final String requestedPath;
  final String branch;
  final String gitExecutable;
  final CommandRunner runner;

  /// Where the selected GitHub server comes from; the real file by default.
  final SettingsStore? settingsStore;
  final WindowFrameController? windowFrameController;

  @override
  State<MonitorBootstrap> createState() => _MonitorBootstrapState();
}

class _MonitorBootstrapState extends State<MonitorBootstrap> {
  late final WindowFrameController _controller =
      widget.windowFrameController ?? WindowFrameController();
  late final Future<
    ({
      GitRepository repository,
      RemoteRepository? remote,
      String root,
      String apiBaseUrl,
      String? token,
    })
  >
  _boot = _resolve();

  Future<
    ({
      GitRepository repository,
      RemoteRepository? remote,
      String root,
      String apiBaseUrl,
      String? token,
    })
  >
  _resolve() async {
    final root = await resolveRepositoryRoot(
      widget.requestedPath,
      gitExecutable: widget.gitExecutable,
      runner: widget.runner,
    );
    final repository = GitRepository(
      root,
      gitExecutable: widget.gitExecutable,
      runner: widget.runner,
    );
    final url = await repository.loadOriginUrl();
    final remote = url == null ? null : RemoteRepository.tryParse(url);
    final settings = await (widget.settingsStore ?? SettingsStore()).load();
    // With no remote there is no host to derive a server from, so the token
    // question falls back to the selected one; the notice for a missing origin
    // comes right after the one for a missing login either way.
    final apiBaseUrl = remote == null
        ? settings.githubApiBaseUrl
        : apiBaseUrlForHost(remote.host, settings);
    return (
      repository: repository,
      remote: remote,
      root: root,
      apiBaseUrl: apiBaseUrl,
      // Read here so build() stays synchronous.
      token: await GithubTokenStore(runner: widget.runner).read(apiBaseUrl),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'yogit 모니터링',
    debugShowCheckedModeBanner: false,
    theme: timelineThemeData(yogitTheme(), TimelineThemeKind.systemGraphite),
    home: FutureBuilder(
      future: _boot,
      builder: (context, snapshot) {
        // Every branch below is wrapped: a monitor window without controls
        // is a window the user cannot close.
        if (snapshot.hasError) {
          return _monitorNotice('Git 저장소가 아닙니다: ${widget.requestedPath}');
        }
        final boot = snapshot.data;
        if (boot == null) {
          return _monitorWindow(
            const Scaffold(body: Center(child: CircularProgressIndicator())),
            zoomOnEntry: false,
          );
        }
        if (boot.token?.isNotEmpty != true) {
          return _monitorNotice(
            'GitHub 연결이 필요합니다 — 설정에서 서버에 로그인하세요.',
            openBundle: appBundlePath(),
          );
        }
        final remote = boot.remote;
        if (remote == null) {
          return _monitorNotice('origin 원격을 찾을 수 없어 PR을 읽을 수 없습니다.');
        }
        return _monitorWindow(
          MonitorScreen(
            repository: boot.repository,
            branch: widget.branch,
            repositoryName: boot.root.split('/').last,
            service: PrMonitorService(
              remote: remote,
              monitoredBranch: widget.branch,
              api: GitHubApi(apiBaseUrl: boot.apiBaseUrl, token: boot.token!),
            ),
          ),
        );
      },
    ),
  );

  Widget _monitorWindow(Widget child, {bool zoomOnEntry = true}) =>
      MonitorWindow(
        controller: _controller,
        zoomOnEntry: zoomOnEntry,
        child: child,
      );

  /// [openBundle] is the app bundle the 설정 열기 button relaunches; outside a
  /// bundle there is nothing to open, so the button stays away.
  Widget _monitorNotice(String message, {String? openBundle}) => _monitorWindow(
    zoomOnEntry: false,
    Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            if (openBundle != null) ...[
              const SizedBox(height: 12),
              TextButton(
                key: const Key('monitor-open-settings'),
                onPressed: () =>
                    unawaited(widget.runner('/usr/bin/open', [openBundle])),
                child: const Text('설정 열기', style: TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'esc 또는 왼쪽 위 닫기 버튼으로 창을 닫습니다',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class YogitBootstrap extends StatefulWidget {
  const YogitBootstrap({
    required this.requestedPath,
    required this.gitExecutable,
    this.runner = runProcess,
    this.rawRunner = runRawProcess,
    this.windowFrameController,
    super.key,
  });

  final String requestedPath;
  final String gitExecutable;
  final CommandRunner runner;
  final RawCommandRunner rawRunner;
  final WindowFrameController? windowFrameController;

  @override
  State<YogitBootstrap> createState() => _YogitBootstrapState();
}

class _YogitBootstrapState extends State<YogitBootstrap> {
  late final WindowFrameController _windowFrameController =
      widget.windowFrameController ?? WindowFrameController();
  late String _requestedPath = widget.requestedPath;
  late Future<String> _root = _resolve(_requestedPath);

  Future<String> _resolve(String path) => resolveRepositoryRoot(
    path,
    gitExecutable: widget.gitExecutable,
    runner: widget.runner,
  );

  Future<void> _pickRepository() async {
    final path = await _windowFrameController.pickRepository();
    if (path == null || !mounted) return;
    setState(() {
      _requestedPath = path;
      _root = _resolve(path);
    });
  }

  @override
  void dispose() {
    if (widget.windowFrameController == null) {
      _windowFrameController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _root,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _RepositoryError(
          path: _requestedPath,
          detail: snapshot.error.toString(),
          onPickRepository: () => unawaited(_pickRepository()),
        );
      }
      if (snapshot.data case final root?) {
        return YogitApp(
          repository: GitRepository(
            root,
            gitExecutable: widget.gitExecutable,
            runner: widget.runner,
            rawRunner: widget.rawRunner,
          ),
          windowFrameController: _windowFrameController,
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
    // Discovery waits for the settings: which server answers for the origin
    // depends on the one the user selected.
    unawaited(() async {
      await _loadSettings();
      if (_avatarService == null && widget.discoverAvatars) {
        await _discoverAvatarService();
      }
    }());
  }

  Future<void> _loadSettings() async {
    final loaded = await _store.load();
    final settings = loaded.migrateLegacyGraphWidth(_repository.root);
    if (!mounted) return;
    setState(() {
      AvatarService.baseBranchColor = settings.baseBranchColorValue;
      AvatarService.palette = settings.laneColorValues;
      _settings = settings;
      _settingsLoaded = true;
    });
    if (settings != loaded) {
      _save = _save.then((_) => _store.save(settings)).catchError((_) {});
    }
  }

  /// The timeline subtree is keyed by root, so switching repositories remounts
  /// it and every per-repository future reloads.
  void _openRepository(String root) {
    if (root == _repository.root) return;
    final previous = _repository.root;
    setState(() {
      _repository =
          widget.repositoryFactory?.call(root) ??
          GitRepository(root, gitExecutable: widget.repository.gitExecutable);
      _avatarService = widget.avatarService;
    });
    if (widget.avatarService == null && widget.discoverAvatars) {
      unawaited(_discoverAvatarService());
    }
    // The repository being left is only worth remembering now that it is being
    // left, so a launch never has to write to disk just to record itself.
    if (_settingsLoaded) {
      _changeSettings(
        _settings.withRecentRepository(previous).withRecentRepository(root),
      );
    }
  }

  /// No token for the origin's server means no avatars: the REST calls would
  /// only come back 401, and the rows already read fine with initials.
  Future<void> _discoverAvatarService() async {
    final repository = _repository;
    final url = await repository.loadOriginUrl();
    final remote = url == null ? null : RemoteRepository.tryParse(url);
    if (remote == null) return;
    final apiBaseUrl = apiBaseUrlForHost(remote.host, _settings);
    final token = await GithubTokenStore(
      runner: repository.runner,
    ).read(apiBaseUrl);
    if (token == null) return;
    if (mounted && identical(_repository, repository)) {
      setState(
        () => _avatarService = AvatarService(
          remote: remote,
          api: GitHubApi(apiBaseUrl: apiBaseUrl, token: token),
        ),
      );
    }
  }

  void _changeSettings(AppSettings settings) {
    setState(() {
      AvatarService.baseBranchColor = settings.baseBranchColorValue;
      AvatarService.palette = settings.laneColorValues;
      _settings = settings;
      _settingsLoaded = true;
    });
    _save = _save.then((_) => _store.save(settings)).catchError((_) {});
  }

  /// The monitor runs as its own app instance, so it gets a real window of
  /// its own. Outside a bundle (dev runs, tests) there is nothing to launch.
  void _openMonitor(String branch) {
    final bundlePath = appBundlePath();
    if (bundlePath == null) return;
    unawaited(
      _repository.runner('/usr/bin/open', [
        ...monitorLaunchArguments(
          bundlePath: bundlePath,
          root: _repository.root,
          gitExecutable: _repository.gitExecutable,
          branch: branch,
        ),
      ]),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            SettingsScreen(settings: _settings, onChanged: _changeSettings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'yogit',
    debugShowCheckedModeBanner: false,
    theme: yogitTheme(),
    home: Builder(
      builder: (context) => Theme(
        data: timelineThemeData(Theme.of(context), _settings.timelineTheme),
        child: TimelineScreen(
          key: Key('timeline-screen-${_repository.root}'),
          repository: _repository,
          controller: widget.windowFrameController,
          onOpenRepository: _openRepository,
          onOpenMonitor: _openMonitor,
          recentRepositories: _settings
              .withRecentRepository(_repository.root)
              .recentRepositories,
          onForgetRecentRepository: _settingsLoaded
              ? (root) =>
                    _changeSettings(_settings.withoutRecentRepository(root))
              : null,
          avatarService: _avatarService,
          deletedBranchNames:
              _settings.deletedBranchNames[_repository.root] ?? const {},
          deletedBranchNamesReady: _settingsLoaded,
          onDeletedBranchNamesChanged: _settingsLoaded
              ? (names) {
                  final caches = {
                    for (final entry in _settings.deletedBranchNames.entries)
                      entry.key: Map<String, String>.of(entry.value),
                    _repository.root: Map<String, String>.of(names),
                  };
                  _changeSettings(
                    _settings.copyWith(deletedBranchNames: caches),
                  );
                }
              : null,
          hiddenRefs: {...?_settings.hiddenRefs[_repository.root]},
          onHiddenRefsChanged: _settingsLoaded
              ? (refs) => _changeSettings(
                  _settings.copyWith(
                    hiddenRefs: {
                      ..._settings.hiddenRefs,
                      _repository.root: refs.toList()..sort(),
                    },
                  ),
                )
              : null,
          showRemoteAvatars: _settingsLoaded && _settings.showAvatars,
          precisePush: _settings.precisePush,
          preferredPreviewPlacement: _settings.previewPlacement,
          preferredBranch: _settingsLoaded
              ? _settings.baseBranches[_repository.root]
              : null,
          preferredBranchReady: _settingsLoaded,
          columnWidths: _settings.columnWidthsForRepository(_repository.root),
          fullDiffColumnWidths: _settings.fullDiffColumnWidths,
          fullDiffPreferences: _settings.fullDiffPreferences,
          refPalette: _settings.refPalette,
          refPaletteAssignments: _settings.refPaletteAssignments,
          branchPreviewMode: _settings.branchPreviewMode,
          timelineFont: _settings.timelineFont,
          timelineFontSize: _settings.timelineFontSize,
          mergeMessageTemplate: _settings.mergeMessageTemplate,
          rebaseMergeMessageTemplate: _settings.rebaseMergeMessageTemplate,
          previewWidth: _settings.previewWidth,
          previewHeight: _settings.previewHeight,
          previewDiffLeftWidth: _settings.previewDiffLeftWidth,
          previewDiffRightWidth: _settings.previewDiffRightWidth,
          previewDiffBottomHeight: _settings.previewDiffBottomHeight,
          onOpenSettings: _settingsLoaded ? () => _openSettings(context) : null,
          commitProfiles: _settings.commitProfiles,
          onCommitProfilesChanged: _settingsLoaded
              ? (profiles) => _changeSettings(
                  _settings.copyWith(commitProfiles: profiles),
                )
              : null,
          onPreviewPlacementChanged: _settingsLoaded
              ? (placement) => _changeSettings(
                  _settings.copyWith(previewPlacement: placement),
                )
              : null,
          onPreferredBranchChanged: _settingsLoaded
              ? (branch) {
                  final baseBranches = Map<String, String>.of(
                    _settings.baseBranches,
                  )..[_repository.root] = branch;
                  _changeSettings(
                    _settings.copyWith(baseBranches: baseBranches),
                  );
                }
              : null,
          onColumnWidthsChanged: _settingsLoaded
              ? (widths) => _changeSettings(
                  _settings.withRepositoryColumnWidths(
                    _repository.root,
                    widths,
                  ),
                )
              : null,
          onFullDiffColumnWidthsChanged: _settingsLoaded
              ? (widths) => _changeSettings(
                  _settings.copyWith(fullDiffColumnWidths: widths),
                )
              : null,
          onFullDiffPreferencesChanged: _settingsLoaded
              ? (preferences) => _changeSettings(
                  _settings.copyWith(fullDiffPreferences: preferences),
                )
              : null,
          onBranchPreviewModeChanged: _settingsLoaded
              ? (mode) =>
                    _changeSettings(_settings.copyWith(branchPreviewMode: mode))
              : null,
          onPreviewSizeChanged: _settingsLoaded
              ? (size) => _changeSettings(
                  _settings.copyWith(
                    previewWidth: size.width,
                    previewHeight: size.height,
                  ),
                )
              : null,
          onPreviewDiffSizeChanged: _settingsLoaded
              ? (size) => _changeSettings(switch (size.placement) {
                  PreviewPlacement.left => _settings.copyWith(
                    previewDiffLeftWidth: size.extent,
                  ),
                  PreviewPlacement.right => _settings.copyWith(
                    previewDiffRightWidth: size.extent,
                  ),
                  PreviewPlacement.bottom => _settings.copyWith(
                    previewDiffBottomHeight: size.extent,
                  ),
                  PreviewPlacement.closed => _settings,
                })
              : null,
        ),
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
  const _RepositoryError({
    required this.path,
    required this.detail,
    this.onPickRepository,
  });

  final String path;
  final String detail;
  final VoidCallback? onPickRepository;

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
                      fontFamily: technicalFontFamily,
                      fontFamilyFallback: technicalFontFallback,
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
                if (onPickRepository != null) ...[
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    key: const Key('bootstrap-pick-repository'),
                    onPressed: onPickRepository,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('저장소 열기'),
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
