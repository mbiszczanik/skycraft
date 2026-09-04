<#
.SYNOPSIS
    Pester 5 test: every Bicep file carries the canonical tag set.

.DESCRIPTION
    Enforces the tagging standard retrofitted in Phase 3 (docs/bicep-standards.md
    section 5): every resource must be tagged with exactly the canonical four
    (Project / Environment / CostCenter / Owner), and ManagedBy / DeploymentDate
    are forbidden.

    This is a text scan, not a compiled-ARM inspection: it reads each *.bicep
    file's `var ...Tags... = { ... }` blocks (and `union(varX, { ... })` second
    arguments, to tolerate the repo's `union(varCommonTags, { Environment: '<env>' })`
    composition pattern) and unions their keys at the file level. A future upgrade
    could instead run `az bicep build` and inspect the resolved `tags` property per
    resource, which would not need the file-level heuristic below - tracked as a
    follow-up, not required for this pass.

    Path matching is separator-agnostic so the suite runs identically on the
    Windows dev box and the Linux CI runner.

.EXAMPLE
    Invoke-Pester -Path .\tests\Bicep-Tags.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$AllBicepFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.bicep'
$AllCases = $AllBicepFiles | ForEach-Object {
    @{
        file = ($_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/')
        path = $_.FullName
    }
}

# Only files that own at least one literal `var ...Tags... = { ... }` block are
# in scope for the canonical-four coverage check. Pure pass-through modules (e.g.
# modules/tags.bicep's `param parTags object` -> `tags: parTags`) have nothing
# to scan and are out of scope.
$TagBlockPattern = '(?m)^var\s+\w*[Tt]ags\w*\s*=\s*\{'
$TagOwningCases = $AllCases | Where-Object {
    (Get-Content -Raw -LiteralPath $_.path) -match $TagBlockPattern
}

Describe 'SkyCraft Bicep - canonical tag set' {

    It "'<file>' tag blocks cover the canonical four tags" -ForEach $TagOwningCases {
        # $CanonicalTags is declared here, not at script scope: an It block created
        # by -ForEach only reliably sees its own case variables (file/path below) at
        # run time - a script-scope variable pulled in only via closure came back
        # empty in testing, which let every assertion silently no-op.
        $CanonicalTags = @('Project', 'Environment', 'CostCenter', 'Owner')
        $text = Get-Content -Raw -LiteralPath $path

        $keys = [System.Collections.Generic.List[string]]::new()
        foreach ($block in [regex]::Matches($text, '(?ms)^var\s+\w*[Tt]ags\w*\s*=\s*\{(.*?)^\}')) {
            foreach ($key in [regex]::Matches($block.Groups[1].Value, '(?m)^\s*(\w+)\s*:')) {
                $keys.Add($key.Groups[1].Value)
            }
        }
        foreach ($union in [regex]::Matches($text, 'union\(\s*\w+\s*,\s*\{([^{}]*)\}\s*\)')) {
            foreach ($key in [regex]::Matches($union.Groups[1].Value, '(\w+)\s*:')) {
                $keys.Add($key.Groups[1].Value)
            }
        }

        foreach ($tag in $CanonicalTags) {
            $keys | Should -Contain $tag -Because "'$file' must tag resources with '$tag' (docs/bicep-standards.md section 5)"
        }
    }

    It "'<file>' does not use a forbidden tag key" -ForEach $AllCases {
        # See note above: declared per-invocation, not at script scope.
        $ForbiddenTags = @('ManagedBy', 'DeploymentDate')
        $text = Get-Content -Raw -LiteralPath $path
        foreach ($tag in $ForbiddenTags) {
            $text | Should -Not -Match "(?m)^\s*$tag\s*:" -Because "'$tag' is forbidden by docs/bicep-standards.md section 5 (found in '$file')"
        }
    }
}
