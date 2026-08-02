<#
.SYNOPSIS
    Pester 5 test: lab 3.3's deploy script does not overwrite two keys its parameter file sets.

.DESCRIPTION
    docs/bicep-standards.md:86 requires a deploy script to overlay onto the hydrated parameter
    set only what it computes at runtime. Re-asserting a static value makes the parameter file
    inert for that key: the file supplies a value, the script overwrites it with a constant, and
    the deployment silently uses the constant.

    Lab 3.3 did exactly that for two keys, and because its parameter files DO vary the other
    resource names, a -Environment prod run produced prod-named container resources inside the
    dev resource group. Nothing failed; the wrong thing deployed successfully.

    This rule is static by design. Compiling a .bicepparam needs `az bicep`, which
    .github/workflows/lint.yml installs only in the Bicep job - the Pester job has Pester and
    PSScriptAnalyzer and nothing else. A test that shelled out to `az` would pass locally and
    fail in CI. The parameter files' own contents are already validated there by the
    build-params loop; what needs guarding here is the script's behaviour.

    SCOPE, so nobody reads this suite as broader than its name. It is a regression guard over
    one script and two named keys, not a general overlay policy: which keys a script legitimately
    computes is not decidable from the AST. The predicate also hardcodes the variable name
    `params`, so a lab hydrating into `$deploymentParams` - as lab 4.1 does - is outside it
    entirely. Widening means adding cases and generalising that name, deliberately.

.EXAMPLE
    Invoke-Pester -Path .\tests\Overlay-Policy.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Key', Justification = 'False positive: captured by GetNewClosure into the overlay predicate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'OverlayCases', Justification = 'False positive: consumed by -ForEach on the It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

    $Lab33Deploy = Join-Path (Get-LabScriptRoot) 'module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1'

    # One case per key the script must leave to the parameter file. Both values live in
    # prod.bicepparam and platform.bicepparam, and in main.bicep's defaults for dev.
    $OverlayCases = @(
        @{ lab = '3.3-containers'; path = $Lab33Deploy; key = 'parResourceGroupName'; default = 'main.bicep:22' }
        @{ lab = '3.3-containers'; path = $Lab33Deploy; key = 'parAcrName';           default = 'main.bicep:34' }
    )
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'ScriptAst.psm1') -Force

    function Get-ParamsOverlay {
        # Assignments onto the hydrated parameter hashtable for one key.
        #
        # Both notations are matched - $params.parAcrName = ... and $params['parAcrName'] = ...
        # even though the script only uses the first. Matching one would let a future edit
        # switch notation and escape the rule without anything failing, which is the silent
        # kind of regression this suite exists to catch.
        param($Ast, [string]$Key)

        $isOverlay = {
            param($node)
            $left = $node.Left
            if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) {
                return $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                       $left.Expression.VariablePath.UserPath -eq 'params' -and
                       $left.Member.Value -eq $Key
            }
            if ($left -is [System.Management.Automation.Language.IndexExpressionAst]) {
                return $left.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                       $left.Target.VariablePath.UserPath -eq 'params' -and
                       $left.Index.Value -eq $Key
            }
            $false
        }.GetNewClosure()

        Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.AssignmentStatementAst]) -Where $isOverlay
    }
}

Describe 'Lab 3.3 leaves its parameter file authoritative for two keys' {
    It "lab <lab> leaves `$params.<key> to the parameter file" -ForEach $OverlayCases {
        $found = @(Get-ParamsOverlay -Ast (Get-ScriptAst -Path $path) -Key $key)
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "the parameter file and $default already supply $key; overwriting it with a script constant makes the file inert for that key and deploys the wrong resource under -Environment prod or platform. Lab $lab assigns it at line(s) $lines."
    }
}
