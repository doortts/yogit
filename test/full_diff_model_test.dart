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
}
