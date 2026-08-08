import 'dart:async';

import 'package:flutter/material.dart';

import 'avatars.dart';
import 'external_editor.dart';
import 'full_diff_commit_message_cache.dart';
import 'full_diff_controller.dart';
import 'full_diff_header.dart';
import 'full_diff_model.dart';
import 'full_diff_selectable_row.dart';
import 'full_diff_theme.dart';
import 'full_diff_workspace.dart';
import 'git.dart';
import 'monaco_editor_screen.dart';
import 'settings.dart';
import 'typography.dart';

// The scroll controller stayed reachable here when the workspace moved out.
export 'full_diff_workspace.dart' show FullDiffScrollController;

/// Full-diff route: the file list of the selected commit beside a
/// [FullDiffWorkspace] that draws everything else.
///
/// Rebuilding an owned session with new [repository] or [commits] replaces that
/// session. Changing [controller] swaps the workspace's subscription, while an
/// injected controller remains externally owned and authoritative for its
/// session.
class DiffScreen extends StatefulWidget {
  const DiffScreen({
    required this.repository,
    required this.commits,
    required this.initialIndex,
    this.initialPreferences = const FullDiffPreferences(),
    this.controller,
    this.columnWidths = const FullDiffColumnWidths(),
    this.onColumnWidthsChanged,
    this.onPreferencesChanged,
    this.editorService,
    this.editorForTesting,
    this.documentLoaderForTesting,
    this.avatarService,
    this.commitMessageCache,
    this.showRemoteAvatars = true,
    super.key,
  });

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final int initialIndex;
  final FullDiffPreferences initialPreferences;
  final FullDiffSessionController? controller;
  final FullDiffColumnWidths columnWidths;
  final ValueChanged<FullDiffColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffPreferences>? onPreferencesChanged;
  final ExternalEditorService? editorService;

  @visibleForTesting
  final Widget? editorForTesting;

