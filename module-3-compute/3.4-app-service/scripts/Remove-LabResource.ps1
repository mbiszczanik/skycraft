<#
.SYNOPSIS
    Removes Lab 3.4 resources.

.DESCRIPTION
    Detaches the regional VNet integration from the Web App and from every deployment slot, waits for
    the AppServiceSubnet service association link to the plan to disappear, then deletes the Web App
    (with its slots), the autoscale setting and the App Service Plan - in that order.

    Deleting the plan while an integration is still attached can leave an orphaned
    serviceAssociationLink on the subnet, which makes the subnet, the VNet, its NSGs and the whole
    resource group undeletable (Azure support ticket). Hence the detach-first order.

    Does NOT delete the Resource Group or the VNet (shared resources).

.PARAMETER RgName
    Resource Group containing the Lab 3.4 App Service resources. Default: dev-skycraft-swc-rg

.PARAMETER AppName
    Web App name. Default: dev-skycraft-swc-app01

.PARAMETER AspName
    App Service Plan name. Default: dev-skycraft-swc-asp

.PARAMETER VnetName
    VNet that holds the integration subnet. Default: dev-skycraft-swc-vnet

.PARAMETER SubnetName
    Integration subnet name. Default: AppServiceSubnet

.PARAMETER Force
    Skips the confirmation prompt before removing resources.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 3.4 - App Service
    Author: Marcin Biszczanik
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Websites, Az.Monitor, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$RgName = 'dev-skycraft-swc-rg',

    [ValidateNotNullOrEmpty()]
    [string]$AppName = 'dev-skycraft-swc-app01',

    [ValidateNotNullOrEmpty()]
    [string]$AspName = 'dev-skycraft-swc-asp',

    [ValidateNotNullOrEmpty()]
    [string]$VnetName = 'dev-skycraft-swc-vnet',

    [ValidateNotNullOrEmpty()]
    [string]$SubnetName = 'AppServiceSubnet',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Cleanup Lab 3.4: App Service ===" -ForegroundColor Cyan
Write-Host "Target Resource Group: $RgName" -ForegroundColor Yellow

# 1. Verify Connection
if (-not (Get-AzContext)) { Write-Host "Not logged in." -ForegroundColor Red; exit 1 }

$webApiVersion = '2023-12-01'
$autoscaleName = "$AspName-autoscale"

try {
    $app = Get-AzWebApp -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue

    # 2. Detach the VNet integration from the app and every slot BEFORE anything is deleted
    if ($app) {
        $targets = @($app.Id)
        $slots = @(Get-AzWebAppSlot -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue)
        foreach ($slot in $slots) { $targets += $slot.Id }

        foreach ($id in $targets) {
            if ($PSCmdlet.ShouldProcess($id, 'Remove VNet integration')) {
                Write-Host "Detaching VNet integration: $id" -ForegroundColor Yellow
                $response = Invoke-AzRestMethod -Method DELETE -Path "$id/networkConfig/virtualNetwork?api-version=$webApiVersion"
                if ($response.StatusCode -notin 200, 204, 404) {
                    Write-Host "  -> [WARN] HTTP $($response.StatusCode): $($response.Content)" -ForegroundColor Yellow
                }
            }
        }

        # Bounded wait for the subnet's service association link to the plan to disappear
        $deadline = (Get-Date).AddMinutes(3)
        do {
            $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
            $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
            $links = @($subnet.ServiceAssociationLinks | Where-Object { $_.Link -like "*/serverfarms/$AspName" })
            if ($links.Count -eq 0) { break }
            Start-Sleep -Seconds 10
        } while ((Get-Date) -lt $deadline)

        if ($links.Count -gt 0) {
            Write-Host "  -> [WARN] '$SubnetName' still carries a serviceAssociationLink to '$AspName' (pre-existing orphaned link or propagation delay). Continuing." -ForegroundColor Yellow
        }
        else {
            Write-Host "  -> VNet integration detached; '$SubnetName' has no link to '$AspName'." -ForegroundColor Green
        }

        # 3. Delete the Web App (slots go with it)
        if ($PSCmdlet.ShouldProcess($AppName, 'Remove Web App (including slots)')) {
            Write-Host "Removing Web App '$AppName'..." -ForegroundColor Yellow
            Remove-AzWebApp -ResourceGroupName $RgName -Name $AppName -Force -ErrorAction Stop | Out-Null
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Web App '$AppName' not found - skipping detach and app deletion." -ForegroundColor Gray
    }

    # 4. Delete the autoscale setting
    if ($PSCmdlet.ShouldProcess($autoscaleName, 'Remove Autoscale Setting')) {
        Write-Host "Removing autoscale setting '$autoscaleName'..." -ForegroundColor Yellow
        $autoscale = Get-AzAutoscaleSetting -ResourceGroupName $RgName -Name $autoscaleName -ErrorAction SilentlyContinue
        if ($autoscale) {
            Remove-AzAutoscaleSetting -ResourceGroupName $RgName -Name $autoscaleName -ErrorAction Stop | Out-Null
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        else {
            Write-Host "  -> Not found or already deleted." -ForegroundColor Gray
        }
    }

    # 5. Delete the App Service Plan
    if ($PSCmdlet.ShouldProcess($AspName, 'Remove App Service Plan')) {
        Write-Host "Removing App Service Plan '$AspName'..." -ForegroundColor Yellow
        $plan = Get-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -ErrorAction SilentlyContinue
        if ($plan) {
            Remove-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -Force -ErrorAction Stop | Out-Null
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        else {
            Write-Host "  -> Not found or already deleted." -ForegroundColor Gray
        }
    }

    Write-Host "Cleanup completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Cleanup failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
