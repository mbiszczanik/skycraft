<#
.SYNOPSIS
    Deploys Lab 1.3 Governance (Tags, Policies, Locks) using Bicep.

.DESCRIPTION
    This script orchestrates the deployment of governance controls for SkyCraft Lab 1.3
    by invoking the main.bicep orchestrator.

    A lab built in the Portal is deployed over without a second copy of anything (issue #406).
    Before the deployment, the script lists the subscription's policy assignments, finds each of
    the guide's four by its definition and scope, whatever its resource name
    (LabPolicyAssignment.ps1, shared with Test-Lab.ps1 and Remove-LabResource.ps1), and prints
    what it does with it:
      [CREATE]  none exists; the template creates it
      [ADOPT]   one exists under the template's own name; the template deploys over it
      [KEEP]    one exists under another name (made in the Portal); the template leaves it as it
                is (parExistingPolicyAssignments) and creates no second one
    The identity of Inherit-Project-Tag keeps the Contributor role it holds; the template grants
    the role only when the identity does not hold it on the subscription yet.

    The script deploys nothing, and exits 1, when it cannot list the policy or role assignments,
    when more than one assignment matches one of the guide's, or when a found assignment differs
    from the lab's in its parameters, enforcement mode or managed identity: it names each
    difference instead of keeping or overwriting the learner's assignment without a word. Texts
    (display name, description, message) are not compared.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER Owner
    Value for the canonical Owner tag. Default: mbiszczanik.

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.
    Over a lab built in the Portal, the preview shows no policy assignment and no role
    assignment to create.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Owner "mbiszczanik"

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the governance deployment without changing anything.

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'mbiszczanik',

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 1.3: Governance Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Connection
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Checking Azure connection..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
    $subscriptionId = $context.Subscription.Id
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# 2. Template
$templateFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# 3. Existing policy assignments and the identity's role (issue #406)
Write-Host "`nChecking existing policy assignments..." -ForegroundColor Cyan
. (Join-Path $PSScriptRoot 'LabPolicyAssignment.ps1')
$subscriptionScope = "/subscriptions/$subscriptionId"
$problemCount = 0

try {
    $assignments = @(Get-AzPolicyAssignment -Scope $subscriptionScope -ErrorAction Stop | Where-Object { $_ })
}
catch {
    Write-Host "  -> [ERROR] Could not list the policy assignments on the subscription, so nothing is deployed (an assignment it could not see may exist): $_" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$plan = @(Get-LabPolicyAssignmentPlan -Assignment $assignments -SubscriptionId $subscriptionId)
$keep = [System.Collections.Generic.List[string]]::new()
foreach ($item in $plan) {
    $name = $item.Spec.Name
    switch ($item.Action) {
        'Create' {
            Write-Host "  [CREATE] ${name}: none on the subscription; the template creates it." -ForegroundColor Gray
        }
        'Adopt' {
            Write-Host "  [ADOPT]  ${name}: $(Format-LabPolicyAssignment -Assignment $item.Found[0]); the template deploys over it." -ForegroundColor Gray
        }
        'Keep' {
            Write-Host "  [KEEP]   ${name}: $(Format-LabPolicyAssignment -Assignment $item.Found[0]), made outside the template; left as it is." -ForegroundColor Gray
            $keep.Add($name)
        }
        'Duplicate' {
            $problemCount++
            $foundList = ($item.Found | ForEach-Object { Format-LabPolicyAssignment -Assignment $_ }) -join ', '
            Write-Host "  -> [ERROR] $($item.Found.Count) assignments match ${name}: $foundList. Delete all but one in the Portal (Policy > Assignments)." -ForegroundColor Red
        }
    }
    if ($item.Drift.Count -gt 0) {
        $problemCount++
        Write-Host "  -> [ERROR] $name $(Format-LabPolicyAssignment -Assignment $item.Found[0]) differs from the lab's: $($item.Drift -join '; '). Set it as step $($item.Spec.Step) does, or delete it, in the Portal (Policy > Assignments)." -ForegroundColor Red
    }
}
$existingCount = @($plan | Where-Object { $_.Action -in 'Adopt', 'Keep' }).Count
Write-Host "  Existing assignments: $existingCount of $($plan.Count)" -ForegroundColor Gray

# The Portal grants the identity's role under a generated name, so a second grant by the template
# fails with RoleAssignmentExists: the template grants it only when the identity lacks it.
$grantInheritRole = $true
$inheritPrincipalToGrant = ''
$inherit = @($plan | Where-Object { $_.Spec.RoleDefinitionId -and $_.Action -in 'Adopt', 'Keep' -and $_.Drift.Count -eq 0 })
if ($inherit.Count -eq 1) {
    $inherit = $inherit[0]
    $principalId = (Get-LabPolicyAssignmentIdentity -Assignment $inherit.Found[0]).PrincipalId
    $roleGuid = ($inherit.Spec.RoleDefinitionId -split '/')[-1]
    $roleLabel = "Role $roleGuid of the identity of $($inherit.Spec.Name)"
    $held = $null
    try {
        $held = @(Select-LabPolicyIdentityRoleAssignment -RoleAssignment @(Get-AzRoleAssignment -Scope $subscriptionScope -ErrorAction Stop) `
                -PrincipalId $principalId -SubscriptionId $subscriptionId |
            Where-Object { ([string]$_.Scope).TrimEnd('/') -eq $subscriptionScope -and [string]$_.RoleDefinitionId -eq $roleGuid })
    }
    catch {
        $problemCount++
        Write-Host "  -> [ERROR] Could not list the role assignments on the subscription, so the role of $($inherit.Spec.Name)'s identity cannot be checked: $_" -ForegroundColor Red
    }
    if ($null -ne $held) {
        if ($held.Count -gt 0) {
            Write-Host "  [KEEP]   ${roleLabel}: held on the subscription already; the template grants none." -ForegroundColor Gray
            $grantInheritRole = $false
        }
        else {
            Write-Host "  [GRANT]  ${roleLabel}: not held on the subscription; the template grants it." -ForegroundColor Gray
            if ($inherit.Action -eq 'Keep') { $inheritPrincipalToGrant = $principalId }
        }
    }
}

if ($problemCount -gt 0) {
    Write-Host "`n  -> [ERROR] Nothing deployed: $problemCount problem(s) above. Fix them and run this script again." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$deploymentName = "Lab-1.3-Gov-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  Owner: $Owner" -ForegroundColor Gray

try {
    $params = @{
        parLocation                     = $Location
        parOwner                        = $Owner
        parExistingPolicyAssignments    = @($keep)
        parGrantInheritProjectTagRole   = $grantInheritRole
        parInheritProjectTagPrincipalId = $inheritPrincipalToGrant
    }

    $deployParams = @{
        Name                    = $deploymentName
        Location                = $Location
        TemplateFile            = $templateFile
        TemplateParameterObject = $params
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "  -> [SUCCESS] Governance deployment completed." -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    } else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        if ($deployment.Error) {
            Write-Host "Error Code: $($deployment.Error.Code)" -ForegroundColor Red
            Write-Host "Error Message: $($deployment.Error.Message)" -ForegroundColor Red
            Write-Host "Error Target: $($deployment.Error.Target)" -ForegroundColor Red
            if ($deployment.Error.Details) {
                foreach ($detail in $deployment.Error.Details) {
                    Write-Host "  - Detail Code: $($detail.Code)" -ForegroundColor Red
                    Write-Host "  - Detail Message: $($detail.Message)" -ForegroundColor Red
                }
            }
        }

        # Get operations
        $ops = Get-AzSubscriptionDeploymentOperation -DeploymentName $deploymentName
        $failedOps = $ops | Where-Object { $_.ProvisioningState -eq "Failed" }
        foreach ($op in $failedOps) {
             Write-Host "Failed Operation: $($op.Properties.TargetResource.ResourceName)" -ForegroundColor Yellow
             Write-Host "Status Message: $($op.Properties.StatusMessage)" -ForegroundColor Red
        }
        $Host.SetShouldExit(1)
        exit 1
    }
}
catch {
    Write-Host "  -> [ERROR] Deployment failed: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nDeployment Complete." -ForegroundColor Green
Write-Host "Next Steps:" -ForegroundColor Gray
Write-Host " 1. Run Test-Lab.ps1 to validate." -ForegroundColor Gray
