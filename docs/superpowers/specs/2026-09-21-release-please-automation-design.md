# Automatic versioning, tagging and releases with release-please

- **Date:** 2026-09-21
- **Status:** Approved design, awaiting implementation plan
- **Supersedes:** the manual CHANGELOG-heading release flow from ADR-0005

## Goal

Remove the last manual step of a release: choosing the version number and
editing the `CHANGELOG.md` heading. After this change a release is produced by
merging a bot-maintained Release PR; the version number, the tag, the GitHub
Release and the changelog section are computed from the Conventional Commits
titles of the pull requests squash-merged into `main`.

## Decisions made during brainstorming

| # | Question | Decision |
|---|----------|----------|
| 1 | When is a release cut? | Whenever the maintainer merges the bot's Release PR. The bot refreshes that PR after every merge to `main`. No cron. |
| 2 | How does the bot get a commit onto protected `main`? | Release PR opened with a **GitHub App** installation token. No ruleset bypass, no PAT. |
| 3 | Own script or off-the-shelf tool? | **release-please** (`googleapis/release-please-action`), the industry-standard Release PR tool. The hand-curated Keep-a-Changelog flow ends at 0.9.0. |
| 4 | Fate of the ADR-0005 tooling (#140)? | Removed entirely: `release.yml`, `tools/Publish-Release.ps1`, `tools/Changelog.psm1`, `tests/Changelog.Tests.ps1`. |
| 5 | Are `docs:` commits releasable? | Yes: the `docs` changelog section is visible, so documentation-only work produces a patch release and appears in the notes. `test`, `chore`, `ci`, `refactor`, `build` stay hidden. |
| 6 | PR title discipline? | Repo setting `squash_merge_commit_title: PR_TITLE` plus a required CI check that validates the PR title against Conventional Commits. |
| 7 | Migration of the 40 pending `[Unreleased]` entries? | Two PRs: PR 1 ships them as **0.9.0** through the old mechanism; PR 2 switches to release-please with the manifest at `0.9.0`. |

### Version bump rules (Conventional Commits, pre-1.0)

| PR title prefix | Bump while `0.y.z` | In release notes |
|---|---|---|
| `fix:`, `perf:`, `revert:`, `docs:` | patch | yes |
| `feat:` | minor | yes |
| `feat!:` / `BREAKING CHANGE:` footer | minor (`bump-minor-pre-major`) | yes |
| `test:`, `chore:`, `ci:`, `refactor:`, `build:` | none | hidden |

The project stays at `0.y.z`. Moving to `1.0.0` is a deliberate human act: a
commit carrying the footer `Release-As: 1.0.0`. The bot never bumps the major
version on its own.

## Industry research summary

- Conventional Commits 1.0.0 defines `fix` → PATCH, `feat` → MINOR,
  `BREAKING CHANGE` → MAJOR; other types "have no implicit effect in Semantic
  Versioning".
- SemVer 2.0.0 rules 6-8 carry an `x > 0` qualifier; its FAQ recommends
  incrementing the minor version for each pre-1.0 release. AVM SNFR17 applies
  the same pre-1.0 convention (breaking/feature → minor, fix → patch).
- Two delivery models exist: push-to-release (semantic-release, refuses 0.x)
  and Release PR (release-please, changesets). Release PR keeps a human in
  control of *when* while the tool controls *what number*.
- release-please's documented caveat: PRs made with `GITHUB_TOKEN` do not
  trigger workflows; the fix is a PAT or a GitHub App token
  (`actions/create-github-app-token`).
- Azure Verified Modules enforce Conventional Commits on PR titles with
  `amannn/action-semantic-pull-request` and use squash merges.
- A release-please Release PR is created when the generated changelog is
  non-empty (`src/strategies/base.ts`), so a commit type is releasable exactly
  when its changelog section is not hidden.

Sources: conventionalcommits.org/en/v1.0.0, semver.org/spec/v2.0.0.html,
github.com/googleapis/release-please (README, docs/manifest-releaser.md,
docs/customizing.md), github.com/googleapis/release-please-action,
docs.github.com "Triggering a workflow", azure.github.io/Azure-Verified-Modules
(BCPNFR14, SNFR17), keepachangelog.com/en/1.1.0.

## Architecture

```
PR (Conventional Commits title) --squash merge--> main
                                                   | push
                                                   v
                             .github/workflows/release-please.yml
                             |- actions/create-github-app-token  -> bot token (1 h)
                             '- googleapis/release-please-action
                                  |- no releasable commits since last tag -> no-op
                                  |- releasable commits -> open/refresh Release PR
                                  |     "chore(main): release X.Y.Z"
                                  |     (bumps .release-please-manifest.json,
                                  |      version.txt, prepends CHANGELOG.md section)
                                  |     App token => lint.yml and pr-title.yml run
                                  '- the push is a merged Release PR
                                        -> tag vX.Y.Z + GitHub Release
                                           (body = the new CHANGELOG section)
```

Components and their single responsibility:

| Component | Responsibility | Depends on |
|---|---|---|
| `.github/workflows/pr-title.yml` | Reject PRs whose title is not a Conventional Commit of an allowed type | `amannn/action-semantic-pull-request@v6`, `GITHUB_TOKEN` |
| `.github/workflows/release-please.yml` | Run release-please on every push to `main` (and on demand) with the App token | `actions/create-github-app-token`, `googleapis/release-please-action`, secrets |
| `release-please-config.json` | Bump rules, changelog sections, tag format | release-please config schema |
| `.release-please-manifest.json` | Last released version per path (`"."`) | maintained by the bot after bootstrap |
| `version.txt` | Version file the `simple` release type maintains; created by the first Release PR | maintained by the bot |
| `tests/Release-Config.Tests.ps1` | Keep the PR-title type list and the changelog-section type list identical; JSON validity | Pester |
| GitHub App `skycraft-release` | Identity whose token lets the Release PR trigger CI | created manually once |

## Configuration

### `release-please-config.json`

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": false,
  "include-v-in-tag": true,
  "changelog-sections": [
    { "type": "feat", "section": "Features" },
    { "type": "fix", "section": "Bug Fixes" },
    { "type": "perf", "section": "Performance" },
    { "type": "revert", "section": "Reverts" },
    { "type": "docs", "section": "Documentation" },
    { "type": "test", "section": "Tests", "hidden": true },
    { "type": "chore", "section": "Miscellaneous", "hidden": true },
    { "type": "ci", "section": "CI", "hidden": true },
    { "type": "refactor", "section": "Refactoring", "hidden": true },
    { "type": "build", "section": "Build", "hidden": true }
  ],
  "packages": { ".": {} }
}
```

### `.release-please-manifest.json`

```json
{ ".": "0.9.0" }
```

### `.github/workflows/release-please.yml`

- Triggers: `push: branches: [main]` and `workflow_dispatch`.
- `permissions: contents: write, pull-requests: write`.
- `concurrency: { group: release-please }` so two quick merges to `main` queue
  instead of racing.
- Steps: `actions/create-github-app-token@v3` with `client-id:
  ${{ secrets.RELEASE_APP_ID }}` and `private-key:
  ${{ secrets.RELEASE_APP_PRIVATE_KEY }}`, then
  `googleapis/release-please-action@v5` with `token: ${{ steps.app-token.outputs.token }}`.
  Action versions pinned to a major tag, like the other workflows in the repo.
- No pwsh steps, so `tests/Workflow-Exit-Gating.Tests.ps1` does not apply.

### `.github/workflows/pr-title.yml`

- Trigger: `pull_request: types: [opened, edited, synchronize, reopened]`.
- Job name (and therefore required-check name): `PR Title (Conventional Commits)`.
- `permissions: pull-requests: read`; the default `GITHUB_TOKEN` is enough.
- `amannn/action-semantic-pull-request@v6` with `types:` set to exactly
  `feat fix perf revert docs test chore ci refactor build`; scope optional
  (`docs(5.2): ...`); `!` allowed.
- The bot's own PR title `chore(main): release 0.10.0` passes.

### Repository settings (manual `gh api -X PATCH repos/mbiszczanik/skycraft`)

- `squash_merge_commit_title: PR_TITLE` (was `COMMIT_OR_PR_TITLE`, which uses
  the commit title for single-commit PRs and silently drops non-conventional
  titles from the release notes).
- `squash_merge_commit_message: PR_BODY` (was `COMMIT_MESSAGES`). release-please
  parses the squash body and treats every intermediate `fix: ...` commit line
  as its own note; with `PR_BODY` only the PR title counts, and a
  `BREAKING CHANGE:` footer is written intentionally in the PR description.

### Ruleset "Protect Main Branch" (id 10388288, manual `gh api -X PUT`)

- Add `PR Title (Conventional Commits)` to the required status checks.
- **No bypass actors.** The Release PR passes the same required checks as any
  other PR. Everything else (squash only, linear history, 0 approvals, resolved
  review threads) is unchanged.

### GitHub App (created once by the maintainer)

1. Settings → Developer settings → GitHub Apps → New GitHub App. Name
   `skycraft-release`, homepage = repo URL, webhook inactive, "Only on this
   account".
2. Repository permissions: **Contents: Read and write**, **Pull requests: Read
   and write**. Nothing else.
3. Generate a private key (`.pem`). Install the App on `mbiszczanik/skycraft`.
4. Repository secrets: `RELEASE_APP_ID` = the App's Client ID,
   `RELEASE_APP_PRIVATE_KEY` = the full `.pem` content.
5. The bot appears as `skycraft-release[bot]`; each token lives one hour and is
   revoked in the action's post step.

## Migration

### PR 1 — `chore: release 0.9.0` (last use of the old mechanism)

- `CHANGELOG.md`: rename `## [Unreleased]` to `## [0.9.0] - <merge date>`; do
  **not** add a new empty Unreleased section (release-please does not use one).
  Add the compare link `[0.9.0]: .../compare/v0.8.0...v0.9.0` like previous
  versions.
