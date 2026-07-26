# Ref Connector Arrowhead Design

## Goal

Make the branch and tag connector point clearly at its commit by replacing the
connector's plain end with an open arrowhead.

The approved visual combines option B's open chevron with option C's small gap
before the commit marker.

## Appearance

- Keep the horizontal connector and arrowhead at `1.0` logical pixel.
- Draw an open chevron rather than a filled triangle.
- Use the connector's existing branch color for the shaft and arrowhead.
- Keep round stroke caps and use a round stroke join.
- Leave `4.0` logical pixels between the arrow tip and the visible edge of the
  commit marker.
- Make the chevron `7.0` logical pixels long and `10.0` logical pixels tall.

The connector shaft reaches the arrow tip. Two diagonal strokes return from
the tip toward the chip, forming the open chevron.

## Marker-Aware Positioning

The visible marker size varies by row, so the arrow tip uses the marker's
actual radius:

- ordinary commit avatar: `11.0` logical pixels;
- merge commit dot: `CommitGraphPainter.nodeRadius`;
- working-tree ring: `CommitGraphPainter.wipNodeRadius`.

For every ref row:

`arrowTipX = laneX(row.lane) - markerRadius - 4.0`

This keeps the perceived gap consistent for avatars, merge dots, and
working-tree rings. The calculation continues to work when lane spacing is
compressed or the graph collapses to its compact lane.

## Rendering

Keep the behavior inside `CommitGraphPainter`.

When `refConnector` is true:

1. calculate the visible marker radius;
2. calculate `arrowTipX`;
3. draw the horizontal shaft from the graph cell's left edge to the arrow tip;
4. draw the two diagonal chevron strokes;
5. draw the commit marker after the connector so the marker remains visually
   dominant.

Rows without refs and pass-through date headings do not draw a connector or
arrowhead.

## Unchanged Behavior

- Branch and tag chip layout and colors
- The selected-row background boundary
- Graph rails, merge curves, and lane colors
- Commit avatars, merge dots, and working-tree rings
- Hover behavior and date-heading selection
- The graph column's compression stages

## Verification

Painter tests will verify that:

- the shaft and chevron use a `1.0` stroke width and the branch color;
- the ordinary commit arrow tip is `4.0` pixels from the avatar edge;
- merge and working-tree rows use their own marker radii;
- compact graph mode preserves the same marker gap;
- rows without refs and pass-through date headings draw no arrowhead.

The existing connector, date-heading, selection-band, and graph geometry tests
must continue to pass.

## Non-goals

- Filled arrowheads
- A user-configurable arrow style, size, or gap
- Arrowheads on vertical rails or merge curves
- Changes to chip-to-graph spacing
