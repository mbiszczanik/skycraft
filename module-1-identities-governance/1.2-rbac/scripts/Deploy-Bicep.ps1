<#
.SYNOPSIS
    Deploys the Lab 1.2 infrastructure (Resource Groups, optionally RBAC role assignments) using Bicep.

.DESCRIPTION
    This script deploys the required resource groups for SkyCraft Lab 1.2 using the
    'resource-groups.bicep' template. It targets the subscription scope.

    With -IncludeRoleAssignments it also deploys 'role-assignments.bicep': the four Entra
    principal IDs the template requires are resolved from the directory (the Lab 1.1 users and
    groups) and passed as parameter overrides, so the declarative path is usable without copying
    object IDs by hand. The AVM role-assignment modules name each assignment with a deterministic
    guid() of scope, role and principal, so a second run is a no-op.

    The imperative alternative, New-LabRoleAssignment.ps1, creates the same five assignments
    through New-AzRoleAssignment under different names. The two paths do not adopt each other's
    assignments: this script skips the template when all five already exist (whichever path
    created them), and a partial overlap surfaces as RoleAssignmentExists from ARM.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER IncludeRoleAssignments
    Also deploys role-assignments.bicep after the resource groups. Requires Lab 1.1's users and
    groups to exist and an Az context that can read Entra ID (Get-AzADUser / Get-AzADGroup).

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the three resource groups to Sweden Central.

.EXAMPLE
    .\Deploy-Bicep.ps1 -IncludeRoleAssignments
    Deploys the resource groups, then the five role assignments with principal IDs resolved from Entra ID.

.EXAMPLE
    .\Deploy-Bicep.ps1 -IncludeRoleAssignments -WhatIf
    Previews both deployments without creating anything.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [switch]$IncludeRoleAssignments,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# --- Principal resolution (issue #81) ------------------------------------------------------
# role-assignments.bicep takes principal IDs, not names: Bicep cannot query Entra ID. The lookups
# below are the ones New-LabRoleAssignment.ps1 performs through the Microsoft.Graph module, done
# here through Az.Resources (Get-AzADUser / Get-AzADGroup call Microsoft Graph with the Az
# context's own token) so the script needs one sign-in and no extra module. The member user is
# matched by userPrincipalName prefix rather than by a hard-coded domain, and the guest by mail,
# because a guest's userPrincipalName is rewritten to <alias>_<domain>#EXT#@<tenant> on invitation.
# Absence and ambiguity both throw: assigning Owner to whichever object came back first is worse
# than stopping. Kept as a top-level function so tests/RoleAssignments-DeployPath.Tests.ps1 can
# lift it out with the parser and exercise it without a tenant.
function Resolve-LabPrincipalId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'Group', 'Guest')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    switch ($Type) {
        'Group' { $found = @(Get-AzADGroup -DisplayName $Name -ErrorAction Stop) }
        'Guest' { $found = @(Get-AzADUser -Filter "mail eq '$Name'" -ErrorAction Stop) }
        'User'  { $found = @(Get-AzADUser -Filter "startsWith(userPrincipalName,'$Name@')" -ErrorAction Stop) }
    }

    if ($found.Count -eq 0) {
        throw "$Type '$Name' not found in Entra ID. Complete Lab 1.1 first, and sign in with an account that can read the directory."
    }
    if ($found.Count -gt 1) {
        $ids = ($found | ForEach-Object { $_.Id }) -join ', '
        throw "$Type '$Name' matched $($found.Count) principals ($ids); expected exactly one."
    }

    return [string]$found[0].Id
}

Write-Host "=== Lab 1.2: Infrastructure Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Checking Azure connection..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$subscriptionId = $context.Subscription.Id

# Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\resource-groups.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$roleTemplateFile = Join-Path $PSScriptRoot "..\bicep\role-assignments.bicep"
if ($IncludeRoleAssignments -and -not (Test-Path $roleTemplateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $roleTemplateFile" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

# Resolve the principals before anything is deployed: a missing Lab 1.1 user should stop the run
# before the resource groups exist, not after.
$principal = $null
if ($IncludeRoleAssignments) {
    Write-Host "`nResolving Entra ID principals for role-assignments.bicep..." -ForegroundColor Cyan
    try {
        $principal = [ordered]@{
            parAdminPrincipalId          = Resolve-LabPrincipalId -Type User  -Name 'malfurion.stormrage'
            parDeveloperGroupPrincipalId = Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers'
            parTesterGroupPrincipalId    = Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Testers'
            parPartnerPrincipalId        = Resolve-LabPrincipalId -Type Guest -Name 'illidan@externalcompany.com'
        }
        foreach ($entry in $principal.GetEnumerator()) {
            Write-Host "  $($entry.Key): $($entry.Value)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  -> [ERROR] $_" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }
}

$deploymentName = "Lab-1.2-RBAC-RG-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  DeploymentName: $deploymentName" -ForegroundColor Gray

try {
    $deployParams = @{
        Name         = $deploymentName
        Location     = $Location
        TemplateFile = $templateFile
        ErrorAction  = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
    }
    else {
        $deployment = New-AzSubscriptionDeployment @deployParams

        if ($deployment.ProvisioningState -ne 'Succeeded') {
            Write-Host "  -> [FAILED] Deployment finished with state: $($deployment.ProvisioningState)" -ForegroundColor Red
            $Host.SetShouldExit(1)
            exit 1
        }

        Write-Host "  -> [SUCCESS] Resource Groups deployed successfully." -ForegroundColor Green

        # Verify RGs
        foreach($rg in $rgs) {
            if(Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
                 Write-Host "     - Verified: $rg exists" -ForegroundColor Green
            } else {
                 Write-Host "     - Warning: $rg not found after deployment" -ForegroundColor Yellow
            }
        }
    }
}
catch {
    Write-Host "  -> [ERROR] Deployment failed: $_" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

if (-not $IncludeRoleAssignments) {
    if ($WhatIf) { exit 0 }
    Write-Host "`nDeployment Complete." -ForegroundColor Green
    exit 0
}

# --- Role assignments ----------------------------------------------------------------------
$roleDeploymentName = "Lab-1.2-RBAC-Roles-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Role Assignment Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $roleTemplateFile" -ForegroundColor Gray
Write-Host "  DeploymentName: $roleDeploymentName" -ForegroundColor Gray

# The five assignments the template declares, in the shape Get-AzRoleAssignment filters on. Kept
# in step with the template by hand; Test-Lab.ps1 asserts the same five.
$desired = @(
    @{ ObjectId = $principal.parAdminPrincipalId;          Role = 'Owner';       Scope = "/subscriptions/$subscriptionId" }
    @{ ObjectId = $principal.parDeveloperGroupPrincipalId; Role = 'Contributor'; Scope = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg" }
    @{ ObjectId = $principal.parTesterGroupPrincipalId;    Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg" }
    @{ ObjectId = $principal.parTesterGroupPrincipalId;    Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/prod-skycraft-swc-rg" }
    @{ ObjectId = $principal.parPartnerPrincipalId;        Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/platform-skycraft-swc-rg" }
)

try {
    # The RG-scoped modules need their resource groups to exist. After a real deployment they do;
    # under -WhatIf on a fresh subscription they do not, and ARM cannot preview into a group that
    # is not there.
    $missingRg = @($rgs | Where-Object { -not (Get-AzResourceGroup -Name $_ -ErrorAction SilentlyContinue) })
    if ($missingRg) {
        Write-Host "  -> [SKIP] Cannot preview role assignments: resource group(s) not found: $($missingRg -join ', ')." -ForegroundColor Yellow
        Write-Host "     Deploy the resource groups first, then re-run with -IncludeRoleAssignments -WhatIf." -ForegroundColor Yellow
        exit 0
    }

    # Get-AzRoleAssignment -Scope also returns assignments inherited from above, so match the
    # scope exactly: a Reader at subscription level is not the RG-level Reader the template makes.
    $existingCount = 0
    foreach ($item in $desired) {
        $scope = $item.Scope
        $match = @(Get-AzRoleAssignment -ObjectId $item.ObjectId -RoleDefinitionName $item.Role -Scope $scope -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $scope })
        if ($match.Count -gt 0) { $existingCount++ }
    }
    Write-Host "  Existing assignments: $existingCount of $($desired.Count)" -ForegroundColor Gray

    $roleParams = @{
        Name         = $roleDeploymentName
        Location     = $Location
        TemplateFile = $roleTemplateFile
        ErrorAction  = 'Stop'
    }
    foreach ($entry in $principal.GetEnumerator()) { $roleParams[$entry.Key] = $entry.Value }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @roleParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    if ($existingCount -eq $desired.Count) {
        Write-Host "  -> [SKIP] All $($desired.Count) role assignments already exist - nothing to deploy." -ForegroundColor Yellow
    }
    else {
        $roleDeployment = New-AzSubscriptionDeployment @roleParams

        if ($roleDeployment.ProvisioningState -ne 'Succeeded') {
            Write-Host "  -> [FAILED] Deployment finished with state: $($roleDeployment.ProvisioningState)" -ForegroundColor Red
            $Host.SetShouldExit(1)
            exit 1
        }

        Write-Host "  -> [SUCCESS] Role assignments deployed successfully." -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Role assignment deployment failed: $_" -ForegroundColor Red
    if ("$_" -match 'RoleAssignmentExists') {
        Write-Host "     An assignment for the same principal, role and scope exists under a name this template does not own -" -ForegroundColor Yellow
        Write-Host "     typically one created by New-LabRoleAssignment.ps1 or in the portal. Remove it, or keep using that path." -ForegroundColor Yellow
    }
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nDeployment Complete." -ForegroundColor Green
