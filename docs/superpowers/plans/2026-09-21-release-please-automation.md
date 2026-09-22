# Release-please Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual CHANGELOG-heading release with a release-please Release PR that computes the version from Conventional Commits PR titles, and gate PR titles in CI.

**Architecture:** Two pull requests. PR 1 ships the pending `[Unreleased]` entries as 0.9.0 through the existing `release.yml` (its last run). PR 2 removes that tooling and adds `release-please.yml` (runs on push to `main` with a GitHub App token, opens/refreshes `chore(main): release X.Y.Z`, tags and publishes on merge), `pr-title.yml` (required check that enforces Conventional Commits PR titles), the release-please config/manifest, one Pester invariant test, ADR-0007 and doc updates. Between the PRs the maintainer creates the GitHub App and two secrets; after PR 2 the maintainer patches the squash settings and the ruleset.

**Tech Stack:** GitHub Actions (`googleapis/release-please-action@v5`, `actions/create-github-app-token@v3`, `amannn/action-semantic-pull-request@v6`), GitHub App installation token, Pester 5, `gh` CLI, PowerShell 7.

**Spec:** `docs/superpowers/specs/2026-09-21-release-please-automation-design.md`

**Repo facts the tasks rely on:**

- Protected `main`, squash-only, required checks `PSScriptAnalyzer`, `Repository Standards (Pester)`, `Bicep Build (Linter)`, `Live Verification Declared`; ruleset id `10388288`, no bypass actors.
- Merges are done by the maintainer in the GitHub UI (`gh pr merge` is not used in this repo).
- Work happens in a git worktree (ADR-0003). The worktree for PR 2 already exists on branch `feature/release-please-automation` and holds the spec. PR 1 needs its own worktree.
- `tests/Pester-Discovery.Tests.ps1` requires every `*.Tests.ps1` to live under `tests/` or `module-*/**/tests/`; `tests/Markdown-Links.Tests.ps1` fails on a broken relative link in any `.md`; `tests/Workflow-Exit-Gating.Tests.ps1` inspects only `shell: pwsh` steps (the new workflows have none).
- `.gitattributes` normalises text to LF; write files with LF.

---

## PR 1 — ship the pending entries as 0.9.0

### Task 1: Create the PR 1 worktree

**Files:** none (git only)

- [ ] **Step 1: Create the worktree from `origin/main`**

Run (from the main checkout `C:\2_Areas\Repositories\mbiszczanik\skycraft`):

```bash
git fetch origin
git worktree add -b chore/release-0.9.0 ../skycraft-release-090 origin/main
git -C ../skycraft-release-090 branch --unset-upstream chore/release-0.9.0
git -C ../skycraft-release-090 log --oneline -1
```

Expected: `2972dd8 feat: require a lab-content PR to declare its live verification (ADR-0006) (#148)` (or a newer `main` head).

All PR 1 steps below run inside `../skycraft-release-090`.

### Task 2: Rename the Unreleased heading to 0.9.0

**Files:**
- Modify: `CHANGELOG.md:8` (heading) and the `[Unreleased]:` compare link at the bottom of the file
- Modify: `CHANGELOG.md:12` (one-word factual fix in the first bullet)

- [ ] **Step 1: Rename the heading**

Replace line 8

```markdown
## [Unreleased]
```

with (use the date of the day the PR is expected to merge; correct it in the PR if the merge slips):

```markdown
## [0.9.0] - 2026-09-21
```

Do **not** add a new empty `## [Unreleased]` section: release-please does not use one.

- [ ] **Step 2: Replace the compare link**

At the bottom of the file replace

```markdown
[Unreleased]: https://github.com/mbiszczanik/skycraft/compare/v0.8.0...HEAD
```

with

```markdown
[0.9.0]: https://github.com/mbiszczanik/skycraft/compare/v0.8.0...v0.9.0
```

- [ ] **Step 3: Fix the ADR number in the first bullet**

Line 12 ends with `ADR-0006 records the decision.` The release-from-CHANGELOG decision is ADR-0005. Change that sentence to `ADR-0005 records the decision.`

- [ ] **Step 4: Preview what the old workflow will publish**

