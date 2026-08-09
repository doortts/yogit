import 'package:flutter/material.dart';

// GitHub Primer's `dark` theme, per docs/diff-pallete-design.md. The line and
// gutter fills are Primer's translucent values already composited over the
// canvas: FullDiffCodeRow layers the gutter over the line, so keeping them
// translucent here would blend the same color twice.
const fullDiffHeader = Color(0xFF151B23);
const fullDiffControl = Color(0xF5363636);
const fullDiffDivider = Color(0xFF3D444D);
const fullDiffCanvas = Color(0xFF0D1117);
const fullDiffHunkHeader = Color(0xFF111D2E);
const fullDiffSelection = Color(0xFF0D273F);
const fullDiffSelectedChip = Color(0xFF273E52);
const fullDiffAccent = Color(0xFF83C4FF);
const fullDiffChip = Color(0xFF3A3A3A);
const fullDiffMuted = Color(0xFF9198A1);
const fullDiffAddedSource = Color(0xFF12261E);
const fullDiffAddedGutter = Color(0xFF1C4328);
const fullDiffDeletedSource = Color(0xFF25171C);
const fullDiffDeletedGutter = Color(0xFF542426);

// Word highlights really do sit on top of the line fill, so these keep
// Primer's own alpha instead of a pre-composited color.
const fullDiffAddedWord = Color(0x662EA043);
const fullDiffDeletedWord = Color(0x66F85149);

const fullDiffHatchBackground = Color(0xFF212830);
const fullDiffHatchStroke = Color(0xFF3D444D);
const fullDiffString = Color(0xFFFFBFA0);
const fullDiffMinimapTrack = Color(0xFF2F2F2F);
const fullDiffMinimapViewport = Color(0xFF353A3E);
const fullDiffMinimapRing = Color(0xC283C4FF);
const fullDiffMinimapAdded = Color(0xFF3FB950);
const fullDiffMinimapDeleted = Color(0xFFF85149);
const fullDiffDeletedMark = Color(0xFFF68B59);

const fullDiffControlHeight = 24.0;
const fullDiffControlRadius = 12.5;
const fullDiffChipRadius = 7.5;
const fullDiffMinimapWidth = 18.0;
const fullDiffLineNumberWidth = 74.0;

/// Side-by-side carries one number per side, so it needs far less room than
/// unified's two columns.
const fullDiffSideLineNumberWidth = 46.0;
