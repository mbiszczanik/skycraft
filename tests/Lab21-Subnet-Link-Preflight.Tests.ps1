<#
.SYNOPSIS
    Pester 5 test: the Lab 2.1 cleanup preflight that reports orphaned service association links.

.DESCRIPTION
    Lifts the decision helpers out of
    module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1 with the PowerShell
    parser and runs them against synthetic VNet objects, the same way
    tests/Lab53-Cleanup-Logic.Tests.ps1 does for Lab 5.3.

    Evaluating only the FunctionDefinitionAst nodes means the script body never runs, so no Azure
    call is made and no Az module is needed - while the code under test is the code the lab ships.

    Why this exists (issue #110): AppServiceSubnet on prod-skycraft-swc-vnet carries a
    serviceAssociationLink naming an App Service Plan that was deleted long ago. The link makes
    Remove-AzVirtualNetwork fail with InUseSubnetCannotBeDeleted, and until #96 and #104 the
    failure was invisible. The preflight now names the link before any delete is attempted, so the
    next occurrence is diagnosed up front instead of at the next deployment. The live subscription
    can only ever show one such link, so the shapes that matter - no links, several links, a link
    whose target still exists, an unverifiable target - are pinned here.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab21-Subnet-Link-Preflight.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $ScriptPath = Join-Path $RepoRoot 'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'

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

    function Get-LinkFixture {
        param([string]$Name, [string]$Target, [bool]$AllowDelete = $false)
        [PSCustomObject]@{ Name = $Name; Link = $Target; AllowDelete = $AllowDelete }
    }

    function Get-SubnetFixture {
        param([string]$Name, [object[]]$Links = @())
        [PSCustomObject]@{ Name = $Name; ServiceAssociationLinks = $Links }
    }

    function Get-VnetFixture {
        param([string]$Name, [object[]]$Subnets = @())
        [PSCustomObject]@{ Name = $Name; Subnets = $Subnets }
    }

    $script:AspId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Web/serverfarms/prod-skycraft-swc-asp'
}

Describe 'Lab 2.1 cleanup - the preflight decisions are exposed as functions' {

    It 'defines every helper the preflight relies on' {
        foreach ($name in @('Get-SubnetServiceLink', 'Format-ServiceLinkFinding')) {
            $script:LiftedName | Should -Contain $name
        }
    }
}

Describe 'Get-SubnetServiceLink' {

    It 'reports nothing for a VNet that is null' {
        @(Get-SubnetServiceLink -Vnet $null).Count | Should -Be 0
    }

    It 'returns an empty array for a VNet with no subnets' {
        @(Get-SubnetServiceLink -Vnet (Get-VnetFixture -Name 'dev-skycraft-swc-vnet')).Count | Should -Be 0
    }

    It 'returns an empty array when no subnet carries a link' {
        $vnet = Get-VnetFixture -Name 'dev-skycraft-swc-vnet' -Subnets @(
            (Get-SubnetFixture -Name 'AppServiceSubnet'),
            (Get-SubnetFixture -Name 'AuthSubnet')
        )
        @(Get-SubnetServiceLink -Vnet $vnet).Count | Should -Be 0
    }

    It 'reports the single orphaned link that blocks the prod VNet delete' {
        $vnet = Get-VnetFixture -Name 'prod-skycraft-swc-vnet' -Subnets @(
            (Get-SubnetFixture -Name 'AuthSubnet'),
            (Get-SubnetFixture -Name 'AppServiceSubnet' -Links @(
                (Get-LinkFixture -Name 'AppServiceLink' -Target $script:AspId)))
        )

        $result = @(Get-SubnetServiceLink -Vnet $vnet)
        $result.Count               | Should -Be 1
        $result[0].VnetName         | Should -Be 'prod-skycraft-swc-vnet'
        $result[0].SubnetName       | Should -Be 'AppServiceSubnet'
        $result[0].LinkName         | Should -Be 'AppServiceLink'
        $result[0].LinkedResourceId | Should -Be $script:AspId
        $result[0].AllowDelete      | Should -BeFalse
    }

    It 'stays countable inline when exactly one link is found' {
        $vnet = Get-VnetFixture -Name 'prod-skycraft-swc-vnet' -Subnets @(
            (Get-SubnetFixture -Name 'AppServiceSubnet' -Links @(
                (Get-LinkFixture -Name 'AppServiceLink' -Target $script:AspId)))
        )
        # Guards the trap this helper was written around: returning ',$findings' would make
        # every inline @(...) capture report 1, so an empty result would read as one finding.
        @(Get-SubnetServiceLink -Vnet $vnet).Count | Should -Be 1
    }

    It 'flattens links across several subnets' {
        $vnet = Get-VnetFixture -Name 'dev-skycraft-swc-vnet' -Subnets @(
            (Get-SubnetFixture -Name 'AppServiceSubnet' -Links @(
                (Get-LinkFixture -Name 'AppServiceLink' -Target $script:AspId))),
            (Get-SubnetFixture -Name 'FunctionSubnet' -Links @(
                (Get-LinkFixture -Name 'AppServiceLink' -Target 'x'),
                (Get-LinkFixture -Name 'OtherLink' -Target 'y')))
        )

        $result = @(Get-SubnetServiceLink -Vnet $vnet)
        $result.Count | Should -Be 3
        @($result | Where-Object { $_.SubnetName -eq 'FunctionSubnet' }).Count | Should -Be 2
    }

    It 'carries allowDelete through as reported' {
        $vnet = Get-VnetFixture -Name 'dev-skycraft-swc-vnet' -Subnets @(
            (Get-SubnetFixture -Name 'AppServiceSubnet' -Links @(
                (Get-LinkFixture -Name 'AppServiceLink' -Target $script:AspId -AllowDelete $true)))
        )
        (@(Get-SubnetServiceLink -Vnet $vnet))[0].AllowDelete | Should -BeTrue
    }
}

