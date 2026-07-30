# Preview Virtual Rail and Arrow Design

## Goal

Match Merge and Rebase previews to the approved graph rules without changing the ordinary timeline.

## Branch / Tag boxes

- In Merge and Rebase previews, inset every Branch / Tag box by 14 pixels on both sides.
- Keep ordinary timeline box geometry unchanged.

## Virtual rails

- Every segment that connects a real commit to a virtual Merge or Rebase commit uses the preview color.
- The whole virtual segment is a 1-pixel dashed line. No part of that segment may inherit a solid real-branch rail.
- Real branch history remains solid and keeps its existing color, width, curves, and connection rules.
- The rule also applies when the graph collapses to its compact single-lane layout.

## Rebase mapping arrows

- Same-commit mapping lines remain 1-pixel solid lines.
- Replace the filled triangular arrowhead with an open chevron made from a 1-pixel stroke.
- Keep the arrowhead and its mapping line the same color.

## Reference

- Approved mockup: `/Users/doortts/.codex/visualizations/2026/07/29/019facff-4489-7e91-87c5-259f89c40a12/preview-virtual-rail-arrow-v2.html`
- Repository reference: `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`

