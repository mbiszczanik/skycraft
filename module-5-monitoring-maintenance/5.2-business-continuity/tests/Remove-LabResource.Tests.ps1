<#
.SYNOPSIS
    Pester 5 tests for the Lab 5.2 cleanup script's failure reporting and exit code.

.DESCRIPTION
    Regression cover for issue #105. The script used to swallow every delete failure into a
    [WARNING] and always exit 0, so an automated cycle could not tell a failed teardown from a
    clean one. These tests run the real Remove-LabResource.ps1 in a child pwsh process against a
    generated stub module, and assert the observable contract:

      1. A clean run exits 0; a run with a stuck resource exits 1 - asserted on the exit code,
         not on the printed message, because printing the guard and actually returning it to the
         caller are two different things (see issue #104).

         Scope limit: the child is launched with -Command, so these tests prove the failure
         counter reaches `exit`, not that `pwsh -File` carries the code out of the process.
         PowerShell 7 drops it there when the script declares #Requires -Modules for a module it
         has to auto-import, which is why the script pairs every non-zero exit with
         $Host.SetShouldExit - that half of the contract is issue #104's guard, enforced
         repo-wide by tests/Exit-Code-Propagation.Tests.ps1.
      2. Failures do not stop the run: later steps still execute.
      3. The Recovery Services Vault failure hint names the tooling requirement first.
      4. The orphaned restore point collection and its emptied AzureBackupRG_* group are removed.
      5. A stale Az.RecoveryServices is diagnosed before the delete is attempted.

    No Azure connection is needed, and none is used. The stubs are imported explicitly rather
    than placed on PSModulePath: pwsh prepends the user and shared module directories to any
    inherited PSModulePath, so a real Az installation would always win command resolution and
    the child would run the teardown against the live subscription. Importing a module whose
    exported functions carry the Az command names shadows the real cmdlets instead (functions
    take precedence over cmdlets), and the child aborts with exit 99 if that shadowing is not in
    effect - the tests fail rather than touching real resources.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftAzStub'

    # Exported explicitly: a manifest with FunctionsToExport = '*' leaves the export list to the
    # module analyser, which infers it with a lightweight scan and can stop partway through.
    $script:StubCommands = @(
        'Get-Module'
        'Get-AzContext'
        'Get-AzDataProtectionBackupVault'
        'Get-AzDataProtectionBackupInstance'
        'Remove-AzDataProtectionBackupInstance'
        'Remove-AzDataProtectionBackupVault'
        'Get-AzStorageAccount'
        'Get-AzRoleAssignment'
        'Remove-AzRoleAssignment'
        'Get-AzRecoveryServicesVault'
        'Get-AzRecoveryServicesBackupItem'
        'Disable-AzRecoveryServicesBackupProtection'
        'Remove-AzRecoveryServicesVault'
        'Get-AzResourceGroup'
        'Get-AzResource'
        'Remove-AzResource'
        'Remove-AzResourceGroup'
    )

    # Every Az command the script calls, implemented as a stub that records its own invocation
    # and optionally throws. Behaviour is driven by environment variables so one generated
    # module serves every scenario.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubCalled {
    param([string]$Name)
    if (-not $script:LogPath -or -not (Test-Path -LiteralPath $script:LogPath)) { return $false }
    return @(Get-Content -LiteralPath $script:LogPath) -contains $Name
}

function Invoke-StubGate {
    param([string]$Name)
    Write-StubCall -Name $Name
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Name) { throw "stub failure: $Name" }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

# The script reads the installed Az.RecoveryServices version through Get-Module -ListAvailable.
# Shadow just that lookup so the version branch can be exercised deterministically; every other
# call is delegated to the real cmdlet.
function Get-Module {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string[]]$Name,
        [switch]$ListAvailable,
        [switch]$All
    )
    if ($ListAvailable -and $Name -contains 'Az.RecoveryServices') {
        return [pscustomobject]@{
            Name    = 'Az.RecoveryServices'
            Version = [version]$env:SKYCRAFT_STUB_RSVERSION
        }
    }
    Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Name = 'stub-context' }
}

function Get-AzDataProtectionBackupVault {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = $VaultName; IdentityPrincipalId = '11111111-1111-1111-1111-111111111111' }
}

