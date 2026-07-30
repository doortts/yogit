# Branch Diff Status Bar and Sidebar Hover Design

## Goal

Make Branch Diff use the normal timeline status bar and keep sidebar branch
content stationary when hover feedback appears.

## Branch Diff Summary

- Remove the `두 부모` badge from clean and conflicting Merge previews.
- Keep the remaining preview result badges and branch direction unchanged.

## Status Bar

- Show the normal timeline status bar in both the default timeline and Branch
  Diff.
- Reuse the existing normal status bar widget so both modes show the same
  legend, focused ref, copy action, remote refresh error, and exact timestamp.
- Remove the comparison-only status bar because the preview summary already
  carries comparison details.

## Sidebar Hover

- Keep the icon, branch name, timestamp, HEAD badge, and behind count at the
  same coordinates before and during hover.
- Draw hover fill and its colored left edge on a separate background layer.
- Extend that background layer 5 pixels to the left without changing the row's
  layout or hit target.

## Verification

- Widget tests verify that `두 부모` is absent and the normal status bar remains
  visible in Branch Diff.
- A widget test compares branch content bounds before and after hover and checks
  that the hover background begins 5 pixels farther left.
- Run static analysis and the complete Flutter test suite before merging.
