# PLAN - #302 release-please closes deferred-verification issues

Spec: https://github.com/mbiszczanik/skycraft/issues/302

- [x] Failing test: `tests/Release-Config.Tests.ps1` asserts `squash_merge_commit_message` is `BLANK`
      through `gh api` (skips without an authenticated `gh`), and that CONTRIBUTING.md no longer
      tells anyone to put a footer in the PR description.
- [ ] Flip the repository setting to `BLANK`; the test passes. (author: agent is not permitted to change repository settings)
- [x] `Release-As` moves from a PR-body footer to the `release-as` key of
      `release-please-config.json` (removed again after the release).
- [x] CONTRIBUTING.md Releases section and step 5; ADR-0007 postscript.
- [x] Dry-run gate (Pester subset + markdownlint on touched files).
- [ ] PR (no lab content, gate needs no line); delete this file in the last commit.
