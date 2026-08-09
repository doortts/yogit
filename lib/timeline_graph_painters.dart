import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'git.dart';
import 'timeline.dart';
import 'timeline_palette.dart';

class RebaseMergeResultPainter extends CustomPainter {
  const RebaseMergeResultPainter({
    required this.commitCount,
    required this.baseLabel,
    required this.mergeCommit,
    required this.railColor,
    required this.mutedColor,
  });

  final int commitCount;
  final String baseLabel;
  final bool mergeCommit;
  final Color railColor;
  final Color mutedColor;

  /// Past a dozen the dots would touch, so the label carries the exact count.
  static const maxDots = 12;
  static const _designWidth = 560.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    double x(double design) => design / _designWidth * size.width;
    void label(String text, double centerX, double top, Color color) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
        // 좁은 pane에서도 한 줄로 남아야 선과 점 위로 겹치지 않는다.
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          (centerX - painter.width / 2).clamp(0, size.width - painter.width),
          top,
        ),
      );
    }

    // 머지 커밋이 없으면 기준 브랜치 선이 재배치된 커밋으로 그대로 이어지니
    // 회색 구간은 기준 tip에서 끝난다.
    canvas.drawLine(
      Offset(x(20), 58),
      Offset(x(mergeCommit ? 540 : 130), 58),
      Paint()
        ..color = railColor
        ..strokeWidth = 2,
    );
    final dot = Paint()..color = mutedColor;
    canvas.drawCircle(Offset(x(60), 58), 5, dot);
    canvas.drawCircle(Offset(x(130), 58), 5, dot);
    label(baseLabel, x(95), 68, mutedColor);

    final path = mergeCommit
        ? (Path()
            ..moveTo(x(130), 58)
            ..cubicTo(x(170), 58, x(170), 26, x(210), 26)
            ..lineTo(x(400), 26)
            ..cubicTo(x(450), 26, x(450), 58, x(490), 58))
        : (Path()
            ..moveTo(x(130), 58)
            ..lineTo(x(470), 58));
    final rail = Paint()
      ..color = previewPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 9) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 5, metric.length)),
          rail,
        );
      }
    }

    final dots = math.min(commitCount, maxDots);
    final replayed = Paint()..color = previewPurple;
    final (from, to, y) = mergeCommit
        ? (210.0, 400.0, 26.0)
        : (140.0, 460.0, 58.0);
    for (var index = 0; index < dots; index++) {
      final at = from + (to - from) * (index + 1) / (dots + 1);
      canvas.drawCircle(Offset(x(at), y), 4.5, replayed);
    }

    if (!mergeCommit) {
      label(
        '재배치된 커밋 $commitCount개 — $baseLabel 선 위에 그대로 이어짐',
        x(300),
        34,
        previewPurple,
      );
      label('브랜치 tip', x(505), 51, mutedColor);
      return;
    }
    label('재배치된 커밋 $commitCount개', x(305), 2, previewPurple);
    canvas.drawCircle(
      Offset(x(490), 58),
      6,
      Paint()..color = previewPurplePanel,
    );
    canvas.drawCircle(
      Offset(x(490), 58),
      6,
      Paint()
        ..color = previewPurple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    label('머지 커밋', x(490), 70, previewPurple);
  }

  @override
  bool shouldRepaint(covariant RebaseMergeResultPainter oldDelegate) =>
      oldDelegate.commitCount != commitCount ||
      oldDelegate.baseLabel != baseLabel ||
      oldDelegate.mergeCommit != mergeCommit ||
      oldDelegate.railColor != railColor ||
      oldDelegate.mutedColor != mutedColor;
}

class RebaseMappingPainter extends CustomPainter {
  const RebaseMappingPainter({
    required this.rows,
    this.entries = const [],
    this.selectedIndex,
    required this.mappings,
    required this.rowIndex,
    required this.laneSpacing,
    required this.compact,
  }) : super(repaint: selectedIndex);

  final List<GraphRow> rows;
  final List<TimelineEntry> entries;
  final ValueListenable<int>? selectedIndex;
  final List<RebaseGraphMapping> mappings;
  final int rowIndex;
  final double laneSpacing;
  final bool compact;