function Get-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'prodskycraftswcsa-blob-instance' }
}

function Remove-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName, $Name)
    Invoke-StubGate -Name 'Remove-AzDataProtectionBackupInstance'
}

function Remove-AzDataProtectionBackupVault {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName)
    Invoke-StubGate -Name 'Remove-AzDataProtectionBackupVault'
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param($ResourceGroupName, $Name)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Id = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$Name" }
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param($ObjectId, $RoleDefinitionId, $Scope)
    [pscustomobject]@{ RoleDefinitionId = $RoleDefinitionId }
}

function Remove-AzRoleAssignment {
    [CmdletBinding()]
    param($ObjectId, $RoleDefinitionId, $Scope)
    Invoke-StubGate -Name 'Remove-AzRoleAssignment'
}

function Get-AzRecoveryServicesVault {
    [CmdletBinding()]
    param($ResourceGroupName, $Name)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = $Name; ID = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$Name" }
}

function Get-AzRecoveryServicesBackupItem {
    [CmdletBinding()]
    param($VaultId, $BackupManagementType, $WorkloadType)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{
        Name          = 'VM;iaasvmcontainerv2;dev-skycraft-swc-rg;dev-skycraft-swc-auth-vm'
        ContainerName = 'iaasvmcontainerv2;dev-skycraft-swc-rg;dev-skycraft-swc-auth-vm'
        FriendlyName  = 'dev-skycraft-swc-auth-vm'
    }
}

function Disable-AzRecoveryServicesBackupProtection {
    [CmdletBinding()]
    param($Item, $VaultId, [switch]$RemoveRecoveryPoints, [switch]$Force)
    Invoke-StubGate -Name 'Disable-AzRecoveryServicesBackupProtection'
}

function Remove-AzRecoveryServicesVault {
    [CmdletBinding()]
    param($Vault)
    Invoke-StubGate -Name 'Remove-AzRecoveryServicesVault'
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param($Name)
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ ResourceGroupName = 'AzureBackupRG_swedencentral_1'; Location = 'swedencentral' }
    [pscustomobject]@{ ResourceGroupName = 'platform-skycraft-swc-rg';      Location = 'swedencentral' }
}

function Get-AzResource {
    [CmdletBinding()]
    param($ResourceGroupName, $ResourceType)
    # Once the collection has been deleted the group reads back empty, which is what lets the
    # script decide the AzureBackupRG_* group is safe to remove.
    if (Test-StubCalled -Name 'Remove-AzResource') { return }
    if ($ResourceGroupName -ne 'AzureBackupRG_swedencentral_1') { return }
    [pscustomobject]@{
        Name         = 'AzureBackup_dev-skycraft-swc-auth-vm_7702140526018345310'
        ResourceType = 'Microsoft.Compute/restorePointCollections'
        ResourceId   = '/subscriptions/0/resourceGroups/AzureBackupRG_swedencentral_1/providers/Microsoft.Compute/restorePointCollections/AzureBackup_dev-skycraft-swc-auth-vm_7702140526018345310'
    }
}

function Remove-AzResource {
    [CmdletBinding()]
    param($ResourceId, [switch]$Force)
    Invoke-StubGate -Name 'Remove-AzResource'
}

