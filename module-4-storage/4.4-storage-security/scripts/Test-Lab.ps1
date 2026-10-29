<#
.SYNOPSIS
    Validates Lab 4.4 Storage Security
.DESCRIPTION
    Checks the state every path of Lab 4.4 leaves - the Portal steps, the guide's Az PowerShell
    blocks or the Bicep (issue #362):

      - the storage account is provisioned (not left Failed, issue #371);
      - its firewall denies by default and has a virtual network rule for WorldSubnet (Step 4.4.2);
      - WorldSubnet carries the Microsoft.Storage service endpoint (Lab 2.2, checked in Step 4.4.1);
      - the container of the SAS exercise, dev-assets, exists (Step 4.4.3);
      - Storage Blob Data Contributor is assigned on the account itself (Step 4.4.7).

    The container is listed through the control plane, which the storage firewall does not block.
    Its stored access policies are data-plane reads: the script prints every policy it finds by
    name, and accepts a container that holds the guide's policy, DevRevokePolicy, as the exercise
    container when dev-assets is missing - a learner who followed an older guide picked any
    container (issue #355). Step 4.4.4 deletes the policy again, so its absence is no failure.

    The key rotation of Steps 4.4.5 and 4.4.6 is reported, not counted: a rotation is an operation
    with no Bicep counterpart, so the Bicep path never shows it. The client IP rule is reported
    too: the Bicep path adds one only when it can detect the address.

    A lookup that fails is a counted [FAIL] that says why. The script ends through Exit-Lab.
.PARAMETER Environment
    Environment to validate (prod or dev). Default: prod.
.PARAMETER StorageAccountName
    The storage account. Default: '<Environment>skycraftswcsa'. Pass the name given to
    Deploy-Bicep.ps1.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-10-18
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Storage, Az.Network

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod',

    # The default reads $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName = "${Environment}skycraftswcsa"
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
$failCount = 0

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$vnetName           = "$Environment-skycraft-swc-vnet"
$subnetName         = 'WorldSubnet'

Write-Host "=== Lab 4.4: Validating Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; Exit-Lab -FailureCount 1
}

# 2. The storage account and its firewall (Step 4.4.2)
$sa = $null
try {
    Write-Host "Checking Storage Firewall for '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve storage account '$storageAccountName': $($_.Exception.Message)" -ForegroundColor Red
    $failCount++
}

if ($sa) {
    # A storage account Azure left in a Failed state passes every settings check below (#371).
    if ("$($sa.ProvisioningState)" -eq 'Succeeded') {
        Write-Host "  -> Storage account is provisioned (Succeeded)." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] Storage account provisioning state is '$($sa.ProvisioningState)'. Expected: Succeeded." -ForegroundColor Red
        $failCount++
    }

    if ($sa.NetworkRuleSet.DefaultAction -eq 'Deny') {
        Write-Host "  -> Firewall is correctly set to 'Deny' by default." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] Firewall default action is '$($sa.NetworkRuleSet.DefaultAction)'. Expected: Deny (Step 4.4.2, 'Enabled from selected networks')." -ForegroundColor Red
        $failCount++
    }

    # The Portal may store the subnet id in another case than the Bicep, so the match ignores case.
    $vnetRules  = @($sa.NetworkRuleSet.VirtualNetworkRules | Where-Object { $_ })
    $worldRules = @($vnetRules | Where-Object { "$($_.VirtualNetworkResourceId)" -like "*/virtualNetworks/$vnetName/subnets/$subnetName" })
    if ($worldRules.Count -eq 0) {
        Write-Host "  -> [FAIL] No virtual network rule for '$vnetName/$subnetName' ($($vnetRules.Count) rule(s) in total). Step 4.4.2 adds it." -ForegroundColor Red
        $failCount++
    }
    else {
        # A rule whose subnet lost its service endpoint is kept with another state; a rule still
        # being applied is 'Provisioning'. Either way the subnet is not let through yet.
        $state = "$($worldRules[0].State)"
        if ($state -and $state -ne 'Succeeded') {
            Write-Host "  -> [FAIL] The virtual network rule for '$subnetName' is in state '$state'. Expected: Succeeded. Wait a minute and run again; if it stays, check the service endpoint (Step 4.4.1)." -ForegroundColor Red
            $failCount++
        }
        else {
            Write-Host "  -> Virtual network rule for '$vnetName/$subnetName' found." -ForegroundColor Green
        }
    }

    $ipRules = @($sa.NetworkRuleSet.IpRules | Where-Object { $_ })
    Write-Host "  -> [INFO] $($ipRules.Count) IP address rule(s). Step 4.4.2 adds your client IPv4 address; without it the Portal and the PowerShell blocks cannot reach the account's data from your computer. Not counted." -ForegroundColor Gray
}