Run (needs `gh auth status` OK):

```powershell
.\tools\Publish-Release.ps1 -WhatIf
```

Expected: output names version `0.9.0`, the current HEAD as target, and prints the 0.9.0 section as the notes ending with a `**Full Changelog**` compare link. No release is created.

- [ ] **Step 5: Run the CHANGELOG parser tests**

Run:

```powershell
Invoke-Pester -Path .\tests\Changelog.Tests.ps1 -Output Detailed
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md
git commit -m "chore: release 0.9.0"
```

### Task 3: Open PR 1 and verify the release

- [ ] **Step 1: Push and open the PR**

```bash
git push -u origin chore/release-0.9.0
gh pr create --base main --title "chore: release 0.9.0" --body "Renames the Unreleased section to 0.9.0. Last release cut with tools/Publish-Release.ps1 before the switch to release-please (spec: docs/superpowers/specs/2026-09-21-release-please-automation-design.md, lands in a follow-up PR).

No lab content changed; no live verification needed."
```

Expected: PR URL printed; the four required checks turn green.

- [ ] **Step 2: Maintainer merges the PR (squash) in the GitHub UI**

- [ ] **Step 3: Verify the release**

```bash
gh run list --workflow=release.yml --limit 1
gh release view v0.9.0
```

Expected: the latest `Release` run is `completed success`; `gh release view v0.9.0` shows title `v0.9.0` and the curated notes (sections Added / Changed / Fixed ... plus the Full Changelog link).

- [ ] **Step 4: Remove the worktree**

From the main checkout:

```bash
git worktree remove ../skycraft-release-090
git branch -d chore/release-0.9.0
```

---

## Manual step — GitHub App and secrets (maintainer, between PR 1 and PR 2)

### Task 4: Create the `skycraft-release` GitHub App

**Files:** none (GitHub settings)

- [ ] **Step 1: Register the App**

GitHub → Settings → Developer settings → GitHub Apps → **New GitHub App**:

- GitHub App name: `skycraft-release`
- Homepage URL: `https://github.com/mbiszczanik/skycraft`
- Webhook: untick **Active**
- Repository permissions: **Contents → Read and write**, **Pull requests → Read and write**. Leave everything else at *No access*.
- Where can this GitHub App be installed? **Only on this account**
- Create GitHub App.

- [ ] **Step 2: Generate the private key**

On the App's page → **Private keys → Generate a private key**. A `.pem` file downloads. Keep it out of the repository.

- [ ] **Step 3: Install the App on the repository**

App page → **Install App** → your account → **Only select repositories** → `skycraft` → Install.

- [ ] **Step 4: Store the two secrets**

Copy the **Client ID** from the App's *General* page (not the numeric App ID: `actions/create-github-app-token@v3` takes `client-id`). Then, from any checkout of the repo:

```bash
gh secret set RELEASE_APP_ID --repo mbiszczanik/skycraft --body "<Client ID>"
gh secret set RELEASE_APP_PRIVATE_KEY --repo mbiszczanik/skycraft < "<path to the downloaded .pem>"
gh secret list --repo mbiszczanik/skycraft
```

Expected: both `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` are listed.

- [ ] **Step 5: Delete the local `.pem` copy** once the secret is set.

---

## PR 2 — switch to release-please

All PR 2 steps run inside the existing worktree on branch `feature/release-please-automation` (`git worktree list` shows its path, `.../scratchpad/wt-release`). First refresh it:

```bash
git fetch origin
git merge --ff-only origin/main || git merge origin/main
git log --oneline -3
```

Expected: the `chore: release 0.9.0` squash commit from PR 1 is in the history.

### Task 5: Write the failing configuration invariant test

**Files:**
- Create: `tests/Release-Config.Tests.ps1`

- [ ] **Step 1: Write the test**

