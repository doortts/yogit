import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final output = Directory.systemTemp.createTempSync('yogit-syntax-size-');
  try {
    final result = await Process.run('flutter', [
      'build',
      'macos',
      '--release',
      '--no-pub',
      '--analyze-size',
      '--code-size-directory=${output.path}',
      '--target=tool/full_diff_syntax_bundle_probe.dart',
      '--dart-define=YOGIT_EXTENDED_SYNTAX=false',
    ], workingDirectory: Directory.current.path);
    if (result.exitCode != 0) {
      stderr
        ..write(result.stdout)
        ..write(result.stderr);
      exitCode = result.exitCode;
      return;
    }

    final snapshot = File('${output.path}/snapshot.arm64.json');
    final analysis =
        jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
    final strings = (analysis['strings'] as List<dynamic>).cast<String>();
    const forbiddenLibraries = {
      'package:highlighting/languages/all.dart',
      'package:highlighting/languages/ada.dart',
      'package:highlighting/languages/perl.dart',
      'package:highlighting/languages/r.dart',
      'package:highlighting/languages/julia.dart',
      'package:highlighting/languages/scala.dart',
      'package:highlighting/languages/elixir.dart',
      'package:highlighting/languages/erlang.dart',
      'package:highlighting/languages/haskell.dart',
      'package:highlighting/languages/ocaml.dart',
      'package:highlighting/languages/fsharp.dart',
      'package:highlighting/languages/clojure.dart',
      'package:highlighting/languages/lisp.dart',
      'package:highlighting/languages/scheme.dart',
      'package:highlighting/languages/verilog.dart',
      'package:highlighting/languages/vhdl.dart',
      'package:highlighting/languages/x86asm.dart',
      'package:highlighting/languages/armasm.dart',
      'package:highlighting/languages/fortran.dart',
      'package:highlighting/languages/matlab.dart',
      'package:highlighting/languages/qml.dart',
      'package:highlighting/languages/latex.dart',
    };
    final retained = forbiddenLibraries.where(strings.contains).toList();
    if (retained.isNotEmpty) {
      stderr.writeln(
        'Disabled release retained syntax libraries: '
        '${retained.join(', ')}',
      );
      exitCode = 1;
      return;
    }
    if (!strings.contains('package:highlighting/languages/dart.dart')) {
      stderr.writeln('Release probe did not retain the base Dart syntax.');
      exitCode = 1;
      return;
    }

    stdout.writeln(
      'AOT snapshot retains base syntax and omits umbrella and extended '
      'languages.',
    );
  } finally {
    output.deleteSync(recursive: true);
  }
}
