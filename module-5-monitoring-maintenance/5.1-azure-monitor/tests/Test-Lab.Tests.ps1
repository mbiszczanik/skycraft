<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.1 validator finds the data collection rule through its VM.

.DESCRIPTION
    Regression cover for issue #355. Test-Lab.ps1 read the data collection rule from a fixed id,
    'skycraft-vm-dcr' in platform-skycraft-swc-rg, which only the Bicep produces: today's VM
    insights wizard names its rule 'MSVMI-<...>' and creates it in the VM's group, and the data
    collection rule wizard takes any group. These tests run the real Test-Lab.ps1 in a child pwsh
    against a generated stub of the Az commands it calls, and assert that:

      1. The Bicep's rule and a rule under a Portal-generated name in the VM's group both pass,
         found through the VM's data collection rule associations, and the output names the
         rule and the VM.
      2. Of several rules on the VM, the one that sends to the lab's workspace is checked; an
         association with a data collection endpoint, which names no rule, is skipped; and a
         group, a VM or an associated rule that cannot be read does not sink a rule found
         elsewhere.
      3. No rule on any SkyCraft VM is a counted failure that says which step makes one, and
         names what could not be read.
      4. An association lookup that fails everywhere is a counted FAIL with the error, and the
         script still reaches its summary.
      5. The alert rule is found through its scope (#355, #365): the rule the learner named
         'skycraft-cpu-alert' passes on a SkyCraft VM in the guide's group or in the VM's group
         (the Portal's default), and every alert check reads it. VM insights' recommended
         alerts on the same VM are not taken for it. When the subscription's rules cannot be
         listed, the guide's group and name still find it.
      6. The Azure Monitor Agent is checked on the rule's VMs (#369): a missing, non-Succeeded or
         unreadable agent fails; zero Heartbeat rows, a query that throws and a query that
         returns an error fail; a late first row is waited for only while the agent is Succeeded.
      7. A rule built by the data collection rules wizard passes the stream checks (#355): one
         flow per data source to an 'la-<n>' destination, an outputStream, a lower-case
         workspace id. Perf and Syslog sent to another workspace do not count.
      8. The log search alert of Step 5.1.8 is found by relation (#357): a rule on Heartbeat that
         watches a SkyCraft VM or the lab's workspace, under any name and in any group. A rule
         that is disabled, does not fire on zero rows or notifies another group fails; no rule
         and a listing that fails fail.

    The VM insights rule in the 'portal' case carries the streams VM insights really sends
    (InsightsMetrics, no Perf or Syslog), so the Perf and Syslog checks fail on it: the guide's
    path is the data collection rules wizard (#369), VM insights only its Portal shortcut.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #355, #357, #369
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab51ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.OperationalInsights', 'Az.Monitor', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzOperationalInsightsWorkspace'
        'Get-AzResource'
        'Invoke-AzRestMethod'
        'Get-AzActionGroup'
        'Get-AzMetricAlertRuleV2'
        'Get-AzStorageAccount'
        'Get-AzDiagnosticSetting'
        'Invoke-AzOperationalInsightsQuery'
        # Shadowed so a wait for Heartbeat rows is counted, not slept.
        'Start-Sleep'
    )

    # The workspace, action group, alert rule and storage diagnostic setting are always as the
    # guide leaves them. The data collection rule varies:
    #   SKYCRAFT_STUB_DCR   'bicep'  'skycraft-vm-dcr' in the platform group, associated with
    #                                the dev auth VM, as Deploy-Bicep.ps1 leaves it
    #                       'portal' a rule named the way VM insights names it, in the VM's
    #                                group; the VM also carries a data collection endpoint
    #                                association and a rule that sends to another workspace, and
    #                                the prod group cannot be read
    #                       'none'   the VMs carry no association
    #                       'nonepartial' as 'none', and the prod group cannot be read
    #                       'fail'   reading the associations fails for every VM
    #                       'vmthrows' the dev world VM's association call throws; the dev
    #                                auth VM carries the Bicep's rule
    #                       'dangling' the dev auth VM carries an association to a deleted rule
    #                                next to the Bicep's rule
    #                       'wizard' the data collection rules wizard's rule in the platform
    #                                group: one flow per source to 'la-<n>', outputStream, the
    #                                workspace id in lower case
    #                       'elsewhere' a rule that sends InsightsMetrics to the lab's workspace
    #                                and Perf and Syslog to another one
    # The Portal-named rule carries the streams VM insights sends: InsightsMetrics, no Syslog.
    # The alert rule varies with SKYCRAFT_STUB_ALERT:
    #   'platform'     'skycraft-cpu-alert' in the platform group on the dev auth VM, as the
    #                  guide leaves it
    #   'vmgroup'      the rule sits in the VM's group, the Portal's default
    #   'recommended'  no rule by the guide's name; VM insights' recommended alerts sit on the VM
    #   'listfails'    as 'vmgroup', and listing the subscription's rules fails
    #   'listfailsplatform' as 'platform', and listing the subscription's rules fails
    # Every case also lists an unrelated rule on a SQL server.
    # The log search alert varies with SKYCRAFT_STUB_LOGALERT:
    #   'vm'        'skycraft-heartbeat-alert' in the platform group on the dev auth VM, as the
    #               guide leaves it
    #   'workspace' a Portal-named rule in the VM's group, scoped to the lab's workspace
    #   'none'      only a Heartbeat rule on a SQL server and a Perf rule on the VM
    #   'disabled', 'wrongop' (fires above zero rows), 'noaction' (notifies another group)
    #   'listfails' listing the rules fails
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
$script:PlatformRg = "$script:Sub/resourceGroups/platform-skycraft-swc-rg"
$script:DevRg      = "$script:Sub/resourceGroups/dev-skycraft-swc-rg"
$script:WorkspaceId = "$script:PlatformRg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law"
$script:DevAuthVmId = "$script:DevRg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm"

function Get-StubRules {
    $bicep = "$script:PlatformRg/providers/Microsoft.Insights/dataCollectionRules/skycraft-vm-dcr"
    $vmi   = "$script:DevRg/providers/Microsoft.Insights/dataCollectionRules/MSVMI-swedencentral-dev-skycraft-swc-auth-vm"
    $other = "$script:DevRg/providers/Microsoft.Insights/dataCollectionRules/security-events-dcr"
    $wizard = "$script:PlatformRg/providers/Microsoft.Insights/dataCollectionRules/skycraft-vm-dcr-wizard"
    $elsewhere = "$script:PlatformRg/providers/Microsoft.Insights/dataCollectionRules/skycraft-vm-dcr-elsewhere"
    $otherLaw = "$script:Sub/resourceGroups/security-rg/providers/Microsoft.OperationalInsights/workspaces/security-law"
    @{
        $wizard = @{ Name = 'skycraft-vm-dcr-wizard'; Group = 'platform-skycraft-swc-rg'
            Destinations = @(@{ name = 'la-1906172418'; workspaceResourceId = $script:WorkspaceId.ToLowerInvariant() })
            Flows = @(
                @{ streams = @('Microsoft-Perf'); destinations = @('la-1906172418'); transformKql = 'source'; outputStream = 'Microsoft-Perf' }
                @{ streams = @('Microsoft-Syslog'); destinations = @('la-1906172418'); transformKql = 'source'; outputStream = 'Microsoft-Syslog' }
            ) }
        $elsewhere = @{ Name = 'skycraft-vm-dcr-elsewhere'; Group = 'platform-skycraft-swc-rg'
            Destinations = @(@{ name = 'la-lab'; workspaceResourceId = $script:WorkspaceId }, @{ name = 'la-other'; workspaceResourceId = $otherLaw })
            Flows = @(
                @{ streams = @('Microsoft-InsightsMetrics'); destinations = @('la-lab') }
                @{ streams = @('Microsoft-Perf', 'Microsoft-Syslog'); destinations = @('la-other') }
            ) }
        $bicep = @{ Name = 'skycraft-vm-dcr'; Group = 'platform-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-Perf', 'Microsoft-InsightsMetrics', 'Microsoft-Syslog') }
        $vmi   = @{ Name = 'MSVMI-swedencentral-dev-skycraft-swc-auth-vm'; Group = 'dev-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-InsightsMetrics') }
        $other = @{ Name = 'security-events-dcr'; Group = 'dev-skycraft-swc-rg'; Workspace = $otherLaw; Streams = @('Microsoft-SecurityEvent') }
    }
}

function New-StubAlert {
    param([string]$Name, [string]$Group, [string]$Scope)
    [pscustomobject]@{
        Name                = $Name
        ResourceGroup       = $Group
        Id                  = "$script:Sub/resourceGroups/$Group/providers/Microsoft.Insights/metricAlerts/$Name"
        Scopes              = @($Scope)
        Enabled             = $true
        Severity            = 2
        WindowSize          = [System.TimeSpan]::FromMinutes(5)
        EvaluationFrequency = [System.TimeSpan]::FromMinutes(1)
    }
}

function Get-StubAlerts {
    switch ($env:SKYCRAFT_STUB_ALERT) {
        { $_ -in 'vmgroup', 'listfails' } { New-StubAlert 'skycraft-cpu-alert' 'dev-skycraft-swc-rg' $script:DevAuthVmId }
        'recommended' {
            New-StubAlert 'Percentage CPU - dev-skycraft-swc-auth-vm' 'dev-skycraft-swc-rg' $script:DevAuthVmId
            New-StubAlert 'Available Memory Bytes - dev-skycraft-swc-auth-vm' 'dev-skycraft-swc-rg' $script:DevAuthVmId
        }
        default { New-StubAlert 'skycraft-cpu-alert' 'platform-skycraft-swc-rg' $script:DevAuthVmId }
    }
    New-StubAlert 'unrelated-sql-alert' 'other-rg' "$script:Sub/resourceGroups/other-rg/providers/Microsoft.Sql/servers/other-sql"
}

# Scheduled query rules, in the raw ARM shape Get-AzResource -ExpandProperties returns.
function New-StubLogAlert {
    param([string]$Name, [string]$Group, [string]$Scope, [string]$Query = 'Heartbeat', [string]$Operator = 'LessThan',
        [double]$Threshold = 1, [bool]$Enabled = $true, [string]$ActionGroup = 'platform-skycraft-swc-rg/skycraft-ops-ag')
    $agGroup, $agName = $ActionGroup -split '/'
    [pscustomobject]@{
        Name              = $Name
        ResourceGroupName = $Group
        ResourceId        = "$script:Sub/resourceGroups/$Group/providers/Microsoft.Insights/scheduledQueryRules/$Name"
        Properties        = [pscustomobject]@{
            enabled  = $Enabled
            scopes   = @($Scope)
            criteria = [pscustomobject]@{ allOf = @([pscustomobject]@{ query = $Query; timeAggregation = 'Count'; operator = $Operator; threshold = $Threshold }) }
            # The Portal writes the id in lower case.
            actions  = [pscustomobject]@{ actionGroups = @("$script:Sub/resourceGroups/$agGroup/providers/microsoft.insights/actiongroups/$agName".ToLowerInvariant()) }
        }
    }
}

function Get-StubLogAlerts {
    if ($env:SKYCRAFT_STUB_LOGALERT -eq 'listfails') { throw 'stub lookup failure: scheduledQueryRules list' }
    New-StubLogAlert 'sql-heartbeat' 'other-rg' "$script:Sub/resourceGroups/other-rg/providers/Microsoft.Sql/servers/other-sql"
    New-StubLogAlert 'vm-perf-rows' 'dev-skycraft-swc-rg' $script:DevAuthVmId -Query 'Perf | where CounterName == "% Processor Time"'
    switch ($env:SKYCRAFT_STUB_LOGALERT) {
        'none'      { }
        'workspace' { New-StubLogAlert 'No heartbeat from the auth VM' 'dev-skycraft-swc-rg' $script:WorkspaceId.ToLowerInvariant() -Query 'Heartbeat | where Computer == "dev-skycraft-swc-auth-vm"' }
        'disabled'  { New-StubLogAlert 'skycraft-heartbeat-alert' 'platform-skycraft-swc-rg' $script:DevAuthVmId -Enabled $false }
        'wrongop'   { New-StubLogAlert 'skycraft-heartbeat-alert' 'platform-skycraft-swc-rg' $script:DevAuthVmId -Operator 'GreaterThan' -Threshold 0 }
        'noaction'  { New-StubLogAlert 'skycraft-heartbeat-alert' 'platform-skycraft-swc-rg' $script:DevAuthVmId -ActionGroup 'dev-skycraft-swc-rg/RecommendedAlertRules-AG-1' }
        default     { New-StubLogAlert 'skycraft-heartbeat-alert' 'platform-skycraft-swc-rg' $script:DevAuthVmId }
    }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Get-AzOperationalInsightsWorkspace {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name            = $Name
        ResourceId      = $script:WorkspaceId
        CustomerId      = '11111111-1111-1111-1111-111111111111'
        Sku             = 'PerGB2018'
        RetentionInDays = 30
        Location        = 'swedencentral'
        Tags            = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param(
        [string]$ResourceId,
        [string]$ResourceType,
        [string]$ResourceGroupName,
        [string]$Name,
        [switch]$ExpandProperties,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )
    if ($ResourceType -eq 'Microsoft.Insights/scheduledQueryRules') {
        return @(Get-StubLogAlerts)
    }
    if ($ResourceType -eq 'Microsoft.Compute/virtualMachines') {
        if ($env:SKYCRAFT_STUB_DCR -in 'portal', 'nonepartial' -and $ResourceGroupName -eq 'prod-skycraft-swc-rg') {
            Write-Error "stub lookup failure: Resource group '$ResourceGroupName' could not be read."
            return
        }
        $env = ($ResourceGroupName -split '-')[0]
        foreach ($role in 'auth', 'world') {
            [pscustomobject]@{
                Name              = "$env-skycraft-swc-$role-vm"
                ResourceGroupName = $ResourceGroupName
                ResourceId        = "$script:Sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$env-skycraft-swc-$role-vm"
            }
        }
        return
    }
    if ($ResourceId -like '*/dataCollectionRules/deleted-dcr') {
        throw "stub lookup failure: ResourceNotFound '$ResourceId'"
    }
    if ($ResourceId -like '*/providers/Microsoft.Insights/metricAlerts/*') {
        return [pscustomobject]@{
            ResourceId = $ResourceId
            Properties = [pscustomobject]@{ criteria = [pscustomobject]@{ allOf = @([pscustomobject]@{ metricName = 'Percentage CPU'; threshold = 80; operator = 'GreaterThan' }) } }
        }
    }
    $rules = Get-StubRules
    if ($ResourceId -and $rules.ContainsKey($ResourceId)) {
        $rule = $rules[$ResourceId]
        $destinations = if ($rule.Destinations) { $rule.Destinations } else { @(@{ name = 'la-dest'; workspaceResourceId = $rule.Workspace }) }
        $flows = if ($rule.Flows) { $rule.Flows } else { @(@{ streams = $rule.Streams; destinations = @('la-dest') }) }
        return [pscustomobject]@{
            Name              = $rule.Name
            ResourceGroupName = $rule.Group
            ResourceId        = $ResourceId
            Properties        = [pscustomobject]@{
                destinations = [pscustomobject]@{ logAnalytics = @($destinations | ForEach-Object { [pscustomobject]$_ }) }
                dataFlows    = @($flows | ForEach-Object { [pscustomobject]$_ })
            }
        }
    }
    throw "stub: unexpected Get-AzResource call (ResourceId '$ResourceId', ResourceType '$ResourceType', group '$ResourceGroupName', name '$Name')"
}

# Lists a VM's data collection rule associations, as GET <vm id>/providers/
# Microsoft.Insights/dataCollectionRuleAssociations does.
function Invoke-AzRestMethod {
    [CmdletBinding()]
    param([string]$Method, [string]$Path, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Path -match '/virtualMachines/[^/]+/extensions\?') { return Get-StubExtensions -Path $Path }
    if ($Path -notmatch '/providers/Microsoft\.Insights/dataCollectionRuleAssociations\?') { throw "stub: unexpected REST path $Path" }
    if ($env:SKYCRAFT_STUB_DCR -eq 'fail') { throw 'stub lookup failure: Invoke-AzRestMethod dataCollectionRuleAssociations' }
    if ($env:SKYCRAFT_STUB_DCR -eq 'vmthrows' -and $Path -like '*/virtualMachines/dev-skycraft-swc-world-vm/*') {
        throw 'stub lookup failure: world VM associations'
    }

    $associations = @()
    if ($Path -like '*/virtualMachines/dev-skycraft-swc-auth-vm/*') {
        $rules = (Get-StubRules).Keys
        $bicepAssociation = @{ name = 'skycraft-vminsights-dcr-assoc'; properties = @{ dataCollectionRuleId = ($rules | Where-Object { $_ -like '*/skycraft-vm-dcr' }) } }
        switch ($env:SKYCRAFT_STUB_DCR) {
            { $_ -in 'bicep', 'vmthrows' } {
                $associations += $bicepAssociation
            }
            { $_ -in 'wizard', 'elsewhere' } {
                $associations += @{ name = 'skycraft-vm-dcr-association'; properties = @{ dataCollectionRuleId = ($rules | Where-Object { $_ -like "*/skycraft-vm-dcr-$env:SKYCRAFT_STUB_DCR" }) } }
            }
            'dangling' {
                $associations += @{ name = 'left-behind'; properties = @{ dataCollectionRuleId = "$script:DevRg/providers/Microsoft.Insights/dataCollectionRules/deleted-dcr" } }
                $associations += $bicepAssociation
            }
            'portal' {
                $associations += @{ name = 'configurationAccessEndpoint'; properties = @{ dataCollectionEndpointId = "$script:DevRg/providers/Microsoft.Insights/dataCollectionEndpoints/stub-dce" } }
                $associations += @{ name = 'security-assoc'; properties = @{ dataCollectionRuleId = ($rules | Where-Object { $_ -like '*/security-events-dcr' }) } }
                $associations += @{ name = 'vmi-assoc'; properties = @{ dataCollectionRuleId = ($rules | Where-Object { $_ -like '*/MSVMI-*' }) } }
            }
        }
    }
    [pscustomobject]@{ StatusCode = 200; Content = (@{ value = $associations } | ConvertTo-Json -Depth 5) }
}

# Lists a VM's extensions, as GET <vm id>/extensions does. Every VM carries the Network Watcher
# agent; the Azure Monitor Agent varies with SKYCRAFT_STUB_AGENT.
function Get-StubExtensions {
    param([string]$Path)
    if ($env:SKYCRAFT_STUB_AGENT -eq 'unreadable') { throw 'stub lookup failure: extensions' }
    $extensions = @(@{ name = 'NetworkWatcherAgentLinux'; properties = @{ publisher = 'Microsoft.Azure.NetworkWatcher'; type = 'NetworkWatcherAgentLinux'; provisioningState = 'Succeeded' } })
    $state = switch ($env:SKYCRAFT_STUB_AGENT) { 'missing' { $null } 'failed' { 'Failed' } default { 'Succeeded' } }
    if ($state) {
        $extensions += @{ name = 'AzureMonitorLinuxAgent'; properties = @{ publisher = 'Microsoft.Azure.Monitor'; type = 'AzureMonitorLinuxAgent'; provisioningState = $state } }
    }
    [pscustomobject]@{ StatusCode = 200; Content = (@{ value = $extensions } | ConvertTo-Json -Depth 5) }
}

# Answers the Heartbeat query with a row for every VM id it names, as SKYCRAFT_STUB_HEARTBEAT says:
#   'rows' (default) at once, 'late' from the second query on, 'none' never, 'fail' throws,
#   'error' returns the partial-error shape the service uses for a failed query.
$script:QueryCount = 0
function Invoke-AzOperationalInsightsQuery {
    [CmdletBinding()]
    param([string]$WorkspaceId, [string]$Query, [Parameter(ValueFromRemainingArguments)]$Rest)
    $script:QueryCount++
    Write-Host "[stub-query $script:QueryCount]" -NoNewline
    if ($WorkspaceId -ne '11111111-1111-1111-1111-111111111111') { throw "stub: unexpected workspace id '$WorkspaceId'" }
    if ($Query -notmatch '^Heartbeat\b' -or $Query -notmatch 'ago\(15m\)') { throw "stub: unexpected query $Query" }
    switch ($env:SKYCRAFT_STUB_HEARTBEAT) {
        'fail'  { throw 'stub lookup failure: workspace query' }
        'error' { return [pscustomobject]@{ Results = @(); Error = [pscustomobject]@{ Message = 'stub query error: PartialError' } } }
    }
    $rows = @()
    $answer = $env:SKYCRAFT_STUB_HEARTBEAT -in '', 'rows' -or ($env:SKYCRAFT_STUB_HEARTBEAT -eq 'late' -and $script:QueryCount -gt 1)
    if ($answer) {
        $rows = @([regex]::Matches($Query, "'(/subscriptions/[^']+)'") | ForEach-Object { [pscustomobject]@{ VmId = $_.Groups[1].Value; LastHeartbeat = '2026-10-28T10:00:00Z' } })
    }
    [pscustomobject]@{ Results = $rows; Error = $null }
}

function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-Host "[stub-sleep $Seconds]" -NoNewline
}

function Get-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = $Name; GroupShortName = 'SkyCraftOps'; EmailReceiver = @([pscustomobject]@{ Name = 'ops' }); Enabled = $true }
}

