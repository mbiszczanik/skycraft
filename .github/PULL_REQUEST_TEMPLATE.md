## Summary

<!-- What does this PR change, and why? Keep it short and specific. -->

## Related issue

<!-- Link the issue this PR addresses, e.g. Closes #123. -->

Closes #

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

- [ ] `Test-Lab.ps1` passes for affected lab(s)
- [ ] PSScriptAnalyzer reports 0 errors (`Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`)
- [ ] Pester suite green (`Invoke-Pester ./tests -CI`)
- [ ] All Bicep entry points build (`az bicep build`)
- [ ] Docs/links updated; directory names match exactly
- [ ] Follows PowerShell & Bicep conventions (CBH, prefixes, required tags)
