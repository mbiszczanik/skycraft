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

    A lookup that fails (a 403, throttling, a transient ARM error) or a deletion that fails is
    reported as [ERROR] and counted; the later steps still run where that is safe, and the script
    exits 1 if anything failed. A resource that does not exist is not a failure: only a lookup that
    succeeds and does not find it, or a getter that reports it as not found, means "absent" -
    Test-LabNotFoundError tells the two apart (issue #290, as #255 did for Labs 1.2-2.3). The App
    Service Plan stays when the Web App or its slots could not be looked up, or the Web App could
    not be deleted: an app may still run on the plan, with its integration attached. It also stays
    when the VNet integration of a site could not be confirmed detached - the DELETE failed, got no
    answer or an unexpected status, or the site still reports a subnet after three minutes - which
    is an [ERROR], counted: deleting the plan then could orphan the serviceAssociationLink. The Web
    App stays when its slots could not be listed, because their integration could not be detached.
    The subnet checks are diagnostic: a VNet they cannot read is a [WARN], not a failure.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

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

# Counts lookups that failed and resources that exist but could not be deleted. Absent resources
# are not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzWebApp fails on a missing app with "Operation returned an invalid status code 'NotFound'".
# Get-AzVirtualNetwork reports a missing VNet as an ARM 404: "The Resource '<type>/<name>' under
# resource group '<rg>' was not found.", code ResourceNotFound; when the group is gone as well,
# "Resource group '<rg>' could not be found.", code ResourceGroupNotFound. Get-AzAppServicePlan
# returns nothing for a missing plan (its SDK accepts the 404), and the slots and the autoscale
# settings are listed, so those are empty matches, not errors. The Azure.Core clients say "Status:
# 404 (Not Found)". A missing subscription is a 404 too, but it means the context is wrong, not
# that the resource is gone, so it never reads as "absent".
function Test-LabNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add([string]$ErrorRecord)
    $evidence.Add([string]$ErrorRecord.FullyQualifiedErrorId)
    $status404 = $false
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        $evidence.Add([string]$exception.Message)
        foreach ($code in @($exception.Body.Code, $exception.Body.Error.Code, $exception.ErrorCode)) {
            if ($code) { $evidence.Add([string]$code) }
        }
        # ResponseStatusCode: the generated cmdlets' RestException, which may carry no error body.
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Runs one lookup with -ErrorAction Stop inside $Lookup, and returns what it found:
#   Value     the lookup's output, as an array - empty when the resource is absent
#   NotFound  the getter reported the resource as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the resource is gone, and the caller leaves the resource alone
function Invoke-LabLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Lookup
    )

    try {
        $value = @(& $Lookup)
        return [pscustomobject]@{ Value = $value; NotFound = $false; Failed = $false }
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "     A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

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
        distinguishable from "no links". Diagnostic only, like the subnet report it feeds: a VNet
        that could not be read is a [WARN], never counted as a failure.
    .NOTES
        Internal helper for Remove-LabResource.ps1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vnet,
        [Parameter(Mandatory)][string]$Rg,
        [Parameter(Mandatory)][string]$Subnet
    )

    $vnetObject = $null
    try {
        $vnetObject = Get-AzVirtualNetwork -Name $Vnet -ResourceGroupName $Rg -ErrorAction Stop
    }
    catch {
        if (-not (Test-LabNotFoundError -ErrorRecord $_)) {
            Write-Host "  -> [WARN] VNet '$Vnet' could not be read - its subnet links are not checked: $_" -ForegroundColor Yellow
        }
        return $null
    }
    if (-not $vnetObject) { return $null }

    $subnetObject = $vnetObject.Subnets | Where-Object { $_.Name -eq $Subnet }
    if (-not $subnetObject) { return $null }

    # Unary comma: without it an empty pipeline collapses to $null and a linkless subnet
    # would be misreported as unreadable.
    return ,@($subnetObject.ServiceAssociationLinks | ForEach-Object { $_.Link })
}

# Why the Web App and the plan must stay, when they must. Set when what runs on them could not be
# looked up or deleted; the lookup or the deletion is already counted, so keeping is not.
$keepAppReason = $null
$keepPlanReason = $null

