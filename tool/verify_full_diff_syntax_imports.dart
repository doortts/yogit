import 'dart:convert';
import 'dart:io';

const _baseLanguageFiles = {
  'apache.dart',
  'bash.dart',
  'c.dart',
  'cmake.dart',
  'cpp.dart',
  'csharp.dart',
  'css.dart',
  'dart.dart',
  'delphi.dart',
  'diff.dart',
  'dockerfile.dart',
  'go.dart',
  'gradle.dart',
  'graphql.dart',
  'groovy.dart',
  'handlebars.dart',
  'http.dart',
  'ini.dart',
  'java.dart',
  'javascript.dart',
  'json.dart',
  'kotlin.dart',
  'lua.dart',
  'makefile.dart',
  'markdown.dart',
  'nginx.dart',
  'nix.dart',
  'objectivec.dart',
  'php.dart',
  'powershell.dart',
  'properties.dart',
  'protobuf.dart',
  'python.dart',
  'ruby.dart',
  'rust.dart',
  'scss.dart',
  'sql.dart',
  'swift.dart',
  'typescript.dart',
  'xml.dart',
  'yaml.dart',
};

const _extendedLanguageFiles = {
  'armasm.dart',
  'clojure.dart',
  'elixir.dart',
  'erlang.dart',
  'fortran.dart',
  'fsharp.dart',
  'haskell.dart',
  'julia.dart',
  'latex.dart',
  'lisp.dart',
  'matlab.dart',
  'mojolicious.dart',
  'ocaml.dart',
  'perl.dart',
  'qml.dart',
  'r.dart',
  'scala.dart',
  'scheme.dart',
  'verilog.dart',
  'vhdl.dart',
  'x86asm.dart',
};

Future<void> main() async {
  final available = _availableLanguageLibraries();
  final baseAllowed = _libraryUris(_baseLanguageFiles);
  final extendedAllowed = {
    ...baseAllowed,
    ..._libraryUris(_extendedLanguageFiles),
  };

  final disabled = await _buildAotLanguageLibraries(enabled: false);
  if (!_verifySnapshot(
    label: 'extended-disabled',
    actual: disabled,
    allowed: baseAllowed,
    available: available,
  )) {
    exitCode = 1;
    return;
  }

  final enabled = await _buildAotLanguageLibraries(enabled: true);
  if (!_verifySnapshot(
    label: 'extended-enabled',
    actual: enabled,
    allowed: extendedAllowed,
    available: available,
  )) {
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'AOT snapshots contain every allowed syntax dependency and no other '
    'highlighting language modules.',
  );
}

Set<String> _availableLanguageLibraries() {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final highlighting = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'highlighting',
  );
  final packageRoot = Directory.fromUri(
    configFile.uri.resolve(highlighting['rootUri'] as String),
  );
  final languages = Directory.fromUri(
    packageRoot.uri.resolve('lib/languages/'),
  );
  return languages
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.uri.pathSegments.last)
      .map(_libraryUri)
      .toSet();
}

Set<String> _libraryUris(Set<String> files) => files.map(_libraryUri).toSet();

String _libraryUri(String file) => 'package:highlighting/languages/$file';

Future<Set<String>> _buildAotLanguageLibraries({required bool enabled}) async {
  final output = Directory.systemTemp.createTempSync(
    'yogit-syntax-size-${enabled ? 'on' : 'off'}-',
  );
  try {
    final result = await Process.run('flutter', [
      'build',
      'macos',
      '--release',
      '--no-pub',
      '--analyze-size',
      '--code-size-directory=${output.path}',
      '--target=tool/full_diff_syntax_bundle_probe.dart',
      '--dart-define=YOGIT_EXTENDED_SYNTAX=$enabled',
    ], workingDirectory: Directory.current.path);
    if (result.exitCode != 0) {
      stderr
        ..write(result.stdout)
        ..write(result.stderr);
      throw ProcessException('flutter', const ['build', 'macos']);
    }

    final snapshot = File('${output.path}/snapshot.arm64.json');
    final analysis =
        jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
    final strings = (analysis['strings'] as List<dynamic>).cast<String>();
    return strings
        .where((value) => value.startsWith('package:highlighting/languages/'))
        .where((value) => value.endsWith('.dart'))
        .toSet();
  } finally {
    output.deleteSync(recursive: true);
  }
}

bool _verifySnapshot({
  required String label,
  required Set<String> actual,
  required Set<String> allowed,
  required Set<String> available,
}) {
  final unexpected = actual.intersection(available.difference(allowed)).toList()
    ..sort();
  final unknown = actual.difference(available).toList()..sort();
  final missing = allowed.difference(actual).toList()..sort();
  if (unexpected.isEmpty && unknown.isEmpty && missing.isEmpty) {
    return true;
  }
  if (unexpected.isNotEmpty) {
    stderr.writeln(
      '$label retained unapproved syntax: ${unexpected.join(', ')}',
    );
  }
  if (unknown.isNotEmpty) {
    stderr.writeln(
      '$label retained unknown syntax inputs: ${unknown.join(', ')}',
    );
  }
  if (missing.isNotEmpty) {
    stderr.writeln('$label omitted approved syntax: ${missing.join(', ')}');
  }
  return false;
}
