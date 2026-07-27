import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_hunk_view.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';

import 'full_diff_fixtures.dart';

final qaCommits = <GitCommit>[
  _qaCommit(
    sha: '2db06c0',
    parent: '1bb13e9',
    subject: 'Persist manually resized window dimensions',
    daysAgo: 15,
  ),
  _qaCommit(
    sha: '40aff6d',
    parent: '62874a0',
    subject: 'Make Retina windows pixel-aware',
    daysAgo: 16,
  ),
  _qaCommit(
    sha: '65f4c80',
    parent: 'c78b2ff',
    subject: 'Use pixel dimensions for Retina windows',
    daysAgo: 16,
  ),
  _qaCommit(
    sha: '1aaf1bd',
    parent: '91f7c63',
    subject: 'Port Android mobile gameplay controls',
    daysAgo: 18,
  ),
];

const qaFiles = <GitFileChange>[
  GitFileChange(
    path: 'src/drlua.pas',
    status: 'M',
    additions: 12,
    deletions: 4,
  ),
  GitFileChange(
    path: 'src/window_sdl.pas',
    status: 'M',
    additions: 9,
    deletions: 3,
  ),
  GitFileChange(
    path: 'macos/retina.pas',
    status: 'A',
    additions: 13,
    deletions: 0,
  ),
  GitFileChange(
    path: 'macos/legacy_scale.pas',
    status: 'D',
    additions: 0,
    deletions: 5,
  ),
];

const qaPatchLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -292,5 +292,6 @@ State.Init'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure TDRLState.Init;',
    oldNumber: 292,
    newNumber: 292,
  ),
  DiffLine(
    kind: DiffLineKind.delete,
    text: "  LuaSystem.Get('VERSION_MODULE');",
    oldNumber: 294,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: "    LuaSystem.Get('VERSION_MODULE');",
    newNumber: 294,
  ),
  DiffLine(kind: DiffLineKind.add, text: '  Result := 0;', newNumber: 295),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 296,
    newNumber: 296,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -312,5 +312,5 @@ SetupBase'),
  DiffLine(
    kind: DiffLineKind.context,
    text: "VersionModuleSave := LuaSystem.Get('VERSION_MODULE_SAVE');",
    oldNumber: 309,
    newNumber: 309,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'DemoVersion := False;',
    oldNumber: 310,
    newNumber: 310,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: "    if LuaSystem.RawDefined('DEMO') then",
    oldNumber: 311,
    newNumber: 311,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: "Log(LOGINFO, 'BASE MODULE VERSION: ' + VersionModule);",
    newNumber: 313,
  ),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'Scale := WindowScale;',
    oldNumber: 313,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'Scale := WindowPixelRatio;',
    newNumber: 314,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 314,
    newNumber: 315,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: '',
    oldNumber: 315,
    newNumber: 316,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'begin',
    oldNumber: 316,
    newNumber: 317,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: "VersionModule := '';",
    oldNumber: 317,
    newNumber: 318,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: "VersionModuleSave := '';",
    oldNumber: 318,
    newNumber: 319,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -318,5 +318,5 @@ LoadCurrent'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure LoadCurrent;',
    oldNumber: 318,
    newNumber: 318,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowWidth := SavedPixelWidth;',
    newNumber: 320,
  ),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'WindowWidth := SavedWidth;',
    oldNumber: 320,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowHeight := SavedPixelHeight;',
    newNumber: 321,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 322,
    newNumber: 322,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -344,6 +344,6 @@ CreateWindow'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure CreateWindow;',
    oldNumber: 344,
    newNumber: 344,
  ),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'WindowWidth := SavedWidth;',
    oldNumber: 347,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowWidth := SavedPixelWidth;',
    newNumber: 347,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowHeight := SavedPixelHeight;',
    newNumber: 348,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 349,
    newNumber: 349,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -371,5 +371,5 @@ ResizeWindow'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure ResizeWindow;',
    oldNumber: 371,
    newNumber: 371,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'PixelWidth := Round(Width * WindowPixelRatio);',
    newNumber: 373,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'PixelHeight := Round(Height * WindowPixelRatio);',
    newNumber: 374,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 375,
    newNumber: 375,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -402,5 +402,5 @@ SaveWindow'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure SaveWindow;',
    oldNumber: 402,
    newNumber: 402,
  ),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'WindowData.Width := WindowWidth;',
    oldNumber: 404,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowData.Width := WindowPixelWidth;',
    newNumber: 404,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowData.Height := WindowPixelHeight;',
    newNumber: 405,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 406,
    newNumber: 406,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -438,4 +438,4 @@ Finalize'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'procedure Finalize;',
    oldNumber: 438,
    newNumber: 438,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'WindowPixelRatio := 1.0;',
    newNumber: 440,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'end;',
    oldNumber: 441,
    newNumber: 441,
  ),
];

