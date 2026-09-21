# ADR-0005: Release from the CHANGELOG head

- **Status:** Accepted
- **Date:** 2026-09-19
- **Deciders:** @mbiszczanik

## Context

SkyCraft keeps a Keep-a-Changelog `CHANGELOG.md` and semantic version tags.
Until now the tag and the GitHub Release were created by hand after the
merge, and the two drifted: v0.8.0 (the Bicep gold-path retrofit) sat
unreleased for weeks after its CHANGELOG section landed on `main`
(issue #82). Every release also had its notes pasted from the CHANGELOG
by hand, which is how the compare link at the bottom came to exist in
some releases and not others.

Two shapes were on the table: a workflow that releases automatically, or a
documented `gh release create` one-liner in `CONTRIBUTING.md`. A one-liner
still depends on someone remembering it after the merge, which is the
step that already failed.

## Decision

The CHANGELOG is the only place a version is written, and the release
follows it automatically.

- A release is the merge to `main` that turns `## [Unreleased]` into
  `## [X.Y.Z] - YYYY-MM-DD`. No version bump anywhere else.
- `.github/workflows/release.yml` runs on every push to `main` that changes
  `CHANGELOG.md`. It calls `tools/Publish-Release.ps1`, which reads the
  topmost released section, checks `gh release view vX.Y.Z`, and only when
  that release is missing runs `gh release create vX.Y.Z` on the merge
  commit with the section body plus a `**Full Changelog**` compare link as
  the notes. `gh` creates the tag in the same call.
- The same script is the manual path (`-Target <sha>` to backfill,
  `-WhatIf` to preview), so there is one release procedure, not two.
- The parser and the `gh` decision live in `tools/Changelog.psm1` and are
  pinned by `tests/Changelog.Tests.ps1` with the CLI injected, so the
  release logic is tested without a token and the repository's own
  `CHANGELOG.md` is checked on every CI run for a well-formed head.

## Consequences

- **Positive:** A versioned merge cannot be left unreleased. The tag, the
  release title and the notes cannot disagree with the CHANGELOG or with
  each other. Backfilling is the same command as the normal path.
- **Positive:** A CHANGELOG edit that adds no version - a typo fix, a new
  `Unreleased` item - is a no-op run, so the workflow is safe on every
  CHANGELOG change and needs no "is this a release?" heuristic.
- **Negative:** The head heading must be exact (`## [X.Y.Z] - YYYY-MM-DD`).
  A malformed one fails `tests/Changelog.Tests.ps1` in the PR rather than
  silently skipping the release, which is the intended failure mode.
- **Negative:** The workflow uses the job's `GITHUB_TOKEN` with
  `contents: write`. A release created by that token does not trigger
  other workflows, which is fine today because nothing listens for a
  release event.
- **Neutral:** A version is released at the commit that merges its
  CHANGELOG section. Squash-merging (ADR-0001) means that is also the
  commit carrying the code, so the tag lands where a reader expects it.
