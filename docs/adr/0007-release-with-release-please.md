# ADR-0007: Release with release-please from Conventional Commits PR titles

- **Status:** Accepted
- **Date:** 2026-09-21
- **Deciders:** @mbiszczanik

## Context

ADR-0005 made `CHANGELOG.md` the release trigger: renaming `## [Unreleased]`
to `## [X.Y.Z] - date` and merging created the tag and the GitHub Release.
One manual step remained, and it was the one that needed judgement: pick the
version number, pick the moment, edit the heading. Nobody else in the project
could tell from the diff whether 0.8.0 → 0.9.0 or → 0.8.1 was right.

A survey of how this is done elsewhere (2026-09-21) found one dominant
standard: the version bump is derived from Conventional Commits
(`fix` → patch, `feat` → minor, breaking change → major; other types do not
release), delivered either continuously on every merge (semantic-release,
which refuses `0.x` versions) or through a bot-maintained **Release PR**
that a human merges when ready (release-please, changesets). Azure Verified
Modules enforce Conventional Commits on PR titles and squash-merge. Pre-1.0,
SemVer's own FAQ increments the minor version for every `0.y.z` release,
and AVM SNFR17 bumps the minor version for breaking changes and features.

Constraints that shaped the choice:

- `main` is protected with no bypass actors (ADR-0002); a bot cannot push
  to it, it has to open a pull request that passes the required checks.
- A pull request opened with `GITHUB_TOKEN` gets its workflow runs only
  after a maintainer clicks *Approve workflows to run* (before mid-2026 it
  got none at all), so every Release PR would wait on a manual click before
  its required checks start. GitHub's documented remedy is a personal
  access token or a GitHub App installation token.
- Squash merges are the only merge method, so every commit on `main` has
  exactly one title, and that title is chosen in the PR.

## Decision

- **We use release-please** (`googleapis/release-please-action`) with the
  `simple` release type. On every push to `main` it opens or refreshes
  `chore(main): release X.Y.Z`; merging that PR creates `vX.Y.Z` and the
  GitHub Release. There is no schedule: a release happens when the
  maintainer merges the Release PR.
- **Version bump while `0.y.z`:** `fix`, `perf`, `revert`, `docs` → patch;
  `feat` → minor; a breaking change → minor (`bump-minor-pre-major`).
  `test`, `chore`, `ci`, `refactor`, `build` are hidden and do not release.
  `docs` is deliberately visible: documentation is most of what this
  repository ships. Moving to 1.0.0 is a human decision expressed with a
  `Release-As: 1.0.0` footer.
- **The bot authenticates as the GitHub App `skycraft-release`** (Contents
  and Pull requests write on this repository only) through
  `actions/create-github-app-token`, so its Release PR runs the same required
  checks as any other PR without a manual approval. The App's Client ID and
  private key are the repository secrets `RELEASE_APP_ID` and
  `RELEASE_APP_PRIVATE_KEY`. The ruleset keeps zero bypass actors.
- **PR titles are the release notes.** The repository setting
  `squash_merge_commit_title` is `PR_TITLE` and `squash_merge_commit_message`
  is `PR_BODY`, and the required check `PR Title (Conventional Commits)`
  (`.github/workflows/pr-title.yml`) refuses a title outside the allowed
  types. `tests/Release-Config.Tests.ps1` keeps that type list identical to
  the release-please changelog sections.
- **The hand-curated Keep-a-Changelog flow ends at 0.9.0.** Sections up to
  0.9.0 stay as written; from 0.10.0 release-please generates each section.
  `release.yml`, `tools/Publish-Release.ps1`, `tools/Changelog.psm1` and
  `tests/Changelog.Tests.ps1` are removed.

## Consequences

**What we gain:**

- No manual step in a release: the number, the tag, the GitHub Release and
  the changelog section come from the merged PR titles.
- The next version is visible at all times in the open Release PR.
- A standard tool with standard behaviour; nothing project-specific to
  maintain beyond one JSON file and one Pester invariant.

**What we give up / accept as cost:**

- Release notes are PR titles, one line each, grouped by type. The prose
  changelog entries of 0.4.0 to 0.9.0 are not coming back; Keep a Changelog
  calls commit-log diffs a bad idea, and typed PR titles are only a step
  above that. We accept that trade for zero manual work; title quality is
  now part of PR review.
- A dependency on a Node-based action and on a GitHub App whose private key
  lives in a repository secret. If the secret is lost, releases stop until it
  is regenerated; nothing else breaks.
- `squash_merge_commit_message: PR_BODY` means intermediate commit messages
  no longer land in the squash body. A `BREAKING CHANGE:` footer has to be
  written in the PR description on purpose.

**What we must do as a follow-up:**

- Repository settings and the ruleset are changed by hand right after this
  ADR merges (`squash_merge_commit_title`, `squash_merge_commit_message`,
  required check `PR Title (Conventional Commits)`).
- The first Release PR (`chore(main): release 0.10.0`) is the end-to-end
  test: its required checks must run, and merging it must produce `v0.10.0`.

## Alternatives considered

- **Own PowerShell script that renames the CHANGELOG heading and opens the
  PR.** Keeps the curated changelog and the #140 tooling, but is ~150 lines
  of version arithmetic and PR plumbing that only this repository would ever
  run; rejected for maintenance cost against a standard tool.
- **semantic-release.** Releases on every merge with no human gate and does
  not support `0.y.z` versions; rejected.
- **Bot pushes to `main` as a ruleset bypass actor.** Skips the required
  checks on the release commit and reverses ADR-0002; rejected.
- **Fine-grained PAT instead of a GitHub App.** Fewer setup steps, but the
  token is bound to the maintainer's account: the bot's work is attributed
  to them, the token is rotated by hand and dies with the account; rejected.
