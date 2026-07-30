<#
.SYNOPSIS
    Pester 5 tests: every resource carries the canonical tag set and none of the banned tags.

.DESCRIPTION
    docs/bicep-standards.md §5 defines the canonical base tag set - exactly
    Project / Environment / CostCenter / Owner - and bans ManagedBy and DeploymentDate.
    The ban exists because a utcNow()-fed timestamp tag changes on every run, so 'what-if'
    always reports a modification and the deployment is never idempotent.

    Nothing enforced that rule, so this test walks every *.bicep under module-*/bicep/ and
    every *.ps1 in the repository and asserts:
      - no ManagedBy / DeploymentDate tag assignment (Bicep object syntax or PowerShell
        hashtable syntax)
      - no utcNow() anywhere in a template, which is how DeploymentDate got in
      - wherever a Bicep tag block sets Project, it also sets CostCenter and Owner
      - wherever a PowerShell script builds a SkyCraft tag hashtable, it also sets Owner,
        so the imperative and declarative deployment paths agree

    Environment is deliberately not required in the same breath: the module-3.1 and
    module-3.2 orchestrators build a common tag block and union the per-environment
    Environment value in at each resource group, which is a legitimate pattern.

.EXAMPLE
    Invoke-Pester -Path .\tests\Tag-Policy.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$BicepCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.bicep' |
              Where-Object { $_.FullName -match '[/\\]module-\d.*[/\\]bicep[/\\]' } |
              ForEach-Object {
                  @{
                      file = $_.FullName.Substring($RepoRoot.Length + 1)
                      path = $_.FullName
                  }
              }

$ScriptCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
               Where-Object { $_.FullName -notmatch '[/\\]\.git[/\\]' } |
               ForEach-Object {
                   @{
                       file = $_.FullName.Substring($RepoRoot.Length + 1)
                       path = $_.FullName
                   }
               }

Describe 'Tags - banned keys are not assigned in Bicep' {
    It "'<file>' assigns neither ManagedBy nor DeploymentDate" -ForEach $BicepCases {
        $text = Get-Content -Raw -LiteralPath $path
        $banned = [regex]::Matches($text, '(?m)^\s*(ManagedBy|DeploymentDate)\s*:') |
                  ForEach-Object { $_.Groups[1].Value } |
                  Sort-Object -Unique
        $banned | Should -BeNullOrEmpty -Because "bicep-standards.md §5 bans these tags; found in '$file': $($banned -join ', ')"
    }
}

Describe 'Tags - no utcNow() in templates' {
    It "'<file>' does not call utcNow()" -ForEach $BicepCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match 'utcNow\s*\(' -Because "a utcNow()-derived value changes on every run and breaks 'what-if' idempotency ('$file')"
    }
}

Describe 'Tags - canonical keys accompany Project in Bicep tag blocks' {
    It "'<file>' sets CostCenter and Owner wherever it sets Project" -ForEach $BicepCases {
        $text = Get-Content -Raw -LiteralPath $path

        if ($text -notmatch '(?m)^\s+Project\s*:') {
            Set-ItResult -Skipped -Because "'$file' declares no tag block"
            return
        }

        $missing = @()
        if ($text -notmatch '(?m)^\s+CostCenter\s*:') { $missing += 'CostCenter' }
        if ($text -notmatch '(?m)^\s+Owner\s*:')      { $missing += 'Owner' }

        $missing | Should -BeNullOrEmpty -Because "the canonical tag set requires Project/Environment/CostCenter/Owner; '$file' is missing: $($missing -join ', ')"
    }
}

Describe 'Tags - PowerShell deployment paths match the canonical set' {
    It "'<file>' sets Owner wherever it builds a SkyCraft tag hashtable" -ForEach $ScriptCases {
        $text = Get-Content -Raw -LiteralPath $path

        # The lookbehind keeps this on hashtable *keys*. PowerShell's -match is
        # case-insensitive, so a bare 'Project\s*=' also matches the naming variable
        # `$project = 'skycraft'` that several Test-Lab/Remove-LabResource scripts use.
        if ($text -notmatch "(?<![`$\w])Project\s*=\s*['`"]SkyCraft['`"]") {
            Set-ItResult -Skipped -Because "'$file' builds no tag hashtable"
            return
        }

        $text | Should -Match "(?<![`$\w])Owner\s*=" -Because "the imperative path must apply the same canonical tags as Bicep ('$file')"
    }

    It "'<file>' assigns neither ManagedBy nor DeploymentDate" -ForEach $ScriptCases {
        $text = Get-Content -Raw -LiteralPath $path
        $banned = [regex]::Matches($text, '(?m)[;{@]\s*(ManagedBy|DeploymentDate)\s*=') |
                  ForEach-Object { $_.Groups[1].Value } |
                  Sort-Object -Unique
        $banned | Should -BeNullOrEmpty -Because "bicep-standards.md §5 bans these tags; found in '$file': $($banned -join ', ')"
    }
}