  @visibleForTesting
  final Future<WorkingTreeTextDocument> Function(String relativePath)?
  documentLoaderForTesting;
  final AvatarService? avatarService;
  final FullDiffCommitMessageCache? commitMessageCache;
  final bool showRemoteAvatars;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late FullDiffSessionController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = _newController();
    if (_ownsController) unawaited(_controller.initialize());
  }

  FullDiffSessionController _newController() {
    _ownsController = widget.controller == null;
    return widget.controller ??
        FullDiffSessionController(
          repository: widget.repository,
          commits: widget.commits,
          initialIndex: widget.initialIndex,
          initialPreferences: widget.initialPreferences,
        );
  }

  @override
  void didUpdateWidget(covariant DiffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    final ownedInputsChanged =
        widget.controller == null &&
        oldWidget.controller == null &&
        (!identical(widget.repository, oldWidget.repository) ||
            !identical(widget.commits, oldWidget.commits) ||
            widget.initialIndex != oldWidget.initialIndex);
    if (!controllerChanged && !ownedInputsChanged) return;

    if (_ownsController) _controller.dispose();
    _controller = _newController();
    if (_ownsController) unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: fullDiffCanvas,
    body: FullDiffWorkspace(
      controller: _controller,
      onBack: () => Navigator.of(context).maybePop(),
      navigationPane: (slot) => _commitFiles(_controller.state, slot),
      columnWidths: widget.columnWidths,
      onColumnWidthsChanged: widget.onColumnWidthsChanged,
      onPreferencesChanged: widget.onPreferencesChanged,
      editorService: widget.editorService,
      editorForTesting: widget.editorForTesting,
      documentLoaderForTesting: widget.documentLoaderForTesting,
      avatarService: widget.avatarService,
      commitMessageCache: widget.commitMessageCache,
      showRemoteAvatars: widget.showRemoteAvatars,
    ),
  );

  Widget _commitFiles(
    FullDiffSessionState state,
    FullDiffNavigationPaneSlot slot,
  ) {
    final commit = state.selectedCommit;
    return ColoredBox(
      color: fullDiffCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (commit.parents.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: DropdownButton<String>(
                key: const Key('merge-parent-chooser'),
                isExpanded: true,
                value: state.parent,
                items: [
                  for (var index = 0; index < commit.parents.length; index++)
                    DropdownMenuItem(
                      value: commit.parents[index],
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Parent ${index + 1} · '),
                            TextSpan(
                              text: _shortSha(commit.parents[index]),
                              style: technicalTextStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                onChanged: (parent) {
                  if (parent != null && parent != state.parent) {
                    unawaited(_controller.selectParent(parent));
                  }
                },
              ),
            ),
          _sectionHeader(
            LayoutBuilder(
              builder: (context, constraints) {
                final summary =
                    '${state.files.length} files · '
                    '+${state.files.fold<int>(0, (sum, file) => sum + (file.additions ?? 0))} '
                    '−${state.files.fold<int>(0, (sum, file) => sum + (file.deletions ?? 0))}';
                final narrow = constraints.maxWidth <= 140;
                return Row(
                  children: [
                    if (narrow)
                      const SizedBox(
                        width: 28,
                        child: Text('변경 파일', maxLines: 2),
                      )
                    else
                      const Expanded(
                        child: Text(
                          '변경 파일',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: technicalTextStyle.copyWith(
                          color: fullDiffMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: Focus(
              key: const Key('changed-files-focus'),
              focusNode: slot.filesFocus,
              onKeyEvent: slot.onFilesKey,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SelectionArea(
                      child: ListView.builder(
                        key: const Key('changed-files-list'),
                        itemCount: state.files.length,
                        itemBuilder: (context, index) {
                          final file = state.files[index];
                          final selected =
                              file.path == state.selectedFile?.path;
                          return Semantics(
                            selected: selected,
                            button: true,
                            child: InkWell(
                              onTap: () {
                                slot.filesFocus.requestFocus();
                                if (!selected) {
                                  unawaited(_controller.selectFile(file));
                                }
                              },
                              child: ListenableBuilder(
                                listenable: slot.detailFocus,
                                builder: (context, _) => FullDiffSelectableRowSurface(
                                  key: selected
                                      ? Key('selected-file-${file.path}')
                                      : null,
                                  selected: selected,
                                  focused:
                                      selected &&
                                      switch (state.view) {
                                        FullDiffView.history =>
                                          !slot.historyFocus.hasFocus,
                                        FullDiffView.blame =>
                                          !slot.blameFocus.hasFocus,
                                        FullDiffView.diff => true,
                                      },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          child: Text(
                                            _statusLetter(file.status),
                                            style: const TextStyle(fontSize: 9),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                file.path,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      technicalFontFamily,
                                                  fontFamilyFallback:
                                                      technicalFontFallback,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '+${file.additions ?? '—'} '
                                                '−${file.deletions ?? '—'} · '
                                                '${formatByteSize(file.sizeBytes)}',
                                                style: technicalTextStyle
                                                    .copyWith(
                                                      color: fullDiffMuted,
                                                      fontSize: 12,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (state.filesResource.loading)
                    const Center(
                      child: SizedBox.square(
                        key: Key('diff-pending-files'),
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (!state.filesResource.loading &&
                      state.filesResource.error != null)
                    Center(
                      key: const Key('files-error'),
                      child: Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.filesResource.error.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: fullDiffDeletedMark,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                key: const Key('files-retry'),
                                onPressed: () =>
                                    unawaited(_controller.retryFiles()),
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!state.filesResource.loading &&
                      state.filesResource.error == null &&
                      state.filesResource.data?.isEmpty == true)
                    const Center(
                      key: Key('files-empty'),
                      child: Text(
                        '변경된 파일이 없습니다',
                        style: TextStyle(color: fullDiffMuted, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      color: fullDiffHeader,
      border: Border(bottom: BorderSide(color: fullDiffDivider)),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      child: child,
    ),
  );
}

String _statusLetter(String status) =>
    status.characters.isEmpty ? '' : status.characters.first;

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
