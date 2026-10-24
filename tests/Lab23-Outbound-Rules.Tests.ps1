<#
.SYNOPSIS
    Pester 5 test: each Lab 2.3 load balancer gives the Module 3 VMs their egress through one
    outbound rule and a shared egress pool, and Lab 2.3's Test-Lab.ps1 fails on any other shape.

.DESCRIPTION
    Issue #344. The subnets are private (#279), so the Module 3 VMs reach the internet only through
    a load balancer outbound rule. The live check (2026-10-15) settled the shape Azure accepts:

      - a frontend IP takes one outbound rule with an overlapping protocol; a second one is
        refused (MoreThanOneOutboundRuleUsingSameFrontendIPConfigurationAndProtocolIsNotSupported),
        so one outbound rule per role pool cannot deploy;
      - once an outbound rule uses the frontend, every load balancing rule on it must keep SNAT
        disabled (LoadBalancingRuleMustDisableSNATSinceSameFrontendIPConfigurationIsReferencedByOutboundRule);
      - so each load balancer has one outbound rule, protocol All, for a dedicated egress pool
        '<lb>-be-outbound', and every VM NIC sits in that pool besides its role pool.

    This suite pins that shape in the Lab 2.3 template; the Lab 3.1 and 3.2 parts follow with
    their own change. Manual port allocation must be a multiple of 8 and admit
    the most instances Module 3 can put into one egress pool: the Lab 3.2 auth and world VMs plus
    the prod scale set at its autoscale maximum of 4, 6 in all, out of the 63,984 ports the
    frontend offers to its outbound rule.

    It also lifts Test-LB out of Lab 2.3's Test-Lab.ps1 with the PowerShell parser and runs it
    against stub load balancers (Get-AzLoadBalancer is a function in this scope, so no Azure call
    is made), including the one-rule-per-role-pool shape that cannot deploy.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab23-Outbound-Rules.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #344
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Lab23    = Join-Path $script:RepoRoot 'module-2-networking/2.3-name-resolution'

    # Ports the frontend IP offers to its one outbound rule (the Portal's Available frontend
    # ports), and the most instances Module 3 can put into one egress pool (2 VMs + 4 VMSS).
    $script:FrontendPorts      = 63984
    $script:MaxEgressInstances = 6

    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:Bicep   = Get-BicepCliPath
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-344-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # --outfile rather than --stdout, as tests/Network-Redeploy.Tests.ps1 explains.
    function ConvertFrom-BicepFile {
        param([string]$Path, [string]$Name)
        $out = Join-Path $script:WorkDir "$Name.json"
        $null = & $script:Bicep build $Path --outfile $out 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bicep build failed for $Path" }
        Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable
    }

    # A module parameter value is a literal or a "[variables('x')]" expression.
    function Resolve-TemplateValue {
        param([System.Collections.IDictionary]$Template, $Value)
        if ($Value -is [string] -and $Value -match "^\[variables\('(?<name>[^']+)'\)\]$") { return $Template.variables[$Matches.name] }
        $Value
    }

    # A template compiled with languageVersion 2.0 keys resources by symbolic name; a classic one lists them.
    function Get-TemplateModule {
        param([System.Collections.IDictionary]$Template, [string]$DeploymentName)
        $resources = if ($Template.resources -is [System.Collections.IDictionary]) { $Template.resources.Values } else { $Template.resources }
        $resources | Where-Object { $_.name -eq $DeploymentName } | Select-Object -First 1
    }

    $script:Template23 = ConvertFrom-BicepFile -Path (Join-Path $script:Lab23 'bicep/main.bicep') -Name 'lab23'
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.3 template - one outbound rule per frontend, for the egress pool' {

    It 'uses the Portal health-probe threshold in Bicep and the PowerShell deployment script' {
        $script = Get-Content -Raw -LiteralPath (Join-Path $script:Lab23 'scripts/Deploy-LoadBalancer.ps1')

        foreach ($deployment in 'deploy-dev-lb', 'deploy-prod-lb') {
            $probes = (Get-TemplateModule -Template $script:Template23 -DeploymentName $deployment).properties.parameters.probes.value
            @($probes).Count | Should -Be 2
            foreach ($probe in $probes) {
                (Resolve-TemplateValue -Template $script:Template23 -Value $probe.probeThreshold) | Should -Be 1
            }
        }
        @([regex]::Matches($script, '-ProbeCount 2 -ProbeThreshold 1')).Count | Should -Be 2
    }

    It "'<deployment>' keeps outbound SNAT off on its load balancing rules" -ForEach @(
        @{ deployment = 'deploy-dev-lb' }
        @{ deployment = 'deploy-prod-lb' }
    ) {
        $lb = Get-TemplateModule -Template $script:Template23 -DeploymentName $deployment
        $lb | Should -Not -BeNullOrEmpty
        foreach ($rule in $lb.properties.parameters.loadBalancingRules.value) {
            $rule.disableOutboundSnat | Should -BeTrue -Because "Azure refuses SNAT on $($rule.name) once an outbound rule uses its frontend"
        }
    }

    It "'<deployment>' has the egress pool and exactly one outbound rule for it" -ForEach @(
        @{ deployment = 'deploy-dev-lb'; lbVariable = 'varLbNameDev' }
        @{ deployment = 'deploy-prod-lb'; lbVariable = 'varLbNameProd' }
    ) {
        $params = (Get-TemplateModule -Template $script:Template23 -DeploymentName $deployment).properties.parameters
        $egressPool = "[format('{0}-be-outbound', variables('$lbVariable'))]"
        @($params.backendAddressPools.value | ForEach-Object { $_.name }) | Should -Contain $egressPool

        $outbound = @($params.outboundRules.value)
        foreach ($frontend in $params.frontendIPConfigurations.value) {
            @($outbound | Where-Object { $_.frontendIPConfigurationName -eq $frontend.name }).Count |
                Should -Be 1 -Because 'Azure refuses a second outbound rule with an overlapping protocol on one frontend IP'
        }
        $outbound.Count | Should -Be 1
        $rule = $outbound[0]
        $rule.name | Should -Be "[format('{0}-outbound', variables('$lbVariable'))]"
        $rule.backendAddressPoolName | Should -Be $egressPool
        $rule.protocol | Should -Be 'All'
        $rule.enableTcpReset | Should -BeTrue
        (Resolve-TemplateValue -Template $script:Template23 -Value $rule.idleTimeoutInMinutes) | Should -Be 4
        $ports = Resolve-TemplateValue -Template $script:Template23 -Value $rule.allocatedOutboundPorts
        $ports | Should -BeOfType [long] -Because 'manual allocation; the module default (63984) admits a single instance'
        $ports % 8 | Should -Be 0 -Because 'Azure allocates outbound ports in multiples of 8'
        [math]::Floor($script:FrontendPorts / $ports) | Should -BeGreaterOrEqual $script:MaxEgressInstances -Because 'the egress pool must admit every instance Module 3 can put there'
    }
}