function Get-AzMetricAlertRuleV2 {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (-not $Name) {
        # Listing the subscription's rules.
        if ($env:SKYCRAFT_STUB_ALERT -in 'listfails', 'listfailsplatform') { throw 'stub lookup failure: Get-AzMetricAlertRuleV2 list' }
        return @(Get-StubAlerts)
    }
    $rule = @(Get-StubAlerts | Where-Object { $_.Name -eq $Name -and $_.ResourceGroup -eq $ResourceGroupName })
    if ($rule.Count -eq 0) {
        Write-Error "stub: alert rule '$Name' not found in '$ResourceGroupName'."
        return
    }
    $rule[0]
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ StorageAccountName = 'platformskycraftswcsa'; Id = "$script:PlatformRg/providers/Microsoft.Storage/storageAccounts/platformskycraftswcsa" }
}

function Get-AzDiagnosticSetting {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name = $Name
        Log  = @([pscustomobject]@{ Category = 'StorageRead'; Enabled = $true }, [pscustomobject]@{ Category = 'StorageWrite'; Enabled = $true })
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('bicep', 'portal', 'none', 'nonepartial', 'fail', 'vmthrows', 'dangling', 'wizard', 'elsewhere')]
            [string]$Dcr,
            [ValidateSet('platform', 'vmgroup', 'recommended', 'listfails', 'listfailsplatform')]
            [string]$Alert = 'platform',
            [ValidateSet('succeeded', 'missing', 'failed', 'unreadable')]
            [string]$Agent = 'succeeded',
            [ValidateSet('rows', 'late', 'none', 'fail', 'error')]
            [string]$Heartbeat = 'rows',
            [ValidateSet('vm', 'workspace', 'none', 'disabled', 'wrongop', 'noaction', 'listfails')]
            [string]$LogAlert = 'vm',
            # 0 by default: a run that waited would spin on the real clock with the stubbed sleep.
            [int]$WaitMinutes = 0
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList @("-HeartbeatWaitMinutes $WaitMinutes") -Environment @{
            SKYCRAFT_STUB_DCR       = $Dcr
            SKYCRAFT_STUB_ALERT     = $Alert
            SKYCRAFT_STUB_AGENT     = $Agent
            SKYCRAFT_STUB_HEARTBEAT = $Heartbeat
            SKYCRAFT_STUB_LOGALERT  = $LogAlert
        }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:BicepMade  = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep'
    $script:PortalMade = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'portal'
    $script:NoRule     = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'none'
    $script:ReadFails  = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'fail'
    $script:NoRulePartial = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'nonepartial'
    $script:VmThrows   = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'vmthrows'
    $script:Dangling   = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'dangling'
    $script:AlertInVmGroup = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Alert 'vmgroup'
    $script:AlertRecommended = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Alert 'recommended'
    $script:AlertListFails = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Alert 'listfails'
    $script:AlertListFailsPlatform = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Alert 'listfailsplatform'
    $script:AgentMissing     = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Agent 'missing'
    $script:AgentFailed      = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Agent 'failed'
    $script:AgentUnreadable  = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Agent 'unreadable'
    $script:AgentFailedNoRow = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Agent 'failed' -Heartbeat 'none' -WaitMinutes 1
    $script:NoHeartbeat      = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Heartbeat 'none'
    $script:HeartbeatLate    = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Heartbeat 'late' -WaitMinutes 1
    $script:QueryThrows      = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Heartbeat 'fail'
    $script:QueryError       = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Heartbeat 'error'
    $script:WizardMade       = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'wizard'
    $script:StreamsElsewhere = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'elsewhere'
    $script:LogAlertWorkspace = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'workspace'
    $script:LogAlertNone      = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'none'
    $script:LogAlertDisabled  = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'disabled'
    $script:LogAlertWrongOp   = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'wrongop'
    $script:LogAlertNoAction  = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'noaction'
    $script:LogAlertListFails = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -LogAlert 'listfails'
    $script:AllRuns    = @(
        $script:BicepMade, $script:PortalMade, $script:NoRule, $script:ReadFails, $script:NoRulePartial,
        $script:VmThrows, $script:Dangling, $script:AlertInVmGroup, $script:AlertRecommended,
        $script:AlertListFails, $script:AlertListFailsPlatform, $script:AgentMissing, $script:AgentFailed,
        $script:AgentUnreadable, $script:AgentFailedNoRow, $script:NoHeartbeat, $script:HeartbeatLate,
        $script:QueryThrows, $script:QueryError, $script:WizardMade, $script:StreamsElsewhere,
        $script:LogAlertWorkspace, $script:LogAlertNone, $script:LogAlertDisabled, $script:LogAlertWrongOp,
        $script:LogAlertNoAction, $script:LogAlertListFails
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.1 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'stubs every Az command the script calls' {
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $called = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^\w+-Az' } | Sort-Object -Unique
        @($called | Where-Object { $_ -notin $script:StubCommands }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.1 Test-Lab.ps1 - finds the data collection rule through the VM it applies to (#355)' {

    It 'passes the rule the Bicep made, and names it and its VM' {
        $run = $script:BicepMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. \('skycraft-vm-dcr' in platform-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
        $run.Output | Should -Match 'DCR destination points to workspace\.\.\. PASS'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'finds a rule under a Portal-generated name in the VM''s group, and reads it' {
        $run = $script:PortalMade
        $run.Output | Should -Match "\('MSVMI-swedencentral-dev-skycraft-swc-auth-vm' in dev-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
        $run.Output | Should -Match 'DCR destination points to workspace\.\.\. PASS'
    }

    It 'fails the Perf and Syslog checks on a VM insights rule, whose InsightsMetrics leaves Step 5.1.4 empty (#369)' {
        # The guide's path is the data collection rules wizard (Perf and Syslog); VM insights is
        # only the Portal shortcut.
        $run = $script:PortalMade
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'DCR sends Perf to the workspace\.\.\. FAIL'
        $run.Output | Should -Match 'DCR sends Syslog to the workspace\.\.\. FAIL'
        $run.Output | Should -Match 'Failed: 2\b'
    }

    It 'passes the lab''s rule when another VM''s association call throws' {
        $run = $script:VmThrows
        $run.ExitCode | Should -Be 0 -Because "one unreadable VM must not hide a rule found on another; output was:`n$($run.Output)"
        $run.Output | Should -Match "\('skycraft-vm-dcr' in platform-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'passes the lab''s rule when the VM also carries an association to a rule that cannot be read' {
        $run = $script:Dangling
        $run.ExitCode | Should -Be 0 -Because "an association left pointing at a deleted rule must not hide the lab's rule; output was:`n$($run.Output)"
        $run.Output | Should -Match "\('skycraft-vm-dcr' in platform-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
        $run.Output | Should -Not -Match 'deleted-dcr'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'checks the rule that sends to the lab''s workspace, not another rule on the same VM' {
        # The security rule is listed before the VM insights rule and sends elsewhere; the
        # endpoint association names no rule; the prod group cannot be read. None of it counts.
        $run = $script:PortalMade
        $run.Output | Should -Not -Match 'security-events-dcr'
        $run.Output | Should -Match 'DCR destination points to workspace\.\.\. PASS'
    }

    It 'fails, counted, when no SkyCraft VM carries a rule, and names the step' {
        $run = $script:NoRule
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. \(no rule is associated with these VMs - Step 5\.1\.2\) FAIL'
        # Found, destination, Perf and Syslog read the rule; the agent and Heartbeat its VMs.
        $run.Output | Should -Match "Azure Monitor Agent Succeeded on the rule's VMs\.\.\. \(no VM carries the lab's rule - Step 5\.1\.2\) FAIL"
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\. \(no VM carries the lab's rule - Step 5\.1\.2\) FAIL"
        $run.Output | Should -Match 'Failed: 6\b'
    }

    It 'counts an association lookup that fails everywhere as a FAIL with the error, and still reaches the summary' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. FAIL \(could not read associations of 'dev-skycraft-swc-auth-vm': stub lookup failure: Invoke-AzRestMethod dataCollectionRuleAssociations"
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 6\b'
    }

    It 'says no rule is associated, and names the group it could not read, when the readable VMs carry none' {
        $run = $script:NoRulePartial
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. \(no rule is associated with these VMs - Step 5\.1\.2; could not read VMs in 'prod-skycraft-swc-rg': stub lookup failure: Resource group 'prod-skycraft-swc-rg' could not be read\.\) FAIL"
        $run.Output | Should -Match 'Failed: 6\b'
    }
}

Describe 'Lab 5.1 Test-Lab.ps1 - finds the alert rule through its scope (#355, #365)' {

    It 'passes the rule where the guide puts it, and says where it is' {
        $run = $script:BicepMade
        $run.Output | Should -Match "Alert rule 'skycraft-cpu-alert' exists\.\.\. \(in platform-skycraft-swc-rg, on a SkyCraft VM\) PASS"
    }

    It 'passes the rule left in the VM''s group, the Portal''s default, and reads every alert check from it' {
        $run = $script:AlertInVmGroup
        $run.ExitCode | Should -Be 0 -Because "the Portal defaults the rule's group to the VM's; output was:`n$($run.Output)"
        $run.Output | Should -Match "Alert rule 'skycraft-cpu-alert' exists\.\.\. \(in dev-skycraft-swc-rg, on a SkyCraft VM; Step 5\.1\.5 puts it in platform-skycraft-swc-rg, either group works\) PASS"
        $run.Output | Should -Match 'Alert rule threshold is > 80% CPU\.\.\. PASS'
        $run.Output | Should -Not -Match 'unrelated-sql-alert'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'does not take VM insights'' recommended alerts for the lab''s rule, and names them' {
        $run = $script:AlertRecommended
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Alert rule 'skycraft-cpu-alert' exists\.\.\. \(no rule named 'skycraft-cpu-alert' on a SkyCraft VM; found 'Percentage CPU - dev-skycraft-swc-auth-vm' in dev-skycraft-swc-rg, 'Available Memory Bytes - dev-skycraft-swc-auth-vm' in dev-skycraft-swc-rg - Step 5\.1\.5 names the rule 'skycraft-cpu-alert'\) FAIL"
        $run.Output | Should -Not -Match 'unrelated-sql-alert'
        # Exists, enabled, severity, window, frequency and threshold all read the rule.
        $run.Output | Should -Match 'Failed: 6\b'
    }

    It 'still fails, counted, when listing the subscription''s rules fails and the guide''s group has none, and prints the error' {
        $run = $script:AlertListFails
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Alert rule 'skycraft-cpu-alert' exists\.\.\. \(no rule named 'skycraft-cpu-alert' in platform-skycraft-swc-rg; the subscription's alert rules could not be listed: stub lookup failure: Get-AzMetricAlertRuleV2 list\) FAIL"
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 6\b'
    }

    It 'falls back to the guide''s group and name when listing the subscription''s rules fails' {
        $run = $script:AlertListFailsPlatform
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Alert rule 'skycraft-cpu-alert' exists\.\.\. \(in platform-skycraft-swc-rg\) PASS"
        $run.Output | Should -Match 'Failed: 0\b'
    }
}

Describe 'Lab 5.1 Test-Lab.ps1 - checks the Azure Monitor Agent and its Heartbeat on the rule''s VMs (#369)' {

    It 'passes a Succeeded agent whose VM sends Heartbeat, and names the VM' {
        $run = $script:BicepMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Azure Monitor Agent Succeeded on the rule's VMs\.\.\. \(dev-skycraft-swc-auth-vm Succeeded\) PASS"
        # A PASS proves the query named the VM: the stub answers only for the ids it is given.
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\.\[stub-query 1\] PASS"
        $run.Output | Should -Match 'DCR sends Perf to the workspace\.\.\. PASS'
        $run.Output | Should -Not -Match 'stub-sleep'
    }

    It 'fails, counted, when the VM has no Azure Monitor Agent, and names the step' {
        $run = $script:AgentMissing
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Azure Monitor Agent Succeeded on the rule's VMs\.\.\. \(dev-skycraft-swc-auth-vm missing - Step 5\.1\.2 installs it\) FAIL"
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails, counted, when the agent is not Succeeded' {
        $run = $script:AgentFailed
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Azure Monitor Agent Succeeded on the rule's VMs\.\.\. \(dev-skycraft-swc-auth-vm Failed - Step 5\.1\.2 installs it\) FAIL"
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'counts an extension read that fails as a FAIL with the error, never a pass' {
        $run = $script:AgentUnreadable
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Azure Monitor Agent Succeeded on the rule's VMs\.\.\. FAIL \(could not read the extensions of 'dev-skycraft-swc-auth-vm' \(stub lookup failure: extensions\)\)"
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails, counted, when no Heartbeat row has arrived from the VM, and names it' {
        $run = $script:NoHeartbeat
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\.\[stub-query 1\] \(no row from dev-skycraft-swc-auth-vm - Steps 5\.1\.2 and 5\.1\.3\) FAIL"
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'waits for a first Heartbeat while the agent is Succeeded, and passes when it arrives' {
        $run = $script:HeartbeatLate
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\.\[stub-query 1\]\.\[stub-sleep 60\]\[stub-query 2\] PASS"
    }

    It 'does not wait for Heartbeat from an agent that is not Succeeded' {
        $run = $script:AgentFailedNoRow
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match 'stub-sleep'
        $run.Output | Should -Not -Match 'stub-query 2'
        $run.Output | Should -Match 'Failed: 2\b'
    }

    It 'counts a workspace query that throws as a FAIL with the error, and still reaches the summary' {
        $run = $script:QueryThrows
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\.\[stub-query 1\] FAIL \(stub lookup failure: workspace query\)"
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'counts a workspace query that returns an error as a FAIL, not as zero rows' {
        $run = $script:QueryError
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Heartbeat from the rule's VMs in the last 15 minutes\.\.\.\[stub-query 1\] FAIL \(the workspace query failed: stub query error: PartialError\)"
        $run.Output | Should -Match 'Failed: 1\b'
    }
}

Describe 'Lab 5.1 Test-Lab.ps1 - passes a rule built by the data collection rules wizard (#355)' {

    It 'passes the wizard''s flows per data source to an la-<n> destination' {
        $run = $script:WizardMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\('skycraft-vm-dcr-wizard' in platform-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
        $run.Output | Should -Match 'DCR destination points to workspace\.\.\. PASS'
        $run.Output | Should -Match 'DCR sends Perf to the workspace\.\.\. PASS'
        $run.Output | Should -Match 'DCR sends Syslog to the workspace\.\.\. PASS'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'does not count Perf and Syslog that the rule sends to another workspace' {
        $run = $script:StreamsElsewhere
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'DCR destination points to workspace\.\.\. PASS'
        $run.Output | Should -Match 'DCR sends Perf to the workspace\.\.\. FAIL'
        $run.Output | Should -Match 'DCR sends Syslog to the workspace\.\.\. FAIL'
        $run.Output | Should -Match 'Failed: 2\b'
    }
}

Describe 'Lab 5.1 Test-Lab.ps1 - finds the log search alert by relation (#357)' {

    It 'passes the rule the guide and the Bicep make, and names it' {
        $run = $script:BicepMade
        $run.Output | Should -Match "Log search alert on Heartbeat watches a SkyCraft VM or the workspace\.\.\. \('skycraft-heartbeat-alert' in platform-skycraft-swc-rg\) PASS"
        $run.Output | Should -Match 'Log search alert is enabled\.\.\. PASS'
        $run.Output | Should -Match 'Log search alert fires when no Heartbeat row arrives \(count < 1\)\.\.\. PASS'
        $run.Output | Should -Match "Log search alert notifies 'skycraft-ops-ag'\.\.\. PASS"
    }

    It 'passes a rule under another name, in another group, scoped to the workspace' {
        $run = $script:LogAlertWorkspace
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\('No heartbeat from the auth VM' in dev-skycraft-swc-rg\) PASS"
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'fails, counted, when no rule reads Heartbeat on a SkyCraft VM, and names the step' {
        $run = $script:LogAlertNone
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Log search alert on Heartbeat watches a SkyCraft VM or the workspace\.\.\. \(no log search alert reads Heartbeat on a SkyCraft VM or 'platform-skycraft-swc-law' - Step 5\.1\.8\) FAIL"
        $run.Output | Should -Not -Match 'sql-heartbeat|vm-perf-rows'
        $run.Output | Should -Match 'Failed: 4\b'
    }

    It 'fails a disabled rule' {
        $run = $script:LogAlertDisabled
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Log search alert is enabled\.\.\. FAIL'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails a rule that does not fire on zero rows, and says what it does' {
        $run = $script:LogAlertWrongOp
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Log search alert fires when no Heartbeat row arrives \(count < 1\)\.\.\. \(Count GreaterThan 0 - Step 5\.1\.8 counts rows, Less than 1\) FAIL'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails a rule that notifies another action group, and names it' {
        $run = $script:LogAlertNoAction
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Log search alert notifies 'skycraft-ops-ag'\.\.\. \(notifies recommendedalertrules-ag-1 - Step 5\.1\.8 picks 'skycraft-ops-ag'\) FAIL"
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'counts a listing that fails as a FAIL with the error, never a pass' {
        $run = $script:LogAlertListFails
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Log search alert on Heartbeat watches a SkyCraft VM or the workspace\.\.\. FAIL \(could not list the log search alert rules: stub lookup failure: scheduledQueryRules list\)'
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 4\b'
    }
}
