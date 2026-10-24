<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.3 cleanup script's failure reporting and exit code.

.DESCRIPTION
    Found by the #121 live pass: after the 24-minute Container Apps environment delete, the
    container instance and registry deletes both threw, the script printed
    "[INFO] Not found or already deleted." for each, ended with "Cleanup Complete." and exited
    0 - while both resources were still standing in the resource group. Every catch in the
    script treated any error as absence, and the two generic ARM deletes ran with
    -ErrorAction SilentlyContinue, so nothing a delete could do was visible to the caller.

    Issue #290: the lookups still ran with -ErrorAction SilentlyContinue, so a lookup that failed
    (a 403, throttling) read as "Not found - nothing to delete." and the run exited 0 while the
    resource still stood.

    These tests run the real Remove-LabResource.ps1 in a child pwsh against a generated stub
    module and assert the observable contract, the way Lab 5.2's suite does (#105):
      1. A clean run exits 0; a run in which nothing exists exits 0, and so does one whose
         getter reports a resource not found.
      2. A resource that exists but cannot be deleted is reported as [ERROR] with the message,
         counted, and the script exits 1 without claiming completion.
      3. A lookup that fails is an [ERROR], counted, and the script exits 1 without touching or
         reporting absent the resource it could not see. The Container Apps environment stays
         when its app could not be looked up or deleted. The stub reports the failure with Write-Error, as
         the Az getters do, so a script that passes -ErrorAction SilentlyContinue swallows it.
      4. A failure does not stop the later steps.
      5. -Environment and the name overrides reach the delete calls; -WhatIf deletes nothing and
         names each resource it would delete.
      6. Issue #374: the Container Apps environment's workspaces are deleted after the
         environment - the one it logs to, found by customer id anywhere in the subscription and
         whatever its name, and any with the Portal's automatic name in the lab's group - and kept
         when the environment could not be removed or a lookup failed (counted). A workspace named
         <anything>-skycraft-swc-law (Lab 5.1's shared workspace) is never deleted: it is named
         with a [WARN].
      7. Azure's default workspace (DefaultWorkspace-<subscription id>-<region> in
         DefaultResourceGroup-<region>) that the ACI wizard's logs default sends the instance's
         logs to is deleted after the instance, and its group too when nothing else is in it; a
         group that still holds something is kept and its contents named. A failed lookup of
         either counts as a failure and deletes nothing; a workspace that only looks like the
         default one is named and kept.
    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.
    No Azure connection is needed, and none is used: the script runs through
    tests/Support/LabScriptStub.psm1 (#112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName  = 'SkyCraftAzStub33'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.ContainerInstance', 'Az.ContainerRegistry')
    $script:StubCommands    = @(
        'Get-AzContext'
        'Get-AzResource'
        'Remove-AzResource'
        'Remove-AzContainerGroup'
        'Remove-AzContainerRegistry'
        'Remove-AzResourceGroup'
    )

    # Every Az command the script calls, as a stub that records its own invocation (with the
    # name it was handed) and optionally throws. Driven by environment variables so one
    # generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzResource returns nothing
    #   SKYCRAFT_STUB_LOOKUP  'Get-AzResource:<name>=<kind>,...' makes one lookup fail (denied,
    #                         throttled) or report its resource not found (notfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>,...' makes every call of that removal throw
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
# What a stubbed removal deleted, by name: a listing after it no longer returns it, as in Azure.
$script:Removed = @{}
# The subscription the workspaces live in, which Azure's default workspace carries in its name.
$script:SubscriptionId = '00000000-0000-0000-0000-000000000000'

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Invoke-StubGate {
    param([string]$Name, [string]$Target)
    Write-StubCall -Name "$Name $Target"
    $fail = @($env:SKYCRAFT_STUB_FAIL -split ',')
    if ($fail -contains $Name -or $fail -contains "$($Name):$Target") { throw "stub failure: $Name $Target" }
    # As Azure: a second delete of the same resource finds nothing.
    if ($script:Removed[$Target]) { throw "ResourceNotFound : The Resource '$Target' was not found." }
    $script:Removed[$Target] = $true
    # SKYCRAFT_STUB_DELETE_NOTFOUND 'name,...': the delete goes through, then the cmdlet reports the
    # resource it just deleted as not found (seen live on a Log Analytics workspace, 2026-10-24).
    if (@($env:SKYCRAFT_STUB_DELETE_NOTFOUND -split ',') -contains $Target) {
        throw "ResourceNotFound : The Resource 'Microsoft.OperationalInsights/workspaces/$Target' under resource group 'stub' was not found."
    }
}

# The workspaces still standing: SKYCRAFT_STUB_WORKSPACES 'name:customerId[:resourceGroup],...',
# in the lab's group unless one is named.
function Get-StubWorkspace {
    foreach ($entry in @($env:SKYCRAFT_STUB_WORKSPACES -split ',' | Where-Object { $_ })) {
        $workspaceName, $customerId, $group = $entry -split ':', 3
        if (-not $group) { $group = $env:SKYCRAFT_STUB_LAB_RG }
        if ($script:Removed[$workspaceName]) { continue }
        [pscustomobject]@{
            Name              = $workspaceName
            ResourceType      = 'Microsoft.OperationalInsights/workspaces'
            ResourceGroupName = $group
            ResourceId        = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$group/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"
            Properties        = [pscustomobject]@{ customerId = $customerId }
        }
    }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Name = 'stub-context' }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the
# Az getters do, so the caller's -ErrorAction decides what happens to it. Returns $true when the
# lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup)
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'notfound' {
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.App/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
    }
    return $false
}