```powershell
<#
.SYNOPSIS
    Pester 5 tests pinning the release-please configuration to the PR-title check.

.DESCRIPTION
    Releases are cut by release-please from the Conventional Commits titles of the pull
    requests squash-merged into main (docs/adr/0007-release-with-release-please.md). Two
    files decide which commit types count and both have to agree:

      1. release-please-config.json - 'changelog-sections' lists the types the bot knows;
         a type outside that list is silently ignored when the release notes are built.
      2. .github/workflows/pr-title.yml - the 'types' input of the PR-title check lists
         the types a contributor may use in a PR title.

    A type allowed by (2) but missing from (1) passes the merge gate and then vanishes
    from the release notes with nothing to notice; the fourth test below makes the two
    lists identical. The first three tests keep the JSON files parseable and version.txt
    in step with the manifest, so a stray comma cannot break the release workflow on main.

.EXAMPLE
    Invoke-Pester -Path .\tests\Release-Config.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ConfigPath   = Join-Path $script:RepoRoot 'release-please-config.json'
    $script:ManifestPath = Join-Path $script:RepoRoot '.release-please-manifest.json'
    $script:PrTitlePath  = Join-Path $script:RepoRoot '.github/workflows/pr-title.yml'

    # The 'types' input is a YAML block scalar (types: |) with one type per indented line.
    # Read it line by line rather than with a YAML parser, which pwsh does not ship.
    function Get-PrTitleAllowedType {
        param([string]$Path)
        $lines = Get-Content -LiteralPath $Path
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*types:\s*\|\s*$') { $start = $i; break }
        }
        if ($start -lt 0) { return @() }
        $indent = ($lines[$start] -replace '^(\s*).*$', '$1').Length
        $types = @()
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -notmatch '^\s+\S') { break }
            if ((($line -replace '^(\s*).*$', '$1').Length) -le $indent) { break }
            $types += $line.Trim()
        }
        return $types
    }
}

Describe 'release-please configuration - the files parse' {
    It 'release-please-config.json is valid JSON and configures the root package' {
        $config = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $config.'release-type' | Should -Be 'simple'
        $config.packages.PSObject.Properties.Name | Should -Contain '.'
        $config.'bump-minor-pre-major' | Should -BeTrue
    }

    It '.release-please-manifest.json pins a three-part version for the root package' {
        $manifest = Get-Content -Raw -LiteralPath $script:ManifestPath | ConvertFrom-Json
        $manifest.'.' | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'version.txt carries the same version as the manifest' {
        $manifest = Get-Content -Raw -LiteralPath $script:ManifestPath | ConvertFrom-Json
        (Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'version.txt')).Trim() |
            Should -Be $manifest.'.'
    }
}

Describe 'release-please configuration - the PR-title check and the changelog sections agree' {
    It 'the PR-title check allows exactly the commit types release-please knows' {
        $config   = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $sections = @($config.'changelog-sections'.type | Where-Object { $_ })
        $allowed  = @(Get-PrTitleAllowedType -Path $script:PrTitlePath)

        $sections.Count | Should -BeGreaterThan 0 -Because 'an empty section list would hide every commit'
        $allowed.Count  | Should -BeGreaterThan 0 -Because "the 'types: |' block was not found in pr-title.yml"
        Compare-Object -ReferenceObject $sections -DifferenceObject $allowed -CaseSensitive |
            Should -BeNullOrEmpty -Because 'a type allowed in a PR title but unknown to release-please is dropped from the notes'
    }

    It 'the docs type is visible so documentation-only work produces a release' {
        $config = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $docs = $config.'changelog-sections' | Where-Object type -ceq 'docs'
        $docs | Should -Not -BeNullOrEmpty
        [bool]$docs.hidden | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

```powershell
Invoke-Pester -Path .\tests\Release-Config.Tests.ps1 -Output Detailed
```

Expected: 5 failed (the config, manifest, version.txt and workflow files do not exist yet).

- [ ] **Step 3: Commit**

```bash
git add tests/Release-Config.Tests.ps1
git commit -m "test: pin the release-please config to the PR-title check"
```

### Task 6: Add the PR-title check workflow

**Files:**
- Create: `.github/workflows/pr-title.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: PR Title

