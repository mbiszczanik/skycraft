<#
.SYNOPSIS
    Pester 5 tests for the check, lookup, subscription and role-retry helpers of
    tools/LabCommon.psm1 (issues #301, #530, #290).

.DESCRIPTION
    Invoke-LabCheck counts passes, failures and skips and never throws on a failed check;
    Skip-LabCheck makes a check SKIPPED, which is neither a pass nor a failure;
    Get-LabResourceOrFail returns $null for an object that is absent and throws for a lookup that
    failed; Assert-LabSubscription compares ids; Invoke-LabRoleRetry waits for a new role and gives
    up after its timeout. Nothing here touches Azure.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\LabCommon-Check.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'LabCommon.psm1') -Force
}

Describe 'Invoke-LabCheck - counting' {

    BeforeEach { Reset-LabCheckCount }

    It 'counts a block that returns $true as passed' {
        $r = Invoke-LabCheck -Name 'ok' -Test { $true }
        $r.Outcome | Should -Be 'Passed'
        (Get-LabCheckCount).Passed | Should -Be 1
    }

    It 'counts $false, $null and no output as failed' {
        (Invoke-LabCheck -Name 'a' -Test { $false }).Outcome | Should -Be 'Failed'
        (Invoke-LabCheck -Name 'b' -Test { $null }).Outcome | Should -Be 'Failed'
        (Invoke-LabCheck -Name 'c' -Test { }).Outcome | Should -Be 'Failed'
        (Get-LabCheckCount).Failed | Should -Be 3
    }

    It 'counts an exception as failed, with its message, and does not throw' {
        { Invoke-LabCheck -Name 'boom' -Test { throw 'the lookup broke' } } | Should -Not -Throw
        $r = Invoke-LabCheck -Name 'boom' -Test { throw 'the lookup broke' }
        $r.Outcome | Should -Be 'Failed'
        $r.Detail | Should -Be 'the lookup broke'
    }

    It 'uses the last value the block writes' {
        (Invoke-LabCheck -Name 'noisy' -Test { 'chatter'; $true }).Outcome | Should -Be 'Passed'
    }

    It 'counts Skip-LabCheck as skipped, not as passed or failed, and keeps the reason' {
        $r = Invoke-LabCheck -Name 'needs a token' -Test { Skip-LabCheck -Reason 'no Log Analytics token' }
        $r.Outcome | Should -Be 'Skipped'
        $r.Detail | Should -Be 'no Log Analytics token'
        $count = Get-LabCheckCount
        $count.Skipped | Should -Be 1
        $count.Passed | Should -Be 0
        $count.Failed | Should -Be 0
    }

    It 'keeps counting after a failure' {
        Invoke-LabCheck -Name 'one' -Test { $false } | Out-Null
        Invoke-LabCheck -Name 'two' -Test { $true } | Out-Null
        $count = Get-LabCheckCount
        $count.Passed | Should -Be 1
        $count.Failed | Should -Be 1
    }

    It 'prints [PASS], [FAIL] and [SKIPPED] lines' {
        $lines = @(
            Invoke-LabCheck -Name 'p' -Test { $true } 6>&1
            Invoke-LabCheck -Name 'f' -Test { $false } 6>&1
            Invoke-LabCheck -Name 's' -Test { Skip-LabCheck -Reason 'why' } 6>&1
        ) | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" }
        ($lines -join "`n") | Should -Match '\[PASS\] p'
        ($lines -join "`n") | Should -Match '\[FAIL\] f'
        ($lines -join "`n") | Should -Match '\[SKIPPED\] s - why'
    }
}

Describe 'Get-LabResourceOrFail - absent is not failed' {

    It 'returns the object a successful lookup finds' {
        Get-LabResourceOrFail -Description 'a group' -Script { 'found' } | Should -Be 'found'
    }

    It 'returns $null when a successful lookup finds nothing' {
        Get-LabResourceOrFail -Description 'a group' -Script { $null } | Should -BeNullOrEmpty
    }

    It 'returns $null when the lookup reports <text>' -ForEach @(
        @{ text = 'ResourceGroupNotFound'; message = "ResourceGroupNotFound: the resource group could not be found." }
        @{ text = 'ResourceNotFound'; message = 'ResourceNotFound: the resource was not found' }
        @{ text = 'HTTP 404'; message = 'Response status code 404' }
    ) {
        Get-LabResourceOrFail -Description 'a group' -Script ([scriptblock]::Create("throw '$message'")) | Should -BeNullOrEmpty
    }

    It 'throws, naming what was looked up, when the lookup failed with <text>' -ForEach @(
        @{ text = '403'; message = 'AuthorizationFailed: the client does not have authorization' }
        @{ text = 'throttling'; message = 'TooManyRequests: slow down' }
        @{ text = 'an expired token'; message = 'ExpiredAuthenticationToken: the token expired' }
    ) {
        { Get-LabResourceOrFail -Description 'resource group dev' -Script ([scriptblock]::Create("throw '$message'")) } |
            Should -Throw -ExpectedMessage '*Could not look up resource group dev*'
    }
}

