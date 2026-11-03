<#
.SYNOPSIS
    Deploys the App Service Lab 3.4 using Bicep.

.DESCRIPTION
    This script deploys the Azure App Service infrastructure defined in main.bicep.
    It targets the 'dev' environment by default.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER Environment
    Target environment (dev, prod). Default: dev.

.PARAMETER AppName
    The web app name. Default: '<Environment>-skycraft-swc-app01'. Web app names are unique per
    region across Azure, so override this on a collision, and pass the same name to Test-Lab.ps1
    and Remove-LabResource.ps1.

.PARAMETER PlanSku
    App Service plan SKU. Default: P0v4. P0v3 and S1 are fallbacks when the subscription has no
    P0v4 quota; both keep deployment slots and autoscale. A subscription that throttles plan
    creation (429, seen on a Free Trial) refuses every SKU: use a Pay-As-You-Go or Visual Studio
    subscription. Test-Lab.ps1 accepts all three.

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev

.EXAMPLE
    .\Deploy-Bicep.ps1 -AppName dev-skycraft-swc-app01-ab
    Deploys the web app under a name of your own, when the default is taken.

.EXAMPLE
    .\Deploy-Bicep.ps1 -PlanSku S1
    Deploys the plan on Standard S1, when the subscription has no Premium V4 quota.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -WhatIf
    Previews the App Service deployment without changing anything.

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    # The default reads $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$')]
    [string]$AppName = "$Environment-skycraft-swc-app01",

    [Parameter(Mandatory = $false)]
    [ValidateSet('P0v4', 'P0v3', 'S1')]
    [string]$PlanSku = 'P0v4',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$BicepFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$DeploymentName = "deploy-lab3.4-$Environment"
# The plan deployment (module name in main.bicep) and the seconds between looks at it. A plan is
# created in about two minutes; ARM retries a throttled create for hours (#439).
$PlanDeploymentName = 'asp-deployment'
$PollSeconds = 15
$PlanWaitMinutes = 15

Write-Host "=== Lab 3.4 Deployment: App Service ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; Exit-Lab -FailureCount 1
}
$ResourceGroupName = "$Environment-skycraft-swc-rg"
Write-Host "  Web app: $AppName" -ForegroundColor Gray
Write-Host "  Plan SKU: $PlanSku" -ForegroundColor Gray

# 2. A taken app name otherwise fails the deployment after the plan is created (#438).
$appOwned = [bool](Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -Name $AppName -ErrorAction SilentlyContinue)
if (-not (Test-LabGlobalName -Kind WebApp -Name $AppName -ParameterName 'AppName' -Owned $appOwned -Location $Location)) {
    Exit-Lab -FailureCount 1
}

# 3. Deploy Bicep
try {
    Write-Host "Starting Bicep deployment from: $BicepFile" -ForegroundColor Yellow
    
    $params = @{
        parLocation          = $Location
        parEnvironment       = $Environment
        parResourceGroupName = $ResourceGroupName
        parVnetName          = "$Environment-skycraft-swc-vnet"
        parAppName           = $AppName
        parPlanSkuName       = $PlanSku
    }

    $deployParams = @{
        Name                    = $DeploymentName
        Location                = $Location
        TemplateFile            = $BicepFile
        TemplateParameterObject = $params
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        Exit-Lab -FailureCount 0
    }

    # A job, so the plan can be watched: ARM retries a throttled plan create (429) for hours and the
    # deployment would only fail at the end.
    $startedUtc = (Get-Date).ToUniversalTime()
    $deployment = New-AzSubscriptionDeployment @deployParams -AsJob  # a job until Receive-Job below
    $stopReason = $null
    while ($deployment.State -in @('NotStarted', 'Running')) {
        Start-Sleep -Seconds $PollSeconds
        # The operations carry no timestamp. A plan deployment record from an earlier run (same name)
        # is stale until this run replaces it, so read the operations only from a record updated since
        # the start (2 minutes of clock slack).
        $planDeployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $PlanDeploymentName -ErrorAction SilentlyContinue
        $ops = @()
        if ($planDeployment -and $planDeployment.Timestamp.ToUniversalTime() -ge $startedUtc.AddMinutes(-2)) {
            $ops = @(Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $PlanDeploymentName -ErrorAction SilentlyContinue)
        }
        $throttle = Get-LabThrottleMessage -Operation $ops
        if ($throttle) {
            $stopReason = "Azure throttled the App Service plan create (HTTP 429): $throttle"
            break
        }
        $planCreated = @($ops | Where-Object { "$($_.TargetResource)" -match 'serverfarms' -and $_.ProvisioningState -eq 'Succeeded' }).Count -gt 0
        if (-not $planCreated -and ((Get-Date).ToUniversalTime() - $startedUtc).TotalMinutes -ge $PlanWaitMinutes) {
            $stopReason = "The App Service plan was not created within $PlanWaitMinutes minutes; Azure is most likely retrying a throttled create."
            break
        }
    }
    if ($stopReason) {
        Stop-AzSubscriptionDeployment -Name $DeploymentName -ErrorAction SilentlyContinue | Out-Null
        Stop-Job $deployment -ErrorAction SilentlyContinue
        Remove-Job $deployment -Force -ErrorAction SilentlyContinue
        Write-Host "[FAILED] $stopReason" -ForegroundColor Red
        Write-Host "  A subscription that throttles plan creation refuses every SKU, so -PlanSku does not help. Deploy on a Pay-As-You-Go, Visual Studio or other paid subscription, or ask Azure support to lift the limit (a Free Trial may refuse any plan). The deployment was stopped; a plan that Azure finished meanwhile stays, so run Remove-LabResource.ps1 before you deploy again." -ForegroundColor Yellow
        Exit-Lab -FailureCount 1
    }
    $deployment = Receive-Job $deployment -Wait -AutoRemoveJob

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    Write-Host "Deployment '$DeploymentName' completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $errorText = $_.Exception.Message
    # A preflight refusal names only the provider; the reason is in the nested details (#497).
    if ($errorText -match 'preflight validation errors') {
        try {
            $nested = Get-LabDeploymentErrorText -ErrorDetail (Test-AzSubscriptionDeployment -Location $Location -TemplateFile $BicepFile -TemplateParameterObject $params -ErrorAction Stop)
            if ($nested) {
                Write-Host $nested -ForegroundColor Red
                $errorText = "$errorText`n$nested"
            }
        }
        catch { Write-Host "  [INFO] The nested error could not be read: $($_.Exception.Message)" -ForegroundColor Gray }
    }
    # No quota for the SKU: say what to do instead of leaving Azure's message alone (#439).
    if ($errorText -match 'additional quota|SkuNotAvailable|quota') {
        Write-Host "  The subscription has no quota for plan SKU $PlanSku in $Location. Run again with another SKU (-PlanSku P0v3 or -PlanSku S1), ask Azure for quota (Portal > Quotas), or use another subscription." -ForegroundColor Yellow
    }
    Exit-Lab -FailureCount 1
}
Exit-Lab -FailureCount 0