function Get-AzResource {
    [CmdletBinding()]
    param($ResourceGroupName, $ResourceType, $Name, $ResourceId, [switch]$ExpandProperties)
    # A lookup by id: not found once the stub removed it; SKYCRAFT_STUB_STILL_THERE 'name,...' keeps it.
    if ($ResourceId) {
        $idName = ($ResourceId -split '/')[-1]
        Write-StubCall -Name "Get-AzResource id:$idName"
        if ($script:Removed[$idName] -and @($env:SKYCRAFT_STUB_STILL_THERE -split ',') -notcontains $idName) {
            throw "ResourceNotFound : The Resource '$idName' was not found."
        }
        return [pscustomobject]@{ Name = $idName; ResourceId = $ResourceId }
    }
    # A lookup without a name lists a type: it is logged and keyed by the type, and one without a
    # resource group (the whole subscription) by the type followed by '@subscription'. A lookup
    # with neither lists a resource group's contents, keyed 'group:<name>'.
    $key = if ($Name) { $Name } elseif ($ResourceType -and $ResourceGroupName) { $ResourceType } elseif ($ResourceType) { "$ResourceType@subscription" } else { "group:$ResourceGroupName" }
    Write-StubCall -Name "Get-AzResource $key"
    if (Invoke-StubLookup -Name "Get-AzResource:$key" -ResourceGroup $ResourceGroupName) { return }
    if (Test-StubEmpty) { return }

    # The workspaces: a listing by group returns that group's; one without, all of them.
    if (-not $Name -and $ResourceType -eq 'Microsoft.OperationalInsights/workspaces') {
        Get-StubWorkspace | Where-Object { -not $ResourceGroupName -or $_.ResourceGroupName -eq $ResourceGroupName }
        return
    }

    # A group's contents: its workspaces, and SKYCRAFT_STUB_GROUP_EXTRA 'name:type:resourceGroup,...'.
    if (-not $Name -and -not $ResourceType) {
        Get-StubWorkspace | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName }
        foreach ($entry in @($env:SKYCRAFT_STUB_GROUP_EXTRA -split ',' | Where-Object { $_ })) {
            $extraName, $extraType, $group = $entry -split ':', 3
            if ($group -ne $ResourceGroupName) { continue }
            [pscustomobject]@{
                Name              = $extraName
                ResourceType      = $extraType
                ResourceGroupName = $group
                ResourceId        = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$group/providers/$extraType/$extraName"
            }
        }
        return
    }

    $properties = $null
    if ($ResourceType -eq 'Microsoft.ContainerInstance/containerGroups' -and $ExpandProperties) {
        # SKYCRAFT_STUB_ACI_CUSTOMERID: the workspace the container instance sends its logs to, if any.
        $properties = if ($env:SKYCRAFT_STUB_ACI_CUSTOMERID) {
            [pscustomobject]@{ diagnostics = [pscustomobject]@{ logAnalytics = [pscustomobject]@{ workspaceId = $env:SKYCRAFT_STUB_ACI_CUSTOMERID } } }
        } else {
            [pscustomobject]@{ diagnostics = $null }
        }
    }
    if ($ResourceType -eq 'Microsoft.App/managedEnvironments' -and $ExpandProperties) {
        # SKYCRAFT_STUB_CAE_CUSTOMERID: the workspace the environment sends its logs to, if any.
        $logs = if ($env:SKYCRAFT_STUB_CAE_CUSTOMERID) {
            [pscustomobject]@{ destination = 'log-analytics'; logAnalyticsConfiguration = [pscustomobject]@{ customerId = $env:SKYCRAFT_STUB_CAE_CUSTOMERID } }
        } else {
            [pscustomobject]@{ destination = 'azure-monitor' }
        }
        $properties = [pscustomobject]@{ appLogsConfiguration = $logs }
    }
    [pscustomobject]@{
        Name         = $Name
        ResourceType = $ResourceType
        ResourceId   = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/$ResourceType/$Name"
        Properties   = $properties
    }
}

