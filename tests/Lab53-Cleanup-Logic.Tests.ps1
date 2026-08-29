<#
.SYNOPSIS
    Pester 5 test: the decisions Lab 5.3 cleanup makes about what to delete.

.DESCRIPTION
    Every other suite in tests/ checks source text. This one checks behaviour:
    it lifts the decision helpers out of
    module-5-monitoring-maintenance/5.3-network-monitoring/scripts/Remove-LabResource.ps1
    with the PowerShell parser and runs them against synthetic input.

    Parsing the file and evaluating only its FunctionDefinitionAst nodes means
    the script body never executes, so no Azure call is made and no Az module is
    needed - while the code under test is the real code the lab ships, not a
    copy that could drift from it.

    Why this exists (issue #106 follow-up): the NWTA-* branch of step [4/4]
    could not be verified against live Azure. Traffic Analytics only creates its
    data collection rule and endpoint after processing real flow data for a
    sustained period; a purpose-built environment with a correctly configured
    flow log, captured flows and forced traffic did not produce them in ~86
    minutes. Selection, filtering, ordering and the guard are therefore pinned
    here instead, where they can be checked in milliseconds.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab53-Cleanup-Logic.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $ScriptPath = Join-Path $RepoRoot 'module-5-monitoring-maintenance/5.3-network-monitoring/scripts/Remove-LabResource.ps1'

    $parseError = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$parseError)
    if ($parseError) {
        throw "Remove-LabResource.ps1 does not parse: $($parseError[0].Message)"
    }

    # Top level only ($false): nested helpers would not be callable on their own.
    $functionAst = $ast.FindAll(
        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($function in $functionAst) {
        . ([scriptblock]::Create($function.Extent.Text))
    }

    $script:LiftedName = @($functionAst.Name)

    function Get-EndpointFixture {
        param([string]$Name, [string]$ResourceId)
        [PSCustomObject]@{ name = $Name; resourceId = $ResourceId }
    }

    function Get-PlatformResourceFixture {
        param([string]$Name, [string]$ResourceType)
        [PSCustomObject]@{
            Name         = $Name
            ResourceType = $ResourceType
            ResourceId   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-skycraft-swc-rg/providers/$ResourceType/$Name"
        }
    }

    $script:DevAuthVmId   = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm'
    $script:DevWorldVmId  = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-world-vm'
    $script:ProdAuthVmId  = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/prod-skycraft-swc-auth-vm'
}

Describe 'Lab 5.3 cleanup - the script exposes its decisions as functions' {

    It 'defines every decision helper the cleanup relies on' {
        foreach ($name in @(
                'Get-VirtualMachineEndpointId'
                'ConvertTo-VmTarget'
                'Test-LabOwnedExtension'
                'Select-TrafficAnalyticsResource')) {
            $script:LiftedName | Should -Contain $name
        }
    }
}

Describe 'Lab 5.3 cleanup - connection monitor endpoints' {

    # Every call below collects the result with @(...), exactly as
    # Remove-LabResource.ps1 does. A PowerShell function emits its results one
    # by one, so the caller - not the function - is what makes a single match an
    # array; testing any other way would pin a contract the script never uses.

    It 'returns the VM resource IDs of both endpoints' {
        $result = @(Get-VirtualMachineEndpointId -Endpoint @(
                Get-EndpointFixture -Name 'prod-auth-source'     -ResourceId $script:ProdAuthVmId
                Get-EndpointFixture -Name 'dev-auth-destination' -ResourceId $script:DevAuthVmId
            ))
        $result.Count | Should -Be 2
        $result | Should -Contain $script:ProdAuthVmId
        $result | Should -Contain $script:DevAuthVmId
    }

    It 'ignores endpoints that are not virtual machines' {
        # An ExternalAddress endpoint carries no resourceId; a subnet endpoint
        # carries one that must not be mistaken for a VM.
        $result = @(Get-VirtualMachineEndpointId -Endpoint @(
                Get-EndpointFixture -Name 'external' -ResourceId $null
                Get-EndpointFixture -Name 'subnet'   -ResourceId '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet/subnets/AuthSubnet'
                Get-EndpointFixture -Name 'vm'       -ResourceId $script:DevAuthVmId
            ))
        $result.Count | Should -Be 1
        $result[0] | Should -Be $script:DevAuthVmId
    }

    It 'returns nothing when the connection monitor is already gone' {
        # $null is what Get-AzResource yields for a deleted monitor. The count
        # has to be a real 0, because that is what sends step [3/4] to the
        # candidate VM list instead of leaving the agents behind.
        @(Get-VirtualMachineEndpointId -Endpoint $null).Count | Should -Be 0
        @(Get-VirtualMachineEndpointId -Endpoint @()).Count   | Should -Be 0
    }

    It 'gives the caller a one-item array when a single endpoint matches' {
        $result = @(Get-VirtualMachineEndpointId -Endpoint @(
                Get-EndpointFixture -Name 'dev-auth-destination' -ResourceId $script:DevAuthVmId
            ))
        $result.Count | Should -Be 1
        # Indexing must yield the ID, not its first character.
        $result[0] | Should -Be $script:DevAuthVmId
    }
}

