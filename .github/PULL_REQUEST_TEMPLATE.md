## Summary

<!-- What does this PR change, and why? Keep it short and specific. -->

## Related issue

<!-- Link the issue this PR addresses, e.g. Closes #123.
     If the live verification below is deferred, write Refs #123 instead - the merge
     must not close an issue whose live acceptance criterion is still open (ADR-0006). -->

Closes #

## Live verification

<!-- Required when the PR touches module-*/, scripts/ or the lab cycle tooling in tools/;
     the 'Live Verification Declared' check reads this section. Keep exactly ONE line:

       Live-verified: <what was run - Invoke-LabCycle run id, or labs + date>
       Live-verification: deferred -> #<issue tracking the live pass>

     A deferred PR is opened as a draft (gh pr create --draft) and links its issue with Refs. -->

Live-verified:

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
- [ ] Pester suite green (`Invoke-Pester ./tests -CI`)
- [ ] All Bicep entry points build (`az bicep build`)
- [ ] Docs/links updated; directory names match exactly
- [ ] Follows PowerShell & Bicep conventions (CBH, prefixes, required tags)