Describe 'Assert-LabSubscription' {

    It 'passes when the context is on the expected subscription' {
        { Assert-LabSubscription -SubscriptionId 'sub-1' -ContextProbe { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'sub-1'; Name = 'x' } } } } |
            Should -Not -Throw
    }

    It 'throws when the context is on another subscription, even one with the same name' {
        { Assert-LabSubscription -SubscriptionId 'sub-1' -ContextProbe { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'sub-2'; Name = 'same' } } } } |
            Should -Throw -ExpectedMessage '*sub-2*not on sub-1*'
    }

    It 'throws when there is no context' {
        { Assert-LabSubscription -SubscriptionId 'sub-1' -ContextProbe { $null } } | Should -Throw -ExpectedMessage '*no Azure context*'
    }
}

Describe 'Invoke-LabRoleRetry' {

    BeforeEach {
        $script:Slept = [System.Collections.Generic.List[int]]::new()
        $script:Sleep = { param($Seconds) $script:Slept.Add($Seconds) }
        $script:Calls = 0
    }

    It 'returns at once, without waiting, when the first call works' {
        $r = Invoke-LabRoleRetry -Description 'x' -Sleep $script:Sleep -Script { $script:Calls++; 'done' }
        $r | Should -Be 'done'
        $script:Slept.Count | Should -Be 0
    }

    It 'waits and retries while the role has not taken effect, then returns' {
        $r = Invoke-LabRoleRetry -Description 'blob backup' -DelaySeconds 5 -Sleep $script:Sleep -Script {
            $script:Calls++
            if ($script:Calls -lt 3) { throw 'AuthorizationFailed: the client does not have authorization' }
            'ok'
        }
        $r | Should -Be 'ok'
        $script:Calls | Should -Be 3
        $script:Slept.Count | Should -Be 2
        $script:Slept[0] | Should -Be 5
    }

    It 'throws the last error after the timeout' {
        { Invoke-LabRoleRetry -Description 'x' -TimeoutSeconds 30 -DelaySeconds 10 -Sleep $script:Sleep -Script { $script:Calls++; throw 'PrincipalNotFound: not there yet' } } |
            Should -Throw -ExpectedMessage '*PrincipalNotFound*'
        $script:Calls | Should -Be 4
        $script:Slept.Count | Should -Be 3
    }

    It 'throws at once for an error that is not a missing role' {
        { Invoke-LabRoleRetry -Description 'x' -Sleep $script:Sleep -Script { $script:Calls++; throw 'InvalidTemplate: bad' } } |
            Should -Throw -ExpectedMessage '*InvalidTemplate*'
        $script:Calls | Should -Be 1
        $script:Slept.Count | Should -Be 0
    }
}

Describe 'Get-LabCycleSkippedCheck - the cycle reads what a validator skipped' {

    BeforeAll { Import-Module (Join-Path $script:RepoRoot 'tools' 'LabCycle.psm1') -Force }

    It 'reads both output forms and nothing else' {
        $text = "  [PASS] a`n  [SKIPPED] Heartbeat - no token`n  Testing: Query... SKIPPED (Forbidden)`n  Testing: other... PASS`n  [FAIL] b - x`n"
        $found = @(Get-LabCycleSkippedCheck -Text $text)
        $found.Count | Should -Be 2
        $found[0].Name | Should -Be 'Heartbeat'
        $found[0].Reason | Should -Be 'no token'
        $found[1].Name | Should -Be 'Query'
        $found[1].Reason | Should -Be 'Forbidden'
    }

    It 'returns nothing for empty or null output' {
        @(Get-LabCycleSkippedCheck -Text '').Count | Should -Be 0
        @(Get-LabCycleSkippedCheck -Text $null).Count | Should -Be 0
    }
}
