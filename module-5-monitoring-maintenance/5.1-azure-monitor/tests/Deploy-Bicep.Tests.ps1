<#
.SYNOPSIS
    Pester 5 tests: Lab 5.1 Deploy-Bicep.ps1 retries a Failed DCR deployment (#473).

.DESCRIPTION
    A fresh workspace needs about a minute before its tables exist, so the DCR deployment can end
    Failed with InvalidPayload. The retry loop must cover a Failed deployment the cmdlet returns
    without throwing, not only a thrown error.

    Two kinds of check. Static checks on the script text pin the shape of the loop. Behavioural
    checks run the real script in a child process with its Az commands replaced by a stub
    (tests/Support/LabScriptStub.psm1), once per way the deployment can end, and read the exit
    code, the [RETRY] lines and how many times the deployment ran. The returned-Failed path prints
    its own line ("Deployment returned Failed"), so a log shows which path fired. No subscription
    is used.

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #473
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $script:Text = Get-Content -LiteralPath $script:ScriptPath -Raw
    $script:StubModuleName = 'SkyCraftLab51DeployStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.Storage', 'Az.Monitor')
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResourceGroup'
        'Get-AzVM'
        'Get-AzStorageAccount'
        'New-AzSubscriptionDeployment'
        'Get-AzDeploymentOperation'
        'Get-AzDataCollectionRuleAssociation'
        'New-AzDataCollectionRuleAssociation'
        'Start-Sleep'
    )

    # How the DCR deployment ends, from SKYCRAFT_STUB_DEPLOY; every call is logged to the file in
    # SKYCRAFT_STUB_STATE ('deploy' per deployment, 'sleep <seconds>' per wait).
    #   thrown-then-ok   the first call throws InvalidOutputTable, the second succeeds
    #   failed-then-ok   the first two calls return a Failed deployment whose operation error is
    #                    InvalidPayload, the third succeeds
    #   failed-other     one call returns Failed with an error that is not a table-not-ready error
    #   failed-always    every call returns Failed with InvalidOutputTable
    $script:StubBody = @'
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub@example.invalid' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}
function Get-AzResourceGroup {
    [CmdletBinding()]
    param($Name)
    [pscustomobject]@{ ResourceGroupName = $Name }
}
function Get-AzVM {
    [CmdletBinding()]
    param($Name, $ResourceGroupName)
    [pscustomobject]@{ Name = $Name; Id = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$Name" }
}
function Get-AzStorageAccount {
    [CmdletBinding()]
    param($ResourceGroupName)
    [pscustomobject]@{ StorageAccountName = 'stubsa'; Id = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/stubsa" }
}
function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds)
    Add-Content -LiteralPath $env:SKYCRAFT_STUB_STATE -Value "sleep $Seconds"
}
function New-AzSubscriptionDeployment {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Add-Content -LiteralPath $env:SKYCRAFT_STUB_STATE -Value 'deploy'
    $call = @(Get-Content -LiteralPath $env:SKYCRAFT_STUB_STATE | Where-Object { $_ -eq 'deploy' }).Count
    $failed = [pscustomobject]@{ ProvisioningState = 'Failed'; Outputs = $null }
    switch ($env:SKYCRAFT_STUB_DEPLOY) {
        'thrown-then-ok' { if ($call -eq 1) { throw 'InvalidOutputTable: the table does not exist yet' } }
        'failed-then-ok' { if ($call -le 2) { return $failed } }
        'failed-other'   { return $failed }
        'failed-always'  { return $failed }
    }
    [pscustomobject]@{ ProvisioningState = 'Succeeded'; Outputs = @{} }
}
function Get-AzDeploymentOperation {
    [CmdletBinding()]
    param($DeploymentName)
    $text = switch ($env:SKYCRAFT_STUB_DEPLOY) {
        'failed-other'  { 'QuotaExceeded: the subscription is out of quota' }
        'failed-always' { 'InvalidOutputTable: table Perf is not available for destination' }
        default         { 'InvalidPayload: Data collection rule is invalid' }
    }
    [pscustomobject]@{ StatusMessage = $text }
}
function Get-AzDataCollectionRuleAssociation {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
}
function New-AzDataCollectionRuleAssociation {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
}
'@

    $script:Stub = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules

    function Invoke-DeployScript {
        param([ValidateSet('thrown-then-ok', 'failed-then-ok', 'failed-other', 'failed-always')][string]$Deploy)
        $state = Join-Path $script:Stub.Directory "state-$Deploy.log"
        Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath `
            -ArgumentList '-OpsEmail', 'ops@example.invalid', '-Force' -Environment @{
            SKYCRAFT_STUB_DEPLOY = $Deploy
            SKYCRAFT_STUB_STATE  = $state
        }
        $log = if (Test-Path -LiteralPath $state) { @(Get-Content -LiteralPath $state) } else { @() }
        [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Deploys  = @($log | Where-Object { $_ -eq 'deploy' }).Count
            Sleeps   = @($log | Where-Object { $_ -like 'sleep *' })
        }
    }

    $script:Thrown      = Invoke-DeployScript -Deploy 'thrown-then-ok'
    $script:ReturnedOk  = Invoke-DeployScript -Deploy 'failed-then-ok'
    $script:Other       = Invoke-DeployScript -Deploy 'failed-other'
    $script:Always      = Invoke-DeployScript -Deploy 'failed-always'
}

AfterAll {
    if ($script:Stub -and $script:Stub.Directory) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.1 Deploy-Bicep.ps1 retry - script text' {
    It 'retries a returned Failed deployment whose operation error is a table-not-ready error' {
        $script:Text | Should -Match "ProvisioningState -eq 'Failed' -and \`$attempt -lt \`$maxAttempts"
        $script:Text | Should -Match 'Get-AzDeploymentOperation -DeploymentName'
        $script:Text | Should -Match "-match 'InvalidOutputTable\|not available for destination\|InvalidPayload'"
    }

    It 'uses the cmdlet, not its alias, so a test stub can replace it' {
        $script:Text | Should -Not -Match 'Get-AzSubscriptionDeploymentOperation'
    }

    It 'still reports a Failed state that is not a table-not-ready error' {
        $script:Text | Should -Match "Deployment finished with state: \`$\(\`$deployment.ProvisioningState\)"
    }
}

Describe 'Lab 5.1 Deploy-Bicep.ps1 retry - the script run against a stub (#473)' {

    It 'never reaches a real subscription' {
        foreach ($run in $script:Thrown, $script:ReturnedOk, $script:Other, $script:Always) {
            $run.Refused | Should -BeFalse -Because "the harness must not fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'retries a thrown table-not-ready error once and succeeds' {
        $script:Thrown.ExitCode | Should -Be 0 -Because "output was:`n$($script:Thrown.Output)"
        $script:Thrown.Deploys | Should -Be 2
        $script:Thrown.Output | Should -Match '\[RETRY 1/3\] Workspace tables not ready yet'
        $script:Thrown.Output | Should -Not -Match 'returned Failed'
    }

    It 'retries a returned Failed deployment twice and succeeds, and the log names that path' {
        $run = $script:ReturnedOk
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Deploys | Should -Be 3
        $run.Sleeps.Count | Should -Be 2
        $run.Output | Should -Match '\[RETRY 1/3\] Deployment returned Failed, workspace tables not ready yet'
        $run.Output | Should -Match '\[RETRY 2/3\] Deployment returned Failed'
        $run.Output | Should -Not -Match '\[RETRY 3/3\]'
        $run.Output | Should -Match 'Deployment succeeded'
    }

    It 'does not retry a Failed deployment whose error is not a table-not-ready error, and exits 1' {
        $run = $script:Other
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Deploys | Should -Be 1
        $run.Sleeps.Count | Should -Be 0
        $run.Output | Should -Not -Match '\[RETRY'
        $run.Output | Should -Match 'Deployment finished with state: Failed'
    }

    It 'gives up after three retries of a deployment that keeps ending Failed, and exits 1' {
        $run = $script:Always
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Deploys | Should -Be 4
        $run.Sleeps.Count | Should -Be 3
        $run.Output | Should -Match '\[RETRY 3/3\] Deployment returned Failed'
        $run.Output | Should -Match 'Deployment finished with state: Failed'
        $run.Output | Should -Not -Match 'Deployment succeeded'
    }
}
