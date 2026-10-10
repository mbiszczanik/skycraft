<#
.SYNOPSIS
    Cleans up resources deployed for Lab 2.2 - Secure Access.

.DESCRIPTION
    This script safely removes the resources associated with Lab 2.2, specifically ensuring that 
    dependencies between NSGs and ASGs are handled correctly. It allows for granular removal of 
    specific components (Bastion, NSGs, ASGs) or a full cleanup.
    
    It handles:
    - Dissociation of NSGs from Subnets across all VNets
    - Clearing of NSG Security Rules to break ASG dependencies
    - Removal of updated Bastion Host and Public IP
    - Removal of NSGs and ASGs

    Every step continues on error, so one stuck resource does not strand the rest. A lookup that
    fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported as
    [ERROR] and counted; if anything failed the script exits 1. A resource that does not exist is
    not a failure: only a lookup that succeeds and does not find it, or a getter that reports it
    as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue #255, as #238
    did for Lab 5.2). The NSG and ASG deletes used to run with -ErrorAction SilentlyContinue and
    print "Success" whatever happened; each one is now looked up first and deleted only if it
    exists.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER ProdResourceGroup
    The name of the Production Resource Group. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The name of the Platform Resource Group. Default: 'platform-skycraft-swc-rg'

.PARAMETER ProdVnetName
    The name of the Production VNet. Default: 'prod-skycraft-swc-vnet'

.PARAMETER RemoveBastion
    Switch to remove Azure Bastion and its Public IP.

.PARAMETER RemoveNSGs
    Switch to remove Network Security Groups.

.PARAMETER RemoveASGs
    Switch to remove Application Security Groups.

.PARAMETER RemoveAll
    Switch to remove ALL Lab 2.2 resources (Bastion, NSGs, ASGs).

.PARAMETER Force
    Switch to suppress confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1 -RemoveAll
    Removes all Lab 2.2 resources after asking for confirmation.

.EXAMPLE
    .\Remove-LabResource.ps1 -RemoveBastion -Force
    Removes only Azure Bastion without asking for confirmation.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdVnetName = 'prod-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [switch]$RemoveBastion,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveNSGs,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveASGs,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveAll,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Default to full cleanup when invoked without explicit switches (e.g. from the orchestrator)
if (-not ($RemoveBastion -or $RemoveNSGs -or $RemoveASGs -or $RemoveAll)) {
    $RemoveAll = $true
}

# Counts lookups that failed and resources that exist but could not be removed. Absent resources
# are not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzBastion, Get-AzPublicIpAddress, Get-AzNetworkSecurityGroup and
# Get-AzApplicationSecurityGroup report a missing resource as an ARM 404: "The Resource
# '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound; when the
# group is gone as well, "Resource group '<rg>' could not be found.", code ResourceGroupNotFound;
# with no error body, "Operation returned an invalid status code 'NotFound'". The code and the
# status travel in the message and in Body and Response; the Azure.Core clients say "Status: 404
# (Not Found)". Get-AzVirtualNetwork without a name is a listing and returns nothing when nothing
# matches. A missing subscription is a 404 too, but it means the context is wrong, not that the
# resource is gone, so it never reads as "absent".
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

