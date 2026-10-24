<#
.SYNOPSIS
    Cleans up resources created in Lab 3.3.

.DESCRIPTION
    This script removes the Container Registry, Container Instance, and Container Apps
    created for Lab 3.3. It preserves the Resource Group (<Environment>-skycraft-swc-rg) as it
    may contain resources from other labs (e.g., VNets).

    It also removes the Log Analytics workspaces that exist only because of this lab (issue #374);
    no other lab uses them (Module 5 uses '<Environment>-skycraft-swc-law'), and left behind they
    cost money per GB and Module 5 wizards offer them as their default workspace. The lab guide
    turns both workspace-creating defaults off, so on the guide's path and the Bicep path these
    steps find nothing.
      - The Container Apps environment's workspace: the one the environment sends its logs to,
        found by relation (the customer id in its appLogsConfiguration) anywhere in the
        subscription and whatever its name, and any workspace in the resource group that carries
        the Portal's automatic name ('workspace' followed by the resource group's name without
        dashes and a short suffix), which stays behind when the learner switched the environment
        to Azure Monitor afterwards. They are deleted after the environment, and kept when the
        environment could not be looked up or deleted: it may still send its logs to them.
      - The container instance's workspace: the ACI wizard's default ("Enable container instance
        logs") sends the logs to Azure's default workspace, DefaultWorkspace-<subscription id>-
        <region> in DefaultResourceGroup-<region>. When the instance sends its logs to that
        workspace (found by relation, through the customer id in its diagnostics), it is deleted
        after the instance, and kept when the instance could not be deleted. A workspace with any
        other name is named and kept. The script finds it only through the instance: once the
        instance is recreated without logs, as the guide says, the old workspace is deleted by hand.
      - Azure's default resource group: once its default workspace is deleted, the group is
        deleted too when nothing else is in it; otherwise it stays and the script names what is
        in it.
    A workspace named '<anything>-skycraft-swc-law' (Lab 5.1's shared workspace) is never
    deleted, whatever points at it: the script names it with a [WARN] and keeps it.

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

# Whether a workspace is Azure's default one: DefaultWorkspace-<subscription id>-<region> in
# DefaultResourceGroup-<region>, with the subscription it lives in and the same region code in
# both names. Only such a workspace, found through the container instance, is deleted (#374).
# Deletes a Log Analytics workspace. The delete is asynchronous, and Remove-AzResource can report
# the workspace it has just deleted as ResourceNotFound (seen 2026-10-24): that counts as deleted
# only when a fresh lookup by id also reports it not found.
function Invoke-LabWorkspaceDelete {
    param([Parameter(Mandatory)][string]$ResourceId)
    try {
        Remove-AzResource -ResourceId $ResourceId -Force -ErrorAction Stop | Out-Null
    } catch {
        if (-not (Test-LabNotFoundError -ErrorRecord $_)) { throw }
        $deleteError = $_
        try {
            $null = Get-AzResource -ResourceId $ResourceId -ErrorAction Stop
        } catch {
            if (Test-LabNotFoundError -ErrorRecord $_) { return }
            throw
        }
        throw $deleteError
    }
}

function Test-LabDefaultWorkspace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Workspace
    )

    if ("$($Workspace.ResourceId)" -notmatch '^/subscriptions/(?<subscription>[^/]+)/') { return $false }
    $subscriptionId = $Matches.subscription
    if ("$($Workspace.Name)" -notmatch "^DefaultWorkspace-$([regex]::Escape($subscriptionId))-(?<region>[A-Za-z0-9]+)$") { return $false }
    return "$($Workspace.ResourceGroupName)" -eq "DefaultResourceGroup-$($Matches.region)"
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
# 'workspace', the resource group's name without dashes, and a short suffix (#374).
$autoWorkspacePattern = '^workspace-?' + [regex]::Escape(($ResourceGroupName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()) + '[0-9a-z]*$'
# Lab 5.1's shared workspace, '<env>-skycraft-swc-law' for any environment: Module 5 uses it, so
# it is never deleted, whatever points at it.
$sharedWorkspacePattern = '^.+-skycraft-swc-law$'
$caeWorkspaceLabel = "the one $CaeName logs to (never *-skycraft-swc-law), and any named workspace$(($ResourceGroupName -replace '[^A-Za-z0-9]', '').ToLowerInvariant())... (the Portal's automatic name)"
# The customer ids of the workspaces the environment and the container instance send their logs
# to, read when each is looked up and before it is deleted.
$script:caeWorkspaceCustomerId = $null
$script:aciWorkspaceCustomerId = $null
# Azure's default workspaces deleted (or, under -WhatIf, that would be): their resource groups are
# checked at the end and deleted when nothing else is in them.
$script:removedDefaultWorkspaces = [System.Collections.Generic.List[object]]::new()

$resourcesToDelete = @(
    @{ Name = $AcaName; Type = "Container App" },
    @{ Name = $CaeName; Type = "Container Apps Environment" },
    @{ Name = $caeWorkspaceLabel; Type = "Log Analytics workspace" },
    @{ Name = $AciName; Type = "Container Instance" },
    @{ Name = $AcrName; Type = "Container Registry" },
    @{ Name = "DefaultWorkspace-<subscription id>-<region>, only if $AciName sends its logs to it, then DefaultResourceGroup-<region> if nothing else is in it"; Type = "Log Analytics workspace" }
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
    @{ Type = 'Log Analytics workspace';    Name = $caeWorkspaceLabel; ResourceType = 'Microsoft.OperationalInsights/workspaces'
       KeepWhenFailed = @('Container App', 'Container Apps Environment'); KeepReason = 'may still send its logs to them'
       # The workspaces in this resource group with the Portal's automatic name, and the one the
       # environment sends its logs to, found by its customer id anywhere in the subscription
       # (#374). If either listing fails, the step fails and deletes none of them.
       Find = {
           Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.OperationalInsights/workspaces' -ErrorAction Stop |
               Where-Object { $_.Name -match $autoWorkspacePattern }
           if ($script:caeWorkspaceCustomerId) {
               Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -ExpandProperties -ErrorAction Stop |
                   Where-Object { "$($_.Properties.customerId)" -eq $script:caeWorkspaceCustomerId }
           }
       }
       Remove = { param($r) Invoke-LabWorkspaceDelete -ResourceId $r.ResourceId } }
    @{ Type = 'Container Instance';         Name = $AciName; ResourceType = 'Microsoft.ContainerInstance/containerGroups'
       # Expanded, so the step after the loop can find the workspace the instance logs to.
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
        # The environment's workspace often carries the automatic name too: delete it once.
        $found = @($found | Sort-Object -Property ResourceId -Unique)
        # Only a relation can bring Lab 5.1's shared workspace here: the automatic name never matches it.
        foreach ($shared in @($found | Where-Object { $_.Name -match $sharedWorkspacePattern })) {
            Write-Host "  -> [WARN] Kept $($shared.Name) in $($shared.ResourceGroupName): $CaeName sent its logs to it, but it is Lab 5.1's shared workspace, which Module 5 uses, so this script never deletes it." -ForegroundColor Yellow
        }
        $found = @($found | Where-Object { $_.Name -notmatch $sharedWorkspacePattern })
    } else {
        # A lookup by name finds at most one resource; the workspace step may find several.
        $found = @($found | Select-Object -First 1)
    }
    if ($found.Count -eq 0) {
        Write-Host "  -> [INFO] Not found - nothing to delete." -ForegroundColor Gray
        continue
    }

    foreach ($resource in $found) {
        $isDefaultWorkspace = $step.Type -eq 'Log Analytics workspace' -and (Test-LabDefaultWorkspace -Workspace $resource)
        if (-not $PSCmdlet.ShouldProcess($resource.Name, "Remove $($step.Type)")) {
            # Under -WhatIf the default group check still runs, so it shows what it would delete.
            if ($WhatIfPreference -and $isDefaultWorkspace) { $script:removedDefaultWorkspaces.Add($resource) }
            continue
        }
        try {
            & $step.Remove $resource
            Write-Host "  -> Deleted $($resource.Name)" -ForegroundColor Green
            if ($isDefaultWorkspace) { $script:removedDefaultWorkspaces.Add($resource) }
        } catch {
            $script:cleanupFailures++
            $stepFailed[$step.Type] = 'deleted'
            Write-Host "  -> [ERROR] Could not delete $($step.Type) '$($resource.Name)': $_" -ForegroundColor Red
        }
    }
}

# The container instance's logs (#374): the ACI wizard's default ("Enable container instance
# logs") sends them to Azure's default workspace, DefaultWorkspace-<subscription id>-<region> in
# DefaultResourceGroup-<region>. No other lab uses it (Module 5 uses <env>-skycraft-swc-law), so
# once the instance is gone it is deleted - found through the customer id the instance sent its
# logs to, never by its name alone. A workspace with any other name is named and kept.
if ($script:aciWorkspaceCustomerId) {
    Write-Host "Removing the Log Analytics workspace $AciName sent its logs to (only Azure's default DefaultWorkspace-...)..." -ForegroundColor Yellow
    if ($stepFailed['Container Instance']) {
        # Not counted again: the instance's failure already is.
        Write-Host "  -> [SKIP] Kept: the Container Instance could not be $($stepFailed['Container Instance']) and may still send its logs to it." -ForegroundColor Yellow
    } else {
        $aciWorkspaceLookup = Invoke-LabLookup -Target "the Log Analytics workspace of $AciName (customer id $($script:aciWorkspaceCustomerId))" -Lookup {
            Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -ExpandProperties -ErrorAction Stop |
                Where-Object { "$($_.Properties.customerId)" -eq $script:aciWorkspaceCustomerId }
        }
        $aciWorkspace = @($aciWorkspaceLookup.Value | Where-Object { $_ }) | Select-Object -First 1
        if ($aciWorkspaceLookup.Failed) {
            # Counted by Invoke-LabLookup; the workspace it could not see is left alone.
        } elseif (-not $aciWorkspace) {
            Write-Host "  -> [INFO] No workspace with customer id $($script:aciWorkspaceCustomerId) in this subscription - nothing left behind." -ForegroundColor Gray
        } elseif ($aciWorkspace.Name -match $sharedWorkspacePattern) {
            Write-Host "  -> [WARN] Kept $($aciWorkspace.Name) in $($aciWorkspace.ResourceGroupName): $AciName sent its logs to it, but it is Lab 5.1's shared workspace, which Module 5 uses, so this script never deletes it." -ForegroundColor Yellow
        } elseif (-not (Test-LabDefaultWorkspace -Workspace $aciWorkspace)) {
            Write-Host "  -> [WARN] Kept $($aciWorkspace.Name) in $($aciWorkspace.ResourceGroupName): $AciName sent its logs to it, but it is not Azure's default workspace (DefaultWorkspace-<subscription id>-<region> in DefaultResourceGroup-<region>), so this script does not delete it. If nothing else uses it, delete it with:" -ForegroundColor Yellow
            Write-Host "     Remove-AzResource -ResourceId '$($aciWorkspace.ResourceId)' -Force" -ForegroundColor Yellow
        } elseif (-not $PSCmdlet.ShouldProcess($aciWorkspace.Name, 'Remove Log Analytics workspace')) {
            # Under -WhatIf the default group check still runs, so it shows what it would delete.
            if ($WhatIfPreference) { $script:removedDefaultWorkspaces.Add($aciWorkspace) }
        } else {
            try {
                Invoke-LabWorkspaceDelete -ResourceId $aciWorkspace.ResourceId
                Write-Host "  -> Deleted $($aciWorkspace.Name)" -ForegroundColor Green
                $script:removedDefaultWorkspaces.Add($aciWorkspace)
            } catch {
                $script:cleanupFailures++
                Write-Host "  -> [ERROR] Could not delete Log Analytics workspace '$($aciWorkspace.Name)': $_" -ForegroundColor Red
            }
        }
    }
}

# Azure's default resource group, once its default workspace is deleted (#374): deleted when
# nothing else is in it, kept and its contents named otherwise. Only a group that held a default
# workspace this run deleted is checked, so no other group is ever a candidate.
foreach ($defaultGroup in @($script:removedDefaultWorkspaces | Group-Object -Property ResourceGroupName)) {
    $defaultGroupName = $defaultGroup.Name
    Write-Host "Removing resource group $defaultGroupName if nothing else is in it..." -ForegroundColor Yellow
    $groupLookup = Invoke-LabLookup -Target "the resources in resource group '$defaultGroupName'" -Lookup {
        Get-AzResource -ResourceGroupName $defaultGroupName -ErrorAction Stop
    }
    if ($groupLookup.Failed) { continue }
    if ($groupLookup.NotFound) {
        Write-Host "  -> [INFO] Not found - nothing to delete." -ForegroundColor Gray
        continue
    }
    # The deleted workspace is left out: under -WhatIf it is still there, and ARM may still list a
    # resource for a moment after its delete returns.
    $deletedIds = @($defaultGroup.Group | ForEach-Object { "$($_.ResourceId)" })
    $remaining = @($groupLookup.Value | Where-Object { $_ -and "$($_.ResourceId)" -notin $deletedIds })
    if ($remaining.Count -gt 0) {
        Write-Host "  -> [INFO] Kept $($defaultGroupName): it still holds $(@($remaining | ForEach-Object { "$($_.Name) ($($_.ResourceType))" }) -join ', ')." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($defaultGroupName, 'Remove resource group')) { continue }
    try {
        Remove-AzResourceGroup -Name $defaultGroupName -Force -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted $defaultGroupName" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not delete resource group '$defaultGroupName': $_" -ForegroundColor Red
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s)." -ForegroundColor Red
    Write-Host "  See the [ERROR] lines above - the resources named there may still be in $ResourceGroupName. Re-run this script once the cause is cleared." -ForegroundColor Gray
    Exit-Lab -FailureCount 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