# The title of a pull request is the squash-commit title on main (repository setting
# squash_merge_commit_title = PR_TITLE), and release-please builds the version bump and
# the release notes from those titles (docs/adr/0007-release-with-release-please.md).
# A title outside the Conventional Commits form would be silently ignored by the bot, so
# this check refuses it before merge. The allowed types are exactly the ones listed in
# release-please-config.json; tests/Release-Config.Tests.ps1 keeps the two lists equal.
#
# 'edited' re-runs the check when the title changes, so a PR is fixed by editing it.

on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

permissions:
  pull-requests: read

jobs:
  pr-title:
    name: PR Title (Conventional Commits)
    runs-on: ubuntu-latest
    steps:
      - uses: amannn/action-semantic-pull-request@v6
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat
            fix
            perf
            revert
            docs
            test
            chore
            ci
            refactor
            build
          requireScope: false
```

- [ ] **Step 2: Run the invariant test again**

```powershell
Invoke-Pester -Path .\tests\Release-Config.Tests.ps1 -Output Detailed
```

Expected: still 5 failed; every failure now names a missing JSON or `version.txt` file, none mentions `pr-title.yml`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pr-title.yml
git commit -m "ci: require a Conventional Commits pull request title"
```

### Task 7: Add the release-please configuration files

**Files:**
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`
- Create: `version.txt`

- [ ] **Step 1: Write `release-please-config.json`**

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
  "packages": {
    ".": {}
  }
}
```

- [ ] **Step 2: Write `.release-please-manifest.json`**

```json
{
  ".": "0.9.0"
}
```

- [ ] **Step 3: Write `version.txt`** (one line, LF terminated)

```text
0.9.0
```

- [ ] **Step 4: Run the invariant test**

```powershell
Invoke-Pester -Path .\tests\Release-Config.Tests.ps1 -Output Detailed
```

Expected: `Tests Passed: 5, Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add release-please-config.json .release-please-manifest.json version.txt
git commit -m "chore: configure release-please for the root package at 0.9.0"
```

### Task 8: Add the release-please workflow

**Files:**
- Create: `.github/workflows/release-please.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Release Please

# Every push to main queues release-please (one run at a time, see concurrency below).
# It reads the Conventional Commits titles since the last tag, and when at least one of
# them is releasable it opens or refreshes the Release PR "chore(main): release X.Y.Z"
# (bumping .release-please-manifest.json and version.txt, prepending the CHANGELOG.md
# section). When the push *is* that Release PR being merged, it creates the vX.Y.Z tag
# and the GitHub Release with the section as the notes.
# Rationale: docs/adr/0007-release-with-release-please.md.
#
# The Release PR is opened with a GitHub App installation token, not GITHUB_TOKEN: a PR
# raised with GITHUB_TOKEN gets its workflow runs only after a maintainer clicks "Approve
# workflows to run", so its required checks would wait on a click every time. The App
# (skycraft-release) has Contents and Pull requests write access on this repository and
# nothing else; its Client ID and private key are the two repository secrets below.
#
# workflow_dispatch is the recovery path: release-please is idempotent, so re-running it
# after a failed run finishes whatever was left (a missing tag, a stale Release PR).

on:
  push:
    branches: [main]
  workflow_dispatch:

# GITHUB_TOKEN is deliberately read-only: every write goes through the App token, so a
# dropped or broken `token:` on the release-please step fails with 403 instead of silently
# opening a Release PR that never runs its checks.
permissions:
  contents: read

concurrency:
  group: release-please
  cancel-in-progress: false

jobs:
  release-please:
    name: Release Please
    runs-on: ubuntu-latest
    steps:
      - name: Mint the release bot token
        id: app-token
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - name: Open or refresh the Release PR, or publish the merged one
        uses: googleapis/release-please-action@v5
        with:
          token: ${{ steps.app-token.outputs.token }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

- [ ] **Step 2: Validate the YAML parses**

```powershell
Install-Module powershell-yaml -Scope CurrentUser -Force -ErrorAction SilentlyContinue
if (Get-Module -ListAvailable powershell-yaml) {
    Import-Module powershell-yaml
    ConvertFrom-Yaml (Get-Content -Raw .github/workflows/release-please.yml) | Out-Null
    ConvertFrom-Yaml (Get-Content -Raw .github/workflows/pr-title.yml) | Out-Null
    'YAML OK'
} else { 'powershell-yaml unavailable - rely on the Actions UI after push' }
```

Expected: `YAML OK` (or the fallback message; then the first push shows any YAML error in the Actions tab).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-please.yml
git commit -m "ci: run release-please on every push to main"
```