  double _laneX(int lane) => compact
      ? CommitGraphPainter.laneInset
      : CommitGraphPainter.laneInset + lane * laneSpacing;

  String? get _focusedSha {
    final index = selectedIndex?.value;
    if (index == null || index < 0 || index >= entries.length) return null;
    final entry = entries[index];
    return entry.rowIndex < 0 ? null : entry.row.commit.sha;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (compact || size.isEmpty || rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    final deepest = rows.fold<int>(
      0,
      (value, row) => math.max(value, row.maxLane),
    );
    final firstRouteX = _laneX(deepest + 1);
    final routeSpacing = laneSpacing / 2;
    final fitsAll = mappings.every(
      (mapping) =>
          firstRouteX + mapping.routeLane * routeSpacing <= size.width - 1,
    );
    final visibleMappings = fitsAll
        ? mappings
        : mappings
              .where(
                (mapping) =>
                    mapping.originalSha == _focusedSha ||
                    mapping.rewrittenSha == _focusedSha,
              )
              .take(1);
    final centerY = size.height / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final mapping in visibleMappings) {
      final top = math.min(mapping.rewrittenRow, mapping.originalRow);
      final bottom = math.max(mapping.rewrittenRow, mapping.originalRow);
      if (rowIndex < top || rowIndex > bottom) continue;
      final routeX = fitsAll
          ? firstRouteX + mapping.routeLane * routeSpacing
          : math.min(firstRouteX, size.width - 1);
      final rewrittenX = _laneX(rows[mapping.rewrittenRow].lane);
      final originalX = _laneX(rows[mapping.originalRow].lane);
      final path = Path();
      if (rowIndex == mapping.rewrittenRow) {
        path
          ..moveTo(routeX, size.height + 1)
          ..lineTo(routeX, centerY + 6)
          ..quadraticBezierTo(routeX, centerY, routeX - 6, centerY)
          ..lineTo(rewrittenX + CommitGraphPainter.avatarDiameter / 2, centerY);
      } else if (rowIndex == mapping.originalRow) {
        path
          ..moveTo(originalX + CommitGraphPainter.avatarDiameter / 2, centerY)
          ..lineTo(routeX - 6, centerY)
          ..quadraticBezierTo(routeX, centerY, routeX, centerY - 6)
          ..lineTo(routeX, -1);
      } else {
        path
          ..moveTo(routeX, -1)
          ..lineTo(routeX, size.height + 1);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = mapping.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (rowIndex == mapping.rewrittenRow) {
        final tip = Offset(
          rewrittenX + CommitGraphPainter.avatarDiameter / 2,
          centerY,
        );
        final arrow = Path()
          ..moveTo(tip.dx + 5, tip.dy - 4)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(tip.dx + 5, tip.dy + 4);
        canvas.drawPath(
          arrow,
          Paint()
            ..color = mapping.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RebaseMappingPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.entries != entries ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.mappings != mappings ||
      oldDelegate.rowIndex != rowIndex ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact;
}

/// Draws one row of the commit graph: pass-through rails, the rounded lane
/// curves into parent lanes, and the row's own node.
class CommitGraphPainter extends CustomPainter {
  CommitGraphPainter({
    required this.row,
    required this.selected,
    required this.committerColor,
    this.previous,
    this.committersBySha = const {},
    this.laneSpacing = defaultLaneSpacing,
    this.compact = false,
    this.refConnector = false,
    this.passThrough = false,
    this.dashedLanes = const {},
    this.previousDashedLanes = const {},
    this.previewRailColor,
    this.previewMergeArrow = false,
    this.outgoingRailColor,
    this.backgroundColor = const Color(0xFF1C1C1E),
    this.selectedRowColor = const Color(0xFF234D72),
  }) : baseBranchColor = AvatarService.baseBranchColor;

  static const laneInset = 28.0;
  static const defaultLaneSpacing = 30.0;
  static const previewLaneSpacing = 49.0;
  static const railWidth = AvatarService.railWidth;
  static const previewRailWidth = 1.0;
  static const avatarDiameter = 18.0;
  static const hashRailClearance = 3.0;

  /// Stage 3: at or below this cell width the graph collapses to one lane.
  static const compactWidth = 56.0;

  /// Stage 2 floor.
  static const minLaneSpacing = 12.0;

  /// Half the node avatar plus the required gap before the hash column's rail.
  static const nodeExtent = avatarDiameter / 2 + hashRailClearance;

  /// The narrowest cell that still shows every node whole. Empty space right of
  /// it clips away before any lane moves.
  static double contentWidth(
    int deepestLane, {
    double laneSpacing = defaultLaneSpacing,
  }) => laneInset + deepestLane * laneSpacing + nodeExtent;

  /// Stage 1 (the cell still holds the rightmost node) keeps
  /// [defaultLaneSpacing]; stage 2 squeezes the lanes so that node stays just
  /// inside the cell.
  static double spacingFor(
    double width,
    int deepestLane, {
    double maxLaneSpacing = defaultLaneSpacing,
  }) {
    if (width >= contentWidth(deepestLane, laneSpacing: maxLaneSpacing)) {
      return maxLaneSpacing;
    }
    return ((width - laneInset - nodeExtent) / math.max(deepestLane, 1)).clamp(
      minLaneSpacing,
      maxLaneSpacing,
    );
  }

  /// Rails are opaque.
  static const railOpacity = 1.0;
  static const connectorWidth = 1.0;

  /// The node disc's own radius, so the ref connector's arrow stops the same
  /// [refArrowGap] short of an avatar as it does of a merge dot.
  static const avatarRadius = avatarDiameter / 2;
  static const refArrowGap = 4.0;
  static const refArrowLength = 7.0;
  static const refArrowHalfHeight = 5.0;
  static const nodeRadius = 6.0;
  static const wipNodeRadius = 8.0;
  static const wipNodeDash = 2.5;

  /// Every transition turns on one quarter arc of this radius beside the node it
  /// belongs to, so the horizontal run into or out of that node stays long and
  /// readable.
  static const cornerRadius = 8.0;

  final GraphRow row;
  final bool selected;
  final Color backgroundColor;
  final Color selectedRowColor;
  final Color baseBranchColor;

  /// The color of the branch line this row's node sits on: `row.branch` through
  /// the settings palette. Named for history — nothing here is per-committer.
  final Color committerColor;

  /// The row above. A lane transition sweeps a full row height, so its arrival
  /// half belongs to this row's cell and is derived from [previous].
  final GraphRow? previous;
  final Map<String, GitIdentity> committersBySha;
  final double laneSpacing;

  /// Stage 3: every lane collapses onto [laneInset] and only the row's own rail
  /// and node survive.
  final bool compact;

  /// Whether this row shows ref chips, which the cell to the left resolves from
  /// both `for-each-ref` tips and the log decorations.
  final bool refConnector;

  /// A date heading: the rails and the arriving sweeps run through it, but it
  /// owns no node, no selected band and no ref connector.
  final bool passThrough;
  final Set<int> dashedLanes;
  final Set<int> previousDashedLanes;

  /// Whether this row is a merge preview's virtual commit. Its dashed second
  /// parent edge then ends in an arrowhead, so the line reads as the compare
  /// branch arriving at the merge rather than leaving it.
  final bool previewMergeArrow;
  final Color? previewRailColor;
  final Color? outgoingRailColor;

  bool isDashedLane(int lane) => dashedLanes.contains(lane);
  bool isDashedAbove(int lane) =>
      isDashedLane(lane) || previousDashedLanes.contains(lane);

  /// A lane movement is a preview line when the lane it LEAVES is dashed;
  /// [above] asks the row that started it. The lane it arrives in is never
  /// asked — a real branch converging on a lane the preview borrows is still
  /// real history and keeps its solid rail.
  bool isDashedTransition(LaneTransition transition, {bool above = false}) =>
      (above ? previousDashedLanes : dashedLanes).contains(transition.from);

  double laneX(int lane) =>
      compact ? laneInset : laneInset + lane * laneSpacing;

  double get refMarkerRadius {
    if (row.commit.isWorkingTree) return wipNodeRadius;
    if (showsMergeDot) return nodeRadius;
    return avatarRadius;
  }

  double get refArrowTipX => laneX(row.lane) - refMarkerRadius - refArrowGap;

  Path refArrowheadPath(double centerY) {
    final tipX = refArrowTipX;
    return Path()
      ..moveTo(tipX - refArrowLength, centerY - refArrowHalfHeight)
      ..lineTo(tipX, centerY)
      ..lineTo(tipX - refArrowLength, centerY + refArrowHalfHeight);
  }

  /// The arrowhead is stroked at the dashed rail's own weight, not the solid
  /// rail's: at [railWidth] the head came out twice as heavy as the line it
  /// closes and as every other arrow in the graph.
  Paint previewMergeArrowPaint() => Paint()
    ..color = previewRailColor ?? committerColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = previewRailWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// The arrowhead closing the dashed merge edge, or null when this row has no
  /// such edge. The tip sits one node-radius plus a gap from the node center,
  /// on the side the edge leaves toward, and points back at the node.
  Path? previewMergeArrowheadPath(double centerY) {
    if (!previewMergeArrow) return null;
    final edge = row.transitions
        .where(
          (transition) =>
              transition.from == row.lane && isDashedLane(transition.to),
        )
        .firstOrNull;
    if (edge == null) return null;
    // Which way the edge leaves decides which way the head points.
    final direction = laneX(edge.to) > laneX(edge.from) ? 1.0 : -1.0;
    final tipX = laneX(row.lane) + direction * (nodeRadius + refArrowGap);
    final baseX = tipX + direction * refArrowLength;
    return Path()
      ..moveTo(baseX, centerY - refArrowHalfHeight)
      ..lineTo(tipX, centerY)
      ..lineTo(baseX, centerY + refArrowHalfHeight);
  }

  /// A line being born out of this row's node: the second-or-later parent edge of
  /// a merge. Everything else is an existing line moving — a foreign column
  /// converging on its parent, or this row's own first-parent tail. Color and
  /// geometry both hang off this one question.
  static bool isMergeEdge(GraphRow row, LaneTransition transition) =>
      transitionBendsAtSource(row, transition);

  /// The branch line a sweep belongs to, so a whole line keeps one color:
  /// a foreign column converging on its parent stays its own line's color, a
  /// commit's first-parent tail stays the commit's, and only a merge edge to a
  /// further parent takes the line it lands in. Null falls back to the sha color.
  static int? transitionBranch(GraphRow row, LaneTransition transition) {
    if (transition.from != row.lane) {
      return row.activeLaneBranches[transition.from];
    }
    return isMergeEdge(row, transition)
        ? row.nextLaneBranches[transition.to]
        : row.branch;
  }

  /// The single rail stage 3 paints, colored by this row's committer.
  ({double top, double bottom}) compactRail(Size size) => (
    top: (previous?.nextLanes.isNotEmpty ?? false) ? 0.0 : size.height / 2,
    bottom: row.nextLanes.isEmpty ? size.height / 2 : size.height,
  );

  /// The straight vertical rails [row] hands down past its node center, keyed by
  /// lane. A rail that moves — a branch, a merge, or a git-style collapse slide —
  /// is left to its transition path, and so is a lane a movement lands in that
  /// carried no rail of its own.
  static Set<int> railsBelow(GraphRow row) {
    final departing = {
      for (final transition in row.transitions) transition.from,
    };
    final joining = {
      for (final transition in row.transitions)
        if (!transitionBendsAtSource(row, transition)) transition.from,
    };
    final arriving = {for (final transition in row.transitions) transition.to};
    return {
      for (final lane in row.nextLanes)
        if (lane == row.lane
            // Keep the first-parent rail when another branch joins it. A lane
            // filled only by a collapsing slide remains owned by the curve.
            ? !joining.contains(lane) &&
                  (!arriving.contains(lane) ||
                      (row.parentLanes.isNotEmpty &&
                          row.parentLanes.first == lane))
            : row.activeLanes.contains(lane) && !departing.contains(lane))
          lane,
    };
  }

  /// True when a rail reaches this row vertically in [lane]. A branch tip starts
  /// its lane here and an arriving curve owns its own top half, so neither gets
  /// a straight segment above the node.
  bool continuesFromAbove(int lane) {
    if (previous case final previous?) {
      return railsBelow(previous).contains(lane);
    }
    return false;
  }

  /// Straight vertical rail segments this row paints, keyed by lane. A lane that
  /// arrives or departs on a curve gets no straight segment over that half, so
  /// the curve is never overdrawn.
  Map<int, ({double top, double bottom})> laneVerticals(Size size) {
    final centerY = size.height / 2;
    final below = railsBelow(row);
    final verticals = <int, ({double top, double bottom})>{};
    for (final lane in {...row.activeLanes, ...row.nextLanes}) {
      final top = continuesFromAbove(lane) ? 0.0 : centerY;
      final bottom = below.contains(lane) ? size.height : centerY;
      if (bottom > top) verticals[lane] = (top: top, bottom: bottom);
    }
    return verticals;
  }

  /// Merge commits replace the avatar stack with a filled lane-colored dot.
  bool get showsMergeDot =>
      !row.commit.isWorkingTree && row.commit.parents.length >= 2;

  Rect selectedBandRect(Size size) =>
      Rect.fromLTRB(laneX(row.lane), 0, size.width, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    if (selected && !passThrough) {
      canvas.drawRect(
        selectedBandRect(size),
        Paint()..color = committerColor.withValues(alpha: 0.22),
      );
    }

    if (compact) {
      // Stage 3: one rail in this row's committer color, no lanes, no curves.
      final rail = compactRail(size);
      void draw(double top, double bottom, {required bool dashed}) {
        if (bottom <= top) return;
        final paint = Paint()
          ..color = dashed ? previewRailColor ?? committerColor : committerColor
          ..strokeWidth = dashed ? previewRailWidth : railWidth
          ..strokeCap = StrokeCap.round;
        _drawVerticalRail(
          canvas,
          Offset(laneInset, top),
          Offset(laneInset, bottom),
          paint,
          dashed: dashed,
        );
      }

      draw(
        rail.top,
        math.min(rail.bottom, centerY),
        dashed: isDashedAbove(row.lane),
      );
      draw(
        math.max(rail.top, centerY),
        rail.bottom,
        dashed: isDashedLane(row.lane),
      );
    } else {
      // Halves are painted apart: above the node a lane carries the rail it
      // waits for, below it the rail it hands down.
      for (final entry in laneVerticals(size).entries) {
        final x = laneX(entry.key);
        if (entry.value.top < centerY) {
          final dashed = isDashedAbove(entry.key);
          final paint = _railPaint(
            row.activeLaneBranches[entry.key],
            row.activeLaneShas[entry.key],
            dashed: dashed,
          );
          _drawVerticalRail(
            canvas,
            Offset(x, entry.value.top),
            Offset(x, centerY),
            paint,
            dashed: dashed,
          );
        }
        if (entry.value.bottom > centerY) {
          final dashed = isDashedLane(entry.key);
          final paint = _railPaint(
            row.nextLaneBranches[entry.key],
            row.nextLaneShas[entry.key],
            dashed: dashed,
            colorOverride: entry.key == row.lane ? outgoingRailColor : null,
          );
          _drawVerticalRail(
            canvas,
            Offset(x, centerY),
            Offset(x, entry.value.bottom),
            paint,
            dashed: dashed,
          );
        }
      }

      // Arrival halves of the movements the row above started, then this row's
      // own departures. Every lane movement is a transition, so the two lists
      // are the whole story.
      if (previous case final previous?) {
        for (final transition in previous.transitions) {
          final dashed = isDashedTransition(transition, above: true);
          _drawRailPath(
            canvas,
            transitionPath(
              transition.from,
              transition.to,
              centerY - size.height,
              size,
              // Classified against the row that started it, so the arrival half
              // repeats its departure half's shape and color exactly.
              bendEarly: isMergeEdge(previous, transition),
            ),
            _railPaint(
              transitionBranch(previous, transition),
              transition.sha,
              dashed: dashed,
            ),
            dashed: dashed,
          );
        }
      }
      for (final transition in row.transitions) {
        final dashed = isDashedTransition(transition);
        _drawRailPath(
          canvas,
          transitionPath(
            transition.from,
            transition.to,
            centerY,
            size,
            bendEarly: isMergeEdge(row, transition),
          ),
          _railPaint(
            transitionBranch(row, transition),
            transition.sha,
            dashed: dashed,
          ),
          dashed: dashed,
        );
      }
    }
    if (passThrough) return;
    final nodeX = laneX(row.lane);
    if (previewMergeArrowheadPath(centerY) case final head?) {
      canvas.drawPath(head, previewMergeArrowPaint());
    }
    if (refConnector) {
      final connectorPaint = Paint()
        ..color = committerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = connectorWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(refArrowTipX, centerY),
        connectorPaint,
      );
      canvas.drawPath(refArrowheadPath(centerY), connectorPaint);
    }
    _drawNode(canvas, Offset(nodeX, centerY));
  }

  /// The node glyph: a dashed ring for the working tree, a filled dot for a
  /// merge, and nothing for a plain commit — its avatar stack sits on top.
  void _drawNode(Canvas canvas, Offset center) {
    if (row.commit.isWorkingTree) {
      _drawWorkingTreeNode(canvas, center);
    } else if (showsMergeDot) {
      canvas.drawCircle(center, nodeRadius, Paint()..color = committerColor);
    }
  }

  /// The working tree ring takes the color of the branch line it sits on, which
  /// for the working tree row is the line `HEAD` is on.
  Color get workingTreeRingColor {
    final branch =
        row.nextLaneBranches[row.lane] ?? row.activeLaneBranches[row.lane];
    return branch == null
        ? AvatarService.color(
            committersBySha[row.nextLaneShas[row.lane] ??
                    row.activeLaneShas[row.lane]] ??
                row.commit.committer,
          )
        : AvatarService.branchColor(branch);
  }

  /// The node fill hides the rail behind it, so it has to match the row it sits
  /// on rather than the global background.
  Color get nodeFillColor => selected ? selectedRowColor : backgroundColor;

  /// The working tree node is a dashed ring, so it reads as pending next to the
  /// avatars that mark real commits.
  void _drawWorkingTreeNode(Canvas canvas, Offset center) {
    canvas.drawCircle(center, wipNodeRadius, Paint()..color = nodeFillColor);
    drawDashedRing(
      canvas,
      center,
      wipNodeRadius,
      Paint()
        ..color = workingTreeRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = railWidth
        ..strokeCap = StrokeCap.round,
      wipNodeDash,
    );
  }

  /// One lane transition, spanning a row height from a node center at [startY] to
  /// the next row's center. Both rows paint the same path — the child from its own
  /// center, the next row with [startY] a row height above its center — so the
  /// halves meet exactly.
  ///
  /// Each kind turns on a single [cornerRadius] quarter arc, horizontal where it
  /// meets its node, so the line reads as entering or leaving that node sideways:
  ///
  /// * [bendEarly] — a line being born runs flat out of its source's side, then
  ///   arcs down into the vertical of its new column.
  /// * otherwise — a line joining its parent runs down its own column, arcs onto
  ///   the parent's own level, and runs flat into the dot from the side. Nothing
  ///   rides the parent's rail, and the dying branch leaves no stub.
  ///
  /// The flat run carries whatever distance the corner does not.
  Path transitionPath(
    int from,
    int to,
    double startY,
    Size size, {
    bool bendEarly = false,
  }) {
    final x0 = laneX(from);
    final x1 = laneX(to);
    final endY = startY + size.height;
    final direction = x1 > x0 ? 1.0 : -1.0;
    final corner = math.min(
      math.min(cornerRadius, (x1 - x0).abs() / 2),
      endY - startY,
    );
    if (bendEarly) {
      return Path()
        ..moveTo(x0, startY)
        ..lineTo(x1 - direction * corner, startY)
        ..quadraticBezierTo(x1, startY, x1, startY + corner)
        ..lineTo(x1, endY);
    }
    return Path()
      ..moveTo(x0, startY)
      ..lineTo(x0, endY - corner)
      ..quadraticBezierTo(x0, endY, x0 + direction * corner, endY)
      ..lineTo(x1, endY);
  }

  /// A rail paints in its branch line's color. Before [GraphRow] carries branch
  /// ids for a lane it falls back to the committer color, so the graph degrades
  /// to the old look instead of to one flat color.
  Paint _railPaint(
    int? branch,
    String? sha, {
    bool dashed = false,
    Color? colorOverride,
  }) => Paint()
    ..color = dashed && previewRailColor != null
        ? previewRailColor!
        : colorOverride ??
              (branch == null
                  ? AvatarService.color(
                      committersBySha[sha] ?? row.commit.committer,
                    )
                  : branch == 0
                  ? AvatarService.branchAssignments[0] ?? baseBranchColor
                  : AvatarService.branchColor(branch))
    ..style = PaintingStyle.stroke
    ..strokeWidth = dashed ? previewRailWidth : railWidth
    ..strokeCap = StrokeCap.round
    // Mitered, so a join's square corner renders as a crisp right angle. Curves
    // are unaffected.
    ..strokeJoin = StrokeJoin.miter;

  void _drawVerticalRail(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }
    _drawRailPath(
      canvas,
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy),
      paint,
      dashed: true,
    );
  }

  void _drawRailPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 6) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 3, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CommitGraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.previous != previous ||
      oldDelegate.selected != selected ||
      oldDelegate.committerColor != committerColor ||
      oldDelegate.baseBranchColor != baseBranchColor ||
      oldDelegate.committersBySha != committersBySha ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact ||
      oldDelegate.refConnector != refConnector ||
      oldDelegate.passThrough != passThrough ||
      !setEquals(oldDelegate.dashedLanes, dashedLanes) ||
      !setEquals(oldDelegate.previousDashedLanes, previousDashedLanes) ||
      oldDelegate.previewRailColor != previewRailColor ||
      oldDelegate.outgoingRailColor != outgoingRailColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.selectedRowColor != selectedRowColor;
}

/// Dashes a ring by walking its perimeter. The dash count is FITTED to that
/// perimeter — whole [dash] + [gap] periods only, [gap] defaulting to [dash] —
/// so the pattern closes at the seam instead of butting a clipped dash against
/// a full one.
void drawDashedRing(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint,
  double dash, {
  double? gap,
}) {
  final period = dash + (gap ?? dash);
  final ring = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  for (final metric in ring.computeMetrics()) {
    final count = math.max(1, (metric.length / period).round());
    final step = metric.length / count;
    for (var i = 0; i < count; i++) {
      canvas.drawPath(
        metric.extractPath(i * step, i * step + step * dash / period),
        paint,
      );
    }
  }
}

/// A virtual commit's node: the same filled disc and the same ring color and
/// width as a real node's, but the ring is DASHED — the commit does not exist
/// yet, just like the dashed rails that lead into it. A `BoxDecoration` border
/// can only be solid, so the ring moves onto the canvas.
class DashedRingNodePainter extends CustomPainter {
  const DashedRingNodePainter({
    required this.fill,
    required this.ring,
    required this.ringWidth,
  });

  /// Denser than the rails' dash, so it still reads as a dash around a circle
  /// this small.
  static const dash = 4.0;
  static const gap = 3.0;

  final Color fill;
  final Color ring;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Same geometry as the BoxDecoration this replaces: the disc fills the box
    // and the ring is stroked just inside its edge.
    final radius = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, radius, Paint()..color = fill);
    drawDashedRing(
      canvas,
      center,
      radius - ringWidth / 2,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
      dash,
      gap: gap,
    );
  }

  @override
  bool shouldRepaint(covariant DashedRingNodePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.ring != ring ||
      oldDelegate.ringWidth != ringWidth;
}
