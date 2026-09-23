<#
.SYNOPSIS
    Pester 5 test: operational course material uses Az PowerShell, not the az CLI.

.DESCRIPTION
    Enforces the tooling rule in docs/powershell-standards.md section 5 for the
    places where an az CLI command is operational rather than educational
    (issue #78). On this project the az CLI and Az PowerShell can be signed in
    to different subscriptions, so an az command a learner pastes from a
    checklist can silently run against the wrong subscription.

    Guarded surfaces:
      - the EXAMPLE line of every Bicep file header (module-*/**/bicep/*.bicep)
        names the Deploy-Bicep.ps1 script or an Az cmdlet - never
        `az deployment ... create`, which contradicts the DEPLOYMENT line below it
      - docs/bicep-standards.md carries no `az deployment` header template for
        new labs to copy
      - lab checklists (module-*/**/lab-checklist-*.md) contain no az CLI code
        fence (```azurecli / ```azcli) and no `az ...` command line inside any
        fence
      - module READMEs (module-*/README.md) follow the same rule (issue #142):
        their prerequisite checks gate a deployment Deploy-Bicep.ps1 then runs
        under the Az context, so they must resolve resources the same way

    Lab guides are deliberately out of scope: docs/lab-guide-standards.md asks
    them to teach Portal, CLI and PowerShell side by side.

.EXAMPLE
    Invoke-Pester -Path .\tests\Docs-Az-PowerShell.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function ConvertTo-RepoCase {
    param([System.IO.FileInfo]$File)
    @{
        file = ($File.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/')
        path = $File.FullName
    }
}

$BicepCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.bicep' |
    Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^module-\d.*/bicep/' } |
    ForEach-Object { ConvertTo-RepoCase $_ }

$ChecklistCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter 'lab-checklist-*.md' |
    Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^module-\d' } |
    ForEach-Object { ConvertTo-RepoCase $_ }

$ModuleDirectory = @(Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*')

$ReadmeCases = $ModuleDirectory |
    ForEach-Object { Join-Path $_.FullName 'README.md' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { ConvertTo-RepoCase (Get-Item -LiteralPath $_) }

$StandardsCase = @(ConvertTo-RepoCase (Get-Item (Join-Path $RepoRoot 'docs\bicep-standards.md')))

Describe 'SkyCraft docs - Bicep headers point at the PowerShell deployment path' {

    It "'<file>' EXAMPLE header line does not use az deployment" -ForEach $BicepCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match '(?m)^EXAMPLE:.*\baz\s+deployment\b' -Because 'the DEPLOYMENT line right below names .\scripts\Deploy-Bicep.ps1 (docs/powershell-standards.md section 5)'
    }

    It "'<file>' header template does not use az deployment" -ForEach $StandardsCase {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match '(?m)^EXAMPLE:.*\baz\s+deployment\b' -Because 'new labs copy the header template verbatim'
    }
}

Describe 'SkyCraft docs - checklists validate with Az PowerShell' {

    It "'<file>' has no az CLI code fence" -ForEach $ChecklistCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match '(?m)^\s*```(azurecli|azcli)\b' -Because 'checklist validation blocks are Az PowerShell (docs/checklist-standards.md section 3.2)'
    }

    It "'<file>' has no az command inside a code fence" -ForEach $ChecklistCases {
        $text = Get-Content -Raw -LiteralPath $path
        # Every fenced block, then every line in it that starts an az command.
        $fences = [regex]::Matches($text, '(?ms)^\s*```[^\r\n]*\r?\n(.*?)^\s*```', 'Multiline')
        $offenders = foreach ($fence in $fences) {
            [regex]::Matches($fence.Groups[1].Value, '(?m)^\s*az\s+[a-z]') | ForEach-Object { $_.Value.Trim() }
        }
        @($offenders) | Should -BeNullOrEmpty -Because "the az CLI can be signed in to a different subscription than Az PowerShell; found: $($offenders -join '; ')"
    }
}

Describe 'SkyCraft docs - module READMEs verify prerequisites with Az PowerShell' {

    It 'discovers a README for every module directory' {
        @($ReadmeCases).Count | Should -Be @($ModuleDirectory).Count -Because 'a silent zero-case discovery would make the rules below pass vacuously'
    }

    It "'<file>' has no az CLI code fence" -ForEach $ReadmeCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match '(?m)^\s*```(azurecli|azcli)\b' -Because 'README prerequisite checks are Az PowerShell (issue #142)'
    }

    It "'<file>' has no az command inside a code fence" -ForEach $ReadmeCases {
        $text = Get-Content -Raw -LiteralPath $path
        $fences = [regex]::Matches($text, '(?ms)^\s*```[^\r\n]*\r?\n(.*?)^\s*```', 'Multiline')
        $offenders = foreach ($fence in $fences) {
            [regex]::Matches($fence.Groups[1].Value, '(?m)^\s*az\s+[a-z]') | ForEach-Object { $_.Value.Trim() }
        }
        @($offenders) | Should -BeNullOrEmpty -Because "a README check runs before a deployment Deploy-Bicep.ps1 makes under the Az context; found: $($offenders -join '; ')"
    }
}
