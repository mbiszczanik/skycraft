#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the subscription-scope budget assertion of tools/Remove-LabCycle.ps1.

.DESCRIPTION
    Runs the real Remove-LabCycle.ps1 in-process with every probe injected. Nothing here reaches
    Azure: the scriptblock parameters get a poisoned default and every Az command the script
    names is shadowed, the isolation tests/LabCycle.Tests.ps1 applies (#152).

.NOTES
    Project: SkyCraft
    Issue:   #526
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $script:Cycle = Join-Path $script:Root 'tools/Remove-LabCycle.ps1'
    Import-Module (Join-Path (Join-Path $PSScriptRoot 'Support') 'LabCycleIsolation.psm1') -Force

    # Poison: records, then throws. A forgotten override inside the script's try/catch would be a
    # failed assertion, so the ledger is what the last test reads.
    $script:Ledger = [System.Collections.Generic.List[string]]::new()
    function Get-Poison {
        param([Parameter(Mandatory)][string]$Name)
        $ledger = $script:Ledger
        $label = $Name
        { $ledger.Add($label); throw "LabCycle-Residue.Tests reached '$label', a real default. Override it in the call." }.GetNewClosure()
    }

    $defaults = @{}
    foreach ($key in @($global:PSDefaultParameterValues.Keys)) { $defaults[$key] = $global:PSDefaultParameterValues[$key] }
    foreach ($parameter in @(Get-LabCycleScriptblockParameter -Path $script:Cycle)) {
        $poison = Get-Poison -Name $parameter.Key
        $defaults[$parameter.Key] = { $poison }.GetNewClosure()
    }
    $script:PSDefaultParameterValues = $defaults

    $script:AzCommands = @(Get-LabCycleAzCommand -Path $script:Cycle)
    foreach ($name in $script:AzCommands) {
        Set-Item -LiteralPath "Function:\global:$name" -Value (Get-Poison -Name $name)
    }

    function Get-ResidueManifest {
        param([Parameter(Mandatory)][string]$Budgets)
        $path = Join-Path $TestDrive "manifest-$([guid]::NewGuid().ToString('N')).psd1"
        @"
@{
    Phases = @(@{ Id = '1.3'; Lab = 'locks' })
    UniqueNames = @()
    Teardowns = @(@{ Lab = 'locks'; Invocations = @(@{ Force = `$true }); TimeoutMs = 1000 })
    ResidualSweep = @{
        ResourceGroups = @('fixture-rg')
        AssertAbsent = @()
        BackupResourceGroupPrefix = 'AzureBackupRG_'
        AssertAbsentBudgets = @($Budgets)
    }
    ToolingFloor = @{ AzCli = '2.75.0'; AzPowerShell = '7.5.0' }
}
"@ | Set-Content -LiteralPath $path -Encoding utf8
        $path
    }

    # Runs the script and returns its result object, its console text and the results-file lines.
    function Invoke-ResidueCycle {
        param(
            [Parameter(Mandatory)][string]$Manifest,
            [Parameter(Mandatory)][scriptblock]$BudgetProbe,
            [switch]$DryRun
        )
        $resultsPath = Join-Path $TestDrive "results-$([guid]::NewGuid().ToString('N')).jsonl"
        $probes = @{
            ContextProbe = { @{ Subscription = @{ Id = 'fixture-subscription' } } }
            ToolingFloorRunner = { @() }
            TeardownRunner = { 0 }
            BackupResourceGroupProbe = { @() }
            ResourceGroupProbe = { $null }
            VaultProbe = { $null }
            ResourceGroupRemover = { $null }
            DiagnosticTargetProbe = { @() }
            DiagnosticSettingProbe = { @() }
            DiagnosticSettingRemover = { 0 }
            BudgetProbe = $BudgetProbe
        }
        $all = & $script:Cycle -SubscriptionId 'fixture-subscription' -ManifestPath $Manifest `
            -Confirm:$false -WhatIf:$DryRun -LogDirectory (Join-Path $TestDrive 'logs') -ResultsPath $resultsPath @probes *>&1
        $exit = $LASTEXITCODE
        [pscustomobject]@{
            Exit = $exit
            Result = @($all | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.Properties['Assertions'] }) | Select-Object -First 1
            Text = (@($all | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" }) -join "`n")
            Lines = @(if (Test-Path -LiteralPath $resultsPath) { Get-Content -LiteralPath $resultsPath })
        }
    }

    $script:Plain = "@{ Name = 'SkyCraft-Monthly-Budget'; Lab = '1.3' }"
}

AfterAll {
    foreach ($name in @($script:AzCommands)) {
        Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
    }
}

Describe 'Budget assertion after a full teardown' {
    It 'passes and records an assertion when the budget is gone' {
        $run = Invoke-ResidueCycle -Manifest (Get-ResidueManifest -Budgets $script:Plain) -BudgetProbe { $null }
        $run.Exit | Should -Be 0
        $run.Text | Should -Match 'budget .SkyCraft-Monthly-Budget. is gone'
        @($run.Result.Assertions | Where-Object { $_.Name -eq 'budget absent' -and $_.Ok }).Count | Should -Be 1
        @($run.Lines | Where-Object { $_ -match '"Target":"budget absent"' -and $_ -match '"Status":"Passed"' }).Count | Should -Be 1
    }

    It 'passes the entry and the subscription id to the probe' {
        $seen = @{ Name = $null; Sub = $null }
        Invoke-ResidueCycle -Manifest (Get-ResidueManifest -Budgets $script:Plain) -BudgetProbe {
            param($Entry, $SubId) $seen.Name = $Entry.Name; $seen.Sub = $SubId; $null
        }.GetNewClosure() | Out-Null
        $seen.Name | Should -Be 'SkyCraft-Monthly-Budget'
        $seen.Sub | Should -Be 'fixture-subscription'
    }

    It 'fails, names the budget and Lab 1.3, and exits non-zero when the budget is present' {
        $run = Invoke-ResidueCycle -Manifest (Get-ResidueManifest -Budgets $script:Plain) -BudgetProbe { @{ Name = 'SkyCraft-Monthly-Budget' } }
        $run.Exit | Should -Not -Be 0
        $run.Text | Should -Match '\[FAIL\].*Lab 1\.3 budget .SkyCraft-Monthly-Budget. still exists'
        $run.Result.AssertionFailedCount | Should -Be 1
        @($run.Lines | Where-Object { $_ -match '"Target":"budget absent"' -and $_ -match '"Status":"Failed"' -and $_ -match 'Lab 1\.3' }).Count | Should -Be 1
    }

    It 'reports the check as not run, never as gone, when the listing throws' {
        $run = Invoke-ResidueCycle -Manifest (Get-ResidueManifest -Budgets $script:Plain) -BudgetProbe { throw 'AuthorizationFailed' }
        $run.Exit | Should -Not -Be 0
        $run.Text | Should -Match 'Could not check whether Lab 1\.3 budget .SkyCraft-Monthly-Budget. is gone'
        $run.Text | Should -Not -Match '\[ OK \].*budget' -Because 'a failed listing must not read as gone'
        $failed = @($run.Result.Assertions | Where-Object { $_.Name -eq 'budget absent' -and -not $_.Ok })
        $failed.Count | Should -Be 1
        $failed[0].Detail | Should -Match 'AuthorizationFailed'
    }

    It 'reports a KeptByDesign budget as kept with its reason and does not fail or probe it' {
        $calls = @{ Count = 0 }
        $budgets = "@{ Name = 'SkyCraft-Monthly-Budget'; Lab = '1.3'; KeptByDesign = 'tenant owner keeps it' }"
        $run = Invoke-ResidueCycle -Manifest (Get-ResidueManifest -Budgets $budgets) -BudgetProbe { $calls.Count++; @{ Name = 'x' } }.GetNewClosure()
        $run.Exit | Should -Be 0
        $run.Text | Should -Match '\[KEPT\].*SkyCraft-Monthly-Budget.*tenant owner keeps it'
        $calls.Count | Should -Be 0
        $run.Result.AssertionFailedCount | Should -Be 0
    }

    It 'asserts nothing for budgets under -WhatIf' {
        $calls = @{ Count = 0 }
        $run = Invoke-ResidueCycle -DryRun -Manifest (Get-ResidueManifest -Budgets $script:Plain) -BudgetProbe { $calls.Count++; @{ Name = 'x' } }.GetNewClosure()
        $run.Exit | Should -Be 0
        $calls.Count | Should -Be 0
        @($run.Result.Assertions | Where-Object { $_.Name -eq 'budget absent' }).Count | Should -Be 0
    }

    It 'lists the budget in the real manifest at subscription scope for Lab 1.3' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'tools/lab-cycle-manifest.psd1')
        $entry = @($manifest.ResidualSweep.AssertAbsentBudgets | Where-Object { $_.Name -eq 'SkyCraft-Monthly-Budget' })
        $entry.Count | Should -Be 1
        $entry[0].Lab | Should -Be '1.3'
    }
}

Describe 'Isolation - no test reached a real default' {
    It 'recorded no poison hit' {
        $script:Ledger | Should -BeNullOrEmpty
    }
}
