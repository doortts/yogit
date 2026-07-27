@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_syntax.dart';

const drlFirstHunkLines = <String>[
  'procedure TDRLLua.ReadWad;',
  'var iProgBase : DWord;',
  '    iModule   : TDRLModule;',
  '    iData     : TVDataFile;',
  'function CheckID( const iID : Ansistring ) : Boolean;',
  'begin',
  "  Exit( ( iID <> 'core' ) and ( iID <> 'drl' ) );",
  'end;',
  'procedure SetupBase;',
  'begin',
  "  Log( LOGINFO, 'BASE MODULE VERSION: '+VersionModule );",
  'end;',
];

void main() {
  test('DRL first hunk highlighting stays within the release gate', () {
    final highlighter = HighlightJsSyntaxHighlighter();
    final samples = <int>[];
    for (var run = 0; run < 30; run++) {
      final watch = Stopwatch()..start();
      for (final line in drlFirstHunkLines) {
        highlighter.highlightLine('src/drlua.pas', line);
      }
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    final sorted = [...samples]..sort();
    final p95 =
        sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    // Printed values are copied to the Task 12 verification record.
    // ignore: avoid_print
    print('syntax-first-us=${samples.first} syntax-p95-us=$p95');
    expect(samples.first, lessThanOrEqualTo(50000));
  });
}
