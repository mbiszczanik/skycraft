<#
.SYNOPSIS
    Validates Module 3.4 App Service deployment.

.DESCRIPTION
    Checks if the App Service Plan, Web App, Slots, and Autoscale rules are correctly configured.

    The web app and its staging slot must run Node 22 LTS with the startup command
    'pm2 serve /home/site/wwwroot --no-daemon' (issue #231, maintainer decision 2026-10-16): a
    Node runtime without it shows the default page instead of the dashboard. Both carry the
    regional VNet integration with outbound internet traffic routed through it (guide step
    3.4.10, the Bicep's slot inherits it from the app), and both must be Running.

    Whether the production URL shows the dashboard is reported as [WARN], not counted: the Bicep
    path deploys no content (guide steps 3.4.3-3.4.4 do), and the page check is an HTTPS request
    to the app, not a read of its configuration.

    The autoscale setting is found through the plan it scales (its target resource), not by
    name: the Bicep names it '<plan>-autoscale', the Portal '<plan>-Autoscale-<n>' (issue #355).
    A lookup that fails is a counted [FAIL] that says why, never a crash or a "not found".

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Websites, Az.Monitor

[CmdletBinding()]
param(
    [string]$RgName = "dev-skycraft-swc-rg",
    [string]$AspName = "dev-skycraft-swc-asp",
    [string]$AppName = "dev-skycraft-swc-app01"
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 3.4 Validation: App Service ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) { Write-Host "Not logged in." -ForegroundColor Red; Exit-Lab -FailureCount 1 }

$failures = 0

# Helper function
function Assert-Resource {
    param($Name, $Condition, $Message)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message ($Name)" -ForegroundColor Red
        $script:failures++
    }
}

# The runtime and the startup command the dashboard needs (#231). The Portal writes the runtime
# as 'NODE|22-lts'; compared without case, as ARM may return it in either.
$expectedRuntime = 'NODE|22-lts'
$startupPattern = '^\s*pm2\s+serve\s+/home/site/wwwroot/?\s+--no-daemon\s*$'

function Test-SiteRuntime {
    param($Site, [string]$Label)
    $runtime = "$($Site.SiteConfig.LinuxFxVersion)"
    $command = "$($Site.SiteConfig.AppCommandLine)"
    Assert-Resource "$Label runs '$runtime'" ($runtime -eq $expectedRuntime) "$Label runtime is Node 22 LTS ($expectedRuntime)"
    Assert-Resource "$Label startup command is '$command'" ($command -match $startupPattern) "$Label startup command is 'pm2 serve /home/site/wwwroot --no-daemon'"
}

# The regional VNet integration and its outbound routing, read from the site's raw ARM body
# (no az CLI dependency).
function Test-SiteVnetIntegration {
    param($Site, [string]$Label)
    $props = $null
    try {
        $props = (Get-AzResource -ResourceId $Site.Id -ExpandProperties -ErrorAction Stop).Properties
    } catch {
        Write-Host "  [FAIL] $Label VNet integration could not be read: $($_.Exception.Message)" -ForegroundColor Red
        $script:failures++
        return
    }
    $subnetId = $props.virtualNetworkSubnetId
    Assert-Resource "$Label subnet: '$subnetId'" ("$subnetId" -like "*/subnets/AppServiceSubnet") "$Label VNet integration uses AppServiceSubnet"

    # Outbound internet traffic through the VNet (guide step 3.4.10). The Portal's check box sets
    # outboundVnetRouting.applicationTraffic, the Bicep sets the same; allTraffic and the legacy
    # vnetRouteAllEnabled flag mean the same or more, so any of them passes. A body that carries
    # none of them (another API version) is reported, not counted.
    $routing = @($props.outboundVnetRouting.applicationTraffic, $props.outboundVnetRouting.allTraffic,
        $props.vnetRouteAllEnabled, $props.siteConfig.vnetRouteAllEnabled) | Where-Object { $null -ne $_ }
    if (@($routing).Count -eq 0) {
        Write-Host "  [WARN] $Label outbound routing could not be read (not counted): check Networking > Virtual network integration > Outbound internet traffic." -ForegroundColor Yellow
    } else {
        Assert-Resource "$Label Outbound internet traffic is unchecked" (@($routing) -contains $true) "$Label routes outbound internet traffic through the VNet"
    }
}

# 2. Check App Service Plan
Write-Host "1. Checking App Service Plan..." -ForegroundColor Yellow
$asp = Get-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -ErrorAction SilentlyContinue

if ($asp) {
    Assert-Resource $AspName ($asp.Sku.Tier -eq "PremiumV4" -or $asp.Sku.Name -eq "P0v4") "Tier is PremiumV4 (P0v4)"
    Assert-Resource $AspName ($asp.Kind -like "*linux*") "OS is Linux"
    Assert-Resource $AspName ($asp.Status -eq "Ready") "Status is Ready"
} else {
    Write-Host "  [FAIL] App Service Plan '$AspName' not found!" -ForegroundColor Red; $failures++
}

# 3. Check Web App
Write-Host "2. Checking Web App..." -ForegroundColor Yellow
$app = Get-AzWebApp -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue

if ($app) {
    Assert-Resource $AppName ($app.State -eq "Running") "App is Running"
    Assert-Resource $AppName ($app.HttpsOnly -eq $true) "HTTPS Only is Enabled"
    Test-SiteRuntime -Site $app -Label "Web App"
    Test-SiteVnetIntegration -Site $app -Label "Web App"
} else {
    Write-Host "  [FAIL] Web App '$AppName' not found!" -ForegroundColor Red; $failures++
}

# 4. Check Deployment Slots
Write-Host "3. Checking Deployment Slots..." -ForegroundColor Yellow
$slot = Get-AzWebAppSlot -ResourceGroupName $RgName -Name $AppName -Slot "staging" -ErrorAction SilentlyContinue
Assert-Resource "staging" ($null -ne $slot) "Slot 'staging' exists"
if ($slot) {
    Assert-Resource "staging is '$($slot.State)'" ($slot.State -eq "Running") "Slot 'staging' is Running"
    # Cloned from the app in step 3.4.5 (Portal) or inherited from it (Bicep).
    Test-SiteRuntime -Site $slot -Label "Slot 'staging'"
    # VNet integration is a slot setting: it is neither cloned nor swapped (step 3.4.10).
    Test-SiteVnetIntegration -Site $slot -Label "Slot 'staging'"
}

# 5. Check Autoscale Settings
Write-Host "4. Checking Autoscale Rules..." -ForegroundColor Yellow
# Found through the plan it scales, not by name (#355): the Bicep names the setting
# '<plan>-autoscale', the Portal '<plan>-Autoscale-<n>', and either may sit in another group.
# Get-AzAutoscaleSetting returns an empty .Profiles collection in this Az.Monitor version, so
# the subscription's settings are listed through Get-AzResource, whose raw ARM body carries
# targetResourceUri and the profiles (capacity + rules, camelCase).
if (-not $asp) {
    Write-Host "  [FAIL] Autoscale setting not checked: App Service Plan '$AspName' not found, and the setting is found through the plan it scales." -ForegroundColor Red; $failures++
} else {
    $asRes = $null
    $lookupError = $null
    try {
        $asRes = @(Get-AzResource -ResourceType 'Microsoft.Insights/autoscalesettings' -ExpandProperties -ErrorAction Stop |
                Where-Object { $_ -and "$($_.Properties.targetResourceUri)" -eq $asp.Id }) |
            Select-Object -First 1
    } catch {
        $lookupError = $_.Exception.Message
    }

    if ($lookupError) {
        Write-Host "  [FAIL] Could not list the autoscale settings: $lookupError" -ForegroundColor Red; $failures++
    } elseif (-not $asRes) {
        Write-Host "  [FAIL] No autoscale setting targets App Service Plan '$AspName' (Scale out (App Service plan) > Custom autoscale)." -ForegroundColor Red; $failures++
    } else {
        Write-Host "  Autoscale setting '$($asRes.Name)' in '$($asRes.ResourceGroupName)' targets '$AspName'." -ForegroundColor Gray
        $asProfile = $asRes.Properties.profiles | Select-Object -First 1
        if ($asProfile) {
            Assert-Resource $asRes.Name ($asProfile.capacity.minimum -eq "1" -and $asProfile.capacity.maximum -eq "3") "Instance limits (1-3) correct"
            Assert-Resource $asRes.Name (@($asProfile.rules).Count -ge 2) "Found $(@($asProfile.rules).Count) scaling rules"
        } else {
            Write-Host "  [FAIL] Autoscale setting '$($asRes.Name)' has no profile." -ForegroundColor Red; $failures++
        }
    }
}

# 6. Check the dashboard page - reported, not counted (see .DESCRIPTION)
Write-Host "5. Checking the dashboard page..." -ForegroundColor Yellow
if ($app -and $app.DefaultHostName) {
    $url = "https://$($app.DefaultHostName)"
    try {
        $page = Invoke-WebRequest -Uri $url -TimeoutSec 30 -ErrorAction Stop
        if ("$($page.Content)" -match 'SkyCraft GM Dashboard') {
            Write-Host "  [OK] $url shows the SkyCraft GM Dashboard" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] $url does not show the SkyCraft GM Dashboard (not counted): deploy it as in steps 3.4.3-3.4.4, and check the startup command." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] $url could not be loaded (not counted): $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [WARN] No web app hostname to check (not counted)." -ForegroundColor Yellow
}

# Summary
Write-Host "`nValidation Summary" -ForegroundColor Cyan
if ($failures -eq 0) {
    Write-Host "SUCCESS: All checks passed!" -ForegroundColor Green
} else {
    Write-Host "FAILURE: Found $failures issues." -ForegroundColor Red
}
Exit-Lab -FailureCount $failures
