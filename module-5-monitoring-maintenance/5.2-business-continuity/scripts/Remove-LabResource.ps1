<#
.SYNOPSIS
    Removes Lab 5.2 Business Continuity & Disaster Recovery resources.

.DESCRIPTION
    Cleans up Lab 5.2 BCDR resources in the correct dependency order:
    1. Blob backup instances (Backup Vault)
    2. RBAC role assignments granted to the Backup Vault identity on the storage account
       (Storage Blob Data Owner, Storage Account Backup Contributor)
    3. Backup Vault (platform-skycraft-swc-bv)
    4. VM backup protection item with data deletion
    5. Recovery Services Vault (platform-skycraft-swc-rsv)
    6. The instant-restore snapshot resource group platform-skycraft-swc-rpc<n>-rg, with the
       restore point collection inside it. SkyCraft owns it (main.bicep creates it and the VM
       backup policy names it, issue #184), so it is deleted outright.
    7. Orphaned Azure Backup restore point collections and the AzureBackupRG_<location>_*
       resource groups that held them, once those groups are empty. Only a policy created
       before issue #184 leaves these behind.

    Notes:
    - The role assignments are removed before the Backup Vault so its managed
      identity is still resolvable; otherwise they would be orphaned on the
      storage account after the vault (and its identity) is deleted.
    - Azure Site Recovery resources (ASR fabric, replication, cache storage
      account) must be cleaned up manually via the Azure Portal before
      deleting the Recovery Services Vault.
    - VMs and Storage Accounts from earlier labs are NOT removed by this script.

    Every step continues on error, so a single stuck resource does not strand the rest. A step
    that fails is reported as [ERROR] with the Azure error message and counted; if any step
    failed the script exits 1 - so a masked failure cannot be mistaken for a clean cleanup.

    A resource that does not exist is not a failure. A lookup that fails with an error (a 403,
    throttling, a transient ARM error) is: it cannot tell whether the resource is gone, so it is
    reported as [ERROR] and counted the same way (issue #238, as #227 did for Lab 1.1). Only a
    lookup that succeeds and finds nothing, or a getter that reports the resource as not found,
    means "absent" - Test-LabNotFoundError tells the two apart. A resource whose dependants could
    not be looked up stays where it is:
    - the snapshot resource group and SkyCraft's restore point collections in AzureBackupRG_*
      survive a Recovery Services Vault or VM backup item lookup that failed, as they survive a
      VM whose protection could not be stopped;
    - the Backup Vault survives a blob backup instance, storage account or role assignment
      lookup that failed, and a role assignment it could not remove, so its identity is still
      there for a rerun to remove the assignments with;
    - an AzureBackupRG_* group survives a failed check that it is empty.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).
    A caller that dot-sources this script, or runs "& .\Remove-LabResource.ps1" with further
    statements after it, still ends with its own exit code rather than this one.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.3.0
    Date: 2026-10-09
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.RecoveryServices, Az.DataProtection, Az.Resources, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
$storageAccount = 'prodskycraftswcsa'
$location       = 'swedencentral'
# Azure Backup names the snapshot group <prefix><n><suffix>; main.bicep creates n = 1, and the
# service adds n = 2, 3, ... only when one group fills up. The pattern covers all of them.
$snapshotRgPattern = 'platform-skycraft-swc-rpc*-rg'

# Minimum Az.RecoveryServices for the one-pass vault delete (see the prerequisite check below).
$rsvMinModuleVersion = [version]'7.5.0'

# Counts lookups that failed and resources that exist but could not be deleted. Absent
# resources are not failures.
$script:cleanupFailures = 0
# Set when a VM backup item could not be stopped, or the vault or its backup items could not be
# looked up; the snapshot group must then survive (step 6).
$script:protectionStillOn = $false
# Set when the vault's blob backup instances or its role assignments on the storage account could
# not be looked up, or a role assignment could not be removed; the Backup Vault must then survive
# (step 3). Deleting it takes its identity along, and an assignment left on the storage account
# would be orphaned for good: a rerun finds no vault and exits 0.
$script:backupVaultMustStay = $false

# Roles granted to the Backup Vault identity by New-LabBlobBackup.ps1 (must be revoked here)
$backupRoles = @(
    @{ Name = 'Storage Blob Data Owner';            RoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' },
    @{ Name = 'Storage Account Backup Contributor'; RoleId = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1' }
)

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Every getter below reports a missing resource as an ARM 404, in one of these shapes:
#   - Get-AzStorageAccount and Get-AzRecoveryServicesVault (CloudException): "The Resource
#     '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound; when the
#     group is gone as well, "Resource group '<rg>' could not be found.", code
#     ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
#     'NotFound'". The exception carries the code in Body and the status in Response.
#   - Get-AzDataProtectionBackupVault and -BackupInstance (generated cmdlets): the same ARM
#     messages, with the code as the error id ("ResourceNotFound,Get-AzDataProtectionBackupVault").
#   - Azure.Core clients: "Status: 404 (Not Found)" and "ErrorCode: ResourceNotFound".
# The list getters - Get-AzResourceGroup, Get-AzResource, Get-AzRecoveryServicesBackupItem and
# Get-AzRoleAssignment - return nothing when nothing matches; Get-AzResource still reports a
# group that is gone as ResourceGroupNotFound. A missing subscription is a 404 too, but it means
# the context is wrong, not that the resource is gone, so it never reads as "absent".
function Test-LabNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add([string]$ErrorRecord)
    $evidence.Add([string]$ErrorRecord.FullyQualifiedErrorId)
    $status404 = $false
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        $evidence.Add([string]$exception.Message)
        foreach ($code in @($exception.Body.Code, $exception.Body.Error.Code, $exception.ErrorCode)) {
            if ($code) { $evidence.Add([string]$code) }
        }
        # ResponseStatusCode: the generated cmdlets' RestException, which may carry no error body.
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Runs one lookup with -ErrorAction Stop inside $Lookup, and returns what it found:
#   Value     the lookup's output, as an array - empty when the resource is absent
#   NotFound  the getter reported the resource as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the resource is gone, and the caller keeps its dependants
function Invoke-LabLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Lookup
    )

    try {
        $value = @(& $Lookup)
        return [pscustomobject]@{ Value = $value; NotFound = $false; Failed = $false }
    } catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "    A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# Azure Backup "secure by default" keeps soft delete AlwaysON on every new Recovery Services
# Vault, so step 5 deletes a vault that still holds soft-deleted items. That works in a single
# pass - but only on Azure CLI 2.75.0+ / Az PowerShell 7.5.0+ (Az.RecoveryServices 7.5.0);
# older tooling insists on a fully empty vault and reintroduces the 14-day wait. Diagnose a
# stale module here, before the delete is attempted, and still run the teardown: refusing to
# clean up over a warning would strand billable resources.
$rsvModuleVersion = (Get-Module -ListAvailable -Name Az.RecoveryServices |
                     Sort-Object Version -Descending |
                     Select-Object -First 1).Version
if ($rsvModuleVersion -and $rsvModuleVersion -ge $rsvMinModuleVersion) {
    Write-Host "  ✓ Az.RecoveryServices version: $rsvModuleVersion" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Az.RecoveryServices $rsvModuleVersion is older than $rsvMinModuleVersion." -ForegroundColor Yellow
    Write-Host "    Deleting a vault that holds soft-deleted items needs Azure CLI 2.75.0+ or" -ForegroundColor Gray
    Write-Host "    Az PowerShell 7.5.0+. Older versions require a fully empty vault and" -ForegroundColor Gray
    Write-Host "    reintroduce the 14-day soft-delete wait. Run: Update-Module Az.RecoveryServices" -ForegroundColor Gray
}

# ── Inventory existing resources ──────────────────────────────────────────
Write-Host "`nChecking resources to delete..." -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

# Every lookup below goes through Invoke-LabLookup: one that fails is an [ERROR] counted in
# $script:cleanupFailures, never "absent" (issue #238).
$bvLookup = Invoke-LabLookup -Target "Backup Vault $bvName" -Lookup {
    Get-AzDataProtectionBackupVault -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction Stop
}
$bvExists = $bvLookup.Value | Select-Object -First 1
if ($bvExists) {
    $instanceLookup = Invoke-LabLookup -Target "the blob backup instances in $bvName" -Lookup {
        Get-AzDataProtectionBackupInstance -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction Stop
    }
    if ($instanceLookup.Failed) { $script:backupVaultMustStay = $true }
    foreach ($inst in $instanceLookup.Value) {
        $resourcesToDelete.Add(@{ Type = 'BlobInstance'; Name = $inst.Name })
        Write-Host "  - Blob Backup Instance: $($inst.Name)" -ForegroundColor Gray
    }

    # Plan removal of the RBAC roles granted to the BV identity on the storage account.
    # Resolve the principalId now, while the vault (and its identity) still exists.
    $bvPrincipalId = $bvExists.IdentityPrincipalId
    $storageLookup = Invoke-LabLookup -Target "storage account $storageAccount" -Lookup {
        Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction Stop
    }
    # Without the storage account the role assignments cannot be planned, so the vault stays.
    if ($storageLookup.Failed) { $script:backupVaultMustStay = $true }
    $storage = $storageLookup.Value | Select-Object -First 1
    if ($bvPrincipalId -and $storage) {
        foreach ($role in $backupRoles) {
            $resourcesToDelete.Add(@{
                Type        = 'RoleAssignment'
                Name        = $role.Name
                RoleId      = $role.RoleId
                PrincipalId = $bvPrincipalId
                Scope       = $storage.Id
            })
            Write-Host "  - RBAC role assignment: $($role.Name) on $storageAccount" -ForegroundColor Gray
        }
    }

    $resourcesToDelete.Add(@{ Type = 'BackupVault'; Name = $bvName })
    Write-Host "  - Backup Vault: $bvName" -ForegroundColor Gray
}

$rsvLookup = Invoke-LabLookup -Target "Recovery Services Vault $rsvName" -Lookup {
    Get-AzRecoveryServicesVault -ResourceGroupName $platformRg -Name $rsvName -ErrorAction Stop
}
# A vault that could not be looked up may still protect a VM, so step 6 keeps the snapshot group.
if ($rsvLookup.Failed) { $script:protectionStillOn = $true }
$rsvExists = $rsvLookup.Value | Select-Object -First 1
if ($rsvExists) {
    $itemLookup = Invoke-LabLookup -Target "the VM backup items in $rsvName" -Lookup {
        Get-AzRecoveryServicesBackupItem -VaultId $rsvExists.ID -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction Stop
    }
    # The same holds for backup items that could not be listed: a VM may still be protected.
    if ($itemLookup.Failed) { $script:protectionStillOn = $true }
    foreach ($item in $itemLookup.Value) {
        # FriendlyName comes back empty for some protected VMs, which left the progress
        # lines and the ShouldProcess target blank during the live v0.8.0 verification.
        # The container name carries the VM name as its last ';'-separated segment.
        $displayName = if ($item.FriendlyName) {
            $item.FriendlyName
        } elseif ($item.ContainerName) {
            ($item.ContainerName -split ';')[-1]
        } else {
            $item.Name
        }
        $resourcesToDelete.Add(@{
            Type          = 'VmBackupItem'
            Name          = $item.Name
            ContainerName = $item.ContainerName
            FriendlyName  = $displayName
            Item          = $item
        })
        Write-Host "  - VM Backup Item: $displayName" -ForegroundColor Gray
    }
    $resourcesToDelete.Add(@{ Type = 'RSV'; Name = $rsvName })
    Write-Host "  - Recovery Services Vault: $rsvName" -ForegroundColor Gray
}

# One listing serves both scans below. If it fails, neither group kind is planned: the run
# exits 1 and a rerun picks them up.
$rgLookup = Invoke-LabLookup -Target 'the resource groups in the subscription' -Lookup {
    Get-AzResourceGroup -ErrorAction Stop
}

# The instant-restore snapshot group the VM backup policy names (#184). Unlike AzureBackupRG_*,
# nothing outside this lab writes to it, so it goes as a whole - restore point collection included.
$snapshotRgs = $rgLookup.Value | Where-Object { $_.ResourceGroupName -like $snapshotRgPattern }
foreach ($snapshotRg in $snapshotRgs) {
    $resourcesToDelete.Add(@{ Type = 'SnapshotResourceGroup'; Name = $snapshotRg.ResourceGroupName })
    Write-Host "  - Snapshot resource group: $($snapshotRg.ResourceGroupName)" -ForegroundColor Gray
}

# Azure Backup provisions AzureBackupRG_<location>_<n> next to the protected VM and parks a
# Microsoft.Compute/restorePointCollections container in it for instant-restore snapshots.
# Disabling protection releases the snapshots, but the (now empty) container and its resource
# group outlive the vault and had to be deleted by hand after the v0.8.0 cycle (#105).
$backupRgCandidates = $rgLookup.Value | Where-Object { $_.ResourceGroupName -like "AzureBackupRG_${location}_*" }
foreach ($backupRg in $backupRgCandidates) {
    $rgName           = $backupRg.ResourceGroupName
    $rgResourceLookup = Invoke-LabLookup -Target "the resources in $rgName" -Lookup {
        Get-AzResource -ResourceGroupName $rgName -ErrorAction Stop
    }
    # A group whose contents could not be listed is left alone (the [ERROR] is counted): an empty
    # listing here would read as "empty group" and plan its delete. One that is gone is skipped.
    if ($rgResourceLookup.Failed -or $rgResourceLookup.NotFound) { continue }
    $rgResources = $rgResourceLookup.Value

    # Only SkyCraft's own collections: the group is shared, and an unrelated protected VM's
    # collection must survive this teardown.
    $rpcs = @($rgResources | Where-Object {
        $_.ResourceType -eq 'Microsoft.Compute/restorePointCollections' -and
        $_.Name -like 'AzureBackup_*skycraft*'
    })
    foreach ($rpc in $rpcs) {
        $resourcesToDelete.Add(@{
            Type              = 'RestorePointCollection'
            Name              = $rpc.Name
            ResourceGroupName = $rgName
            ResourceId        = $rpc.ResourceId
        })
        Write-Host "  - Restore point collection: $($rpc.Name) (in $rgName)" -ForegroundColor Gray
    }

    # The group itself is only deleted if it is left empty once those collections are gone.
    if ($rpcs.Count -gt 0 -or $rgResources.Count -eq 0) {
        $resourcesToDelete.Add(@{ Type = 'BackupResourceGroup'; Name = $rgName })
        Write-Host "  - Azure Backup resource group: $rgName (deleted only if left empty)" -ForegroundColor Gray
    }
}

if ($resourcesToDelete.Count -eq 0) {
    # "Nothing found" is only true when every lookup succeeded; otherwise the summary exits 1.
    if ($script:cleanupFailures -eq 0) {
        Write-Host "`nNo Lab 5.2 resources found to delete." -ForegroundColor Green
        exit 0
    }
    Write-Host "`nNo Lab 5.2 resources found, but $($script:cleanupFailures) lookup(s) failed - see the [ERROR] lines above." -ForegroundColor Red
} else {
    # ── Confirm deletion (per-operation via ShouldProcess; pass -Force or -Confirm:$false to skip) ──
    Write-Host "`n[WARNING] This will permanently delete the above resources." -ForegroundColor Yellow
    Write-Host "  Ensure ASR replication has been removed via Azure Portal first." -ForegroundColor Gray
    Write-Host "  VMs, VNets, and Storage Accounts will NOT be deleted." -ForegroundColor Gray

    Write-Host "`nDeleting resources..." -ForegroundColor Yellow
}

# 1. Delete Blob Backup Instances
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BlobInstance' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete blob backup instance')) { continue }
    Write-Host "  Deleting Blob Backup Instance: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzDataProtectionBackupInstance `
            -ResourceGroupName $platformRg `
            -VaultName $bvName `
            -Name $r.Name | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete blob backup instance '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 2. Remove RBAC role assignments granted to the BV identity (before deleting the vault,
