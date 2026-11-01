BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $script:Cycle = Join-Path $script:Root 'tools/Remove-LabCycle.ps1'
    $script:ManifestPath = Join-Path $TestDrive 'manifest.psd1'
    @'
@{
    Phases = @(@{ Id = '1.3'; Lab = 'locks' }, @{ Id = '1.2'; Lab = 'groups' })
    UniqueNames = @()
    Teardowns = @(
        @{ Lab = 'locks'; Invocations = @(@{ Force = $true }); TimeoutMs = 1000 }
        @{ Lab = 'groups'; Invocations = @(@{ Force = $true }); TimeoutMs = 1000 }
    )
    ResidualSweep = @{ ResourceGroups = @('fixture-rg'); AssertAbsent = @(); BackupResourceGroupPrefix = 'AzureBackupRG_' }
    ToolingFloor = @{ AzCli = '2.75.0'; AzPowerShell = '7.5.0' }
}
'@ | Set-Content -LiteralPath $script:ManifestPath -Encoding utf8
    $script:Id = '/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/Microsoft.Storage/storageAccounts/fixture/blobServices/default'
    function Invoke-DiagnosticCycle {
        param([hashtable]$Override = @{}, [switch]$WhatIf, [switch]$SkipSweep, [string[]]$Labs = @(), [hashtable]$UniqueNames = @{})
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
        }
        foreach ($key in $Override.Keys) { $probes[$key] = $Override[$key] }
        & $script:Cycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ManifestPath `
            -Confirm:$false -WhatIf:$WhatIf -SkipSweep:$SkipSweep -Labs $Labs -UniqueNames $UniqueNames `
            -LogDirectory (Join-Path $TestDrive 'logs') -ResultsPath (Join-Path $TestDrive 'results.jsonl') @probes
    }
}

