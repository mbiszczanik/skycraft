<#
.SYNOPSIS
    Pester 5 tests: the Lab 3.3 validator accepts the state every path of the guide leaves, fails
    the Portal defaults the guide changes, and reports a container app without containers as a
    failed check, not a crash.

.DESCRIPTION
    Regression cover for issue #355 ("Crash instead of a [FAIL] line"). Test-Lab.ps1 read the
    container app's image with $props.template.containers[0]. A template that lists no
    containers returns $null there, and indexing $null throws "Cannot index into a null array"
    under $ErrorActionPreference = 'Stop', which ended the script before its summary and its
    exit code.

    Issues #229, #228 and #374 (the Lab 3.3 guide PR): the guide now chooses, and the validator
    checks, the settings where the Portal's defaults differ from the Bicep - no container instance
    logs, the Container Apps environment's logs sent to Azure Monitor, the HTTP rule 'http-load'
    with 1-3 replicas, target port 80 - and that no Log Analytics workspace with the Portal's
    automatic name is left in the resource group, where Module 5 wizards would offer it as their
    default. The environment is found through the app (docs/powershell-standards.md rule 7).

    These tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az
    commands it calls, and assert that:

      1. The resources as the Portal steps leave them pass, and the script exits 0.
      2. The resources as the Az PowerShell blocks leave them (no DNS label scope value, logs
         to Azure Monitor as the block sets) pass too, and so does an environment created with
         "Don't save logs" (no destination), which creates no workspace either.
      3. A container app whose template lists no containers fails the image tag check, counted,
         and the script still prints its summary and exits 1.
      4. The Portal's defaults - container instance logs, Azure Log Analytics for the
         environment with its auto-named workspace, the Portal's own scale rule and 0-10
         replicas, the Tenant label scope - fail exactly the five checks they break, report the
         rest as [INFO], leave an unrelated workspace alone, and exit 1.
      5. A registry or environment left in a Failed state (#371), the Portal's 1.5 GiB size, another
         restart policy, an environment without the Consumption profile, a region outside the two
         allowed ones and a missing tag each fail one check.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Issue: #355, #374
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab33ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.ContainerRegistry', 'Az.ContainerInstance', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzContainerRegistry'
        'Get-AzContainerRegistryRepository'
        'Get-AzContainerGroup'
        'Get-AzResource'
    )

    #   SKYCRAFT_STUB_ACA   'guide'           the resources as the Portal steps leave them
    #                       'powershell'      as the guide's Az PowerShell blocks leave them
    #                       'nologs'          the environment with "Don't save logs" (no destination)
    #                       'nocontainers'    the container app's template lists no containers
    #                       'portaldefaults'  the Portal's defaults the guide changes were kept
    #                       'drift'           failed creates, the wrong size, restart policy,
    #                                         workload profile, region and tags
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
$script:Mode = $env:SKYCRAFT_STUB_ACA

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Get-AzContainerRegistry {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $state = if ($script:Mode -eq 'drift') { 'Failed' } else { 'Succeeded' }
    [pscustomobject]@{ Name = $Name; SkuName = 'Standard'; AdminUserEnabled = $true; ProvisioningState = $state }
}

function Get-AzContainerRegistryRepository {
    [CmdletBinding()]
    param([string]$RegistryName, [Parameter(ValueFromRemainingArguments)]$Rest)
    @('skycraft-auth')
}