function Remove-AzResourceGroup {
    [CmdletBinding()]
    param($Name, [switch]$Force)
    Invoke-StubGate -Name 'Remove-AzResourceGroup'
}
'@

    # Writes the stub module to a throwaway directory and returns its manifest path. Alongside it,
    # empty Az.* modules are written to a 'modules' subdirectory that is added to PSModulePath:
    # they exist only so the script's #Requires -Modules line is satisfied on a runner with no Az
    # installed (CI does not install it). They never win command resolution - the explicitly
    # imported stub does that - so behaviour is the same with or without a real Az.
    function Initialize-StubModule {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-52-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir "$script:StubModuleName.psm1") -Value $script:StubBody -Encoding utf8
        $manifest = Join-Path $dir "$script:StubModuleName.psd1"
        New-ModuleManifest -Path $manifest `
            -RootModule "$script:StubModuleName.psm1" `
            -ModuleVersion '1.0.0' `
            -FunctionsToExport $script:StubCommands

        foreach ($required in 'Az.Accounts', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Resources', 'Az.Storage') {
            $requiredDir = Join-Path $dir 'modules' $required '1.0.0'
            New-Item -ItemType Directory -Path $requiredDir -Force | Out-Null
            New-ModuleManifest -Path (Join-Path $requiredDir "$required.psd1") `
                -ModuleVersion '1.0.0' `
                -FunctionsToExport @()
        }
        return $manifest
    }

    # Runs the real script in a child process with the stubs shadowing the Az cmdlets, and
    # returns the exit code it hands back to the caller.
    function Invoke-CleanupScript {
        param(
            [string]$Manifest,
            [string[]]$Fail = @(),
            [string]$RecoveryServicesVersion = '7.7.1',
            [switch]$Empty
        )

        $logPath = Join-Path (Split-Path -Parent $Manifest) 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        # The real Az modules are imported first, on purpose. The script's #Requires -Modules line
        # imports whatever is installed, and Az.DataProtection is autorest-generated, so it
        # exports *functions* - which would shadow same-named stub functions imported earlier
        # (the cmdlet-based modules would not). Loading them up front and importing the stub last
        # keeps the stub on top of both kinds.
        #
        # The child then aborts with 99 unless every stubbed command resolves to the stub module,
        # so a broken harness can never fall through and run a real teardown.
        $required = "'" + (@('Az.Accounts', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Resources', 'Az.Storage') -join "','") + "'"
        $shadowed = "'" + ($script:StubCommands -join "','") + "'"
        $childCommand = @"
foreach (`$m in @($required)) { Import-Module `$m -ErrorAction SilentlyContinue }
Import-Module '$Manifest' -Force
`$notShadowed = @($shadowed) | Where-Object { (Get-Command `$_ -ErrorAction SilentlyContinue).Source -ne '$script:StubModuleName' }
if (`$notShadowed) {
    Write-Host "[HARNESS] Az stubs are not in effect for: `$(`$notShadowed -join ', ') - refusing to run."
    exit 99
}
`$global:LASTEXITCODE = 0
& '$script:ScriptPath' -Force
exit `$LASTEXITCODE
"@

        $saved = @{
            Fail       = $env:SKYCRAFT_STUB_FAIL
            Empty      = $env:SKYCRAFT_STUB_EMPTY
            Log        = $env:SKYCRAFT_STUB_LOG
            RsVersion  = $env:SKYCRAFT_STUB_RSVERSION
            ModulePath = $env:PSModulePath
        }
        try {
            $env:SKYCRAFT_STUB_FAIL      = $Fail -join ','
            $env:SKYCRAFT_STUB_EMPTY     = if ($Empty) { '1' } else { '0' }
            $env:SKYCRAFT_STUB_LOG       = $logPath
            $env:SKYCRAFT_STUB_RSVERSION = $RecoveryServicesVersion
            # Only so the placeholder Az.* modules are discoverable when no real Az is installed.
            $env:PSModulePath = (Join-Path (Split-Path -Parent $Manifest) 'modules') +
                                [System.IO.Path]::PathSeparator + $env:PSModulePath

            $output = & pwsh -NoProfile -NonInteractive -Command $childCommand 2>&1
            $code   = $LASTEXITCODE
        } finally {
            $env:SKYCRAFT_STUB_FAIL      = $saved.Fail
            $env:SKYCRAFT_STUB_EMPTY     = $saved.Empty
            $env:SKYCRAFT_STUB_LOG       = $saved.Log
            $env:SKYCRAFT_STUB_RSVERSION = $saved.RsVersion
            $env:PSModulePath            = $saved.ModulePath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $code
            Output   = ($output | Out-String)
            Calls    = $calls
        }
    }

    $script:Manifest = Initialize-StubModule
    $script:StubDir  = Split-Path -Parent $script:Manifest

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean       = Invoke-CleanupScript -Manifest $script:Manifest
    $script:Nothing     = Invoke-CleanupScript -Manifest $script:Manifest -Empty
    $script:VaultStuck  = Invoke-CleanupScript -Manifest $script:Manifest -Fail 'Remove-AzRecoveryServicesVault'
    $script:TwoStuck    = Invoke-CleanupScript -Manifest $script:Manifest -Fail 'Remove-AzDataProtectionBackupInstance', 'Remove-AzRecoveryServicesVault'
    $script:FirstStuck  = Invoke-CleanupScript -Manifest $script:Manifest -Fail 'Remove-AzDataProtectionBackupInstance'
    $script:StaleModule = Invoke-CleanupScript -Manifest $script:Manifest -RecoveryServicesVersion '7.1.0'
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az cmdlets instead of touching Azure' {
        # Exit 99 is the child refusing to run; anything else means the stubs were in effect.
        foreach ($run in @($script:Clean, $script:Nothing, $script:VaultStuck, $script:StaleModule)) {
            $run.ExitCode | Should -Not -Be 99 -Because "the harness must never fall through to the real Az cmdlets: $($run.Output)"
        }
    }
}