Describe 'Lab 5.3 cleanup - VM targets' {

    It 'splits a resource ID into its resource group and name' {
        $target = @(ConvertTo-VmTarget -VmResourceId $script:DevAuthVmId)
        $target.Count                   | Should -Be 1
        $target[0].ResourceGroupName    | Should -Be 'dev-skycraft-swc-rg'
        $target[0].Name                 | Should -Be 'dev-skycraft-swc-auth-vm'
        $target[0].Id                   | Should -Be $script:DevAuthVmId
    }

    It 'keeps VMs from different resource groups apart' {
        $target = @(ConvertTo-VmTarget -VmResourceId @($script:ProdAuthVmId, $script:DevAuthVmId))
        $target.Count | Should -Be 2
        ($target | Where-Object { $_.Name -eq 'prod-skycraft-swc-auth-vm' }).ResourceGroupName |
            Should -Be 'prod-skycraft-swc-rg'
        ($target | Where-Object { $_.Name -eq 'dev-skycraft-swc-auth-vm' }).ResourceGroupName |
            Should -Be 'dev-skycraft-swc-rg'
    }

    It 'processes a VM only once when it is listed twice' {
        # The monitor can name the same VM as source and destination.
        (@(ConvertTo-VmTarget -VmResourceId @($script:DevAuthVmId, $script:DevAuthVmId))).Count |
            Should -Be 1
    }

    It 'returns nothing for an empty list' {
        (@(ConvertTo-VmTarget -VmResourceId @())).Count | Should -Be 0
    }
}

Describe 'Lab 5.3 cleanup - extension ownership guard' {

    It 'claims an agent this lab tagged' {
        Test-LabOwnedExtension -Tag @{ Project = 'SkyCraft'; Environment = 'Development' } |
            Should -BeTrue
    }

    It 'leaves an agent belonging to another project alone' {
        Test-LabOwnedExtension -Tag @{ Project = 'SomethingElse' } | Should -BeFalse
    }

    It 'leaves an untagged agent alone' {
        # Get-AzResource yields $null tags for a resource with none; an agent the
        # lab did not install must survive cleanup.
        Test-LabOwnedExtension -Tag $null      | Should -BeFalse
        Test-LabOwnedExtension -Tag @{}        | Should -BeFalse
        Test-LabOwnedExtension -Tag @{ Owner = 'someone' } | Should -BeFalse
    }
}

Describe 'Lab 5.3 cleanup - Traffic Analytics resource selection' {

    BeforeAll {
        $script:PlatformResource = @(
            Get-PlatformResourceFixture -Name 'NWTA-794cbf46-8c63-4a87-9521-7582a107a678-swedencentral' -ResourceType 'Microsoft.Insights/dataCollectionEndpoints'
            Get-PlatformResourceFixture -Name 'NWTA-794cbf46-8c63-4a87-9521-7582a107a678-swedencentral' -ResourceType 'Microsoft.Insights/dataCollectionRules'
            Get-PlatformResourceFixture -Name 'platform-skycraft-swc-law'  -ResourceType 'Microsoft.OperationalInsights/workspaces'
            Get-PlatformResourceFixture -Name 'platformskycraftswcsa'      -ResourceType 'Microsoft.Storage/storageAccounts'
            Get-PlatformResourceFixture -Name 'skycraft-vm-dcr'            -ResourceType 'Microsoft.Insights/dataCollectionRules'
        )
    }

    It 'selects both NWTA resources and nothing else' {
        $result = @(Select-TrafficAnalyticsResource -Resource $script:PlatformResource -TrafficAnalyticsFlowLogCount 0)
        $result.Count | Should -Be 2
        $result.Name | ForEach-Object { $_ | Should -BeLike 'NWTA-*' }
    }

    It "leaves Lab 5.1's own data collection rule in place" {
        # skycraft-vm-dcr is the VM Insights DCR from Lab 5.1: same resource
        # type, different owner. Only the NWTA- prefix separates them.
        $result = @(Select-TrafficAnalyticsResource -Resource $script:PlatformResource -TrafficAnalyticsFlowLogCount 0)
        $result.Name | Should -Not -Contain 'skycraft-vm-dcr'
    }

    It 'deletes the rule before the endpoint it references' {
        $result = @(Select-TrafficAnalyticsResource -Resource $script:PlatformResource -TrafficAnalyticsFlowLogCount 0)
        $result[0].ResourceType | Should -Be 'Microsoft.Insights/dataCollectionRules'
        $result[1].ResourceType | Should -Be 'Microsoft.Insights/dataCollectionEndpoints'
    }

    It 'keeps the pair while a flow log still feeds Traffic Analytics' {
        @(Select-TrafficAnalyticsResource -Resource $script:PlatformResource -TrafficAnalyticsFlowLogCount 1).Count |
            Should -Be 0
        @(Select-TrafficAnalyticsResource -Resource $script:PlatformResource -TrafficAnalyticsFlowLogCount 5).Count |
            Should -Be 0
    }

    It 'returns nothing when the resource group holds no NWTA resources' {
        $noNwta = @(
            Get-PlatformResourceFixture -Name 'platform-skycraft-swc-law' -ResourceType 'Microsoft.OperationalInsights/workspaces'
            Get-PlatformResourceFixture -Name 'skycraft-vm-dcr'           -ResourceType 'Microsoft.Insights/dataCollectionRules'
        )
        @(Select-TrafficAnalyticsResource -Resource $noNwta -TrafficAnalyticsFlowLogCount 0).Count | Should -Be 0
    }

    It 'returns nothing for an empty or absent resource group' {
        @(Select-TrafficAnalyticsResource -Resource @()   -TrafficAnalyticsFlowLogCount 0).Count | Should -Be 0
        @(Select-TrafficAnalyticsResource -Resource $null -TrafficAnalyticsFlowLogCount 0).Count | Should -Be 0
    }

    It 'ignores an NWTA-named resource of an unrelated type' {
        # Defensive: only the two data collection types are ever deleted.
        $decoy = @(Get-PlatformResourceFixture -Name 'NWTA-decoy' -ResourceType 'Microsoft.Storage/storageAccounts')
        @(Select-TrafficAnalyticsResource -Resource $decoy -TrafficAnalyticsFlowLogCount 0).Count | Should -Be 0
    }
}