function Remove-AzResource {
    [CmdletBinding()]
    param($ResourceId, [switch]$Force)
    Invoke-StubGate -Name 'Remove-AzResource' -Target (($ResourceId -split '/')[-1])
}

function Remove-AzContainerGroup {
    [CmdletBinding()]
    param($Name, $ResourceGroupName)
    Invoke-StubGate -Name 'Remove-AzContainerGroup' -Target $Name
}

function Remove-AzContainerRegistry {
    [CmdletBinding()]
    param($Name, $ResourceGroupName)
    Invoke-StubGate -Name 'Remove-AzContainerRegistry' -Target $Name
}

function Remove-AzResourceGroup {
    [CmdletBinding()]
    param($Name, [switch]$Force)
    Invoke-StubGate -Name 'Remove-AzResourceGroup' -Target $Name
}
'@

    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$Arguments = @('-Force'),
            [string[]]$Workspace = @(),
            [string]$CaeCustomerId = '',
            [string]$AciCustomerId = '',
            [string]$LabResourceGroup = 'dev-skycraft-swc-rg',
            [string[]]$GroupExtra = @(),
            [string[]]$DeleteNotFound = @(),
            [string[]]$StillThere = @(),
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $Arguments -Environment @{
            SKYCRAFT_STUB_FAIL           = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP         = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY          = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG            = $logPath
            SKYCRAFT_STUB_WORKSPACES     = $Workspace -join ','
            SKYCRAFT_STUB_CAE_CUSTOMERID = $CaeCustomerId
            SKYCRAFT_STUB_ACI_CUSTOMERID = $AciCustomerId
            SKYCRAFT_STUB_LAB_RG         = $LabResourceGroup
            SKYCRAFT_STUB_GROUP_EXTRA    = $GroupExtra -join ','
            SKYCRAFT_STUB_DELETE_NOTFOUND = $DeleteNotFound -join ','
            SKYCRAFT_STUB_STILL_THERE    = $StillThere -join ','
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean    = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing  = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:AciStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzContainerGroup'
    $script:TwoStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzResource', 'Remove-AzContainerRegistry'
    $script:Prod     = Invoke-CleanupScript -Stub $script:Stub -Arguments '-Force', '-Environment', 'prod', '-AcaName', 'prod-skycraft-swc-aca-world-02'
    $script:WhatIf   = Invoke-CleanupScript -Stub $script:Stub -Arguments '-WhatIf'
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzResource:dev-skycraft-swc-aci-auth=notfound'
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResource:dev-skycraft-swc-aci-auth=denied'
        'Get-AzResource:devskycraftswcacr01=throttled'
    )
    $script:AppDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzResource:dev-skycraft-swc-aca-world=denied'

    # #374: the Portal's auto-named workspace in the lab's group, the workspace the environment
    # sends its logs to (in another group, under a name of the learner's), and an unrelated
    # workspace that must stay.
    $script:LabWorkspaces = @(
        'workspacedevskycraftswcrg1a2b:aaaaaaaa-0000-0000-0000-000000000001'
        'dev-skycraft-swc-law-reports:bbbbbbbb-0000-0000-0000-000000000002'
        'my-env-logs:cccccccc-0000-0000-0000-000000000003:my-logs-rg'
    )
    $script:Workspaces = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:LabWorkspaces `
        -CaeCustomerId 'cccccccc-0000-0000-0000-000000000003'
    # Seen live on 2026-10-24: the environment logs to the Portal's auto-named workspace itself, so
    # the name and the relation find the same workspace.
    $script:SameWorkspace = Invoke-CleanupScript -Stub $script:Stub `
        -Workspace 'workspacedevskycraftswcrg1a2b:aaaaaaaa-0000-0000-0000-000000000001' `
        -CaeCustomerId 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:DeleteQuirk = Invoke-CleanupScript -Stub $script:Stub `
        -Workspace 'workspacedevskycraftswcrg1a2b:aaaaaaaa-0000-0000-0000-000000000001' `
        -CaeCustomerId 'aaaaaaaa-0000-0000-0000-000000000001' -DeleteNotFound 'workspacedevskycraftswcrg1a2b'
    $script:DeleteQuirkStill = Invoke-CleanupScript -Stub $script:Stub `
        -Workspace 'workspacedevskycraftswcrg1a2b:aaaaaaaa-0000-0000-0000-000000000001' `
        -CaeCustomerId 'aaaaaaaa-0000-0000-0000-000000000001' -DeleteNotFound 'workspacedevskycraftswcrg1a2b' `
        -StillThere 'workspacedevskycraftswcrg1a2b'
    $script:EnvStuck = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:LabWorkspaces `
        -CaeCustomerId 'cccccccc-0000-0000-0000-000000000003' -Fail 'Remove-AzResource:dev-skycraft-swc-cae-02'
    $script:WorkspaceDenied = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:LabWorkspaces `
        -Lookup 'Get-AzResource:Microsoft.OperationalInsights/workspaces=denied'
    $script:RelationDenied = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:LabWorkspaces `
        -CaeCustomerId 'cccccccc-0000-0000-0000-000000000003' -Lookup 'Get-AzResource:Microsoft.OperationalInsights/workspaces@subscription=denied'
    $script:WhatIfWorkspaces = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:LabWorkspaces `
        -CaeCustomerId 'cccccccc-0000-0000-0000-000000000003' -Arguments '-WhatIf'
    # Review of #374: with -Environment platform the lab's group also holds Lab 5.1's shared
    # workspace; an environment pointed at it must not get it deleted.
    $script:PlatformShared = Invoke-CleanupScript -Stub $script:Stub -Arguments '-Force', '-Environment', 'platform' `
        -LabResourceGroup 'platform-skycraft-swc-rg' -CaeCustomerId 'dddddddd-0000-0000-0000-000000000004' -Workspace @(
            'platform-skycraft-swc-law:dddddddd-0000-0000-0000-000000000004'
            'workspaceplatformskycraftswcrg9f8e:eeeeeeee-0000-0000-0000-000000000005'
        )
    # Any environment's shared workspace is kept, not only the one of the environment torn down.
    $script:OtherShared = Invoke-CleanupScript -Stub $script:Stub -CaeCustomerId '99999999-0000-0000-0000-000000000009' -Workspace @(
        'prod-skycraft-swc-law:99999999-0000-0000-0000-000000000009:prod-skycraft-swc-rg'
    )

    # The ACI wizard's default sends the instance's logs to Azure's default workspace in Azure's
    # default group: it is deleted, and the group with it when nothing else is in it.
    $script:AciDefaultWorkspace = @(
        'DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS:ffffffff-0000-0000-0000-000000000006:DefaultResourceGroup-EUS'
    )
    $script:AciLogs = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006'
    $script:AciBusyGroup = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -GroupExtra 'other-insights:microsoft.insights/components:DefaultResourceGroup-EUS'
    $script:AciLogsDenied = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -Lookup 'Get-AzResource:Microsoft.OperationalInsights/workspaces@subscription=denied'
    $script:AciGroupDenied = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -Lookup 'Get-AzResource:group:DefaultResourceGroup-EUS=denied'
    $script:AciStuckLogs = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -Fail 'Remove-AzContainerGroup'
    $script:WhatIfAci = Invoke-CleanupScript -Stub $script:Stub -Workspace $script:AciDefaultWorkspace `
        -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -Arguments '-WhatIf'
    # Azure's default name outside Azure's default group is not Azure's default workspace.
    $script:AciLookalike = Invoke-CleanupScript -Stub $script:Stub -AciCustomerId 'ffffffff-0000-0000-0000-000000000006' -Workspace @(
        'DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS:ffffffff-0000-0000-0000-000000000006:my-logs-rg'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:AciStuck, $script:TwoStuck, $script:Prod, $script:WhatIf,
        $script:NotFound, $script:LookupsFail, $script:AppDenied, $script:Workspaces, $script:EnvStuck,
        $script:WorkspaceDenied, $script:RelationDenied, $script:WhatIfWorkspaces, $script:PlatformShared,
        $script:OtherShared, $script:AciLogs, $script:AciBusyGroup, $script:AciLogsDenied, $script:AciGroupDenied,
        $script:AciStuckLogs, $script:WhatIfAci, $script:AciLookalike
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az cmdlets instead of touching Azure' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az cmdlets (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - exit code contract' {

    It 'exits 0 when every step succeeds' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'exits 0 when there is nothing to delete, and says so' {
        $script:Nothing.ExitCode | Should -Be 0
        $script:Nothing.Output   | Should -Match 'Not found'
        $script:Nothing.Calls    | Should -Not -Match '^Remove-'
    }

    It 'exits 1 when a resource exists but cannot be deleted' {
        $script:AciStuck.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($script:AciStuck.Output)"
        $script:AciStuck.Output   | Should -Match '\[ERROR\] Could not delete Container Instance ''dev-skycraft-swc-aci-auth'': stub failure'
        $script:AciStuck.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $script:AciStuck.Output   | Should -Not -Match 'Cleanup Complete'
        $script:AciStuck.Output   | Should -Not -Match 'Not found or already deleted'
    }

    It 'counts every failed step rather than stopping at the first' {
        # Remove-AzResource fails for the app, which keeps its environment; the registry fails too.
        $script:TwoStuck.ExitCode | Should -Be 1
        $script:TwoStuck.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
    }

    It 'keeps the Container Apps environment when its app could not be deleted, counted once' {
        $run = $script:TwoStuck
        $run.Output | Should -Match "\[ERROR\] Could not delete Container App 'dev-skycraft-swc-aca-world': stub failure"
        $run.Output | Should -Match 'Kept: the Container App could not be deleted and may still be in it'
        $run.Calls  | Should -Not -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $run.Calls  | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
    }

    It 'keeps running the later steps after a failure' {
        $script:AciStuck.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'exits 0 when a getter reports its resource not found, and deletes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        $run.Calls    | Should -Not -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls    | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up Container Instance 'dev-skycraft-swc-aci-auth'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match "\[ERROR\] Could not look up Container Registry 'devskycraftswcacr01'[^\r\n]*requests exceeded the limit"
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as absent, and deletes none of it' {
        $run = $script:LookupsFail
        # The workspace step legitimately finds none (#374); the two failed lookups must not read so.
        $run.Output | Should -Not -Match 'Removing Container Instance: [^\r\n]*\r?\n\s*-> \[INFO\] Not found'
        $run.Output | Should -Not -Match 'Removing Container Registry: [^\r\n]*\r?\n\s*-> \[INFO\] Not found'
        $run.Calls  | Should -Not -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls  | Should -Not -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'still deletes the resources it could look up' {
        $script:LookupsFail.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-aca-world'
        $script:LookupsFail.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
    }

    It 'keeps the Container Apps environment when its app could not be looked up' {
        $run = $script:AppDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Match 'Kept: the Container App could not be looked up'
        $run.Calls    | Should -Not -Contain 'Get-AzResource dev-skycraft-swc-cae-02'
        $run.Calls    | Should -Not -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $run.Calls    | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls    | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - the Container Apps environment''s Log Analytics workspace (#374)' {

    It 'deletes the workspace with the Portal''s automatic name, and the one the environment logs to under any name' {
        $run = $script:Workspaces
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Remove-AzResource workspacedevskycraftswcrg1a2b'
        $run.Calls | Should -Contain 'Remove-AzResource my-env-logs'
        $run.Calls | Should -Not -Contain 'Remove-AzResource dev-skycraft-swc-law-reports'
        $run.Output | Should -Match 'Cleanup Complete'
    }

    It 'deletes a workspace that both the name and the relation find once, and exits 0' {
        $run = $script:SameWorkspace
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -eq 'Remove-AzResource workspacedevskycraftswcrg1a2b' }).Count | Should -Be 1
        $run.Output | Should -Match 'Cleanup Complete'
    }

    It 'counts a workspace as deleted when the delete reports it not found and a fresh lookup agrees' {
        $run = $script:DeleteQuirk
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Get-AzResource id:workspacedevskycraftswcrg1a2b'
        $run.Output | Should -Match '-> Deleted workspacedevskycraftswcrg1a2b'
    }

    It 'fails when the delete reports not found but the workspace is still there' {
        $run = $script:DeleteQuirkStill
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Could not delete Log Analytics workspace 'workspacedevskycraftswcrg1a2b'"
    }

    It 'finds the environment''s workspace by its customer id across the subscription' {
        $script:Workspaces.Calls | Should -Contain 'Get-AzResource Microsoft.OperationalInsights/workspaces@subscription'
        # my-env-logs lives in another group: only the relation can have found it.
        $script:Workspaces.Output | Should -Match '-> Deleted my-env-logs'
    }

    It 'does not look across the subscription when the environment sends no logs to a workspace' {
        $script:Clean.Calls | Should -Not -Contain 'Get-AzResource Microsoft.OperationalInsights/workspaces@subscription'
    }

    It 'never deletes Lab 5.1''s shared workspace, even when the environment logs to it, and warns' {
        $run = $script:PlatformShared
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Get-AzResource Microsoft.OperationalInsights/workspaces'
        $run.Calls | Should -Not -Contain 'Remove-AzResource platform-skycraft-swc-law'
        $run.Calls | Should -Contain 'Remove-AzResource workspaceplatformskycraftswcrg9f8e'
        $run.Output | Should -Match '\[WARN\] Kept platform-skycraft-swc-law in platform-skycraft-swc-rg: platform-skycraft-swc-cae-02 sent its logs to it, but it is Lab 5.1''s shared workspace'
    }

    It 'never deletes another environment''s shared workspace either' {
        $run = $script:OtherShared
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Not -Contain 'Remove-AzResource prod-skycraft-swc-law'
        $run.Output | Should -Match '\[WARN\] Kept prod-skycraft-swc-law in prod-skycraft-swc-rg'
    }

    It 'names each workspace it would delete under -WhatIf, and deletes none' {
        $run = $script:WhatIfWorkspaces
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'What if: Performing the operation "Remove Log Analytics workspace" on target "workspacedevskycraftswcrg1a2b"'
        $run.Output | Should -Match 'What if: Performing the operation "Remove Log Analytics workspace" on target "my-env-logs"'
        $run.Output | Should -Not -Match 'What if: [^\r\n]*"dev-skycraft-swc-law-reports"'
        $run.Calls  | Should -Not -Match '^Remove-'
    }

    It 'deletes the workspaces after the environment, and before the instance and the registry' {
        $calls = $script:Workspaces.Calls
        $env = [array]::IndexOf($calls, 'Remove-AzResource dev-skycraft-swc-cae-02')
        $workspace = [array]::IndexOf($calls, 'Remove-AzResource workspacedevskycraftswcrg1a2b')
        $related = [array]::IndexOf($calls, 'Remove-AzResource my-env-logs')
        $aci = [array]::IndexOf($calls, 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth')
        $env | Should -BeGreaterOrEqual 0
        $workspace | Should -BeGreaterThan $env
        $related | Should -BeGreaterThan $env
        $aci | Should -BeGreaterThan ([math]::Max($workspace, $related))
    }

    It 'finds nothing to delete on the guide''s path, where no workspace exists' {
        $script:Clean.Output | Should -Match "Removing Log Analytics workspace: the one dev-skycraft-swc-cae-02 logs to \(never \*-skycraft-swc-law\), and any named workspacedevskycraftswcrg\.\.\. \(the Portal's automatic name\)\.\.\.\s+-> \[INFO\] Not found - nothing to delete\."
        @($script:Clean.Calls | Where-Object { $_ -like 'Remove-AzResource workspace*' }) | Should -BeNullOrEmpty
    }

    It 'keeps the workspaces when the environment could not be deleted, counted once' {
        $run = $script:EnvStuck
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not delete Container Apps Environment 'dev-skycraft-swc-cae-02': stub failure"
        $run.Output | Should -Match 'Kept: the Container Apps Environment could not be deleted and may still send its logs to them'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        @($run.Calls | Where-Object { $_ -in 'Remove-AzResource workspacedevskycraftswcrg1a2b', 'Remove-AzResource my-env-logs' }) | Should -BeNullOrEmpty
        $run.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'keeps the workspaces when the app could not be looked up, which keeps the environment too' {
        $run = $script:AppDenied
        $run.Output | Should -Match 'Kept: the Container App could not be looked up and may still send its logs to them'
        $run.Calls | Should -Not -Contain 'Get-AzResource Microsoft.OperationalInsights/workspaces'
    }

    It 'counts a failed workspace lookup in the group and deletes none of them' {
        $run = $script:WorkspaceDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up Log Analytics workspace 'the one dev-skycraft-swc-cae-02 logs to[^\r\n]*does not have authorization"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzResource workspace*' -or $_ -eq 'Remove-AzResource my-env-logs' }) | Should -BeNullOrEmpty
        $run.Calls | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
    }

    It 'counts a failed lookup of the environment''s workspace and deletes none of them' {
        $run = $script:RelationDenied
        $run.ExitCode | Should -Be 1 -Because "a workspace it could not see must not read as absent; output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up Log Analytics workspace 'the one dev-skycraft-swc-cae-02 logs to[^\r\n]*does not have authorization"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output | Should -Not -Match 'Removing Log Analytics workspace: [^\r\n]*\r?\n\s*-> \[INFO\] Not found'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzResource workspace*' -or $_ -eq 'Remove-AzResource my-env-logs' }) | Should -BeNullOrEmpty
        $run.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - the container instance''s default workspace (#374)' {

    It 'deletes Azure''s default workspace the instance logged to, after the instance' {
        $run = $script:AciLogs
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $aci = [array]::IndexOf($run.Calls, 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth')
        $aci | Should -BeGreaterOrEqual 0
        [array]::IndexOf($run.Calls, 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS') | Should -BeGreaterThan $aci
        $run.Output | Should -Match 'Cleanup Complete'
    }

    It 'deletes Azure''s default resource group after its workspace, when nothing else is in it' {
        $run = $script:AciLogs
        $workspace = [array]::IndexOf($run.Calls, 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS')
        $group = [array]::IndexOf($run.Calls, 'Remove-AzResourceGroup DefaultResourceGroup-EUS')
        $group | Should -BeGreaterThan $workspace -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '-> Deleted DefaultResourceGroup-EUS'
    }

    It 'keeps Azure''s default resource group when it still holds something, and names it' {
        $run = $script:AciBusyGroup
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $run.Calls | Should -Not -Contain 'Remove-AzResourceGroup DefaultResourceGroup-EUS'
        $run.Output | Should -Match '\[INFO\] Kept DefaultResourceGroup-EUS: it still holds other-insights \(microsoft\.insights/components\)\.'
    }

    It 'does not look for it when the instance sent no logs' {
        $script:Clean.Calls | Should -Not -Contain 'Get-AzResource Microsoft.OperationalInsights/workspaces@subscription'
        $script:Clean.Calls | Should -Not -Match '^Remove-AzResourceGroup'
        $script:Clean.Output | Should -Not -Match '\[WARN\]'
    }

    It 'keeps a workspace with Azure''s default name outside Azure''s default group, and names it' {
        $run = $script:AciLookalike
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Not -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $run.Calls | Should -Not -Match '^Remove-AzResourceGroup'
        $run.Output | Should -Match "\[WARN\] Kept DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS in my-logs-rg: dev-skycraft-swc-aci-auth sent its logs to it, but it is not Azure's default workspace"
        $run.Output | Should -Match "Remove-AzResource -ResourceId '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-logs-rg/providers/Microsoft\.OperationalInsights/workspaces/DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS' -Force"
    }

    It 'keeps the workspace when the instance could not be deleted, counted once' {
        $run = $script:AciStuckLogs
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Kept: the Container Instance could not be deleted and may still send its logs to it'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls | Should -Not -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $run.Calls | Should -Not -Match '^Remove-AzResourceGroup'
    }

    It 'counts a failed lookup of it as a failure and deletes neither it nor its group' {
        $run = $script:AciLogsDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up the Log Analytics workspace of dev-skycraft-swc-aci-auth \(customer id ffffffff-0000-0000-0000-000000000006\)'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output | Should -Not -Match 'nothing left behind'
        $run.Calls | Should -Not -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $run.Calls | Should -Not -Match '^Remove-AzResourceGroup'
    }

    It 'counts a failed lookup of the group''s contents as a failure and keeps the group' {
        $run = $script:AciGroupDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up the resources in resource group 'DefaultResourceGroup-EUS'[^\r\n]*does not have authorization"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls | Should -Contain 'Remove-AzResource DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS'
        $run.Calls | Should -Not -Match '^Remove-AzResourceGroup'
    }

    It 'names the workspace and the group it would delete under -WhatIf, and deletes neither' {
        $run = $script:WhatIfAci
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'What if: Performing the operation "Remove Log Analytics workspace" on target "DefaultWorkspace-00000000-0000-0000-0000-000000000000-EUS"'
        $run.Output | Should -Match 'What if: Performing the operation "Remove resource group" on target "DefaultResourceGroup-EUS"'
        $run.Calls | Should -Not -Match '^Remove-'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'deletes nothing and exits 0' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls    | Should -Not -Match '^Remove-'
        $run.Output   | Should -Match 'What if: .*dev-skycraft-swc-cae-02'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - names follow -Environment and the overrides' {

    It 'deletes the dev names by default' {
        $script:Clean.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-aca-world'
        $script:Clean.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $script:Clean.Calls | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $script:Clean.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'deletes the prod names with -Environment prod, honouring an -AcaName override' {
        $script:Prod.ExitCode | Should -Be 0
        $script:Prod.Calls | Should -Contain 'Remove-AzResource prod-skycraft-swc-aca-world-02'
        $script:Prod.Calls | Should -Contain 'Remove-AzResource prod-skycraft-swc-cae-02'
        $script:Prod.Calls | Should -Contain 'Remove-AzContainerGroup prod-skycraft-swc-aci-auth'
        $script:Prod.Calls | Should -Contain 'Remove-AzContainerRegistry prodskycraftswcacr01'
    }

    It 'deletes the app before its environment' {
        $app = [array]::IndexOf($script:Clean.Calls, 'Remove-AzResource dev-skycraft-swc-aca-world')
        $env = [array]::IndexOf($script:Clean.Calls, 'Remove-AzResource dev-skycraft-swc-cae-02')
        $app | Should -BeLessThan $env
    }
}
