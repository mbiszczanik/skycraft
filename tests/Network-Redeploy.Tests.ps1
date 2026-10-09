<#
.SYNOPSIS
    Pester 5 test: re-running Lab 2.1 or Lab 3.1 leaves the networks later labs built intact.

.DESCRIPTION
    Regression guard for issue #188. Both labs were unsafe to re-run on a subscription where hub
    and prod already stood, for example to add the dev spoke:

      Lab 3.1  redeployed the hub VNet through modules/network.bicep, which declares no peerings,
               so ARM reset virtualNetworkPeerings and hub-to-prod disappeared. The dev VNet had
               the same problem with dev-to-hub (and with the NSGs and service endpoints Lab 2.2
               attaches).
      Lab 2.1  re-declared every subnet, so the prod subnets lost Lab 2.2's NSGs, AppServiceSubnet
               had its portal-made 'delegation' renamed, privateEndpointNetworkPolicies flipped to
               'Enabled', prod-skycraft-swc-lb-pip gained zones, and the peerings flipped
               doNotVerifyRemoteGateways to the AVM default.

    The fix pinned here:

      Lab 3.1  deploys a VNet only when it does not exist. scripts/Deploy-Bicep.ps1 looks the hub
               and dev VNets up and hands the result to the parameter files through
               SKYCRAFT_HUB_VNET_EXISTS / SKYCRAFT_DEV_VNET_EXISTS.
      Lab 2.1  leaves existing subnets and public IPs out of the deployment (parExistingSubnets,
               parDevLbPipExists, parProdLbPipExists, filled by scripts/Deploy-Bicep.ps1), and
               declares privateEndpointNetworkPolicies 'Disabled' and doNotVerifyRemoteGateways
               false, the values Azure and the portal use.

    Three layers: the compiled templates (what ARM receives), the deploy scripts' decision
    helpers lifted from their AST, and both deploy scripts run end to end with -WhatIf in a child
    pwsh whose Az cmdlets are stubs (tests/Support/LabScriptStub.psm1), so no Azure call is made.

