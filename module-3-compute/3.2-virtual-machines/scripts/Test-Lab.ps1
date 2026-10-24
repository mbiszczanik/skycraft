<#
.SYNOPSIS
    Tests Lab 3.2 Virtual Machines deployment.

.DESCRIPTION
    Validates that all Lab 3.2 resources are deployed correctly, whichever path built them
    (Portal, Az PowerShell or Bicep):
    - VMs exist, are running and sit in their zones
    - each VM's NIC is in its subnet and, in dev, in its application security group (Lab 2.2)
    - the World VM has its data disk at LUN 0
    - each VM's NIC is in its role pool and in the egress pool <lb>-be-outbound, the only pool the
      load balancer's outbound rule gives internet access (the subnets are private)
    - the key vault exists, the Auth VM is encrypted with Azure Disk Encryption and the World VM
      is not: Lab 5.2 runs file-level recovery and Site Recovery on it (#368)
    - a scale set left over from Step 3.2.33 is reported as a warning, not counted

    NICs and disks are found through their VMs (NetworkProfile, StorageProfile), never by name:
    the Portal names a NIC <vm-name><digits> (#355). Every check runs in its own try/catch, so a
    missing resource is a [FAIL] line, not a crash.

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER KeyVaultName
    The key vault of Step 3.2.17, when the default name was taken (key vault names are globally
    unique). Default: <env>-skycraft-swc-kv

.EXAMPLE
    .\Test-Lab.ps1 -Environment dev

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.Network, Az.KeyVault

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$')]
    [string]$KeyVaultName
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$namePrefix = "$Environment-skycraft-swc"
$kvName = if ($KeyVaultName) { $KeyVaultName } else { "$namePrefix-kv" }
$script:passCount = 0
$script:failCount = 0

function Invoke-Test {
    param(
        [string]$Label,
        [scriptblock]$Test
    )
    Write-Host "  Testing: $Label..." -NoNewline
    try {
        if (& $Test) {
            Write-Host " PASS" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host " FAIL ($($_.Exception.Message))" -ForegroundColor Red
        $script:failCount++
    }
}

# Returns the resource or $null; a failed lookup surfaces in the check that needs the resource.
function Get-LabVm {
    param([string]$Name)
    try { Get-AzVM -ResourceGroupName $rgName -Name $Name -ErrorAction Stop } catch { $null }
}

function Get-LabVmNic {
    param($Vm)
    $nicId = @($Vm.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.Id }) | Select-Object -First 1
    if (-not $nicId) { return $null }
    try { Get-AzNetworkInterface -ResourceId $nicId -ErrorAction Stop } catch { $null }
}

# Whether one of the NIC's IP configurations is a member of the pool.
function Test-NicInPool {
    param($Nic, $Lb, [string]$PoolName)
    if (-not $Nic -or -not $Lb) { return $false }
    $members = @(($Lb.BackendAddressPools | Where-Object { $_.Name -eq $PoolName }).BackendIpConfigurations | ForEach-Object { $_.Id })
    @($members | Where-Object { $_ -like "$($Nic.Id)/ipConfigurations/*" }).Count -gt 0
}

Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Deployment Validation"  -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

# Verify Azure context
$context = Get-AzContext
if (-not $context) {
    Write-Host "[ERROR] Not logged into Azure. Run Connect-AzAccount first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

$roles = @(
    @{ Label = 'Auth';  Vm = "$namePrefix-auth-vm";  Zone = '1'; Subnet = 'AuthSubnet';  Asg = "$namePrefix-asg-auth";  Pool = "$namePrefix-lb-be-auth" }
    @{ Label = 'World'; Vm = "$namePrefix-world-vm"; Zone = '2'; Subnet = 'WorldSubnet'; Asg = "$namePrefix-asg-world"; Pool = "$namePrefix-lb-be-world" }
)
foreach ($role in $roles) {
    $role.Model = Get-LabVm -Name $role.Vm
    $role.Nic = if ($role.Model) { Get-LabVmNic -Vm $role.Model } else { $null }
}
$auth, $world = $roles

# ============================================================================
# VM Tests
# ============================================================================
Write-Host "[VMs]" -ForegroundColor Yellow

foreach ($role in $roles) {
    # Get-AzVM -Status returns an instance view: the power state is in .Statuses.
    Invoke-Test "$($role.Label) VM exists and running" {
        $iv = Get-AzVM -ResourceGroupName $rgName -Name $role.Vm -Status -ErrorAction Stop
        ($iv.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus -eq 'VM running'
    }
}
foreach ($role in $roles) {
    Invoke-Test "$($role.Label) VM in Zone $($role.Zone)" { @($role.Model.Zones) -contains $role.Zone }
}

# ============================================================================
# NIC Tests (each NIC is found through its VM, whatever its name)
# ============================================================================
Write-Host ""
Write-Host "[NICs]" -ForegroundColor Yellow

foreach ($role in $roles) {
    Invoke-Test "$($role.Label) NIC in $($role.Subnet)" {
        @($role.Nic.IpConfigurations | Where-Object { $_.Subnet.Id -like "*/subnets/$($role.Subnet)" }).Count -gt 0
    }
}

# Lab 2.2 creates the ASGs in dev only.
if ($Environment -eq 'dev') {
    foreach ($role in $roles) {
        Invoke-Test "$($role.Label) NIC in application security group $($role.Asg)" {
            $asgIds = @($role.Nic.IpConfigurations | ForEach-Object { $_.ApplicationSecurityGroups } | ForEach-Object { $_.Id })
            @($asgIds | Where-Object { $_ -like "*/applicationSecurityGroups/$($role.Asg)" }).Count -gt 0
        }
    }
}

# ============================================================================
# Data Disk Tests
# ============================================================================
Write-Host ""
Write-Host "[Data Disks]" -ForegroundColor Yellow

Invoke-Test "World VM has a 64 GB data disk at LUN 0" {
    $disk = @($world.Model.StorageProfile.DataDisks | Where-Object { $_.Lun -eq 0 }) | Select-Object -First 1
    $disk -and $disk.DiskSizeGB -eq 64
}

# ============================================================================
# Load Balancer Tests
# ============================================================================
Write-Host ""
Write-Host "[Load Balancer]" -ForegroundColor Yellow

$lb = try { Get-AzLoadBalancer -ResourceGroupName $rgName -Name "$namePrefix-lb" -ErrorAction Stop } catch { $null }

foreach ($role in $roles) {
    Invoke-Test "$($role.Label) NIC in LB backend pool $($role.Pool)" { Test-NicInPool -Nic $role.Nic -Lb $lb -PoolName $role.Pool }
}

# The subnets are private and the load balancer's single outbound rule (Lab 2.3) covers only
# '-be-outbound', so a VM outside it has no internet access.
foreach ($role in $roles) {
    Invoke-Test "$($role.Label) VM NIC in egress pool $namePrefix-lb-be-outbound" { Test-NicInPool -Nic $role.Nic -Lb $lb -PoolName "$namePrefix-lb-be-outbound" }
}

# ============================================================================
# Disk Encryption Tests (#368: only the Auth VM is encrypted)
# ============================================================================
Write-Host ""
Write-Host "[Disk Encryption]" -ForegroundColor Yellow

Invoke-Test "Key vault $kvName enabled for disk encryption" {
    $kv = Get-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -ErrorAction Stop
    $kv -and $kv.EnabledForDiskEncryption
}

Invoke-Test "Auth VM OS disk encrypted with Azure Disk Encryption" {
    $status = Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $auth.Vm -ErrorAction Stop
    "$($status.OsVolumeEncrypted)" -eq 'Encrypted'
}

# Lab 5.2 restores files from and replicates the World VM; file recovery is not available for an ADE VM.
Invoke-Test "World VM not encrypted with Azure Disk Encryption (Lab 5.2)" {
    $status = Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $world.Vm -ErrorAction Stop
    $status -and "$($status.OsVolumeEncrypted)" -ne 'Encrypted' -and "$($status.DataVolumesEncrypted)" -ne 'Encrypted'
}

# ============================================================================
# Scale set cleanup (Step 3.2.33), reported, not counted
# ============================================================================
$vmssName = "$namePrefix-world-vmss"
try {
    $vmss = Get-AzVmss -ResourceGroupName $rgName -VMScaleSetName $vmssName -ErrorAction Stop
    if ($vmss) {
        Write-Host ""
        Write-Host "[WARN] Scale set $vmssName still exists and its instances cost money. Delete it (Step 3.2.33) or run Remove-LabResource.ps1." -ForegroundColor Yellow
    }
} catch {
    if ("$_" -notmatch 'was not found|ResourceNotFound|NotFound') {
        Write-Host ""
        Write-Host "[WARN] Could not check for a leftover scale set $($vmssName): $_" -ForegroundColor Yellow
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Test Results Summary"  -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Passed: $script:passCount" -ForegroundColor Green
if ($script:failCount -gt 0) {
    Write-Host "  Failed: $script:failCount" -ForegroundColor Red
} else {
    Write-Host "  Failed: $script:failCount" -ForegroundColor Gray
}
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

Exit-Lab -FailureCount $script:failCount