Describe 'Format-ServiceLinkFinding' {

    BeforeAll {
        $script:Finding = [PSCustomObject]@{
            VnetName         = 'prod-skycraft-swc-vnet'
            SubnetName       = 'AppServiceSubnet'
            LinkName         = 'AppServiceLink'
            LinkedResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Web/serverfarms/prod-skycraft-swc-asp'
            AllowDelete      = $false
        }
    }

    It 'calls out an orphan when the target no longer exists' {
        $line = Format-ServiceLinkFinding -Link $script:Finding -LinkedResourceExists $false
        $line | Should -Match 'ORPHANED'
        $line | Should -Match 'prod-skycraft-swc-vnet/AppServiceSubnet'
        $line | Should -Match 'AppServiceLink'
        $line | Should -Match 'prod-skycraft-swc-asp'
        $line | Should -Match 'allowDelete=False'
    }

    It 'does not call a link with a live target an orphan' {
        $line = Format-ServiceLinkFinding -Link $script:Finding -LinkedResourceExists $true
        $line | Should -Not -Match 'ORPHANED'
        $line | Should -Match 'target still exists'
    }

    It 'says so rather than guessing when the target could not be resolved' {
        $line = Format-ServiceLinkFinding -Link $script:Finding -LinkedResourceExists $null
        $line | Should -Not -Match 'ORPHANED'
        $line | Should -Match 'target unverified'
    }
}

Describe 'Lab 2.1 cleanup - the preflight cannot change the exit code' {

    BeforeAll {
        $script:Source = Get-Content -Raw -LiteralPath (
            Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path `
                'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1')
    }

    It 'counts orphaned links separately from the deletes that failed' {
        $script:Source | Should -Match '\$orphanedLinkCount\s*=\s*0'
        $script:Source | Should -Match '\$orphanedLinkCount\+\+'
    }

    It 'never feeds the preflight into the cleanup failure counter' {
        # A reported link must not turn an otherwise clean teardown red - only a failed delete may.
        $script:Source | Should -Not -Match '\$orphanedLinkCount[^\r\n]*cleanupFailures'
        $script:Source | Should -Not -Match 'orphanedLinkCount\+\+[\s\S]{0,120}cleanupFailures\+\+'
    }

    It 'runs the preflight before the first delete' {
        $preflightAt = $script:Source.IndexOf('Preflight: service association links')
        $firstDelete = $script:Source.IndexOf('Remove-VNetPeering -VnetName')
        $preflightAt | Should -BeGreaterThan 0
        $firstDelete | Should -BeGreaterThan 0
        $preflightAt | Should -BeLessThan $firstDelete
    }
}

Describe 'Lab 3.4 cleanup - the help does not describe a 404-only detach check' {

    BeforeAll {
        $script:Lab34Source = Get-Content -Raw -LiteralPath (
            Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path `
                'module-3-compute/3.4-app-service/scripts/Remove-LabResource.ps1')
    }

    It 'documents that 200 with an empty subnet id also means detached' {
        # The code always treated both as detached; the help used to claim 404 only, which is the
        # trap that has previously burned the full wait budget on a false "still attached" (#110).
        $script:Lab34Source | Should -Not -Match 'route answers 404 once detached'
        $script:Lab34Source | Should -Match 'subnetResourceId'
    }
}
