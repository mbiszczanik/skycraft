<#
.SYNOPSIS
    Pester 5 test: every Lab 3.3 resource name follows the environment the caller picks.

.DESCRIPTION
    Issue #121: Lab 3.3 spelled its container names for dev and for nothing else, so
    `-Environment prod` deployed dev-named resources into the prod resource group, and the
    prod and platform containers a hand-edited branch had deployed could neither be validated
    nor torn down from this repository. Every other Module 3 lab composes its names from the
    environment; this suite pins Lab 3.3 to the same contract.

    It lifts the param block out of each script with the PowerShell parser and evaluates
    only that - the defaults are expressions, so binding `-Environment prod` yields the
    names the script would act on, without the script body running and without Azure. The
    Bicep side is checked as text: the defaults must be composed from parEnvironment, and
    the parameter file must not pin a name back to dev.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab33-Environment-Names.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $LabRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'module-3-compute/3.3-containers'

    # The name parameters each script must expose beside -Environment. Deploy-Bicep.ps1
    # needs only the registry (Phase 1 runs before the template); the template composes the
    # rest. The validator and the teardown act on every resource, so they take every name.
    $ScriptCases = @(
        @{ Script = 'Deploy-Bicep.ps1';        NameParameter = @('ResourceGroupName', 'AcrName') }
        @{ Script = 'Test-Lab.ps1';            NameParameter = @('ResourceGroupName', 'AcrName', 'AciName', 'CaeName', 'AcaName') }
        @{ Script = 'Remove-LabResource.ps1';  NameParameter = @('ResourceGroupName', 'AcrName', 'AciName', 'CaeName', 'AcaName') }
    ) | ForEach-Object { $_.Path = Join-Path $LabRoot "scripts/$($_.Script)"; $_ }
}

BeforeAll {
    $LabRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'module-3-compute/3.3-containers'

    # The scheme every environment must produce; {0} is the environment prefix.
    $script:ExpectedName = @{
        ResourceGroupName = '{0}-skycraft-swc-rg'
        AcrName           = '{0}skycraftswcacr01'
        AciName           = '{0}-skycraft-swc-aci-auth'
        CaeName           = '{0}-skycraft-swc-cae-02'
        AcaName           = '{0}-skycraft-swc-aca-world'
    }

    function Get-ParamBlockDefault {
        <#
        .SYNOPSIS
            Binds a script's param block on its own and returns the resolved parameter values.
        #>
        param(
            [Parameter(Mandatory = $true)] [string]$Path,
            [Parameter(Mandatory = $true)] [hashtable]$Bind
        )

        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$Path does not parse: $($parseError[0].Message)" }
        if (-not $ast.ParamBlock) { throw "$Path has no param block" }

        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $body = $ast.ParamBlock.Extent.Text + "`n" +
            '$resolved = @{}' + "`n" +
            'foreach ($n in @(' + (($names | ForEach-Object { "'$_'" }) -join ', ') + ')) { $resolved[$n] = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue }' + "`n" +
            'return $resolved'

        return & ([scriptblock]::Create($body)) @Bind
    }

    function Get-ParameterAst {
        param([string]$Path, [string]$Name)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        return $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Name }
    }
}

Describe 'Lab 3.3 <Script> takes the environment it deploys, validates or tears down' -ForEach $ScriptCases {

    It 'exposes -Environment constrained to dev, prod and platform' {
        $parameter = Get-ParameterAst -Path $Path -Name 'Environment'
        $parameter | Should -Not -BeNullOrEmpty -Because "$Script must accept -Environment"

        $validateSet = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validateSet | Should -Not -BeNullOrEmpty
        @($validateSet.PositionalArguments | ForEach-Object { $_.Value }) | Sort-Object |
            Should -Be @('dev', 'platform', 'prod')
    }

    It 'exposes -<_> so a name can be overridden' -ForEach $NameParameter {
        Get-ParameterAst -Path $Path -Name $_ | Should -Not -BeNullOrEmpty
    }

    Context 'defaults compose from -Environment <Environment>' -ForEach @(
        @{ Environment = 'dev' }
        @{ Environment = 'prod' }
        @{ Environment = 'platform' }
    ) {
        BeforeAll {
            $script:Resolved = Get-ParamBlockDefault -Path $Path -Bind @{ Environment = $Environment }
        }

        It 'resolves -<_> for <Environment>' -ForEach $NameParameter {
            $script:Resolved[$_] | Should -Be ($script:ExpectedName[$_] -f $Environment)
        }
    }

    It 'keeps every resolved name inside the Azure length limit for platform' {
        $resolved = Get-ParamBlockDefault -Path $Path -Bind @{ Environment = 'platform' }
        if ($resolved.ContainsKey('AcaName')) { $resolved.AcaName.Length | Should -BeLessOrEqual 32 }
        if ($resolved.ContainsKey('AcrName')) { $resolved.AcrName.Length | Should -BeLessOrEqual 50 }
        if ($resolved.ContainsKey('CaeName')) { $resolved.CaeName.Length | Should -BeLessOrEqual 60 }
        if ($resolved.ContainsKey('AciName')) { $resolved.AciName.Length | Should -BeLessOrEqual 63 }
    }

    It 'spells no dev-only resource name in code' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $literal = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $args[0].Value -match 'devskycraftswcacr01|dev-skycraft-swc-'
            }, $true)
        @($literal | ForEach-Object { $_.Value }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 3.3 Bicep names compose from parEnvironment' {

    It '<File> defaults <Parameter> from parEnvironment' -ForEach @(
        @{ File = 'bicep/main.bicep'; Parameter = 'parResourceGroupName' }
        @{ File = 'bicep/main.bicep'; Parameter = 'parAcrName' }
        @{ File = 'bicep/main.bicep'; Parameter = 'parAciName' }
        @{ File = 'bicep/main.bicep'; Parameter = 'parCaeName' }
        @{ File = 'bicep/main.bicep'; Parameter = 'parAcaName' }
        @{ File = 'bicep/acr.bicep';  Parameter = 'parAcrName' }
    ) {
        $text = Get-Content -Raw -LiteralPath (Join-Path $LabRoot $File)
        $match = [regex]::Match($text, "param $Parameter string = '([^']*)'")
        $match.Success | Should -BeTrue -Because "$File must declare $Parameter with a default"
        $match.Groups[1].Value | Should -Match '^\$\{parEnvironment\}'
    }

    It 'the platform container app name fits the 32-character limit' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $LabRoot 'bicep/main.bicep')
        $default = [regex]::Match($text, "param parAcaName string = '([^']*)'").Groups[1].Value
        ($default -replace '\$\{parEnvironment\}', 'platform').Length | Should -BeLessOrEqual 32
    }

    It 'the parameter file pins no resource name back to dev' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $LabRoot 'bicep/parameters/main.bicepparam')
        $text | Should -Not -Match 'param par(ResourceGroupName|AcrName|AciName|CaeName|AcaName)\b'
    }
}
