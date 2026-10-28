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
      6. When ARM refuses the raw read of the alert rule's criteria (AuthorizationFailed), the
         threshold check fails and prints that error, and the script exits 1 (#452).

    Known gap, kept visible on purpose: the VM insights rule in the 'portal' case carries the
    streams VM insights really sends (InsightsMetrics, no Syslog), so 'DCR includes Syslog
    stream' fails on it. Which streams the lab collects is decided on #369 and changed with the
    Lab 5.1 guide PR; this suite does not pretend a Portal-built 5.1 passes today.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #355
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
    # The Portal-named rule carries the streams VM insights sends: InsightsMetrics, no Syslog.
    # The alert rule varies with SKYCRAFT_STUB_ALERT:
    #   'platform'     'skycraft-cpu-alert' in the platform group on the dev auth VM, as the
    #                  guide leaves it
    #   'vmgroup'      the rule sits in the VM's group, the Portal's default
    #   'recommended'  no rule by the guide's name; VM insights' recommended alerts sit on the VM
    #   'listfails'    as 'vmgroup', and listing the subscription's rules fails
    #   'listfailsplatform' as 'platform', and listing the subscription's rules fails
    #   'criteriadenied' as 'platform', and the raw read of the rule's criteria is refused
    # Every case also lists an unrelated rule on a SQL server.
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
    @{
        $bicep = @{ Name = 'skycraft-vm-dcr'; Group = 'platform-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-InsightsMetrics', 'Microsoft-Syslog') }
        $vmi   = @{ Name = 'MSVMI-swedencentral-dev-skycraft-swc-auth-vm'; Group = 'dev-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-InsightsMetrics') }
        $other = @{ Name = 'security-events-dcr'; Group = 'dev-skycraft-swc-rg'; Workspace = "$script:Sub/resourceGroups/security-rg/providers/Microsoft.OperationalInsights/workspaces/security-law"; Streams = @('Microsoft-SecurityEvent') }
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
        if ($env:SKYCRAFT_STUB_ALERT -eq 'criteriadenied') {
            throw "AuthorizationFailed: The client does not have authorization to perform action 'Microsoft.Insights/metricAlerts/read' over scope '$ResourceId'."
        }
        return [pscustomobject]@{
            ResourceId = $ResourceId
            Properties = [pscustomobject]@{ criteria = [pscustomobject]@{ allOf = @([pscustomobject]@{ metricName = 'Percentage CPU'; threshold = 80; operator = 'GreaterThan' }) } }
        }
    }
    $rules = Get-StubRules
    if ($ResourceId -and $rules.ContainsKey($ResourceId)) {
        $rule = $rules[$ResourceId]
        return [pscustomobject]@{
            Name              = $rule.Name
            ResourceGroupName = $rule.Group
            ResourceId        = $ResourceId
            Properties        = [pscustomobject]@{
                destinations = [pscustomobject]@{ logAnalytics = @([pscustomobject]@{ name = 'la-dest'; workspaceResourceId = $rule.Workspace }) }
                dataFlows    = @([pscustomobject]@{ streams = $rule.Streams; destinations = @('la-dest') })
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
            [ValidateSet('bicep', 'portal', 'none', 'nonepartial', 'fail', 'vmthrows', 'dangling')]
            [string]$Dcr,
            [ValidateSet('platform', 'vmgroup', 'recommended', 'listfails', 'listfailsplatform', 'criteriadenied')]
            [string]$Alert = 'platform'
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DCR   = $Dcr
            SKYCRAFT_STUB_ALERT = $Alert
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
    $script:CriteriaDenied = Invoke-ValidatorScript -Stub $script:Stub -Dcr 'bicep' -Alert 'criteriadenied'
    $script:AllRuns    = @(
        $script:BicepMade, $script:PortalMade, $script:NoRule, $script:ReadFails, $script:NoRulePartial,
        $script:VmThrows, $script:Dangling, $script:AlertInVmGroup, $script:AlertRecommended,
        $script:AlertListFails, $script:AlertListFailsPlatform, $script:CriteriaDenied
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
        $run.Output | Should -Match 'DCR has InsightsMetrics data flow\.\.\. PASS'
    }

    It 'still fails the Syslog check on a VM insights rule, which sends no Syslog (known gap, #369)' {
        # Finding the rule is fixed here; which streams the lab collects is not. This pins the
        # gap so the Lab 5.1 guide PR that settles the streams (#369) has to change this line.
        $run = $script:PortalMade
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'DCR includes Syslog stream\.\.\. FAIL'
        $run.Output | Should -Match 'Failed: 1\b'
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
        # Found, destination, InsightsMetrics and Syslog all read the rule.
        $run.Output | Should -Match 'Failed: 4\b'
    }

    It 'counts an association lookup that fails everywhere as a FAIL with the error, and still reaches the summary' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. FAIL \(could not read associations of 'dev-skycraft-swc-auth-vm': stub lookup failure: Invoke-AzRestMethod dataCollectionRuleAssociations"
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 4\b'
    }

    It 'says no rule is associated, and names the group it could not read, when the readable VMs carry none' {
        $run = $script:NoRulePartial
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. \(no rule is associated with these VMs - Step 5\.1\.2; could not read VMs in 'prod-skycraft-swc-rg': stub lookup failure: Resource group 'prod-skycraft-swc-rg' could not be read\.\) FAIL"
        $run.Output | Should -Match 'Failed: 4\b'
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

Describe 'Lab 5.1 Test-Lab.ps1 - a raw ARM read that fails is not a missing resource (#452)' {

    It 'fails the threshold check with the lookup error' {
        $line = ($script:CriteriaDenied.Output -split '\r?\n' | Where-Object { $_ -match 'Testing: Alert rule threshold' }) -join "`n"
        $line | Should -Match 'FAIL \(.*AuthorizationFailed' -Because "output was:`n$($script:CriteriaDenied.Output)"
    }

    It 'exits 1' {
        $script:CriteriaDenied.ExitCode | Should -Be 1
    }
}
