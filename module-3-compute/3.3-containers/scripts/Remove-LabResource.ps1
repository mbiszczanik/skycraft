<#
.SYNOPSIS
    Cleans up resources created in Lab 3.3.

.DESCRIPTION
    This script removes the Container Registry, Container Instance, and Container Apps
    created for Lab 3.3. It preserves the Resource Group (<Environment>-skycraft-swc-rg) as it
    may contain resources from other labs (e.g., VNets).

    It also removes the Log Analytics workspace the Portal creates when the Container Apps
    environment is created with the wizard's default logs destination (issue #374): a workspace
    in the resource group whose name is the Portal's automatic one ('workspace' followed by the
    resource group's name without dashes and a short suffix). Left behind, Module 5 wizards
    offer it as their default workspace. The lab guide chooses Azure Monitor, which creates no
    workspace, so on the guide's path and the Bicep path this step finds nothing. Only that name
    is deleted: a workspace with any other name, in this resource group or another, is never
    deleted - not even the one the environment sent its logs to, which the script names so the
    learner can decide - and '<Environment>-skycraft-swc-law' (Lab 5.1's shared workspace) is
    excluded even if its name ever matched. The workspace stays when the environment could not
    be looked up or deleted: the environment may still send its logs to it.

    The container instance's logs are a different case. The ACI wizard's default ("Enable
    container instance logs") sends them to DefaultWorkspace-<subscription id>-<region> in
    DefaultResourceGroup-<region>, a workspace Azure shares between every service of the
    subscription that asks for a default one. When the instance still sends its logs there, the
    script names that workspace and its resource group and prints the command to delete it, but
    does not delete it: it cannot tell whether anything else in the subscription uses it.

    Under -WhatIf, and at the confirmation prompt, every delete names the resource it targets:
    the lookups run first (they change nothing), then each resource found is confirmed by name.

    A resource that does not exist is reported and skipped. A resource that exists but cannot
    be deleted is reported as [ERROR] with the Azure error message and counted; the later
    steps still run, and the script exits 1 if any step failed, so an orchestrated cycle can
    tell a failed teardown from a clean one.

    A lookup that fails (a 403, throttling, a transient ARM error) is an [ERROR] too, counted, and
    the resource it could not see is left alone. Only a lookup that succeeds and does not find the
    resource, or a getter that reports it as not found, means "absent" - Test-LabNotFoundError
    tells the two apart (issue #290, as #255 did for Labs 1.2-2.3). The Container Apps environment
    stays when its container app could not be looked up or deleted: the app may still be running
    in it. The kept environment is not counted again - the app's failure already is.

    Every exit goes through Exit-Lab (tools/LabCommon.psm1): 1 when anything failed, 0
    otherwise. Run as "pwsh -File", where #Requires -Modules would drop a bare "exit 1"
    (issue #104), it also sets the process exit code; run at a prompt or by another script,
    it leaves the session open and the code in $LASTEXITCODE (issue #257).

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER Environment
    The environment to tear down: dev, prod or platform. Default: 'dev'. Every resource name
    below defaults to the prefix this selects (#121), matching what Deploy-Bicep.ps1 deploys.

.PARAMETER ResourceGroupName
    The resource group name. Default: '<Environment>-skycraft-swc-rg'

.PARAMETER AcrName
    The container registry name. Default: '<Environment>skycraftswcacr01'

.PARAMETER AciName
    The container instance name. Default: '<Environment>-skycraft-swc-aci-auth'

.PARAMETER CaeName
    The Container Apps environment name. Default: '<Environment>-skycraft-swc-cae-02'

.PARAMETER AcaName
    The container app name. Default: '<Environment>-skycraft-swc-aca-world'. Override it to
    remove an app deployed under the pre-#121 scheme, e.g. prod-skycraft-swc-aca-world-02.

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting the dev resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment prod -Force
    Removes the prod resources from prod-skycraft-swc-rg without prompting.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.ContainerInstance, Az.ContainerRegistry

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform')]
    [string]$Environment = 'dev',

    # Defaults below read $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "$Environment-skycraft-swc-rg",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcrName = "${Environment}skycraftswcacr01",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AciName = "$Environment-skycraft-swc-aci-auth",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CaeName = "$Environment-skycraft-swc-cae-02",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcaName = "$Environment-skycraft-swc-aca-world"
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
if ($Force) { $ConfirmPreference = 'None' }

# Absence and failure are different outcomes and are reported differently (#121 live pass):
# the old catch blocks printed "Not found or already deleted" for any error, so a delete that
# threw after the long environment teardown left the registry and the instance standing
# behind a "Cleanup Complete." and an exit code of 0. Each step now looks the resource up
# first, deletes only what exists, and counts a failed lookup or a failed delete; the script
# exits 1 if any did.
$script:cleanupFailures = 0

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzResource, asked for one name and type, reports a missing resource as an ARM 404: "The
# Resource '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound; when
# the group is gone as well, "Resource group '<rg>' could not be found.", code
# ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
# 'NotFound'". The Azure.Core clients say "Status: 404 (Not Found)". A missing subscription is a
# 404 too, but it means the context is wrong, not that the resource is gone, so it never reads as
# "absent".
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

Write-Host "=== Lab 3.3 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# The name the Portal gives the workspace it creates for a new Container Apps environment:
# 'workspace', the resource group's name without dashes, and a short suffix (#374). Only a
# workspace with this name is deleted; Lab 5.1's shared workspace never is, whatever the pattern.
$autoWorkspacePattern = '^workspace-?' + [regex]::Escape(($ResourceGroupName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()) + '[0-9a-z]*$'
$sharedWorkspaceName  = "$Environment-skycraft-swc-law"
$autoWorkspaceLabel   = "named workspace$(($ResourceGroupName -replace '[^A-Za-z0-9]', '').ToLowerInvariant())... (the Portal's automatic name)"
# The customer ids of the workspaces the environment and the container instance send their logs
# to, read when each is looked up and before it is deleted.
$script:caeWorkspaceCustomerId = $null
$script:aciWorkspaceCustomerId = $null

$resourcesToDelete = @(
    @{ Name = $AcaName; Type = "Container App" },
    @{ Name = $CaeName; Type = "Container Apps Environment" },
    @{ Name = $autoWorkspaceLabel; Type = "Log Analytics workspace" },
    @{ Name = $AciName; Type = "Container Instance" },
    @{ Name = $AcrName; Type = "Container Registry" }
)

# Summary of resources targeted for deletion
Write-Host "This will delete the following resources from $($ResourceGroupName) ($Environment):" -ForegroundColor Yellow
foreach ($res in $resourcesToDelete) {
    Write-Host " - [$($res.Type)] $($res.Name)" -ForegroundColor Gray
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Delete order matters: the app must go before its environment, the environment stays when the
# app could not be looked up or deleted, and the environment's workspace stays when the
# environment could not be (KeepWhenFailed names the steps whose failure keeps it, KeepReason
# says why). A step without Find looks its one resource up by name.
$steps = @(
    @{ Type = 'Container App';              Name = $AcaName; ResourceType = 'Microsoft.App/containerApps'
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Apps Environment'; Name = $CaeName; ResourceType = 'Microsoft.App/managedEnvironments'
       KeepWhenFailed = @('Container App'); KeepReason = 'may still be in it'
       # Expanded, so the workspace step below can find the workspace this environment logs to.
       Find = { Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/managedEnvironments' -Name $CaeName -ExpandProperties -ErrorAction Stop }
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Log Analytics workspace';    Name = $autoWorkspaceLabel; ResourceType = 'Microsoft.OperationalInsights/workspaces'
       KeepWhenFailed = @('Container App', 'Container Apps Environment'); KeepReason = 'may still send its logs to it'
       # Every workspace in this resource group; the loop below keeps only the Portal's automatic
       # name for deletion (#374) and names the environment's workspace if it has another name.
       Find = { Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.OperationalInsights/workspaces' -ExpandProperties -ErrorAction Stop }
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Instance';         Name = $AciName; ResourceType = 'Microsoft.ContainerInstance/containerGroups'
       # Expanded, so the report after the loop can name the workspace the instance logs to.
       Find = { Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.ContainerInstance/containerGroups' -Name $AciName -ExpandProperties -ErrorAction Stop }
       Remove = { param($r) Remove-AzContainerGroup -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Registry';         Name = $AcrName; ResourceType = 'Microsoft.ContainerRegistry/registries'
       Remove = { param($r) Remove-AzContainerRegistry -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
)

# The steps that did not remove their resource, by type: 'looked up' or 'deleted', for the message
# of the steps they keep. A kept step counts as not deleted for the steps that depend on it.
$stepFailed = @{}

foreach ($step in $steps) {
    Write-Host "Removing $($step.Type): $($step.Name)..." -ForegroundColor Yellow
    $keptBy = @($step.KeepWhenFailed | Where-Object { $_ -and $stepFailed[$_] }) | Select-Object -First 1
    if ($keptBy) {
        # Not counted again: the failure that keeps it already is.
        Write-Host "  -> [SKIP] Kept: the $keptBy could not be $($stepFailed[$keptBy]) and $($step.KeepReason)." -ForegroundColor Yellow
        $stepFailed[$step.Type] = 'deleted'
        continue
    }
    # The Container Apps types have no base-module cmdlet in the Az gold-path, so every step
    # resolves its target through the generic ARM lookup and the app/environment/workspace steps
    # delete through it too. The lookup runs before the confirmation, so that the prompt and
    # -WhatIf name the resource itself; a lookup changes nothing.
    $find = if ($step.Find) { $step.Find } else { { Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $step.ResourceType -Name $step.Name -ErrorAction Stop } }
    $lookup = Invoke-LabLookup -Target "$($step.Type) '$($step.Name)'" -Lookup $find
    if ($lookup.Failed) {
        $stepFailed[$step.Type] = 'looked up'
        continue
    }
    $found = @($lookup.Value | Where-Object { $_ })
    if ($step.Type -eq 'Container Apps Environment' -and $found) {
        $script:caeWorkspaceCustomerId = "$($found[0].Properties.appLogsConfiguration.logAnalyticsConfiguration.customerId)"
    }
    if ($step.Type -eq 'Container Instance' -and $found) {
        $script:aciWorkspaceCustomerId = "$($found[0].Properties.diagnostics.logAnalytics.workspaceId)"
    }
    if ($step.Type -eq 'Log Analytics workspace') {
        # The environment's workspace under another name was not created by the Portal's default
        # (or was renamed by the learner), so it is named here and left alone (#374).
        foreach ($other in @($found | Where-Object {
                    $_.Name -notmatch $autoWorkspacePattern -and $script:caeWorkspaceCustomerId -and
                    "$($_.Properties.customerId)" -eq $script:caeWorkspaceCustomerId })) {
            Write-Host "  -> [INFO] Kept $($other.Name): $CaeName sent its logs to it, but it does not carry the Portal's automatic name, so this script does not delete it. Delete it yourself if nothing else uses it." -ForegroundColor Gray
        }
        $found = @($found | Where-Object { $_.Name -match $autoWorkspacePattern -and $_.Name -ne $sharedWorkspaceName })
    } else {
        # A lookup by name finds at most one resource; the workspace step may find several.
        $found = @($found | Select-Object -First 1)
    }
    if ($found.Count -eq 0) {
        Write-Host "  -> [INFO] Not found - nothing to delete." -ForegroundColor Gray
        continue
    }

    foreach ($resource in $found) {
        if (-not $PSCmdlet.ShouldProcess($resource.Name, "Remove $($step.Type)")) { continue }
        try {
            & $step.Remove $resource
            Write-Host "  -> Deleted $($resource.Name)" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $stepFailed[$step.Type] = 'deleted'
            Write-Host "  -> [ERROR] Could not delete $($step.Type) '$($resource.Name)': $_" -ForegroundColor Red
        }
    }
}

# The container instance's logs (#374): the ACI wizard's default sends them to the subscription's
# shared DefaultWorkspace-<subscription id>-<region>. It is named here, with the command to delete
# it, and never deleted: other services of the subscription may send their logs to it too.
if ($script:aciWorkspaceCustomerId) {
    Write-Host "Checking the Log Analytics workspace $AciName sent its logs to..." -ForegroundColor Yellow
    $aciWorkspaceLookup = Invoke-LabLookup -Target "the Log Analytics workspace of $AciName (customer id $($script:aciWorkspaceCustomerId))" -Lookup {
        Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -ExpandProperties -ErrorAction Stop |
            Where-Object { "$($_.Properties.customerId)" -eq $script:aciWorkspaceCustomerId }
    }
    if (-not $aciWorkspaceLookup.Failed) {
        $aciWorkspace = @($aciWorkspaceLookup.Value | Where-Object { $_ }) | Select-Object -First 1
        if ($aciWorkspace) {
            Write-Host "  -> [WARN] $AciName sent its logs to Log Analytics workspace '$($aciWorkspace.Name)' in resource group '$($aciWorkspace.ResourceGroupName)' (the Portal's 'Enable container instance logs'). This script does not delete it, because other services of your subscription may use it too. If nothing else does, delete it - and its resource group, if that is then empty - with:" -ForegroundColor Yellow
            Write-Host "     Remove-AzResource -ResourceId '$($aciWorkspace.ResourceId)' -Force" -ForegroundColor Yellow
        } else {
            Write-Host "  -> [INFO] No workspace with customer id $($script:aciWorkspaceCustomerId) in this subscription - nothing left behind." -ForegroundColor Gray
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s)." -ForegroundColor Red
    Write-Host "  See the [ERROR] lines above - the resources named there may still be in $ResourceGroupName. Re-run this script once the cause is cleared." -ForegroundColor Gray
    Exit-Lab -FailureCount 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