- Merge → the existing `release.yml` creates `v0.9.0` with the curated notes.
  Verify with `gh release view v0.9.0`.

### Between PR 1 and PR 2 (manual)

Create the GitHub App and the two secrets as described above. PR 2 cannot
work without them.

### PR 2 — `feat: release with release-please (ADR-0007)`

Added:

- `.github/workflows/release-please.yml`, `.github/workflows/pr-title.yml`
- `release-please-config.json`, `.release-please-manifest.json`
- `tests/Release-Config.Tests.ps1`
- `docs/adr/0007-release-with-release-please.md`

Removed:

- `.github/workflows/release.yml`, `tools/Publish-Release.ps1`,
  `tools/Changelog.psm1`, `tests/Changelog.Tests.ps1`

Changed:

- `CHANGELOG.md` intro: sections up to 0.9.0 were hand-written in
  Keep-a-Changelog form and stay as they are; from 0.10.0 release-please
  generates each section from PR titles.
- `CONTRIBUTING.md` §Releases: PR title = release-note line; release = merge
  the Release PR; `BREAKING CHANGE:` footer goes in the PR description;
  `Release-As: X.Y.Z` forces a version; drop every reference to
  `Publish-Release.ps1`.
- `docs/adr/0007-release-with-release-please.md` (repo template): Context (the
  heading edit was the last manual step; research summary above), Decision
  (release-please, App token, PR-title check, `docs` visible, pre-1.0 rules),
  Consequences (curated changelog ends at 0.9.0, dependency on a Node-based
  action, squash settings change), Alternatives (own script; semantic-release;
  ruleset bypass).
