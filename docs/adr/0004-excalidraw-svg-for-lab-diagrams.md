# ADR-0004: Author lab architecture diagrams in Excalidraw, commit as SVG

- **Status:** Accepted
- **Date:** 2026-09-05
- **Deciders:** @mbiszczanik

## Context

Lab guides carried 26 Mermaid diagrams across 22 files. Mermaid was chosen for
one strong reason: GitHub renders it natively, so no binary artifact has to be
committed. Two problems surfaced.

First, quality. A bake-off on Lab 2.1 (hub-spoke) and Lab 2.2 (Bastion/NSG/ASG)
compared Mermaid against two alternatives: a JSON-driven interactive HTML
generator, and the Excalidraw skill. Rendering the existing Lab 2.1 Mermaid
block exposed a defect that had been in the repo since the beginning — ten
subnets are declared but never connected to their VNets, so they render as
floating rectangles. The diagram never actually said that `AuthSubnet` belongs
to the dev VNet. Mermaid's auto-layout also reversed the intended column order
and left the resource-group subgraphs default yellow.

Second, teaching capacity. The Excalidraw version of Lab 2.2 carried facts the
other two could not express at all: that NSG rules are evaluated lowest-number
first and stop at the first match, that a peering is two objects rather than
one, and real `az` commands with real error strings. The JSON generator models a
`services + connections` graph, which has no notion of evaluation order — that
is a modelling limit, not a rendering one, and no amount of styling fixes it.

We then measured whether committing images is actually acceptable. GitHub serves
SVG byte-for-byte, preserves the `<style>` block, and loads an embedded
`@font-face`, verified on a live branch. `<picture>` with `prefers-color-scheme`
works there too. SVG is 53–66 KB against 174 KB for the equivalent PNG, stays
crisp at any zoom, and keeps text selectable by Ctrl+F.

## Decision

We author the Architecture Overview diagram of every lab in Excalidraw and
commit three files: the `.excalidraw` source, a light `.svg`, and a dark `.svg`.
They are embedded with `<picture>`.

Two constraints are mandatory, both derived from measurement rather than taste:

1. **Author at ≤860 units wide.** GitHub's README column is ~861 css px on a
   1280 px laptop. At 1900 units the diagram renders at 0.45x and 11 px body
   text becomes 5.4 px — the evidence artifacts that justify this format are the
   first thing to become unreadable. Sections stack vertically.
2. **Nothing in the source may be deliberately dark.** The dark export is a
   colour inversion, so a dark panel inverts to light. Code panels are light
   fill with dark text.

Mermaid is legacy. Existing blocks stay until touched; new ones are not added.

## Consequences

**What we gain.** Diagrams that argue instead of listing inventory, full layout
control, one artifact set that serves both github.com and a future GitHub Pages
site, theme-aware rendering, searchable text, and smaller files than PNG.

**What we accept as cost.** Authoring is roughly 8 minutes per diagram against
about 5 for Mermaid, and the body layout does not transfer between diagrams —
only the header strip, section-title convention, evidence row and palette do,
roughly 40% reuse. Diffs stop being readable: 700 lines of coordinates instead
of 29 lines of text, so review means looking at the rendered SVG. Code panels
lose the terminal look in light mode, which is the price of rule 2. The
toolchain now depends on `uv`, Playwright and a CDN fetch at render time.

**Follow-up work this creates.**

- Convert the 26 existing Mermaid diagrams, narrowest-value-first.
- While converting, fix the missing VNet→subnet containment edges; the Lab 2.1
  defect is unlikely to be the only instance.
- Re-author the two bake-off diagrams (Lab 2.1 and the first Lab 2.2 draft) —
  both are 1900 units wide and violate rule 1.

## Alternatives considered

**Stay on Mermaid.** Rejected once we accepted committing images: its single
decisive advantage was native GitHub rendering, and nothing else about it wins.

**JSON → interactive HTML generator.** Produced the most Azure-portal-like
output and is the only option that could be generated from Bicep, which keeps
diagrams in sync with infrastructure. Rejected because its interactivity is lost
in a README, it degrades badly past ~13 nodes (edges cross whole columns,
vertical stacking implies a sequence that does not exist), and its data model
cannot express evaluation order. Worth revisiting only if a documentation site
is built and diagram-from-code becomes the goal.
