<#
.SYNOPSIS
    Deploys the Lab 1.2 infrastructure (Resource Groups, optionally RBAC role assignments) using Bicep.

.DESCRIPTION
    This script deploys the required resource groups for SkyCraft Lab 1.2 using the
    'resource-groups.bicep' template. It targets the subscription scope.

    With -IncludeRoleAssignments it also deploys 'role-assignments.bicep': the four Entra
    principal IDs the template requires are resolved from the directory (the Lab 1.1 users and
    groups) and passed as parameter overrides, so the declarative path is usable without copying
    object IDs by hand. Lab 1.1's user is looked up on the tenant's initial *.onmicrosoft.com
    domain, where Lab 1.1 creates it; when the tenant lists no initial domain the script stops
    with [ERROR] and exit code 1 before anything is deployed. The AVM role-assignment modules
    name each assignment with a deterministic guid() of scope, role and principal, so a second
    run is a no-op.

    The Portal and the imperative alternative, New-LabRoleAssignment.ps1, create the same five
    assignments under random names, and ARM refuses a second assignment of one principal, role
    and scope (RoleAssignmentExists). So before the preview or the deployment the script reads
    which of the five exist, at their exact scope and whatever their name (issue #406), prints
    "Existing assignments: n of 5" and one line per assignment:
      [KEEP]    it exists; the template leaves it as it is (parExistingAssignments)
      [CREATE]  it does not; the template creates it
    When all five exist, the script says so and neither previews nor deploys the template. A
    read that fails stops the script with [ERROR] and exit code 1 before anything is deployed, and
    so does an Owner for Malfurion that has a condition: it is not the lab's, and ARM keeps no
    second one beside it (guide Troubleshooting, Issue 6).

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER IncludeRoleAssignments
    Also deploys role-assignments.bicep after the resource groups. Requires Lab 1.1's users and
    groups to exist and an Az context that can read Entra ID (Get-AzADUser / Get-AzADGroup, and
    the tenant's domains through Invoke-AzRestMethod), which needs Microsoft Graph through the Az
    sign-in's Graph token. Where the tenant asks for interaction before it issues that token, sign
    in with 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId' first; a failed lookup
    says so. The existing assignments are read through the Azure Resource Manager API, which needs
    no Graph (issue #397); only the missing ones are previewed and deployed (issue #406).

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the three resource groups to Sweden Central.

.EXAMPLE
    .\Deploy-Bicep.ps1 -IncludeRoleAssignments
    Deploys the resource groups, then those of the five role assignments that do not exist yet,
    with principal IDs resolved from Entra ID.

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
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
# The module's role assignment helpers use the ARM API, not Microsoft Graph (#397).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# --- Principal resolution (issue #81) ------------------------------------------------------
# role-assignments.bicep takes principal IDs, not names: Bicep cannot query Entra ID. The lookups
# below are the ones New-LabRoleAssignment.ps1 performs through the Microsoft.Graph module, done
# here through Az.Resources (Get-AzADUser / Get-AzADGroup call Microsoft Graph with the Az
# context's own token) so the script needs one sign-in and no extra module. The member user is
# matched by its full userPrincipalName on the tenant's initial domain, where Lab 1.1 creates it
# (issue #237; see Select-LabInitialDomain below), and the guest by mail, because a guest's
# userPrincipalName is rewritten to <alias>_<domain>#EXT#@<tenant> on invitation. Absence and
# ambiguity both throw: assigning Owner to whichever object came back first is worse than
# stopping. A lookup that fails throws with the sign-in that provides Microsoft Graph
# (Get-LabGraphSignInHint, issue #397); absence and ambiguity do not name it, because signing in
# again does not change what the directory holds. Kept as top-level functions so
# tests/RoleAssignments-DeployPath.Tests.ps1 can lift them out with the parser and exercise them
# without a tenant.
function Resolve-LabPrincipalId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'Group', 'Guest')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        switch ($Type) {
            'Group' { $found = @(Get-AzADGroup -DisplayName $Name -ErrorAction Stop) }
            'Guest' { $found = @(Get-AzADUser -Filter "mail eq '$Name'" -ErrorAction Stop) }
            'User'  { $found = @(Get-AzADUser -Filter "userPrincipalName eq '$Name'" -ErrorAction Stop) }
        }
    }
    catch {
        throw "Could not look up $Type '$Name' in Entra ID: $($_.Exception.Message) $(Get-LabGraphSignInHint -Client Az)"
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

# The tenant's domains, as Microsoft Graph lists them (GET /v1.0/domains: id, isInitial, ...).
# Az.Resources has no domain cmdlet, so the list comes through Invoke-AzRestMethod, which calls
# Graph with the same Az token Get-AzADUser uses: still one sign-in and no extra module. It
# answers an HTTP error with a status code rather than an exception, so the code is checked here:
# a failed lookup is an error, never an empty list.
function Get-LabDirectoryDomain {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $response = Invoke-AzRestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/domains?$select=id,isInitial' -ErrorAction Stop
    if ([int]$response.StatusCode -ne 200) {
        throw "Microsoft Graph answered $($response.StatusCode) to GET /v1.0/domains: $($response.Content)"
    }
    return @(($response.Content | ConvertFrom-Json).value)
}

# --- The users' domain (issues #193, #237) --------------------------------------------------
# Lab 1.1 creates its users on the tenant's INITIAL *.onmicrosoft.com domain, the one its guide's
# '<name>@[yourtenant].onmicrosoft.com' means, so this script looks them up there. Not the default
# domain: in a tenant whose default is a custom domain, that names users Lab 1.1 never created.
# And no guess when the tenant lists no initial domain. A byte-identical copy of the function in
# Lab 1.1's scripts and in New-LabRoleAssignment.ps1; tests/Module1-Initial-Domain.Tests.ps1 holds
# the copies together.
function Select-LabInitialDomain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Domain
    )

    $initial = @($Domain | Where-Object { $_ -and $_.IsInitial -eq $true } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
    if ($initial.Count -eq 0) { throw 'the tenant lists no domain marked IsInitial' }
    return $initial[0]
}

# --- Existing assignments (issues #397, #406) ----------------------------------------------
# Returns the Key of each of the template's assignments ($Desired: Key, ObjectId, Role, Scope,
# optional NoCondition) that already exists, whatever its name: the template skips those listed
# in parExistingAssignments, so a lab built in the Portal or by New-LabRoleAssignment.ps1 gets no
# second one. Read through the
# ARM role assignments API (Get-LabArmRoleAssignment), not Get-AzRoleAssignment, which calls
# Microsoft Graph. The listing also returns assignments inherited from above, so the role and the
# scope must match exactly: a Reader at subscription level is not the RG-level Reader the template
# makes. A read that fails throws: counting it as "not there" would deploy on top of assignments
# that may exist. Top-level, like Resolve-LabPrincipalId, so
# tests/RoleAssignments-DeployPath.Tests.ps1 can exercise it without a subscription.
function Get-LabExistingAssignmentKey {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Desired
    )

    $held = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Desired) {
        $scope = $item.Scope
        $roleId = Get-LabBuiltInRoleId -Name $item.Role
        try {
            $match = @(Get-LabArmRoleAssignment -Scope $scope -PrincipalId $item.ObjectId |
                Where-Object { $_.RoleDefinitionId -eq $roleId -and $_.Scope -eq $scope })
        }
        catch {
            throw "Could not read the role assignments at ${scope}: $($_.Exception.Message)"
        }
        # As Test-Lab.ps1 checks it: a conditioned Owner is not the lab's, and the template cannot replace it.
        if ($item.NoCondition -and $match.Count -gt 0 -and -not @($match | Where-Object { -not $_.Condition })) {
            throw "$($item.Key): the $($item.Role) assignment at $scope has a condition; the lab's has none. Remove it in the Portal (guide Troubleshooting, Issue 6) and run again."
        }
        if ($match.Count -gt 0) { $held.Add([string]$item.Key) }
    }
    return $held.ToArray()
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
    Exit-Lab -FailureCount 1
}