final qaWhitespacePatchLines = List<DiffLine>.unmodifiable(
  qaPatchLines.where(
    (line) =>
        line.text != "  LuaSystem.Get('VERSION_MODULE');" &&
        line.text != "    LuaSystem.Get('VERSION_MODULE');",
  ),
);

final Uint8List qaFileBytes = Uint8List.fromList(
  utf8.encode('${_qaSourceLines().join('\n')}\n'),
);

final qaBlameLines = List<GitBlameLine>.generate(450, (index) {
  final lineNumber = index + 1;
  final changed =
      lineNumber == 294 ||
      lineNumber == 295 ||
      lineNumber == 313 ||
      lineNumber == 314;
  return GitBlameLine(
    lineNumber: lineNumber,
    sha: changed ? '40aff6d' : 'a8eda6d',
    author: changed ? 'Suwon Chae' : 'epyon',
    uncommitted: false,
  );
}, growable: false);

final qaHistoryRecords = <GitFileHistoryRecord>[
  GitFileHistoryRecord(
    commit: qaCommits[1],
    path: 'src/drlua.pas',
    oldPath: null,
    status: 'M',
  ),
  GitFileHistoryRecord(
    commit: qaCommits[2],
    path: 'src/drlua.pas',
    oldPath: null,
    status: 'M',
  ),
  GitFileHistoryRecord(
    commit: _qaCommit(
      sha: 'c78b2ff',
      parent: '91f7c63',
      subject: 'Fix held diagonal arrow movement',
      daysAgo: 22,
    ),
    path: 'src/drlua.pas',
    oldPath: null,
    status: 'M',
  ),
  GitFileHistoryRecord(
    commit: _qaCommit(
      sha: '91f7c63',
      parent: '23f84da',
      subject:
          'Merge branch '
          'hotfix/0_10_9a'
          '',
      daysAgo: 32,
      author: const GitIdentity(name: 'epyon', email: 'epyon@example.com'),
    ),
    path: 'src/drlua.pas',
    oldPath: null,
    status: 'M',
  ),
];

Future<void> loadFullDiffQaFonts() async {
  final materialFonts = _flutterMaterialFontsDirectory();
  final appleKorean = File('/System/Library/Fonts/AppleSDGothicNeo.ttc');
  final menlo = File('/System/Library/Fonts/Menlo.ttc');
  final uiFontLoader = FontLoader('Roboto')
    ..addFont(_fontData('${materialFonts.path}/Roboto-Regular.ttf'))
    ..addFont(_fontData('${materialFonts.path}/Roboto-Bold.ttf'));
  if (appleKorean.existsSync()) {
    uiFontLoader.addFont(_fontData(appleKorean.path));
  }
  await uiFontLoader.load();
  await (FontLoader('MaterialIcons')
        ..addFont(_fontData('${materialFonts.path}/MaterialIcons-Regular.otf')))
      .load();
  final menloLoader = FontLoader('Menlo');
  if (menlo.existsSync()) {
    menloLoader.addFont(_fontData(menlo.path));
  } else {
    menloLoader.addFont(_fontData('assets/fonts/D2Coding.ttf'));
  }
  await menloLoader.load();
  await (FontLoader('D2Coding')
        ..addFont(_fontData('assets/fonts/D2Coding.ttf'))
        ..addFont(_fontData('assets/fonts/D2Coding-Bold.ttf')))
      .load();
  if (appleKorean.existsSync()) {
    await (FontLoader('AppleSDGothicNeo')
          ..addFont(_fontData(appleKorean.path))
          ..addFont(_fontData('${materialFonts.path}/Roboto-Bold.ttf'))
          ..addFont(_fontData('assets/fonts/D2Coding-Bold.ttf')))
        .load();
  }
}

ThemeData fullDiffQaTheme() => ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'AppleSDGothicNeo',
  fontFamilyFallback: const ['Roboto', 'D2Coding'],
);

