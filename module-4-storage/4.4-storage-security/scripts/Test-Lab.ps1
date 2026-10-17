<#
.SYNOPSIS
    Validates Lab 4.4 Storage Security
.DESCRIPTION
    Checks for Storage Firewall settings, Service Endpoints, and the container of the SAS
    exercise with its stored access policy.

    The container is found through what it holds, not by name (issue #355): step 4.4.3 lets the
    learner pick any container and names only the policy, DevRevokePolicy, while the Bicep path
    creates the container dev-assets without a policy. Containers are listed through the control
    plane, which the storage firewall does not block; their stored access policies are data-plane
    reads. A lookup that fails is a counted [FAIL] that says why.
.PARAMETER Environment
    Environment to validate (prod or dev). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage, Az.Network

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'
$failCount = 0

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$vnetName           = "$Environment-skycraft-swc-vnet"

Write-Host "=== Lab 4.4: Validating Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 2. Check Storage Firewall
$sa = $null
try {
    Write-Host "Checking Storage Firewall for '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop

    if ($sa.NetworkRuleSet.DefaultAction -eq 'Deny') {
        Write-Host "  -> Firewall is correctly set to 'Deny' by default." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] Firewall default action is '$($sa.NetworkRuleSet.DefaultAction)'. Expected: Deny." -ForegroundColor Red
        $failCount++
    }

    if ($sa.NetworkRuleSet.VirtualNetworkRules.Count -gt 0) {
        Write-Host "  -> Found $($sa.NetworkRuleSet.VirtualNetworkRules.Count) Virtual Network rules." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] No Virtual Network rules found." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve storage account '$storageAccountName'." -ForegroundColor Red
    $failCount++
}

# 3. Check Service Endpoint on WorldSubnet (not ApplicationSubnet — the deployed subnet is WorldSubnet)
try {
    Write-Host "Checking Service Endpoint on '$vnetName' / WorldSubnet..." -ForegroundColor Yellow
    $vnet       = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $worldSubnet = $vnet.Subnets | Where-Object { $_.Name -eq 'WorldSubnet' }

    if ($worldSubnet) {
        if ($worldSubnet.ServiceEndpoints.Service -contains 'Microsoft.Storage') {
            Write-Host "  -> Service Endpoint 'Microsoft.Storage' is enabled on WorldSubnet." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAIL] Service Endpoint 'Microsoft.Storage' is NOT enabled on WorldSubnet." -ForegroundColor Red
            $failCount++
        }
    }
    else {
        Write-Host "  -> [FAIL] WorldSubnet not found in '$vnetName'." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve VNet '$vnetName'." -ForegroundColor Red
    $failCount++
}

# 4. The container of the SAS exercise, found through its stored access policy (#355)
# Step 4.4.3 names the policy, not the container ("any container"); the Bicep path creates
# 'dev-assets' and no policy. So the lab's container is the one holding the guide's policy, or
# 'dev-assets' when no container holds it. Step 4.4.4 deletes the policy at its end, after which
# a Portal-built lab leaves nothing that marks its container: that case is reported, not counted.
$policyName        = 'DevRevokePolicy'
$bicepContainerName = 'dev-assets'
if ($sa) {
    Write-Host "Checking the SAS exercise container and stored access policy '$policyName'..." -ForegroundColor Yellow
    $containers = $null
    try {
        # Control plane: the storage firewall does not block it, so the listing works from anywhere.
        $containers = @(Get-AzRmStorageContainer -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction Stop | Where-Object { $_ })
    }
    catch {
        Write-Host "  -> [FAIL] Could not list the containers of '$storageAccountName': $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }

    if ($null -ne $containers) {
        $holders    = @()
        $readErrors = @()
        foreach ($container in $containers) {
            try {
                # Data plane: blocked by the firewall unless step 4.4.2 allowed your client IP.
                $policies = @(Get-AzStorageContainerStoredAccessPolicy -Container $container.Name -Context $sa.Context -ErrorAction Stop | Where-Object { $_ })
            }
            catch {
                $readErrors += "$($container.Name): $($_.Exception.Message)"
                continue
            }
            foreach ($policy in $policies) {
                # The returned object names the policy in .Policy (there is no .Id).
                $permissions = if ($policy.PSObject.Properties['Permissions']) { $policy.Permissions } else { $policy.Permission }
                Write-Host "  -> Found stored access policy '$($policy.Policy)' (permissions: $permissions) on container '$($container.Name)'." -ForegroundColor Gray
                if ($policy.Policy -eq $policyName) { $holders += $container.Name }
            }
        }

        if ($holders.Count -gt 0) {
            Write-Host "  -> Container '$($holders -join "', '")' holds stored access policy '$policyName'." -ForegroundColor Green
        }
        elseif ($containers.Name -contains $bicepContainerName) {
            Write-Host "  -> Container '$bicepContainerName' found (the Bicep path's container); no container holds '$policyName'." -ForegroundColor Green
        }
        elseif ($readErrors.Count -gt 0) {
            Write-Host "  -> [FAIL] No container holds '$policyName' among those readable, and the stored access policies of $($readErrors.Count) container(s) could not be read (is your client IP allowed, step 4.4.2?): $($readErrors -join '; ')" -ForegroundColor Red
            $failCount++
        }
        else {
            Write-Host "  -> [INFO] No container holds stored access policy '$policyName', and '$bicepContainerName' does not exist. Step 4.4.3 creates the policy and step 4.4.4 deletes it again, so after step 4.4.4 nothing is left to check. Not counted." -ForegroundColor Gray
        }
    }
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
$Host.SetShouldExit($failCount)
exit $failCount