### Task 9: Remove the CHANGELOG-head release tooling

**Files:**
- Delete: `.github/workflows/release.yml`
- Delete: `tools/Publish-Release.ps1`
- Delete: `tools/Changelog.psm1`
- Delete: `tests/Changelog.Tests.ps1`

- [ ] **Step 1: Delete the four files**

```bash
git rm .github/workflows/release.yml tools/Publish-Release.ps1 tools/Changelog.psm1 tests/Changelog.Tests.ps1
```

- [ ] **Step 2: Find every remaining reference**

```bash
grep -rIn --exclude-dir=.git "Publish-Release\|Changelog\.psm1\|Changelog\.Tests\|workflows/release\.yml" .
```

Expected: hits only in `CHANGELOG.md` (historic 0.9.0 entry, keep), `CONTRIBUTING.md` (rewritten in Task 11), `docs/adr/0005-release-from-changelog.md` (historic, keep), and the spec/plan under `docs/superpowers/` (keep). Any other hit must be fixed before committing.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: drop the CHANGELOG-head release workflow and script"
```

### Task 10: Write ADR-0007 and update the ADR index, ADR-0005 and ADR-0002

**Files:**
- Create: `docs/adr/0007-release-with-release-please.md`
- Modify: `docs/adr/README.md` (index table)
- Modify: `docs/adr/0005-release-from-changelog.md:3` (status line)
- Modify: `docs/adr/0002-branch-protection-rules.md:37-41` (required checks)

- [ ] **Step 1: Write `docs/adr/0007-release-with-release-please.md`**

```markdown
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
```

- [ ] **Step 2: Add the index row to `docs/adr/README.md`**

After the `0006` row append:

```markdown
| [0007](0007-release-with-release-please.md) | Release with release-please from Conventional Commits PR titles | Accepted |
```

and change the `0005` row's status cell from `Accepted` to
`Superseded by [ADR-0007](0007-release-with-release-please.md)`.

- [ ] **Step 3: Mark ADR-0005 superseded**

In `docs/adr/0005-release-from-changelog.md` replace line 3

```markdown
- **Status:** Accepted
```

with

```markdown
- **Status:** Superseded by [ADR-0007](0007-release-with-release-please.md)
```

- [ ] **Step 4: Amend the required-checks bullet in ADR-0002**

In `docs/adr/0002-branch-protection-rules.md` replace

```markdown
- **Require status checks to pass** — enabled. The required checks are
  `PSScriptAnalyzer`, `Repository Standards (Pester)`, and `Bicep Build
  (Linter)`, defined in `.github/workflows/lint.yml`, plus `Live
  Verification Declared` from `.github/workflows/pr-gate.yml`
  (ADR-0006, 2026-09-21).
```

with

```markdown
- **Require status checks to pass** — enabled. The required checks are
  `PSScriptAnalyzer`, `Repository Standards (Pester)`, and `Bicep Build
  (Linter)`, defined in `.github/workflows/lint.yml`, plus `Live
  Verification Declared` from `.github/workflows/pr-gate.yml`
  (ADR-0006, 2026-09-21) and `PR Title (Conventional Commits)` from
  `.github/workflows/pr-title.yml` (ADR-0007, 2026-09-21).
```

- [ ] **Step 5: Check the links resolve**

```powershell
Invoke-Pester -Path .\tests\Markdown-Links.Tests.ps1 -Output Detailed
```

Expected: all ADR links pass; the one remaining failure is
`CONTRIBUTING.md` → `.github/workflows/release.yml`, which Task 11 removes.

- [ ] **Step 6: Commit**

```bash
git add docs/adr/0007-release-with-release-please.md docs/adr/README.md docs/adr/0005-release-from-changelog.md docs/adr/0002-branch-protection-rules.md
git commit -m "docs: ADR-0007 release with release-please; supersede ADR-0005"
```

### Task 11: Rewrite CONTRIBUTING §Releases and the CHANGELOG intro

**Files:**
- Modify: `CONTRIBUTING.md` (§🚀 Releases, and step 5 of the PR flow)
- Modify: `CHANGELOG.md:1-7`
- Modify: `docs/superpowers/specs/2026-09-21-release-please-automation-design.md` (one row: `version.txt` is committed in PR 2, not created by the bot)

- [ ] **Step 1: Replace the whole `## 🚀 Releases` section in `CONTRIBUTING.md`**