Future<FullDiffSessionController> qaControllerFor({
  FullDiffView view = FullDiffView.diff,
  DiffPresentation presentation = DiffPresentation.hunk,
  bool focusMode = false,
  bool ignoreWhitespace = false,
  bool wrapLines = false,
  int activeHunkIndex = 1,
  DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
}) async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => qaFiles)
    ..diff = ((_, _, _, _, whitespace) async =>
        whitespace ? qaWhitespacePatchLines : qaPatchLines)
    ..content = ((_, _, _) async => qaFileBytes)
    ..blame = ((_, _, _, _) async => qaBlameLines)
    ..history = ((_, _) async => qaHistoryRecords);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: qaCommits,
    initialIndex: 1,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  controller
    ..setView(view)
    ..setPresentation(presentation)
    ..setFocusMode(focusMode)
    ..setWrapLines(wrapLines);
  if (ignoreWhitespace) await controller.setIgnoreWhitespace(true);
  if (algorithm != DiffAlgorithm.gitSetting) {
    await controller.selectAlgorithm(algorithm);
  }
  await _waitForViewData(controller, view);
  final document = controller.state.patch.data;
  if (document != null && document.hunks.isNotEmpty) {
    controller.selectAnchor(
      document
          .hunks[activeHunkIndex.clamp(0, document.hunks.length - 1)]
          .anchor,
    );
  }
  return controller;
}

class FullDiffQaHarness extends StatelessWidget {
  const FullDiffQaHarness({
    required this.controller,
    this.detailOnly = false,
    this.surfaceSize,
    super.key,
  });

  final FullDiffSessionController controller;
  final bool detailOnly;
  final Size? surfaceSize;

  @override
  Widget build(BuildContext context) {
    final workspace = detailOnly
        ? FullDiffQaDetail(controller: controller)
        : DiffScreen(
            repository: controller.repository,
            commits: controller.state.nearbyCommits,
            initialIndex: 0,
            initialView: FullDiffInitialView.hunk,
            controller: controller,
            columnWidths: _qaColumnWidths(surfaceSize?.width),
            editorEnabledOverride: true,
          );
    final sizedWorkspace = switch ((surfaceSize, detailOnly)) {
      (final Size size, false) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width - 32,
            height: 641,
            child: workspace,
          ),
        ),
      ),
      (final Size size, true) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: size.width, height: 596, child: workspace),
      ),
      _ => workspace,
    };
    return RepaintBoundary(
      key: const Key('full-diff-qa-root'),
      child: ColoredBox(color: fullDiffCanvas, child: sizedWorkspace),
    );
  }
}

class FullDiffQaDetail extends StatefulWidget {
  const FullDiffQaDetail({required this.controller, super.key});

  final FullDiffSessionController controller;

  @override
  State<FullDiffQaDetail> createState() => _FullDiffQaDetailState();
}

