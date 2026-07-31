# Preview Diff Resizer Hover Line Design

## Goal

Make the left/right preview diff splitter discoverable without adding a permanent visual accent.

## Behavior

- Keep the existing neutral one-pixel pane border at rest.
- Use a 12 logical-pixel invisible pointer target around the divider.
- While the pointer is inside that target, draw a centered two-pixel `#5AB0FF` vertical line.
- Remove the blue line immediately when the pointer leaves, including after a drag.
- Do not change the bottom preview's horizontal splitter or any resize calculations.

## Implementation

Reuse `TimelineScreen._previewDiffResizer`. One boolean owned by `TimelineScreen` records whether the active left/right splitter is hovered. The existing `MouseRegion` updates it and the existing `GestureDetector` keeps all drag behavior.

## Verification

A widget test opens a right-side preview diff, moves a mouse onto and away from the splitter, and checks the line color at rest, on hover, and after exit. Existing resize endpoint and persistence tests remain unchanged.
