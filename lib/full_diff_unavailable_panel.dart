import 'package:flutter/material.dart';

import 'full_diff_model.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

enum FullDiffUnavailableReason {
  noChanges,
  binary,
  unsupportedEncoding,
  byteLimit,
  lineLimit,
  gitError,
}

class FullDiffUnavailablePanel extends StatelessWidget {
  const FullDiffUnavailablePanel({
    required this.file,
    required this.path,
    required this.reason,
    required this.algorithm,
    required this.ignoreWhitespace,
    this.error,
    this.onRetry,
    super.key,
  });

  final GitFileChange file;
  final String path;
  final FullDiffUnavailableReason reason;
  final DiffAlgorithm algorithm;
  final bool ignoreWhitespace;
  final Object? error;
  final VoidCallback? onRetry;

  String get _attribute => switch (reason) {
    FullDiffUnavailableReason.noChanges => 'UTF-8',
    FullDiffUnavailableReason.binary => 'Binary',
    FullDiffUnavailableReason.unsupportedEncoding => 'Unsupported encoding',
    FullDiffUnavailableReason.byteLimit =>
      '${fullDiffTextByteLimit ~/ (1024 * 1024)} MiB 초과',
    FullDiffUnavailableReason.lineLimit =>
      '${_formatCount(fullDiffTextLineLimit)}줄 초과',
    FullDiffUnavailableReason.gitError => 'Git error',
  };

  String get _message => switch (reason) {
    FullDiffUnavailableReason.noChanges => '현재 옵션으로 표시할 변경이 없습니다.',
    FullDiffUnavailableReason.binary => '바이너리 파일이라 텍스트 diff를 표시할 수 없습니다.',
    FullDiffUnavailableReason.unsupportedEncoding =>
      'UTF-8로 해석할 수 없는 파일이라 텍스트 diff를 표시할 수 없습니다.',
    FullDiffUnavailableReason.byteLimit =>
      '파일이 ${fullDiffTextByteLimit ~/ (1024 * 1024)} MiB 제한을 초과해 내용을 표시하지 않습니다.',
    FullDiffUnavailableReason.lineLimit =>
      '파일이 ${_formatCount(fullDiffTextLineLimit)}줄 제한을 초과해 내용을 표시하지 않습니다.',
    FullDiffUnavailableReason.gitError => 'Git에서 이 파일의 변경 내용을 읽지 못했습니다.',
  };

  @override
  Widget build(BuildContext context) {
    const technical = technicalTextStyle;
    final showRetry =
        reason == FullDiffUnavailableReason.gitError && onRetry != null;
    return Center(
      key: const Key('full-diff-unavailable'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          container: true,
          child: SelectionArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    path,
                    textAlign: TextAlign.center,
                    style: technical.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fileSummary(file),
                    style: technical.copyWith(
                      color: fullDiffAccent,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: fullDiffChip,
                      borderRadius: BorderRadius.circular(fullDiffChipRadius),
                    ),
                    child: Text(
                      _attribute,
                      style: technical.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: fullDiffMuted, fontSize: 10),
                  ),
                  if (reason == FullDiffUnavailableReason.noChanges) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${algorithm.label} · '
                      '${ignoreWhitespace ? '공백 무시' : '공백 포함'}',
                      textAlign: TextAlign.center,
                      style: technical.copyWith(
                        color: fullDiffMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (reason == FullDiffUnavailableReason.gitError &&
                      error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: technical.copyWith(
                        color: fullDiffDeletedMark,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (showRetry) ...[
                    const SizedBox(height: 10),
                    TextButton(onPressed: onRetry, child: const Text('다시 시도')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _fileSummary(GitFileChange file) =>
    '${file.status.characters.first} · '
    '+${file.additions ?? '—'} −${file.deletions ?? '—'}';

String _formatCount(int value) {
  final digits = value.toString();
  final firstGroup = digits.length % 3;
  final parts = <String>[];
  if (firstGroup != 0) parts.add(digits.substring(0, firstGroup));
  for (var index = firstGroup; index < digits.length; index += 3) {
    parts.add(digits.substring(index, index + 3));
  }
  return parts.join(',');
}
