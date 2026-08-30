<#
.SYNOPSIS
    Removes Lab 3.4 resources.

.DESCRIPTION
    Detaches the regional VNet integration from the Web App and from every deployment slot, then
    verifies per site that the integration is really gone, reports the state of the integration
    subnet, and finally deletes the Web App (with its slots), the autoscale setting and the App
    Service Plan - in that order.

    Once the integration is detached, the site's networkConfig/virtualNetwork route answers 404
    on some stamps and 200 with an empty subnetResourceId on others, so the verification counts
    both as detached and only a non-empty subnet id as still attached. Checking for 404 alone is
    a known trap - it reads a perfectly detached site as still attached and burns the whole
    three-minute wait budget.

    Deleting the plan while an integration is still attached can leave an orphaned
    serviceAssociationLink on the subnet, which makes the subnet, the VNet, its NSGs and the whole
    resource group undeletable (Azure support ticket). Hence the detach-first order. The dev and
    prod AppServiceSubnets already carry such an orphaned link naming a plan with the same name, so
    the subnet links are compared against a snapshot taken before the detach and only reported -
    a leftover link is a warning, never a failure.

    The subnet is inspected before the plan is deleted even when the Web App is already gone, so a
    partially cleaned lab still gets a warning instead of a silent plan deletion.

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
if (-not (Get-AzContext)) { Write-Host "Not logged in." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1 }

# The AVM modules deploy Microsoft.Web/* at 2025-03-01; the networkConfig/virtualNetwork sub-resource
# route is unchanged across both versions, so pinning the older one here is deliberate.
$webApiVersion = '2023-12-01'
$autoscaleName = "$AspName-autoscale"

function Get-SubnetLinkSnapshot {
    <#
    .SYNOPSIS
        Returns the service association link URIs of the integration subnet.
    .DESCRIPTION
        Returns $null when the VNet or the subnet cannot be read, so that "unknown" stays
        distinguishable from "no links".
    .NOTES
        Internal helper for Remove-LabResource.ps1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vnet,
        [Parameter(Mandatory)][string]$Rg,
        [Parameter(Mandatory)][string]$Subnet
    )

    $vnetObject = Get-AzVirtualNetwork -Name $Vnet -ResourceGroupName $Rg -ErrorAction SilentlyContinue
    if (-not $vnetObject) { return $null }

    $subnetObject = $vnetObject.Subnets | Where-Object { $_.Name -eq $Subnet }
    if (-not $subnetObject) { return $null }

    # Unary comma: without it an empty pipeline collapses to $null and a linkless subnet
    # would be misreported as unreadable.
    return ,@($subnetObject.ServiceAssociationLinks | ForEach-Object { $_.Link })
}