try {
    # 2. Snapshot the subnet links BEFORE the detach. The known orphan names a plan with this very
    #    name, so only a before/after comparison can tell it apart from a link left by this run.
    #    Not needed under -WhatIf, where the comparison never runs.
    $linksBefore = if ($WhatIfPreference) { $null } else {
        Get-SubnetLinkSnapshot -Vnet $VnetName -Rg $RgName -Subnet $SubnetName
    }

    $appLookup = Invoke-LabLookup -Target "Web App '$AppName'" -Lookup {
        Get-AzWebApp -ResourceGroupName $RgName -Name $AppName -ErrorAction Stop
    }
    $app = $appLookup.Value | Select-Object -First 1
    $targets = @()
    $detached = @()

    # 3. Detach the VNet integration from the app and every slot BEFORE anything is deleted
    if ($appLookup.Failed) {
        $keepPlanReason = "Web App '$AppName' could not be looked up, and it may still run on the plan"
    }
    elseif ($app) {
        $targets = @($app.Id)
        $slotLookup = Invoke-LabLookup -Target "the deployment slots of '$AppName'" -Lookup {
            Get-AzWebAppSlot -ResourceGroupName $RgName -Name $AppName -ErrorAction Stop
        }
        if ($slotLookup.Failed) {
            # A slot runs on the plan too, and an integration it holds cannot be detached unseen.
            $keepAppReason = "its deployment slots could not be listed, so their VNet integration was not detached"
            $keepPlanReason = "the deployment slots of '$AppName' could not be looked up, and they may still run on the plan"
        }
        foreach ($slot in $slotLookup.Value) { $targets += $slot.Id }

        foreach ($id in $targets) {
            if ($PSCmdlet.ShouldProcess($id, 'Remove VNet integration')) {
                Write-Host "Detaching VNet integration: $id" -ForegroundColor Yellow
                # A DELETE that did not go through is not polled: the integration is still there,
                # and three minutes of polling would only confirm it.
                $response = $null
                $problem = $null
                try {
                    $response = Invoke-AzRestMethod -Method DELETE -Path "$id/networkConfig/virtualNetwork?api-version=$webApiVersion" -ErrorAction Stop
                }
                catch {
                    $problem = "no response from the management API: $_"
                }
                if (-not $problem -and $null -eq $response) {
                    $problem = 'no response from the management API'
                }
                elseif (-not $problem -and $response.StatusCode -notin 200, 202, 204, 404) {
                    $problem = "HTTP $($response.StatusCode): $($response.Content)"
                }

                if ($problem) {
                    $script:cleanupFailures++
                    Write-Host "  -> [ERROR] Could not detach the VNet integration - it may still be attached ($problem)" -ForegroundColor Red
                    $keepPlanReason = 'the VNet integration could not be confirmed detached from every site, and deleting the plan could orphan its serviceAssociationLink'
                }
                else {
                    $detached += $id
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
                # A poll that gets no answer is inconclusive: the site stays pending until the
                # deadline, and is then reported as still attached.
                $check = $null
                try {
                    $check = Invoke-AzRestMethod -Method GET -Path "$id/networkConfig/virtualNetwork?api-version=$webApiVersion" -ErrorAction Stop
                }
                catch {
                    $check = $null
                }
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
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Integration still attached after 3 minutes: $id" -ForegroundColor Red
            $keepPlanReason = 'the VNet integration could not be confirmed detached from every site, and deleting the plan could orphan its serviceAssociationLink'
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
    if ($app -and $keepAppReason) {
        Write-Host "Keeping Web App '$AppName': $keepAppReason." -ForegroundColor Yellow
    }
    elseif ($app -and $PSCmdlet.ShouldProcess($AppName, 'Remove Web App (including slots)')) {
        Write-Host "Removing Web App '$AppName'..." -ForegroundColor Yellow
        try {
            Remove-AzWebApp -ResourceGroupName $RgName -Name $AppName -Force -ErrorAction Stop | Out-Null
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete Web App '$AppName': $_" -ForegroundColor Red
            if (-not $keepPlanReason) { $keepPlanReason = "Web App '$AppName' could not be deleted, and it may still run on the plan" }
        }
    }

    # 7. Delete the autoscale setting
    if ($PSCmdlet.ShouldProcess($autoscaleName, 'Remove Autoscale Setting')) {
        Write-Host "Removing autoscale setting '$autoscaleName'..." -ForegroundColor Yellow
        # Listed and picked by name: Get-AzAutoscaleSetting is a generated cmdlet, and asked for
        # one name that does not exist it throws a plain "[code] : message" exception with no
        # status, which is not a recognised not-found error. A missing setting is an empty match.
        $autoscaleLookup = Invoke-LabLookup -Target "the autoscale settings in '$RgName'" -Lookup {
            Get-AzAutoscaleSetting -ResourceGroupName $RgName -ErrorAction Stop
        }
        if ($autoscaleLookup.Value | Where-Object { $_.Name -eq $autoscaleName }) {
            try {
                Remove-AzAutoscaleSetting -ResourceGroupName $RgName -Name $autoscaleName -ErrorAction Stop | Out-Null
                Write-Host "  -> Deleted" -ForegroundColor Green
            }
            catch {
                $script:cleanupFailures++
                Write-Host "  -> [ERROR] Could not delete autoscale setting '$autoscaleName': $_" -ForegroundColor Red
            }
        }
        elseif (-not $autoscaleLookup.Failed) {
            Write-Host "  -> Not found or already deleted." -ForegroundColor Gray
        }
    }

    # 8. Delete the App Service Plan - only when nothing that may still run on it went unseen.
    if ($keepPlanReason) {
        Write-Host "Keeping App Service Plan '$AspName': $keepPlanReason." -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess($AspName, 'Remove App Service Plan')) {
        Write-Host "Removing App Service Plan '$AspName'..." -ForegroundColor Yellow
        $planLookup = Invoke-LabLookup -Target "App Service Plan '$AspName'" -Lookup {
            Get-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -ErrorAction Stop
        }
        if ($planLookup.Value) {
            try {
                Remove-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -Force -ErrorAction Stop | Out-Null
                Write-Host "  -> Deleted" -ForegroundColor Green
            }
            catch {
                $script:cleanupFailures++
                Write-Host "  -> [ERROR] Could not delete App Service Plan '$AspName': $_" -ForegroundColor Red
            }
        }
        elseif (-not $planLookup.Failed) {
            Write-Host "  -> Not found or already deleted." -ForegroundColor Gray
        }
    }
}
catch {
    # Anything the steps above did not expect: counted, and the run ends here.
    $script:cleanupFailures++
    Write-Host "Cleanup failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "Cleanup completed successfully." -ForegroundColor Green
