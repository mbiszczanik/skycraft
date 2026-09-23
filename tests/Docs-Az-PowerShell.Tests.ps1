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
        AND every parameter file header (module-*/**/bicep/**/*.bicepparam)
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
      - lab guides (module-*/**/lab-guide-*.md) contain none of a fixed list of
        *operational* az verbs - the ones that deploy, export or delete the
        lab's own infrastructure (issue #141)

    Lab guides are otherwise deliberately out of scope: docs/lab-guide-standards.md
    asks them to teach Portal, CLI and PowerShell side by side, so `az vm resize`,
    `az storage ...` and the "Option 2: Azure CLI" blocks stay. The rule below is
    a verb allowlist rather than a heading-scoped rule on purpose: the
    `#### Option 2: Azure CLI` heading exists in only three guides, and the
    operational blocks this guards were fenced ```bash, not ```azurecli, so
    neither a heading nor a fence-language rule would catch them without firing
    on the multi-modal sections.

    `az bicep` and `az acr build` are NOT listed. `az bicep build|decompile` is a
    local compile that never contacts a subscription (and powershell-standards.md
    section 5 names `az bicep` an accepted exception); `az acr build` has no Az
    PowerShell equivalent - no cmdlet builds an image from source - and is marked
    in lab-guide-3.3.md as the documented exception.

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

# -Filter '*.bicep' does not match '*.bicepparam', which is how 16 parameter-file
# headers kept an `az deployment sub create` EXAMPLE line through #134 (#141).
# Both extensions are collected here.
$BicepCases = Get-ChildItem -Path $RepoRoot -Recurse -File |
    Where-Object { $_.Extension -in '.bicep', '.bicepparam' } |
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

$GuideCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter 'lab-guide-*.md' |
    Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^module-\d' } |
    ForEach-Object { ConvertTo-RepoCase $_ }

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

Describe 'SkyCraft docs - lab guides deploy with Az PowerShell' {

    BeforeAll {
        # Defined here, not at file scope: Pester 5 discovers and runs in separate
        # phases, and a file-scope variable is $null during the run phase. An empty
        # pattern would match at every position and report thousands of blank hits.
        #
        # Operational az verbs: they deploy, export or delete the lab's own
        # infrastructure, so they must run in the Az PowerShell context the lab's
        # scripts use. Teaching verbs (az vm, az storage, az monitor, ...) are
        # absent by design - see the DESCRIPTION block.
        $script:OperationalAzPattern = '(?m)^\s*az\s+(' +
            'deployment\s+(sub|group|mg|tenant)\s+(create|what-if|validate|show|list)' +
            '|group\s+(create|delete|export)' +
            '|webapp\s+deploy' +
            ')\b'
    }

    It 'the operational-verb pattern is not empty' {
        # A blank pattern silently passes nothing and fails everything.
        $script:OperationalAzPattern | Should -Not -BeNullOrEmpty
    }

    It 'collected at least one lab guide' {
        # Get-ChildItem -Path 'module-*' -Recurse -File -Filter returns nothing on
        # pwsh 7.6; an empty case list would pass this suite on zero tests.
        @($GuideCases).Count | Should -BeGreaterThan 0
    }

    It "'<file>' has no operational az command" -ForEach $GuideCases {
        $text = Get-Content -Raw -LiteralPath $path
        $offenders = [regex]::Matches($text, $script:OperationalAzPattern) | ForEach-Object { $_.Value.Trim() }
        @($offenders) | Should -BeNullOrEmpty -Because "deploying, exporting or deleting the lab's own resources must use the lab's scripts / Az cmdlets - the az CLI can be signed in to a different subscription (docs/powershell-standards.md section 5); found: $($offenders -join '; ')"
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
