<#
.SYNOPSIS
    Pester 5 tests: Lab 5.2's Site Recovery test failover is optional, and the lab's end state is
    a Protected replication.

.DESCRIPTION
    Issue #366, maintainer decision of 2026-10-31: a Free Trial subscription often cannot start
    the failover VM (Standard_B2ls_v2 is not offered in North Europe, the core quota is 4,
    confidential sizes are refused, and Site Recovery's default Standard_HC44rs needs 44 cores),
    so the test failover is an optional, clearly documented step. These tests read the guide, the
    checklist and the scripts, and assert:

      1. The guide marks Step 5.2.7 optional and says in plain words that the size must be offered
         in North Europe and fit the core quota, that Free Trial subscriptions often cannot, and
         that the learner can skip the step or request quota.
      2. The checklist marks its Test Failover section optional.
      3. Enable-SiteRecovery.ps1 starts a test failover only under -TestFailover, and Deploy-Bicep.ps1
         never passes that switch.
      4. Test-Lab.ps1 reads no test failover state, so it cannot require one.

    No Azure sign-in is needed.

.EXAMPLE
    Invoke-Pester -Path .\Site-Recovery-Optional-Failover.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #366
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Guide = Get-Content -LiteralPath (Join-Path $script:LabRoot 'lab-guide-5.2.md') -Raw
    $script:Checklist = Get-Content -LiteralPath (Join-Path $script:LabRoot 'lab-checklist-5.2.md') -Raw

    function Get-ScriptAst {
        param([string]$Name)
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:LabRoot 'scripts' $Name), [ref]$null, [ref]$null)
    }

    # The text of Step 5.2.7, up to the next level-3 heading.
    $step = [regex]::Match($script:Guide, '(?ms)^### Step 5\.2\.7:.*?(?=^### )')
    $script:StepText = $step.Value
}

Describe 'Lab 5.2 guide - Step 5.2.7 is optional (#366)' {

    It 'finds the step' {
        $script:StepText | Should -Not -BeNullOrEmpty
    }

    It 'marks the step optional in its heading' {
        $script:StepText | Should -Match '(?m)^### Step 5\.2\.7: Perform Test Failover \(optional\)'
    }

    It 'says the lab ends at a Protected replication and Test-Lab, with no test failover needed' {
        $script:StepText | Should -Match 'This step is optional'
        $script:StepText | Should -Match 'Protected'
        $script:StepText | Should -Match 'Test-Lab\.ps1'
    }

    It 'says the size must be offered in North Europe and fit the core quota' {
        $script:StepText | Should -Match 'offered to your subscription there'
        $script:StepText | Should -Match 'free cores of its quota'
    }

    It 'names what a Free Trial subscription runs into' {
        $script:StepText | Should -Match 'Free Trial'
        $script:StepText | Should -Match 'Standard_B2ls_v2'
        $script:StepText | Should -Match 'core quota is 4'
        $script:StepText | Should -Match 'confidential size'
        $script:StepText | Should -Match 'Standard_HC44rs'
        $script:StepText | Should -Match '44 cores'
    }

    It 'says what to do: skip the step, or request quota' {
        $script:StepText | Should -Match 'skip this step'
        $script:StepText | Should -Match 'request core quota for North Europe'
    }

    It 'says the script stops with exit code 1 and a message when no size fits' {
        $script:StepText | Should -Match 'exit code 1'
    }

    It 'does not put the test failover in the objectives or the summary as a requirement' {
        $script:Guide | Should -Match 'run an optional test failover'
        $script:Guide | Should -Match 'Optionally performed a \*\*Test Failover\*\*'
        $script:Guide | Should -Not -Match '(?m)^- \[ \] Test failover succeeded'
    }
}

Describe 'Lab 5.2 checklist - the test failover is optional (#366)' {

    It 'marks the Test Failover section optional and says the lab is complete with a Protected replication' {
        $script:Checklist | Should -Match '(?m)^### Test Failover \(optional\)'
        $script:Checklist | Should -Match 'The lab is complete with a \*\*Protected\*\* replication'
    }

    It 'names the Free Trial limit and the choice to skip' {
        $script:Checklist | Should -Match 'Free Trial'
        $script:Checklist | Should -Match 'skip the step'
    }
}

Describe 'Lab 5.2 scripts - the test failover only runs on request (#366)' {

    It 'starts the test failover job only inside if ($TestFailover)' {
        $ast = Get-ScriptAst -Name 'Enable-SiteRecovery.ps1'
        $starts = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Start-AzRecoveryServicesAsrTestFailoverJob' }, $true))
        $starts.Count | Should -BeGreaterThan 0
        foreach ($call in $starts) {
            $parent = $call.Parent
            $guarded = $false
            while ($parent) {
                if ($parent -is [System.Management.Automation.Language.IfStatementAst] -and
                    @($parent.Clauses | Where-Object { $_.Item1.Extent.Text -eq '$TestFailover' }).Count -gt 0) { $guarded = $true; break }
                $parent = $parent.Parent
            }
            $guarded | Should -BeTrue -Because "line $($call.Extent.StartLineNumber) must sit under if (`$TestFailover)"
        }
    }

    It 'keeps -TestFailover a switch that is off by default' {
        $ast = Get-ScriptAst -Name 'Enable-SiteRecovery.ps1'
        $parameter = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'TestFailover' })
        $parameter | Should -HaveCount 1
        $parameter[0].StaticType.Name | Should -Be 'SwitchParameter'
        $parameter[0].DefaultValue | Should -BeNullOrEmpty
    }

    It 'never lets Deploy-Bicep.ps1 pass -TestFailover' {
        $ast = Get-ScriptAst -Name 'Deploy-Bicep.ps1'
        $withSwitch = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandParameterAst] -and $n.ParameterName -eq 'TestFailover' }, $true))
        $withSwitch | Should -BeNullOrEmpty
    }

    It 'makes Test-Lab.ps1 read no test failover state, so it cannot require a test failover' {
        $ast = Get-ScriptAst -Name 'Test-Lab.ps1'
        $uses = @($ast.FindAll({ param($n) $n.Extent.Text -match 'TestFailover' -and
                    ($n -is [System.Management.Automation.Language.CommandAst] -or
                    $n -is [System.Management.Automation.Language.MemberExpressionAst] -or
                    $n -is [System.Management.Automation.Language.VariableExpressionAst]) }, $true))
        $uses | Should -BeNullOrEmpty -Because 'a check on a test failover would make an optional step required'
    }
}
