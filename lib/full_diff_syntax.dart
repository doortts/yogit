import 'package:flutter/material.dart';
import 'package:highlighting/languages/apache.dart' as lang_apache;
import 'package:highlighting/languages/armasm.dart' as lang_armasm;
import 'package:highlighting/languages/bash.dart' as lang_bash;
import 'package:highlighting/languages/c.dart' as lang_c;
import 'package:highlighting/languages/clojure.dart' as lang_clojure;
import 'package:highlighting/languages/cmake.dart' as lang_cmake;
import 'package:highlighting/languages/cpp.dart' as lang_cpp;
import 'package:highlighting/languages/csharp.dart' as lang_csharp;
import 'package:highlighting/languages/css.dart' as lang_css;
import 'package:highlighting/languages/dart.dart' as lang_dart;
import 'package:highlighting/languages/delphi.dart' as lang_delphi;
import 'package:highlighting/languages/diff.dart' as lang_diff;
import 'package:highlighting/languages/dockerfile.dart' as lang_dockerfile;
import 'package:highlighting/languages/elixir.dart' as lang_elixir;
import 'package:highlighting/languages/erlang.dart' as lang_erlang;
import 'package:highlighting/languages/fortran.dart' as lang_fortran;
import 'package:highlighting/languages/fsharp.dart' as lang_fsharp;
import 'package:highlighting/languages/go.dart' as lang_go;
import 'package:highlighting/languages/gradle.dart' as lang_gradle;
import 'package:highlighting/languages/graphql.dart' as lang_graphql;
import 'package:highlighting/languages/groovy.dart' as lang_groovy;
import 'package:highlighting/languages/haskell.dart' as lang_haskell;
import 'package:highlighting/languages/http.dart' as lang_http;
import 'package:highlighting/languages/ini.dart' as lang_ini;
import 'package:highlighting/languages/java.dart' as lang_java;
import 'package:highlighting/languages/javascript.dart' as lang_javascript;
import 'package:highlighting/languages/json.dart' as lang_json;
import 'package:highlighting/languages/julia.dart' as lang_julia;
import 'package:highlighting/languages/kotlin.dart' as lang_kotlin;
import 'package:highlighting/languages/latex.dart' as lang_latex;
import 'package:highlighting/languages/lisp.dart' as lang_lisp;
import 'package:highlighting/languages/lua.dart' as lang_lua;
import 'package:highlighting/languages/makefile.dart' as lang_makefile;
import 'package:highlighting/languages/markdown.dart' as lang_markdown;
import 'package:highlighting/languages/matlab.dart' as lang_matlab;
import 'package:highlighting/languages/nginx.dart' as lang_nginx;
import 'package:highlighting/languages/nix.dart' as lang_nix;
import 'package:highlighting/languages/objectivec.dart' as lang_objectivec;
import 'package:highlighting/languages/ocaml.dart' as lang_ocaml;
import 'package:highlighting/languages/perl.dart' as lang_perl;
import 'package:highlighting/languages/php.dart' as lang_php;
import 'package:highlighting/languages/powershell.dart' as lang_powershell;
import 'package:highlighting/languages/properties.dart' as lang_properties;
import 'package:highlighting/languages/protobuf.dart' as lang_protobuf;
import 'package:highlighting/languages/python.dart' as lang_python;
import 'package:highlighting/languages/qml.dart' as lang_qml;
import 'package:highlighting/languages/r.dart' as lang_r;
import 'package:highlighting/languages/ruby.dart' as lang_ruby;
import 'package:highlighting/languages/rust.dart' as lang_rust;
import 'package:highlighting/languages/scala.dart' as lang_scala;
import 'package:highlighting/languages/scheme.dart' as lang_scheme;
import 'package:highlighting/languages/scss.dart' as lang_scss;
import 'package:highlighting/languages/sql.dart' as lang_sql;
import 'package:highlighting/languages/swift.dart' as lang_swift;
import 'package:highlighting/languages/typescript.dart' as lang_typescript;
import 'package:highlighting/languages/verilog.dart' as lang_verilog;
import 'package:highlighting/languages/vhdl.dart' as lang_vhdl;
import 'package:highlighting/languages/x86asm.dart' as lang_x86asm;
import 'package:highlighting/languages/xml.dart' as lang_xml;
import 'package:highlighting/languages/yaml.dart' as lang_yaml;

import 'full_diff_highlight_engine.dart';
import 'full_diff_syntax_contract.dart';

const _fileNames = <String, String>{
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'gnumakefile': 'makefile',
  'cmakelists.txt': 'cmake',
  'build.gradle': 'gradle',
  'settings.gradle': 'gradle',
  'nginx.conf': 'nginx',
};