Everything from `## 🚀 Releases` up to (not including) `## 📦 AVM module versions` becomes:

```markdown
## 🚀 Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please).
The title of your pull request is the squash-commit title on `main`, and the bot reads
those titles to decide the next version and to write the release notes.

- **Title your PR as a Conventional Commit**: `type(scope): subject`, lowercase subject,
  scope optional (e.g. `docs(5.2): say how Deploy-Bicep.ps1 creates backup policies`).
  The `PR Title (Conventional Commits)` check refuses anything else. Allowed types and
  what they do while the project is at `0.y.z`:

  | Type | Version bump | In the release notes |
  |---|---|---|
  | `fix`, `perf`, `revert`, `docs` | patch | yes |
  | `feat` | minor | yes |
  | `feat!` / `BREAKING CHANGE:` footer in the PR description | minor | yes |
  | `test`, `chore`, `ci`, `refactor`, `build` | none | no |

- **What happens automatically**: after every merge to `main` the
  [Release Please workflow](.github/workflows/release-please.yml) opens or refreshes a
  pull request titled `chore(main): release X.Y.Z` that bumps `version.txt`,
  `.release-please-manifest.json` and prepends the new section to `CHANGELOG.md`.
  Merging that PR creates the `vX.Y.Z` tag and the GitHub Release with the section as
  the notes. Nothing to type anywhere.
- **To cut a release**: merge the open `chore(main): release X.Y.Z` pull request.
- **To force a version** (for example the jump to 1.0.0): merge a PR whose description
  carries the footer `Release-As: 1.0.0`. Hand edits to the Release PR are overwritten
  the next time the bot refreshes it.
- **If a run failed** (an API error after the Release PR merged, a stale Release PR):
  re-run the workflow from the Actions tab (`workflow_dispatch`); release-please is
  idempotent and finishes what was left.
- **If the run fails on the token step**: the GitHub App `skycraft-release` key or
  Client ID is missing or was rotated. On the App's page generate a new private key,
  then `gh secret set RELEASE_APP_PRIVATE_KEY --repo mbiszczanik/skycraft < key.pem`
  (and `gh secret set RELEASE_APP_ID --body "<Client ID>"` if that changed), delete the
  local `.pem`, and re-run the workflow.

Sections up to 0.9.0 in `CHANGELOG.md` were written by hand in Keep a Changelog form and
stay as they are. The reasoning is in [ADR-0007](docs/adr/0007-release-with-release-please.md).

```

- [ ] **Step 2: Update step 5 of the PR flow in `CONTRIBUTING.md`**

Replace

```markdown
5.  **Submit a Pull Request against `main`**: Describe your changes clearly and link to any relevant issues. PRs are squash-merged. If you changed lab content, fill in the **Live verification** section of the template; if you could not run the live checks, open the PR as a draft, link the issue with `Refs #N`, and name the issue that tracks the live pass.
```

with

```markdown
5.  **Submit a Pull Request against `main`**: Title it as a Conventional Commit (see the Releases section below); the title becomes the squash-commit title and a line in the release notes. Describe your changes clearly and link to any relevant issues. PRs are squash-merged. If you changed lab content, fill in the **Live verification** section of the template; if you could not run the live checks, open the PR as a draft, link the issue with `Refs #N`, and name the issue that tracks the live pass.
```

- [ ] **Step 3: Replace lines 1-7 of `CHANGELOG.md`**

Current:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

```

New:

```markdown
# Changelog

All notable changes to this project are documented in this file.

From 0.10.0 on, each section is generated by
[release-please](https://github.com/googleapis/release-please) from the Conventional
Commits titles of the pull requests merged into `main` (see `CONTRIBUTING.md` and
ADR-0007). Sections up to 0.9.0 were written by hand in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) form. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

```