.EXAMPLE
    Invoke-Pester -Path .\tests\Network-Redeploy.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #188
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Lab21    = Join-Path $script:RepoRoot 'module-2-networking/2.1-virtual-networks'
    $script:Lab31    = Join-Path $script:RepoRoot 'module-3-compute/3.1-infrastructure-as-code'

    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:Bicep   = Get-BicepCliPath
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-188-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # --outfile rather than --stdout: --stdout crashes on a non-UTF-8 Windows console as soon as
    # a template pulls in an AVM module (docs/dry-run-harness.md).
    function ConvertFrom-BicepFile {
        param([string]$Path, [string]$Name)
        $out = Join-Path $script:WorkDir "$Name.json"
        $null = & $script:Bicep build $Path --outfile $out 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bicep build failed for $Path" }
        Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable
    }

    function ConvertFrom-BicepParamFile {
        param([string]$Path, [string]$Name)
        $out = Join-Path $script:WorkDir "$Name.parameters.json"
        $null = & $script:Bicep build-params $Path --outfile $out 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bicep build-params failed for $Path" }
        (Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable).parameters
    }

    # A template compiled with languageVersion 2.0 (Lab 2.1: it declares a type) keys resources by
    # symbolic name; a classic one (Lab 3.1) lists them, so they are found by deployment name.
    function Get-TemplateResource {
        param([System.Collections.IDictionary]$Template, [string]$Symbol, [string]$Name)
        if ($Template.resources -is [System.Collections.IDictionary]) { return $Template.resources[$Symbol] }
        $Template.resources | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    }

    # Lifts the top-level functions of a script without running its body (as
    # tests/Lab21-Subnet-Link-Preflight.Tests.ps1 does for the Lab 2.1 cleanup).
    function Import-ScriptFunction {
        param([string]$Path)
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$Path does not parse: $($parseError[0].Message)" }
        $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
            ForEach-Object { $_.Extent.Text }
    }

    function Get-StubErrorRecord {
        param([string]$Message)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), 'StubError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
    }

    $script:Template21 = ConvertFrom-BicepFile -Path (Join-Path $script:Lab21 'bicep/main.bicep') -Name 'lab21'
    $script:Template31 = ConvertFrom-BicepFile -Path (Join-Path $script:Lab31 'bicep/main.bicep') -Name 'lab31'
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.1 template - an existing VNet is referenced, not redeployed' {

    It 'deploys the hub VNet only when parHubVnetExists is false' {
        $hub = Get-TemplateResource -Template $script:Template31 -Symbol 'modHubVnet' -Name 'hubVnetDeployment'
        $hub | Should -Not -BeNullOrEmpty
        $hub.condition | Should -Be "[not(parameters('parHubVnetExists'))]" -Because 'redeploying the hub resets its peerings and removes hub-to-prod (#188)'
    }

    It 'deploys the dev VNet only when parDevVnetExists is false' {
        $dev = Get-TemplateResource -Template $script:Template31 -Symbol 'modDevVnet' -Name 'devVnetDeployment'
        $dev | Should -Not -BeNullOrEmpty
        $dev.condition | Should -Be "[not(parameters('parDevVnetExists'))]" -Because 'redeploying the dev VNet removes dev-to-hub and swaps the Lab 2.2 subnet settings'
    }

    It 'defaults both flags to a first deployment' {
        $script:Template31.parameters.parHubVnetExists.defaultValue | Should -BeFalse
        $script:Template31.parameters.parDevVnetExists.defaultValue | Should -BeFalse
    }

    It 'builds the VNet ID outputs from the names, not from the conditional modules' {
        # A reference to a module that did not run fails the deployment; an ID by name does not.
        $script:Template31.outputs.outHubVnetId.value | Should -Not -Match 'hubVnetDeployment'
        $script:Template31.outputs.outDevVnetId.value | Should -Not -Match 'devVnetDeployment'
        $script:Template31.outputs.outHubVnetId.value | Should -Match "virtualNetworks', variables\('varHubVnetName'\)"
    }

    It "creates subnets with privateEndpointNetworkPolicies 'Disabled', as Lab 2.1 does" {
        Get-Content -Raw -LiteralPath (Join-Path $script:Lab31 'bicep/modules/network.bicep') |
            Should -Match "privateEndpointNetworkPolicies: 'Disabled'"
    }

    It 'no longer claims that a re-run after Module 2 changes nothing' {
        Get-Content -Raw -LiteralPath (Join-Path $script:Lab31 'bicep/main.bicep') | Should -Not -Match 'changes nothing'
    }
}

Describe 'Lab 3.1 parameter files - the lookup reaches the template' {

    It "'<file>' reads both flags from the environment Deploy-Bicep.ps1 sets" -ForEach @(
        @{ file = 'dev.bicepparam' }
        @{ file = 'prod.bicepparam' }
    ) {
        $path = Join-Path $script:Lab31 "bicep/parameters/$file"
        $saved = @{ hub = $env:SKYCRAFT_HUB_VNET_EXISTS; dev = $env:SKYCRAFT_DEV_VNET_EXISTS }
        try {
            $env:SKYCRAFT_HUB_VNET_EXISTS = $null
            $env:SKYCRAFT_DEV_VNET_EXISTS = $null
            $unset = ConvertFrom-BicepParamFile -Path $path -Name "$file-unset"
            $unset.parHubVnetExists.value | Should -BeFalse
            $unset.parDevVnetExists.value | Should -BeFalse

            $env:SKYCRAFT_HUB_VNET_EXISTS = 'true'
            $env:SKYCRAFT_DEV_VNET_EXISTS = 'false'
            $set = ConvertFrom-BicepParamFile -Path $path -Name "$file-set"
            $set.parHubVnetExists.value | Should -BeTrue
            $set.parDevVnetExists.value | Should -BeFalse
        }
        finally {
            $env:SKYCRAFT_HUB_VNET_EXISTS = $saved.hub
            $env:SKYCRAFT_DEV_VNET_EXISTS = $saved.dev
        }
    }
}

