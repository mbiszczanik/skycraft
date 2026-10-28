<#
.SYNOPSIS
    Pester 5 tests for the Lab 5.1 cleanup: when it reports an object absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked every object up with -ErrorAction
    SilentlyContinue, so a lookup that failed - a 403, throttling, a transient ARM error - read as
    "absent"; it printed a failed deletion as a warning, and it never exited 1. These tests run the
    real Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands
    it calls, and assert the observable contract:

      1. Everything the lab created is removed when it is present, and the run exits 0. Objects
         the lab did not create are left alone. The alert rule and the data collection rule are
         found as Test-Lab.ps1 finds them, by what they watch or apply to, so a rule the Portal
         left in the VM's group is removed too (#362).
      2. An object that is absent - an empty listing, or a getter that reports it not found - is
         not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         reporting absent the object it could not see. What depends on that object keeps it: the
         action group stays while the alert could not be looked up, the data collection rule while
         its association could not, and the workspace while the rule may still send to it. The
         stub reports the failure with Write-Error, as the Az getters do, so a script that passes
         -ErrorAction SilentlyContinue swallows it.
      4. A deletion that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. The log search alert of Step 5.1.8 is found as Test-Lab.ps1 finds it (#357): a Heartbeat
         rule on a SkyCraft VM or the lab's workspace, that notifies the lab's action group or
         carries the Bicep's name. Another Heartbeat rule and a Perf rule on the VM stay. The
         action group stays while the rules could not be listed or one could not be deleted.

    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard, enforced by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab51CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.Storage', 'Az.OperationalInsights', 'Az.Monitor')

    # Every Az command the script calls, before #290 and after it. The getters accept both the
    # by-name form the script used before #290 and the listing it uses now, so a revert runs
    # against the stub instead of a subscription.
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzMetricAlertRuleV2'
        'Remove-AzMetricAlertRuleV2'
        'Get-AzVM'
        'Get-AzDataCollectionRuleAssociation'
        'Remove-AzDataCollectionRuleAssociation'
        'Get-AzResource'
        'Remove-AzResource'
        'Get-AzActionGroup'
        'Remove-AzActionGroup'
        'Get-AzStorageAccount'
        'Get-AzDiagnosticSetting'
        'Remove-AzDiagnosticSetting'
        'Get-AzOperationalInsightsWorkspace'
        'Remove-AzOperationalInsightsWorkspace'
    )

    # Every command records its own invocation. By default the subscription holds everything the
    # lab creates, next to an unrelated alert, association, action group, diagnostic setting and
    # workspace. Environment variables change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: the platform group and the VM are gone,
    #                         and the getters report them not found, as the real ones do
    #   SKYCRAFT_STUB_BARE    '1' keeps the groups, the VM and the storage account, but none of the
    #                         lab's own objects
    #   SKYCRAFT_STUB_TWO     '1' puts a second storage account in the platform group, listed
    #                         after the first; the lab's diagnostic setting is on the second one
    #   SKYCRAFT_STUB_PORTAL  '1' builds the alert rule and the data collection rule as the Portal
    #                         does (#362): the alert rule left in the VM's group, and VM insights'
    #                         'MSVMI-<vm>' rule in the VM's group instead of 'skycraft-vm-dcr';
    #                         the log search alert under the learner's own name, in the VM's
    #                         group, scoped to the workspace
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled)
    #   SKYCRAFT_STUB_FAIL    '<command>:<name>,...' makes one deletion throw
    # A lookup is named after its command ('Get-AzDiagnosticSetting:<account>' for the diagnostic
    # settings, 'Get-AzVM:<group>' for a group's VMs, 'Get-AzResource:<name>' for a data collection
    # rule, 'Get-AzResource:scheduledQueryRules' for the log search alerts); a deletion is logged as '<command>:<name>' ('<account>/<name>' for a setting), and as
    # '<command>:<group>/<name>' too for an alert rule or a data collection rule.
    # A missing data collection rule is reported the way Az.Resources can report it: a status-only
    # 404 (an exception whose inner CloudException carries the 404 response) with no not-found
    # wording.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
$script:VmId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm"
$script:StorageRoot = "/subscriptions/$($script:SubscriptionId)/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts"
$script:RuleRoot = "/subscriptions/$($script:SubscriptionId)/resourceGroups/{0}/providers/Microsoft.Insights/dataCollectionRules"