Describe 'Lab 5.2 Remove-LabResource.ps1 - exit code contract' {

    It 'exits 0 when every step succeeds' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
    }

    It 'exits 0 when there is nothing to delete' {
        $script:Nothing.ExitCode | Should -Be 0
        $script:Nothing.Output   | Should -Match 'No Lab 5\.2 resources found to delete'
    }

    It 'exits 1 when a resource exists but cannot be deleted' {
        $script:VaultStuck.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($script:VaultStuck.Output)"
        $script:VaultStuck.Output   | Should -Match '\[ERROR\] Could not delete RSV'
        $script:VaultStuck.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $script:VaultStuck.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'counts every failed step rather than stopping at the first' {
        $script:TwoStuck.ExitCode | Should -Be 1
        $script:TwoStuck.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
    }

    It 'keeps running the later steps after a failure' {
        # The blob instance delete failed, yet the vault teardown and the residue cleanup ran.
        $script:FirstStuck.Calls    | Should -Contain 'Remove-AzRecoveryServicesVault'
        $script:FirstStuck.Calls    | Should -Contain 'Remove-AzResource'
        $script:FirstStuck.ExitCode | Should -Be 1
    }
}

Describe 'Lab 5.2 Remove-LabResource.ps1 - Recovery Services Vault failure hint' {

    It 'names the tooling requirement' {
        $script:VaultStuck.Output | Should -Match 'Azure CLI 2\.75\.0\+'
        $script:VaultStuck.Output | Should -Match 'Az PowerShell 7\.5\.0\+'
    }

    It 'no longer claims the vault must be emptied through the portal first' {
        $script:VaultStuck.Output | Should -Not -Match 'Backup Items . Stop protection'
        $script:VaultStuck.Output | Should -Not -Match 'Ensure all backup items, data, and ASR resources are removed first'
    }
}

Describe 'Lab 5.2 Remove-LabResource.ps1 - orphaned Azure Backup residue' {

    It 'deletes the orphaned restore point collection' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzResource'
        $script:Clean.Output | Should -Match 'AzureBackup_dev-skycraft-swc-auth-vm_7702140526018345310'
    }

    It 'deletes the AzureBackupRG_* group once it is empty' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzResourceGroup'
        $script:Clean.Output | Should -Match 'Deleting empty Azure Backup resource group: AzureBackupRG_swedencentral_1'
    }

    It 'leaves resource groups that are not Azure Backup residue alone' {
        $script:Clean.Output | Should -Not -Match 'Azure Backup resource group: platform-skycraft-swc-rg'
    }
}

Describe 'Lab 5.2 Remove-LabResource.ps1 - tooling version guard' {

    It 'warns before deleting anything when Az.RecoveryServices is older than 7.5.0' {
        $script:StaleModule.Output | Should -Match '\[WARNING\] Az\.RecoveryServices 7\.1\.0 is older than 7\.5\.0'
    }

    It 'diagnoses the stale module without blocking the teardown' {
        # A teardown that refuses to run over a warning strands billable resources.
        $script:StaleModule.ExitCode | Should -Be 0
        $script:StaleModule.Calls    | Should -Contain 'Remove-AzRecoveryServicesVault'
    }

    It 'reports the version and does not warn when Az.RecoveryServices is current' {
        $script:Clean.Output | Should -Match 'Az\.RecoveryServices version: 7\.7\.1'
        $script:Clean.Output | Should -Not -Match 'is older than'
    }
}