const _extensions = <String, String>{
  'pas': 'delphi',
  'pp': 'delphi',
  'dpr': 'delphi',
  'dart': 'dart',
  'c': 'c',
  'h': 'c',
  'cc': 'cpp',
  'cpp': 'cpp',
  'cxx': 'cpp',
  'm': 'objectivec',
  'mm': 'objectivec',
  'cs': 'csharp',
  'swift': 'swift',
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'go': 'go',
  'rs': 'rust',
  'rb': 'ruby',
  'php': 'php',
  'sh': 'bash',
  'bash': 'bash',
  'ps1': 'powershell',
  'sql': 'sql',
  'lua': 'lua',
  'html': 'xml',
  'htm': 'xml',
  'xml': 'xml',
  'css': 'css',
  'scss': 'scss',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'md': 'markdown',
  'markdown': 'markdown',
  'graphql': 'graphql',
  'proto': 'protobuf',
  'diff': 'diff',
  'patch': 'diff',
  'cmake': 'cmake',
  'gradle': 'gradle',
  'properties': 'properties',
  'env': 'ini',
  'nix': 'nix',
  'conf': 'apache',
  'http': 'http',
  'pl': 'perl',
  'pm': 'perl',
  'r': 'r',
  'jl': 'julia',
  'scala': 'scala',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hrl': 'erlang',
  'hs': 'haskell',
  'ml': 'ocaml',
  'mli': 'ocaml',
  'fs': 'fsharp',
  'fsx': 'fsharp',
  'clj': 'clojure',
  'cljs': 'clojure',
  'lisp': 'lisp',
  'scm': 'scheme',
  'v': 'verilog',
  'sv': 'verilog',
  'vhd': 'vhdl',
  'vhdl': 'vhdl',
  'asm': 'x86asm',
  's': 'armasm',
  'f': 'fortran',
  'f90': 'fortran',
  'matlab': 'matlab',
  'qml': 'qml',
  'tex': 'latex',
};

String? _languageForPath(String path) {
  final name = path.split('/').last.toLowerCase();
  if (_fileNames[name] case final language?) return language;
  if (name == '.env' || name.startsWith('.env.')) return 'ini';
  final dot = name.lastIndexOf('.');
  return dot < 0 ? null : _extensions[name.substring(dot + 1)];
}

String? languageForPath(String path) => _languageForPath(path);