Describe "Lab 2.3 Test-Lab.ps1 - the egress pool and its outbound rule are required" {

    BeforeAll {
        $path = Join-Path $script:Lab23 'scripts/Test-Lab.ps1'
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$path does not parse: $($parseError[0].Message)" }
        $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-LB' }, $true) |
            Select-Object -First 1
        $definition | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($definition.Extent.Text))

        # Test-LB reads the load balancer through this stub; nothing reaches Azure.
        function Get-AzLoadBalancer { param($ResourceGroupName, $Name, $ErrorAction) $script:StubLb }

        function New-StubPoolRef { param([string]$Name) [pscustomobject]@{ Id = "/subscriptions/stub/resourceGroups/rg/providers/Microsoft.Network/loadBalancers/lb/backendAddressPools/$Name" } }

        # One stub load balancer; each parameter breaks one part of the working design.
        function Invoke-StubTestLb {
            param(
                [string[]]$Pools = @('lb-be-world', 'lb-be-auth', 'lb-be-outbound'),
                [object[]]$OutboundRules = @([pscustomobject]@{ Name = 'lb-outbound'; Protocol = 'All'; AllocatedOutboundPorts = 8000; BackendAddressPool = (New-StubPoolRef 'LB-BE-OUTBOUND') }),
                [bool]$SnatOnAuthRule = $false,
                [object[]]$Probes = @(
                    [pscustomobject]@{ Name = 'probe-world'; ProbeThreshold = 1 }
                    [pscustomobject]@{ Name = 'probe-auth'; ProbeThreshold = 1 }
                )
            )
            $script:StubLb = [pscustomobject]@{
                Sku                 = [pscustomobject]@{ Name = 'Standard' }
                Probes              = $Probes
                BackendAddressPools = @($Pools | ForEach-Object { [pscustomobject]@{ Name = $_ } })
                LoadBalancingRules  = @(
                    [pscustomobject]@{ Name = 'rule-world'; DisableOutboundSnat = $true }
                    [pscustomobject]@{ Name = 'rule-auth'; DisableOutboundSnat = -not $SnatOnAuthRule }
                )
                OutboundRules       = $OutboundRules
                Tag                 = @{ Project = 'SkyCraft'; Environment = 'Development'; CostCenter = 'MSDN'; Owner = 'owner' }
            }
            $script:validationErrors = 0
            $output = Test-LB -RgName 'rg' -LbName 'lb' -ExpectedEnvironment 'Development' 6>&1 | ForEach-Object { "$_" }
            [pscustomobject]@{ Errors = $script:validationErrors; Output = $output }
        }
    }

    It 'passes the working design: the egress pool, its outbound rule, SNAT off on the rules' {
        $run = Invoke-StubTestLb
        $run.Errors | Should -Be 0
        $run.Output | Should -Contain '  - [OK] Egress backend pool found: lb-be-outbound'
        $run.Output | Should -Contain '  - [OK] Outbound rule lb-outbound serves lb-be-outbound (All, 8000 ports per instance)'
        $run.Output | Should -Contain '  - [OK] Outbound SNAT disabled on all 2 LB rule(s)'
    }

    It 'fails the one-rule-per-role-pool design, which Azure refuses to deploy' {
        $run = Invoke-StubTestLb -Pools 'lb-be-world', 'lb-be-auth' -OutboundRules @(
            [pscustomobject]@{ Name = 'lb-outbound-world'; Protocol = 'All'; AllocatedOutboundPorts = 8000; BackendAddressPool = (New-StubPoolRef 'lb-be-world') }
            [pscustomobject]@{ Name = 'lb-outbound-auth'; Protocol = 'All'; AllocatedOutboundPorts = 8000; BackendAddressPool = (New-StubPoolRef 'lb-be-auth') }
        )
        $run.Errors | Should -Be 1
        $run.Output | Should -Contain '  - [FAIL] Egress backend pool NOT found: lb-be-outbound'
    }

    It 'fails a probe with <condition>' -ForEach @(
        @{ condition = 'a threshold of two'; probe = [pscustomobject]@{ Name = 'probe-world'; ProbeThreshold = 2 } }
        @{ condition = 'a null threshold'; probe = [pscustomobject]@{ Name = 'probe-world'; ProbeThreshold = $null } }
        @{ condition = 'no threshold property'; probe = [pscustomobject]@{ Name = 'probe-world' } }
    ) {
        $run = Invoke-StubTestLb -Probes @($probe, [pscustomobject]@{ Name = 'probe-auth'; ProbeThreshold = 1 })
        $run.Errors | Should -Be 1
        $run.Output | Should -Contain '  - [FAIL] Health probe threshold must be 1 on: probe-world'
    }

    It 'accepts modern threshold one with ignored legacy count <legacy>' -ForEach @(
        @{ legacy = 1 }
        @{ legacy = 2 }
    ) {
        $run = Invoke-StubTestLb -Probes @(
            [pscustomobject]@{ Name = 'probe-world'; ProbeThreshold = 1; NumberOfProbes = $legacy }
            [pscustomobject]@{ Name = 'probe-auth'; ProbeThreshold = 1; NumberOfProbes = $legacy }
        )
        $run.Errors | Should -Be 0
    }

    It 'fails when no outbound rule uses the egress pool' {
        $run = Invoke-StubTestLb -OutboundRules @()
        $run.Errors | Should -Be 1
        $run.Output | Should -Contain '  - [FAIL] No outbound rule uses lb-be-outbound - the Module 3 VMs would have no internet access'
    }

    It 'fails an outbound rule with protocol <protocol> and <ports> ports' -ForEach @(
        @{ protocol = 'Tcp'; ports = 8000 }
        @{ protocol = 'All'; ports = 0 }
    ) {
        $run = Invoke-StubTestLb -OutboundRules @([pscustomobject]@{ Name = 'lb-outbound'; Protocol = $protocol; AllocatedOutboundPorts = $ports; BackendAddressPool = (New-StubPoolRef 'lb-be-outbound') })
        $run.Errors | Should -Be 1
        $run.Output | Should -Contain "  - [FAIL] Outbound rule lb-outbound for lb-be-outbound has protocol $protocol and $ports allocated ports (Expected All, more than 0)"
    }

    It 'fails a load balancing rule with outbound SNAT on (the pre-#344 design)' {
        $run = Invoke-StubTestLb -SnatOnAuthRule $true
        $run.Errors | Should -Be 1
        $run.Output | Should -Contain '  - [FAIL] Outbound SNAT not disabled on: rule-auth'
    }
}
