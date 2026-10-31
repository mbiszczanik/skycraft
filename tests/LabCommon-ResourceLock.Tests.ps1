<#
.SYNOPSIS
    Pester 5 tests for Invoke-LabWithoutLock in tools/LabCommon.psm1 (issue #372).

.DESCRIPTION
    Lab 1.3 puts a CanNotDelete lock on platform-skycraft-swc-rg and prod-skycraft-swc-rg, and
    every delete the later cleanups make in those groups failed with ScopeLocked (live run of
    2026-10-28: Labs 4.1-5.3, Removed 2 Failed 5). Invoke-LabWithoutLock lifts the lock for the
    deletes and puts it back. These tests pin that:

      1. A locked group: the lock is read, removed, the deletes run, and the lock is put back
         with the same level, notes and owners. No other lock and no other group is touched.
      2. A delete that throws still has the lock put back.
      3. A lock that cannot be read, or removed, is an [ERROR], and no delete runs; a lock
         already removed is put back.
      4. A lock that cannot be put back is an [ERROR] that says the group is unlocked and gives
         the command that recreates the lock.
      5. Under -WhatIf no lock is removed or restored, and the deletes still report.

    No subscription is needed, and none is used: global functions named Invoke-AzRestMethod and
    Get-AzContext answer in place of the Az.Accounts cmdlets (a function outranks a cmdlet), and
    hold the locks in memory.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-ResourceLock.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #372
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabCommon = Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1') -Force -PassThru

    $script:Prod     = 'prod-skycraft-swc-rg'
    $script:Platform = 'platform-skycraft-swc-rg'
    $script:Notes    = 'Cannot delete resource or child resources.'

    # The fake ARM locks API: Locks maps a group to its Lab 1.3 lock (or nothing), Fail maps
    # '<METHOD>:<group>' to how many times that request fails before it succeeds (-1: always).
    $global:SkyCraftLockFake = [pscustomobject]@{
        Calls     = [System.Collections.Generic.List[string]]::new()
        Locks     = @{}
        Fail      = @{}
        NoContext = $false
    }

    function global:Get-AzContext {
        [CmdletBinding()]
        param()
        if ($global:SkyCraftLockFake.NoContext) { return $null }
        [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
    }

    function global:Invoke-AzRestMethod {
        [CmdletBinding()]
        param([string]$Path, [string]$Method = 'GET', [string]$Payload)
        $fake = $global:SkyCraftLockFake
        if ($Path -notmatch '^/subscriptions/0{8}-0{4}-0{4}-0{4}-0{12}/resourceGroups/(?<group>[^/]+)/providers/Microsoft\.Authorization/locks/(?<name>[^/?]+)\?api-version=2020-05-01$') {
            throw "fake: unexpected ARM request $Method $Path"
        }
        $group = $Matches['group']
        $name = $Matches['name']
        $fake.Calls.Add("${Method}:${group}:${name}")
        $key = "${Method}:${group}"
        if ($fake.Fail.ContainsKey($key) -and $fake.Fail[$key] -ne 0) {
            $fake.Fail[$key]--
            return [pscustomobject]@{ StatusCode = 403; Content = (@{ error = @{ code = 'AuthorizationFailed'; message = "stub: $key refused" } } | ConvertTo-Json -Compress) }
        }
        $lock = $fake.Locks[$group]
        switch ($Method) {
            'GET' {
                if (-not $lock -or $lock.name -ne $name) {
                    return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"LockNotFound","message":"The lock was not found."}}' }
                }
                return [pscustomobject]@{ StatusCode = 200; Content = ($lock | ConvertTo-Json -Depth 6 -Compress) }
            }
            'DELETE' {
                $fake.Locks.Remove($group)
                return [pscustomobject]@{ StatusCode = 200; Content = '' }
            }
            'PUT' {
                $body = $Payload | ConvertFrom-Json -AsHashtable
                $fake.Locks[$group] = @{ id = ($Path -split '\?')[0]; name = $name; properties = $body.properties }
                return [pscustomobject]@{ StatusCode = 200; Content = ($fake.Locks[$group] | ConvertTo-Json -Depth 6 -Compress) }
            }
        }
        throw "fake: unexpected method $Method"
    }

    function New-Lab13Lock {
        param([string]$Group, [string]$Level = 'CanNotDelete', [string]$Notes = $script:Notes, [object[]]$Owners = @())
        $name = if ($Group -eq $script:Prod) { 'lock-no-delete-prod' } else { 'lock-no-delete-platform' }
        $properties = @{ level = $Level; notes = $Notes }
        if ($Owners.Count -gt 0) { $properties.owners = $Owners }
        @{ id = "/subscriptions/0/resourceGroups/$Group/providers/Microsoft.Authorization/locks/$name"; name = $name; properties = $properties }
    }

    function Reset-LockFake {
        param([hashtable]$Locks = @{}, [hashtable]$Fail = @{})
        $global:SkyCraftLockFake.Calls.Clear()
        $global:SkyCraftLockFake.Locks = $Locks
        $global:SkyCraftLockFake.Fail = $Fail
        $global:SkyCraftLockFake.NoContext = $false
        $global:SkyCraftLockFake | Add-Member -NotePropertyName ActionRan -NotePropertyValue $false -Force
        $global:SkyCraftLockFake | Add-Member -NotePropertyName LocksDuringAction -NotePropertyValue $null -Force
    }

    # Runs the helper and splits what it returns from what it writes to the host.
    function Invoke-Helper {
        param([string[]]$Group, [scriptblock]$Action, [switch]$DryRun)
        if (-not $Action) {
            $Action = {
                $global:SkyCraftLockFake.ActionRan = $true
                $global:SkyCraftLockFake.LocksDuringAction = @($global:SkyCraftLockFake.Locks.Keys)
            }
        }
        $all = @(Invoke-LabWithoutLock -ResourceGroupName $Group -Action $Action -WhatIf:$DryRun 6>&1)
        [pscustomobject]@{
            Result = @($all | Where-Object { $_ -is [int] })
            Text   = ($all | Where-Object { $_ -isnot [int] } | Out-String)
        }
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-AzRestMethod, Function:\Get-AzContext -ErrorAction SilentlyContinue
    Remove-Variable -Name SkyCraftLockFake -Scope Global -ErrorAction SilentlyContinue
    if ($script:LabCommon) { Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue }
}

