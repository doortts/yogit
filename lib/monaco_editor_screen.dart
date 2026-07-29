import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import 'git.dart';

enum TextLineEnding { lf, crlf }

class WorkingTreeTextDocument {
  WorkingTreeTextDocument._({
    required this.file,
    required this.text,
    required this.hasBom,
    required this.lineEnding,
  });

  final File file;
  final String text;
  final bool hasBom;
  final TextLineEnding lineEnding;

  static Future<WorkingTreeTextDocument> load({
    required String repositoryRoot,
    required String relativePath,
  }) async {
    final file = await resolveWorkingTreeFile(repositoryRoot, relativePath);
    final bytes = await file.readAsBytes();
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    final contents = hasBom ? bytes.sublist(3) : bytes;
    if (contents.contains(0)) {
      throw const FormatException('Binary files cannot be opened');
    }
    final decoded = utf8.decode(contents, allowMalformed: false);
    final lineEnding = decoded.contains('\r\n')
        ? TextLineEnding.crlf
        : TextLineEnding.lf;
    return WorkingTreeTextDocument._(
      file: file,
      text: decoded.replaceAll('\r\n', '\n'),
      hasBom: hasBom,
      lineEnding: lineEnding,
    );
  }

  Future<void> save(String value) async {
    if (value.contains('\x00')) {
      throw const FormatException('Binary content cannot be saved');
    }
    final normalized = value.replaceAll('\r\n', '\n');
    final encoded = utf8.encode(
      lineEnding == TextLineEnding.crlf
          ? normalized.replaceAll('\n', '\r\n')
          : normalized,
    );
    await file.writeAsBytes([
      if (hasBom) ...const [0xEF, 0xBB, 0xBF],
      ...encoded,
    ], flush: true);
  }
}

MonacoLanguage monacoLanguageForPath(String path) {
  final name = path.split(Platform.pathSeparator).last.toLowerCase();
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1);
  return switch (extension) {
    'dart' => MonacoLanguage.dart,
    'js' || 'jsx' => MonacoLanguage.javascript,
    'ts' || 'tsx' => MonacoLanguage.typescript,
    'json' => MonacoLanguage.json,
    'md' || 'markdown' => MonacoLanguage.markdown,
    'html' || 'htm' => MonacoLanguage.html,
    'css' => MonacoLanguage.css,
    'scss' => MonacoLanguage.scss,
    'xml' => MonacoLanguage.xml,
    'yaml' || 'yml' => MonacoLanguage.yaml,
    'sh' || 'bash' || 'zsh' => MonacoLanguage.shell,
    'py' => MonacoLanguage.python,
    'rb' => MonacoLanguage.ruby,
    'rs' => MonacoLanguage.rust,
    'go' => MonacoLanguage.go,
    'java' => MonacoLanguage.java,
    'kt' || 'kts' => MonacoLanguage.kotlin,
    'swift' => MonacoLanguage.swift,
    'c' || 'h' => MonacoLanguage.c,
    'cc' || 'cpp' || 'cxx' || 'hpp' => MonacoLanguage.cpp,
    'sql' => MonacoLanguage.sql,
    _ => MonacoLanguage.plaintext,
  };
}

class MonacoEditorScreen extends StatefulWidget {
  const MonacoEditorScreen({
    super.key,
    required this.title,
    required this.initialText,
    required this.language,
    required this.readOnly,
    this.onSave,
    this.onOpenExternal,
    this.editorForTesting,
  });

  final String title;
  final String initialText;
  final MonacoLanguage language;
  final bool readOnly;
  final Future<void> Function(String text)? onSave;
  final Future<void> Function()? onOpenExternal;

  @visibleForTesting
  final Widget? editorForTesting;

  @override
  State<MonacoEditorScreen> createState() => _MonacoEditorScreenState();
}

class _MonacoEditorScreenState extends State<MonacoEditorScreen> {
  MonacoController? _controller;
  MonacoActionRegistration? _saveAction;
  Object? _error;
  var _saving = false;

  Future<void> _save() async {
    if (_saving || widget.readOnly || widget.onSave == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final text = await _controller?.document.getText() ?? widget.initialText;
      await widget.onSave!(text);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _ready(MonacoController controller) {
    _controller = controller;
    if (!widget.readOnly && widget.onSave != null) {
      unawaited(_registerSaveAction(controller));
    }
  }

  Future<void> _registerSaveAction(MonacoController controller) async {
    try {
      final action = await controller.addAction(
        const MonacoActionDescriptor(
          id: MonacoAction('yogit.save'),
          label: 'Save',
          keybindings: [MonacoKeybinding(key: MonacoKey.keyS, ctrlCmd: true)],
        ),
        _save,
      );
      if (!mounted) {
        await action.dispose();
        return;
      }
      _saveAction = action;
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _openExternal() async {
    await Navigator.of(context).maybePop();
    await widget.onOpenExternal?.call();
  }

  @override
  void dispose() {
    final saveAction = _saveAction;
    if (saveAction != null) unawaited(saveAction.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !widget.readOnly && widget.onSave != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('내장 에디터'),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          Center(child: Text(widget.readOnly ? '읽기 전용' : '수정 가능')),
          const SizedBox(width: 12),
          if (widget.onOpenExternal != null)
            TextButton(onPressed: _openExternal, child: const Text('외부 에디터')),
          if (canSave)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '저장 중' : '저장'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                widget.editorForTesting ??
                MonacoEditor(
                  initialText: widget.initialText,
                  options: EditorOptions(
                    language: widget.language,
                    readOnly: widget.readOnly,
                  ),
                  autofocus: true,
                  onReady: _ready,
                  onError: (error, _) {
                    if (mounted) setState(() => _error = error);
                  },
                  errorBuilder: (context, error, _) => Center(
                    child: Text(error.toString(), textAlign: TextAlign.center),
                  ),
                ),
          ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error.toString()),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('닫기'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
