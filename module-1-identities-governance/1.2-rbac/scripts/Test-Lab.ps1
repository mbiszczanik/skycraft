<#
.SYNOPSIS
    Validates infrastructure and role assignments for Lab 1.2.

.DESCRIPTION
    Checks presence of Resource Groups and specific Role Assignments.
    - Malfurion -> Owner (Subscription), without a condition
    - SkyCraft-Developers -> Contributor (dev-rg)
    - SkyCraft-Testers -> Reader (dev-rg, prod-rg)
    - Illidan -> Reader (platform-rg)

    Every check prints [OK] or [FAIL] and is counted. The summary states how many passed and how
    many failed, and the script exits 0 only when none failed. It exits 1 when any check failed,
    and also when no one is signed in to Azure, in which case no check runs (issue #254).

    The role assignments are read through the Azure Resource Manager role assignments API
    (Get-LabArmRoleAssignment in tools/LabCommon.psm1), filtered by principal and matched on the
    exact scope and the role's id. Finding the four principals by name - Malfurion by his
    userPrincipalName, the two groups by display name, Illidan by his mail - needs Microsoft
    Graph, through the Az sign-in's Graph token (Get-AzADUser, Get-AzADGroup). Where the tenant
    asks for interaction before it issues that token, sign in with
    'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId'; a principal that cannot be
    looked up fails its checks with that hint (issue #397). -SkipRoleAssignments needs no Graph.

.PARAMETER SkipRoleAssignments
    Checks the resource groups only. The five role-assignment checks are reported as skipped and
    not counted. For the automated lab cycle, which deploys the resource groups without the role
    assignments (Deploy-Bicep.ps1 without -IncludeRoleAssignments) and does not run Lab 1.1, so
    the assignments those checks look for are not the cycle's to create.

.EXAMPLE
    .\Test-Lab.ps1
    Runs validation.

.EXAMPLE
    .\Test-Lab.ps1 -SkipRoleAssignments
    Validates the resource groups only, as the lab cycle does.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [switch]$SkipRoleAssignments
)

$ErrorActionPreference = "Stop"
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
# The module's role assignment helpers use the ARM API, not Microsoft Graph (#397).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 1.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
Write-Host "`nChecking Azure connection..." -ForegroundColor Cyan
$context = Get-AzContext
if (-not $context) {
    Write-Host "[ERROR] Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$subId = $context.Subscription.Id
Write-Host "Connected to: $($context.Subscription.Name) ($subId)" -ForegroundColor Green

# Every check below ends in exactly one [OK] or [FAIL], and each is counted here: the summary
# states the counts and the exit code follows them (issue #254). Before that, a run in which every
# check printed [FAIL] still ended "Validation complete." with exit 0, so the lab cycle read a
# failed validation as a passed one.
$passCount = 0
$failCount = 0

# 1. Validate Resource Groups
Write-Host "`n=== Validating Resource Groups ===" -ForegroundColor Cyan
$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rg in $rgs) {
    # -ErrorAction Stop: a missing resource group and a lookup that failed both land in the catch,
    # so neither can read as found.
    try {
        Get-AzResourceGroup -Name $rg -ErrorAction Stop | Out-Null
        Write-Host "[OK] Resource Group: $rg" -ForegroundColor Green
        $passCount++
    }
    catch {
        Write-Host "[FAIL] Resource Group missing or unreadable: $rg ($($_.Exception.Message))" -ForegroundColor Red
        $failCount++
    }
}

# 2. Validate Role Assignments
Write-Host "`n=== Validating Role Assignments ===" -ForegroundColor Cyan

# The five assignments the lab makes: each principal, its role and the exact scope the guide
# assigns it at. An assignment inherited from above (a subscription Reader, say) is not the
# resource-group assignment the lab asks for, as in Deploy-Bicep.ps1 and Remove-LabResource.ps1.
$checks = @(
    @{ Name="Malfurion (Admin)"; Principal="malfurion.stormrage"; Role="Owner"; Scope="/subscriptions/$subId"; NoCondition=$true }
    @{ Name="Developers Group";  Principal="SkyCraft-Developers";  Role="Contributor"; Scope="/subscriptions/$subId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Name="Testers Group (Dev)"; Principal="SkyCraft-Testers";   Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Name="Testers Group (Prod)"; Principal="SkyCraft-Testers";  Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/prod-skycraft-swc-rg" }
    @{ Name="External Partner";  Principal="istormrage@illidari.com"; Role="Reader";   Scope="/subscriptions/$subId/resourceGroups/platform-skycraft-swc-rg" }
)

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

# Finds one of Lab 1.1's principals by name, through Microsoft Graph with the Az sign-in's own
# token: Malfurion by his full userPrincipalName on the initial domain (issue #380), a group by display name, the
# guest by mail (a guest's userPrincipalName is rewritten to <alias>_<domain>#EXT#@<tenant>).
# Returns the object id, $null when the directory holds no such principal, and throws when the
# lookup fails or finds more than one. Only a failed lookup names the sign-in that provides
# Microsoft Graph (issue #397): signing in again does not change what the directory holds.
function Find-LabPrincipalId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$InitialDomain
    )

    $isUser = $Name -notlike 'SkyCraft-*' -and $Name -notlike '*@*'
    if ($isUser -and -not $InitialDomain) { throw "the tenant's initial domain is unknown, so '$Name' cannot be looked up" }

    try {
        $found = if ($Name -like 'SkyCraft-*') {
            @(Get-AzADGroup -DisplayName $Name -ErrorAction Stop)
        }
        elseif ($Name -like '*@*') {
            @(Get-AzADUser -Filter "mail eq '$Name'" -ErrorAction Stop)
        }
        else {
            @(Get-AzADUser -Filter "userPrincipalName eq '$Name@$InitialDomain'" -ErrorAction Stop)
        }
    }
    catch {
        throw "Could not look up '$Name' in Entra ID: $($_.Exception.Message) $(Get-LabGraphSignInHint -Client Az)"
    }
    $found = @($found | Where-Object { $_ })
    if ($found.Count -gt 1) { throw "'$Name' matched $($found.Count) principals in Entra ID; expected exactly one." }
    if ($found.Count -eq 0) { return $null }
    return [string]$found[0].Id
}

