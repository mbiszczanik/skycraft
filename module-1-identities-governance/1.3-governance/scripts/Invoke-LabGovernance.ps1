<#
.SYNOPSIS
    Deploys Lab 1.3 Governance artifacts (Tags, Policies, Locks) using imperative PowerShell.

.DESCRIPTION
    This script demonstrates how to apply governance controls using Azure PowerShell cmdlets directly.
    It serves as a "PowerShell Showcase" alternative to the Bicep deployment.
    
    Actions performed:
    1. Applies Tags to Resource Groups (Update-AzTag)
    2. Assigns Azure Policies at Subscription Scope (New-AzPolicyAssignment). An assignment that
       already exists - under the fixed name, or made in the Portal under a generated name with
       the guide's name as display name - is left as it is; one made twice is an [ERROR] and
       nothing is created for it (issue #330).
       Inherit-Project-Tag, the Modify assignment of step 1.3.8 (issue #350), is created with a
       system-assigned managed identity in -Location, and its identity is given the role the
       definition names (Contributor) on the subscription - what the Portal does itself - unless
       it holds it already. The role is used only by a remediation task; a new identity can take
       a minute to replicate, so the grant is retried while Azure reports the principal unknown.
    3. Creating Resource Locks (New-AzResourceLock). A lock that already exists under the guide's
       name but with another level is set to CanNotDelete, and the script says so (issue #258).

.PARAMETER SubscriptionId
    Target Subscription ID. Defaults to current context.

.PARAMETER Owner
    Value for the canonical Owner tag. Default: mbiszczanik.

.PARAMETER Location
    Location of the managed identity of Inherit-Project-Tag (the guide's "System assigned
    identity location"). Default: swedencentral.

.EXAMPLE
    .\Invoke-LabGovernance.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'mbiszczanik',

    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Color output functions
function Write-Success { param([string]$Message) Write-Host "  -> [SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "$Message" -ForegroundColor Yellow }
function Write-Header { param([string]$Message) Write-Host "$Message" -ForegroundColor Cyan }
function Write-Error-Custom { param([string]$Message) Write-Host "  -> [ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Lab 1.3: Governance Deployment (Imperative) ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Connection & Context
try {
    Write-Info "Checking Azure connection..."
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Logging in..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $SubscriptionId = $context.Subscription.Id
    }
    
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "Using Subscription: $($context.Subscription.Name) ($SubscriptionId)" -ForegroundColor Green
}
catch {
    Write-Error-Custom "Failed to connect: $_"
    $Host.SetShouldExit(1)
    exit 1
}

# 2. Apply Tags
Write-Header "`n=== 1. Applying Tags (Update-AzTag) ==="

$tagConfigurations = @(
    @{ Name = "dev-skycraft-swc-rg"; Tags = @{ Environment="Development"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$Owner } },
    @{ Name = "prod-skycraft-swc-rg"; Tags = @{ Environment="Production"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$Owner } },
    @{ Name = "platform-skycraft-swc-rg"; Tags = @{ Environment="Platform"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$Owner } }
)

foreach ($config in $tagConfigurations) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would tag $($config.Name)" -ForegroundColor Yellow
    }
    else {
        try {
            $rg = Get-AzResourceGroup -Name $config.Name -ErrorAction Stop
            # Merge tags
            Update-AzTag -ResourceId $rg.ResourceId -Tag $config.Tags -Operation Merge -ErrorAction Stop | Out-Null
            Write-Success "Tagged $($config.Name)"
        }
        catch {
            Write-Host "  -> [WARN] Failed to tag $($config.Name) (RG might not exist?)" -ForegroundColor Yellow
        }
    }
}

# 3. Assign Policies
Write-Header "`n=== 2. Assigning Policies (New-AzPolicyAssignment) ==="

# The four assignments - names, display names, definition ids - come from
# LabPolicyAssignment.ps1, shared with Test-Lab.ps1 and Remove-LabResource.ps1; the parameters
# are this script's own.
. (Join-Path $PSScriptRoot 'LabPolicyAssignment.ps1')
$policyParams = @{
    'Require-Environment-Tag-RG' = @{ tagName = "Environment" }
    'Enforce-Project-Tag'        = @{ tagName = "Project"; tagValue = "SkyCraft" }
    'Inherit-Project-Tag'        = @{ tagName = "Project" }
    'Restrict-Azure-Regions'     = @{ listOfAllowedLocations = @("swedencentral", "northeurope") }
}
$subscriptionScope = "/subscriptions/$SubscriptionId"

# Gives the managed identity of a Modify assignment the role its definition names, on the
# subscription, unless it holds it there already - what the Portal does when it creates the
# assignment (issue #350). The role is used only by a remediation task: a request-time Modify
# needs none. The role assignments are listed and matched by principal id rather than read with
# -ObjectId, which looks the principal up in Microsoft Graph first. A new identity can take a
# minute to replicate, so the grant is retried while Azure reports the principal unknown.
function Grant-LabPolicyIdentityRole {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $label = Format-LabPolicyAssignment -Assignment $Assignment
    $identity = Get-LabPolicyAssignmentIdentity -Assignment $Assignment
    if (-not $identity.PrincipalId) {
        Write-Error-Custom "$($Spec.Name) $label has no managed identity, so its remediation role cannot be granted. Delete it in the Portal (Policy > Assignments) and run this script again, or follow step $($Spec.Step)."
        return
    }

    $roleGuid = ($Spec.RoleDefinitionId -split '/')[-1]
    try {
        $held = @(Select-LabPolicyIdentityRoleAssignment -RoleAssignment @(Get-AzRoleAssignment -Scope $subscriptionScope -ErrorAction Stop) `
                -PrincipalId $identity.PrincipalId -SubscriptionId $SubscriptionId |
            Where-Object { ([string]$_.Scope).TrimEnd('/') -eq $subscriptionScope -and [string]$_.RoleDefinitionId -eq $roleGuid })
    }
    catch {
        Write-Error-Custom "Could not list the role assignments on the subscription, so the role of $($Spec.Name)'s identity is not granted: $_"
        return
    }
    if ($held.Count -gt 0) {
        Write-Success "Identity of $($Spec.Name) already holds role $roleGuid on the subscription"
        return
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            New-AzRoleAssignment `
                -ObjectId $identity.PrincipalId `
                -ObjectType 'ServicePrincipal' `
                -RoleDefinitionId $roleGuid `
                -Scope $subscriptionScope `
                -ErrorAction Stop | Out-Null
            Write-Success "Granted role $roleGuid on the subscription to the identity of $($Spec.Name)"
            return
        }
        catch {
            if ($attempt -lt 6 -and "$_" -match 'PrincipalNotFound|does not exist in the directory') {
                Write-Host "  -> [WAIT] The identity of $($Spec.Name) is not replicated yet; retrying in 10 seconds ($attempt/5)." -ForegroundColor Gray
                Start-Sleep -Seconds 10
                continue
            }
            Write-Error-Custom "Failed to grant role $roleGuid to the identity of $($Spec.Name): $_"
            return
        }
    }
}

# An assignment the learner made in the Portal has a generated resource name and the guide's
# name as its display name (issue #330). Checking by resource name missed it and created a second
# set next to it, so the subscription's assignments are listed and matched the way the cleanup
# matches them. A listing that fails creates nothing: an assignment it could not see may exist.
$assignments = $null
if (-not $WhatIf) {
    try {
        $assignments = @(Get-AzPolicyAssignment -Scope $subscriptionScope -ErrorAction Stop | Where-Object { $_ })
    }
    catch {
        Write-Error-Custom "Could not list the policy assignments on the subscription, so none is created: $_"
    }
}

foreach ($policy in Get-LabPolicyAssignmentSpec) {
    if ($WhatIf) {
         Write-Host "WHATIF: Would assign policy $($policy.Name)" -ForegroundColor Yellow
         continue
    }
    if ($null -eq $assignments) { continue }

    $found = @(Select-LabPolicyAssignment -Assignment $assignments -SubscriptionId $SubscriptionId -Spec $policy)
    if ($found.Count -eq 1) {
        Write-Success "Policy $($policy.Name) already assigned: $(Format-LabPolicyAssignment -Assignment $found[0])"
        if ($policy.RoleDefinitionId) { Grant-LabPolicyIdentityRole -Assignment $found[0] -Spec $policy }
        continue
    }
    if ($found.Count -gt 1) {
        $foundList = ($found | ForEach-Object { Format-LabPolicyAssignment -Assignment $_ }) -join ', '
        Write-Error-Custom "$($found.Count) assignments match $($policy.Name): $foundList. Not creating another; delete all but one in the Portal (Policy > Assignments)."
        continue
    }

    try {
        # Read by id: a search by display name can pick a custom definition of the same name.
        $def = Get-AzPolicyDefinition -Id $policy.PolicyDefinitionId -ErrorAction Stop
        $assignArgs = @{
            Name                  = $policy.Name
            DisplayName           = $policy.DisplayName
            Scope                 = $subscriptionScope
            PolicyDefinition      = $def
            PolicyParameterObject = $policyParams[$policy.Name]
        }
        # A Modify assignment needs a managed identity, and an identity needs a location.
        if ($policy.ManagedIdentity) {
            $assignArgs.IdentityType = 'SystemAssigned'
            $assignArgs.Location = $Location
        }
        $created = New-AzPolicyAssignment @assignArgs -ErrorAction Stop
        Write-Success "Assigned policy $($policy.Name)"
    }
    catch {
        Write-Error-Custom "Failed to assign $($policy.Name): $_"
        continue
    }
    if ($policy.RoleDefinitionId) { Grant-LabPolicyIdentityRole -Assignment $created -Spec $policy }
}

# 4. Apply Locks
Write-Header "`n=== 3. Applying Locks (New-AzResourceLock) ==="

$locks = @(
    @{ RG = "prod-skycraft-swc-rg"; Name = "lock-no-delete-prod"; Notes = "Cannot delete resource or child resources." },
    @{ RG = "platform-skycraft-swc-rg"; Name = "lock-no-delete-platform"; Notes = "Cannot delete resource or child resources." }
)

foreach ($lock in $locks) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would lock $($lock.RG)" -ForegroundColor Yellow
    }
    else {
        try {
            if (Get-AzResourceGroup -Name $lock.RG -ErrorAction SilentlyContinue) {
                # A lock under this name but with another level (say ReadOnly, made by hand) is not
                # the lock the guide creates, and Test-Lab.ps1 fails it (issue #258). Rather than
                # report it as present, overwrite it in place - New-AzResourceLock -Force on an
                # existing name updates that lock - and say which level it had.
                $existing = @(Get-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -ErrorAction SilentlyContinue | Where-Object { $_ })
                $existingLevels = @($existing | ForEach-Object { $_.Properties.level })
                if ($existingLevels -contains 'CanNotDelete') {
                    Write-Success "Lock $($lock.Name) already exists."
                }
                else {
                    if ($existing.Count -gt 0) {
                        Write-Host "  -> [WARN] Lock $($lock.Name) exists with level $($existingLevels -join ', '); setting it to CanNotDelete." -ForegroundColor Yellow
                    }
                    New-AzResourceLock `
                        -ResourceGroupName $lock.RG `
                        -LockName $lock.Name `
                        -LockLevel CanNotDelete `
                        -LockNotes $lock.Notes `
                        -Force `
                        -ErrorAction Stop | Out-Null
                    if ($existing.Count -gt 0) {
                        Write-Success "Set $($lock.Name) on $($lock.RG) to CanNotDelete"
                    }
                    else {
                        Write-Success "Locked $($lock.RG)"
                    }
                }
            }
            else {
                Write-Host "  -> [WARN] RG $($lock.RG) not found, skipping lock." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error-Custom "Failed to lock $($lock.RG): $_"
        }
    }
}

Write-Host "`nImperative Deployment Complete." -ForegroundColor Green
