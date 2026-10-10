<#
.SYNOPSIS
    Removes Lab 3.2 Virtual Machines resources.

.DESCRIPTION
    Cleans up Lab 3.2 resources in the following order:
    1. Virtual Machines (which auto-deletes NICs and OS disks via deleteOption=Delete)
    2. Data Disks
    3. Key Vault (if exists; deleted and purged)

    Note: This does NOT remove Lab 3.1 resources (VNets, NSGs, Load Balancer).

    Every step continues on error, so one stuck resource does not strand the rest. A lookup that
    fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported as
    [ERROR] and counted; if anything failed the script exits 1. A resource that does not exist is
    not a failure: only a lookup that succeeds and does not find it, or a getter that reports it
    as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue #290, as #255
    did for Labs 1.2-2.3). A resource that could not be looked up is left alone.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER IncludeKeyVault
    Also remove the Key Vault and purge it from the soft-deleted state (requires purge permission on the vault).

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev -Force -IncludeKeyVault

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.KeyVault

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$IncludeKeyVault
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and resources that exist but could not be deleted. Absent resources
# are not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzVM and Get-AzDisk report a missing resource as an ARM 404: "The Resource '<type>/<name>'
# under resource group '<rg>' was not found.", code ResourceNotFound; when the group is gone as
# well, "Resource group '<rg>' could not be found.", code ResourceGroupNotFound; with no error
# body, "Operation returned an invalid status code 'NotFound'". Get-AzKeyVault returns nothing
# for a vault that does not exist. The Azure.Core clients say "Status: 404 (Not Found)". A
# missing subscription is a 404 too, but it means the context is wrong, not that the resource is
# gone, so it never reads as "absent".
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
#             cannot tell whether the resource is gone, and the caller leaves the resource alone
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
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "     A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$namePrefix = "$Environment-skycraft-swc"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify Azure context
$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged into Azure. Run Connect-AzAccount first."
    $Host.SetShouldExit(1)
    exit 1
}

# List resources to be deleted
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = @()

# Check VMs
$vms = @("$namePrefix-auth-vm", "$namePrefix-world-vm")
# The VMs whose lookup failed, by name.
$vmLookupFailed = @{}
foreach ($vm in $vms) {
    $vmLookup = Invoke-LabLookup -Target "VM $vm" -Lookup {
        Get-AzVM -Name $vm -ResourceGroupName $rgName -ErrorAction Stop
    }
    if ($vmLookup.Failed) { $vmLookupFailed[$vm] = $true }
    if ($vmLookup.Value) {
        $resourcesToDelete += @{ Type = 'VM'; Name = $vm }
        Write-Host "  - VM: $vm" -ForegroundColor Gray
    }
}

# Check Data Disks. The data disk belongs to the world VM: when that VM could not be looked up, it
# may still hold the disk, so the disk is left alone too (not counted again - the lookup is).
$dataDisk = "$namePrefix-world-datadisk"
if ($vmLookupFailed["$namePrefix-world-vm"]) {
    Write-Host "  [SKIP] Disk $dataDisk kept: VM $namePrefix-world-vm could not be looked up and may still use it." -ForegroundColor Yellow
}
else {
    $diskLookup = Invoke-LabLookup -Target "disk $dataDisk" -Lookup {
        Get-AzDisk -DiskName $dataDisk -ResourceGroupName $rgName -ErrorAction Stop
    }
    if ($diskLookup.Value) {
        $resourcesToDelete += @{ Type = 'Disk'; Name = $dataDisk }
        Write-Host "  - Disk: $dataDisk" -ForegroundColor Gray
    }
}

# Check Key Vault
if ($IncludeKeyVault) {
    $kvName = "$namePrefix-kv"
    $kvLookup = Invoke-LabLookup -Target "Key Vault $kvName" -Lookup {
        Get-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -ErrorAction Stop
    }
    $vault = $kvLookup.Value | Select-Object -First 1
    if ($vault) {
        # The vault object carries the location the purge needs.
        $resourcesToDelete += @{ Type = 'KeyVault'; Name = $kvName; Vault = $vault }
        Write-Host "  - Key Vault: $kvName" -ForegroundColor Gray
    }
}

if ($resourcesToDelete.Count -eq 0 -and $script:cleanupFailures -eq 0) {
    Write-Host "`nNo Lab 3.2 resources found to delete." -ForegroundColor Green
    exit 0
}

# Delete resources
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# Delete VMs first (NICs and OS disks auto-delete via deleteOption=Delete)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'VM' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove virtual machine')) {
        Write-Host "  Deleting VM: $($resource.Name)..." -ForegroundColor Gray
        try {
            Remove-AzVM -Name $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Could not delete VM $($resource.Name): $_" -ForegroundColor Red
        }
    }
}

# Delete data disks
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'Disk' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove managed disk')) {
        Write-Host "  Deleting Disk: $($resource.Name)..." -ForegroundColor Gray
        try {
            Remove-AzDisk -DiskName $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Could not delete disk $($resource.Name): $_" -ForegroundColor Red
        }
    }
}

# Delete and purge the Key Vault (soft delete cannot be disabled; the lab keeps 7-day retention and no purge protection)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'KeyVault' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove and purge Key Vault')) {
        $vault = $resource.Vault
        Write-Host "  Deleting Key Vault: $($resource.Name)..." -ForegroundColor Gray
        try {
            Remove-AzKeyVault -VaultName $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Could not delete Key Vault $($resource.Name): $_" -ForegroundColor Red
            continue
        }
        Write-Host "  Purging Key Vault: $($resource.Name) (location $($vault.Location))..." -ForegroundColor Gray
        try {
            Remove-AzKeyVault -VaultName $resource.Name -Location $vault.Location -InRemovedState -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted and purged" -ForegroundColor Green
        } catch {
            Write-Warning "Vault '$($vault.VaultName)' deleted but not purged: $_"
            Write-Host "  Purge manually: Remove-AzKeyVault -VaultName $($vault.VaultName) -Location $($vault.Location) -InRemovedState -Force" -ForegroundColor Gray
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    Write-Host "  The resources named there may still exist in $rgName. Re-run this script once the cause is cleared." -ForegroundColor Gray
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.1 resources (VNets, NSGs, LB) were NOT deleted." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