Describe 'Invoke-LabWithoutLock - a locked group (#372)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'lifts the lock, runs the deletes without it, and puts it back as it was' {
        $before = New-Lab13Lock -Group $script:Prod -Owners @(@{ applicationId = 'app-1' })
        Reset-LockFake -Locks @{ $script:Prod = $before }

        $run = Invoke-Helper -Group $script:Prod

        $run.Result | Should -Be @(0)
        $global:SkyCraftLockFake.ActionRan | Should -BeTrue
        $global:SkyCraftLockFake.LocksDuringAction | Should -Not -Contain $script:Prod -Because 'the deletes must run with the lock lifted'
        @($global:SkyCraftLockFake.Calls) | Should -Be @(
            'GET:prod-skycraft-swc-rg:lock-no-delete-prod'
            'DELETE:prod-skycraft-swc-rg:lock-no-delete-prod'
            'PUT:prod-skycraft-swc-rg:lock-no-delete-prod'
        )
        $after = $global:SkyCraftLockFake.Locks[$script:Prod]
        $after.name | Should -Be 'lock-no-delete-prod'
        $after.properties.level | Should -Be 'CanNotDelete'
        $after.properties.notes | Should -Be $script:Notes
        @($after.properties.owners).applicationId | Should -Be 'app-1'
        $run.Text | Should -Match "Restored Lab 1.3's lock 'lock-no-delete-prod'"
    }

    It 'restores the level it found, not a fixed one' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod -Level 'ReadOnly' -Notes '') }
        (Invoke-Helper -Group $script:Prod).Result | Should -Be @(0)
        $global:SkyCraftLockFake.Locks[$script:Prod].properties.level | Should -Be 'ReadOnly'
        $global:SkyCraftLockFake.Locks[$script:Prod].properties.Keys | Should -Not -Contain 'notes'
    }

    It 'waits for the removal to reach ARM once, before the deletes' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod); $script:Platform = (New-Lab13Lock -Group $script:Platform) }
        (Invoke-Helper -Group $script:Prod, $script:Platform).Result | Should -Be @(0)
        Should -Invoke -ModuleName LabCommon Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 45 }
        $global:SkyCraftLockFake.Locks.Keys | Should -Contain $script:Prod
        $global:SkyCraftLockFake.Locks.Keys | Should -Contain $script:Platform
    }

    It 'only asks for the Lab 1.3 lock of each group, and ignores groups Lab 1.3 does not lock' {
        Reset-LockFake -Locks @{ $script:Platform = (New-Lab13Lock -Group $script:Platform) }
        (Invoke-Helper -Group 'dev-skycraft-swc-rg', $script:Platform, $script:Platform).Result | Should -Be @(0)
        $global:SkyCraftLockFake.Calls | Should -Not -Match 'dev-skycraft-swc-rg'
        @($global:SkyCraftLockFake.Calls | Where-Object { $_ -notmatch ':lock-no-delete-platform$' }) | Should -BeNullOrEmpty
        @($global:SkyCraftLockFake.Calls | Where-Object { $_ -like 'DELETE:*' }).Count | Should -Be 1
    }

    It 'runs the deletes and calls nothing for a group that is not one Lab 1.3 locks' {
        Reset-LockFake
        (Invoke-Helper -Group 'dev-skycraft-swc-rg').Result | Should -Be @(0)
        $global:SkyCraftLockFake.ActionRan | Should -BeTrue
        $global:SkyCraftLockFake.Calls | Should -BeNullOrEmpty
    }

    It 'runs the deletes when the group has no Lab 1.3 lock, and removes nothing' {
        Reset-LockFake
        (Invoke-Helper -Group $script:Prod).Result | Should -Be @(0)
        $global:SkyCraftLockFake.ActionRan | Should -BeTrue
        @($global:SkyCraftLockFake.Calls) | Should -Be @('GET:prod-skycraft-swc-rg:lock-no-delete-prod')
        Should -Invoke -ModuleName LabCommon Start-Sleep -Times 0 -Exactly
    }

    It "runs the deletes in the caller's scope" {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) }
        $fromCaller = 'caller value'
        Invoke-Helper -Group $script:Prod -Action { $global:SkyCraftLockFake.ActionRan = $fromCaller } | Out-Null
        $global:SkyCraftLockFake.ActionRan | Should -Be 'caller value'
    }
}

