import 'package:flutter/material.dart';

/// The timeline's own colours: the ones that mean something specific — a hash,
/// a deletion, a branch-preview rail — rather than the surface tones the theme
/// swaps per palette. Everything that draws a commit graph reads from here.

/// The design's `--yo-main` accent: additions, lane dots, the name tint.
const mainAccent = Color(0xFF8AD6A1);
const successGreen = Color(0xFF34C759);
const behindOrange = Color(0xFFF0A35E);
const remoteBehindRed = Color(0xFFFF453A);

const hashRed = Color(0xFFEF6C63);
const deletedPink = Color(0xFFF29AB2);
const renamedPurple = Color(0xFFB6A0EA);

/// The branch preview draws what is not committed yet: purple for a clean
/// result, red for a conflict, blue for the controls that decide it.
const previewPurple = Color(0xFFC69AFF);
const previewPurplePanel = Color(0xFF29243A);
const previewConflict = Color(0xFFFF7A84);
const previewConflictPanel = Color(0xFF4B252C);
const previewControlBlue = Color(0xFF4388EE);

/// 커밋 행 배지와 '양쪽 유지' 미리보기의 색. 초록이 브랜치 쪽(그리고 이미 반영된
/// 커밋), 파랑이 기준 쪽 추가, 주황이 충돌 예고다.
const duplicateBadge = Color(0xFF7CE0A0);
const forecastBadge = Color(0xFFF0A35E);
const keepBothOursColor = Color(0xFF8FCBFF);
const keepBothTheirsColor = Color(0xFF7CE0A0);

/// Five steps down from a branch's own colour, for the rebase mapping ribbons.
List<Color> rebaseMappingColors(Color branchColor) {
  final source = HSLColor.fromColor(branchColor);
  final startLightness = source.lightness + (1 - source.lightness) * 0.12;
  return [
    for (var index = 0; index < 5; index++)
      source
          .withSaturation(source.saturation * (0.92 - index * 0.11))
          .withLightness(startLightness * (1 - index * 0.09))
          .toColor(),
  ];
}
