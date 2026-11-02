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
       A vault Bicep made has no vaultExtendedInfo, which Set-AzRecoveryServicesAsrVaultContext
       needs: the script adds it first (a PUT, no resource, no cost)
    2. Return at once when the vault already holds a replication item for the VM
    3. Create what replication needs, each only when missing: the tagged target VNet with the
       world subnet, the cache storage account in Sweden Central, the two fabrics and protection
       containers, the 24-hour replication policy, both container mappings and both network
       mappings
    4. Enable replication of the VM's disks into the target group
    5. Wait until the item reads Protected (the initial replication of the two disks took 45 to 70
       minutes), then set the failover VM size: the source VM's size when the subscription may
       use it in North Europe and has the quota, else the nearest size it may use. Site Recovery's
       own pick (Standard_HC44rs, 44 cores) fails the test failover on the core quota, and a size
       the subscription is barred from is refused with an empty size name
    6. With -TestFailover only (Step 5.2.7 is optional): run a test failover into the target VNet,
       wait for the test VM, then clean it up. The lab's end state is the Protected replication

    Exit code 1 when a prerequisite is missing, a job fails or the wait ends before Protected, or
    -TestFailover finds no size it can set; 0 otherwise. A job that ends PartiallySucceeded is a
    warning: the wait for Protected decides.

.PARAMETER Force
    Skip the confirmation prompt, for Deploy-Bicep.ps1 and the lab cycle. Without it, a session
    that cannot prompt exits 1 and creates nothing.

.PARAMETER TestFailover
    After Protected, run the optional test failover of Step 5.2.7 and its cleanup. The size it
    starts must be offered to the subscription in North Europe and fit its core quota; a Free
    Trial subscription often cannot (see Troubleshooting, Issue 9). With no size that fits, the
    script stops with exit code 1 and a message before it starts anything.

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
    Version: 1.1.0
    Date: 2026-10-31
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
        if ($Job.State -in @('Succeeded', 'Failed', 'Cancelled', 'CompletedWithInformation', 'PartiallySucceeded')) { break }
        Start-Sleep -Seconds ([Math]::Min($PollSeconds, 10))
    } while ((Get-Date) -lt $deadline)
    $detail = @($Job.Errors | ForEach-Object { $_.ServiceErrorDetails.Message }) -join '; '
    # PartiallySucceeded: a task failed and was retried (Enable replication showed an Entra 401 while the
    # Mobility service installed) and the job went on; the wait for Protected decides whether it worked.
    if ($Job.State -eq 'PartiallySucceeded') {
        Write-Host "  [WARNING] $Label finished PartiallySucceeded$(if ($detail) { ": $detail" }). The wait for Protected decides whether it worked." -ForegroundColor Yellow
    } elseif ($Job.State -notin @('Succeeded', 'CompletedWithInformation')) {
        throw "$Label ended $($Job.State)$(if ($detail) { ": $detail" })"
    }
    return $Job
}

function Get-LabSkuCapability {
    param($Sku, [string]$Name)
    return ($Sku.Capabilities | Where-Object { $_.Name -eq $Name } | Select-Object -First 1).Value
}