Line 8 must remain `## [0.9.0] - 2026-09-21` (from PR 1): release-please inserts the new section directly under the intro, before the first `## ` heading.

- [ ] **Step 4: Correct the spec's `version.txt` row**

In `docs/superpowers/specs/2026-09-21-release-please-automation-design.md`, in the components table, replace

```markdown
| `version.txt` | Version file the `simple` release type maintains; created by the first Release PR | maintained by the bot |
```

with

```markdown
| `version.txt` | Version file the `simple` release type maintains; committed at `0.9.0` in PR 2 so the first bump edits an existing file | maintained by the bot |
```

- [ ] **Step 5: Run the markdown suites and the markdownlint CLI if present**

```powershell
Invoke-Pester -Path .\tests\Markdown-Links.Tests.ps1, .\tests\Readme-Casing.Tests.ps1 -Output Detailed
if (Get-Command markdownlint-cli2 -ErrorAction SilentlyContinue) { markdownlint-cli2 "CONTRIBUTING.md" "CHANGELOG.md" "docs/adr/*.md" }
```

Expected: Pester all pass; markdownlint reports 0 errors (or is not installed; CI runs it).

- [ ] **Step 6: Commit**

```bash
git add CONTRIBUTING.md CHANGELOG.md docs/superpowers/specs/2026-09-21-release-please-automation-design.md
git commit -m "docs: describe the release-please flow in CONTRIBUTING and the CHANGELOG intro"
```

### Task 12: Run the offline gate and open PR 2

- [ ] **Step 1: Run the whole offline gate**

```powershell
.\tools\Invoke-DryRun.ps1
Invoke-Pester -Path .\tests -Output Detailed
```

Expected: `Invoke-DryRun.ps1` reports success (parse, PSScriptAnalyzer, Bicep build); Pester reports `Failed: 0`, and `Pester-Discovery` lists `tests/Release-Config.Tests.ps1` among the suites CI runs.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin feature/release-please-automation
gh pr create --base main --title "feat: release with release-please (ADR-0007)" --body "Replaces the CHANGELOG-head release (ADR-0005, #140) with release-please.

- release-please.yml runs on every push to main with the skycraft-release App token, opens/refreshes chore(main): release X.Y.Z, and tags + publishes when that PR merges.
- pr-title.yml is a new required check: PR titles must be Conventional Commits of the types release-please knows; tests/Release-Config.Tests.ps1 keeps the two lists equal.
- release-please-config.json / .release-please-manifest.json / version.txt start the root package at 0.9.0 (released in the previous PR).
- Removed: release.yml, tools/Publish-Release.ps1, tools/Changelog.psm1, tests/Changelog.Tests.ps1.
- ADR-0007 records the decision and supersedes ADR-0005; ADR-0002's required-checks list and CONTRIBUTING are updated.

Manual steps after merge (maintainer): set squash_merge_commit_title=PR_TITLE and squash_merge_commit_message=PR_BODY, add the PR Title check to ruleset 10388288. Spec: docs/superpowers/specs/2026-09-21-release-please-automation-design.md.

