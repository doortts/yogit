# Sidebar Section Styling Design

## Goal

Reduce the resting contrast of the sidebar search field and make the `LOCAL`,
`REMOTE`, and `TAGS` rows read as category headers without changing the tree
structure or interactions.

## Approved direction

Use mockup A, the thin section bar.

- The search field uses the active timeline palette instead of Material's
  default outline colors.
- Its resting outline uses `TimelineThemePalette.border`.
- Its focused outline uses `TimelineThemePalette.interactive`.
- Each category header gets a thin raised background with subtle top and bottom
  borders.
- Category icons, labels, and counts use a slightly stronger text color than
  tree metadata.
- Collapse behavior, counts, spacing below the header, and the tag overflow
  behavior stay unchanged.

## Implementation

Keep the change inside `TimelineScreen` in `lib/timeline.dart`.

- Add explicit `enabledBorder` and `focusedBorder` values to the existing search
  field decoration.
- Replace the category header's plain padding wrapper with a keyed decorated
  container.
- Derive every color from the selected `TimelineThemePalette` so System
  Graphite, Warm Graphite, and Carbon remain supported.
- Do not add a new theme token or a new reusable widget for these two local
  styling changes.

## Verification

Widget tests will verify:

1. The search field exposes the palette border while resting and the palette
   interactive color while focused.
2. Every category header exposes the approved raised fill and horizontal
   separator borders.
3. Existing tree filtering, collapsing, counts, and navigation tests remain
   green.

The full Flutter test suite, static analysis, and macOS debug build will run
before integration.