Write-Host "=== Lab 2.2 - Cleanup Security Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# ===================================
# Remove Azure Bastion (Highest Cost)
# ===================================
if ($RemoveBastion -or $RemoveAll) {
    Write-Host "`n=== Removing Azure Bastion ===" -ForegroundColor Cyan
    
    $bastionLookup = Invoke-LabLookup -Target 'Bastion platform-skycraft-swc-bas' -Lookup {
        Get-AzBastion -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas' -ErrorAction Stop
    }
    if ($bastionLookup.Value.Count -gt 0) {
        Write-Host "Removing Bastion: platform-skycraft-swc-bas (this may take a few minutes)..." -ForegroundColor Yellow
        try {
            if ($PSCmdlet.ShouldProcess('platform-skycraft-swc-bas', 'Remove Azure Bastion')) {
                Remove-AzBastion -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas' -Force -ErrorAction Stop
                Write-Host "  -> Bastion removed successfully" -ForegroundColor Green
            }
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove Bastion" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    elseif (-not $bastionLookup.Failed) {
        Write-Host "  -> Bastion does not exist, skipping" -ForegroundColor Gray
    }

    # Remove Bastion Public IP
    Write-Host "Removing Bastion Public IP..." -ForegroundColor Yellow
    $bastionPipLookup = Invoke-LabLookup -Target 'Bastion Public IP platform-skycraft-swc-bas-pip' -Lookup {
        Get-AzPublicIpAddress -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas-pip' -ErrorAction Stop
    }
    if ($bastionPipLookup.Value.Count -gt 0) {
        try {
            if ($PSCmdlet.ShouldProcess('platform-skycraft-swc-bas-pip', 'Remove Bastion Public IP')) {
                Remove-AzPublicIpAddress -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas-pip' -Force -ErrorAction Stop
                Write-Host "  -> Bastion Public IP removed" -ForegroundColor Green
            }
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove Bastion Public IP" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    elseif (-not $bastionPipLookup.Failed) {
        Write-Host "  -> Bastion Public IP does not exist, skipping" -ForegroundColor Gray
    }
}

# ===================================
# Remove NSG Associations and NSGs
# ===================================
if ($RemoveNSGs -or $RemoveAll) {
    Write-Host "`n=== Removing Network Security Groups ===" -ForegroundColor Cyan
    
    # First, dissociate NSG from all subnets it is currently attached to
    # We do a universal check to catch any accidental or deep associations
    Write-Host "Searching for and removing NSG associations across all VNets..." -ForegroundColor Yellow
    # Remove NSGs
    # -----------------------------------
    $nsgList = @(
        @{ Name="dev-skycraft-swc-auth-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-world-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-db-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="prod-skycraft-swc-auth-nsg"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-world-nsg"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-db-nsg"; RG=$ProdResourceGroup },
        @{ Name="platform-skycraft-swc-nsg"; RG=$PlatformResourceGroup }
    )

    # 1. Dissociate first. If the VNets cannot be listed, nothing is dissociated (the [ERROR] is
    #    counted); an NSG still associated then fails its own delete below and is counted there.
    Write-Host "`nDissociating NSGs from all subnets..." -ForegroundColor Yellow
    $vnetLookup = Invoke-LabLookup -Target 'the virtual networks in the subscription' -Lookup {
        Get-AzVirtualNetwork -ErrorAction Stop
    }
    foreach ($vnet in $vnetLookup.Value) {
        $updated = $false
        foreach ($subnet in $vnet.Subnets) {
            if ($subnet.NetworkSecurityGroup) {
                # Check if this subnet's NSG is one we want to remove
                # (Simple check by name similarity or just blanket remove ID if it matches one of our targets)
                foreach ($targetNsg in $nsgList) {
                    if ($subnet.NetworkSecurityGroup.Id -match $targetNsg.Name) {
                        Write-Host "  -> Removing $($targetNsg.Name) from $($vnet.Name)/$($subnet.Name)" -ForegroundColor Yellow
                        $subnet.NetworkSecurityGroup = $null
                        $updated = $true
                        break
                    }
                }
            }
        }
        if ($updated) {
            if ($PSCmdlet.ShouldProcess($vnet.Name, 'Dissociate NSGs from subnets')) {
                try {
                    $vnet | Set-AzVirtualNetwork -ErrorAction Stop | Out-Null
                }
                catch {
                    $script:cleanupFailures++
                    Write-Host "  -> [ERROR] Could not dissociate the NSGs from $($vnet.Name): $_" -ForegroundColor Red
                }
            }
        }
    }
    
    # Wait for azure to settle
    Start-Sleep -Seconds 10

    # 2. Delete NSGs. Each is looked up first, so "does not exist" is a fact rather than a guess
    #    made from a failed delete.
    foreach ($targetNsg in $nsgList) {
        Write-Host "Removing NSG: $($targetNsg.Name)..." -ForegroundColor Yellow
        $nsgLookup = Invoke-LabLookup -Target "NSG $($targetNsg.Name)" -Lookup {
            Get-AzNetworkSecurityGroup -ResourceGroupName $targetNsg.RG -Name $targetNsg.Name -ErrorAction Stop
        }
        if ($nsgLookup.Failed) { continue }
        if ($nsgLookup.Value.Count -eq 0) {
            Write-Host "  -> NSG does not exist, skipping" -ForegroundColor Gray
            continue
        }
        try {
            if ($PSCmdlet.ShouldProcess($targetNsg.Name, 'Remove network security group')) {
                Remove-AzNetworkSecurityGroup -ResourceGroupName $targetNsg.RG -Name $targetNsg.Name -Force -ErrorAction Stop
                Write-Host "  -> Success" -ForegroundColor Green
            }
        } catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete $($targetNsg.Name): $_" -ForegroundColor Red
        }
    }
}

# ===================================
# Remove Application Security Groups
# ===================================
if ($RemoveASGs -or $RemoveAll) {
    Write-Host "`n=== Removing Application Security Groups ===" -ForegroundColor Cyan
    
    $asgList = @(
        @{ Name="dev-skycraft-swc-asg-auth"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-asg-world"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-asg-db"; RG="dev-skycraft-swc-rg" },
        @{ Name="prod-skycraft-swc-asg-auth"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-asg-world"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-asg-db"; RG=$ProdResourceGroup }
    )

    foreach ($asg in $asgList) {
        Write-Host "Removing ASG: $($asg.Name)..." -ForegroundColor Yellow
        $asgLookup = Invoke-LabLookup -Target "ASG $($asg.Name)" -Lookup {
            Get-AzApplicationSecurityGroup -ResourceGroupName $asg.RG -Name $asg.Name -ErrorAction Stop
        }
        if ($asgLookup.Failed) { continue }
        if ($asgLookup.Value.Count -eq 0) {
            Write-Host "  -> ASG does not exist, skipping" -ForegroundColor Gray
            continue
        }
        try {
            if ($PSCmdlet.ShouldProcess($asg.Name, 'Remove application security group')) {
                Remove-AzApplicationSecurityGroup -ResourceGroupName $asg.RG -Name $asg.Name -Force -ErrorAction Stop
                Write-Host "  -> Success" -ForegroundColor Green
            }
        } catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete $($asg.Name): $_" -ForegroundColor Red
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s) - see the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Cyan -BackgroundColor Black

# Show cost savings estimate
if ($RemoveBastion -or $RemoveAll) {
    Write-Host "`n[INFO] Estimated monthly savings:" -ForegroundColor Green
    Write-Host '  - Azure Bastion Basic SKU: ~$140/month' -ForegroundColor Gray
    Write-Host '  - Public IP: ~$3/month' -ForegroundColor Gray
    Write-Host '  Total: ~$143/month' -ForegroundColor Green
}

Write-Host "`nNote: NSGs and ASGs have no compute costs, only minimal metadata storage." -ForegroundColor Gray
Write-Host "You can recreate resources anytime using Deploy-Security.ps1 or Deploy-Bicep.ps1" -ForegroundColor Gray