function Get-AzContainerGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $scope = switch ($script:Mode) { 'portaldefaults' { 'TenantReuse' } 'powershell' { $null } default { 'Unsecure' } }
    $fqdn  = if ($script:Mode -eq 'portaldefaults') { "$Name-ab12.0123456789abcdef.swedencentral.azurecontainer.io" } else { "$Name-ab12.swedencentral.azurecontainer.io" }
    $drift = $script:Mode -eq 'drift'
    [pscustomobject]@{
        Name                   = $Name
        ProvisioningState      = 'Succeeded'
        OSType                 = 'Linux'
        Sku                    = 'Standard'
        RestartPolicy          = if ($drift) { 'OnFailure' } else { 'Always' }
        # The Portal's default size is 1 CPU core and 1.5 GiB; the guide changes it to 1 GiB.
        Container              = @([pscustomobject]@{ Name = $Name; RequestCpu = 1.0; RequestMemoryInGb = if ($drift) { 1.5 } else { 1.0 } })
        IpAddress              = [pscustomobject]@{ Ip = '192.0.2.10'; Fqdn = $fqdn; AutoGeneratedDomainNameLabelScope = $scope }
        LogAnalyticWorkspaceId = if ($script:Mode -eq 'portaldefaults') { '11111111-1111-1111-1111-111111111111' } else { $null }
    }
}

# The four lab resources as a listing of the group returns them, with region and tags.
function Get-StubGroupListing {
    param([string]$ResourceGroupName)
    $tags = @{ Project = 'SkyCraft'; Environment = 'Development'; CostCenter = 'MSDN'; Owner = 'learner' }
    $driftTags = @{ Project = 'SkyCraft'; Environment = 'Development'; Owner = 'learner' }
    $drift = $script:Mode -eq 'drift'
    [pscustomobject]@{ Name = 'devskycraftswcacr01'; ResourceType = 'Microsoft.ContainerRegistry/registries'; Location = 'swedencentral'; Tags = $tags }
    [pscustomobject]@{ Name = 'dev-skycraft-swc-aci-auth'; ResourceType = 'Microsoft.ContainerInstance/containerGroups'; Location = 'swedencentral'; Tags = $(if ($drift) { $driftTags } else { $tags }) }
    [pscustomobject]@{ Name = 'dev-skycraft-swc-cae-02'; ResourceType = 'Microsoft.App/managedEnvironments'; Location = 'swedencentral'; Tags = $tags }
    [pscustomobject]@{ Name = 'dev-skycraft-swc-aca-world'; ResourceType = 'Microsoft.App/containerApps'; Location = $(if ($drift) { 'westus2' } else { 'swedencentral' }); Tags = $tags }
    # Another lab's resource in the same group is not this validator's business.
    [pscustomobject]@{ Name = 'dev-skycraft-swc-vnet'; ResourceType = 'Microsoft.Network/virtualNetworks'; Location = 'westeurope'; Tags = @{} }
}