Describe 'Invoke-LabWithoutLock - the lock comes back after a failed delete (#372)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'puts the lock back when the deletes throw, and lets the error through' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) }
        { Invoke-LabWithoutLock -ResourceGroupName $script:Prod -Action { throw 'stub: delete failed' } 6>$null } | Should -Throw '*stub: delete failed*'
        $global:SkyCraftLockFake.Calls[-1] | Should -Be 'PUT:prod-skycraft-swc-rg:lock-no-delete-prod'
        $global:SkyCraftLockFake.Locks[$script:Prod].properties.notes | Should -Be $script:Notes
    }
}

Describe 'Invoke-LabWithoutLock - a lock it cannot read or lift (#372)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'counts a lock it cannot read as a failure and runs no delete' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) } -Fail @{ "GET:$script:Prod" = -1 }
        $run = Invoke-Helper -Group $script:Prod
        $run.Result | Should -Be @(1)
        $global:SkyCraftLockFake.ActionRan | Should -BeFalse
        $global:SkyCraftLockFake.Calls | Should -Not -Match '^(DELETE|PUT):'
        $run.Text | Should -Match "\[ERROR\] Could not read Lab 1.3's lock 'lock-no-delete-prod' on 'prod-skycraft-swc-rg'[^\r\n]*AuthorizationFailed"
        $run.Text | Should -Match '\[ERROR\] The deletes in prod-skycraft-swc-rg were not attempted'
    }

    It 'lifts no lock at all when one of the groups cannot be read' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod); $script:Platform = (New-Lab13Lock -Group $script:Platform) } -Fail @{ "GET:$script:Platform" = -1 }
        (Invoke-Helper -Group $script:Prod, $script:Platform).Result | Should -Be @(1)
        $global:SkyCraftLockFake.ActionRan | Should -BeFalse
        $global:SkyCraftLockFake.Calls | Should -Not -Match '^(DELETE|PUT):'
    }

    It 'counts a context without a subscription as a failure and runs no delete' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) }
        $global:SkyCraftLockFake.NoContext = $true
        $run = Invoke-Helper -Group $script:Prod
        $run.Result | Should -Be @(1)
        $global:SkyCraftLockFake.ActionRan | Should -BeFalse
        $global:SkyCraftLockFake.Calls | Should -BeNullOrEmpty
    }

    It 'puts back the lock it lifted when the next one cannot be lifted, and runs no delete' {
        Reset-LockFake -Locks @{ $script:Platform = (New-Lab13Lock -Group $script:Platform); $script:Prod = (New-Lab13Lock -Group $script:Prod) } -Fail @{ "DELETE:$script:Prod" = -1 }
        $run = Invoke-Helper -Group $script:Platform, $script:Prod
        $run.Result | Should -Be @(1)
        $global:SkyCraftLockFake.ActionRan | Should -BeFalse
        $global:SkyCraftLockFake.Calls | Should -Contain 'PUT:platform-skycraft-swc-rg:lock-no-delete-platform'
        $global:SkyCraftLockFake.Locks.Keys | Should -Contain $script:Platform
        $global:SkyCraftLockFake.Locks.Keys | Should -Contain $script:Prod
        $run.Text | Should -Match "\[ERROR\] Could not lift Lab 1.3's lock 'lock-no-delete-prod'"
    }
}

