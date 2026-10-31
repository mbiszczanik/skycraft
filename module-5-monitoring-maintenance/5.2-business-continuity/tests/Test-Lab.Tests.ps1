<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.2 validator's Backup vault soft delete check and what it says.

.DESCRIPTION
    Regression cover for issue #355 (decision on #366). Test-Lab.ps1 requires the Backup vault's
    soft delete to be Off, a lab-friction override the Bicep sets. A Backup vault created in the
    Portal is AlwaysOn ("secure by default", in preview for Backup vaults in Sweden Central), and
    AlwaysOn cannot be turned off, so the lab creates the vault with Az PowerShell or the Bicep.
    The check stays strict while the option exists, and says what to do when it fails. These
    tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands
    it calls, and assert that:

      1. A vault with soft delete Off passes the check.
      2. An AlwaysOn vault fails it, and the line says the state cannot be turned off and that
         the vault has to be recreated with Az PowerShell or the Bicep, naming both.
      3. A vault with soft delete On fails it, and the line names the state and the command that
         turns it off.
      4. When ARM refuses the raw reads (AuthorizationFailed), the RSV tag and soft delete, Backup
         vault and blob policy checks fail and print that error, and the script exits 1 (#452).

    Only the Backup vault, and in run 4 the Recovery Services vault, is modelled; every other
    lookup returns nothing, so the other checks fail and are not asserted here. No subscription is needed, and none is used:
    tests/Support/LabScriptStub.psm1 (issue #112) imports the real modules first, the stub last,
    and aborts the child with exit 99 unless every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #355
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab52ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Storage', 'Az.Compute')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzRecoveryServicesVault'
        'Get-AzRecoveryServicesBackupProperty'
        'Get-AzRecoveryServicesVaultProperty'
        'Get-AzRecoveryServicesBackupProtectionPolicy'
        'Get-AzRecoveryServicesBackupItem'
        'Get-AzRecoveryServicesBackupJob'
        'Get-AzRecoveryServicesBackupJobDetail'
        'Get-AzResource'
        'Get-AzResourceGroup'
        'Get-AzResourceLock'
        'Get-AzVM'
        'Get-AzDataProtectionBackupVault'
        'Get-AzDataProtectionBackupPolicy'
        'Get-AzDataProtectionBackupInstance'
        'Get-AzStorageAccount'
        'Get-AzDiagnosticSetting'
    )

    #   SKYCRAFT_STUB_BVSOFTDELETE   the Backup vault's softDeleteSettings.state: 'Off' (Az
    #                                PowerShell or Bicep), 'AlwaysOn' (the Portal), or 'On'
    #   SKYCRAFT_STUB_ARM            'denied': the Recovery Services vault exists and every
    #                                Get-AzResource read throws AuthorizationFailed
    $script:StubBody = @'
$script:BvId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.DataProtection/backupVaults/platform-skycraft-swc-bv'

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Get-AzDataProtectionBackupVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VaultName, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = $VaultName; Id = $script:BvId; Location = 'swedencentral' }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$ExpandProperties, [string]$ApiVersion, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ARM -eq 'denied') {
        throw "AuthorizationFailed: The client does not have authorization to perform action 'read' over scope '$ResourceId'."
    }
    if ($ResourceId -ne $script:BvId) { return }
    [pscustomobject]@{
        ResourceId = $ResourceId
        Identity   = [pscustomobject]@{ Type = 'SystemAssigned'; PrincipalId = '11111111-1111-1111-1111-111111111111' }
        Tags       = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' }
        Properties = [pscustomobject]@{
            storageSettings  = @([pscustomobject]@{ datastoreType = 'VaultStore'; type = 'LocallyRedundant' })
            securitySettings = [pscustomobject]@{
                softDeleteSettings = [pscustomobject]@{ state = $env:SKYCRAFT_STUB_BVSOFTDELETE; retentionDurationInDays = 14 }
            }
        }
    }
}

function Get-AzRecoveryServicesVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ARM -ne 'denied') { return }
    [pscustomobject]@{
        Name     = $Name
        ID       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$Name"
        Location = 'swedencentral'
    }
}

