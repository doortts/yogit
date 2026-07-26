# Ref Connector Line Design

## Goal

Render the horizontal line between a branch or tag chip and its commit node as
a solid 1 logical-pixel line.

## Scope

- Change only the ref connector drawn for rows that show a branch or tag chip.
- Keep graph rails, transition curves, commit nodes, and chip borders unchanged.
- Keep the connector color and rounded line caps unchanged.
- Apply the same connector width at every graph compression stage.

## Implementation

Use the existing `CommitGraphPainter.connectorWidth` constant as the single
source of truth and change its value from `2.0` to `1.0`. No new setting or
rendering mode is needed.

## Verification

Add a painter test that renders a row with `refConnector: true` and verifies
that the horizontal connector uses a `1.0` stroke width. Run the focused test,
the timeline test file, formatting, and static analysis.

## Non-goals

- Dashed connector styles
- User-configurable connector width
- Changes to vertical or curved graph lines