# The shape of a status-only 404 from Az.Resources: ResourceManagerCloudException around the SDK's
# CloudException, whose Response carries the status. Neither message says "not found".
if (-not ('SkyCraftLab51Stub.CloudException' -as [type])) {
    Add-Type -TypeDefinition @"
namespace SkyCraftLab51Stub
{
    public class CloudException : System.Exception
    {
        public CloudException(string message) : base(message) { }
        public object Response { get; set; }
    }
    public class ResourceManagerCloudException : System.Exception
    {
        public ResourceManagerCloudException(string message, System.Exception inner) : base(message, inner) { }
    }
}
"@
}

function Write-StubStatus404 {
    $inner = [SkyCraftLab51Stub.CloudException]::new('Long running operation failed.')
    $inner.Response = [pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::NotFound }
    Write-Error -Exception ([SkyCraftLab51Stub.ResourceManagerCloudException]::new('The request failed.', $inner)) -ErrorId 'StubCloudError'
}

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }
function Test-StubBare { return $env:SKYCRAFT_STUB_BARE -eq '1' }
function Test-StubPortal { return $env:SKYCRAFT_STUB_PORTAL -eq '1' }

# A deletion is logged as '<command>:<name>' and, for an object in a group, as
# '<command>:<group>/<name>' as well.
function Invoke-StubRemoval {
    param([string]$Command, [string]$Name, [string]$Group)
    Write-StubCall -Name $Command
    Write-StubCall -Name "${Command}:$Name"
    if ($Group) { Write-StubCall -Name "${Command}:$Group/$Name" }
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains "${Command}:$Name") { throw "stub failure: ${Command} $Name" }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the Az
# getters do, so the caller's -ErrorAction decides what happens to it. -Gone names what the real
# getter reports as not found in the empty subscription ('group' or 'resource'). Returns $true when
# the lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [string]$Gone)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    if (-not $kind -and $Gone -and (Test-StubEmpty)) { $kind = $Gone }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'group' {
            Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group 'platform-skycraft-swc-rg' could not be found."
            return $true
        }
        'resource' {
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'stub/$Name' under resource group 'stub-rg' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
    }
    return $false
}

# A listing: the lab's own object (unless the subscription is bare) and an unrelated one, or the
# one -Name asks for (the by-name form the script used before #290).
function Select-StubItem {
    param([string]$Own, [string]$Other, [string]$Name)
    $items = @([pscustomobject]@{ Name = $Other })
    if (-not (Test-StubBare)) { $items += [pscustomobject]@{ Name = $Own } }
    if ($Name) { $items = @($items | Where-Object { $_.Name -eq $Name }) }
    $items
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = $script:SubscriptionId; Name = 'stub-subscription' }
        Account      = [pscustomobject]@{ Id = 'stub-account' }
    }
}

function New-StubAlert {
    param([string]$Name, [string]$Group, [string]$Scope)
    [pscustomobject]@{
        Name          = $Name
        ResourceGroup = $Group
        Id            = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$Group/providers/Microsoft.Insights/metricAlerts/$Name"
        Scopes        = @($Scope)
    }
}

# The subscription's alert rules. The lab's rule watches the VM, from the platform group, or from
# the VM's group as the Portal defaults it (SKYCRAFT_STUB_PORTAL). Next to it: an unrelated rule in
# the platform group, a VM insights recommended rule on the same VM, and a rule that carries the
# lab's name but sits in another group and watches another VM - not the lab's either.
function Get-AzMetricAlertRuleV2 {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzMetricAlertRuleV2') { return }
    if (Test-StubEmpty) { return }
    $otherVm = "/subscriptions/$($script:SubscriptionId)/resourceGroups/other-rg/providers/Microsoft.Compute/virtualMachines/other-vm"
    $items = @(
        New-StubAlert -Name 'unrelated-alert' -Group 'platform-skycraft-swc-rg' -Scope $script:StorageRoot
        New-StubAlert -Name 'unrelated-recommended-cpu' -Group 'dev-skycraft-swc-rg' -Scope $script:VmId
        New-StubAlert -Name 'skycraft-cpu-alert' -Group 'other-rg' -Scope $otherVm
    )
    if (-not (Test-StubBare)) {
        $group = if (Test-StubPortal) { 'dev-skycraft-swc-rg' } else { 'platform-skycraft-swc-rg' }
        $items += New-StubAlert -Name 'skycraft-cpu-alert' -Group $group -Scope $script:VmId
    }
    if ($ResourceGroupName) { $items = @($items | Where-Object { $_.ResourceGroup -eq $ResourceGroupName }) }
    if ($Name) { $items = @($items | Where-Object { $_.Name -eq $Name }) }
    $items
}

