<#
.SYNOPSIS
    Replicates dev-skycraft-swc-world-vm to North Europe with Azure Site Recovery (Steps 5.2.6-5.2.7).

.DESCRIPTION
    The Az PowerShell path of the Portal's Disaster recovery wizard, ending in the same state: the
    world VM replicates to the tagged group platform-skycraft-neu-asr-rg and its replication
    item reads Protected with health Normal. The world VM is the unencrypted one: the encrypted
    auth VM needs a target key vault and a copy of its secrets first (issue #368).

    The script will:
    1. Check the VM, the target group (it must carry the four SkyCraft tags) and its vault
       (platform-skycraft-neu-asr-rsv; main.bicep creates both). Nothing here creates a group:
       Site Recovery's own default groups carry no tags and Lab 1.3 denies them (issue #366)
    2. Return at once when the vault already holds a replication item for the VM
    3. Create what replication needs, each only when missing: the tagged target VNet with the
       world subnet, the cache storage account in Sweden Central, the two fabrics and protection
       containers, the 24-hour replication policy, both container mappings and both network
       mappings
    4. Enable replication of the VM's disks into the target group
    5. Wait until the item reads Protected (the initial replication of the two disks took about
       45 minutes), then set the failover VM size to the source VM's size. A size that cannot be
       set is a warning: the live pass of 2026-10-17 saw that job fail without an error text
    6. With -TestFailover: run a test failover into the target VNet, wait for the test VM, then
       clean it up

    Exit code 1 when a prerequisite is missing, a job fails or the wait ends before Protected,
    0 otherwise.

.PARAMETER Force
    Skip the confirmation prompt, for Deploy-Bicep.ps1 and the lab cycle. Without it, a session
    that cannot prompt exits 1 and changes nothing.

.PARAMETER TestFailover
    After Protected, run the test failover of Step 5.2.7 and its cleanup.

.PARAMETER WaitMinutes
    How long to wait for the item to read Protected. Default: 90

.PARAMETER PollSeconds
    Seconds between two status reads. Default: 60

.EXAMPLE
    .\Enable-SiteRecovery.ps1

.EXAMPLE
    .\Enable-SiteRecovery.ps1 -Force -TestFailover

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-10-29
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.RecoveryServices, Az.Compute, Az.Network, Az.Storage

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$TestFailover,

    [Parameter()]
    [ValidateRange(0, 1440)]
    [int]$WaitMinutes = 90,

    [Parameter()]
    [ValidateRange(0, 3600)]
    [int]$PollSeconds = 60
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$vmRg         = 'dev-skycraft-swc-rg'
$vmName       = 'dev-skycraft-swc-world-vm'
$srcVnetName  = 'dev-skycraft-swc-vnet'
$subnetName   = 'WorldSubnet'
$srcLocation  = 'swedencentral'
$dstLocation  = 'northeurope'
$targetRg     = 'platform-skycraft-neu-asr-rg'
$vaultName    = 'platform-skycraft-neu-asr-rsv'
$dstVnetName  = 'platform-skycraft-neu-asr-vnet'
$dstVnetCidr  = '10.3.0.0/16'
$dstSubnetCidr = '10.3.2.0/24'
$requiredTags = @('Project', 'Environment', 'CostCenter', 'Owner')
$srcFabricName = 'asr-a2a-swedencentral'
$dstFabricName = 'asr-a2a-northeurope'
$srcContainerName = 'asr-a2a-swc-container'
$dstContainerName = 'asr-a2a-neu-container'
$policyName   = 'SkyCraft-24h-ASR-Policy'
$srcToDstName = 'asr-swc-to-neu'
$dstToSrcName = 'asr-neu-to-swc'
$srcNetMapName = 'asr-netmap-swc-to-neu'
$dstNetMapName = 'asr-netmap-neu-to-swc'

function Wait-LabAsrJob {
    param([Parameter(Mandatory)]$Job, [string]$Label)
    $deadline = (Get-Date).AddMinutes(30)
    do {
        $Job = Get-AzRecoveryServicesAsrJob -Job $Job
        if ($Job.State -in @('Succeeded', 'Failed', 'Cancelled', 'CompletedWithInformation')) { break }
        Start-Sleep -Seconds ([Math]::Min($PollSeconds, 10))
    } while ((Get-Date) -lt $deadline)
    if ($Job.State -notin @('Succeeded', 'CompletedWithInformation')) {
        $detail = @($Job.Errors | ForEach-Object { $_.ServiceErrorDetails.Message }) -join '; '
        throw "$Label ended $($Job.State)$(if ($detail) { ": $detail" })"
    }
    return $Job
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Site Recovery - World VM" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if (-not (Get-AzContext)) {
    Write-Host "[ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$subscriptionId = (Get-AzContext).Subscription.Id

Write-Host "[1/6] Checking the VM, the target group and the vault..." -ForegroundColor Yellow
$vm = Get-AzVM -ResourceGroupName $vmRg -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "[ERROR] VM '$vmName' not found in '$vmRg'. Complete Lab 3.2 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$rg = Get-AzResourceGroup -Name $targetRg -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "[ERROR] Resource group '$targetRg' not found. Run Deploy-Bicep.ps1 or create it with the SkyCraft tags (Step 5.2.6)." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$missingTags = @($requiredTags | Where-Object { -not $rg.Tags -or -not $rg.Tags.ContainsKey($_) })
if ($missingTags.Count -gt 0) {
    Write-Host "[ERROR] '$targetRg' lacks the tag(s) $($missingTags -join ', '): Lab 1.3 denies what Site Recovery creates in an untagged group." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$tags = @{}
foreach ($key in $requiredTags) { $tags[$key] = $rg.Tags[$key] }
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $targetRg -Name $vaultName -ErrorAction SilentlyContinue
if (-not $vault) {
    Write-Host "[ERROR] Vault '$vaultName' not found in '$targetRg'. Run Deploy-Bicep.ps1 or create it with the SkyCraft tags (Step 5.2.6)." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$size = $vm.HardwareProfile.VmSize
Write-Host "  ✓ $vmName ($size), group $targetRg, vault $vaultName" -ForegroundColor Green

function Get-LabReplicationItem {
    foreach ($fabric in @(Get-AzRecoveryServicesAsrFabric)) {
        foreach ($container in @(Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric)) {
            $item = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
                Where-Object { $_.FriendlyName -eq $vmName } | Select-Object -First 1
            if ($item) { return $item }
        }
    }
}

$item = Get-LabReplicationItem
if (-not $item) {
    if (-not $Force) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', "Replicate $vmName to North Europe. The initial replication takes about 45 minutes and the replica disks, cache account and instance fee are billed until Remove-LabResource.ps1 runs.")
            [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Cancel. Nothing is changed.')
        )
        try {
            $answer = $Host.UI.PromptForChoice('Lab 5.2 - Azure Site Recovery', "`nReplicate $vmName now?", $choices, 1)
        } catch {
            Write-Host "`n[ABORTED] Cannot ask for confirmation: this session has no interactive console." -ForegroundColor Red
            Write-Host "  Re-run with -Force to replicate non-interactively. Nothing was changed." -ForegroundColor Gray
            Exit-Lab -FailureCount 1
        }
        if ($answer -ne 0) {
            Write-Host "Replication cancelled. Nothing was changed." -ForegroundColor Yellow
            Exit-Lab -FailureCount 1
        }
    }

    try {
        Write-Host "`n[2/6] Target network and cache storage account..." -ForegroundColor Yellow
        $dstVnet = Get-AzVirtualNetwork -ResourceGroupName $targetRg -Name $dstVnetName -ErrorAction SilentlyContinue
        if (-not $dstVnet) {
            $subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $dstSubnetCidr
            $dstVnet = New-AzVirtualNetwork -ResourceGroupName $targetRg -Name $dstVnetName -Location $dstLocation `
                -AddressPrefix $dstVnetCidr -Subnet $subnet -Tag $tags
        }
        $srcVnet = Get-AzVirtualNetwork -ResourceGroupName $vmRg -Name $srcVnetName
        # Cache accounts live in the source region; the name is global, so it carries the subscription.
        $cacheName = 'asrcache' + $subscriptionId.Replace('-', '').Substring(0, 12)
        $cache = Get-AzStorageAccount -ResourceGroupName $targetRg -Name $cacheName -ErrorAction SilentlyContinue
        if (-not $cache) {
            $cache = New-AzStorageAccount -ResourceGroupName $targetRg -Name $cacheName -Location $srcLocation `
                -SkuName Standard_LRS -Kind StorageV2 -Tag $tags
        }
        Write-Host "  ✓ $dstVnetName, cache account $cacheName" -ForegroundColor Green

        Write-Host "`n[3/6] Fabrics, containers, policy and mappings..." -ForegroundColor Yellow
        $fabrics = @{}
        foreach ($f in @(@{ Name = $srcFabricName; Location = 'Sweden Central' }, @{ Name = $dstFabricName; Location = 'North Europe' })) {
            $fabric = Get-AzRecoveryServicesAsrFabric | Where-Object { $_.Name -eq $f.Name }
            if (-not $fabric) {
                Wait-LabAsrJob -Job (New-AzRecoveryServicesAsrFabric -Azure -Location $f.Location -Name $f.Name) -Label "Fabric $($f.Name)" | Out-Null
                $fabric = Get-AzRecoveryServicesAsrFabric | Where-Object { $_.Name -eq $f.Name }
            }
            $fabrics[$f.Name] = $fabric
        }
        $containers = @{}
        foreach ($c in @(@{ Name = $srcContainerName; Fabric = $srcFabricName }, @{ Name = $dstContainerName; Fabric = $dstFabricName })) {
            $container = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabrics[$c.Fabric] | Where-Object { $_.Name -eq $c.Name }
            if (-not $container) {
                Wait-LabAsrJob -Job (New-AzRecoveryServicesAsrProtectionContainer -InputObject $fabrics[$c.Fabric] -Name $c.Name) -Label "Container $($c.Name)" | Out-Null
                $container = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabrics[$c.Fabric] | Where-Object { $_.Name -eq $c.Name }
            }
            $containers[$c.Name] = $container
        }
        $policy = Get-AzRecoveryServicesAsrPolicy | Where-Object { $_.Name -eq $policyName }
        if (-not $policy) {
            Wait-LabAsrJob -Job (New-AzRecoveryServicesAsrPolicy -AzureToAzure -Name $policyName `
                    -RecoveryPointRetentionInHours 24 -ApplicationConsistentSnapshotFrequencyInHours 4) -Label "Policy $policyName" | Out-Null
            $policy = Get-AzRecoveryServicesAsrPolicy | Where-Object { $_.Name -eq $policyName }
        }
        $mappings = @{}
        foreach ($m in @(@{ Name = $srcToDstName; From = $srcContainerName; To = $dstContainerName }, @{ Name = $dstToSrcName; From = $dstContainerName; To = $srcContainerName })) {
            $mapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $containers[$m.From] | Where-Object { $_.Name -eq $m.Name }
            if (-not $mapping) {
                Wait-LabAsrJob -Job (New-AzRecoveryServicesAsrProtectionContainerMapping -Name $m.Name -Policy $policy `
                        -PrimaryProtectionContainer $containers[$m.From] -RecoveryProtectionContainer $containers[$m.To]) -Label "Mapping $($m.Name)" | Out-Null
                $mapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $containers[$m.From] | Where-Object { $_.Name -eq $m.Name }
            }
            $mappings[$m.Name] = $mapping
        }
        foreach ($n in @(@{ Name = $srcNetMapName; PrimaryFabric = $srcFabricName; Primary = $srcVnet.Id; RecoveryFabric = $dstFabricName; Recovery = $dstVnet.Id },
                @{ Name = $dstNetMapName; PrimaryFabric = $dstFabricName; Primary = $dstVnet.Id; RecoveryFabric = $srcFabricName; Recovery = $srcVnet.Id })) {
            $existing = Get-AzRecoveryServicesAsrNetworkMapping -PrimaryFabric $fabrics[$n.PrimaryFabric] | Where-Object { $_.Name -eq $n.Name }
            if (-not $existing) {
                Wait-LabAsrJob -Job (New-AzRecoveryServicesAsrNetworkMapping -AzureToAzure -Name $n.Name `
                        -PrimaryFabric $fabrics[$n.PrimaryFabric] -PrimaryAzureNetworkId $n.Primary `
                        -RecoveryFabric $fabrics[$n.RecoveryFabric] -RecoveryAzureNetworkId $n.Recovery) -Label "Network mapping $($n.Name)" | Out-Null
            }
        }
        Write-Host "  ✓ Fabrics, containers, policy $policyName, container and network mappings" -ForegroundColor Green

        Write-Host "`n[4/6] Enabling replication of $vmName..." -ForegroundColor Yellow
        $diskConfigs = @()
        $disks = @([pscustomobject]@{ Id = $vm.StorageProfile.OsDisk.ManagedDisk.Id; Type = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType }) +
            @($vm.StorageProfile.DataDisks | ForEach-Object { [pscustomobject]@{ Id = $_.ManagedDisk.Id; Type = $_.ManagedDisk.StorageAccountType } })
        foreach ($disk in $disks) {
            $diskType = if ($disk.Type) { "$($disk.Type)" } else { 'StandardSSD_LRS' }
            $diskConfigs += New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $cache.Id `
                -DiskId $disk.Id -RecoveryResourceGroupId $rg.ResourceId `
                -RecoveryReplicaDiskAccountType $diskType -RecoveryTargetDiskAccountType $diskType
        }
        $job = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure -AzureVmId $vm.Id -Name $vmName `
            -ProtectionContainerMapping $mappings[$srcToDstName] -AzureToAzureDiskReplicationConfiguration $diskConfigs `
            -RecoveryResourceGroupId $rg.ResourceId
        Wait-LabAsrJob -Job $job -Label "Enable replication of $vmName" | Out-Null
        Write-Host "  ✓ Replication enabled" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        if ("$_" -match 'RequestDisallowedByPolicy') {
            Write-Host "  A Lab 1.3 policy denied a resource. Every resource goes into '$targetRg', which carries the tags; see Lab 5.2 Troubleshooting." -ForegroundColor Gray
        }
        Exit-Lab -FailureCount 1
    }
} else {
    Write-Host "  ✓ $vmName already has a replication item ($($item.ProtectionState)); not creating another." -ForegroundColor Green
}

Write-Host "`n[5/6] Waiting for Protected (up to $WaitMinutes minutes)..." -ForegroundColor Yellow
$deadline = (Get-Date).AddMinutes($WaitMinutes)
do {
    $item = Get-LabReplicationItem
    if ($item -and $item.ProtectionState -eq 'Protected') { break }
    Write-Host "  $(if ($item) { $item.ProtectionState } else { 'item not listed yet' })" -ForegroundColor Gray
    if ($WaitMinutes -eq 0) { break }
    Start-Sleep -Seconds $PollSeconds
} while ((Get-Date) -lt $deadline)

if (-not $item -or $item.ProtectionState -ne 'Protected') {
    Write-Host "  [ERROR] $vmName is not Protected after $WaitMinutes minutes (state: $(if ($item) { $item.ProtectionState } else { 'no item' }))." -ForegroundColor Red
    Write-Host "  Open the VM's Disaster recovery page or the vault's Replicated items for the error; Lab 5.2 Troubleshooting Issue 7 covers ASRMobilityServiceKernelNotSupportedV2." -ForegroundColor Gray
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Protected, health $($item.ReplicationHealth)" -ForegroundColor Green

# The recovery size defaults to Standard_DC4as_cc_v5, a confidential 4 vCPU size.
try {
    Wait-LabAsrJob -Job (Set-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $item -Size $size) -Label "Failover VM size $size" | Out-Null
    Write-Host "  ✓ Failover VM size set to $size" -ForegroundColor Green
} catch {
    Write-Host "  [WARNING] Could not set the failover VM size to ${size}: $_" -ForegroundColor Yellow
    Write-Host "    The test VM would run in the size Site Recovery chose. Set it on the item's Compute and Network page (Step 5.2.7)." -ForegroundColor Gray
}

if ($TestFailover) {
    Write-Host "`n[6/6] Test failover and cleanup..." -ForegroundColor Yellow
    try {
        $dstVnet = Get-AzVirtualNetwork -ResourceGroupName $targetRg -Name $dstVnetName
        $item = Get-LabReplicationItem
        Wait-LabAsrJob -Job (Start-AzRecoveryServicesAsrTestFailoverJob -ReplicationProtectedItem $item -Direction PrimaryToRecovery `
                -AzureVMNetworkId $dstVnet.Id) -Label 'Test failover' | Out-Null
        $testVm = Get-AzVM -ResourceGroupName $targetRg -Name "$vmName-test" -ErrorAction SilentlyContinue
        Write-Host "  ✓ Test failover succeeded; test VM $(if ($testVm) { "'$($testVm.Name)' ($($testVm.HardwareProfile.VmSize))" } else { 'not found in the target group' })" -ForegroundColor Green
        $item = Get-LabReplicationItem
        Wait-LabAsrJob -Job (Start-AzRecoveryServicesAsrTestFailoverCleanupJob -ReplicationProtectedItem $item -Comment 'Lab 5.2 test failover') -Label 'Test failover cleanup' | Out-Null
        Write-Host "  ✓ Test failover cleaned up" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
} else {
    Write-Host "`n[6/6] Test failover skipped; run with -TestFailover or use Step 5.2.7." -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Site Recovery Ready" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Exit-Lab -FailureCount 0
