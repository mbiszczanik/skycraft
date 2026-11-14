<#
.SYNOPSIS
    Pester 5 tests for tools/Test-LabConsistency.ps1 (issues #363, #364, #362).

.DESCRIPTION
    Runs the real script as a child process against fixture repositories: a validator that
    compares a property with -eq $false, a guide whose Prerequisites miss a manifest dependency,
    a guide without a Prerequisites or a Leaves Behind section each fail; an allowlisted finding
    passes; a stale allowlist entry, a reasonless entry and an empty repository fail; and the
    repository itself passes.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\Lab-Consistency.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Tool = Join-Path $script:RepoRoot 'tools' 'Test-LabConsistency.ps1'
    $script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('labcons-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Fixture | Out-Null

    $script:EmptyAllowlist = Join-Path $script:Fixture 'empty.psd1'
    Set-Content -LiteralPath $script:EmptyAllowlist -Value '@{ Allow = @() }'

    # Built from two parts: the name of a real lab script in this file would make the harness guard
    # (Lab-Script-Harness-Guard) treat the suite as one that runs lab scripts; it runs none.
    $script:ValidatorName = 'Test-' + 'Lab.ps1'

    $script:GoodGuide = @'
# Lab 1.2

## Prerequisites

- Lab 1.1 is done.

## Steps

## What This Lab Leaves Behind

Nothing.
'@
    $script:GoodValidator = 'if (-not $sa.AllowBlobPublicAccess) { "ok" }'
    $script:ExitLine = 'Exit-Lab -FailureCount 0 -PassCount 1'

    function Initialize-LabFixture {
        param([string]$Guide = $script:GoodGuide, [string]$Validator = $script:GoodValidator, [string]$Manifest, [switch]$NoLab, [switch]$NoResult)
        $dir = Join-Path $script:Fixture ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'tools') | Out-Null
        if (-not $Manifest) { $Manifest = "@{ Phases = @( @{ Id = '1.2'; Lab = 'module-1-x/1.2-a'; DependsOn = @('1.1') } ) }" }
        Set-Content -LiteralPath (Join-Path $dir 'tools' 'lab-cycle-manifest.psd1') -Value $Manifest
        if (-not $NoResult) { $Validator = $Validator + "`n" + $script:ExitLine }
        if (-not $NoLab) {
            $lab = Join-Path $dir 'module-1-x' '1.2-a'
            New-Item -ItemType Directory -Path (Join-Path $lab 'scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lab 'lab-guide-1.2.md') -Value $Guide
            Set-Content -LiteralPath (Join-Path $lab 'scripts' $script:ValidatorName) -Value $Validator
        }
        return $dir
    }

    function Invoke-Gate {
        param([string]$Repo, [string]$Allowlist = $script:EmptyAllowlist)
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $Repo -AllowlistPath $Allowlist 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-LabConsistency.ps1 - findings' {

    It 'passes on a lab whose guide, validator and manifest agree' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 guide\(s\), 1 validator\(s\), 1 manifest phase\(s\); 0 finding'
    }

    It 'fails on a validator that compares a property with -eq $false' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($sa.AllowBlobPublicAccess -eq $false) { "ok" }')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[NullUnsafeComparison\].*Test-Lab\.ps1'
    }

    It 'fails on a validator that compares a property with -ne $false' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($x.Enabled -ne $false) { "ok" }')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[NullUnsafeComparison\]'
    }

    It 'does not flag -eq $true or a plain variable' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($x.Enabled -eq $true -or $flag -eq $false) { "ok" }')
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'fails when the last Exit-Lab call of a validator has no -PassCount' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoResult -Validator "`$failCount = 0`nExit-Lab -FailureCount `$failCount")
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[ResultLine\].*Test-Lab\.ps1.*no -PassCount'
    }

    It 'fails when a validator never calls Exit-Lab' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoResult -Validator 'Write-Host "Tests Passed: 3"')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[ResultLine\].*never calls Exit-Lab'
    }

    It 'passes when the last Exit-Lab call has -PassCount, whatever an earlier or trap call does' {
        $validator = "trap { Exit-Lab -FailureCount 1 }`nExit-Lab -FailureCount 1`nExit-Lab -FailureCount `$f -PassCount `$p -SkipCount 2"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoResult -Validator $validator)
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'passes when the validator prints the RESULT line itself' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoResult -Validator 'Write-Host "RESULT passed=$p failed=$f"')
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'ignores an Exit-Lab call that is only in a comment' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoResult -Validator '# Exit-Lab -FailureCount 0 -PassCount 1')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[ResultLine\]'
    }

    It 'fails when the Prerequisites section does not name a manifest dependency' {
        $guide = $script:GoodGuide -replace 'Lab 1\.1 is done\.', 'Nothing else is needed.'
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[PrerequisiteEdges\].*depend on Lab 1\.1'
    }

    It 'fails when the guide has no Prerequisites section at all' {
        $guide = $script:GoodGuide -replace '(?s)## Prerequisites.*?(?=## Steps)', ''
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'no Prerequisites section'
    }

    It 'fails when the validator looks up a resource name no guide step names' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'Get-AzResourceGroup -Name "dev-skycraft-swc-rg"')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "\[ValidatorResourceName\].*looks up 'dev-skycraft-swc-rg'"
    }

    It 'passes when the guide of the lab names the resource the validator looks up' {
        $guide = $script:GoodGuide + "`nCreate the resource group dev-skycraft-swc-rg.`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide -Validator 'Get-AzResourceGroup -Name "dev-skycraft-swc-rg"')
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'fails when a body section is not in the Estimated Time list' {
        $guide = $script:GoodGuide + "`n## Estimated Time: 1 hour`n`n- **Section 1**: One (10 min)`n`n## Section 1: One (10 min)`n`n## Section 2: Two (10 min)`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "\[TimePlanSections\].*'## Section 2:' and the Estimated Time list does not"
    }

    It 'fails when the Estimated Time list names a section the body lacks' {
        $guide = $script:GoodGuide + "`n## Estimated Time: 1 hour`n`n- **Section 1**: One (10 min)`n- **Section 2**: Two (10 min)`n`n## Section 1: One (10 min)`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[TimePlanSections\].*names Section 2 and the body has no'
    }

    It 'fails when the guide has sections and no Estimated Time list' {
        $guide = $script:GoodGuide + "`n## Section 1: One (10 min)`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[TimePlanSections\]'
    }

    It 'passes when the time plan and the section headings agree' {
        $guide = $script:GoodGuide + "`n## Estimated Time: 1 hour`n`n- **Section 1**: One (10 min)`n- **Section 2**: Two (10 min)`n- **What This Lab Leaves Behind** (5 min)`n`n## Section 1: One (10 min)`n`n## Section 2: Two (10 min)`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'fails when an objective cites a section the body does not have' {
        $guide = "## Learning Objectives`n`n- Do a thing (Section 3)`n`n" + $script:GoodGuide
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[ObjectiveSection\].*cites Section 3'
    }

    It 'warns about a checklist name no step uses, without failing the gate' {
        $guide = $script:GoodGuide + "`n## Lab Checklist`n`n- [ ] ``ghost-resource`` exists`n`n## Next`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match "\[WARN\] \[ChecklistTerm\].*'ghost-resource'"
        $run.Output | Should -Match '1 warning\(s\)'
    }

    It 'does not warn when a step names the checklist item' {
        $guide = $script:GoodGuide + "`nCreate ghost-resource.`n`n## Lab Checklist`n`n- [ ] ``ghost-resource`` exists`n`n## Next`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '0 warning\(s\)'
    }

    It 'warns about a step that changes Azure with no Az PowerShell block, without failing the gate' {
        $guide = $script:GoodGuide + "`n### Step 1.2.1: Make it`n`nSelect **Create**.`n`n### Step 1.2.2: Make more`n`nSelect **Save**.`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '\[WARN\] \[ChangeStepCommand\].*2 step\(s\).*Step 1\.2\.1, 1\.2\.2'
    }

    It 'does not warn when the step has a PowerShell block, a Portal only marker or changes nothing' {
        $fence = '```'
        $guide = $script:GoodGuide + "`n### Step 1.2.1: Make it`n`nSelect **Create**.`n`n${fence}powershell`nNew-AzResourceGroup`n${fence}`n`n### Step 1.2.2: Demo`n`nPortal only. Select **Save**.`n`n### Step 1.2.3: Look`n`nOpen the blade.`n"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Not -Match 'ChangeStepCommand'
    }

    It 'fails when the guide has no Leaves Behind section' {
        $guide = $script:GoodGuide -replace '(?s)## What This Lab Leaves Behind.*', ''
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[LeavesBehindSection\]'
    }
}

