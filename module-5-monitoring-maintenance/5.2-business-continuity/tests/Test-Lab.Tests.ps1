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

    Only the Backup vault is modelled; every other lookup returns nothing, so the other checks
    fail and are not asserted here. No subscription is needed, and none is used:
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

# Everything else in the lab is absent: these return nothing.
function Get-AzRecoveryServicesVault { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
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
function Get-AzDataProtectionBackupInstance { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzStorageAccount { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzDiagnosticSetting { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('Off', 'AlwaysOn', 'On')]
            [string]$SoftDelete
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_BVSOFTDELETE = $SoftDelete
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
    $script:AllRuns       = @($script:ScriptedVault, $script:PortalVault, $script:OnVault)
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
