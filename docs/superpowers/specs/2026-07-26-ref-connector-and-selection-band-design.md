# Ref Connector and Selection Band Design

## Goals

Render the horizontal line between a branch or tag chip and its commit node as
a solid 1 logical-pixel line.

Start a selected commit row's background at that commit's graph lane rather
than at the left edge of the Branch / Tag column.

## Connector Scope

- Change only the ref connector drawn for rows that show a branch or tag chip.
- Keep graph rails, transition curves, commit nodes, and chip borders unchanged.
- Keep the connector color and rounded line caps unchanged.
- Apply the same connector width at every graph compression stage.

## Selection Band Scope

- Use the selected commit's vertical graph line as the exact left edge of the
  selection background.
- Keep everything left of that line on the normal timeline background. This
  includes the Branch / Tag cell, its chip, the connector's surrounding area,
  and any earlier graph lanes.
- Render the branch or tag chip with its normal unselected styling.
- Keep the existing selected-row treatment to the right of the focused lane,
  including the graph tint and the Hash, Commit Message, Date, and Name cells.
- Do not change hover styling or date-heading selection behavior.

## Implementation

Use the existing `CommitGraphPainter.connectorWidth` constant as the single
source of truth and change its value from `2.0` to `1.0`. No new setting or
rendering mode is needed.

Paint the commit row on its normal background first. When the row is selected,
place the selected-row background behind its content starting at:

`Branch / Tag width + CommitGraphPainter.laneX(row.lane)`

Keep the painter's existing selected tint over the graph portion to the right
of that point. Do not pass the selected state into ref-chip styling.

## Verification

Add a painter test that renders a row with `refConnector: true` and verifies
that the horizontal connector uses a `1.0` stroke width.

Add widget tests that verify:

- the selected background begins at the focused lane's horizontal coordinate;
- the Branch / Tag cell and the graph area left of the lane retain the normal
  background;
- the ref chip retains its normal styling when its commit row is selected;
- the cells to the right remain selected.

Run the focused tests, the timeline test file, formatting, and static analysis.

## Non-goals

- Dashed connector styles
- User-configurable connector width
- Changes to vertical or curved graph lines
- Changes to selection behavior for date headings
- Changes to hover styling
