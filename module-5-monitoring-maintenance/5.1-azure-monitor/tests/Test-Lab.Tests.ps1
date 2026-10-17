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
         group that cannot be read does not sink a rule found in the other.
      3. No rule on any SkyCraft VM is a counted failure that says which step makes one.
      4. An association lookup that fails is a counted FAIL with the error, and the script still
         reaches its summary.

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
    #                       'fail'   reading the associations fails
    # The streams of the Portal-named rule are set to what the stream checks expect: this suite
    # is about finding the rule, not about which wizard collects what (#365).
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
$script:PlatformRg = "$script:Sub/resourceGroups/platform-skycraft-swc-rg"
$script:DevRg      = "$script:Sub/resourceGroups/dev-skycraft-swc-rg"
$script:WorkspaceId = "$script:PlatformRg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law"
$script:AlertId     = "$script:PlatformRg/providers/Microsoft.Insights/metricAlerts/skycraft-cpu-alert"

function Get-StubRules {
    $bicep = "$script:PlatformRg/providers/Microsoft.Insights/dataCollectionRules/skycraft-vm-dcr"
    $vmi   = "$script:DevRg/providers/Microsoft.Insights/dataCollectionRules/MSVMI-swedencentral-dev-skycraft-swc-auth-vm"
    $other = "$script:DevRg/providers/Microsoft.Insights/dataCollectionRules/security-events-dcr"
    @{
        $bicep = @{ Name = 'skycraft-vm-dcr'; Group = 'platform-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-InsightsMetrics', 'Microsoft-Syslog') }
        $vmi   = @{ Name = 'MSVMI-swedencentral-dev-skycraft-swc-auth-vm'; Group = 'dev-skycraft-swc-rg'; Workspace = $script:WorkspaceId; Streams = @('Microsoft-InsightsMetrics', 'Microsoft-Syslog') }
        $other = @{ Name = 'security-events-dcr'; Group = 'dev-skycraft-swc-rg'; Workspace = "$script:Sub/resourceGroups/security-rg/providers/Microsoft.OperationalInsights/workspaces/security-law"; Streams = @('Microsoft-SecurityEvent') }
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
        if ($env:SKYCRAFT_STUB_DCR -eq 'portal' -and $ResourceGroupName -eq 'prod-skycraft-swc-rg') {
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
    if ($ResourceId -eq $script:AlertId) {
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

    $associations = @()
    if ($Path -like '*/virtualMachines/dev-skycraft-swc-auth-vm/*') {
        $rules = (Get-StubRules).Keys
        switch ($env:SKYCRAFT_STUB_DCR) {
            'bicep' {
                $associations += @{ name = 'skycraft-vminsights-dcr-assoc'; properties = @{ dataCollectionRuleId = ($rules | Where-Object { $_ -like '*/skycraft-vm-dcr' }) } }
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
    [pscustomobject]@{
        Name                = $Name
        Id                  = $script:AlertId
        Enabled             = $true
        Severity            = 2
        WindowSize          = [System.TimeSpan]::FromMinutes(5)
        EvaluationFrequency = [System.TimeSpan]::FromMinutes(1)
    }
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
            [ValidateSet('bicep', 'portal', 'none', 'fail')]
            [string]$Dcr
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DCR = $Dcr
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
    $script:AllRuns    = @($script:BicepMade, $script:PortalMade, $script:NoRule, $script:ReadFails)
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

    It 'passes a rule under a Portal-generated name in the VM''s group' {
        $run = $script:PortalMade
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.Output | Should -Match "\('MSVMI-swedencentral-dev-skycraft-swc-auth-vm' in dev-skycraft-swc-rg, on dev-skycraft-swc-auth-vm\) PASS"
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

    It 'counts an association lookup that fails as a FAIL with the error, and still reaches the summary' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Not -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Data collection rule associated with a VM in dev-skycraft-swc-rg or prod-skycraft-swc-rg\.\.\. FAIL \(stub lookup failure: Invoke-AzRestMethod dataCollectionRuleAssociations\)'
        $run.Output | Should -Match 'Test Results Summary'
        $run.Output | Should -Match 'Failed: 4\b'
    }
}
