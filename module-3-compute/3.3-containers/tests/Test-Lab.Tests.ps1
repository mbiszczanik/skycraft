<#
.SYNOPSIS
    Pester 5 tests: the Lab 3.3 validator reports a container app without containers as a failed
    check, not a crash.

.DESCRIPTION
    Regression cover for issue #355 ("Crash instead of a [FAIL] line"). Test-Lab.ps1 read the
    container app's image with $props.template.containers[0]. A template that lists no
    containers returns $null there, and indexing $null throws "Cannot index into a null array"
    under $ErrorActionPreference = 'Stop', which ended the script before its summary and its
    exit code. These tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of
    the Az commands it calls, and assert that:

      1. The registry, the container instance and the container app as the guide leaves them
         pass, and the script exits 0.
      2. A container app whose template lists no containers fails the image tag check, counted,
         and the script still prints its summary and exits 1.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Issue: #355
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

    #   SKYCRAFT_STUB_ACA   'guide'         the container app as the guide leaves it
    #                       'nocontainers'  the container app's template lists no containers
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'

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
    [pscustomobject]@{ Name = $Name; SkuName = 'Standard'; AdminUserEnabled = $true }
}

function Get-AzContainerRegistryRepository {
    [CmdletBinding()]
    param([string]$RegistryName, [Parameter(ValueFromRemainingArguments)]$Rest)
    @('skycraft-auth')
}

function Get-AzContainerGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name              = $Name
        ProvisioningState = 'Succeeded'
        IpAddress         = [pscustomobject]@{ Ip = '192.0.2.10'; Fqdn = 'skycraft-auth.swedencentral.azurecontainer.io' }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param(
        [string]$ResourceGroupName,
        [string]$ResourceType,
        [string]$Name,
        [switch]$ExpandProperties,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )
    if ($ResourceType -ne 'Microsoft.App/containerApps') { throw "stub: unexpected Get-AzResource call (type '$ResourceType', name '$Name')" }
    $template = [pscustomobject]@{
        scale = [pscustomobject]@{ rules = @([pscustomobject]@{ name = 'http-load'; http = [pscustomobject]@{ metadata = [pscustomobject]@{ concurrentRequests = '10' } } }) }
    }
    if ($env:SKYCRAFT_STUB_ACA -ne 'nocontainers') {
        $template | Add-Member -NotePropertyName containers -NotePropertyValue @([pscustomobject]@{ name = 'world'; image = 'devskycraftswcacr01.azurecr.io/skycraft-auth:v1' })
    }
    [pscustomobject]@{
        Name       = $Name
        Properties = [pscustomobject]@{
            provisioningState    = 'Succeeded'
            configuration        = [pscustomobject]@{ ingress = [pscustomobject]@{ external = $true; fqdn = "$Name.example.swedencentral.azurecontainerapps.io" } }
            template             = $template
            managedEnvironmentId = "$script:Sub/resourceGroups/$ResourceGroupName/providers/Microsoft.App/managedEnvironments/dev-skycraft-swc-cae-02"
        }
    }
}
'@

    function Invoke-ValidatorScript {
        param([pscustomobject]$Stub, [ValidateSet('guide', 'nocontainers')][string]$Aca)
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

    $script:AsGuide      = Invoke-ValidatorScript -Stub $script:Stub -Aca 'guide'
    $script:NoContainers = Invoke-ValidatorScript -Stub $script:Stub -Aca 'nocontainers'
    $script:AllRuns      = @($script:AsGuide, $script:NoContainers)
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

Describe 'Lab 3.3 Test-Lab.ps1 - a container app without containers is a failed check, not a crash (#355)' {

    It 'passes the resources as the guide leaves them' {
        $run = $script:AsGuide
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Image Tag 'v1' verified"
        $run.FailLines | Should -Be 0
    }

    It 'fails the image tag check of a template without containers and still reaches the summary' {
        $run = $script:NoContainers
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match 'Cannot index into a null array'
        $run.Output | Should -Match '\[FAIL\] Image Tag mismatch'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Lab 3\.3 validation found 1 issue\(s\)\.'
    }
}