- `docs/adr/0005-release-from-changelog.md`: status `Superseded by ADR-0007`.
- `docs/adr/0002-branch-protection-rules.md`: required checks list gains
  `PR Title (Conventional Commits)`.
- `docs/adr/README.md`: index entry for 0007.

Manual steps after PR 2 is merged (checklist in the implementation plan):
PATCH the squash settings, PUT the ruleset with the new required check.

### First run

Merging PR 2 is a push to `main`; the bot sees the commits since `v0.9.0`
(PR 2 itself is a `feat:`), opens `chore(main): release 0.10.0`, and merging
that PR is the end-to-end test.

## Testing and verification

Automated:

- `tests/Release-Config.Tests.ps1`: both JSON files parse; the set of `type`
  values in `changelog-sections` equals the `types:` list in `pr-title.yml`.
  This is the one invariant that can break silently (a type passes the lint
  but the bot ignores it).
- Existing suites (`Markdown-Links`, `Pester-Discovery`, PSScriptAnalyzer,
  markdownlint) run on PR 2 unchanged. `.markdownlint.jsonc` is permissive
  (`MD013` off, `MD024 siblings_only`), so generated CHANGELOG sections pass.
- No tests for the version arithmetic itself: that is release-please's code.

End-to-end checklist:

1. After PR 1: `gh release view v0.9.0` shows the curated notes.
2. After PR 2: `release-please.yml` run is green; a Release PR
   `chore(main): release 0.10.0` is open, authored by `skycraft-release[bot]`,
   and **all required checks ran on it** (proof that the App token works).
3. Merging the Release PR produces tag `v0.10.0` and a GitHub Release with
   Features / Documentation sections.
4. A PR titled without a prefix gets a red `PR Title (Conventional Commits)`
   check and cannot be merged.

## Failure handling

| Failure | Effect | Recovery |
|---|---|---|
| Missing or expired secrets | `create-github-app-token` step fails on `main`; nothing is changed | Fix the secret, re-run via `workflow_dispatch` |
| CI red on the Release PR | Nothing is released | Fix on `main`; the bot refreshes the PR |
| Computed version is not what you want | e.g. 0.9.1 instead of 0.10.0 | Empty commit/PR with footer `Release-As: 0.10.0`; manual edits to the Release PR are overwritten |
| Release PR merged but tag missing (API failure) | Version bumped in files, no tag | `workflow_dispatch`: release-please is idempotent and finishes the release |
| Two merges to `main` in quick succession | Would race | `concurrency: release-please` queues the second run |
| Non-conventional title merged before the check existed | Commit invisible to the bot | Follow-up conventional commit, or `Release-As` |

## Out of scope

- Any change to `lint.yml` jobs other than adding the PR-title workflow.
- Publishing artifacts (there are none); Bicep registry or PowerShell Gallery
  versioning of individual modules.
- Backfilling or rewriting releases older than 0.9.0.
