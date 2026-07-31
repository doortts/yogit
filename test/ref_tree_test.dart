import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/ref_tree.dart';

void main() {
  test('builds slash-delimited refs without duplicating prefix refs', () {
    final roots = buildRefTree([
      'feature',
      'feature/login',
      'feature/payments/api',
      'main',
    ]);

    expect(roots.map((node) => node.segment), ['feature', 'main']);
    expect(roots.first.fullName, 'feature');
    expect(roots.first.children.map((node) => node.segment), [
      'login',
      'payments',
    ]);
    expect(roots.first.children.first.fullName, 'feature/login');
    expect(
      roots.first.children.last.children.single.fullName,
      'feature/payments/api',
    );
  });

  test('preserves first-descendant order at every tree level', () {
    final roots = buildRefTree([
      'origin/release/z',
      'upstream/main',
      'origin/main',
      'origin/release/a',
    ]);

    expect(roots.map((node) => node.segment), ['origin', 'upstream']);
    expect(roots.first.children.map((node) => node.segment), [
      'release',
      'main',
    ]);
    expect(roots.first.children.first.children.map((node) => node.segment), [
      'z',
      'a',
    ]);
  });

  test('sorts dated refs newest first and undated refs by name last', () {
    expect(
      sortRefsNewestFirst(
        ['undated-z', 'v1', 'v3', 'undated-a', 'v2'],
        {'v1': 100, 'v2': 200, 'v3': 200},
      ),
      ['v2', 'v3', 'v1', 'undated-a', 'undated-z'],
    );
  });
}