try {
    # 2. Snapshot the subnet links BEFORE the detach. The known orphan names a plan with this very
    #    name, so only a before/after comparison can tell it apart from a link left by this run.
    #    Not needed under -WhatIf, where the comparison never runs.
    $linksBefore = if ($WhatIfPreference) { $null } else {
        Get-SubnetLinkSnapshot -Vnet $VnetName -Rg $RgName -Subnet $SubnetName
    }

    $app = Get-AzWebApp -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue
    $targets = @()
    $detached = @()

    # 3. Detach the VNet integration from the app and every slot BEFORE anything is deleted
    if ($app) {
        $targets = @($app.Id)
        $slots = @(Get-AzWebAppSlot -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue)
        foreach ($slot in $slots) { $targets += $slot.Id }

        foreach ($id in $targets) {
            if ($PSCmdlet.ShouldProcess($id, 'Remove VNet integration')) {
                Write-Host "Detaching VNet integration: $id" -ForegroundColor Yellow
                $detached += $id
                $response = Invoke-AzRestMethod -Method DELETE -Path "$id/networkConfig/virtualNetwork?api-version=$webApiVersion" -ErrorAction SilentlyContinue
                if ($null -eq $response) {
                    Write-Host "  -> [WARN] No response from the management API - the integration may still be attached." -ForegroundColor Yellow
                }
                elseif ($response.StatusCode -notin 200, 202, 204, 404) {
                    Write-Host "  -> [WARN] HTTP $($response.StatusCode): $($response.Content)" -ForegroundColor Yellow
                }
            }
        }
    }
    else {
        Write-Host "Web App '$AppName' not found - nothing to detach." -ForegroundColor Gray
    }

    # 4. Verify per site that the integration is gone. This is the only check the known orphaned link
    #    cannot confuse. The route answers 404 on some stamps and 200 with an empty body on others
    #    once the integration is deleted, so both count as detached; only a non-empty subnet id does
    #    not. Only sites whose DELETE actually ran are polled - a declined prompt leaves the site
    #    attached on purpose, so waiting three minutes for it would be pointless.
    if ($WhatIfPreference) {
        Write-Host "What if: Would poll networkConfig/virtualNetwork on $($targets.Count) site(s) until no subnet is reported, up to 3 minutes." -ForegroundColor Gray
    }
    elseif ($detached.Count -gt 0) {
        $deadline = (Get-Date).AddMinutes(3)
        $pending = [System.Collections.Generic.List[string]]::new()
        foreach ($id in $detached) { $pending.Add($id) }

        while ($pending.Count -gt 0) {
            foreach ($id in @($pending)) {
                $check = Invoke-AzRestMethod -Method GET -Path "$id/networkConfig/virtualNetwork?api-version=$webApiVersion" -ErrorAction SilentlyContinue
                if ($null -eq $check) { continue }

                $stillAttached = $false
                if ($check.StatusCode -eq 200) {
                    $subnetId = $null
                    try { $subnetId = ($check.Content | ConvertFrom-Json).properties.subnetResourceId } catch { $subnetId = $null }
                    $stillAttached = -not [string]::IsNullOrWhiteSpace($subnetId)
                }
                elseif ($check.StatusCode -ne 404) {
                    # Any other status is inconclusive; keep polling until the deadline.
                    $stillAttached = $true
                }

                if (-not $stillAttached) {
                    Write-Host "  -> Integration detached: $id" -ForegroundColor Green
                    [void]$pending.Remove($id)
                }
            }
            if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 10
        }

        foreach ($id in $pending) {
            Write-Host "  -> [WARN] Integration still attached after 3 minutes: $id" -ForegroundColor Yellow
        }
    }

    # 5. Report the subnet state before the plan is deleted - informational, never fatal.
    if ($WhatIfPreference) {
        Write-Host "What if: Would compare the service association links of '$SubnetName' against the pre-cleanup snapshot." -ForegroundColor Gray
    }
    else {
        $linksAfter = Get-SubnetLinkSnapshot -Vnet $VnetName -Rg $RgName -Subnet $SubnetName
        if ($null -eq $linksAfter) {
            Write-Host "  -> [WARN] Subnet '$SubnetName' not found in '$VnetName' - cannot confirm the link is gone." -ForegroundColor Yellow
        }
        else {
            $planLinksAfter = @($linksAfter | Where-Object { $_ -like "*/serverfarms/$AspName" })
            $planLinksBefore = @($linksBefore | Where-Object { $_ -like "*/serverfarms/$AspName" })

            if ($planLinksAfter.Count -eq 0) {
                Write-Host "  -> Confirmed: '$SubnetName' carries no service association link to '$AspName'." -ForegroundColor Green
            }
            elseif ($planLinksBefore.Count -gt 0) {
                Write-Host "  -> [WARN] '$SubnetName' still carries a link to '$AspName' - pre-existing link (unchanged), the known orphan. Continuing." -ForegroundColor Yellow
            }
            else {
                Write-Host "  -> [WARN] '$SubnetName' carries a NEW link to '$AspName' that was absent before cleanup. Continuing." -ForegroundColor Yellow
            }
        }
    }

    # 6. Delete the Web App (slots go with it)
    if ($app -and $PSCmdlet.ShouldProcess($AppName, 'Remove Web App (including slots)')) {
        Write-Host "Removing Web App '$AppName'..." -ForegroundColor Yellow
        Remove-AzWebApp -ResourceGroupName $RgName -Name $AppName -Force -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted" -ForegroundColor Green
    }

    # 7. Delete the autoscale setting
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

    # 8. Delete the App Service Plan
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
    $Host.SetShouldExit(1)
    exit 1
}