# Sizes to try for the failover VM, best first: the source size when the subscription may use it in the
# target region and has the quota, else the nearest size it may. Site Recovery's own default is
# Standard_HC44rs (44 cores, over the usual 4-core quota). It rejects a size the subscription may not
# use, and every confidential size (DC, EC; five tried live), with 'The selected VM size '''' does not
# support disk controller type': those are skipped here (issue #366).
function Get-LabFailoverSize {
    param([string]$SourceSize, [string]$SourceLocation, [string]$TargetLocation, [string]$Generation)
    $sourceSku = Get-AzComputeResourceSku -Location $SourceLocation | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $SourceSize } | Select-Object -First 1
    $sourceCpu = if ($sourceSku) { [int](Get-LabSkuCapability -Sku $sourceSku -Name 'vCPUs') } else { 0 }
    $sourceMemory = if ($sourceSku) { [double](Get-LabSkuCapability -Sku $sourceSku -Name 'MemoryGB') } else { 0 }
    $free = @{}
    foreach ($usage in @(Get-AzVMUsage -Location $TargetLocation)) { $free[$usage.Name.Value] = [int]($usage.Limit - $usage.CurrentValue) }
    $usable = @(Get-AzComputeResourceSku -Location $TargetLocation | Where-Object {
            $_.ResourceType -eq 'virtualMachines' -and -not @($_.Restrictions | Where-Object { "$($_.Type)" -eq 'Location' })
        } | ForEach-Object {
            $cpu = [int](Get-LabSkuCapability -Sku $_ -Name 'vCPUs')
            $controllers = "$(Get-LabSkuCapability -Sku $_ -Name 'DiskControllerTypes')"
            $fits = $cpu -le $free['cores'] -and (-not $_.Family -or -not $free.ContainsKey($_.Family) -or $cpu -le $free[$_.Family])
            [pscustomobject]@{
                Name         = $_.Name
                Cpu          = $cpu
                Memory       = [double](Get-LabSkuCapability -Sku $_ -Name 'MemoryGB')
                Compatible   = $fits -and "$(Get-LabSkuCapability -Sku $_ -Name 'HyperVGenerations')" -match $Generation -and
                    (-not $controllers -or $controllers -match 'SCSI') -and -not (Get-LabSkuCapability -Sku $_ -Name 'GPUs') -and
                    -not (Get-LabSkuCapability -Sku $_ -Name 'ConfidentialComputingType')
            }
        } | Where-Object { $_.Compatible })
    $sourceUsable = @($usable | Where-Object { $_.Name -eq $SourceSize })
    $nearest = @($usable | Where-Object { $_.Name -ne $SourceSize -and $_.Cpu -ge $sourceCpu -and $_.Memory -ge $sourceMemory } |
            Sort-Object Cpu, Memory, Name)
    return @($sourceUsable + $nearest | Select-Object -First 3)
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
# A Bicep-made vault has no vaultExtendedInfo (Portal and PowerShell vaults do) and
# Set-AzRecoveryServicesAsrVaultContext throws a NullReferenceException on it; main.bicep cannot add it.
try {
    $extInfoPath = "$($vault.ID)/extendedInformation/vaultExtendedInfo?api-version=2016-06-01"
    $extInfo = Invoke-AzRestMethod -Method GET -Path $extInfoPath
    if ($extInfo.StatusCode -eq 404) {
        $integrityKey = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        $body = @{ properties = @{ algorithm = 'None'; integrityKey = $integrityKey } } | ConvertTo-Json -Depth 3 -Compress
        $put = Invoke-AzRestMethod -Method PUT -Path $extInfoPath -Payload $body
        if ($put.StatusCode -notin 200, 201) { throw "PUT returned $($put.StatusCode): $($put.Content)" }
        Write-Host "  ✓ Created the vault's extended information (a Bicep-made vault has none)" -ForegroundColor Green
    } elseif ($extInfo.StatusCode -ne 200) {
        throw "GET returned $($extInfo.StatusCode): $($extInfo.Content)"
    }
    Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
} catch {
    Write-Host "[ERROR] Could not prepare vault '$vaultName' for Site Recovery: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
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
            [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', "Replicate $vmName to North Europe. The initial replication takes about 45 to 75 minutes and the replica disks, cache account and instance fee are billed until Remove-LabResource.ps1 runs.")
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
$waitStart = Get-Date
do {
    $item = Get-LabReplicationItem
    if ($item -and $item.ProtectionState -eq 'Protected') { break }
    $waited = [int][Math]::Floor(((Get-Date) - $waitStart).TotalMinutes)
    Write-Host "  Waiting for Protected (state: $(if ($item) { $item.ProtectionState } else { 'item not listed yet' }), $waited min of $WaitMinutes)" -ForegroundColor Gray
    if ($WaitMinutes -eq 0) { break }
    Start-Sleep -Seconds $PollSeconds
} while ((Get-Date) -lt $deadline)

if (-not $item -or $item.ProtectionState -ne 'Protected') {
    Write-Host "  [ERROR] $vmName is not Protected after $WaitMinutes minutes (state: $(if ($item) { $item.ProtectionState } else { 'no item' }))." -ForegroundColor Red
    Write-Host "  Open the VM's Disaster recovery page or the vault's Replicated items for the error; Lab 5.2 Troubleshooting Issue 7 covers ASRMobilityServiceKernelNotSupportedV2." -ForegroundColor Gray
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Protected, health $($item.ReplicationHealth)" -ForegroundColor Green

# Site Recovery picks Standard_HC44rs, and a test failover then fails on the core quota.
$failoverSize = $null
try {
    $generation = (Get-AzVM -ResourceGroupName $vmRg -Name $vmName -Status).HyperVGeneration
    $candidates = @(Get-LabFailoverSize -SourceSize $size -SourceLocation $srcLocation -TargetLocation $dstLocation -Generation $(if ($generation) { $generation } else { 'V2' }))
    if ($candidates.Count -eq 0 -or $candidates[0].Name -ne $size) {
        Write-Host "  [WARNING] $size is not usable for this subscription in $dstLocation (not offered, or no quota)." -ForegroundColor Yellow
    }
    foreach ($candidate in $candidates) {
        try {
            Wait-LabAsrJob -Job (Set-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $item -Size $candidate.Name) -Label "Failover VM size $($candidate.Name)" | Out-Null
            $failoverSize = $candidate.Name
            Write-Host "  ✓ Failover VM size set to $failoverSize ($($candidate.Cpu) vCPUs, $($candidate.Memory) GB)" -ForegroundColor Green
            break
        } catch {
            Write-Host "  [WARNING] Site Recovery refused $($candidate.Name): $_" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  [WARNING] Could not choose a failover VM size: $_" -ForegroundColor Yellow
}
if (-not $failoverSize) {
    Write-Host "  [WARNING] The failover VM size is still Site Recovery's choice ($((Get-LabReplicationItem).RecoveryAzureVMSize)). Set an offered size under the item's General > Compute > Edit (Step 5.2.7)." -ForegroundColor Yellow
    if ($TestFailover) {
        Write-Host "  [ERROR] No failover size could be set, so a test failover would start that size and fail on the core quota. Nothing was started." -ForegroundColor Red
        Write-Host "    No size that this subscription may use in $dstLocation fits the free core quota and is accepted by Site Recovery (confidential sizes are refused). Ask for core quota there, or use a subscription that offers $size." -ForegroundColor Gray
        Exit-Lab -FailureCount 1
    }
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
    Write-Host "`n[6/6] Test failover skipped (optional); run with -TestFailover or use Step 5.2.7 if your subscription can start the failover VM." -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Site Recovery Ready" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Exit-Lab -FailureCount 0