Describe 'Test-LabConsistency.ps1 - the allowlist' {

    BeforeAll {
        $script:Weak = 'if ($sa.AllowBlobPublicAccess -eq $false) { "ok" }'
        $script:WeakFile = "module-1-x/1.2-a/scripts/$script:ValidatorName"
    }

    It 'lets an allowlisted finding pass' {
        $list = Join-Path $script:Fixture 'allow.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = '$script:WeakFile'; Match = '`$sa.AllowBlobPublicAccess -eq `$false'; Reason = 'fixture' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator $script:Weak) -Allowlist $list
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 finding\(s\), 0 not allowlisted'
    }

    It 'fails on an entry that matches no finding any more' {
        $list = Join-Path $script:Fixture 'stale.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = '$script:WeakFile'; Match = 'gone'; Reason = 'fixture' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist $list
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'matches no finding any more'
    }

    It 'fails on an entry without a reason' {
        $list = Join-Path $script:Fixture 'noreason.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = 'a'; Match = 'b'; Reason = '' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist $list
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'has no Reason'
    }

    It 'fails when the allowlist does not exist' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist (Join-Path $script:Fixture 'nope.psd1')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'does not exist'
    }
}

Describe 'Test-LabConsistency.ps1 - a check that did not run is not a pass' {

    It 'fails when the repository holds no lab at all' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoLab)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'Found no guide, no validator'
    }

    It 'fails when the manifest is missing' {
        $dir = Initialize-LabFixture
        Remove-Item -LiteralPath (Join-Path $dir 'tools' 'lab-cycle-manifest.psd1')
        $run = Invoke-Gate -Repo $dir
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'manifest .* does not exist'
    }
}

Describe 'Test-LabConsistency.ps1 - the repository' {

    It 'passes on this repository' {
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $script:RepoRoot 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'Lab consistency check passed'
    }

    It 'gives every allowlist entry a reason' {
        $list = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'tools' 'lab-consistency-allowlist.psd1')
        foreach ($entry in @($list.Allow)) { "$($entry.Reason)".Trim() | Should -Not -BeNullOrEmpty -Because "$($entry.File) needs a reason" }
    }
}