Describe 'Cycle diagnostics' {
    It 'captures before teardown and removes after locks before resource teardown' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $id = $script:Id
        Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { param($Group) $calls.Add("capture:$Group"); $id }.GetNewClosure()
            DiagnosticSettingProbe = { param($Id) $calls.Add("read:$Id") }.GetNewClosure()
            DiagnosticSettingRemover = { param($Ids) $calls.Add('remove'); 0 }.GetNewClosure()
            TeardownRunner = { param($Invocation) $calls.Add("lab:$($Invocation.Lab)"); 0 }.GetNewClosure()
        } | Out-Null
        $calls[0] | Should -Be 'capture:fixture-rg'
        [array]::IndexOf($calls.ToArray(), 'remove') | Should -BeGreaterThan ([array]::IndexOf($calls.ToArray(), 'lab:locks'))
        [array]::IndexOf($calls.ToArray(), 'remove') | Should -BeLessThan ([array]::IndexOf($calls.ToArray(), 'lab:groups'))
        @($calls | Where-Object { $_ -eq "read:$id" }).Count | Should -BeGreaterOrEqual 2
    }
    It 'refuses all lab teardown when capture fails' {
        $seen = @{ Count = 0 }
        Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { throw 'AuthorizationFailed' }
            TeardownRunner = { $seen.Count++; 0 }.GetNewClosure()
        } | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $seen.Count | Should -Be 0
    }
    It 'refuses all lab teardown when a diagnostic read fails' {
        $seen = @{ Count = 0 }
        $id = $script:Id
        Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { $id }.GetNewClosure()
            DiagnosticSettingProbe = { throw 'AuthorizationFailed' }
            TeardownRunner = { $seen.Count++; 0 }.GetNewClosure()
        } | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $seen.Count | Should -Be 0
    }
    It 'stops resource teardown when removal fails after locks' {
        $seen = [System.Collections.Generic.List[string]]::new()
        $id = $script:Id
        Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { $id }.GetNewClosure()
            DiagnosticSettingRemover = { 1 }
            TeardownRunner = { param($Invocation) $seen.Add($Invocation.Lab); 0 }.GetNewClosure()
        } | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $seen.ToArray() | Should -Contain 'locks'
        $seen.ToArray() | Should -Not -Contain 'groups'
    }
    It 'fails for an orphan on an id captured before its parent was deleted' {
        $state = @{ Removed = $false }
        $id = $script:Id
        $result = Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { if (-not $state.Removed) { $id } }.GetNewClosure()
            DiagnosticSettingProbe = { if ($state.Removed) { @{ Name = 'orphan' } } }.GetNewClosure()
            TeardownRunner = { $state.Removed = $true; 0 }.GetNewClosure()
        }
        $LASTEXITCODE | Should -Not -Be 0
        @($result.Assertions | Where-Object { $_.Name -eq 'diagnostic settings absent' -and -not $_.Ok }).Count | Should -Be 1
    }
    It 'skips broad discovery for partial and SkipSweep teardown' {
        foreach ($mode in 'partial', 'skip') {
            $seen = @{ Count = 0 }
            $arguments = @{ Override = @{ DiagnosticTargetProbe = { $seen.Count++; throw 'unexpected lookup' }.GetNewClosure() } }
            if ($mode -eq 'partial') { $arguments.Labs = @('1.3') } else { $arguments.SkipSweep = $true }
            Invoke-DiagnosticCycle @arguments | Out-Null
            $LASTEXITCODE | Should -Be 0
            $seen.Count | Should -Be 0
        }
    }
    It 'does not remove diagnostics under WhatIf' {
        $seen = @{ Count = 0 }
        $id = $script:Id
        Invoke-DiagnosticCycle -WhatIf -Override @{
            DiagnosticTargetProbe = { $id }.GetNewClosure()
            DiagnosticSettingRemover = { $seen.Count++; 0 }.GetNewClosure()
        } | Out-Null
        $LASTEXITCODE | Should -Be 0
        $seen.Count | Should -Be 0
    }
    It 'keeps a group when a fresh target cannot be cleaned immediately before sweep deletion' {
        $state = @{ Captures = 0; Deleted = 0 }
        $id = $script:Id
        $result = Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { $state.Captures++; if ($state.Captures -gt 1) { $id } }.GetNewClosure()
            DiagnosticSettingRemover = { 1 }
            ResourceGroupProbe = { 'present' }
            ResourceGroupRemover = { $state.Deleted++; $null }.GetNewClosure()
        }
        $LASTEXITCODE | Should -Not -Be 0
        $state.Deleted | Should -Be 0
        $result.TeardownFailedCount | Should -Be 1
    }
    It 'fails a final diagnostic assertion when its read fails' {
        $state = @{ Reads = 0 }
        $id = $script:Id
        $result = Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { $id }.GetNewClosure()
            DiagnosticSettingProbe = { $state.Reads++; if ($state.Reads -gt 1) { throw 'AuthorizationFailed' } }.GetNewClosure()
        }
        $LASTEXITCODE | Should -Not -Be 0
        @($result.Assertions | Where-Object { $_.Name -eq 'diagnostic settings absent' -and -not $_.Ok }).Count | Should -Be 1
    }
    It 'rejects discovered IDs outside the chosen group before any lab runs' {
        $seen = @{ Count = 0 }
        Invoke-DiagnosticCycle -Override @{
            DiagnosticTargetProbe = { '/subscriptions/fixture-subscription/resourceGroups/other/providers/Microsoft.KeyVault/vaults/fixture' }
            TeardownRunner = { $seen.Count++; 0 }.GetNewClosure()
        } | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $seen.Count | Should -Be 0
    }
    It 'checks manifest IDs with custom names even when parents were deleted before this run' {
        $original = Get-Content -LiteralPath $script:ManifestPath -Raw -Encoding utf8
        try {
            $body = $original.Replace('UniqueNames = @()', "UniqueNames = @(@{ Parameter = 'DevSaName'; Default = 'defaultaccount' })")
            $body = $body.Replace("ResourceGroups = @('fixture-rg');", "DiagnosticResources = @(@{ ResourceGroup = 'fixture-rg'; ResourceType = 'Microsoft.Storage/storageAccounts'; Name = 'defaultaccount'; NameParameter = 'DevSaName' }); ResourceGroups = @('fixture-rg');")
            Set-Content -LiteralPath $script:ManifestPath -Value $body -Encoding utf8
            $calls = [System.Collections.Generic.List[string]]::new()
            $probes = @{
                DiagnosticSettingProbe = { param($Id) $calls.Add($Id) }.GetNewClosure()
            }
            Invoke-DiagnosticCycle -Override $probes -UniqueNames @{ DevSaName = 'customaccount' } | Out-Null
            $calls.ToArray() | Should -Contain '/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/Microsoft.Storage/storageAccounts/customaccount/blobServices/default'
            $calls.ToArray() | Should -Not -Contain '/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/Microsoft.Storage/storageAccounts/defaultaccount/blobServices/default'
        }
        finally { Set-Content -LiteralPath $script:ManifestPath -Value $original -Encoding utf8 }
    }
}