Describe 'Lab 2.1 template - a re-run leaves what later labs set alone' {

    It "deploys only the '<vnet>' subnets that do not exist yet" -ForEach @(
        @{ vnet = 'hub'; symbol = 'modVnetHub'; variable = 'varHubSubnetsToDeploy' }
        @{ vnet = 'dev'; symbol = 'modVnetDev'; variable = 'varDevSubnetsToDeploy' }
        @{ vnet = 'prod'; symbol = 'modVnetProd'; variable = 'varProdSubnetsToDeploy' }
    ) {
        $module = Get-TemplateResource -Template $script:Template21 -Symbol $symbol
        $module.properties.parameters.subnets.value | Should -Be "[variables('$variable')]"
        $script:Template21.variables[$variable] | Should -Match ([regex]::Escape("parameters('parExistingSubnets').$vnet"))
        $script:Template21.variables[$variable] | Should -Match '^\[filter\('
    }

    It 'defaults parExistingSubnets to a first deployment' {
        $default = $script:Template21.parameters.parExistingSubnets.defaultValue
        foreach ($vnet in 'hub', 'dev', 'prod') {
            @($default[$vnet]).Count | Should -Be 0
        }
    }

    It "declares privateEndpointNetworkPolicies 'Disabled' on every subnet of '<variable>'" -ForEach @(
        @{ variable = 'varHubSubnets' }
        @{ variable = 'varDevSubnets' }
        @{ variable = 'varProdSubnets' }
    ) {
        # Unset, the AVM subnet module sends nothing and the API applies 'Enabled'.
        foreach ($subnet in $script:Template21.variables[$variable]) {
            $subnet.privateEndpointNetworkPolicies | Should -Be 'Disabled' -Because "$($subnet.name) must match the portal and the existing subnets"
        }
    }

    It "names the AppServiceSubnet delegation the way Lab 3.1's network module does" {
        # The AVM module names a delegation after its service; Lab 3.1 does the same, so the two
        # labs never rename it on each other.
        foreach ($variable in 'varDevSubnets', 'varProdSubnets') {
            $app = $script:Template21.variables[$variable] | Where-Object { $_.name -eq 'AppServiceSubnet' }
            $app.delegation | Should -Be 'Microsoft.Web/serverFarms'
        }
        Get-Content -Raw -LiteralPath (Join-Path $script:Lab31 'bicep/modules/network.bicep') |
            Should -Match 'name: subnet\.delegation!'
    }

    It "declares doNotVerifyRemoteGateways false on both directions of '<peering>'" -ForEach @(
        @{ peering = 'hub-to-dev' }
        @{ peering = 'hub-to-prod' }
    ) {
        # The AVM peering module defaults it to true; Azure, the portal and Az PowerShell use false.
        $hub = Get-TemplateResource -Template $script:Template21 -Symbol 'modVnetHub'
        $entry = $hub.properties.parameters.peerings.value | Where-Object { $_.name -eq $peering }
        $entry | Should -Not -BeNullOrEmpty
        $entry.doNotVerifyRemoteGateways | Should -BeFalse
        $entry.ContainsKey('doNotVerifyRemoteGateways') | Should -BeTrue
        $entry.remotePeeringDoNotVerifyRemoteGateways | Should -BeFalse
        $entry.ContainsKey('remotePeeringDoNotVerifyRemoteGateways') | Should -BeTrue
    }

    It "creates '<symbol>' only when the public IP does not exist" -ForEach @(
        @{ symbol = 'modPipDevLb'; flag = 'parDevLbPipExists' }
        @{ symbol = 'modPipProdLb'; flag = 'parProdLbPipExists' }
    ) {
        # Zones are fixed at creation; a portal-made, non-zonal IP would reject the declaration.
        (Get-TemplateResource -Template $script:Template21 -Symbol $symbol).condition |
            Should -Be "[not(parameters('$flag'))]"
    }
}