function Remove-AzMetricAlertRuleV2 {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzMetricAlertRuleV2' -Name $Name -Group $ResourceGroupName
}

# The VMs of a group: the dev group holds the lab's VM, the prod group none. Looked up as
# 'Get-AzVM:<group>'.
function Get-AzVM {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzVM:$ResourceGroupName" -Gone 'group') { return }
    if ($ResourceGroupName -ne 'dev-skycraft-swc-rg') { return }
    $vm = [pscustomobject]@{ Name = 'dev-skycraft-swc-auth-vm'; Id = $script:VmId }
    if ($Name -and $Name -ne $vm.Name) { return }
    $vm
}

# The VM's associations: the lab's (the Bicep's to skycraft-vm-dcr, or the Portal's to its MSVMI
# rule in the VM's group), one to an unrelated rule that sends elsewhere, and one to a data
# collection endpoint, which names no rule.
function Get-AzDataCollectionRuleAssociation {
    [CmdletBinding()]
    param([string]$ResourceUri, [string]$AssociationName)
    if (Invoke-StubLookup -Name 'Get-AzDataCollectionRuleAssociation' -Gone 'resource') { return }
    $items = @(
        [pscustomobject]@{ Name = 'unrelated-assoc'; DataCollectionRuleId = "$($script:RuleRoot -f 'other-rg')/unrelated-dcr" }
        [pscustomobject]@{ Name = 'configurationAccessEndpoint'; DataCollectionRuleId = $null }
    )
    if (Test-StubPortal) {
        $items += [pscustomobject]@{ Name = 'MSVMI-dev-skycraft-swc-auth-vm-assoc'; DataCollectionRuleId = "$($script:RuleRoot -f 'dev-skycraft-swc-rg')/MSVMI-dev-skycraft-swc-auth-vm" }
    }
    elseif (-not (Test-StubBare)) {
        $items += [pscustomobject]@{ Name = 'skycraft-vminsights-dcr-assoc'; DataCollectionRuleId = "$($script:RuleRoot -f 'platform-skycraft-swc-rg')/skycraft-vm-dcr" }
    }
    if ($AssociationName) { $items = @($items | Where-Object { $_.Name -eq $AssociationName }) }
    $items
}

function Remove-AzDataCollectionRuleAssociation {
    [CmdletBinding()]
    param([string]$ResourceUri, [string]$AssociationName)
    Invoke-StubRemoval -Command 'Remove-AzDataCollectionRuleAssociation' -Name $AssociationName
}