#    so the managed identity is still resolvable and no orphaned assignments remain).
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RoleAssignment' }) {
    if (-not $PSCmdlet.ShouldProcess("$($r.Name) -> $storageAccount", 'Remove role assignment')) { continue }
    Write-Host "  Removing role assignment '$($r.Name)' on $storageAccount..." -ForegroundColor Gray
    $assignmentLookup = Invoke-LabLookup -Target "role assignment '$($r.Name)' on $storageAccount" -Lookup {
        Get-AzRoleAssignment -ObjectId $r.PrincipalId -RoleDefinitionId $r.RoleId -Scope $r.Scope -ErrorAction Stop
    }
    if ($assignmentLookup.Failed) {
        $script:backupVaultMustStay = $true
        continue
    }
    try {
        if ($assignmentLookup.Value.Count -gt 0) {
            Remove-AzRoleAssignment -ObjectId $r.PrincipalId -RoleDefinitionId $r.RoleId -Scope $r.Scope -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Removed role assignment: $($r.Name)" -ForegroundColor Green
        } else {
            Write-Host "  ✓ Role assignment already absent: $($r.Name)" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        $script:backupVaultMustStay = $true
        Write-Host "  [ERROR] Could not remove role assignment '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 3. Delete Backup Vault. While its blob backup instances or its role assignments could not be
#    checked or removed, the vault stays: its identity is what a rerun needs to find and remove
#    the assignments, and the [ERROR] above already makes this run exit 1.
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BackupVault' }) {
    if ($script:backupVaultMustStay) {
        Write-Host "  [INFO] $($r.Name) left in place - its backup instances or role assignments could not be checked or removed (see the [ERROR] above)." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete backup vault')) { continue }
    Write-Host "  Deleting Backup Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzDataProtectionBackupVault `
            -ResourceGroupName $platformRg `
            -VaultName $r.Name | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete Backup Vault '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 4. Disable VM backup protection and delete backup data
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'VmBackupItem' }) {
    if (-not $PSCmdlet.ShouldProcess($r.FriendlyName, 'Disable VM backup protection and delete backup data')) { continue }
    Write-Host "  Disabling VM backup protection: $($r.FriendlyName)..." -ForegroundColor Gray
    try {
        Disable-AzRecoveryServicesBackupProtection `
            -Item $r.Item `
            -VaultId $rsvExists.ID `
            -RemoveRecoveryPoints `
            -Force | Out-Null
        Write-Host "  ✓ Protection disabled and backup data deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        $script:protectionStillOn = $true
        Write-Host "  [ERROR] Could not disable backup protection for '$($r.FriendlyName)': $_" -ForegroundColor Red
        Write-Host "    Manual cleanup may be required via Azure Portal." -ForegroundColor Gray
    }
}

# 5. Delete Recovery Services Vault
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RSV' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete Recovery Services Vault')) { continue }
    Write-Host "  Deleting Recovery Services Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzRecoveryServicesVault -Vault $rsvExists | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete RSV '$($r.Name)': $_" -ForegroundColor Red
        Write-Host "    Most likely cause is stale tooling: deleting a vault that still holds" -ForegroundColor Gray
        Write-Host "    soft-deleted items needs Azure CLI 2.75.0+ or Az PowerShell 7.5.0+" -ForegroundColor Gray
        Write-Host "    (Az.RecoveryServices $rsvMinModuleVersion+). Older versions require a fully" -ForegroundColor Gray
        Write-Host "    empty vault and reintroduce the 14-day soft-delete wait." -ForegroundColor Gray
        Write-Host "    Otherwise the vault still has dependencies this script does not touch:" -ForegroundColor Gray
        Write-Host "    ASR replicated items, registered storage accounts, or private endpoints." -ForegroundColor Gray
    }
}

# 6. Delete the snapshot resource group. After the protection is gone, nothing but the released
#    restore point collection is left in it. While a VM is still protected - or may be, because
#    the vault or its backup items could not be looked up - the group stays: the next backup
#    would recreate it untagged, and Lab 1.3's policy would deny that group again.
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'SnapshotResourceGroup' }) {
    if ($script:protectionStillOn) {
        Write-Host "  [INFO] $($r.Name) left in place - a VM may still be protected (see the [ERROR] above)." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete instant-restore snapshot resource group')) { continue }
    Write-Host "  Deleting snapshot resource group: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzResourceGroup -Name $r.Name -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete snapshot resource group '$($r.Name)': $_" -ForegroundColor Red
        Write-Host "    A resource lock on the group blocks the delete - the lab never sets one." -ForegroundColor Gray
    }
}

# 7. Delete the orphaned Azure Backup restore point collections and, once they are gone, the
#    AzureBackupRG_<location>_* groups that held them. The step 6 rule applies: while a VM may
#    still be protected, its collection is live, so it stays - and so does the group, whose
#    re-check below then finds it.
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RestorePointCollection' }) {
    if ($script:protectionStillOn) {
        Write-Host "  [INFO] $($r.Name) left in place - a VM may still be protected (see the [ERROR] above)." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete orphaned restore point collection')) { continue }
    Write-Host "  Deleting restore point collection: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete restore point collection '$($r.Name)': $_" -ForegroundColor Red
    }
}

foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BackupResourceGroup' }) {
    # Re-check emptiness: the group is shared infrastructure and Azure recreates it on demand,
    # so it is only removed when nothing is left in it. A check that failed proves nothing - the
    # group would be deleted with whatever it still holds - so the group stays.
    $remainingLookup = Invoke-LabLookup -Target "the resources left in $($r.Name)" -Lookup {
        Get-AzResource -ResourceGroupName $r.Name -ErrorAction Stop
    }
    if ($remainingLookup.Failed) {
        Write-Host "  [INFO] $($r.Name) left in place - it could not be checked for other resources." -ForegroundColor Gray
        continue
    }
    if ($remainingLookup.NotFound) {
        Write-Host "  ✓ Azure Backup resource group already absent: $($r.Name)" -ForegroundColor Green
        continue
    }
    $remaining = $remainingLookup.Value
    if ($remaining.Count -gt 0) {
        Write-Host "  [INFO] $($r.Name) still holds $($remaining.Count) resource(s) - left in place." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete empty Azure Backup resource group')) { continue }
    Write-Host "  Deleting empty Azure Backup resource group: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzResourceGroup -Name $r.Name -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete resource group '$($r.Name)': $_" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:cleanupFailures -gt 0) {
    Write-Host "  Cleanup finished with $($script:cleanupFailures) failure(s)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  See the [ERROR] lines above - this run exits 1, nothing was masked." -ForegroundColor Gray
    Write-Host "  VMs, VNets, and Storage Accounts were NOT deleted." -ForegroundColor Gray
    Write-Host "  ASR replication resources must be removed via Azure Portal." -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, and Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  ASR replication resources must be removed via Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