Describe 'Invoke-LabWithoutLock - a lock it cannot put back (#372)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'says the group is unlocked and gives the command that recreates the lock' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) } -Fail @{ "PUT:$script:Prod" = -1 }
        $run = Invoke-Helper -Group $script:Prod
        $run.Result | Should -Be @(1)
        $global:SkyCraftLockFake.ActionRan | Should -BeTrue
        @($global:SkyCraftLockFake.Calls | Where-Object { $_ -like 'PUT:*' }).Count | Should -Be 3 -Because 'a restore is tried three times'
        $run.Text | Should -Match "\[ERROR\] Could not restore Lab 1.3's lock 'lock-no-delete-prod' on 'prod-skycraft-swc-rg'[^\r\n]*AuthorizationFailed"
        $run.Text | Should -Match "\[ERROR\] 'prod-skycraft-swc-rg' is UNLOCKED"
        $run.Text | Should -Match ([regex]::Escape("New-AzResourceLock -ResourceGroupName 'prod-skycraft-swc-rg' -LockName 'lock-no-delete-prod' -LockLevel CanNotDelete -LockNotes '$script:Notes' -Force"))
    }

    It 'gives the ARM request instead when the lock has owners, which New-AzResourceLock cannot set' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod -Owners @(@{ applicationId = 'app-1' })) } -Fail @{ "PUT:$script:Prod" = -1 }
        $run = Invoke-Helper -Group $script:Prod
        $run.Result | Should -Be @(1)
        $run.Text | Should -Match "Invoke-AzRestMethod -Method PUT -Path '/subscriptions/[^']+/locks/lock-no-delete-prod\?api-version=2020-05-01' -Payload '[^']*app-1"
    }

    It 'succeeds when a later attempt puts the lock back' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) } -Fail @{ "PUT:$script:Prod" = 1 }
        (Invoke-Helper -Group $script:Prod).Result | Should -Be @(0)
        $global:SkyCraftLockFake.Locks.Keys | Should -Contain $script:Prod
    }
}

