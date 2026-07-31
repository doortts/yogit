# Preview Scroll Priority Design

## Goal

Make `Shift+Command+Up/Down` scroll only preview content that can move in the requested direction, with an open adjacent diff taking priority.

## Target selection

1. If the adjacent diff is open and its controller can move in the requested direction, scroll the diff.
2. Otherwise, if the preview details and file list can move in that direction, scroll the preview.
3. Otherwise, consume the shortcut without moving the timeline or another screen.

Reaching one end of the diff allows the preview to receive the next shortcut when it still has content in that direction.

## Existing behavior retained

- `Command+Up/Down` continues to move through changed files.
- Pointer and trackpad scrolling remain local to the pane under the pointer.
- The shortcut label and half-viewport scroll distance do not change.

## Verification

A widget test opens a scrollable adjacent diff while the preview is also scrollable. It verifies diff-first scrolling, preview fallback at the diff boundary, and no movement when both panes are at their boundary.
