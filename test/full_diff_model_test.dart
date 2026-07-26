import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

void main() {
  test('groups patch rows into hunks with readable ranges and anchors', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.header, text: 'diff --git a/a.pas b/a.pas'),
      DiffLine(
        kind: DiffLineKind.hunk,
        text: '@@ -10,3 +10,4 @@ procedure ConfigureWindow',
      ),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'begin',
        oldNumber: 10,
        newNumber: 10,
      ),
      DiffLine(kind: DiffLineKind.delete, text: 'Scale := 1;', oldNumber: 11),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'Scale := PixelRatio;',
        newNumber: 11,
      ),
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -40 +41,2 @@'),
      DiffLine(kind: DiffLineKind.add, text: 'Log(Scale);', newNumber: 41),
    ]);

    expect(document.headers.single, startsWith('diff --git'));
    expect(document.hunks, hasLength(2));
    expect(document.hunks.first.rangeLabel, '−10,3  +10,4');
    expect(document.hunks.first.context, 'procedure ConfigureWindow');
    expect(document.hunks.first.anchor.oldLine, 11);
    expect(document.hunks.first.anchor.newLine, 11);
    expect(document.hunks.last.rangeLabel, '−40  +41,2');
    expect(document.rows, hasLength(4));
  });

  test('uses only the old line for a delete-only hunk anchor', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -7,2 +7 @@'),
      DiffLine(
        kind: DiffLineKind.delete,
        text: 'obsolete setting',
        oldNumber: 7,
      ),
    ]);

    expect(document.hunks.single.anchor.oldLine, 7);
    expect(document.hunks.single.anchor.newLine, isNull);
  });

  test('rejects malformed hunk headers', () {
    expect(
      () => DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 + @@'),
      ]),
      throwsFormatException,
    );
  });

  test('derives anchors, split rows, and displayed source length', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,3 +10,4 @@ SetupBase'),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'begin',
        oldNumber: 10,
        newNumber: 10,
      ),
      DiffLine(kind: DiffLineKind.delete, text: 'Scale := 1;', oldNumber: 11),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'Scale := WindowPixelRatio;',
        newNumber: 11,
      ),
      DiffLine(kind: DiffLineKind.add, text: 'Log(Scale);', newNumber: 12),
    ]);

    expect(document.hunks.single.anchor.hunkIndex, 0);
    expect(document.hunks.single.anchor.oldLine, 11);
    expect(document.hunks.single.anchor.newLine, 11);
    expect(document.hunks.single.changedLines, hasLength(3));
    expect(document.splitRows, hasLength(3));
    expect(document.splitRows[1].left?.text, 'Scale := 1;');
    expect(document.splitRows[1].right?.text, 'Scale := WindowPixelRatio;');
    expect(document.sourceLineCount, 12);
  });

  test('classifies bytes without treating unsupported text as binary', () {
    final utf8File = FileDocument.fromBytes(
      revision: 'abc',
      path: 'src/a.pas',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('begin\nend;\n')),
      gitMarkedBinary: false,
    );
    final unsupported = FileDocument.fromBytes(
      revision: 'abc',
      path: 'legacy.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(const [0x80, 0x81]),
      gitMarkedBinary: false,
    );
    final binary = FileDocument.fromBytes(
      revision: 'abc',
      path: 'asset.bin',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(const [0x41, 0x00, 0x42]),
      gitMarkedBinary: false,
    );

    expect(utf8File.kind, FileContentKind.utf8);
    expect(utf8File.lines, ['begin', 'end;']);
    expect(utf8File.hasTrailingNewline, isTrue);
    expect(unsupported.kind, FileContentKind.unsupportedEncoding);
    expect(binary.kind, FileContentKind.binary);
  });

  test('rejects blame rows that do not match the file', () {
    final file = FileDocument.fromBytes(
      revision: 'abc',
      path: 'one.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('one\n')),
      gitMarkedBinary: false,
    );
    expect(
      () => BlameDocument.fromGitLines(file, const []),
      throwsFormatException,
    );
  });

  test('stops materializing text beyond either hard limit', () {
    final bytesOverLimit = Uint8List(fullDiffTextByteLimit + 1)
      ..fillRange(0, fullDiffTextByteLimit + 1, 0x61);
    final linesOverLimit = Uint8List.fromList(
      utf8.encode(List.filled(fullDiffTextLineLimit + 1, 'x').join('\n')),
    );

    for (final bytes in [bytesOverLimit, linesOverLimit]) {
      final file = FileDocument.fromBytes(
        revision: 'abc',
        path: 'large.txt',
        side: FileDocumentSide.result,
        bytes: bytes,
        gitMarkedBinary: false,
      );
      expect(file.kind, FileContentKind.tooLarge);
      expect(file.lines, isEmpty);
      expect(file.disableRichRendering, isTrue);
    }
  });

  test('applies the byte hard limit before decoding invalid UTF-8', () {
    final bytes = Uint8List(fullDiffTextByteLimit + 1)
      ..fillRange(0, fullDiffTextByteLimit + 1, 0x80);

    final file = FileDocument.fromBytes(
      revision: 'abc',
      path: 'large.txt',
      side: FileDocumentSide.result,
      bytes: bytes,
      gitMarkedBinary: false,
    );

    expect(file.kind, FileContentKind.tooLarge);
    expect(file.lines, isEmpty);
  });

  test('stops at the row hard limit before decoding later invalid UTF-8', () {
    final bytes = Uint8List.fromList([
      ...utf8.encode(
        '${List.filled(fullDiffTextLineLimit + 1, 'x').join('\n')}\n',
      ),
      0x80,
    ]);

    final file = FileDocument.fromBytes(
      revision: 'abc',
      path: 'many-lines.txt',
      side: FileDocumentSide.result,
      bytes: bytes,
      gitMarkedBinary: false,
    );

    expect(file.kind, FileContentKind.tooLarge);
    expect(file.lines, isEmpty);
  });
}