Describe 'Invoke-LabWithoutLock - -WhatIf (#372)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'removes and restores nothing, and still runs the deletes so they can report' {
        Reset-LockFake -Locks @{ $script:Prod = (New-Lab13Lock -Group $script:Prod) }
        $run = Invoke-Helper -Group $script:Prod -DryRun
        $run.Result | Should -Be @(0)
        $global:SkyCraftLockFake.ActionRan | Should -BeTrue
        $global:SkyCraftLockFake.LocksDuringAction | Should -Contain $script:Prod
        $global:SkyCraftLockFake.Calls | Should -Not -Match '^(DELETE|PUT):'
        Should -Invoke -ModuleName LabCommon Start-Sleep -Times 0 -Exactly
    }
}

Describe 'Module 4-5 cleanups route their locked-group deletes through Invoke-LabWithoutLock (#372)' {

    # Labs 2.1-3.4 delete in the same groups and are owed the same change (#372); the course pins
    # them (#300), so they are not in this list yet.
    It '<Lab> passes -WhatIf through and adds the lock failures in a statement of their own' -ForEach @(
        @{ Lab = '4.1'; Path = 'module-4-storage/4.1-storage-accounts' }
        @{ Lab = '4.2'; Path = 'module-4-storage/4.2-blob-storage' }
        @{ Lab = '4.3'; Path = 'module-4-storage/4.3-azure-files' }
        @{ Lab = '4.4'; Path = 'module-4-storage/4.4-storage-security' }
        @{ Lab = '5.1'; Path = 'module-5-monitoring-maintenance/5.1-azure-monitor' }
        @{ Lab = '5.2'; Path = 'module-5-monitoring-maintenance/5.2-business-continuity' }
        @{ Lab = '5.3'; Path = 'module-5-monitoring-maintenance/5.3-network-monitoring' }
    ) {
        $file = Join-Path $PSScriptRoot '..' $Path 'scripts' 'Remove-LabResource.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty

        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-LabWithoutLock' }, $true))
        $calls.Count | Should -BeGreaterThan 0 -Because "Lab $Lab deletes in a group Lab 1.3 locks"
        foreach ($call in $calls) {
            $call.Extent.Text | Should -Match '-WhatIf:\$WhatIfPreference\b' -Because 'a module function does not see the script''s -WhatIf'

            # '$script:cleanupFailures += Invoke-LabWithoutLock ...' reads the count before -Action
            # raises it, and loses what -Action counted.
            $assignment = $call.Parent
            while ($assignment -and $assignment -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { $assignment = $assignment.Parent }
            $assignment | Should -Not -BeNullOrEmpty -Because 'the lock failures must be counted'
            $assignment.Operator | Should -Be 'Equals'
            $variable = $assignment.Left.VariablePath.UserPath
            $source = $ast.Extent.Text
            $source | Should -Match ('\$script:cleanupFailures \+= \$' + [regex]::Escape($variable) + '\b')
        }
    }

    # A delete outside the locked groups can still remove a child inside one: deleting Lab 5.3's
    # flow log (NetworkWatcherRG) deletes the lifecycle policy on the platform storage account.
    It 'Lab 5.3 deletes the flow log inside Invoke-LabWithoutLock' {
        $file = Join-Path $PSScriptRoot '..' 'module-5-monitoring-maintenance/5.3-network-monitoring' 'scripts' 'Remove-LabResource.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        $deletes = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Remove-AzNetworkWatcherFlowLog' }, $true))
        $deletes.Count | Should -BeGreaterThan 0
        foreach ($delete in $deletes) {
            $wrapper = $delete.Parent
            while ($wrapper -and -not ($wrapper -is [System.Management.Automation.Language.CommandAst] -and $wrapper.GetCommandName() -eq 'Invoke-LabWithoutLock')) { $wrapper = $wrapper.Parent }
            $wrapper | Should -Not -BeNullOrEmpty -Because 'the flow log delete removes a child in the platform group, which Lab 1.3 locks'
            $wrapper.Extent.Text | Should -Match 'platformRg'
        }
    }
}
