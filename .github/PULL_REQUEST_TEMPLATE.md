## Summary

<!-- What does this PR change, and why? Keep it short and specific. -->

## Related issue

<!-- Closes #N when every live item of the issue ran on this branch, or the issue has none.
     Otherwise Refs #N, list what is still owed, and write no closing keyword next to
     that number anywhere in this body (ADR-0006 decision 6c). -->

Refs #

## Live verification

<!-- Required when the PR touches module-*/, scripts/ or the lab cycle tooling in tools/;
     the 'Live Verification Declared' check reads this section (ADR-0006, decision 6).

     A fix re-runs, on this branch, the live check that found the defect (the failing steps,
     Test-Lab.ps1 of the affected labs) and keeps the first line:

       Live-verified: <what ran, where, date, exit codes>

     Defer only when the test environment cannot run the check (a brand-new subscription,
     an account that has not consented yet, Cloud Shell). Then replace it with both:

       Live-verification: deferred -> #<issue tracking the live pass>
       Live-verification-blocker: <why the live check cannot run in the test environment>

     A deferred PR is opened as a draft (gh pr create --draft), links its issue with Refs, and
     can merge only after the maintainer adds the label live-deferral-approved.
     The check is not repeated on main after the merge. If the branch changes after the
     check, run it again or say here why the change cannot affect it. -->

Live-verified:

## Acceptance evidence

<!-- Required for the same lab-content paths as live verification. See docs/lab-acceptance.md.
     Identify each affected lab in the entries. Use not-applicable: <specific reason>
     for unrelated checks or blocked: <missing precondition>; tracked in #N.
     A complete record is not proof of a passed check. -->

Test-conditions: <lifecycle, offer, region, permissions, existing resources>
Acceptance-head: <tested commit>
Scripted-check: <date, command/run ID, expected/observed counts, exit code>
Portal-check: <date, changed step IDs, expected/observed result, evidence link>
Negative-check: <date, failure input, expected/observed failure, command>
Missing-result-check: <date, empty/null/zero-work input, expected/observed failure, command>
Fallback-deploy: <date, variant, create command/run ID, observed resource, exit code>

## Offline checks

<!-- The full test set CI runs (./tests and every module-*/**/tests suite), never a subset,
     and the green CI run id at this PR's head. -->

Offline checks: full CI test set, CI run <id>

## Type of change

<!-- Check all that apply. -->

- [ ] New lab / content
- [ ] Bug fix
- [ ] Enhancement
- [ ] Documentation
- [ ] CI / tooling / chore
- [ ] Breaking change

## Pre-merge checklist

<!-- All items are required before this PR can be squash-merged into `main`. -->

- [ ] `Test-Lab.ps1` passes for affected lab(s) - and the **Live verification** line above says so, or names the issue that tracks it
- [ ] PSScriptAnalyzer reports 0 errors (`Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`)
- [ ] Pester suite green: `./tests` and every `module-*/**/tests` suite, as `.github/workflows/lint.yml` runs them
- [ ] All Bicep entry points build (`bicep build`, or `.\tools\Invoke-DryRun.ps1 -Check Bicep,BicepParams`)
- [ ] Docs/links updated; directory names match exactly
- [ ] Follows PowerShell & Bicep conventions (CBH, prefixes, required tags)