Describe 'Deploy-Bicep.ps1 lookup helpers (Lab 2.1 and Lab 3.1)' {

    It "'<lab>' treats only a missing resource as absent" -ForEach @(
        @{ lab = '2.1'; path = 'module-2-networking/2.1-virtual-networks/scripts/Deploy-Bicep.ps1' }
        @{ lab = '3.1'; path = 'module-3-compute/3.1-infrastructure-as-code/scripts/Deploy-Bicep.ps1' }
    ) {
        foreach ($text in Import-ScriptFunction -Path (Join-Path $script:RepoRoot $path)) {
            . ([scriptblock]::Create($text))
        }

        $notFound = @(
            "The Resource 'Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet' under resource group 'dev-skycraft-swc-rg' was not found. StatusCode: 404 ErrorCode: ResourceNotFound"
            "Resource group 'dev-skycraft-swc-rg' could not be found. ErrorCode: ResourceGroupNotFound"
        )
        foreach ($message in $notFound) {
            Test-NotFoundError -ErrorRecord (Get-StubErrorRecord -Message $message) | Should -BeTrue -Because $message
            Find-ExistingResource -Lookup ([scriptblock]::Create("throw '$($message -replace "'", "''")'")) | Should -BeNullOrEmpty
        }

        $denied = "The client does not have authorization to perform action 'Microsoft.Network/virtualNetworks/read'. ErrorCode: AuthorizationFailed"
        Test-NotFoundError -ErrorRecord (Get-StubErrorRecord -Message $denied) | Should -BeFalse
        # An unreadable VNet must stop the script, never be redeployed as if it were absent.
        { Find-ExistingResource -Lookup ([scriptblock]::Create("throw '$denied'")) } | Should -Throw '*AuthorizationFailed*'

        Find-ExistingResource -Lookup { [pscustomobject]@{ Name = 'found' } } | Select-Object -ExpandProperty Name | Should -Be 'found'
    }

    It 'Get-SubnetName (Lab 2.1) returns every subnet name, and nothing for a missing VNet' {
        foreach ($text in Import-ScriptFunction -Path (Join-Path $script:Lab21 'scripts/Deploy-Bicep.ps1')) {
            . ([scriptblock]::Create($text))
        }
        @(Get-SubnetName -Vnet $null).Count | Should -Be 0
        @(Get-SubnetName -Vnet ([pscustomobject]@{ Subnets = @() })).Count | Should -Be 0
        $one = [pscustomobject]@{ Subnets = @([pscustomobject]@{ Name = 'AuthSubnet' }) }
        @(Get-SubnetName -Vnet $one) | Should -Be @('AuthSubnet')
        $four = [pscustomobject]@{ Subnets = @('AuthSubnet', 'WorldSubnet', 'DatabaseSubnet', 'AppServiceSubnet' | ForEach-Object { [pscustomobject]@{ Name = $_ } }) }
        @(Get-SubnetName -Vnet $four).Count | Should -Be 4
    }
}

Describe 'Deploy-Bicep.ps1 -WhatIf against a stubbed subscription' {

    BeforeAll {
        Import-Module (Join-Path $script:RepoRoot 'tests' 'Support' 'LabScriptStub.psm1') -Force

        # Scenario knobs: SKYCRAFT_STUB_EXISTING lists the resource names that exist,
        # SKYCRAFT_STUB_DENY makes every lookup fail with an authorization error, and
        # SKYCRAFT_STUB_LOG receives what the what-if call was given.
        $script:StubBody = @'
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Name = 'stub-context'; Subscription = [pscustomobject]@{ Name = 'stub-subscription' } }
}

function Assert-StubLookup {
    param([string]$ResourceGroupName, [string]$Name, [string]$Type)
    if ($env:SKYCRAFT_STUB_DENY -eq '1') {
        throw "The client does not have authorization to perform action '$Type/read'. ErrorCode: AuthorizationFailed"
    }
    if (@($env:SKYCRAFT_STUB_EXISTING -split ',') -notcontains $Name) {
        throw "The Resource '$Type/$Name' under resource group '$ResourceGroupName' was not found. ErrorCode: ResourceNotFound"
    }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param($ResourceGroupName, $Name)
    Assert-StubLookup -ResourceGroupName $ResourceGroupName -Name $Name -Type 'Microsoft.Network/virtualNetworks'
    $subnets = if ($Name -like 'platform-*') { 'AzureBastionSubnet', 'GatewaySubnet' }
               else { 'AuthSubnet', 'WorldSubnet', 'DatabaseSubnet', 'AppServiceSubnet' }
    [pscustomobject]@{ Name = $Name; Subnets = @($subnets | ForEach-Object { [pscustomobject]@{ Name = $_ } }) }
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param($ResourceGroupName, $Name)
    Assert-StubLookup -ResourceGroupName $ResourceGroupName -Name $Name -Type 'Microsoft.Network/publicIPAddresses'
    [pscustomobject]@{ Name = $Name }
}

function Get-AzSubscriptionDeploymentWhatIfResult {
    [CmdletBinding()]
    param($Name, $Location, $TemplateFile, $TemplateParameterFile, $TemplateParameterObject)
    [ordered]@{
        Parameters    = $TemplateParameterObject
        ParameterFile = $TemplateParameterFile
        HubVnetExists = $env:SKYCRAFT_HUB_VNET_EXISTS
        DevVnetExists = $env:SKYCRAFT_DEV_VNET_EXISTS
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $env:SKYCRAFT_STUB_LOG
}

function New-AzSubscriptionDeployment {
    [CmdletBinding()]
    param()
    throw 'New-AzSubscriptionDeployment must not run under -WhatIf'
}
'@
        $script:Commands = @(
            'Get-AzContext', 'Get-AzVirtualNetwork', 'Get-AzPublicIpAddress',
            'Get-AzSubscriptionDeploymentWhatIfResult', 'New-AzSubscriptionDeployment'
        )
        $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftAzStub188' -Command $script:Commands `
            -Body $script:StubBody -RequiredModule @('Az.Accounts', 'Az.Resources', 'Az.Network')

        function Invoke-DeployWhatIf {
            param([string]$ScriptPath, [string[]]$Existing = @(), [switch]$Deny)
            $log = Join-Path $script:Stub.Directory ('whatif-' + [guid]::NewGuid().ToString('N') + '.json')
            $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $ScriptPath -ArgumentList '-WhatIf' -Environment @{
                SKYCRAFT_STUB_EXISTING = $Existing -join ','
                SKYCRAFT_STUB_DENY     = if ($Deny) { '1' } else { '0' }
                SKYCRAFT_STUB_LOG      = $log
            }
            $call = if (Test-Path -LiteralPath $log) { Get-Content -Raw -LiteralPath $log | ConvertFrom-Json -AsHashtable } else { $null }
            [pscustomobject]@{ ExitCode = $run.ExitCode; Refused = $run.Refused; Output = $run.Output; WhatIf = $call }
        }

        $deploy21 = Join-Path $script:Lab21 'scripts/Deploy-Bicep.ps1'
        $deploy31 = Join-Path $script:Lab31 'scripts/Deploy-Bicep.ps1'

        # One child per scenario; each costs a few seconds.
        $script:Lab21Fresh   = Invoke-DeployWhatIf -ScriptPath $deploy21
        $script:Lab21AddDev  = Invoke-DeployWhatIf -ScriptPath $deploy21 -Existing @(
            'platform-skycraft-swc-vnet', 'prod-skycraft-swc-vnet', 'prod-skycraft-swc-lb-pip')
        $script:Lab21Denied  = Invoke-DeployWhatIf -ScriptPath $deploy21 -Deny
        $script:Lab31Fresh   = Invoke-DeployWhatIf -ScriptPath $deploy31
        $script:Lab31AfterM2 = Invoke-DeployWhatIf -ScriptPath $deploy31 -Existing @(
            'platform-skycraft-swc-vnet', 'dev-skycraft-swc-vnet')
        $script:Lab31Denied  = Invoke-DeployWhatIf -ScriptPath $deploy31 -Deny
    }

    AfterAll {
        if ($script:Stub) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never falls through to the real Az cmdlets' {
        foreach ($run in $script:Lab21Fresh, $script:Lab21AddDev, $script:Lab21Denied, $script:Lab31Fresh, $script:Lab31AfterM2, $script:Lab31Denied) {
            $run.Refused | Should -BeFalse -Because "the harness must shadow Az (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'Lab 2.1 declares everything on an empty subscription' {
        $script:Lab21Fresh.ExitCode | Should -Be 0 -Because $script:Lab21Fresh.Output
        $p = $script:Lab21Fresh.WhatIf.Parameters
        foreach ($vnet in 'hub', 'dev', 'prod') { @($p.parExistingSubnets[$vnet]).Count | Should -Be 0 }
        $p.parDevLbPipExists  | Should -BeFalse
        $p.parProdLbPipExists | Should -BeFalse
    }

    It 'Lab 2.1 adding dev leaves the hub and prod subnets and the prod public IP out' {
        $script:Lab21AddDev.ExitCode | Should -Be 0 -Because $script:Lab21AddDev.Output
        $p = $script:Lab21AddDev.WhatIf.Parameters
        @($p.parExistingSubnets.hub)  | Should -Be @('AzureBastionSubnet', 'GatewaySubnet')
        @($p.parExistingSubnets.prod) | Should -Be @('AuthSubnet', 'WorldSubnet', 'DatabaseSubnet', 'AppServiceSubnet')
        @($p.parExistingSubnets.dev).Count | Should -Be 0
        $p.parProdLbPipExists | Should -BeTrue
        $p.parDevLbPipExists  | Should -BeFalse
    }

    It 'Lab 2.1 stops before the what-if when a lookup is denied' {
        $script:Lab21Denied.ExitCode | Should -Be 1
        $script:Lab21Denied.WhatIf   | Should -BeNullOrEmpty -Because 'nothing may be previewed or deployed from an unreadable estate'
        $script:Lab21Denied.Output   | Should -Match 'AuthorizationFailed'
    }

    It 'Lab 3.1 creates both VNets on an empty subscription' {
        $script:Lab31Fresh.ExitCode | Should -Be 0 -Because $script:Lab31Fresh.Output
        $script:Lab31Fresh.WhatIf.HubVnetExists | Should -Be 'false'
        $script:Lab31Fresh.WhatIf.DevVnetExists | Should -Be 'false'
        $script:Lab31Fresh.WhatIf.ParameterFile | Should -Match 'dev\.bicepparam$'
    }

    It 'Lab 3.1 after Module 2 references the hub and dev VNets instead of redeploying them' {
        $script:Lab31AfterM2.ExitCode | Should -Be 0 -Because $script:Lab31AfterM2.Output
        $script:Lab31AfterM2.WhatIf.HubVnetExists | Should -Be 'true'
        $script:Lab31AfterM2.WhatIf.DevVnetExists | Should -Be 'true'
    }

    It 'Lab 3.1 stops before the what-if when a lookup is denied' {
        $script:Lab31Denied.ExitCode | Should -Be 1
        $script:Lab31Denied.WhatIf   | Should -BeNullOrEmpty
        $script:Lab31Denied.Output   | Should -Match 'AuthorizationFailed'
    }
}
