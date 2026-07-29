import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/monaco_editor_screen.dart';

void main() {
  testWidgets('editable internal editor saves the current text once', (
    tester,
  ) async {
    final saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonacoEditorScreen(
          title: 'lib/a.dart',
          initialText: 'changed\n',
          language: MonacoLanguage.dart,
          readOnly: false,
          onSave: (text) async => saved.add(text),
          editorForTesting: const SizedBox.expand(),
        ),
      ),
    );

    expect(find.text('내장 에디터'), findsOneWidget);
    expect(find.text('수정 가능'), findsOneWidget);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(saved, ['changed\n']);
  });

  testWidgets('read-only internal editor has no save action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MonacoEditorScreen(
          title: 'lib/a.dart',
          initialText: 'old\n',
          language: MonacoLanguage.dart,
          readOnly: true,
          editorForTesting: SizedBox.expand(),
        ),
      ),
    );

    expect(find.text('읽기 전용'), findsOneWidget);
    expect(find.text('저장'), findsNothing);
  });

  testWidgets('save failure keeps the editor open and shows the error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonacoEditorScreen(
          title: 'lib/a.dart',
          initialText: 'changed\n',
          language: MonacoLanguage.dart,
          readOnly: false,
          onSave: (_) async => throw StateError('save failed'),
          editorForTesting: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('내장 에디터'), findsOneWidget);
    expect(find.textContaining('save failed'), findsOneWidget);
  });

  testWidgets('external editor fallback appears only when available', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MonacoEditorScreen(
          title: 'lib/a.dart',
          initialText: 'text\n',
          language: MonacoLanguage.plaintext,
          readOnly: false,
          onOpenExternal: () async => opened = true,
          editorForTesting: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tap(find.text('외부 에디터'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  test('maps common file extensions and falls back to plain text', () {
    expect(monacoLanguageForPath('lib/a.dart'), MonacoLanguage.dart);
    expect(monacoLanguageForPath('web/app.ts'), MonacoLanguage.typescript);
    expect(monacoLanguageForPath('README.md'), MonacoLanguage.markdown);
    expect(monacoLanguageForPath('LICENSE'), MonacoLanguage.plaintext);
  });
}