$subscriptionId = $context.Subscription.Id

# Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\resource-groups.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

$roleTemplateFile = Join-Path $PSScriptRoot "..\bicep\role-assignments.bicep"
if ($IncludeRoleAssignments -and -not (Test-Path $roleTemplateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $roleTemplateFile" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

# Resolve the principals before anything is deployed: a missing Lab 1.1 user should stop the run
# before the resource groups exist, not after.
$principal = $null
if ($IncludeRoleAssignments) {
    Write-Host "`nResolving Entra ID principals for role-assignments.bicep..." -ForegroundColor Cyan
    try {
        $domain = Select-LabInitialDomain -Domain @(Get-LabDirectoryDomain)
        Write-Host "  Initial domain: $domain" -ForegroundColor Gray
    }
    catch {
        Write-Host "  -> [ERROR] Could not determine the tenant's initial *.onmicrosoft.com domain: $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    try {
        $principal = [ordered]@{
            parAdminPrincipalId          = Resolve-LabPrincipalId -Type User  -Name "malfurion.stormrage@$domain"
            parDeveloperGroupPrincipalId = Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers'
            parTesterGroupPrincipalId    = Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Testers'
            parPartnerPrincipalId        = Resolve-LabPrincipalId -Type Guest -Name 'istormrage@illidari.com'
        }
        foreach ($entry in $principal.GetEnumerator()) {
            Write-Host "  $($entry.Key): $($entry.Value)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  -> [ERROR] $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
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
            Exit-Lab -FailureCount 1
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
    Exit-Lab -FailureCount 1
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

# The five assignments the template declares: its parExistingAssignments key, principal, role and
# exact scope. Kept in step with the template by hand; Test-Lab.ps1 asserts the same five.
$desired = @(
    @{ Key = 'admin-owner';               ObjectId = $principal.parAdminPrincipalId;          Role = 'Owner';       Scope = "/subscriptions/$subscriptionId"; NoCondition = $true }
    @{ Key = 'developer-contributor-dev'; ObjectId = $principal.parDeveloperGroupPrincipalId; Role = 'Contributor'; Scope = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Key = 'tester-reader-dev';         ObjectId = $principal.parTesterGroupPrincipalId;    Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Key = 'tester-reader-prod';        ObjectId = $principal.parTesterGroupPrincipalId;    Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/prod-skycraft-swc-rg" }
    @{ Key = 'partner-reader-platform';   ObjectId = $principal.parPartnerPrincipalId;        Role = 'Reader';      Scope = "/subscriptions/$subscriptionId/resourceGroups/platform-skycraft-swc-rg" }
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

    # Exact role and scope, through the ARM API (Get-LabExistingAssignmentKey above). A read that
    # fails throws into the catch below: an [ERROR] and exit 1, nothing deployed.
    $heldKeys = @(Get-LabExistingAssignmentKey -Desired $desired)
    Write-Host "  Existing assignments: $($heldKeys.Count) of $($desired.Count)" -ForegroundColor Gray
    foreach ($item in $desired) {
        $label = "$($item.Key) ($($item.Role) at $($item.Scope))"
        if ($heldKeys -contains $item.Key) {
            Write-Host "  [KEEP]   ${label}: exists already; the template leaves it as it is." -ForegroundColor Gray
        }
        else {
            Write-Host "  [CREATE] ${label}: does not exist; the template creates it." -ForegroundColor Gray
        }
    }

    if ($heldKeys.Count -eq $desired.Count) {
        Write-Host "  -> [SKIP] All $($desired.Count) role assignments already exist - nothing to preview or deploy." -ForegroundColor Yellow
    }
    else {
        # The template skips the assignments listed here (issue #406).
        $roleParams = @{
            Name                   = $roleDeploymentName
            Location               = $Location
            TemplateFile           = $roleTemplateFile
            parExistingAssignments = $heldKeys
            ErrorAction            = 'Stop'
        }
        foreach ($entry in $principal.GetEnumerator()) { $roleParams[$entry.Key] = $entry.Value }

        if ($WhatIf) {
            Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
            Get-AzSubscriptionDeploymentWhatIfResult @roleParams
            Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
            exit 0
        }

        $roleDeployment = New-AzSubscriptionDeployment @roleParams

        if ($roleDeployment.ProvisioningState -ne 'Succeeded') {
            Write-Host "  -> [FAILED] Deployment finished with state: $($roleDeployment.ProvisioningState)" -ForegroundColor Red
            Exit-Lab -FailureCount 1
        }

        Write-Host "  -> [SUCCESS] Role assignments deployed successfully." -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Role assignment deployment failed: $_" -ForegroundColor Red
    if ("$_" -match 'RoleAssignmentExists') {
        Write-Host "     One of the assignments was created after this script read the existing ones," -ForegroundColor Yellow
        Write-Host "     in the portal or by New-LabRoleAssignment.ps1 meanwhile. Run this script again: it keeps those that exist." -ForegroundColor Yellow
    }
    Exit-Lab -FailureCount 1
}

if ($WhatIf) { exit 0 }
Write-Host "`nDeployment Complete." -ForegroundColor Green
Exit-Lab -FailureCount 0
