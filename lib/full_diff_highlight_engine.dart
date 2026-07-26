// Portions adapted from highlighting 0.9.0+11.8.0.
//
// MIT License
//
// Copyright (c) 2023 Akvelon Inc.
// Copyright (c) 2019 Rongjian Zhang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// ignore_for_file: implementation_imports

import 'package:highlighting/src/const/literals.dart';
import 'package:highlighting/src/const/magic_numbers.dart';
import 'package:highlighting/src/domain_regexp_match.dart';
import 'package:highlighting/src/language.dart';
import 'package:highlighting/src/mode.dart';
import 'package:highlighting/src/mode_compiler.dart';
import 'package:highlighting/src/response.dart';
import 'package:highlighting/src/result.dart';
import 'package:highlighting/src/utils.dart';

export 'package:highlighting/src/node.dart' show Node;

class RegisteredHighlightEngine {
  final _languages = <String, Language>{};

  void registerLanguage(Language language) {
    _languages[language.id] = language;
  }

  Result parse(String text, {required String languageId}) {
    return _highlight(languageId, text, true);
  }

  Result _highlight(
    String languageId,
    String codeToHighlight,
    bool ignoreIllegals, {
    Mode? continuation,
    bool safeMode = true,
  }) {
    final emitter = Result();
    final language = _languages[languageId];
    if (language == null) {
      return _plainTextResult(codeToHighlight);
    }
    final md = compileLanguage(language);

    var top = continuation ?? md;
    final continuations = <String, Mode?>{};

    void processContinuations() {
      final scopes = <String>[];
      for (
        Mode? current = top;
        current != language && current != null;
        current = current.parent
      ) {
        if (current.scope case final String scope) {
          scopes.insert(0, scope);
        }
      }
      for (final scope in scopes) {
        emitter.openNode(scope);
      }
    }

    processContinuations();
    var modeBuffer = '';
    var relevance = 0.0;
    var index = 0;
    var iterations = 0;
    var resumeScanAtSamePosition = false;
    DomainRegexMatch? lastMatch;
    final keywordHits = <String, int>{};

    void processKeywords() {
      if (top.keywords == null) {
        emitter.addText(modeBuffer);
        return;
      }

      var lastIndex = 0;
      top.keywordPatternRe!.lastIndex = 0;
      var match = top.keywordPatternRe!.exec(modeBuffer);
      var buffer = '';

      while (match != null) {
        buffer += substring(modeBuffer, lastIndex, match.index);
        final word = language.case_insensitive
            ? match[0]!.toLowerCase()
            : match[0]!;
        final data = top.keywords[word];
        if (data != null) {
          final kind = data.item1 as String;
          final keywordRelevance = data.item2 as double;
          emitter.addText(buffer);
          buffer = '';

          keywordHits[word] = (keywordHits[word] ?? 0) + 1;
          if (keywordHits[word]! <= kMaxKeywordHits) {
            relevance += keywordRelevance;
          }
          if (kind.startsWith('_')) {
            buffer += match[0]!;
          } else {
            final cssClass = language.classNameAliases[kind] ?? kind;
            emitter.addKeyword(match[0]!, cssClass);
          }
        } else {
          buffer += match[0]!;
        }
        lastIndex = top.keywordPatternRe!.lastIndex;
        match = top.keywordPatternRe?.exec(modeBuffer);
      }

      buffer += substring(modeBuffer, lastIndex);
      emitter.addText(buffer);
    }

    void processSubLanguage() {
      if (top.subLanguage.isEmpty) {
        throw StateError('Missing sublanguage');
      }
      if (modeBuffer.isEmpty) {
        return;
      }

      late final Result result;
      if (top.subLanguage.length > 1) {
        result = _highlightAuto(modeBuffer, top.subLanguage);
      } else {
        final sublanguage = top.subLanguage.first;
        if (_languages.containsKey(sublanguage)) {
          result = _highlight(
            sublanguage,
            modeBuffer,
            true,
            continuation: continuations[sublanguage],
          );
          continuations[sublanguage] = result.top;
        } else {
          result = _plainTextResult(modeBuffer);
        }
      }

      if (top.relevance! > 0) {
        relevance += result.relevance;
      }
      emitter.addSublanguage(result, result.language);
    }

    void processBuffer() {
      if (top.subLanguage.isNotEmpty) {
        processSubLanguage();
      } else {
        processKeywords();
      }
      modeBuffer = '';
    }

    void emitMultiClass(Map<dynamic, dynamic> scope, DomainRegexMatch match) {
      var capture = 1;
      final max = match.length - 1;
      while (capture <= max) {
        if (scope[$emit][capture] == null) {
          capture++;
          continue;
        }
        final className =
            language.classNameAliases[scope[capture.toString()]] ??
            scope[capture.toString()];
        final text = match[capture];
        if (className != null) {
          emitter.addKeyword(text!, className);
        } else {
          modeBuffer = text!;
          processKeywords();
          modeBuffer = '';
        }
        capture++;
      }
    }

    Mode startNewMode(Mode mode, DomainRegexMatch match) {
      if (mode.scope case final String scope) {
        emitter.openNode(language.classNameAliases[scope] ?? scope);
      }

      if (mode.beginScope != null) {
        if (mode.beginScope[$wrap] != null) {
          emitter.addKeyword(
            modeBuffer,
            language.classNameAliases[mode.beginScope[$wrap]] ??
                mode.beginScope[$wrap],
          );
          modeBuffer = '';
        } else if (mode.beginScope[$multi] == true) {
          emitMultiClass(mode.beginScope, match);
          modeBuffer = '';
        }
      }

      top = Mode.inherit(mode, Mode(parent: top));
      return top;
    }

    Mode? endOfMode(
      Mode mode,
      DomainRegexMatch match,
      String matchPlusRemainder,
    ) {
      var matched = false;
      if (mode.endRe != null) {
        matched = matchPlusRemainder.startsWith(mode.endRe!);
      }
      if (matched) {
        if (mode.onEnd != null) {
          final response = Response(mode: mode);
          mode.onEnd?.call(match, response);
          if (response.isMatchIgnored) {
            matched = false;
          }
        }
        if (matched) {
          while (mode.endsParent == true && mode.parent != null) {
            mode = mode.parent!;
          }
          return mode;
        }
      }
      if (mode.endsWithParent == true) {
        return endOfMode(mode.parent!, match, matchPlusRemainder);
      }
      return null;
    }

    int ignore(String lexeme) {
      if (top.matcher?.regexIndex == 0) {
        modeBuffer += lexeme[0];
        return 1;
      }
      resumeScanAtSamePosition = true;
      return 0;
    }

    int beginMatch(DomainRegexMatch match) {
      final lexeme = match[0]!;
      final newMode = match.rule!;
      final response = Response(mode: newMode);
      final callbacks = [newMode.beforeBegin, newMode.onBegin];

      for (final callback in callbacks) {
        if (callback == null) {
          continue;
        }
        callback(match, response);
        if (response.isMatchIgnored) {
          return ignore(lexeme);
        }
      }

      if (newMode.skip == true) {
        modeBuffer += lexeme;
      } else {
        if (newMode.excludeBegin == true) {
          modeBuffer += lexeme;
        }
        processBuffer();
        if (newMode.returnBegin != true && newMode.excludeBegin != true) {
          modeBuffer = lexeme;
        }
      }
      startNewMode(newMode, match);
      return newMode.returnBegin == true ? 0 : lexeme.length;
    }

    int endMatch(DomainRegexMatch match) {
      final lexeme = match[0]!;
      final matchPlusRemainder = substring(codeToHighlight, match.index);
      final endMode = endOfMode(top, match, matchPlusRemainder);
      if (endMode == null) {
        return kNoMatch;
      }

      final origin = top;
      if (top.endScope != null && top.endScope[$wrap] != null) {
        processBuffer();
        emitter.addKeyword(lexeme, top.endScope[$wrap]);
      } else if (top.endScope != null && top.endScope[$multi] == true) {
        processBuffer();
        emitMultiClass(top.endScope, match);
      } else if (origin.skip == true) {
        modeBuffer += lexeme;
      } else {
        if (!(origin.returnEnd == true || origin.excludeEnd == true)) {
          modeBuffer += lexeme;
        }
        processBuffer();
        if (origin.excludeEnd == true) {
          modeBuffer = lexeme;
        }
      }

      do {
        if (top.scope != null) {
          emitter.closeNode();
        }
        if (top.skip != true && top.subLanguage.isEmpty) {
          relevance += top.relevance!;
        }
        top = top.parent!;
      } while (top != endMode.parent);

      if (endMode.starts != null) {
        startNewMode(endMode.starts!, match);
      }
      return origin.returnEnd == true ? 0 : lexeme.length;
    }

    int processLexeme(String textBeforeMatch, DomainRegexMatch? match) {
      final lexeme = match?[0];
      modeBuffer += textBeforeMatch;

      if (lexeme == null) {
        processBuffer();
        return 0;
      }
      if (lastMatch?.matchType == $begin &&
          match!.matchType == $end &&
          lastMatch?.index == match.index &&
          lexeme.isEmpty) {
        modeBuffer += codeToHighlight.substring(match.index, match.index + 1);
        if (!safeMode) {
          throw StateError('Zero-width match for $languageId');
        }
        return 1;
      }

      lastMatch = match!;
      if (match.matchType == $begin) {
        return beginMatch(match);
      }
      if (match.matchType == $illegal && !ignoreIllegals) {
        throw StateError('Illegal lexeme for ${top.scope ?? languageId}');
      }
      if (match.matchType == $end) {
        final processed = endMatch(match);
        if (processed != kNoMatch) {
          return processed;
        }
      }
      if (match.matchType == $illegal && lexeme.isEmpty) {
        return 1;
      }
      if (iterations > kMaxIterations && iterations > match.index * 3) {
        throw StateError('Too many highlighting iterations');
      }

      modeBuffer += lexeme;
      return lexeme.length;
    }

    try {
      top.matcher?.considerAll();
      for (;;) {
        iterations++;
        if (resumeScanAtSamePosition) {
          resumeScanAtSamePosition = false;
        } else {
          top.matcher?.considerAll();
        }
        top.matcher?.lastIndex = index;
        final match = top.matcher?.exec(codeToHighlight);
        if (match == null) {
          break;
        }
        final beforeMatch = substring(codeToHighlight, index, match.index);
        final processedCount = processLexeme(beforeMatch, match);
        index = match.index + processedCount;
      }
      processLexeme(substring(codeToHighlight, index), null);
      emitter.closeAllNodes();
      emitter.finalize();
      emitter.relevance = relevance;
      emitter.language = languageId;
      emitter.top = top;
      return emitter;
    } on Exception {
      return emitter;
    }
  }

  Result _highlightAuto(String code, List<String> languageSubset) {
    var best = _plainTextResult(code);
    for (final id in languageSubset) {
      final language = _languages[id];
      if (language == null || language.disableAutodetect) {
        continue;
      }
      final candidate = _highlight(id, code, false);
      if (_compare(candidate, best) < 0) {
        best = candidate;
      }
    }
    return best;
  }

  Result _plainTextResult(String code) {
    final emitter = Result();
    emitter.addText(code);
    return emitter;
  }

  int _compare(Result first, Result second) {
    if ((first.relevance - second.relevance).abs() > 0.0001) {
      return (second.relevance - first.relevance).sign.round();
    }
    final firstLanguage = first.language;
    final secondLanguage = second.language;
    if (firstLanguage != null && secondLanguage != null) {
      if (_languages[firstLanguage]?.supersetOf == secondLanguage) {
        return 1;
      }
      if (_languages[secondLanguage]?.supersetOf == firstLanguage) {
        return -1;
      }
    }
    return 0;
  }
}