# Everything else in the lab is absent: these return nothing.
function Get-AzRecoveryServicesBackupProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesVaultProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupProtectionPolicy { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupItem { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJob { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJobDetail { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzResourceGroup { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzResourceLock { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzVM { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzDataProtectionBackupPolicy { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = $Name; Id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa' }
}
# SKYCRAFT_STUB_BLOBINSTANCE: 'ok', 'protectionerror', 'provisioningfailed', 'nostate' or 'none' (no instance);
# 'configuring' / 'creating' report an in-progress state on the 2nd and 3rd call (the 1st is the
# exists check) and settle on the 4th; 'stuck' / 'failedconfiguring' never settle.
$script:InstanceCalls = 0
function Get-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VaultName, [Parameter(ValueFromRemainingArguments)]$Rest)
    $mode = $env:SKYCRAFT_STUB_BLOBINSTANCE
    if (-not $mode -or $mode -eq 'none') { return }
    $script:InstanceCalls++
    $inProgress = $script:InstanceCalls -ge 2 -and $script:InstanceCalls -le 3
    $protectionState = switch ($mode) {
        'protectionerror' { 'ProtectionError' }
        'nostate' { $null }
        'configuring' { if ($inProgress) { 'ConfiguringProtection' } else { 'ProtectionConfigured' } }
        'stuck' { if ($script:InstanceCalls -ge 2) { 'ConfiguringProtection' } else { 'ProtectionConfigured' } }
        'failedconfiguring' { if ($script:InstanceCalls -ge 2) { 'ConfiguringProtection' } else { 'ProtectionConfigured' } }
        default { 'ProtectionConfigured' }
    }
    $provisioningState = switch ($mode) {
        'provisioningfailed' { 'Failed' }
        'nostate' { $null }
        'creating' { if ($inProgress) { 'Creating' } else { 'Succeeded' } }
        'failedconfiguring' { if ($script:InstanceCalls -ge 3) { 'Failed' } else { 'Succeeded' } }
        default { 'Succeeded' }
    }
    [pscustomobject]@{
        Name     = 'prodskycraftswcsa-instance'
        Property = [pscustomobject]@{
            DataSourceInfo         = [pscustomobject]@{ ResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa' }
            CurrentProtectionState = $protectionState
            ProvisioningState      = $provisioningState
        }
    }
}
function Get-AzDiagnosticSetting { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('Off', 'AlwaysOn', 'On')]
            [string]$SoftDelete,
            [ValidateSet('', 'denied')]
            [string]$Arm = '',
            [string]$BlobInstance = 'none',
            [string[]]$ArgumentList = @('-ProtectionTimeoutSeconds', '60', '-ProtectionPollSeconds', '0')
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_BVSOFTDELETE = $SoftDelete
            SKYCRAFT_STUB_ARM          = $Arm
            SKYCRAFT_STUB_BLOBINSTANCE = $BlobInstance
        }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            # The one line under test.
            Line     = ($run.Output -split '\r?\n' | Where-Object { $_ -match 'Testing: Backup Vault soft delete' }) -join "`n"
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:ScriptedVault = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off'
    $script:PortalVault   = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'AlwaysOn'
    $script:OnVault       = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'On'
    $script:Denied        = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -Arm 'denied'
    $script:BlobOk        = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'ok'
    $script:BlobProtErr   = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'protectionerror'
    $script:BlobProvFail  = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'provisioningfailed'
    $script:BlobNoState   = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'nostate'
    $script:BlobNone      = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'none'
    $script:BlobConfiguring = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'configuring'
    $script:BlobCreating  = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'creating'
    $script:BlobStuck     = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'stuck' `
        -ArgumentList @('-ProtectionTimeoutSeconds', '2', '-ProtectionPollSeconds', '1')
    # A long window: a terminal state that waited would run to the timeout.
    $script:BlobFailedWhileConfiguring = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'failedconfiguring' `
        -ArgumentList @('-ProtectionTimeoutSeconds', '60', '-ProtectionPollSeconds', '1')
    $script:BlobFailedAtOnce = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -BlobInstance 'provisioningfailed' `
        -ArgumentList @('-ProtectionTimeoutSeconds', '60', '-ProtectionPollSeconds', '1')
    $script:AllRuns       = @($script:ScriptedVault, $script:PortalVault, $script:OnVault, $script:Denied, $script:BlobOk,
        $script:BlobProtErr, $script:BlobProvFail, $script:BlobNoState, $script:BlobNone,
        $script:BlobConfiguring, $script:BlobCreating, $script:BlobStuck, $script:BlobFailedWhileConfiguring, $script:BlobFailedAtOnce)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'stubs every Az command the script calls' {
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $called = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^\w+-Az' } | Sort-Object -Unique
        @($called | Where-Object { $_ -notin $script:StubCommands }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - Backup vault soft delete (#355, decision on #366)' {

    It 'passes a vault with soft delete Off' {
        $script:ScriptedVault.Line | Should -Match 'Testing: Backup Vault soft delete is Off \(lab-friction override, docs/bicep-standards\.md section 4\.5\)\.\.\. PASS$' -Because "output was:`n$($script:ScriptedVault.Output)"
    }

    It 'fails a Portal-built AlwaysOn vault and says it has to be recreated with soft delete Off' {
        $line = $script:PortalVault.Line
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'state is AlwaysOn, which cannot be turned off: a vault created in the Portal is AlwaysOn'
        $line | Should -Match 'delete the vault and recreate it with soft delete Off, with New-AzDataProtectionBackupVault -SoftDeleteState Off \(Az PowerShell\) or scripts/Deploy-Bicep\.ps1 \(the Bicep\)'
    }

    It 'fails a vault with soft delete On and names the command that turns it off' {
        $line = $script:OnVault.Line
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:OnVault.Output)"
        $line | Should -Match "state is 'On' - set it to Off: Update-AzDataProtectionBackupVault -SoftDeleteState Off"
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - a raw ARM read that fails is not a missing resource (#452)' {

    It 'fails <label> with the lookup error' -ForEach @(
        @{ label = "RSV tag 'Project'"; pattern = "Testing: RSV tag 'Project'" }
        @{ label = 'RSV soft delete'; pattern = 'Testing: RSV soft delete' }
        @{ label = 'Backup Vault storage type'; pattern = 'Testing: Backup Vault storage type' }
        @{ label = 'Backup Vault soft delete'; pattern = 'Testing: Backup Vault soft delete' }
        @{ label = 'blob policy datasource type'; pattern = 'Testing: Blob policy datasource type' }
    ) {
        $line = ($script:Denied.Output -split '\r?\n' | Where-Object { $_ -match $pattern }) -join "`n"
        $line | Should -Match 'FAIL \(.*AuthorizationFailed' -Because "output was:`n$($script:Denied.Output)"
    }

    It 'exits 1' {
        $script:Denied.ExitCode | Should -Be 1
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - blob backup instance protection (#371)' {

    It 'passes an instance with protection configured and provisioning Succeeded' {
        $script:BlobOk.Output | Should -Match 'Testing: Blob backup instance exists for[^\r\n]*PASS'
        $script:BlobOk.Output | Should -Match 'Testing: Blob backup instance protection is configured and provisioned\.\.\. PASS'
    }

    It 'fails an instance in protection state ProtectionError, and names the state' {
        $script:BlobProtErr.ExitCode | Should -Be 1 -Because "output was:`n$($script:BlobProtErr.Output)"
        $script:BlobProtErr.Output | Should -Match "Blob backup instance exists for[^\r\n]*PASS"
        $script:BlobProtErr.Output | Should -Match "protection state 'ProtectionError', provisioning state 'Succeeded'[^\r\n]*FAIL"
    }

    It 'fails an instance whose provisioning state is Failed' {
        $script:BlobProvFail.Output | Should -Match "protection state 'ProtectionConfigured', provisioning state 'Failed'[^\r\n]*FAIL"
    }

    It 'fails an instance that reports no state at all' {
        $script:BlobNoState.Output | Should -Match "protection state '', provisioning state ''[^\r\n]*FAIL"
    }

    It 'fails the protection check when there is no instance' {
        $script:BlobNone.Output | Should -Match 'Blob backup instance protection is configured and provisioned\.\.\. FAIL'
    }

    It 'retries an instance still in protection state ConfiguringProtection, with progress lines, and passes once it settles' {
        $out = $script:BlobConfiguring.Output
        $out | Should -Match "protection state 'ConfiguringProtection', provisioning state 'Succeeded'; checking again"
        $out | Should -Match 'Blob backup instance protection is configured and provisioned[\s\S]*PASS'
        $out | Should -Not -Match 'protection is configured and provisioned[^\r\n]*FAIL'
    }

    It 'retries an instance whose provisioning state is Creating, and passes once it settles' {
        $out = $script:BlobCreating.Output
        $out | Should -Match "provisioning state 'Creating'; checking again"
        $out | Should -Match 'Blob backup instance protection is configured and provisioned[\s\S]*PASS'
    }

    It 'fails an instance that never leaves ConfiguringProtection, once the time is up, naming the state' {
        $script:BlobStuck.ExitCode | Should -Be 1 -Because "output was:`n$($script:BlobStuck.Output)"
        $script:BlobStuck.Output | Should -Match "protection state 'ConfiguringProtection', provisioning state 'Succeeded'; expected ProtectionConfigured and Succeeded[^\r\n]*FAIL"
    }

    It 'stops waiting at once when a configuring instance turns Failed' {
        $out = $script:BlobFailedWhileConfiguring.Output
        $out | Should -Match "protection state 'ConfiguringProtection', provisioning state 'Failed'; expected[^\r\n]*FAIL"
        @([regex]::Matches($out, 'checking again')).Count | Should -Be 1 -Because "only the first poll was in progress:`n$out"
    }

    It 'does not wait for a terminal Failed state' {
        $out = $script:BlobFailedAtOnce.Output
        $out | Should -Match "provisioning state 'Failed'[^\r\n]*FAIL"
        $out | Should -Not -Match 'checking again'
    }
}