function Get-AzResource {
    [CmdletBinding()]
    param(
        [string]$ResourceGroupName,
        [string]$ResourceType,
        [string]$Name,
        [string]$ResourceId,
        [switch]$ExpandProperties,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    # The environment, looked up through the app's managedEnvironmentId.
    if ($ResourceId) {
        if ($ResourceId -notmatch '/providers/Microsoft\.App/managedEnvironments/') { throw "stub: unexpected Get-AzResource -ResourceId '$ResourceId'" }
        $logs = switch ($script:Mode) {
            'portaldefaults' { [pscustomobject]@{ destination = 'log-analytics'; logAnalyticsConfiguration = [pscustomobject]@{ customerId = '22222222-2222-2222-2222-222222222222' } } }
            'nologs'         { [pscustomobject]@{ destination = $null } }
            default          { [pscustomobject]@{ destination = 'azure-monitor' } }
        }
        $drift = $script:Mode -eq 'drift'
        return [pscustomobject]@{
            Name       = ($ResourceId -split '/')[-1]
            Properties = [pscustomobject]@{
                provisioningState    = if ($drift) { 'Failed' } else { 'Succeeded' }
                workloadProfiles     = if ($drift) { $null } else { @([pscustomobject]@{ name = 'Consumption'; workloadProfileType = 'Consumption' }) }
                appLogsConfiguration = $logs
            }
        }
    }

    # A listing of the whole group (section 5): no type, no name.
    if (-not $ResourceType -and -not $Name) { return Get-StubGroupListing -ResourceGroupName $ResourceGroupName }

    if ($ResourceType -eq 'Microsoft.OperationalInsights/workspaces') {
        # An unrelated workspace is always there; the Portal's auto-named one only with its defaults.
        [pscustomobject]@{ Name = 'dev-skycraft-swc-law-reports'; ResourceType = $ResourceType }
        if ($script:Mode -eq 'portaldefaults') { [pscustomobject]@{ Name = 'workspacedevskycraftswcrg1a2b'; ResourceType = $ResourceType } }
        return
    }

    if ($ResourceType -ne 'Microsoft.App/containerApps') { throw "stub: unexpected Get-AzResource call (type '$ResourceType', name '$Name')" }
    $scale = if ($script:Mode -eq 'portaldefaults') {
        [pscustomobject]@{ minReplicas = 0; maxReplicas = 10; rules = @([pscustomobject]@{ name = 'http-scaler'; http = [pscustomobject]@{ metadata = [pscustomobject]@{ concurrentRequests = '10' } } }) }
    } else {
        [pscustomobject]@{ minReplicas = 1; maxReplicas = 3; rules = @([pscustomobject]@{ name = 'http-load'; http = [pscustomobject]@{ metadata = [pscustomobject]@{ concurrentRequests = '10' } } }) }
    }
    $template = [pscustomobject]@{ scale = $scale }
    if ($script:Mode -ne 'nocontainers') {
        $template | Add-Member -NotePropertyName containers -NotePropertyValue @([pscustomobject]@{ name = 'worldserver'; image = 'devskycraftswcacr01.azurecr.io/skycraft-auth:v1' })
    }
    [pscustomobject]@{
        Name       = $Name
        Properties = [pscustomobject]@{
            provisioningState    = 'Succeeded'
            configuration        = [pscustomobject]@{ ingress = [pscustomobject]@{ external = $true; targetPort = 80; fqdn = "$Name.example.swedencentral.azurecontainerapps.io" } }
            template             = $template
            managedEnvironmentId = "$script:Sub/resourceGroups/$ResourceGroupName/providers/Microsoft.App/managedEnvironments/dev-skycraft-swc-cae-02"
        }
    }
}
'@

    function Invoke-ValidatorScript {
        param([pscustomobject]$Stub, [ValidateSet('guide', 'powershell', 'nologs', 'nocontainers', 'portaldefaults', 'drift')][string]$Aca)
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_ACA = $Aca
        }
        return [pscustomobject]@{
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            FailLines = ([regex]::Matches($run.Output, '\[FAIL\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:AsGuide        = Invoke-ValidatorScript -Stub $script:Stub -Aca 'guide'
    $script:AsPowerShell   = Invoke-ValidatorScript -Stub $script:Stub -Aca 'powershell'
    $script:NoContainers   = Invoke-ValidatorScript -Stub $script:Stub -Aca 'nocontainers'
    $script:NoLogs         = Invoke-ValidatorScript -Stub $script:Stub -Aca 'nologs'
    $script:PortalDefaults = Invoke-ValidatorScript -Stub $script:Stub -Aca 'portaldefaults'
    $script:Drift          = Invoke-ValidatorScript -Stub $script:Stub -Aca 'drift'
    $script:AllRuns        = @($script:AsGuide, $script:AsPowerShell, $script:NoLogs, $script:NoContainers, $script:PortalDefaults, $script:Drift)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.3 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 3.3 Test-Lab.ps1 - every path of the guide passes (#362)' {

    It 'passes the resources as the Portal steps leave them' {
        $run = $script:AsGuide
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Image Tag 'v1' verified"
        $run.Output | Should -Match 'Environment logs destination: azure-monitor'
        $run.Output | Should -Match 'No container instance logs'
        $run.Output | Should -Match 'Replicas 1-3 verified'
        $run.Output | Should -Match '\[OK\] No auto-created Log Analytics workspace in dev-skycraft-swc-rg'
        $run.Output | Should -Match 'Size: 1 CPU core, 1 GiB memory'
        $run.Output | Should -Match 'Environment workload profile: Consumption'
        $run.Output | Should -Match 'dev-skycraft-swc-aca-world: tags Project, Environment and CostCenter verified'
        $run.Output | Should -Not -Match '\[INFO\]'
    }

    It 'passes the resources as the Az PowerShell blocks leave them: no label scope value, logs to Azure Monitor' {
        # The block under Step 3.3.8 passes -AppLogConfigurationDestination 'azure-monitor'.
        $run = $script:AsPowerShell
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match 'Environment logs destination: azure-monitor'
        $run.Output | Should -Not -Match 'DNS name label scope is'
    }

    It 'passes an environment created with "Don''t save logs", which creates no workspace either' {
        $run = $script:NoLogs
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match 'Environment logs destination: none'
    }

    It 'leaves another lab''s resource in the group alone' {
        foreach ($run in $script:AllRuns) {
            $run.Output | Should -Not -Match 'dev-skycraft-swc-vnet'
        }
    }

    It 'never flags a workspace whose name is not the Portal''s automatic one' {
        foreach ($run in $script:AllRuns) {
            $run.Output | Should -Not -Match 'dev-skycraft-swc-law-reports'
        }
    }
}

Describe 'Lab 3.3 Test-Lab.ps1 - the Portal defaults the guide changes fail (#229, #374)' {

    It 'fails the container instance logs, the environment''s workspace, the auto-named workspace, the scale rule and the replicas' {
        $run = $script:PortalDefaults
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Container instance logs go to a Log Analytics workspace'
        $run.Output | Should -Match '\[FAIL\] The environment sends its logs to a Log Analytics workspace'
        $run.Output | Should -Match "\[FAIL\] Log Analytics workspace 'workspacedevskycraftswcrg1a2b' in dev-skycraft-swc-rg was created by the Portal's default"
        $run.Output | Should -Match "\[FAIL\] Scaling rule 'http-load' with 10 concurrent requests not found"
        $run.Output | Should -Match "\[FAIL\] Replicas are '0'-'10'"
        $run.FailLines | Should -Be 5
        $run.Output | Should -Match 'Lab 3\.3 validation found 5 issue\(s\)\.'
    }

    It 'reports the Tenant label scope and the Portal''s own scale rule without failing them' {
        $run = $script:PortalDefaults
        $run.Output | Should -Match '\[INFO\] DNS name label scope is TenantReuse'
        $run.Output | Should -Match "\[INFO\] Another scale rule: 'http-scaler'"
    }
}

Describe 'Lab 3.3 Test-Lab.ps1 - failed creates and settings the guide sets fail (#371, review of #229)' {

    It 'fails the failed registry and environment, the size, the restart policy, the workload profile, the region and the tags' {
        $run = $script:Drift
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Provisioning State is 'Failed' \(Expected: Succeeded\)"
        $run.Output | Should -Match "\[FAIL\] Environment provisioning state is 'Failed'"
        $run.Output | Should -Match "\[FAIL\] Restart policy is 'OnFailure' \(Expected: Always"
        $run.Output | Should -Match "\[FAIL\] Size is '1' CPU cores and '1\.5' GiB memory"
        $run.Output | Should -Match '\[FAIL\] The environment has no Consumption workload profile'
        $run.Output | Should -Match "\[FAIL\] dev-skycraft-swc-aca-world is in 'westus2'"
        $run.Output | Should -Match "\[FAIL\] dev-skycraft-swc-aci-auth: tag CostCenter is '' \(Expected: MSDN\)"
        $run.FailLines | Should -Be 7
        $run.Output | Should -Match 'Lab 3\.3 validation found 7 issue\(s\)\.'
    }

    It 'does not compare the Owner tag, which is the learner''s own' {
        $script:AsGuide.Output | Should -Not -Match 'Owner'
    }
}

Describe 'Lab 3.3 Test-Lab.ps1 - a container app without containers is a failed check, not a crash (#355)' {

    It 'fails the image tag check of a template without containers and still reaches the summary' {
        $run = $script:NoContainers
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match 'Cannot index into a null array'
        $run.Output | Should -Match '\[FAIL\] Image Tag mismatch'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Lab 3\.3 validation found 1 issue\(s\)\.'
    }
}
