import 'dart:math' as math;

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

/// How close a lane colour may come to the avatar's own tone before the ring
/// drawn around a photo in that tone stops being a ring. WCAG contrast was the
/// first measure tried and it excluded far too much: on a mid-grey photo it
/// rules out pink (1.06) and orange (1.16), both of which read perfectly well
/// because hue carries what lightness does not. Oklab is perceptually uniform,
/// so one distance covers pale-on-pale and vivid-on-grey alike.
///
/// 0.10 is where the two entries the symptom was reported on (0.013 and 0.045
/// against the blue doodle) fall out while the nearest colour confirmed as
/// readable, cyan at 0.127, stays. Provisional: this is the one number to move
/// if the exclusion turns out too eager on a real avatar.
const paletteToneCollision = 0.10;

/// Perceived distance between two colours: plain Euclidean in Oklab, where a
/// step of the same size looks the same size wherever it is taken.
double oklabDistance(Color first, Color second) {
  final left = _oklab(first);
  final right = _oklab(second);
  final l = left.l - right.l;
  final a = left.a - right.a;
  final b = left.b - right.b;
  return math.sqrt(l * l + a * a + b * b);
}

/// Which of [candidates] still draw a visible ring on an avatar in [tone] —
/// the ones whose colour in [laneColors] is far enough away to be told from it.
///
/// Falls back to the three furthest rather than to whatever survived: a random
/// pool of one would paint a whole repository in a single colour, and an empty
/// one has no assignment to make at all. Three is the smallest pool that still
/// reads as several branches, and the furthest three are by definition the ones
/// that come closest to clearing the threshold.
List<int> paletteIndexesAvoiding(
  List<int> candidates,
  List<Color> laneColors,
  Color tone,
) {
  double distance(int index) => oklabDistance(laneColors[index], tone);
  final clear = [
    for (final index in candidates)
      if (distance(index) >= paletteToneCollision) index,
  ];
  if (clear.length >= 3) return clear;
  final ranked = [...candidates]
    ..sort((left, right) => distance(right).compareTo(distance(left)));
  return ranked.take(3).toList()..sort();
}

/// Ottosson's Oklab: perceived lightness, then green→red and blue→yellow. The
/// matrices are his, and the cube roots are what make a step in the result
/// look the same size at both ends of the range.
({double l, double a, double b}) _oklab(Color color) {
  final r = _linear(color.r);
  final g = _linear(color.g);
  final b = _linear(color.b);
  final long = math
      .pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3)
      .toDouble();
  final medium = math
      .pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3)
      .toDouble();
  final short = math
      .pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3)
      .toDouble();
  return (
    l: 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short,
    a: 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short,
    b: 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short,
  );
}

/// sRGB undone: the stored channel is gamma-encoded, and the matrices above
/// want the light it stands for.
double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

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
