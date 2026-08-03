import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_theme.dart';

/// The one place the approved GitHub Dark values are written out by hand.
/// Every other test compares against the constants, so a typo here is the
/// only way a wrong color can reach the diff.
void main() {
  test('the palette carries the approved GitHub Dark values', () {
    expect(fullDiffCanvas, const Color(0xFF0D1117), reason: 'diff 바탕');
    expect(fullDiffHeader, const Color(0xFF151B23), reason: '헤더·빈 칸 바탕');
    expect(fullDiffDivider, const Color(0xFF3D444D), reason: '기본 테두리');
    expect(fullDiffMuted, const Color(0xFF9198A1), reason: '보조 글자');
    expect(fullDiffAddedSource, const Color(0xFF12261E), reason: '추가 줄');
    expect(fullDiffAddedGutter, const Color(0xFF1C4328), reason: '추가 줄 번호');
    expect(fullDiffDeletedSource, const Color(0xFF25171C), reason: '삭제 줄');
    expect(fullDiffDeletedGutter, const Color(0xFF542426), reason: '삭제 줄 번호');
    expect(fullDiffHunkHeader, const Color(0xFF111D2E), reason: 'hunk 줄');
    expect(fullDiffHatchBackground, const Color(0xFF212830), reason: '빈 칸 빗금');
  });

  test('word highlights keep Primer transparency and stay distinct', () {
    // These sit on top of the line background, so they are the one pair the
    // spec keeps translucent rather than pre-composited.
    expect(fullDiffAddedWord, const Color(0x662EA043));
    expect(fullDiffDeletedWord, const Color(0x66F85149));
    expect(fullDiffAddedWord, isNot(fullDiffDeletedWord));
  });

  test('the minimap marks additions green and deletions red', () {
    expect(fullDiffMinimapAdded, const Color(0xFF3FB950));
    expect(fullDiffMinimapDeleted, const Color(0xFFF85149));
  });
}
