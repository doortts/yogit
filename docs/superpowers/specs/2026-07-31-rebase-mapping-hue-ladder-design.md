# Rebase Mapping Hue Ladder Design

## Goal

Match successful Rebase previews to the approved visual reference without changing the ordinary timeline graph.

## Mapping lines

- Derive every same-commit mapping color from the compare branch rail color.
- Keep the hue unchanged.
- Start with the oldest replayed commit at the lightest step derived from the compare branch color.
- Lower saturation and lightness one discrete step for each later replayed commit.
- Keep each mapping path one flat solid color. Do not use gradients.
- Use the mapping color as the border of both matching commit avatars.
- Preserve the existing maximum of five distinct mapping colors. Later mappings keep the fifth color instead of cycling back to a brighter color.

## Branch / Tag chips

- In Merge and Rebase previews only, inset Branch / Tag chips by 16 pixels on both sides.
- Keep ordinary timeline chip geometry unchanged.

## Reference

- Approved inline mockup: `/Users/doortts/.codex/visualizations/2026/07/29/019facff-4489-7e91-87c5-259f89c40a12/rebase-hue-ladder-preview.html`
- Repository reference: `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`