# A data collection rule, read by its id and looked up as 'Get-AzResource:<name>'. The lab's rules
# send to the lab's workspace; the unrelated one sends to another. The Bicep's rule exists unless
# the subscription is bare or Portal-built, the MSVMI rule only when it is Portal-built; a missing
# rule is reported as a status-only 404.
function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$ResourceType, [switch]$ExpandProperties)
    if ($ResourceType -eq 'Microsoft.Insights/scheduledQueryRules') { return Get-StubLogAlerts }
    $name  = ($ResourceId -split '/')[-1]
    $group = ($ResourceId -split '/')[4]
    if (Invoke-StubLookup -Name "Get-AzResource:$name" -Gone 'group') { return }
    $exists = switch ($name) {
        'skycraft-vm-dcr'                { -not (Test-StubBare) -and -not (Test-StubPortal) }
        'MSVMI-dev-skycraft-swc-auth-vm' { Test-StubPortal }
        'unrelated-dcr'                  { $true }
        default                          { $false }
    }
    if (-not $exists) {
        Write-StubStatus404
        return
    }
    $workspace = if ($name -eq 'unrelated-dcr') { 'unrelated-law' } else { 'platform-skycraft-swc-law' }
    [pscustomobject]@{
        Name              = $name
        ResourceGroupName = $group
        ResourceId        = $ResourceId
        Properties        = [pscustomobject]@{
            destinations = [pscustomobject]@{
                logAnalytics = @([pscustomobject]@{ workspaceResourceId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.OperationalInsights/workspaces/$workspace" })
            }
        }
    }
}

# The subscription's log search alerts, raw ARM shape. The lab's notifies the lab's action group
# (the Portal writes the id in lower case); next to it a Heartbeat rule on another VM, a Perf rule
# on the lab's VM, and a Heartbeat rule on the lab's VM that notifies another group under a
# learner's name - none of them the lab's.
function New-StubLogAlert {
    param([string]$Name, [string]$Group, [string]$Scope, [string]$Query = 'Heartbeat', [string]$ActionGroup = 'platform-skycraft-swc-rg/skycraft-ops-ag')
    $agGroup, $agName = $ActionGroup -split '/'
    [pscustomobject]@{
        Name              = $Name
        ResourceGroupName = $Group
        ResourceId        = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$Group/providers/Microsoft.Insights/scheduledQueryRules/$Name"
        Properties        = [pscustomobject]@{
            scopes   = @($Scope)
            criteria = [pscustomobject]@{ allOf = @([pscustomobject]@{ query = $Query }) }
            actions  = [pscustomobject]@{ actionGroups = @("/subscriptions/$($script:SubscriptionId)/resourcegroups/$agGroup/providers/microsoft.insights/actiongroups/$agName".ToLowerInvariant()) }
        }
    }
}

function Get-StubLogAlerts {
    if (Invoke-StubLookup -Name 'Get-AzResource:scheduledQueryRules') { return }
    if (Test-StubEmpty) { return }
    $otherVm = "/subscriptions/$($script:SubscriptionId)/resourceGroups/other-rg/providers/Microsoft.Compute/virtualMachines/other-vm"
    New-StubLogAlert -Name 'unrelated-heartbeat-other-vm' -Group 'other-rg' -Scope $otherVm
    New-StubLogAlert -Name 'unrelated-perf-rows' -Group 'dev-skycraft-swc-rg' -Scope $script:VmId -Query 'Perf | where CounterName == "% Processor Time"'
    New-StubLogAlert -Name 'unrelated-heartbeat-team' -Group 'dev-skycraft-swc-rg' -Scope $script:VmId -ActionGroup 'dev-skycraft-swc-rg/team-ag'
    if (Test-StubBare) { return }
    if (Test-StubPortal) {
        $workspace = "/subscriptions/$($script:SubscriptionId)/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law"
        New-StubLogAlert -Name 'vm-heartbeat-missing' -Group 'dev-skycraft-swc-rg' -Scope $workspace.ToLowerInvariant() -Query 'Heartbeat | where Computer == "dev-skycraft-swc-auth-vm"'
    }
    else {
        New-StubLogAlert -Name 'skycraft-heartbeat-alert' -Group 'platform-skycraft-swc-rg' -Scope $script:VmId
    }
}

function Remove-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzResource' -Name (($ResourceId -split '/')[-1]) -Group (($ResourceId -split '/')[4])
}

function Get-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzActionGroup' -Gone 'group') { return }
    Select-StubItem -Own 'skycraft-ops-ag' -Other 'unrelated-ag' -Name $Name
}

function Remove-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzActionGroup' -Name $Name
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzStorageAccount' -Gone 'group') { return }
    [pscustomobject]@{ StorageAccountName = 'platformskycraftswcsa'; Id = "$($script:StorageRoot)/platformskycraftswcsa" }
    if ($env:SKYCRAFT_STUB_TWO -eq '1') {
        [pscustomobject]@{ StorageAccountName = 'platformskycraftswcsb'; Id = "$($script:StorageRoot)/platformskycraftswcsb" }
    }
}

function Get-AzDiagnosticSetting {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$Name)
    $account = ($ResourceId -split '/')[-3]
    if (Invoke-StubLookup -Name "Get-AzDiagnosticSetting:$account" -Gone 'resource') { return }
    # With two accounts the lab's setting is on the second; the first carries only another one.
    $onThisAccount = if ($env:SKYCRAFT_STUB_TWO -eq '1') { $account -eq 'platformskycraftswcsb' } else { $true }
    if (-not $onThisAccount) {
        $items = @([pscustomobject]@{ Name = 'unrelated-diag' })
        if ($Name) { $items = @($items | Where-Object { $_.Name -eq $Name }) }
        return $items
    }
    Select-StubItem -Own 'skycraft-storage-diag' -Other 'unrelated-diag' -Name $Name
}

function Remove-AzDiagnosticSetting {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzDiagnosticSetting' -Name "$(($ResourceId -split '/')[-3])/$Name"
}