No lab content changed; no live verification needed."
```

Expected: PR URL; the existing required checks go green (`PR Title (Conventional Commits)` also runs on this PR because the workflow file is on the PR branch and the title `feat: release with release-please (ADR-0007)` is valid).

- [ ] **Step 3: Maintainer merges PR 2 (squash) in the GitHub UI**

---

## After PR 2 — repository settings, ruleset, first automatic release

### Task 13: Change the squash settings and the ruleset

**Files:** none (GitHub API)

- [ ] **Step 1: Squash settings**

```bash
gh api -X PATCH repos/mbiszczanik/skycraft -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY --jq '{squash_merge_commit_title,squash_merge_commit_message}'
```

Expected: `{"squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}`.

- [ ] **Step 2: Add the required check to the ruleset**

Run in PowerShell 7:

```powershell
$rs = gh api repos/mbiszczanik/skycraft/rulesets/10388288 | ConvertFrom-Json -Depth 20
$checks = ($rs.rules | Where-Object type -eq 'required_status_checks').parameters
if (-not ($checks.required_status_checks.context -contains 'PR Title (Conventional Commits)')) {
    $checks.required_status_checks += [pscustomobject]@{ context = 'PR Title (Conventional Commits)' }
}
# The API rejects "parameters": null on rules that take none; drop the property instead.
$rules = foreach ($r in $rs.rules) {
    if ($null -eq $r.parameters) { [pscustomobject]@{ type = $r.type } } else { $r }
}
$body = [pscustomobject]@{
    name          = $rs.name
    target        = $rs.target
    enforcement   = $rs.enforcement
    bypass_actors = @($rs.bypass_actors)
    conditions    = $rs.conditions
    rules         = @($rules)
} | ConvertTo-Json -Depth 20
$path = Join-Path ([IO.Path]::GetTempPath()) 'ruleset-10388288.json'
Set-Content -LiteralPath $path -Value $body -Encoding utf8
gh api -X PUT repos/mbiszczanik/skycraft/rulesets/10388288 --input $path --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'
```

Expected output (five lines):

```text
PSScriptAnalyzer
Repository Standards (Pester)
Bicep Build (Linter)
Live Verification Declared
PR Title (Conventional Commits)
```

- [ ] **Step 3: Confirm bypass actors are still empty**

```bash
gh api repos/mbiszczanik/skycraft/rulesets/10388288 --jq '.bypass_actors'
```

Expected: `[]`.

### Task 14: Verify the first automatic release end to end

- [ ] **Step 1: The workflow ran on the PR 2 merge**

```bash
gh run list --workflow=release-please.yml --limit 1
```

Expected: `completed success`. If it is `failure` on the token step, the secrets from Task 4 are missing or wrong; fix them and run `gh workflow run release-please.yml`.

- [ ] **Step 2: The Release PR exists and its checks ran**

```bash
gh pr list --state open --search "chore(main): release" --json number,title,author,statusCheckRollup --jq '.[] | {number,title,author:.author.login,checks:[.statusCheckRollup[].name]}'
```

Expected: one PR `chore(main): release 0.10.0`, author `skycraft-release` (shown as `app/skycraft-release` or `skycraft-release[bot]`), and `checks` lists `PSScriptAnalyzer`, `Repository Standards (Pester)`, `Bicep Build (Linter)`, `Live Verification Declared`, `PR Title (Conventional Commits)`. An empty `checks` list means the PR was opened with `GITHUB_TOKEN`; check that `release-please.yml` passes `token: ${{ steps.app-token.outputs.token }}`.

- [ ] **Step 3: Review the generated section**

Open the Release PR diff. `CHANGELOG.md` gains

```markdown
## [0.10.0](https://github.com/mbiszczanik/skycraft/compare/v0.9.0...v0.10.0) (YYYY-MM-DD)

### Features

* release with release-please (ADR-0007) (#NNN) ...
```

above `## [0.9.0] - 2026-09-21`; `version.txt` and `.release-please-manifest.json` read `0.10.0`.

- [ ] **Step 4: Maintainer merges the Release PR in the GitHub UI**

- [ ] **Step 5: Tag and release exist**

```bash
gh run list --workflow=release-please.yml --limit 1
gh release view v0.10.0 --json tagName,name,body --jq '{tagName,name,body:(.body|.[0:200])}'
git fetch --tags && git tag --list 'v0.10.0'
```

Expected: run `completed success`; release `v0.10.0` with the Features section as body; tag `v0.10.0` present.

- [ ] **Step 6: Negative test of the title gate**

Open a throwaway branch with one trivial commit and a PR titled `Update README` (no type). Expected: `PR Title (Conventional Commits)` fails and the Merge button is blocked by the ruleset. Edit the title to `docs: update README`; expected: the check re-runs and passes. Close the PR without merging and delete the branch.

- [ ] **Step 7: Remove the PR 2 worktree**

From the main checkout:

```bash
git worktree remove <path shown by git worktree list for feature/release-please-automation>
git branch -d feature/release-please-automation
```