# 3. Service endpoint on WorldSubnet (Lab 2.2's, checked in Step 4.4.1)
try {
    Write-Host "Checking Service Endpoint on '$vnetName' / $subnetName..." -ForegroundColor Yellow
    $vnet        = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $worldSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $subnetName }

    if ($worldSubnet) {
        if ($worldSubnet.ServiceEndpoints.Service -contains 'Microsoft.Storage') {
            Write-Host "  -> Service Endpoint 'Microsoft.Storage' is enabled on $subnetName." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAIL] Service Endpoint 'Microsoft.Storage' is NOT enabled on $subnetName." -ForegroundColor Red
            $failCount++
        }
    }
    else {
        Write-Host "  -> [FAIL] $subnetName not found in '$vnetName'." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve VNet '$vnetName': $($_.Exception.Message)" -ForegroundColor Red
    $failCount++
}

# 4. The container of the SAS exercise (Step 4.4.3) and the stored access policy it held
# Every path creates 'dev-assets'. Step 4.4.4 deletes the policy again, so the policy is reported,
# not required. A container that holds the policy is accepted in place of dev-assets: guides
# before issue #361 let the learner pick any container (#355).
$policyName    = 'DevRevokePolicy'
$containerName = 'dev-assets'
if ($sa) {
    Write-Host "Checking container '$containerName' and stored access policy '$policyName'..." -ForegroundColor Yellow
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

        if ($containers.Name -contains $containerName) {
            Write-Host "  -> Container '$containerName' found." -ForegroundColor Green
            if ($holders -contains $containerName) {
                Write-Host "  -> [INFO] '$containerName' still holds '$policyName': Step 4.4.4 deletes it at its end. Not counted." -ForegroundColor Gray
            }
            elseif ($readErrors.Count -gt 0) {
                Write-Host "  -> [INFO] The stored access policies of $($readErrors.Count) container(s) could not be read (is your client IP allowed, step 4.4.2?): $($readErrors -join '; '). Not counted." -ForegroundColor Gray
            }
            else {
                Write-Host "  -> [INFO] No container holds '$policyName', as after Step 4.4.4. Not counted." -ForegroundColor Gray
            }
        }
        elseif ($holders.Count -gt 0) {
            Write-Host "  -> Container '$($holders -join "', '")' holds stored access policy '$policyName' (the exercise container of an older guide; Step 4.4.3 now creates '$containerName')." -ForegroundColor Green
        }
        elseif ($readErrors.Count -gt 0) {
            Write-Host "  -> [FAIL] Container '$containerName' not found, and the stored access policies of $($readErrors.Count) container(s) could not be read (is your client IP allowed, step 4.4.2?): $($readErrors -join '; ')" -ForegroundColor Red
            $failCount++
        }
        else {
            Write-Host "  -> [FAIL] Container '$containerName' not found, and no container holds '$policyName'. Step 4.4.3 creates '$containerName'." -ForegroundColor Red
            $failCount++
        }
    }
}

# 5. Storage Blob Data Contributor on the account itself (Step 4.4.7)
# Only an assignment made on the account counts: one inherited from the resource group or the
# subscription is not what the step creates, and the lab's cleanup removes only the account's own.
$roleName = 'Storage Blob Data Contributor'
if ($sa) {
    Write-Host "Checking '$roleName' role assignments on '$storageAccountName'..." -ForegroundColor Yellow
    # The ARM API, not Get-AzRoleAssignment, which needs a Microsoft Graph token (#397).
    try {
        $assignments = @(Get-LabArmRoleAssignment -Scope $sa.Id |
            Where-Object { $_.RoleDefinitionName -eq $roleName -and $_.Scope -eq $sa.Id })
        if ($assignments.Count -gt 0) {
            # Who holds it is not printed: a display name is a real person's name, and an object id
            # identifies the directory. The output may be pasted as evidence, so it names the kind only.
            $kinds = (@($assignments | ForEach-Object { if ($_.ObjectType) { "$($_.ObjectType)" } else { 'Unknown' } }) | Sort-Object -Unique) -join ', '
            Write-Host "  -> '$roleName' is assigned on the account: $($assignments.Count) assignment(s), principal type(s): $kinds." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAIL] No '$roleName' assignment on '$storageAccountName' itself. Step 4.4.7 assigns it to your account." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "  -> [FAIL] Could not read the role assignments of '$storageAccountName': $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# 6. Key rotation (Steps 4.4.5 and 4.4.6): reported, not counted - see the description above.
if ($sa) {
    Write-Host "Checking when the access keys were last rotated..." -ForegroundColor Yellow
    $keyTimes = $sa.KeyCreationTime
    foreach ($key in 'Key1', 'Key2') {
        $created = if ($keyTimes) { $keyTimes.$key } else { $null }
        if (-not $created) {
            Write-Host "  -> [INFO] $($key.ToLower()): Azure reports no creation time. Not counted." -ForegroundColor Gray
        }
        elseif ($sa.CreationTime -and ([datetime]$created - [datetime]$sa.CreationTime).TotalMinutes -lt 5) {
            Write-Host "  -> [INFO] $($key.ToLower()) has not been rotated since the account was created ($created). Steps 4.4.5 and 4.4.6 rotate both keys; the Bicep path cannot. Not counted." -ForegroundColor Gray
        }
        else {
            Write-Host "  -> $($key.ToLower()) last rotated $created." -ForegroundColor Green
        }
    }
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
Exit-Lab -FailureCount $failCount