function Get-AzOperationalInsightsWorkspace {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzOperationalInsightsWorkspace' -Gone 'group') { return }
    Select-StubItem -Own 'platform-skycraft-swc-law' -Other 'unrelated-law' -Name $Name
}

function Remove-AzOperationalInsightsWorkspace {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzOperationalInsightsWorkspace' -Name $Name
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$ArgumentList = @('-Force'),
            [switch]$Empty,
            [switch]$Bare,
            [switch]$Two,
            [switch]$Portal
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_BARE   = if ($Bare) { '1' } else { '0' }
            SKYCRAFT_STUB_TWO    = if ($Two) { '1' } else { '0' }
            SKYCRAFT_STUB_PORTAL = if ($Portal) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG    = $logPath
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

    # A deletion the script makes.
    $script:ChangePattern = '^Remove-'

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:Bare    = Invoke-CleanupScript -Stub $script:Stub -Bare
    $script:WhatIf  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzMetricAlertRuleV2=denied'
        'Get-AzDataCollectionRuleAssociation=throttled'
        'Get-AzOperationalInsightsWorkspace=denied'
    )
    $script:VmDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzVM:dev-skycraft-swc-rg=denied'
    $script:StepsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzMetricAlertRuleV2:skycraft-cpu-alert'
        'Remove-AzDiagnosticSetting:platformskycraftswcsa/skycraft-storage-diag'
    )
    $script:TwoAccounts       = Invoke-CleanupScript -Stub $script:Stub -Two
    $script:TwoAccountsDenied = Invoke-CleanupScript -Stub $script:Stub -Two -Lookup 'Get-AzDiagnosticSetting:platformskycraftswcsa=denied'
    $script:Portal            = Invoke-CleanupScript -Stub $script:Stub -Portal
    $script:PortalRuleDenied  = Invoke-CleanupScript -Stub $script:Stub -Portal -Lookup 'Get-AzResource:MSVMI-dev-skycraft-swc-auth-vm=denied'
    $script:PortalAssocFails  = Invoke-CleanupScript -Stub $script:Stub -Portal -Fail 'Remove-AzDataCollectionRuleAssociation:MSVMI-dev-skycraft-swc-auth-vm-assoc'
    $script:LogAlertsDenied   = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzResource:scheduledQueryRules=denied'
    $script:LogAlertFails     = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzResource:skycraft-heartbeat-alert'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:Bare, $script:WhatIf, $script:LookupsFail, $script:VmDenied,
        $script:StepsFail, $script:TwoAccounts, $script:TwoAccountsDenied, $script:Portal, $script:PortalRuleDenied,
        $script:PortalAssocFails, $script:LogAlertsDenied, $script:LogAlertFails
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - removes what the lab created' {

    It 'exits 0 when everything is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes the alert, the association, the rule, the action group, the diagnostic setting and the workspace' {
        $calls = $script:Clean.Calls
        $calls | Should -Contain 'Remove-AzMetricAlertRuleV2:platform-skycraft-swc-rg/skycraft-cpu-alert'
        $calls | Should -Contain 'Remove-AzResource:platform-skycraft-swc-rg/skycraft-heartbeat-alert'
        $calls | Should -Contain 'Remove-AzDataCollectionRuleAssociation:skycraft-vminsights-dcr-assoc'
        $calls | Should -Contain 'Remove-AzResource:platform-skycraft-swc-rg/skycraft-vm-dcr'
        $calls | Should -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $calls | Should -Contain 'Remove-AzDiagnosticSetting:platformskycraftswcsa/skycraft-storage-diag'
        $calls | Should -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
    }

    It 'leaves the objects the lab did not create alone' {
        foreach ($run in $script:Clean, $script:Portal) {
            # A lookup may name an unrelated object ('Get-AzResource:unrelated-dcr'); a deletion may not.
            @($run.Calls | Where-Object { $_ -match '^Remove-.*:(.*/)?unrelated-' }) | Should -BeNullOrEmpty
            # A rule that carries the lab's name but watches another VM from another group, and an
            # association to a data collection endpoint.
            $run.Calls | Should -Not -Contain 'Remove-AzMetricAlertRuleV2:other-rg/skycraft-cpu-alert'
            $run.Calls | Should -Not -Contain 'Remove-AzDataCollectionRuleAssociation:configurationAccessEndpoint'
        }
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - removes what Test-Lab.ps1 accepts, wherever it sits (#362)' {

    It 'removes the alert rule and the VM insights rule that the Portal left in the VM''s group' {
        $run = $script:Portal
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Cleanup Complete'
        $run.Calls    | Should -Contain 'Remove-AzMetricAlertRuleV2:dev-skycraft-swc-rg/skycraft-cpu-alert'
        $run.Calls    | Should -Contain 'Remove-AzDataCollectionRuleAssociation:MSVMI-dev-skycraft-swc-auth-vm-assoc'
        $run.Calls    | Should -Contain 'Remove-AzResource:dev-skycraft-swc-rg/MSVMI-dev-skycraft-swc-auth-vm'
        $run.Calls    | Should -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $run.Calls    | Should -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
    }

    It 'leaves the VM insights recommended alert on the same VM alone' {
        $script:Portal.Calls | Should -Not -Contain 'Remove-AzMetricAlertRuleV2:unrelated-recommended-cpu'
        $script:Clean.Calls  | Should -Not -Contain 'Remove-AzMetricAlertRuleV2:unrelated-recommended-cpu'
    }

    It 'counts a rule that could not be read and keeps the workspace it may send to' {
        $run = $script:PortalRuleDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up data collection rule 'MSVMI-dev-skycraft-swc-auth-vm'"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzResource:*MSVMI-*' }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
        $run.Output   | Should -Match "Kept Log Analytics Workspace 'platform-skycraft-swc-law'"
    }

    It 'keeps a rule whose association could not be deleted, and the workspace with it' {
        $run = $script:PortalAssocFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not delete DCR Association 'MSVMI-dev-skycraft-swc-auth-vm-assoc'"
        $run.Output   | Should -Match "Kept Data Collection Rule 'MSVMI-dev-skycraft-swc-auth-vm'"
        $run.Calls    | Should -Not -Contain 'Remove-AzResource:dev-skycraft-swc-rg/MSVMI-dev-skycraft-swc-auth-vm'
        $run.Calls    | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
        $run.Calls    | Should -Contain 'Remove-AzMetricAlertRuleV2:dev-skycraft-swc-rg/skycraft-cpu-alert'
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and deletes nothing when the getters report everything not found' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'No Lab 5\.1 resources found to delete'
        $run.Output   | Should -Not -Match '\[ERROR\]'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'exits 0 and deletes nothing when the listings hold none of the lab''s objects' {
        $run = $script:Bare
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'No Lab 5\.1 resources found to delete'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'reads a status-only 404 for the data collection rule as absent, not as a failed lookup' {
        # The bare subscription's rule is reported missing with no not-found wording at all: only
        # the 404 on the inner CloudException's response says so.
        $script:Bare.Calls  | Should -Contain 'Get-AzResource:skycraft-vm-dcr'
        $script:Bare.Output | Should -Not -Match 'Could not look up data collection rule'
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - every storage account in the platform group is checked' {

    It 'removes the diagnostic setting from the account it is on, not only the first one listed' {
        $run = $script:TwoAccounts
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls    | Should -Contain 'Get-AzDiagnosticSetting:platformskycraftswcsa'
        $run.Calls    | Should -Contain 'Get-AzDiagnosticSetting:platformskycraftswcsb'
        $run.Calls    | Should -Contain 'Remove-AzDiagnosticSetting:platformskycraftswcsb/skycraft-storage-diag'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzDiagnosticSetting:platformskycraftswcsa/*' }) | Should -BeNullOrEmpty
    }

    It 'counts an account whose settings could not be looked up, still checks the next, and keeps the workspace' {
        $run = $script:TwoAccountsDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the diagnostic settings of 'platformskycraftswcsa'"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls    | Should -Contain 'Remove-AzDiagnosticSetting:platformskycraftswcsb/skycraft-storage-diag'
        $run.Calls    | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
        $run.Output   | Should -Match "Kept Log Analytics Workspace 'platform-skycraft-swc-law'"
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 and counts each failed lookup' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the metric alert rules in the subscription[^\r\n]*does not have authorization"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the data collection rule associations on 'dev-skycraft-swc-auth-vm'[^\r\n]*requests exceeded the limit"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the Log Analytics workspaces in 'platform-skycraft-swc-rg'"
        $run.Output   | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
        $run.Output   | Should -Not -Match 'No Lab 5\.1 resources found'
    }

    It 'deletes nothing it could not see, and keeps what may still depend on it' {
        $calls = $script:LookupsFail.Calls
        $calls | Should -Not -Contain 'Remove-AzMetricAlertRuleV2:skycraft-cpu-alert'
        $calls | Should -Not -Contain 'Remove-AzDataCollectionRuleAssociation:skycraft-vminsights-dcr-assoc'
        $calls | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
        # The alert may still use the action group; the association may still tie the rule to the VM.
        $calls | Should -Not -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $calls | Should -Not -Contain 'Remove-AzResource:skycraft-vm-dcr'
        $script:LookupsFail.Output | Should -Match "Kept Action Group 'skycraft-ops-ag'"
        $script:LookupsFail.Output | Should -Match "Kept Data Collection Rule 'skycraft-vm-dcr'"
    }

    It 'still removes what it could see and nothing depends on' {
        $script:LookupsFail.Calls | Should -Contain 'Remove-AzDiagnosticSetting:platformskycraftswcsa/skycraft-storage-diag'
    }

    It 'keeps the rule and the workspace when the VM could not be looked up' {
        $run = $script:VmDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the VMs in 'dev-skycraft-swc-rg'"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls    | Should -Not -Contain 'Remove-AzResource:skycraft-vm-dcr'
        $run.Calls    | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
        $run.Calls    | Should -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $run.Output   | Should -Match "Kept Log Analytics Workspace 'platform-skycraft-swc-law'"
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - a failed deletion is counted' {

    It 'exits 1 and counts each deletion that failed' {
        $run = $script:StepsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not delete Metric Alert 'skycraft-cpu-alert'"
        $run.Output   | Should -Match "\[ERROR\] Could not delete Storage Diagnostic Settings 'skycraft-storage-diag'"
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed deletion' {
        $script:StepsFail.Calls | Should -Contain 'Remove-AzDataCollectionRuleAssociation:skycraft-vminsights-dcr-assoc'
        $script:StepsFail.Calls | Should -Contain 'Remove-AzResource:skycraft-vm-dcr'
    }

    It 'keeps the action group and the workspace while what uses them is still there' {
        $script:StepsFail.Calls | Should -Not -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $script:StepsFail.Calls | Should -Not -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up and deletes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain 'Get-AzOperationalInsightsWorkspace'
        $run.Output   | Should -Match 'What if: .*skycraft-cpu-alert'
        $run.Output   | Should -Match 'What if: .*platform-skycraft-swc-law'
    }
}

Describe 'Lab 5.1 Remove-LabResource.ps1 - removes the log search alert Test-Lab.ps1 accepts (#357)' {

    It 'removes the rule the Portal made under the learner''s name, scoped to the workspace' {
        $script:Portal.Calls | Should -Contain 'Remove-AzResource:dev-skycraft-swc-rg/vm-heartbeat-missing'
    }

    It 'removes the log search alert before the action group it notifies' {
        $calls = @($script:Clean.Calls)
        [array]::IndexOf($calls, 'Remove-AzResource:platform-skycraft-swc-rg/skycraft-heartbeat-alert') |
            Should -BeLessThan ([array]::IndexOf($calls, 'Remove-AzActionGroup:skycraft-ops-ag'))
    }

    It 'leaves other Heartbeat and Perf rules alone' {
        foreach ($run in $script:Clean, $script:Portal) {
            $run.Calls | Should -Not -Contain 'Remove-AzResource:other-rg/unrelated-heartbeat-other-vm'
            $run.Calls | Should -Not -Contain 'Remove-AzResource:dev-skycraft-swc-rg/unrelated-perf-rows'
            $run.Calls | Should -Not -Contain 'Remove-AzResource:dev-skycraft-swc-rg/unrelated-heartbeat-team'
        }
    }

    It 'counts a listing that fails and keeps the action group' {
        $run = $script:LogAlertsDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match '\[ERROR\] Could not look up the log search alert rules in the subscription'
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls    | Should -Not -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $run.Output   | Should -Match "Kept Action Group 'skycraft-ops-ag'"
    }

    It 'counts a deletion that fails and keeps the action group' {
        $run = $script:LogAlertFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not delete Log Search Alert 'skycraft-heartbeat-alert'"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls    | Should -Not -Contain 'Remove-AzActionGroup:skycraft-ops-ag'
        $run.Calls    | Should -Contain 'Remove-AzOperationalInsightsWorkspace:platform-skycraft-swc-law'
    }
}