class _FullDiffQaDetailState extends State<FullDiffQaDetail> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFraction(double fraction) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(
      _scrollController.position.maxScrollExtent * fraction,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final state = controller.state;
      final patch = state.patch.data ?? DiffDocument.empty;
      final anchorKeys = <String, GlobalKey>{
        for (final hunk in patch.hunks) hunk.anchor.id: GlobalKey(),
      };
      return ClipRRect(
        borderRadius: BorderRadius.circular(fullDiffOuterRadius),
        child: Material(
          color: fullDiffHeader,
          child: Padding(
            padding: const EdgeInsets.all(fullDiffOuterPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlobalDiffToolbar(
                  view: state.view,
                  presentation: state.presentation,
                  activeIndex: state.activeAnchor?.hunkIndex ?? 0,
                  anchorCount: patch.hunks.length,
                  algorithm: state.requestedAlgorithm,
                  ignoreWhitespace: state.requestedIgnoreWhitespace,
                  wrapLines: state.wrapLines,
                  focusMode: state.focusMode,
                  loadingPatch: state.patch.loading,
                  showLeadingControls: false,
                  onPresentationSelected: controller.setPresentation,
                  onPrevious: () => controller.stepAnchor(-1),
                  onNext: () => controller.stepAnchor(1),
                  onAlgorithmSelected: controller.selectAlgorithm,
                  onIgnoreWhitespaceChanged: controller.setIgnoreWhitespace,
                  onWrapLinesChanged: controller.setWrapLines,
                  onFocusModeChanged: controller.setFocusMode,
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: HunkPresentationView(
                          document: patch,
                          activeAnchor: state.activeAnchor,
                          path: state.selectedFile?.path ?? 'src/drlua.pas',
                          wrapLines: state.wrapLines,
                          highlighter: const NoopSyntaxHighlighter(),
                          anchorKeys: anchorKeys,
                          controller: _scrollController,
                        ),
                      ),
                      SizedBox(
                        width: fullDiffMinimapWidth,
                        child: FullDiffMinimap(
                          document: patch,
                          activeAnchor: state.activeAnchor,
                          sourceLineCount: patch.sourceLineCount,
                          deletedFile: false,
                          view: state.view,
                          presentation: state.presentation,
                          scrollController: _scrollController,
                          onAnchorSelected: controller.selectAnchor,
                          onScrollFractionChanged: _scrollToFraction,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

FullDiffColumnWidths _qaColumnWidths(double? surfaceWidth) {
  if (surfaceWidth == null || surfaceWidth <= 650) {
    return const FullDiffColumnWidths();
  }
  final mainWidth = surfaceWidth - 56;
  final unit = mainWidth / 6.02;
  return FullDiffColumnWidths(
    commits: math.max(FullDiffColumnWidths.minCommits, unit * 0.82),
    files: math.max(FullDiffColumnWidths.minFiles, unit),
  );
}

GitCommit _qaCommit({
  required String sha,
  required String parent,
  required String subject,
  required int daysAgo,
  GitIdentity author = fixtureIdentity,
}) {
  final timestamp =
      DateTime.now()
          .subtract(Duration(days: daysAgo, hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return GitCommit(
    sha: sha,
    shortSha: sha,
    parents: [parent],
    author: author,
    authorTimestamp: timestamp,
    committer: author,
    committerTimestamp: timestamp,
    refs: const [],
    subject: subject,
  );
}

List<String> _qaSourceLines() {
  final lines = List<String>.generate(
    450,
    (index) => '  // drlua source line ${index + 1}',
  );
  void set(int number, String text) => lines[number - 1] = text;
  set(292, 'procedure TDRLState.Init;');
  set(293, 'begin');
  set(294, "    LuaSystem.Get('VERSION_MODULE');");
  set(295, '  Result := 0;');
  set(296, 'end;');
  set(309, "VersionModuleSave := LuaSystem.Get('VERSION_MODULE_SAVE');");
  set(310, 'DemoVersion := False;');
  set(311, "    if LuaSystem.RawDefined('DEMO') then");
  set(312, 'procedure SetupBase;');
  set(313, "Log(LOGINFO, 'BASE MODULE VERSION: ' + VersionModule);");
  set(314, 'Scale := WindowPixelRatio;');
  set(315, 'end;');
  set(316, '');
  set(317, 'begin');
  set(318, "VersionModule := '';");
  set(319, "VersionModuleSave := '';");
  set(320, 'WindowWidth := SavedPixelWidth;');
  set(321, 'WindowHeight := SavedPixelHeight;');
  set(322, 'end;');
  set(344, 'procedure CreateWindow;');
  set(347, 'WindowWidth := SavedPixelWidth;');
  set(348, 'WindowHeight := SavedPixelHeight;');
  set(349, 'end;');
  set(371, 'procedure ResizeWindow;');
  set(373, 'PixelWidth := Round(Width * WindowPixelRatio);');
  set(374, 'PixelHeight := Round(Height * WindowPixelRatio);');
  set(375, 'end;');
  set(402, 'procedure SaveWindow;');
  set(404, 'WindowData.Width := WindowPixelWidth;');
  set(405, 'WindowData.Height := WindowPixelHeight;');
  set(406, 'end;');
  set(438, 'procedure Finalize;');
  set(440, 'WindowPixelRatio := 1.0;');
  set(441, 'end;');
  return lines;
}

Future<void> _waitForViewData(
  FullDiffSessionController controller,
  FullDiffView view,
) async {
  bool ready() => switch (view) {
    FullDiffView.blame =>
      !controller.state.blame.loading && controller.state.blame.data != null,
    FullDiffView.history =>
      !controller.state.history.loading &&
          controller.state.history.data != null,
    _ => true,
  };

  Object? error() => switch (view) {
    FullDiffView.blame => controller.state.blame.error,
    FullDiffView.history => controller.state.history.error,
    _ => null,
  };

  if (ready()) return;
  final completer = Completer<void>();
  void handleChange() {
    if (!completer.isCompleted && (ready() || error() != null)) {
      completer.complete();
    }
  }

  controller.addListener(handleChange);
  try {
    handleChange();
    await completer.future;
  } finally {
    controller.removeListener(handleChange);
  }
  if (error() case final failure?) {
    throw StateError('QA data did not load for $view: $failure');
  }
}

Directory _flutterMaterialFontsDirectory() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final directory = Directory(
      '$configuredRoot/bin/cache/artifacts/material_fonts',
    );
    if (directory.existsSync()) return directory;
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = Directory(
      '${directory.path}/bin/cache/artifacts/material_fonts',
    );
    if (candidate.existsSync()) return candidate;
    directory = directory.parent;
  }
  throw StateError('Cannot locate Flutter material fonts');
}

Future<ByteData> _fontData(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());