if ($SkipRoleAssignments) {
    Write-Host "[SKIP] $($checks.Count) role-assignment checks not run (-SkipRoleAssignments) and not counted." -ForegroundColor Yellow
}
else {
    # Each principal is looked up once. A lookup that fails or is ambiguous is remembered with its
    # error, so every check of that principal fails and says why.
    $principalIds = @{}
    $principalErrors = @{}

    # Lab 1.1 creates Malfurion on the tenant's initial domain; a user of that name on another domain
    # is not his (issue #380). If the domain cannot be determined, his checks fail and say why.
    $initialDomain = $null
    $domainError = $null
    try {
        $initialDomain = Select-LabInitialDomain -Domain @(Get-LabDirectoryDomain)
    }
    catch {
        $domainError = "Could not determine the tenant's initial *.onmicrosoft.com domain: $($_.Exception.Message) $(Get-LabGraphSignInHint -Client Az)"
    }

    foreach ($name in @($checks | ForEach-Object { $_.Principal } | Select-Object -Unique)) {
        try {
            $principalIds[$name] = Find-LabPrincipalId -Name $name -InitialDomain $initialDomain
        }
        catch {
            $principalErrors[$name] = if ($domainError -and -not $initialDomain -and $name -notlike 'SkyCraft-*' -and $name -notlike '*@*') { $domainError } else { $_.Exception.Message }
        }
    }

    foreach ($check in $checks) {
        Write-Host "Checking: $($check.Name)..." -NoNewline

        if ($principalErrors.ContainsKey($check.Principal)) {
            Write-Host " [FAIL] $($principalErrors[$check.Principal])" -ForegroundColor Red
            $failCount++
            continue
        }
        $principalId = $principalIds[$check.Principal]
        if (-not $principalId) {
            Write-Host " [FAIL] '$($check.Principal)' not found in Entra ID. Complete Lab 1.1 first." -ForegroundColor Red
            $failCount++
            continue
        }

        # Through the ARM role assignments API, not Get-AzRoleAssignment, which resolves every
        # principal through Microsoft Graph (issue #397). A read that fails is a failed check that
        # says why, not an empty scope.
        try {
            $roleId = Get-LabBuiltInRoleId -Name $check.Role
            $found = @(Get-LabArmRoleAssignment -Scope $check.Scope -PrincipalId $principalId |
                Where-Object { $_.RoleDefinitionId -eq $roleId -and $_.Scope -eq $check.Scope })

            # Owner without a condition is what the Bicep and New-LabRoleAssignment.ps1 create and
            # what guide step 1.2.4 selects ("Allow user to assign all roles"). Any other option on
            # the Portal's Conditions tab adds a condition: the assignment exists but is not the
            # lab's, so it fails here as well (#325, guide Troubleshooting Issue 6).
            if ($found.Count -gt 0 -and $check.NoCondition -and -not @($found | Where-Object { -not $_.Condition })) {
                Write-Host " [FAIL] '$($check.Role)' assignment found, but with a condition; the lab's has none (guide step 1.2.4)." -ForegroundColor Red
                $failCount++
            }
            elseif ($found.Count -gt 0) {
                Write-Host " [OK] Found '$($check.Role)' assignment." -ForegroundColor Green
                $passCount++
            }
            else {
                Write-Host " [FAIL] Expected Assignment '$($check.Role)' for '$($check.Principal)' NOT found." -ForegroundColor Red
                $failCount++
            }
        }
        catch {
            Write-Host " [FAIL] Could not read role assignments at scope: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })

if ($failCount -gt 0) {
    Write-Host "`nLab 1.2 validation failed: $failCount check(s) failed. See the [FAIL] lines above." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "`nLab 1.2 validation passed: all $passCount checks passed." -ForegroundColor Green
Exit-Lab -FailureCount 0