const _syntaxStyles = <String, TextStyle>{
  'keyword': TextStyle(color: Color(0xFF83C4FF)),
  'built_in': TextStyle(color: Color(0xFF83C4FF)),
  'type': TextStyle(color: Color(0xFF83C4FF)),
  'string': TextStyle(color: Color(0xFFFFBFA0)),
  'number': TextStyle(color: Color(0xFFC9E28B)),
  'literal': TextStyle(color: Color(0xFFC9E28B)),
  'comment': TextStyle(color: Color(0xFF919191)),
  'title': TextStyle(color: Color(0xFFD7BA7D)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
};

const extendedSyntaxEnabled = bool.fromEnvironment(
  'YOGIT_EXTENDED_SYNTAX',
  defaultValue: true,
);

const extendedLanguageIds = <String>{
  'perl',
  'r',
  'julia',
  'scala',
  'elixir',
  'erlang',
  'haskell',
  'ocaml',
  'fsharp',
  'clojure',
  'lisp',
  'scheme',
  'verilog',
  'vhdl',
  'x86asm',
  'armasm',
  'fortran',
  'matlab',
  'qml',
  'latex',
};

final _baseLanguages = [
  lang_delphi.delphi,
  lang_dart.dart,
  lang_c.c,
  lang_cpp.cpp,
  lang_objectivec.objectivec,
  lang_csharp.csharp,
  lang_swift.swift,
  lang_java.java,
  lang_kotlin.kotlin,
  lang_javascript.javascript,
  lang_typescript.typescript,
  lang_python.python,
  lang_go.go,
  lang_rust.rust,
  lang_ruby.ruby,
  lang_php.php,
  lang_bash.bash,
  lang_powershell.powershell,
  lang_sql.sql,
  lang_lua.lua,
  lang_xml.xml,
  lang_css.css,
  lang_scss.scss,
  lang_json.json,
  lang_yaml.yaml,
  lang_ini.ini,
  lang_markdown.markdown,
  lang_graphql.graphql,
  lang_protobuf.protobuf,
  lang_diff.diff,
  lang_dockerfile.dockerfile,
  lang_makefile.makefile,
  lang_cmake.cmake,
  lang_gradle.gradle,
  lang_groovy.groovy,
  lang_properties.properties,
  lang_nginx.nginx,
  lang_nix.nix,
  lang_apache.apache,
  lang_http.http,
];

List<dynamic> get _extendedLanguages => [
  lang_perl.perl,
  lang_r.r,
  lang_julia.julia,
  lang_scala.scala,
  lang_elixir.elixir,
  lang_erlang.erlang,
  lang_haskell.haskell,
  lang_ocaml.ocaml,
  lang_fsharp.fsharp,
  lang_clojure.clojure,
  lang_lisp.lisp,
  lang_scheme.scheme,
  lang_verilog.verilog,
  lang_vhdl.vhdl,
  lang_x86asm.x86Asm,
  lang_armasm.armasm,
  lang_fortran.fortran,
  lang_matlab.matlab,
  lang_qml.qml,
  lang_latex.latex,
];

var _languagesRegistered = false;
final _highlight = RegisteredHighlightEngine();

void registerFullDiffLanguages() {
  if (_languagesRegistered) return;
  _languagesRegistered = true;
  for (final language in _baseLanguages) {
    _highlight.registerLanguage(language);
  }
  if (extendedSyntaxEnabled) {
    for (final language in _extendedLanguages) {
      _highlight.registerLanguage(language);
    }
  }
}

class HighlightJsSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  HighlightJsSyntaxHighlighter() {
    registerFullDiffLanguages();
  }

  @override
  String? languageForPath(String path) => _languageForPath(path);

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) {
    final language = languageForPath(path);
    if (language == null ||
        (!extendedSyntaxEnabled && extendedLanguageIds.contains(language))) {
      return const [];
    }

    final result = _highlight.parse(source, languageId: language);
    final spans = <CodeTokenSpan>[];
    var offset = 0;

    void visit(Node node, TextStyle? inheritedStyle) {
      final style = _styleFor(node.className) ?? inheritedStyle;
      final value = node.value;
      if (value != null) {
        final end = offset + value.length;
        if (style != null && end > offset) {
          spans.add(CodeTokenSpan(start: offset, end: end, style: style));
        }
        offset = end;
        return;
      }
      for (final child in node.children) {
        visit(child, style);
      }
    }

    visit(result.rootNode, null);
    return List.unmodifiable(spans);
  }
}

TextStyle? _styleFor(String? className) {
  if (className == null) return null;
  final separator = className.indexOf('.');
  return _syntaxStyles[className] ??
      _syntaxStyles[separator < 0
          ? className
          : className.substring(0, separator)];
}

const maxWordDiffTokens = 512;
const maxWordDiffCharacters = 20000;

@immutable
class WordRange {
  const WordRange({required this.text, required this.start, required this.end});

  final String text;
  final int start;
  final int end;
}

@immutable
class WordChangeRanges {
  const WordChangeRanges({required this.oldRanges, required this.newRanges});

  static const empty = WordChangeRanges(oldRanges: [], newRanges: []);

  final List<WordRange> oldRanges;
  final List<WordRange> newRanges;

  bool get isEmpty => oldRanges.isEmpty && newRanges.isEmpty;
}

List<WordRange> tokenizeWords(String text) {
  final matches = RegExp(r'\w+|[^\w\s]+|\s+').allMatches(text);
  return List.unmodifiable(
    matches.map(
      (match) =>
          WordRange(text: match.group(0)!, start: match.start, end: match.end),
    ),
  );
}

WordChangeRanges changedWordRanges(String oldText, String newText) {
  if (oldText.length > maxWordDiffCharacters ||
      newText.length > maxWordDiffCharacters) {
    return WordChangeRanges.empty;
  }
  final oldTokens = tokenizeWords(oldText);
  final newTokens = tokenizeWords(newText);
  if (oldTokens.length > maxWordDiffTokens ||
      newTokens.length > maxWordDiffTokens) {
    return WordChangeRanges.empty;
  }
  var prefix = 0;
  while (prefix < oldTokens.length &&
      prefix < newTokens.length &&
      oldTokens[prefix].text == newTokens[prefix].text) {
    prefix++;
  }
  var oldSuffix = oldTokens.length;
  var newSuffix = newTokens.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldTokens[oldSuffix - 1].text == newTokens[newSuffix - 1].text) {
    oldSuffix--;
    newSuffix--;
  }
  return WordChangeRanges(
    oldRanges: List.unmodifiable(oldTokens.sublist(prefix, oldSuffix)),
    newRanges: List.unmodifiable(newTokens.sublist(prefix, newSuffix)),
  );
}
